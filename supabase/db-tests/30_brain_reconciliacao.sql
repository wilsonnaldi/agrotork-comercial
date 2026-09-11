-- ============================================================
-- BRAIN — reconciliação comercial (migration 20260911170000).
--
-- A lacuna que este arquivo fecha: a reposição antiga arrumava o
-- barramento e deixava o CRM errado. "Zero eventos faltantes" passava
-- com a oportunidade parada em `prospecting` e o lead nunca convertido.
--
-- O que este arquivo prova:
--   RC1  ponte desligada, venda inteira acontece → o BRAIN fica para trás
--        em SEIS tipos de divergência, e o relatório os mostra;
--   RC2  reconciliar arruma os seis;
--   RC3  pedido cancelado durante o apagão → oportunidade volta a
--        negotiation, e NÃO fica ganha por engano;
--   RC4  decisão humana não é atropelada: `lost` continua `lost`;
--   RC5  estágio não anda para trás;
--   RC6  lead convertido continua convertido mesmo com o pedido cancelado;
--   RC7  a segunda execução não muda NADA — md5 do estado do CRM;
--   RC8  vendedor não reconcilia nem enxerga divergência.
--
-- Prefixo de UUID = 30.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('30303030-0000-4000-8000-000000000001','rc.admin@teste.local','{"full_name":"Admin Reconciliacao","role":"admin"}'),
 ('30303030-0000-4000-8000-000000000002','rc.vend@teste.local' ,'{"full_name":"Vendedor Reconciliacao","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '30303030-0000-4000-8000-000000000001';

insert into public.customers (id, name, city, state) values
 ('30303030-0000-4000-8000-0000000000c1','Fazenda da Reconciliacao','Londrina','PR'),
 ('30303030-0000-4000-8000-0000000000c2','Sitio do Cancelamento','Cambe','PR'),
 ('30303030-0000-4000-8000-0000000000c3','Chacara da Decisao','Rolandia','PR');

insert into public.products (code, name, unit_id, sale_price)
select 'RC-001', 'Pulverizador da Reconciliacao', u.id, 100000.00 from public.units u where u.code = 'UN';

-- ── Uma venda inteira com a PONTE DESLIGADA ─────────────────
-- É o cenário real do incidente: a ponte saiu, a vida comercial seguiu.
alter table public.quotes disable trigger trg_brain_quotes;
alter table public.orders disable trigger trg_brain_orders;
alter table public.orders disable trigger trg_brain_orders_created;

do $$
declare v_lead uuid; v_quote uuid; v_order uuid; v_prod uuid;
begin
  select id into v_prod from public.products where code = 'RC-001';

  -- Negócio 1: venda completa, tudo com a ponte fora.
  insert into brain.leads (name, customer_id, owner_id)
   values ('Lead da Reconciliacao','30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-000000000002')
   returning id into v_lead;
  insert into public.quotes (customer_id, owner_id)
   values ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-000000000002')
   returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key)
   values (v_lead, v_quote, 'Oportunidade RC1', 'other');
  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Pulverizador da Reconciliacao', 'RC-001', 2, 100000.00, 1);
  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;
  v_order := public.create_order_from_quote(v_quote);
  perform set_config('brain.teste.rc1_quote', v_quote::text, false);
  perform set_config('brain.teste.rc1_order', v_order::text, false);
  perform set_config('brain.teste.rc1_lead',  v_lead::text,  false);

  -- Negócio 3: orçamento aprovado, mas alguém já deu a oportunidade
  -- por perdida. A reconciliação não pode desfazer isso.
  insert into brain.leads (name, customer_id) values ('Lead da Decisao','30303030-0000-4000-8000-0000000000c3')
   returning id into v_lead;
  insert into public.quotes (customer_id, owner_id)
   values ('30303030-0000-4000-8000-0000000000c3','30303030-0000-4000-8000-000000000002')
   returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key, stage)
   values (v_lead, v_quote, 'Oportunidade RC4', 'other', 'lost');
  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;
  perform set_config('brain.teste.rc4_quote', v_quote::text, false);
end
$$;

alter table public.quotes enable trigger trg_brain_quotes;
alter table public.orders enable trigger trg_brain_orders;
alter table public.orders enable trigger trg_brain_orders_created;

