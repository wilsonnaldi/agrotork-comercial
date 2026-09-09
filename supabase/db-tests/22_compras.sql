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

-- ════════════════════════════════════════════════════════════
-- CP17–CP23) Guardas da migration 20260909110000 (A5, A7, A8, A9, A14, A17)
-- ════════════════════════════════════════════════════════════
reset role;
insert into public.products (code, name, unit_id, sale_price)
select 'CMP-TERCEIRO', 'Terceira peca', u.id, 0 from public.units u where u.code = 'UN';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-00000000c001', false);

-- Nota nova do administrador, com três linhas iguais e frete 100: o
-- rateio linha a linha daria 33,33 × 3 = 99,99.
do $$
begin
  insert into public.purchases (id, supplier_id, condition_id, invoice_number, freight_amount)
  select '22222222-0000-4000-8000-00000000cc17', s.id, c.id, '55517', 100
    from public.suppliers s, public.price_conditions c
   where s.name = 'Distribuidora de Teste' and c.is_default;
  insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost)
  select '22222222-0000-4000-8000-00000000cc17', p.id, 1, 10
    from public.products p where p.code in ('CMP-CARO', 'CMP-BARATO', 'CMP-TERCEIRO');
end $$;

-- CP17) item de nota não muda de nota.
do $$
declare v_outra uuid; v_item uuid; v_antes int; v_depois int;
begin
  select id into v_outra from public.purchases where id <> '22222222-0000-4000-8000-00000000cc17' and status = 'draft' limit 1;
  if v_outra is null then
    insert into public.purchases (supplier_id, condition_id)
    select s.id, c.id from public.suppliers s, public.price_conditions c
     where s.name = 'Distribuidora de Teste' and c.is_default returning id into v_outra;
  end if;
  select id into v_item from public.purchase_items where purchase_id = '22222222-0000-4000-8000-00000000cc17' limit 1;
  select count(*) into v_antes from public.purchase_items where purchase_id = '22222222-0000-4000-8000-00000000cc17';
  begin
    update public.purchase_items set purchase_id = v_outra where id = v_item;
    raise notice 'CP17) FALHA: item mudou de nota';
  exception when check_violation then
    select count(*) into v_depois from public.purchase_items where purchase_id = '22222222-0000-4000-8000-00000000cc17';
    if v_antes = v_depois then raise notice 'CP17) OK: item nao muda de nota (% linha(s) continuam na origem)', v_depois;
    else raise notice 'CP17) FALHA: origem perdeu linha'; end if;
  end;
end $$;

-- CP18) o contador de notas é interno: nem o administrador logado lê/escreve.
do $$
declare v_falhas text := ''; v_rls boolean;
begin
  select relrowsecurity into v_rls from pg_class where oid = 'public.purchase_sequences'::regclass;
  begin perform 1 from public.purchase_sequences; v_falhas := v_falhas || ' leu';
        exception when insufficient_privilege then null; end;
  begin update public.purchase_sequences set last_number = 0; v_falhas := v_falhas || ' escreveu';
        exception when insufficient_privilege then null; end;
  if v_rls and v_falhas = '' then raise notice 'CP18) OK: purchase_sequences com RLS e sem privilegio para a API';
  else raise notice 'CP18) FALHA: rls=% ->%', v_rls, v_falhas; end if;
end $$;

-- CP19) o total escrito direto vira recálculo.
do $$
declare v_total numeric; v_itens numeric;
begin
  update public.purchases set total = 1, items_total = 1 where id = '22222222-0000-4000-8000-00000000cc17';
  select total, items_total into v_total, v_itens from public.purchases where id = '22222222-0000-4000-8000-00000000cc17';
  if v_itens = 30 and v_total = 130
    then raise notice 'CP19) OK: total direto foi recalculado (itens % + frete 100 = %)', v_itens, v_total;
    else raise notice 'CP19) FALHA: itens % / total %', v_itens, v_total; end if;
end $$;

