-- ============================================================
-- AGROTORK BRAIN — Fase 1 (migration 20260910120000).
--
-- Os seis cenários de aceitação, mais segurança e imutabilidade:
--   BR1  novo interessado do Instagram: evento → lead → interação →
--        oportunidade → vendedor → tarefa
--   BR2  contato que JÁ é cliente do ERP é reconhecido, sem duplicar
--   BR3  o mesmo evento/interação/contato chegando duas vezes vira UM
--   BR4  lead → oportunidade → orçamento (public.quotes)
--   BR5  orçamento vira pedido: oportunidade ganha, lead convertido
--   BR6  jornada cronológica numa consulta só
--   BR7  RLS: vendedor não vê lead alheio, pega da fila, anon não entra
--   BR8  evento é imutável
--   BR9  auditoria de alteração sem fantasma; verbos próprios
--   BR10 higiene: RLS em tudo, search_path vazio, anon sem privilégio
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('25252525-0000-4000-8000-000000002501','brain.admin@teste.local','{"full_name":"Admin Brain","role":"admin"}'),
 ('25252525-0000-4000-8000-000000002502','brain.vend.a@teste.local','{"full_name":"Vendedor A","role":"salesperson"}'),
 ('25252525-0000-4000-8000-000000002503','brain.vend.b@teste.local','{"full_name":"Vendedor B","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '25252525-0000-4000-8000-000000002501';

-- Cliente que JÁ existe no ERP (para o cenário 2).
insert into public.customers (name, person_type, whatsapp, email, city, state, created_by)
values ('Fazenda Santa Rita', 'company', '(43) 99999-0000', 'compras@santarita.com.br', 'Londrina', 'PR',
        '25252525-0000-4000-8000-000000002501');

insert into public.products (code, name, unit_id, sale_price, is_active)
select 'BR-AGRAS', 'DJI Agras T50', u.id, 250000, true from public.units u where u.code = 'UN';

-- ── Contexto: VENDEDOR A ────────────────────────────────────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002502', false);

-- ── BR1: Instagram → evento → lead → interação → oportunidade → tarefa ──
do $$
declare
  v_ev record; v_lead record; v_int record; v_opp uuid; v_task uuid;
  v_attr text; v_ids int; v_owner uuid;
begin
  select * into v_ev from brain.ingest_event(
    'instagram.message_received', 'instagram',
    '{"text":"Quanto custa o Agras T50?","username":"joao_agro"}'::jsonb,
    'ig-msg-1', now() - interval '10 minutes', 'instagram');

  select * into v_lead from brain.find_or_create_lead(
    'João da Silva', '(43) 98888-7777', null, '@joao_agro', 'instagram', 'DM do post Agras',
    null, 'Cambé', 'pr',
    '{"source":"instagram","medium":"social","campaign":"agras-setembro","content":"post-12"}'::jsonb);

  select * into v_int from brain.log_interaction(
    v_lead.lead_id, 'Perguntou o preço do Agras T50', 'instagram', 'message', 'inbound',
    now() - interval '10 minutes', 'instagram', 'ig-msg-1', null, v_ev.event_id);

  insert into brain.opportunities (lead_id, owner_id, product_id, title, estimated_value, temperature, channel_key)
  select v_lead.lead_id, '25252525-0000-4000-8000-000000002502', p.id, 'Agras T50 para 300 ha', 250000, 'hot', 'instagram'
    from public.products p where p.code = 'BR-AGRAS'
  returning id into v_opp;

  insert into brain.tasks (lead_id, opportunity_id, assignee_id, kind, title, due_at, priority)
  values (v_lead.lead_id, v_opp, '25252525-0000-4000-8000-000000002502', 'call', 'Ligar para o João', now() + interval '1 day', 'high')
  returning id into v_task;

  select a.campaign into v_attr from brain.leads l join brain.attributions a on a.id = l.first_attribution_id where l.id = v_lead.lead_id;
  select count(*) into v_ids from brain.identities where lead_id = v_lead.lead_id;
  select owner_id into v_owner from brain.leads where id = v_lead.lead_id;

  if not v_ev.duplicate and v_lead.created and v_lead.customer_id is null and not v_int.duplicate
     and v_opp is not null and v_task is not null and v_attr = 'agras-setembro' and v_ids = 3
     and v_owner = '25252525-0000-4000-8000-000000002502'
    then raise notice 'BR1) OK: evento, lead (campanha %), % identidades, interacao, oportunidade e tarefa — dono = vendedor A', v_attr, v_ids;
    else raise notice 'BR1) FALHA: ev_dup=% created=% cust=% int_dup=% opp=% task=% attr=% ids=% owner=%',
      v_ev.duplicate, v_lead.created, v_lead.customer_id, v_int.duplicate, v_opp, v_task, v_attr, v_ids, v_owner; end if;
end $$;

-- ── BR2: quem já é cliente é reconhecido, sem duplicar ──────
do $$
declare v1 record; v2 record; v_cust uuid; n_before int; n_after int; v_lead_cust uuid;
begin
  select id into v_cust from public.customers where name = 'Fazenda Santa Rita';
  select count(*) into n_before from public.customers;

  -- Chega pelo site com o WhatsApp que o ERP já conhece (grafia diferente).
  select * into v1 from brain.find_or_create_lead('Contato do site', '43 99999 0000', null, null, 'website', 'formulario-agras');
  -- Volta pelo WhatsApp: mesma pessoa, mesmo lead.
  select * into v2 from brain.find_or_create_lead('Santa Rita (whats)', '+55 (43) 99999-0000', null, null, 'whatsapp');
  select count(*) into n_after from public.customers;
  select customer_id into v_lead_cust from brain.leads where id = v1.lead_id;

  if v1.created and v1.customer_id = v_cust and v1.matched_by = 'customer_phone'
     and not v2.created and v2.lead_id = v1.lead_id and v2.matched_by = 'identity'
     and n_before = n_after and v_lead_cust = v_cust
    then raise notice 'BR2) OK: lead ligado ao cliente existente (%); segundo contato caiu no mesmo lead; clientes continuam %', v1.matched_by, n_after;
    else raise notice 'BR2) FALHA: v1=(%,%,%) v2=(%,%,%) clientes %→%', v1.created, v1.customer_id, v1.matched_by, v2.created, v2.lead_id = v1.lead_id, v2.matched_by, n_before, n_after; end if;
end $$;

-- ── BR3: o mesmo evento duas vezes vira um ──────────────────
do $$
declare v_ev record; v_int record; v_lead record; v_joao uuid; n_ev int; n_int int; n_leads int;
begin
  select id into v_joao from brain.leads where name = 'João da Silva';

  select * into v_ev from brain.ingest_event('instagram.message_received', 'instagram',
    '{"text":"Quanto custa o Agras T50?"}'::jsonb, 'ig-msg-1', now(), 'instagram');
  select count(*) into n_ev from brain.events where source = 'instagram' and external_id = 'ig-msg-1';

  select * into v_int from brain.log_interaction(v_joao, 'Perguntou de novo', 'instagram', 'message', 'inbound',
    now(), 'instagram', 'ig-msg-1');
  select count(*) into n_int from brain.interactions where source = 'instagram' and external_id = 'ig-msg-1';

  -- Mesma pessoa pelo Instagram, com grafia diferente.
  select * into v_lead from brain.find_or_create_lead('J. Silva', null, null, 'JOAO_AGRO', 'instagram');
  select count(*) into n_leads from brain.leads where name in ('João da Silva', 'J. Silva');

  if v_ev.duplicate and n_ev = 1 and v_int.duplicate and n_int = 1
     and not v_lead.created and v_lead.lead_id = v_joao and n_leads = 1
    then raise notice 'BR3) OK: evento repetido = 1, interacao repetida = 1, @JOAO_AGRO caiu no mesmo lead';
    else raise notice 'BR3) FALHA: ev_dup=% n_ev=% int_dup=% n_int=% lead_created=% mesmo=% leads=%',
      v_ev.duplicate, n_ev, v_int.duplicate, n_int, v_lead.created, v_lead.lead_id = v_joao, n_leads; end if;
end $$;

-- ── BR4: lead → oportunidade → orçamento ────────────────────
do $$
declare v_joao uuid; v_cust uuid; v_q uuid; v_opp uuid; v_ev_lead uuid; v_stage text; n_ev int;
begin
  select id into v_joao from brain.leads where name = 'João da Silva';

  -- Para orçar, o ERP precisa do cliente: nasce aqui e o lead aponta para ele.
  insert into public.customers (name, person_type, whatsapp, city, state, created_by)
  values ('João da Silva', 'individual', '43988887777', 'Cambé', 'PR', '25252525-0000-4000-8000-000000002502')
  returning id into v_cust;
  update brain.leads set customer_id = v_cust where id = v_joao;

  insert into public.quotes (customer_id, owner_id, created_by)
  values (v_cust, '25252525-0000-4000-8000-000000002502', '25252525-0000-4000-8000-000000002502')
  returning id into v_q;
  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
  select v_q, p.id, p.name, p.code, 1, 250000, 1 from public.products p where p.code = 'BR-AGRAS';

  -- A oportunidade passa a apontar para o orçamento.
  select id into v_opp from brain.opportunities where lead_id = v_joao;
  update brain.opportunities set quote_id = v_q where id = v_opp;

  update public.quotes set status = 'sent' where id = v_q;
  update public.quotes set status = 'approved' where id = v_q;

  select lead_id into v_ev_lead from brain.events where event_name = 'quote.created' and (payload->>'quote_id')::uuid = v_q;
  select count(*) into n_ev from brain.events where source = 'erp' and (payload->>'quote_id')::uuid = v_q;
  select stage::text into v_stage from brain.opportunities where id = v_opp;

  if v_ev_lead = v_joao and n_ev = 3 and v_stage = 'negotiation'
    then raise notice 'BR4) OK: quote.created/sent/approved no barramento com o lead; oportunidade em %', v_stage;
    else raise notice 'BR4) FALHA: ev_lead=% (esperado %) eventos=% stage=%', v_ev_lead, v_joao, n_ev, v_stage; end if;
end $$;

-- ── BR5: orçamento vira pedido → oportunidade ganha, lead convertido ──
do $$
declare v_joao uuid; v_q uuid; v_o uuid; r_opp record; r_lead record; v_ev_opp uuid;
begin
  select id into v_joao from brain.leads where name = 'João da Silva';
  select quote_id into v_q from brain.opportunities where lead_id = v_joao;

  v_o := public.create_order_from_quote(v_q);

  select stage::text as stage, order_id, closed_at into r_opp from brain.opportunities where lead_id = v_joao;
  select status::text as status, converted_at, customer_id into r_lead from brain.leads where id = v_joao;
  select opportunity_id into v_ev_opp from brain.events where event_name = 'order.created' and (payload->>'order_id')::uuid = v_o;

  if r_opp.stage = 'won' and r_opp.order_id = v_o and r_opp.closed_at is not null
     and r_lead.status = 'converted' and r_lead.converted_at is not null and r_lead.customer_id is not null
     and v_ev_opp is not null
    then raise notice 'BR5) OK: lead → oportunidade (ganha) → orcamento → pedido; lead convertido e ligado ao cliente';
    else raise notice 'BR5) FALHA: opp=(%,%,%) lead=(%,%,%) ev_opp=%',
      r_opp.stage, r_opp.order_id = v_o, r_opp.closed_at, r_lead.status, r_lead.converted_at, r_lead.customer_id, v_ev_opp; end if;
end $$;

-- ── BR6: a jornada, em ordem ────────────────────────────────
do $$
declare v_joao uuid; v_seq text; n int; v_first text; v_last text;
begin
  select id into v_joao from brain.leads where name = 'João da Silva';
  select string_agg(kind, ' → ' order by occurred_at, kind), count(*),
         (array_agg(kind order by occurred_at, kind))[1],
         (array_agg(kind order by occurred_at desc, kind desc))[1]
    into v_seq, n, v_first, v_last
    from brain.journey_entries where lead_id = v_joao;
  if n >= 8 and v_first = 'event' and v_last in ('event', 'order')
     and v_seq like '%opportunity%' and v_seq like '%quote%' and v_seq like '%order%'
    then raise notice 'BR6) OK: % entradas — %', n, v_seq;
    else raise notice 'BR6) FALHA: % entradas, primeira=% ultima=% — %', n, v_first, v_last, v_seq; end if;
end $$;

-- ── BR7: RLS — vendedor B ───────────────────────────────────
reset role;
-- Um lead na fila (sem dono), criado pelo administrador.
insert into brain.leads (name, phone, channel_key, created_by)
values ('Lead da fila', '43977776666', 'phone', '25252525-0000-4000-8000-000000002501');

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002503', false);

do $$
declare n_leads int; n_alheio int; n_fila int; n_ev int; n_opp int; v_claim uuid; n_upd int;
begin
  select count(*) into n_leads from brain.leads;
  select count(*) into n_alheio from brain.leads where name = 'João da Silva';
  select count(*) into n_fila from brain.leads where name = 'Lead da fila';
  select count(*) into n_ev from brain.events where lead_id = (select id from brain.leads where name='João da Silva');
  select count(*) into n_opp from brain.opportunities;

  -- Pega o lead da fila para si.
  update brain.leads set owner_id = '25252525-0000-4000-8000-000000002503' where name = 'Lead da fila';
  get diagnostics n_upd = row_count;
  -- Tenta editar o lead do vendedor A (invisível: 0 linhas).
  update brain.leads set notes = 'invasao' where name = 'João da Silva';

  if n_alheio = 0 and n_fila = 1 and n_ev = 0 and n_opp = 0 and n_upd = 1
    then raise notice 'BR7) OK: vendedor B nao ve lead/oportunidade/evento do A; viu e pegou o lead da fila';
    else raise notice 'BR7) FALHA: leads=% alheio=% fila=% eventos=% opps=% claim=%', n_leads, n_alheio, n_fila, n_ev, n_opp, n_upd; end if;
end $$;

-- anon: nem USAGE no schema (conferido pelo catálogo, como postgres).
reset role;
do $$
declare v_usage boolean; v_sel boolean;
begin
  v_usage := has_schema_privilege('anon', 'brain', 'usage');
  v_sel   := has_table_privilege('anon', 'brain.leads', 'select');
  if not v_usage and not v_sel
    then raise notice 'BR7b) OK: anon sem USAGE no schema brain e sem SELECT em leads';
    else raise notice 'BR7b) FALHA: usage=% select=%', v_usage, v_sel; end if;
end $$;

-- ── BR8: evento imutável ────────────────────────────────────
do $$
declare v_id bigint; e1 text := '(sem erro)'; e2 text := '(sem erro)'; v_proc text;
begin
  select id into v_id from brain.events where external_id = 'ig-msg-1';
  begin
    update brain.events set payload = '{}'::jsonb where id = v_id;
  exception when others then e1 := left(sqlerrm, 40); end;
  begin
    delete from brain.events where id = v_id;
  exception when others then e2 := left(sqlerrm, 40); end;
  update brain.events set processing = 'processed', processed_at = now() where id = v_id;
  select processing::text into v_proc from brain.events where id = v_id;
  if e1 <> '(sem erro)' and e2 <> '(sem erro)' and v_proc = 'processed'
    then raise notice 'BR8) OK: payload e delete recusados (mesmo como postgres); processamento gravado';
    else raise notice 'BR8) FALHA: update=% delete=% processing=%', e1, e2, v_proc; end if;
end $$;

-- ── BR9: auditoria de alteração, sem fantasma ───────────────
do $$
declare n_fantasma int; v_verbos text; n_created int;
begin
  select count(*) into n_fantasma from public.audit_log
   where entity_type = 'lead' and operation = 'UPDATE'
     and changed_fields <@ array['first_touch_at', 'last_touch_at', 'score']::text[];
  select string_agg(distinct action, ', ' order by action) into v_verbos from public.audit_log
   where action in ('lead.created', 'lead.converted', 'lead.assigned', 'opportunity.created', 'opportunity.won', 'task.created');
  select count(*) into n_created from public.audit_log where action = 'lead.created';
  if n_fantasma = 0 and n_created = 3
     and v_verbos = 'lead.assigned, lead.converted, lead.created, opportunity.created, opportunity.won, task.created'
    then raise notice 'BR9) OK: zero lead.updated de toque; verbos: %', v_verbos;
    else raise notice 'BR9) FALHA: fantasmas=% created=% verbos=%', n_fantasma, n_created, v_verbos; end if;
end $$;

-- ── BR10: higiene ───────────────────────────────────────────
do $$
declare n_sem_rls int; n_sp int; n_anon int; n_tabelas int;
begin
  select count(*), count(*) filter (where not c.relrowsecurity) into n_tabelas, n_sem_rls
    from pg_class c where c.relnamespace = 'brain'::regnamespace and c.relkind = 'r';
  select count(*) into n_sp from pg_proc p
   where p.pronamespace = 'brain'::regnamespace
     and not (coalesce(p.proconfig, array[]::text[]) @> array['search_path=""']);
  select count(*) into n_anon from pg_class c
   where c.relnamespace = 'brain'::regnamespace and c.relkind in ('r', 'v')
     and has_table_privilege('anon', c.oid, 'select');
  if n_tabelas = 9 and n_sem_rls = 0 and n_sp = 0 and n_anon = 0
    then raise notice 'BR10) OK: % tabelas com RLS; toda funcao com search_path vazio; anon sem SELECT em nada', n_tabelas;
    else raise notice 'BR10) FALHA: tabelas=% sem_rls=% funcoes_sem_sp=% anon=%', n_tabelas, n_sem_rls, n_sp, n_anon; end if;
end $$;

reset role;
