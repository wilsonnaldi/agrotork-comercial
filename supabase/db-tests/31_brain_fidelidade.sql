-- ============================================================
-- BRAIN — fidelidade do nome do evento (migration 20260911210000).
--
-- A lacuna que este arquivo fecha: com as pontes desligadas em
-- produção, TODO evento do ERP passa a nascer pela reconciliação. Se
-- ela batizar o mesmo fato com outro nome, o BRAIN acumula dois
-- vocabulários e quem consumir esses eventos na Fase 2 lê história
-- errada. O ensaio do deploy pegou exatamente isso: a ponte publica
-- `order.created` no nascimento do pedido, e a reconciliação publicava
-- `order.confirmed`, porque tirava o nome do status — e `draft`, o
-- único status que ela traduzia para `created`, nem existe em
-- `public.order_status`.
--
-- O que este arquivo prova:
--   FD1  pedido nascido com a ponte fora → a reconciliação publica
--        `order.created`, o MESMO nome que a ponte publicaria;
--   FD2  orçamento nascido com a ponte fora → `quote.created`;
--   FD3  orçamento que já tem evento e muda de status → `quote.sent`,
--        e não um segundo `quote.created`;
--   FD4  orçamento que nasceu e já foi para `sent` sem nenhum evento →
--        `quote.created` carregando o estado de agora, porque o fato
--        que faltou é o nascimento;
--   FD5  o evento reposto sai marcado como reconstrução
--        (`reconciliado_em` no metadado) — não se passa por evento
--        publicado na hora;
--   FD6  rodar a reconciliação de novo não duplica evento nenhum;
--   FD7  o nome que a ponte dá e o nome que a reconciliação dá para o
--        MESMO fato são iguais — comparação direta, sem literal.
--
-- Prefixo de UUID = 31.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('31313131-0000-4000-8000-000000000001','fd.admin@teste.local','{"full_name":"Admin Fidelidade","role":"admin"}');
update public.profiles set role = 'admin' where id = '31313131-0000-4000-8000-000000000001';

insert into public.customers (id, name, city, state) values
 ('31313131-0000-4000-8000-0000000000c1','Fazenda da Fidelidade','Londrina','PR'),
 ('31313131-0000-4000-8000-0000000000c2','Sitio do Nome Certo','Ibipora','PR');

insert into public.products (code, name, unit_id, sale_price)
select 'FD-001', 'Plantadeira da Fidelidade', u.id, 80000.00 from public.units u where u.code = 'UN';

-- ── FD1 e FD2: venda inteira com as pontes fora ─────────────
alter table public.quotes disable trigger trg_brain_quotes;
alter table public.orders disable trigger trg_brain_orders;
alter table public.orders disable trigger trg_brain_orders_created;

do $$
declare v_lead uuid; v_quote uuid; v_order uuid; v_prod uuid; v_nome text;
begin
  perform set_config('request.jwt.claim.sub','31313131-0000-4000-8000-000000000001',false);
  select id into v_prod from public.products where code = 'FD-001';
  select lead_id into v_lead from brain.find_or_create_lead('Lead da Fidelidade', null, null, null, 'other');

  insert into public.quotes (id, customer_id, owner_id)
   values ('31313131-0000-4000-8000-0000000000a1','31313131-0000-4000-8000-0000000000c1',
           '31313131-0000-4000-8000-000000000001') returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Oportunidade FD1', 'other', '31313131-0000-4000-8000-0000000000c1');
  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Plantadeira da Fidelidade', 'FD-001', 1, 80000.00, 1);
  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;
  v_order := public.create_order_from_quote(v_quote);

  -- Só o que ESTA suíte criou: o banco de teste já carrega eventos das
  -- suítes anteriores, e eles não têm nada a ver com esta medida.
  if exists (select 1 from brain.events
              where source = 'erp'
                and (payload ->> 'quote_id' = v_quote::text
                  or payload ->> 'order_id' = v_order::text)) then
    raise exception 'FD setup FALHOU: ponte publicou evento com o gatilho desligado';
  end if;

  perform brain.reconciliar_erp();

  select event_name into v_nome from brain.events
   where source = 'erp' and payload ->> 'order_id' = v_order::text;
  if v_nome is distinct from 'order.created' then
    raise exception 'FD1 FALHOU: pedido nascido virou evento %, e a ponte diria order.created', coalesce(v_nome,'(nenhum)');
  end if;
  raise notice ' FD1) OK: pedido nascido sem ponte virou order.created';

  select event_name into v_nome from brain.events
   where source = 'erp' and payload ->> 'quote_id' = v_quote::text;
  if v_nome is distinct from 'quote.created' then
    raise exception 'FD2 FALHOU: orcamento virou evento %, esperado quote.created', coalesce(v_nome,'(nenhum)');
  end if;
  raise notice ' FD2) OK: orcamento nascido sem ponte virou quote.created';

  -- FD5: é reconstrução, e o evento diz isso.
  if not exists (select 1 from brain.events
                  where source = 'erp' and payload ->> 'order_id' = v_order::text
                    and metadata ? 'reconciliado_em') then
    raise exception 'FD5 FALHOU: evento reposto nao esta marcado como reconstrucao';
  end if;
  raise notice ' FD5) OK: o evento reposto se identifica como reconciliado';
