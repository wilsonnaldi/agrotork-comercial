-- ============================================================
-- AGROTORK BRAIN — Fase 1 (migration 20260911130000).
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
-- A criação do pedido e a conferência ficam em transações SEPARADAS: o
-- evento `order.created` é adiado para o commit, de propósito (F5).
select public.create_order_from_quote(quote_id) as pedido
  from brain.opportunities where lead_id = (select id from brain.leads where name = 'João da Silva') \gset

do $$
declare v_joao uuid; v_o uuid; r_opp record; r_lead record; v_ev_opp uuid; v_ev_total numeric; v_total numeric;
begin
  select id into v_joao from brain.leads where name = 'João da Silva';
  select order_id into v_o from brain.opportunities where lead_id = v_joao;

  select stage::text as stage, order_id, closed_at into r_opp from brain.opportunities where lead_id = v_joao;
  select status::text as status, converted_at, customer_id into r_lead from brain.leads where id = v_joao;
  select opportunity_id, (payload->>'total')::numeric into v_ev_opp, v_ev_total
    from brain.events where event_name = 'order.created' and (payload->>'order_id')::uuid = v_o;
  select total into v_total from public.orders where id = v_o;

  if r_opp.stage = 'won' and r_opp.order_id is not null and r_opp.closed_at is not null
     and r_lead.status = 'converted' and r_lead.converted_at is not null and r_lead.customer_id is not null
     and v_ev_opp is not null and v_ev_total = v_total and v_total = 250000
    then raise notice 'BR5) OK: lead → oportunidade (ganha) → orcamento → pedido; lead convertido; order.created com total % = pedido', v_ev_total;
    else raise notice 'BR5) FALHA: opp=(%,%,%) lead=(%,%,%) ev_opp=% ev_total=% pedido_total=%',
      r_opp.stage, r_opp.order_id, r_opp.closed_at, r_lead.status, r_lead.converted_at, r_lead.customer_id, v_ev_opp, v_ev_total, v_total; end if;
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

-- Os ids do lead, da oportunidade e do evento do vendedor A ficam em
-- variáveis de sessão ANTES de trocar de usuário: a conferência usa ids
-- conhecidos, não uma subconsulta que a RLS já esconderia.
reset role;
select set_config('brain.test.joao', (select id::text from brain.leads where name = 'João da Silva'), false);
select set_config('brain.test.opp',  (select id::text from brain.opportunities where lead_id = current_setting('brain.test.joao')::uuid), false);
select set_config('brain.test.ev',   (select min(id)::text from brain.events where lead_id = current_setting('brain.test.joao')::uuid), false);
select set_config('brain.test.quote', (select quote_id::text from brain.opportunities where id = current_setting('brain.test.opp')::uuid), false);
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002503', false);

do $$
declare n_leads int; n_alheio int; n_fila int; n_ev int; n_opp int; v_claim uuid; n_upd int;
begin
  select count(*) into n_leads from brain.leads;
  select count(*) into n_alheio from brain.leads where id = current_setting('brain.test.joao')::uuid;
  select count(*) into n_fila from brain.leads where name = 'Lead da fila';
  select count(*) into n_ev from brain.events where id = current_setting('brain.test.ev')::bigint;
  select count(*) into n_opp from brain.opportunities where id = current_setting('brain.test.opp')::uuid;

  -- Pega o lead da fila para si.
  update brain.leads set owner_id = '25252525-0000-4000-8000-000000002503' where name = 'Lead da fila';
  get diagnostics n_upd = row_count;
  -- Tenta editar o lead do vendedor A (invisível: 0 linhas).
  update brain.leads set notes = 'invasao' where id = current_setting('brain.test.joao')::uuid;

  if n_alheio = 0 and n_fila = 1 and n_ev = 0 and n_opp = 0 and n_upd = 1
    then raise notice 'BR7) OK: vendedor B nao ve lead/oportunidade/evento do A (por id); viu e pegou o lead da fila';
    else raise notice 'BR7) FALHA: leads=% alheio=% fila=% eventos=% opps=% claim=%', n_leads, n_alheio, n_fila, n_ev, n_opp, n_upd; end if;
end $$;

