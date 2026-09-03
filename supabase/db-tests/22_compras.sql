-- ============================================================
-- Entrada de mercadoria (migration 20260903140000).
--
-- O que este arquivo prova:
--   · o total da nota é do banco, e frete/despesa/desconto entram nele;
--   · o rateio é POR VALOR: o item caro absorve mais frete;
--   · receber faz três coisas na mesma transação — estoque, custo e
--     situação — ou não faz nenhuma;
--   · o custo anterior não se perde: a vigência fecha, não apaga;
--   · duas notas no mesmo dia não quebram o histórico;
--   · nota recebida não muda de conteúdo, nem se cancela;
--   · o vendedor não enxerga nota de compra — é custo de ponta a ponta.
--
-- Prefixo de UUID = número da suíte.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('22222222-0000-4000-8000-00000000c001','comp.admin@teste.local','{"full_name":"Admin Compra","role":"admin"}'),
 ('22222222-0000-4000-8000-00000000c002','comp.vend@teste.local','{"full_name":"Vendedor Compra","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = '22222222-0000-4000-8000-00000000c001';

insert into public.suppliers (name, document, city, state)
values ('Distribuidora de Teste', '11222333000181', 'Curitiba', 'PR');

-- Um item caro e um barato: é o par que faz o rateio por valor aparecer.
insert into public.products (code, name, unit_id, sale_price)
select 'CMP-CARO', 'Equipamento caro', u.id, 0 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'CMP-BARATO', 'Peca barata', u.id, 0 from public.units u where u.code = 'UN';

-- Custo anterior, para o histórico ter o que preservar. Ontem, de
-- propósito: hoje é o dia da nota.
insert into public.product_costs (product_id, cost_price, valid_from)
select p.id, 100, current_date - 10 from public.products p where p.code = 'CMP-CARO';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-00000000c001', false);

-- ── CP1: a nota nasce numerada e em rascunho ────────────────
do $$
declare v_num text; v_status public.purchase_status;
begin
  insert into public.purchases (supplier_id, condition_id, invoice_number, freight_amount)
  select s.id, c.id, '55501', 200
    from public.suppliers s, public.price_conditions c
   where s.name = 'Distribuidora de Teste' and c.is_default;

  select number, status into v_num, v_status from public.purchases limit 1;

  if v_num like 'ENT-%' and v_status = 'draft'
    then raise notice 'CP1) OK: nota % nasceu em rascunho', v_num;
    else raise notice 'CP1) FALHA: numero % / situacao %', v_num, v_status; end if;
end $$;

-- ── CP2: o total é do banco, com frete somado ───────────────
do $$
declare v_itens numeric; v_total numeric; v_nota uuid;
begin
  select id into v_nota from public.purchases limit 1;

  -- 1 caro a 1.000 e 10 baratas a 20 = 1.000 + 200 = 1.200 de itens.
  insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost, sort_order)
  select v_nota, p.id, 1, 1000, 1 from public.products p where p.code = 'CMP-CARO';
  insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost, sort_order)
  select v_nota, p.id, 10, 20, 2 from public.products p where p.code = 'CMP-BARATO';

  select items_total, total into v_itens, v_total from public.purchases where id = v_nota;

  if v_itens = 1200 and v_total = 1400
    then raise notice 'CP2) OK: itens % + frete 200 = total %', v_itens, v_total;
    else raise notice 'CP2) FALHA: itens % / total %', v_itens, v_total; end if;
end $$;

-- ── CP3: o mesmo produto duas vezes na mesma nota, não ──────
do $$
declare v_nota uuid;
begin
  select id into v_nota from public.purchases limit 1;
  begin
    insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost)
    select v_nota, p.id, 1, 999 from public.products p where p.code = 'CMP-CARO';
    raise notice 'CP3) FALHA: aceitou o mesmo produto duas vezes';
  exception when unique_violation then
    raise notice 'CP3) OK: produto repetido na mesma nota recusado';
  end;
end $$;

-- ── CP4: receber move estoque, custo e situação ─────────────
do $$
declare v_nota uuid; v_quantos int; v_status public.purchase_status;
        v_saldo_caro numeric; v_saldo_barato numeric;
begin
  select id into v_nota from public.purchases limit 1;
  select public.receive_purchase(v_nota) into v_quantos;

  select status into v_status from public.purchases where id = v_nota;
  select quantity into v_saldo_caro   from public.product_stock where code = 'CMP-CARO';
  select quantity into v_saldo_barato from public.product_stock where code = 'CMP-BARATO';

  if v_quantos = 2 and v_status = 'received' and v_saldo_caro = 1 and v_saldo_barato = 10
    then raise notice 'CP4) OK: % item(ns) recebidos, estoque 1 e 10, nota %', v_quantos, v_status;
    else raise notice 'CP4) FALHA: itens % / situacao % / saldos % e %',
         v_quantos, v_status, v_saldo_caro, v_saldo_barato; end if;
