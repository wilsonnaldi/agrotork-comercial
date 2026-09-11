-- ════════════════════════════════════════════════════════════
-- BRAIN — fidelidade do nome do evento reposto
-- ════════════════════════════════════════════════════════════
-- O ensaio do deploy em modo desacoplado pegou uma divergência REAL
-- entre os dois caminhos que publicam o mesmo fato:
--
--   ponte (síncrona)  INSERT em `public.orders` → `order.created`
--   reconciliação     pedido novo               → `order.confirmed`
--
-- O nome vinha do status, e o status de nascimento de um pedido é
-- `confirmed` — `draft` nem existe em `public.order_status`, é status
-- de orçamento. Resultado: `order.created` NUNCA sairia pela
-- reconciliação. Com as pontes desligadas em produção, o BRAIN passaria
-- a receber um histórico com nomes diferentes dos que a ponte produz, e
-- quem for consumir esses eventos na Fase 2 leria dois vocabulários
-- para o mesmo fato.
--
-- A regra passa a ser a da ponte, e não a do status:
--
--   entidade SEM nenhum evento do ERP  →  `X.created`   (é o nascimento)
--   entidade COM evento do ERP         →  `X.<status>`  (é uma mudança)
--
-- Um pedido nascido e ainda `confirmed` recebe `order.created`, igual à
-- ponte. Um pedido que já tem evento e foi para `invoiced` recebe
-- `order.invoiced`, igual à ponte. Um orçamento que nasceu e já foi
-- para `sent` sem nenhum evento recebe `quote.created` carregando o
-- estado atual: o nascimento é o fato mais antigo que faltou, e o
-- `payload` diz a verdade de agora. O evento sai marcado com
-- `reconciliado_em` no metadado — é uma reconstrução, e está dito.
--
-- Idempotência: a chave de deduplicação passa a carregar o nome do
-- evento além do status, então rodar de novo não duplica nada, e o
-- relatório seguinte volta vazio porque `divergencias_erp()` compara
-- `payload ->> 'status'`, que o evento reposto carrega correto nos dois
-- casos.
--
-- Não mexe em ponte, não religa nada, não toca em dado comercial.

create or replace function brain.nome_do_evento_erp(
  p_entidade text, p_id uuid, p_situacao text)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from brain.events e
                  where e.source = 'erp'
                    and e.payload ->> (p_entidade || '_id') = p_id::text)
    then p_entidade || '.' || p_situacao
    else p_entidade || '.created'
  end;
$$;

revoke execute on function brain.nome_do_evento_erp(text, uuid, text) from public, anon;
grant  execute on function brain.nome_do_evento_erp(text, uuid, text) to authenticated, service_role;

comment on function brain.nome_do_evento_erp(text, uuid, text) is
  'Nome do evento que a ponte teria publicado: X.created quando a entidade nao tem nenhum evento do ERP (e o nascimento), X.<status> quando ja tem.';

create or replace function brain.reconciliar_erp(p_limite integer default 500)
returns table (
  tipo       text,
  corrigidas integer
)
language plpgsql security definer set search_path = '' as $$
declare
  r           record;
  v_eventos   int := 0;
  v_estagio   int := 0;
  v_ganhas    int := 0;
  v_desfeitas int := 0;
  v_ligadas   int := 0;
  v_leads     int := 0;
  v_n         int;
begin
  if not brain.is_privileged() then
    raise exception 'Somente administrador (ou o processo periodico) reconcilia o BRAIN com o ERP'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  update brain.opportunities op
     set stage = 'negotiation'
    from public.orders o
   where op.order_id = o.id and o.status = 'cancelled' and op.stage = 'won';
  get diagnostics v_desfeitas = row_count;

  for r in
    select o.id as pedido, o.customer_id, op.id as oportunidade, op.lead_id
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
     where o.deleted_at is null and o.status <> 'cancelled' and op.stage <> 'lost'
     order by o.created_at
     limit p_limite
  loop
    update brain.opportunities set order_id = r.pedido
     where id = r.oportunidade and order_id is null;
    get diagnostics v_n = row_count;  v_ligadas := v_ligadas + v_n;

    update brain.opportunities
       set stage = 'won', customer_id = coalesce(customer_id, r.customer_id)
     where id = r.oportunidade and stage <> 'won';
    get diagnostics v_n = row_count;  v_ganhas := v_ganhas + v_n;

    if r.lead_id is not null then
      update brain.leads
         set status = 'converted',
             converted_at = coalesce(converted_at, now()),
             customer_id = coalesce(customer_id, r.customer_id)
       where id = r.lead_id and status not in ('converted', 'lost');
      get diagnostics v_n = row_count;  v_leads := v_leads + v_n;
    end if;
  end loop;

  update brain.opportunities op
     set stage = 'negotiation'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'approved'
     and op.stage in ('prospecting', 'qualified', 'proposal');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  update brain.opportunities op
     set stage = 'proposal'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'sent'
     and op.stage in ('prospecting', 'qualified');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  for r in
    select d.entidade, d.id, d.situacao
      from brain.divergencias_erp() d
     where d.tipo = 'evento_ausente'
     limit p_limite
  loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        brain.nome_do_evento_erp('quote', r.id, r.situacao),
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reconciliacao:'
          || brain.nome_do_evento_erp('quote', r.id, r.situacao) || ':' || r.situacao,
        (select q.updated_at from public.quotes q where q.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        (select q.customer_id from public.quotes q where q.id = r.id),
        (select op.id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        brain.nome_do_evento_erp('order', r.id, r.situacao),
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reconciliacao:'
          || brain.nome_do_evento_erp('order', r.id, r.situacao) || ':' || r.situacao,
        (select o.updated_at from public.orders o where o.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        (select o.customer_id from public.orders o where o.id = r.id),
        (select op.id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    end if;
    v_eventos := v_eventos + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);

  return query
    select * from (values
      ('evento_ausente',      v_eventos),
      ('estagio_atrasado',    v_estagio),
      ('venda_nao_ganha',     v_ganhas),
      ('venda_desfeita',      v_desfeitas),
      ('pedido_nao_ligado',   v_ligadas),
      ('lead_nao_convertido', v_leads)
    ) as t(tipo, corrigidas);
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.reconciliar_erp(integer) from public, anon;
grant  execute on function brain.reconciliar_erp(integer) to authenticated, service_role;

comment on function brain.reconciliar_erp(integer) is
  'Poe o BRAIN de acordo com o ERP: evento (com o nome que a ponte teria dado), estagio, venda ganha, venda desfeita, vinculo do pedido e conversao do lead. Nao atropela decisao humana (lost fica lost) e rodar duas vezes nao muda nada.';
