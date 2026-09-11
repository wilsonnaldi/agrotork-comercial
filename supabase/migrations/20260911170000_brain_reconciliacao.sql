-- ============================================================
-- BRAIN — reconciliação de verdade: evento E estado comercial
--
-- O defeito: `brain.repor_eventos_erp()` republicava o evento que a
-- ponte perdeu e parava aí. Mas a ponte não publica só evento — ela
-- também move o estágio da oportunidade, marca a venda como ganha e
-- converte o lead. Quando ela falha, TUDO isso deixa de acontecer, e
-- repor só o evento devolvia um barramento arrumado em cima de um CRM
-- errado.
--
-- Pior: "zero eventos faltantes" virava critério de sucesso, e era um
-- critério que podia estar satisfeito com a oportunidade parada em
-- `prospecting` e o lead nunca convertido.
--
-- ── O QUE ENTRA ─────────────────────────────────────────────
--
-- `brain.divergencias_erp()` — o relatório. Uma linha por desacordo
-- entre a venda no ERP e o que o BRAIN sabe dela. Seis tipos:
--
--   evento_ausente        o estado atual da venda nunca foi publicado
--   estagio_atrasado      orçamento enviado/aprovado e a oportunidade
--                         ficou para trás
--   venda_nao_ganha       pedido vivo e a oportunidade não está `won`
--   venda_desfeita        pedido cancelado e a oportunidade ainda `won`
--   pedido_nao_ligado     pedido vivo e a oportunidade sem `order_id`
--   lead_nao_convertido   pedido vivo e o lead do negócio não convertido
--
-- `brain.reconciliar_erp()` — conserta o que pode e devolve a contagem
-- por tipo. É ela que passa a ser chamada; `repor_eventos_erp()` fica
-- como apelido, para não quebrar quem já a conhece.
--
-- ── O QUE ELA NÃO ATROPELA ──────────────────────────────────
--
-- · Oportunidade em `lost` fica em `lost`. Alguém decidiu isso depois, e
--   a reconciliação não desfaz decisão humana — é a mesma regra que a
--   ponte já segue (`stage not in ('won','lost')`).
-- · Pedido cancelado devolve a oportunidade para `negotiation`, nunca
--   para `lost`: quem perde a venda decide, não o script.
-- · Lead convertido continua convertido mesmo se o pedido for cancelado.
--   É a regra da ponte, escrita lá: o cliente existe; o que não existe
--   mais é esta venda.
-- · Estágio NUNCA anda para trás por conta do orçamento. Se a
--   oportunidade já está em `negotiation` e o orçamento só foi enviado,
--   não se rebaixa para `proposal`.
--
-- ── IDEMPOTÊNCIA ────────────────────────────────────────────
--
-- Rodar duas vezes dá o mesmo resultado, e a segunda não faz nada: toda
-- escrita é condicionada ao estado errado. A suíte mede isso pelo md5
-- do estado do CRM antes e depois da segunda execução (RC7).
-- ============================================================

-- ── 1. O relatório de divergências ──────────────────────────

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
  with permitido as (select (select public.is_admin()) as pode),

  -- Orçamento cujo estado atual nunca foi publicado.
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

  -- Orçamento andou e a oportunidade ficou para trás.
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

  -- Pedido vivo e a oportunidade não ganhou.
  nao_ganha as (
    select 'venda_nao_ganha'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido em ' || o.status::text || ' e oportunidade em ' || op.stage::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id)), permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.stage <> 'won' and op.stage <> 'lost'
  ),

  -- Pedido cancelado e a oportunidade continua ganha.
  desfeita as (
    select 'venda_desfeita'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido cancelado e oportunidade ainda em won'
      from public.orders o
      join brain.opportunities op on op.order_id = o.id, permitido p
     where p.pode and o.status = 'cancelled' and op.stage = 'won'
  ),

  -- Pedido vivo, oportunidade ganha, mas sem o vínculo.
  sem_vinculo as (
    select 'pedido_nao_ligado'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'oportunidade sem order_id apontando para o pedido'
      from public.orders o
      join brain.opportunities op on op.quote_id = o.quote_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.order_id is null and op.stage <> 'lost'
  ),

  -- Pedido vivo e o lead do negócio não foi convertido.
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

revoke execute on function brain.divergencias_erp() from public, anon;
grant  execute on function brain.divergencias_erp() to authenticated, service_role;