end $$;

-- ── CP5: o rateio é POR VALOR ───────────────────────────────
-- Frete 200 sobre itens de 1.200: o caro (1.000/1.200 = 83,33%) leva
-- 166,67 e a peça (200/1.200) leva 33,33. Ratear por peça daria 18,18
-- para cada uma das 11 unidades, e a peça de 20 reais ficaria custando
-- 38 — quase o dobro, por causa do frete de um equipamento.
do $$
declare v_caro numeric; v_barato numeric; v_lc_caro numeric; v_lc_barato numeric;
begin
  select freight_share, landed_cost into v_caro, v_lc_caro
    from public.purchase_items pi join public.products p on p.id = pi.product_id
   where p.code = 'CMP-CARO';
  select freight_share, landed_cost into v_barato, v_lc_barato
    from public.purchase_items pi join public.products p on p.id = pi.product_id
   where p.code = 'CMP-BARATO';

  -- 166,67 + 33,33 = 200: o frete inteiro foi distribuído.
  if v_caro = 166.67 and v_barato = 33.33 and v_lc_caro = 1166.6700 and v_lc_barato = 23.3330
    then raise notice 'CP5) OK: frete % no caro e % na peca — custo final % e %',
         v_caro, v_barato, v_lc_caro, v_lc_barato;
    else raise notice 'CP5) FALHA: fretes % e % / custos % e %',
         v_caro, v_barato, v_lc_caro, v_lc_barato; end if;
end $$;

-- ── CP6: o custo do produto passou a ser o da nota ──────────
do $$
declare v_vigente numeric; v_anterior numeric;
begin
  select cost_price into v_vigente from public.product_costs pc
    join public.products p on p.id = pc.product_id
   where p.code = 'CMP-CARO' and pc.valid_to is null;

  select previous_cost into v_anterior
    from public.purchase_items pi join public.products p on p.id = pi.product_id
   where p.code = 'CMP-CARO';

  if v_vigente = 1166.67 and v_anterior = 100
    then raise notice 'CP6) OK: custo subiu de % para % — e a tela sabe dizer isso', v_anterior, v_vigente;
    else raise notice 'CP6) FALHA: vigente % / anterior %', v_vigente, v_anterior; end if;
end $$;

-- ── CP7: o custo anterior não se perde ──────────────────────
do $$
declare v_fechados int; v_ate date;
begin
  select count(*)::int, max(valid_to) into v_fechados
       , v_ate
    from public.product_costs pc join public.products p on p.id = pc.product_id
   where p.code = 'CMP-CARO' and pc.valid_to is not null;

  if v_fechados = 1 and v_ate = current_date - 1
    then raise notice 'CP7) OK: a linha antiga fechou em %, nao foi apagada', v_ate;
    else raise notice 'CP7) FALHA: % linha(s) fechada(s), ate %', v_fechados, v_ate; end if;
end $$;

-- ── CP8: o custo da ENTRADA no livro é o custo com frete ────
do $$
declare v_custo numeric;
begin
  select mc.unit_cost into v_custo
    from public.stock_movements m
    join public.stock_movement_costs mc on mc.movement_id = m.id
    join public.products p on p.id = m.product_id
   where m.reason = 'purchase' and p.code = 'CMP-CARO';

  if v_custo = 1166.67
    then raise notice 'CP8) OK: o livro guardou % — o custo com frete, nao o da nota', v_custo;
    else raise notice 'CP8) FALHA: custo % no livro', v_custo; end if;
end $$;

-- ── CP9: receber duas vezes, não ────────────────────────────
do $$
declare v_nota uuid;
begin
  select id into v_nota from public.purchases limit 1;
  begin
    perform public.receive_purchase(v_nota);
    raise notice 'CP9) FALHA: recebeu a mesma nota duas vezes';
  exception when check_violation then
    raise notice 'CP9) OK: nota ja recebida nao entra de novo no estoque';
  end;
end $$;

-- ── CP10: nota recebida não muda de conteúdo ────────────────
do $$
declare v_nota uuid; v_falhas text := '';
begin
  select id into v_nota from public.purchases limit 1;

  begin update public.purchases set freight_amount = 999 where id = v_nota;
        v_falhas := v_falhas || ' frete'; exception when others then null; end;
  begin update public.purchase_items set quantity = 99 where purchase_id = v_nota;
        v_falhas := v_falhas || ' item'; exception when others then null; end;
  begin delete from public.purchase_items where purchase_id = v_nota;
        v_falhas := v_falhas || ' apagou-item'; exception when others then null; end;
  begin insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost)
        select v_nota, p.id, 1, 1 from public.products p where p.code = 'CMP-BARATO' limit 1;
        v_falhas := v_falhas || ' novo-item'; exception when others then null; end;

  if v_falhas = ''
    then raise notice 'CP10) OK: nota recebida nao muda de conteudo';
    else raise notice 'CP10) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── CP11: e não se cancela ──────────────────────────────────