end
$$;

-- ── FD3: entidade que JÁ tem evento muda de status ──────────
do $$
declare v_quote uuid; v_lead uuid; v_n int;
begin
  perform set_config('request.jwt.claim.sub','31313131-0000-4000-8000-000000000001',false);
  select lead_id into v_lead from brain.find_or_create_lead('Lead do Nome Certo', null, null, null, 'other');

  insert into public.quotes (id, customer_id, owner_id)
   values ('31313131-0000-4000-8000-0000000000a2','31313131-0000-4000-8000-0000000000c2',
           '31313131-0000-4000-8000-000000000001') returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Oportunidade FD3', 'other', '31313131-0000-4000-8000-0000000000c2');

  perform brain.reconciliar_erp();          -- publica quote.created (draft)
  update public.quotes set status = 'sent' where id = v_quote;
  perform brain.reconciliar_erp();          -- agora tem evento: quote.sent

  select count(*) into v_n from brain.events
   where source = 'erp' and payload ->> 'quote_id' = v_quote::text and event_name = 'quote.created';
  if v_n <> 1 then
    raise exception 'FD3 FALHOU: % evento(s) quote.created para o mesmo orcamento', v_n;
  end if;
  if not exists (select 1 from brain.events
                  where source = 'erp' and payload ->> 'quote_id' = v_quote::text
                    and event_name = 'quote.sent') then
    raise exception 'FD3 FALHOU: mudanca de status nao virou quote.sent';
  end if;
  raise notice ' FD3) OK: com evento anterior, a mudanca vira quote.sent e nao um segundo quote.created';
end
$$;

-- ── FD4: nasceu e já andou, sem nenhum evento ───────────────
do $$
declare v_quote uuid; v_lead uuid; r record;
begin
  perform set_config('request.jwt.claim.sub','31313131-0000-4000-8000-000000000001',false);
  select lead_id into v_lead from brain.find_or_create_lead('Lead do Atraso', null, null, null, 'other');

  insert into public.quotes (id, customer_id, owner_id)
   values ('31313131-0000-4000-8000-0000000000a3','31313131-0000-4000-8000-0000000000c2',
           '31313131-0000-4000-8000-000000000001') returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Oportunidade FD4', 'other', '31313131-0000-4000-8000-0000000000c2');
  update public.quotes set status = 'sent' where id = v_quote;

  perform brain.reconciliar_erp();

  select event_name, payload ->> 'status' as st into r from brain.events
   where source = 'erp' and payload ->> 'quote_id' = v_quote::text;
  if r.event_name is distinct from 'quote.created' then
    raise exception 'FD4 FALHOU: primeiro evento de um orcamento atrasado veio como %', coalesce(r.event_name,'(nenhum)');
  end if;
  if r.st is distinct from 'sent' then
    raise exception 'FD4 FALHOU: o evento do nascimento nao carrega o estado de agora (veio %)', coalesce(r.st,'(nulo)');
  end if;
  raise notice ' FD4) OK: nascimento reposto carrega o estado atual (sent) e se chama quote.created';
end
$$;

-- ── FD6: rodar de novo não duplica ──────────────────────────
do $$
declare v_antes int; v_depois int;
begin
  perform set_config('request.jwt.claim.sub','31313131-0000-4000-8000-000000000001',false);
  select count(*) into v_antes from brain.events where source = 'erp';
  perform brain.reconciliar_erp();
  perform brain.reconciliar_erp();
  select count(*) into v_depois from brain.events where source = 'erp';
  -- A contagem aqui é global de propósito: se QUALQUER entidade do banco
  -- ganhasse evento duplicado numa segunda passada, é defeito.
  if v_depois <> v_antes then
    raise exception 'FD6 FALHOU: duas execucoes a mais criaram % evento(s)', v_depois - v_antes;
  end if;
  raise notice ' FD6) OK: reconciliar de novo nao duplica evento';
