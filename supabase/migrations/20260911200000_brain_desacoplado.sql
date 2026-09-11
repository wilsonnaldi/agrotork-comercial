-- ============================================================
-- BRAIN — modo DESACOPLADO: as pontes nascem desligadas
--
-- Decisão de arquitetura tomada no GO condicionado de 11/09/2026: no
-- primeiro deploy em produção, NENHUM processamento do BRAIN acontece
-- dentro da transação de orçamento ou de pedido.
--
-- Os três gatilhos continuam EXISTINDO — o código está aplicado,
-- revisado e testado — mas ficam `DISABLE`. A sincronização ERP → BRAIN
-- passa a ser periódica:
--
--   ERP confirma orçamento/pedido
--     → a transação comercial termina (sem nada do BRAIN dentro)
--     → pg_cron chama brain.reconciliar_erp()
--     → divergencias_erp() acha o que falta
--     → reconciliar_erp() corrige
--     → o BRAIN recebe evento, vínculo e estágio
--     → a execução seguinte devolve relatório vazio
--
-- O preço é latência: o BRAIN sabe da venda no minuto seguinte, não no
-- instante. O ganho é que o risco residual do `statement_timeout` — o
-- único que sobrava depois de 20260911190000 — cai a ZERO, porque não há
-- mais código do BRAIN dentro da transação comercial.
--
-- ── COMO RELIGAR, quando for a hora ─────────────────────────
-- Não é editando este arquivo. É uma migration nova, com
-- `alter table ... enable trigger`, depois de a reconciliação periódica
-- ter rodado tempo suficiente para se confiar nela. Até lá, um banco
-- montado do Git reproduz produção: pontes desligadas.
-- ============================================================

alter table public.quotes disable trigger trg_brain_quotes;
alter table public.orders disable trigger trg_brain_orders;
alter table public.orders disable trigger trg_brain_orders_created;

-- ── A reconciliação precisa ser alcançável pelo pg_cron ─────
-- `is_admin()` responde pelo JWT, e o pg_cron não tem JWT nenhum: roda
-- como `postgres`, sem `auth.uid()`. `brain.is_privileged()` já sabe
-- distinguir isso — ela é verdadeira para administrador, para o marcador
-- interno e para papel de confiança sem JWT (postgres, service_role), e
-- FALSA para `anon` e para vendedor autenticado.
--
-- Trocar `is_admin()` por `is_privileged()` nas duas funções é o que
-- deixa o cron entrar sem abrir nada para quem não deve.

create or replace function brain.divergencias_erp()
returns table (
  tipo          text,
  entidade      text,
  id            uuid,
  numero        text,
  situacao      text,
  detalhe       text
)
language sql stable security definer set search_path = '' as $$
  with permitido as (select brain.is_privileged() as pode),

  ev_quote as (
    select 'evento_ausente'::text, 'quote'::text, q.id, q.number::text, q.status::text,
           'nenhum evento do ERP com status ' || q.status::text
      from public.quotes q, permitido p
     where p.pode and q.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'quote_id' = q.id::text
                          and e.payload ->> 'status'   = q.status::text)
  ),
  ev_order as (
    select 'evento_ausente'::text, 'order'::text, o.id, o.number::text, o.status::text,
           'nenhum evento do ERP com status ' || o.status::text
      from public.orders o, permitido p
     where p.pode and o.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'order_id' = o.id::text
                          and e.payload ->> 'status'   = o.status::text)
  ),
  estagio as (
    select 'estagio_atrasado'::text, 'opportunity'::text, op.id, q.number::text, op.stage::text,
           'orcamento em ' || q.status::text || ' e oportunidade em ' || op.stage::text
      from brain.opportunities op
      join public.quotes q on q.id = op.quote_id, permitido p
     where p.pode and q.deleted_at is null
       and op.stage not in ('won', 'lost')
       and ((q.status = 'approved' and op.stage in ('prospecting', 'qualified', 'proposal'))
         or (q.status = 'sent'     and op.stage in ('prospecting', 'qualified')))
  ),
  nao_ganha as (
    select 'venda_nao_ganha'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido em ' || o.status::text || ' e oportunidade em ' || op.stage::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id)), permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.stage <> 'won' and op.stage <> 'lost'
  ),
  desfeita as (
    select 'venda_desfeita'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido cancelado e oportunidade ainda em won'
      from public.orders o
      join brain.opportunities op on op.order_id = o.id, permitido p
     where p.pode and o.status = 'cancelled' and op.stage = 'won'
  ),
  sem_vinculo as (
    select 'pedido_nao_ligado'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'oportunidade sem order_id apontando para o pedido'
      from public.orders o
      join brain.opportunities op on op.quote_id = o.quote_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.order_id is null and op.stage <> 'lost'
  ),
  lead_parado as (
    select 'lead_nao_convertido'::text, 'lead'::text, l.id, o.number::text, l.status::text,
           'pedido vivo e lead em ' || l.status::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
      join brain.leads l on l.id = op.lead_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and l.status <> 'converted' and l.status <> 'lost'
       and op.stage <> 'lost'
  )

  select * from ev_quote
  union all select * from ev_order
  union all select * from estagio
  union all select * from nao_ganha
  union all select * from desfeita
  union all select * from sem_vinculo
  union all select * from lead_parado;