-- ── BR11 (F1): conhecer o id de um evento não dá acesso a ele ──
-- Evento sem lead, criado pelo admin (B não o enxerga). B tenta "puxar" o
-- evento para o próprio lead via log_interaction.
reset role;
select set_config('brain.test.ev_solto', (select event_id::text from brain.ingest_event('website.whatsapp_clicked', 'website', '{"page":"/agras"}'::jsonb, 'w-solto-1')), false);
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002503', false);
do $$
declare v_fila uuid; e1 text := '(sem erro)'; n_antes int; n_depois int; v_lead_ev uuid;
begin
  select id into v_fila from brain.leads where name = 'Lead da fila';
  select count(*) into n_antes from brain.events where id = current_setting('brain.test.ev_solto')::bigint;
  begin
    perform brain.log_interaction(v_fila, 'tentativa', 'whatsapp', 'message', 'inbound', now(), 'whatsapp', 'x-1', null,
                                  current_setting('brain.test.ev_solto')::bigint);
  exception when others then e1 := left(sqlerrm, 44); end;
  select count(*) into n_depois from brain.events where id = current_setting('brain.test.ev_solto')::bigint;
  if n_antes = 0 and e1 <> '(sem erro)' and n_depois = 0
    then raise notice 'BR11) OK: evento alheio continua invisivel para B (%)', e1;
    else raise notice 'BR11) FALHA: antes=% erro=% depois=%', n_antes, e1, n_depois; end if;
end $$;

-- ── BR12 (F2): funções privilegiadas não revelam nem tocam o lead alheio ──
do $$
declare r record; v_touch_antes timestamptz; v_touch_depois timestamptz; e1 text := '(sem erro)'; e2 text := '(sem erro)'; n_leads int;
begin
  select count(*) into n_leads from brain.leads;
  -- B chega com o Instagram do lead de A.
  select * into r from brain.find_or_create_lead('Impostor', null, null, '@joao_agro', 'instagram');
  begin
    perform brain.ingest_event('order.delivered', 'erp', '{}'::jsonb, 'forjado-1', now(), null,
                               current_setting('brain.test.joao')::uuid);
  exception when others then e1 := left(sqlerrm, 40); end;
  begin
    perform brain.ingest_event('crm.note', 'app', '{}'::jsonb, 'forjado-2', now(), null,
                               current_setting('brain.test.joao')::uuid);
  exception when others then e2 := left(sqlerrm, 40); end;
  if r.lead_id is null and not r.created and r.matched_by = 'exists_elsewhere'
     and e1 <> '(sem erro)' and e2 <> '(sem erro)'
     and (select count(*) from brain.leads) = n_leads
    then raise notice 'BR12) OK: contato de outro vendedor devolve exists_elsewhere sem id; origem erp e lead alheio recusados (% / %)', e1, e2;
    else raise notice 'BR12) FALHA: r=(%,%,%) e1=% e2=%', r.lead_id, r.created, r.matched_by, e1, e2; end if;
end $$;

-- ── BR13 (F3): usuário desativado não escreve nem pela função ──
reset role;
update public.profiles set is_active = false where id = '25252525-0000-4000-8000-000000002503';
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002503', false);
do $$
declare v_fila uuid; e1 text := '(sem erro)'; e2 text := '(sem erro)'; n_int int;
begin
  select id into v_fila from brain.leads where name = 'Lead da fila';   -- invisível: nulo
  begin
    perform brain.log_interaction(coalesce(v_fila, '00000000-0000-4000-8000-000000000000'::uuid), 'inativo escreve?');
  exception when others then e1 := left(sqlerrm, 30); end;
  begin
    perform brain.find_or_create_lead('Inativo', '43911112222');
  exception when others then e2 := left(sqlerrm, 30); end;
  select count(*) into n_int from brain.interactions where summary = 'inativo escreve?';
  if v_fila is null and e1 <> '(sem erro)' and e2 <> '(sem erro)' and n_int = 0
    then raise notice 'BR13) OK: desativado nao le, nao registra interacao nem cria lead (% / %)', e1, e2;
    else raise notice 'BR13) FALHA: fila=% e1=% e2=% interacoes=%', v_fila, e1, e2, n_int; end if;
end $$;
reset role;
update public.profiles set is_active = true where id = '25252525-0000-4000-8000-000000002503';
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002503', false);