do $$
declare v_nota uuid;
begin
  select id into v_nota from public.purchases limit 1;
  begin
    perform public.cancel_purchase(v_nota);
    raise notice 'CP11) FALHA: cancelou nota ja recebida';
  exception when check_violation then
    raise notice 'CP11) OK: recebida nao se cancela — o caminho e a devolucao';
  end;
end $$;

-- ── CP12: segunda nota no mesmo dia não quebra o histórico ──
-- O índice de vigência não deixaria duas linhas com o mesmo `valid_from`;
-- neste caso a linha de hoje é atualizada no lugar.
do $$
declare v_nota uuid; v_vigentes int; v_custo numeric;
begin
  insert into public.purchases (supplier_id, condition_id, invoice_number)
  select s.id, c.id, '55502'
    from public.suppliers s, public.price_conditions c
   where s.name = 'Distribuidora de Teste' and c.is_default
  returning id into v_nota;

  insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost)
  select v_nota, p.id, 2, 1500 from public.products p where p.code = 'CMP-CARO';

  perform public.receive_purchase(v_nota);

  select count(*)::int into v_vigentes from public.product_costs pc
    join public.products p on p.id = pc.product_id
   where p.code = 'CMP-CARO' and pc.valid_to is null;

  select cost_price into v_custo from public.product_costs pc
    join public.products p on p.id = pc.product_id
   where p.code = 'CMP-CARO' and pc.valid_to is null;

  if v_vigentes = 1 and v_custo = 1500
    then raise notice 'CP12) OK: segunda nota do dia atualizou o custo vigente para %, sem duplicar', v_custo;
    else raise notice 'CP12) FALHA: % vigente(s), custo %', v_vigentes, v_custo; end if;
end $$;

-- ── CP13: a mesma nota do mesmo fornecedor, não ─────────────
do $$
begin
  begin
    insert into public.purchases (supplier_id, condition_id, invoice_number)
    select s.id, c.id, '55501'
      from public.suppliers s, public.price_conditions c
     where s.name = 'Distribuidora de Teste' and c.is_default;
    raise notice 'CP13) FALHA: lancou a mesma nota duas vezes';
  exception when unique_violation then
    raise notice 'CP13) OK: nota repetida do mesmo fornecedor recusada';
  end;
end $$;

-- ── CP14: nota sem item não entra no estoque ────────────────
do $$
declare v_nota uuid;
begin
  insert into public.purchases (supplier_id, condition_id)
  select s.id, c.id from public.suppliers s, public.price_conditions c
   where s.name = 'Distribuidora de Teste' and c.is_default
  returning id into v_nota;

  begin
    perform public.receive_purchase(v_nota);
    raise notice 'CP14) FALHA: recebeu nota vazia';
  exception when check_violation then
    raise notice 'CP14) OK: nota sem item nao entra no estoque';
  end;

  -- E essa, sim, se cancela: ainda é rascunho.
  if public.cancel_purchase(v_nota)
    then raise notice 'CP14b) OK: rascunho se cancela';
    else raise notice 'CP14b) FALHA: nao cancelou o rascunho'; end if;
end $$;

-- ── CP15: o vendedor não enxerga nota de compra ─────────────
-- Uma nota de entrada é custo da primeira à última linha.
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-00000000c002', false);

do $$
declare v_notas int; v_itens int; v_saldo numeric; v_falhas text := '';
begin
  select count(*)::int into v_notas from public.purchases;
  select count(*)::int into v_itens from public.purchase_items;

  -- Mas o SALDO que a entrada gerou, sim: é o que ele precisa para
  -- responder ao cliente.
  select quantity into v_saldo from public.product_stock where code = 'CMP-CARO';

  begin
    perform public.receive_purchase((select id from public.purchases limit 1));
    v_falhas := ' recebeu';
  exception when others then null; end;

  if v_notas = 0 and v_itens = 0 and v_saldo = 3 and v_falhas = ''
    then raise notice 'CP15) OK: vendedor ve 0 nota e 0 item, mas ve o saldo %', v_saldo;
    else raise notice 'CP15) FALHA: notas % / itens % / saldo % / %',
         v_notas, v_itens, v_saldo, v_falhas; end if;
end $$;

-- ── CP16: anônimo não alcança ───────────────────────────────
do $$
declare v_falhas text := '';
begin
  reset role;
  set local role anon;
  begin perform 1 from public.purchases;      v_falhas := v_falhas || ' notas';
        exception when others then null; end;
  begin perform 1 from public.purchase_items; v_falhas := v_falhas || ' itens';
        exception when others then null; end;
  if v_falhas = ''
    then raise notice 'CP16) OK: anonimo sem privilegio em compras';
    else raise notice 'CP16) FALHA: alcancou ->%', v_falhas; end if;
end $$;

reset role;