-- CP20) rascunho NÃO vira `received` por UPDATE direto — e não nasce conta a pagar.
do $$
declare v_status public.purchase_status; v_titulos int;
begin
  begin
    update public.purchases set status = 'received' where id = '22222222-0000-4000-8000-00000000cc17';
  exception when restrict_violation then null; end;
  select status into v_status from public.purchases where id = '22222222-0000-4000-8000-00000000cc17';
  select count(*) into v_titulos from public.financial_entries where purchase_id = '22222222-0000-4000-8000-00000000cc17';
  if v_status = 'draft' and v_titulos = 0
    then raise notice 'CP20) OK: status so anda por receive_purchase(); nenhum titulo criado';
    else raise notice 'CP20) FALHA: status % / % titulo(s)', v_status, v_titulos; end if;
end $$;

-- CP21) rateio fecha o centavo: 3 linhas iguais, frete 100 → 33,34 + 33,33 + 33,33.
do $$
declare v_soma numeric; v_itens int;
begin
  v_itens := public.receive_purchase('22222222-0000-4000-8000-00000000cc17');
  select sum(freight_share) into v_soma from public.purchase_items where purchase_id = '22222222-0000-4000-8000-00000000cc17';
  if v_itens = 3 and v_soma = 100
    then raise notice 'CP21) OK: rateio de 3 linhas soma exatamente o frete (%)', v_soma;
    else raise notice 'CP21) FALHA: % itens, rateio somou %', v_itens, v_soma; end if;
end $$;

-- CP22) nota recebida NÃO volta a rascunho — logo não é recebida de novo.
do $$
declare v_status public.purchase_status; v_mov int;
begin
  begin
    update public.purchases set status = 'draft' where id = '22222222-0000-4000-8000-00000000cc17';
  exception when restrict_violation then null; end;
  begin
    update public.purchases set invoice_key = repeat('9', 44) where id = '22222222-0000-4000-8000-00000000cc17';
  exception when restrict_violation then null; end;
  select status into v_status from public.purchases where id = '22222222-0000-4000-8000-00000000cc17';
  reset role;
  select count(*) into v_mov from public.stock_movements where notes = 'Entrada ' || (select number from public.purchases where id = '22222222-0000-4000-8000-00000000cc17');
  set role authenticated;
  if v_status = 'received' and v_mov = 3
     and (select invoice_key from public.purchases where id = '22222222-0000-4000-8000-00000000cc17') is null
    then raise notice 'CP22) OK: nota recebida continua recebida, chave congelada, % lancamento(s) no livro', v_mov;
    else raise notice 'CP22) FALHA: status % / % lancamento(s)', v_status, v_mov; end if;
end $$;

-- CP23) trilha da nota: purchase.created, purchase.received, itens
--       adicionados — e NENHUM evento de totais nem de rateio.
do $$
declare v_created int; v_received int; v_items int; v_fantasma int; v_admin_insere boolean := false;
begin
  reset role;
  select count(*) into v_created  from public.audit_log where entity_type='purchase' and entity_id='22222222-0000-4000-8000-00000000cc17' and action='purchase.created';
  select count(*) into v_received from public.audit_log where entity_type='purchase' and entity_id='22222222-0000-4000-8000-00000000cc17' and action='purchase.received';
  select count(*) into v_items    from public.audit_log where entity_type='purchase_item' and parent_id='22222222-0000-4000-8000-00000000cc17' and action='purchase.item_added';
  select count(*) into v_fantasma from public.audit_log
   where (entity_type='purchase' and entity_id='22222222-0000-4000-8000-00000000cc17' and changed_fields && array['items_total','total'])
      or (entity_type='purchase_item' and parent_id='22222222-0000-4000-8000-00000000cc17' and action='purchase.item_changed');
  set role authenticated;
  -- A17: o administrador não insere no livro por fora da função.
  begin
    insert into public.stock_movements (product_id, reason, quantity)
    select id, 'sale', -1 from public.products where code = 'CMP-CARO';
    v_admin_insere := true;
  exception when others then null; end;
  if v_created = 1 and v_received = 1 and v_items = 3 and v_fantasma = 0 and not v_admin_insere
    then raise notice 'CP23) OK: trilha da nota sem fantasma (1 created, 1 received, 3 item_added); livro so pela funcao';
    else raise notice 'CP23) FALHA: created=% received=% items=% fantasma=% admin_insere=%', v_created, v_received, v_items, v_fantasma, v_admin_insere; end if;
end $$;

reset role;