end
$$;

-- ── FD7: ponte e reconciliação batizam igual ────────────────
-- Sem literal: o mesmo fato é publicado pelos dois caminhos em dois
-- orçamentos gêmeos, e os nomes têm de coincidir.
alter table public.quotes enable trigger trg_brain_quotes;

do $$
declare v_pela_ponte text; v_pela_recon text; v_lead uuid;
begin
  perform set_config('request.jwt.claim.sub','31313131-0000-4000-8000-000000000001',false);
  select lead_id into v_lead from brain.find_or_create_lead('Lead do Espelho', null, null, null, 'other');

  -- Gêmeo A: com a ponte ligada.
  insert into public.quotes (id, customer_id, owner_id)
   values ('31313131-0000-4000-8000-0000000000a4','31313131-0000-4000-8000-0000000000c1',
           '31313131-0000-4000-8000-000000000001');
  select event_name into v_pela_ponte from brain.events
   where source = 'erp' and payload ->> 'quote_id' = '31313131-0000-4000-8000-0000000000a4';

  -- Gêmeo B: com a ponte fora, reposto pela reconciliação.
  alter table public.quotes disable trigger trg_brain_quotes;
  insert into public.quotes (id, customer_id, owner_id)
   values ('31313131-0000-4000-8000-0000000000a5','31313131-0000-4000-8000-0000000000c1',
           '31313131-0000-4000-8000-000000000001');
  perform brain.reconciliar_erp();
  select event_name into v_pela_recon from brain.events
   where source = 'erp' and payload ->> 'quote_id' = '31313131-0000-4000-8000-0000000000a5';

  if v_pela_ponte is null or v_pela_recon is null then
    raise exception 'FD7 FALHOU: ponte=% reconciliacao=%', coalesce(v_pela_ponte,'(nenhum)'), coalesce(v_pela_recon,'(nenhum)');
  end if;
  if v_pela_ponte <> v_pela_recon then
    raise exception 'FD7 FALHOU: a ponte chamou de % e a reconciliacao de %', v_pela_ponte, v_pela_recon;
  end if;
  raise notice ' FD7) OK: ponte e reconciliacao chamam o mesmo fato de % — um vocabulario so', v_pela_ponte;
end
$$;

-- ── Devolve o estado de produção: as três desligadas ────────
alter table public.quotes disable trigger trg_brain_quotes;
alter table public.orders disable trigger trg_brain_orders;
alter table public.orders disable trigger trg_brain_orders_created;

reset role;

-- Limpeza: só o que esta suíte criou. Eventos não se apagam.
delete from brain.tasks where lead_id in (select id from brain.leads where name in ('Lead da Fidelidade','Lead do Nome Certo','Lead do Atraso','Lead do Espelho'));
delete from brain.interactions where lead_id in (select id from brain.leads where name in ('Lead da Fidelidade','Lead do Nome Certo','Lead do Atraso','Lead do Espelho'));
delete from brain.opportunities where title like 'Oportunidade FD%';
delete from brain.identities where lead_id in (select id from brain.leads where name in ('Lead da Fidelidade','Lead do Nome Certo','Lead do Atraso','Lead do Espelho'));
delete from brain.leads where name in ('Lead da Fidelidade','Lead do Nome Certo','Lead do Atraso','Lead do Espelho');
delete from public.order_items where order_id in (select id from public.orders where customer_id in ('31313131-0000-4000-8000-0000000000c1','31313131-0000-4000-8000-0000000000c2'));
delete from public.orders where customer_id in ('31313131-0000-4000-8000-0000000000c1','31313131-0000-4000-8000-0000000000c2');
delete from public.quote_items where quote_id in (select id from public.quotes where customer_id in ('31313131-0000-4000-8000-0000000000c1','31313131-0000-4000-8000-0000000000c2'));
delete from public.quotes where customer_id in ('31313131-0000-4000-8000-0000000000c1','31313131-0000-4000-8000-0000000000c2');
delete from public.products where code = 'FD-001';
delete from public.customers where id in ('31313131-0000-4000-8000-0000000000c1','31313131-0000-4000-8000-0000000000c2');
delete from auth.users where id in ('31313131-0000-4000-8000-000000000001');