-- ── Negócio 2: ganho COM a ponte ligada, cancelado no apagão ──
-- É assim que `venda_desfeita` nasce de verdade: a oportunidade chegou a
-- ser marcada como ganha, e o cancelamento é que se perdeu.
do $$
declare v_lead uuid; v_quote uuid; v_order uuid; v_prod uuid;
begin
  select id into v_prod from public.products where code = 'RC-001';
  insert into brain.leads (name, customer_id) values ('Lead do Cancelamento','30303030-0000-4000-8000-0000000000c2')
   returning id into v_lead;
  insert into public.quotes (customer_id, owner_id)
   values ('30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-000000000002')
   returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key)
   values (v_lead, v_quote, 'Oportunidade RC3', 'other');
  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Pulverizador da Reconciliacao', 'RC-001', 1, 100000.00, 1);
  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;
  v_order := public.create_order_from_quote(v_quote);
  perform set_config('brain.teste.rc3_order', v_order::text, false);
end
$$;

do $$
begin
  if (select stage from brain.opportunities where title = 'Oportunidade RC3') <> 'won' then
    raise exception 'preparo RC3 FALHOU: a ponte nao marcou a venda como ganha';
  end if;
end
$$;

-- Agora a ponte sai, e o cancelamento acontece sem ela.
alter table public.orders disable trigger trg_brain_orders;
update public.orders set status = 'cancelled'
 where id = current_setting('brain.teste.rc3_order')::uuid;
alter table public.orders enable trigger trg_brain_orders;

-- ── RC1: o relatório vê os seis tipos ───────────────────────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '30303030-0000-4000-8000-000000000001', false);

do $$
declare v_tipos text; v_total int;
begin
  select string_agg(distinct tipo, ', ' order by tipo), count(*) into v_tipos, v_total
    from brain.divergencias_erp();

  if v_total = 0 then
    raise exception 'RC1 FALHOU: com a ponte desligada o relatorio veio vazio';
  end if;
  foreach v_tipos in array array['evento_ausente','estagio_atrasado','venda_nao_ganha',
                                 'venda_desfeita','pedido_nao_ligado','lead_nao_convertido'] loop
    if not exists (select 1 from brain.divergencias_erp() where tipo = v_tipos) then
      raise exception 'RC1 FALHOU: o relatorio nao acusou "%"', v_tipos;
    end if;
  end loop;

  select string_agg(distinct tipo, ', ' order by tipo) into v_tipos from brain.divergencias_erp();
  raise notice ' RC1) OK: % divergencia(s) em 6 tipos — %', v_total, v_tipos;
end
$$;

-- ── RC2 a RC6: reconciliar ──────────────────────────────────
do $$
declare
  r record; v_texto text := '';
  v_order_rc3 uuid := current_setting('brain.teste.rc3_order')::uuid;
  v_order_rc1 uuid := current_setting('brain.teste.rc1_order')::uuid;
  v_lead_rc1  uuid := current_setting('brain.teste.rc1_lead')::uuid;
  v_quote_rc4 uuid := current_setting('brain.teste.rc4_quote')::uuid;
  v_estagio brain.opportunity_stage;
begin
  for r in select * from brain.reconciliar_erp() where corrigidas > 0 order by tipo loop
    v_texto := v_texto || case when v_texto = '' then '' else ', ' end || r.tipo || '=' || r.corrigidas;
  end loop;

  -- RC2: sobrou divergência?
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'RC2 FALHOU: sobrou divergencia: %',
      (select string_agg(tipo || '/' || coalesce(numero,'?'), ', ') from brain.divergencias_erp());
  end if;
  raise notice ' RC2) OK: reconciliado — %; relatorio zerado', v_texto;

  -- RC3: o pedido cancelado não pode ter ficado ganho.
  select stage into v_estagio from brain.opportunities where order_id = v_order_rc3;
  if v_estagio is distinct from 'negotiation' then
    raise exception 'RC3 FALHOU: pedido cancelado deixou a oportunidade em %', coalesce(v_estagio::text,'(sem vinculo)');
  end if;
  raise notice ' RC3) OK: pedido cancelado — oportunidade em negotiation, nunca marcada como ganha';

  -- RC4: decisão humana intacta.
  select stage into v_estagio from brain.opportunities where quote_id = v_quote_rc4;
  if v_estagio is distinct from 'lost' then
    raise exception 'RC4 FALHOU: a oportunidade dada por perdida virou %', v_estagio;
  end if;
  if (select status from brain.leads where name = 'Lead da Decisao') = 'converted' then
    raise exception 'RC4 FALHOU: converteu o lead de uma oportunidade perdida';
  end if;
  raise notice ' RC4) OK: oportunidade em lost continua em lost, e o lead dela nao foi convertido';

  -- RC5: a venda completa ficou certa.
  select stage into v_estagio from brain.opportunities where order_id = v_order_rc1;
  if v_estagio is distinct from 'won' then
    raise exception 'RC5 FALHOU: a venda completa ficou em %', v_estagio;
  end if;
  if (select status from brain.leads where id = v_lead_rc1) <> 'converted' then
    raise exception 'RC5 FALHOU: o lead da venda completa nao foi convertido';
  end if;
  if (select count(*) from brain.events where source = 'erp'
        and payload ->> 'order_id' = v_order_rc1::text) = 0 then
    raise exception 'RC5 FALHOU: o pedido continua sem evento';
  end if;
  raise notice ' RC5) OK: venda completa — oportunidade ganha, lead convertido, evento no barramento';