-- ── BR14 (F4): vínculo com lead/orçamento/oportunidade alheios é recusado; autoria é forçada ──
do $$
declare v_fila uuid; v_q uuid; e1 text := '(sem erro)'; e2 text := '(sem erro)'; e3 text := '(sem erro)'; v_cb uuid; v_opp uuid;
begin
  select id into v_fila from brain.leads where name = 'Lead da fila';
  v_q := current_setting('brain.test.quote')::uuid;   -- orçamento do vendedor A, id conhecido
  begin
    insert into brain.opportunities (lead_id, owner_id, title)
    values (current_setting('brain.test.joao')::uuid, '25252525-0000-4000-8000-000000002503', 'roubo de lead');
  exception when others then e1 := left(sqlerrm, 40); end;
  begin
    insert into brain.opportunities (lead_id, owner_id, title, quote_id)
    values (v_fila, '25252525-0000-4000-8000-000000002503', 'roubo de orcamento', v_q);
  exception when others then e2 := left(sqlerrm, 40); end;
  begin
    insert into brain.tasks (lead_id, opportunity_id, assignee_id, title)
    values (v_fila, current_setting('brain.test.opp')::uuid, '25252525-0000-4000-8000-000000002503', 'tarefa em opp alheia');
  exception when others then e3 := left(sqlerrm, 40); end;
  -- Autoria: B tenta assinar como A.
  insert into brain.opportunities (lead_id, owner_id, title, created_by)
  values (v_fila, '25252525-0000-4000-8000-000000002503', 'legitima', '25252525-0000-4000-8000-000000002502')
  returning id, created_by into v_opp, v_cb;
  if e1 <> '(sem erro)' and e2 <> '(sem erro)' and e3 <> '(sem erro)'
     and v_cb = '25252525-0000-4000-8000-000000002503'
    then raise notice 'BR14) OK: lead, orcamento e oportunidade alheios recusados; created_by forcado ao usuario logado';
    else raise notice 'BR14) FALHA: e1=% e2=% e3=% created_by=%', e1, e2, e3, v_cb; end if;
end $$;

-- ── BR15 (F6): identidade nova enriquece o lead reconhecido (e não cria outro) ──
select set_config('request.jwt.claim.sub', '25252525-0000-4000-8000-000000002502', false);
do $$
declare r1 record; r2 record; n int; v_joao uuid := current_setting('brain.test.joao')::uuid;
begin
  -- A reconhece o João pelo Instagram e traz um e-mail novo.
  select * into r1 from brain.find_or_create_lead('João', null, 'joao@fazenda.com.br', 'joao_agro', 'email');
  -- Depois chega SÓ o e-mail.
  select * into r2 from brain.find_or_create_lead('J.', null, 'JOAO@fazenda.com.br', null, 'email');
  select count(*) into n from brain.identities where lead_id = v_joao and kind = 'email';
  if not r1.created and r1.lead_id = v_joao and not r2.created and r2.lead_id = v_joao and n = 1
    then raise notice 'BR15) OK: e-mail novo enriqueceu o lead reconhecido; chegada so pelo e-mail caiu no mesmo lead';
    else raise notice 'BR15) FALHA: r1=(%,%) r2=(%,%) emails=%', r1.created, r1.lead_id = v_joao, r2.created, r2.lead_id = v_joao, n; end if;
end $$;

-- ── BR16 (F5b): pedido cancelado devolve a oportunidade a negociacao ──
reset role;
do $$
declare v_o uuid; v_stage text; n_ev int;
begin
  select order_id into v_o from brain.opportunities where id = current_setting('brain.test.opp')::uuid;
  update public.orders set status = 'cancelled' where id = v_o;
  select stage::text into v_stage from brain.opportunities where id = current_setting('brain.test.opp')::uuid;
  select count(*) into n_ev from brain.events where event_name = 'order.cancelled' and (payload->>'order_id')::uuid = v_o;
  if v_stage = 'negotiation' and n_ev = 1
    then raise notice 'BR16) OK: order.cancelled publicado; oportunidade voltou a negotiation';
    else raise notice 'BR16) FALHA: stage=% eventos=%', v_stage, n_ev; end if;
end $$;

-- ── BR17 (F8): TRUNCATE recusado — por gatilho e por privilégio ──
do $$
declare e1 text := '(sem erro)'; v_priv boolean; n int;
begin
  select count(*) into n from brain.events;
  begin
    truncate brain.events cascade;
  exception when others then e1 := left(sqlerrm, 40); end;
  v_priv := has_table_privilege('service_role', 'brain.events', 'truncate');
  if e1 <> '(sem erro)' and not v_priv and (select count(*) from brain.events) = n
    then raise notice 'BR17) OK: truncate recusado ate para postgres (%); service_role sem TRUNCATE; % eventos intactos', e1, n;
    else raise notice 'BR17) FALHA: erro=% priv=%', e1, v_priv; end if;
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