comment on function brain.divergencias_erp() is
  'Uma linha por desacordo entre a venda no ERP e o que o BRAIN sabe dela. Vazio e o criterio de sucesso da reconciliacao — "zero eventos faltantes" sozinho nao era.';

-- A função antiga continua existindo e agora é uma vista estreita do
-- relatório novo: só os eventos ausentes.
create or replace function brain.erp_events_faltando()
returns table (
  entidade      text,
  id            uuid,
  numero        text,
  status        text,
  atualizado_em timestamptz
)
language sql stable security definer set search_path = '' as $$
  select d.entidade, d.id, d.numero, d.situacao,
         coalesce((select q.updated_at from public.quotes q where q.id = d.id),
                  (select o.updated_at from public.orders o where o.id = d.id))
    from brain.divergencias_erp() d
   where d.tipo = 'evento_ausente'
   order by 5 desc nulls last;
$$;

revoke execute on function brain.erp_events_faltando() from public, anon;
grant  execute on function brain.erp_events_faltando() to authenticated, service_role;

-- ── 2. A reconciliação ──────────────────────────────────────

create or replace function brain.reconciliar_erp(p_limite integer default 500)
returns table (
  tipo       text,
  corrigidas integer
)
language plpgsql security definer set search_path = '' as $$
declare
  r          record;
  v_eventos  int := 0;
  v_estagio  int := 0;
  v_ganhas   int := 0;
  v_desfeitas int := 0;
  v_ligadas  int := 0;
  v_leads    int := 0;
  v_n        int;
begin
  if not (select public.is_admin()) then
    raise exception 'Somente administrador reconcilia o BRAIN com o ERP'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  -- ── 2.1 Pedido cancelado desfaz a venda ganha ─────────────
  -- Vem PRIMEIRO: assim um pedido cancelado nunca é "ganho" por um passo
  -- posterior e depois desfeito — a ordem evita o vaivém.
  update brain.opportunities op
     set stage = 'negotiation'
    from public.orders o
   where op.order_id = o.id and o.status = 'cancelled' and op.stage = 'won';
  get diagnostics v_desfeitas = row_count;

  -- ── 2.2 Pedido vivo: liga, ganha e converte ───────────────
  for r in
    select o.id as pedido, o.customer_id, op.id as oportunidade, op.lead_id
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
     where o.deleted_at is null and o.status <> 'cancelled' and op.stage <> 'lost'
     order by o.created_at
     limit p_limite
  loop
    update brain.opportunities
       set order_id = r.pedido
     where id = r.oportunidade and order_id is null;
    get diagnostics v_n = row_count;  v_ligadas := v_ligadas + v_n;

    update brain.opportunities
       set stage = 'won',
           customer_id = coalesce(customer_id, r.customer_id)
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

  -- ── 2.3 Estágio atrasado pelo orçamento ───────────────────
  -- Só avança. `greatest` não existe para enum, então são dois UPDATEs
  -- com a condição escrita por extenso — e a condição é justamente a
  -- que impede voltar atrás.
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

  -- ── 2.4 Os eventos que faltaram ───────────────────────────
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

revoke execute on function brain.reconciliar_erp(integer) from public, anon;
grant  execute on function brain.reconciliar_erp(integer) to authenticated, service_role;

comment on function brain.reconciliar_erp(integer) is
  'Poe o BRAIN de acordo com o ERP: evento, estagio, venda ganha, venda desfeita, vinculo do pedido e conversao do lead. Nao atropela decisao humana (lost fica lost) e rodar duas vezes nao muda nada.';

-- `repor_eventos_erp()` continua existindo e agora chama a reconciliação
-- inteira — quem só repunha evento passa a arrumar o CRM junto.
create or replace function brain.repor_eventos_erp(p_limite integer default 500)
returns integer language sql security definer set search_path = '' as $$
  select coalesce(sum(corrigidas), 0)::integer from brain.reconciliar_erp(p_limite);
$$;

revoke execute on function brain.repor_eventos_erp(integer) from public, anon;
grant  execute on function brain.repor_eventos_erp(integer) to authenticated, service_role;

comment on function brain.repor_eventos_erp(integer) is
  'Apelido de brain.reconciliar_erp(): devolve o total de correcoes. Mantido para nao quebrar quem ja o chamava.';

-- Índice do caminho que a reconciliação percorre.
create index if not exists idx_opportunities_quote_stage
  on brain.opportunities (quote_id, stage) where quote_id is not null;