$$;

-- Só a porta de entrada muda; o corpo é o mesmo de 20260911170000.
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
        case when r.situacao = 'draft' then 'quote.created' else 'quote.' || r.situacao end,
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reconciliacao:' || r.situacao,
        (select q.updated_at from public.quotes q where q.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        (select q.customer_id from public.quotes q where q.id = r.id),
        (select op.id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        case when r.situacao = 'draft' then 'order.created' else 'order.' || r.situacao end,
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reconciliacao:' || r.situacao,
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

revoke execute on function brain.divergencias_erp()          from public, anon;
revoke execute on function brain.reconciliar_erp(integer)    from public, anon;
grant  execute on function brain.divergencias_erp()          to authenticated, service_role;
grant  execute on function brain.reconciliar_erp(integer)    to authenticated, service_role;

-- ── O que o pg_cron chama ───────────────────────────────────
-- Uma função sem argumento, que engole a própria falha: se a
-- reconciliação quebrar, o job NÃO pode ficar em estado de erro
-- permanente nem poluir o log a cada minuto. Ela registra o problema
-- como `warning` e devolve o total corrigido (ou -1 quando falhou), e a
-- execução seguinte tenta de novo.
--
-- Isto NÃO é a ponte: roda na sessão do pg_cron, fora de qualquer
-- transação comercial. Uma falha aqui não tem como tocar num orçamento.

create or replace function brain.reconciliar_erp_periodico()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_total integer := 0; r record;
begin
  for r in select * from brain.reconciliar_erp(500) loop
    v_total := v_total + r.corrigidas;
  end loop;
  return v_total;
exception when others then
  raise warning '[brain-reconciliacao] falhou: % (%)', sqlerrm, sqlstate;
  return -1;
end;
$$;

revoke execute on function brain.reconciliar_erp_periodico() from public, anon, authenticated;
grant  execute on function brain.reconciliar_erp_periodico() to service_role;

comment on function brain.reconciliar_erp_periodico() is
  'Ponto de entrada do pg_cron. Roda fora de qualquer transacao comercial; se falhar, registra warning e devolve -1, e o minuto seguinte tenta de novo.';

-- ── Quem está ligado, para conferir de fora ─────────────────
create or replace function brain.estado_das_pontes()
returns table (gatilho text, tabela text, habilitado boolean, estado "char")
language sql stable security definer set search_path = '' as $$
  select t.tgname::text, c.relname::text, t.tgenabled <> 'D', t.tgenabled
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
   where t.tgname in ('trg_brain_quotes', 'trg_brain_orders', 'trg_brain_orders_created');
$$;

revoke execute on function brain.estado_das_pontes() from public, anon;
grant  execute on function brain.estado_das_pontes() to authenticated, service_role;

comment on function brain.estado_das_pontes() is
  'Estado dos tres gatilhos da ponte ERP -> BRAIN. No modo desacoplado, os tres tem de vir habilitado = false.';