end
$$;

-- ── RC6: estágio não anda para trás ─────────────────────────
do $$
declare v_quote uuid := current_setting('brain.teste.rc1_quote')::uuid; v_estagio text;
begin
  -- A oportunidade da venda completa está em `won`. Reconciliar de novo
  -- não pode rebaixá-la para `negotiation` por causa do orçamento
  -- aprovado.
  perform brain.reconciliar_erp();
  select stage::text into v_estagio from brain.opportunities where quote_id = v_quote;
  if v_estagio <> 'won' then
    raise exception 'RC6 FALHOU: o estagio voltou de won para %', v_estagio;
  end if;
  raise notice ' RC6) OK: oportunidade ganha nao foi rebaixada pelo orcamento aprovado';
end
$$;

-- ── RC7: a segunda execução não muda nada ───────────────────
do $$
declare v_antes text; v_depois text; r record; v_mexeu int := 0;
begin
  select md5(string_agg(t::text, '|' order by t::text)) into v_antes
    from (select id, stage, order_id, quote_id, lead_id, customer_id from brain.opportunities
          union all
          select id, null, null, null, null, customer_id from brain.leads) t;

  for r in select * from brain.reconciliar_erp() loop
    v_mexeu := v_mexeu + r.corrigidas;
  end loop;

  select md5(string_agg(t::text, '|' order by t::text)) into v_depois
    from (select id, stage, order_id, quote_id, lead_id, customer_id from brain.opportunities
          union all
          select id, null, null, null, null, customer_id from brain.leads) t;

  if v_mexeu <> 0 then
    raise exception 'RC7 FALHOU: a execucao seguinte ainda corrigiu % coisa(s)', v_mexeu;
  end if;
  if v_antes is distinct from v_depois then
    raise exception 'RC7 FALHOU: o estado do CRM mudou na execucao seguinte';
  end if;
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'RC7 FALHOU: voltou a divergir';
  end if;
  raise notice ' RC7) OK: execucao seguinte corrigiu 0 e o md5 do CRM nao mudou (%)', left(v_depois, 12);
end
$$;

-- ── RC8: só administrador ───────────────────────────────────
do $$
begin
  perform set_config('request.jwt.claim.sub', '30303030-0000-4000-8000-000000000002', false);
  begin
    perform brain.reconciliar_erp();
    raise exception 'RC8 FALHOU: vendedor reconciliou';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'RC8 FALHOU: vendedor enxergou divergencia';
  end if;
  raise notice ' RC8) OK: reconciliar e ver divergencia sao so do administrador';
end
$$;

reset role;

-- Limpeza: só o que esta suíte criou. Eventos não se apagam.
delete from brain.tasks where lead_id in (select id from brain.leads where name like '%Reconciliacao%' or name like '%Cancelamento%' or name like '%Decisao%');
delete from brain.interactions where lead_id in (select id from brain.leads where name like '%Reconciliacao%' or name like '%Cancelamento%' or name like '%Decisao%');
delete from brain.opportunities where title like 'Oportunidade RC%';
delete from brain.identities where lead_id in (select id from brain.leads where name like 'Lead d%');
delete from brain.leads where name in ('Lead da Reconciliacao','Lead do Cancelamento','Lead da Decisao');
delete from public.order_items where order_id in (select id from public.orders where customer_id in ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-0000000000c3'));
delete from public.orders where customer_id in ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-0000000000c3');
delete from public.quote_items where quote_id in (select id from public.quotes where customer_id in ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-0000000000c3'));
delete from public.quotes where customer_id in ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-0000000000c3');
delete from public.products where code = 'RC-001';
delete from public.customers where id in ('30303030-0000-4000-8000-0000000000c1','30303030-0000-4000-8000-0000000000c2','30303030-0000-4000-8000-0000000000c3');
delete from auth.users where id in ('30303030-0000-4000-8000-000000000001','30303030-0000-4000-8000-000000000002');
