-- ============================================================
-- Estoque (migrations 20260903120000 e 20260903130000).
--
-- O que este arquivo prova:
--   · o saldo é a SOMA do livro, nunca um número digitado;
--   · a linha do livro não muda e não some — nem para o dono do banco;
--   · faturar o pedido baixa o estoque sozinho, uma vez só;
--   · kit baixa os COMPONENTES escolhidos, não o kit;
--   · item avulso não mexe em estoque nenhum;
--   · sem saldo o sistema deixa passar e fica negativo, de propósito;
--   · o vendedor lê o estoque, mas não lança nada;
--   · série vincula ao pedido faturado, e só ao produto certo.
--
-- Prefixo de UUID = número da suíte.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('21212121-0000-4000-8000-00000000e001','est.admin@teste.local','{"full_name":"Admin Estoque","role":"admin"}'),
 ('21212121-0000-4000-8000-00000000e002','est.vend@teste.local','{"full_name":"Vendedor Estoque","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = '21212121-0000-4000-8000-00000000e001';

insert into public.customers (name, city, state) values ('Cliente do Estoque', 'Londrina', 'PR');

-- Um drone (com série), duas peças e um kit montado com as duas peças.
insert into public.products (code, name, unit_id, sale_price, tracks_serial)
select 'EST-DRONE', 'Drone com serie', u.id, 12000, true from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'EST-BAT', 'Bateria', u.id, 900 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'EST-HEL', 'Helice', u.id, 60 from public.units u where u.code = 'UN';

-- O custo mora em `product_costs`, fora do alcance do vendedor (migration 1200).
insert into public.product_costs (product_id, cost_price)
select p.id, v.custo from public.products p
  join (values ('EST-DRONE', 8000), ('EST-BAT', 500), ('EST-HEL', 20)) as v(code, custo)
    on v.code = p.code;

insert into public.kits (code, name) values ('EST-KIT', 'Kit de campo');
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 1 from public.kits k, public.products p
 where k.code = 'EST-KIT' and p.code = 'EST-BAT';
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 4 from public.kits k, public.products p
 where k.code = 'EST-KIT' and p.code = 'EST-HEL';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e001', false);

-- ── ES1: produto sem movimento aparece com saldo zero ───────
-- Sumir da lista seria pior: some justamente o que ninguém contou.
do $$
declare v_saldo numeric; v_encontrado int;
begin
  select count(*)::int, coalesce(max(quantity), -1) into v_encontrado, v_saldo
    from public.product_stock where code = 'EST-DRONE';
  if v_encontrado = 1 and v_saldo = 0
    then raise notice 'ES1) OK: produto sem movimento aparece com saldo zero';
    else raise notice 'ES1) FALHA: encontrado % / saldo %', v_encontrado, v_saldo; end if;
end $$;

-- ── ES2: contagem inicial e entrada somam ───────────────────
do $$
declare v_saldo numeric;
begin
  perform public.register_stock_movement(
    (select id from public.products where code = 'EST-DRONE'), 'initial', 2, 'Contagem de abertura');
  perform public.register_stock_movement(
    (select id from public.products where code = 'EST-DRONE'), 'purchase', 3, 'Nota 1234');

  select quantity into v_saldo from public.product_stock where code = 'EST-DRONE';
  if v_saldo = 5
    then raise notice 'ES2) OK: 2 de contagem + 3 de compra = saldo %', v_saldo;
    else raise notice 'ES2) FALHA: saldo % (esperado 5)', v_saldo; end if;
end $$;

-- ── ES3: perda entra negativa mesmo digitada positiva ───────
-- Errar o sinal de uma perda infla o estoque em silêncio. O sinal é do
-- banco, não da tela.
do $$
declare v_saldo numeric; v_lancado numeric;
begin
  perform public.register_stock_movement(
    (select id from public.products where code = 'EST-DRONE'), 'loss', 1, 'Queda no teste');

  select quantity into v_lancado from public.stock_movements
   where reason = 'loss' order by created_at desc limit 1;
  select quantity into v_saldo from public.product_stock where code = 'EST-DRONE';

  if v_lancado = -1 and v_saldo = 4
    then raise notice 'ES3) OK: perda digitada como 1 virou % — saldo %', v_lancado, v_saldo;
    else raise notice 'ES3) FALHA: lancado % / saldo %', v_lancado, v_saldo; end if;
end $$;

-- ── ES4: ajuste vai para os dois lados ──────────────────────
do $$
declare v_saldo numeric;
begin
  perform public.register_stock_movement(
    (select id from public.products where code = 'EST-DRONE'), 'adjustment', -1, 'Recontagem');
  select quantity into v_saldo from public.product_stock where code = 'EST-DRONE';
  if v_saldo = 3
    then raise notice 'ES4) OK: ajuste negativo aceito — saldo %', v_saldo;
    else raise notice 'ES4) FALHA: saldo % (esperado 3)', v_saldo; end if;
end $$;

-- ── ES5: 'sale' não se lança à mão ──────────────────────────
-- Deixar a tela lançar venda abriria a porta para o estoque discordar da
-- nota fiscal — o oposto da decisão de baixar no faturamento.
do $$
declare v_erro text;
begin
  begin
    perform public.register_stock_movement(
      (select id from public.products where code = 'EST-DRONE'), 'sale', -1, null);
    raise notice 'ES5) FALHA: lancou venda a mao';
  exception when check_violation then
    raise notice 'ES5) OK: venda a mao recusada — nasce do pedido faturado';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'ES5) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── ES6: quantidade zero é ruído no livro ───────────────────
do $$
begin
  begin
    perform public.register_stock_movement(
      (select id from public.products where code = 'EST-BAT'), 'adjustment', 0, null);
    raise notice 'ES6) FALHA: aceitou lancamento de zero';
  exception when check_violation then
    raise notice 'ES6) OK: lancamento de zero recusado';
  end;
end $$;

-- ── ES7: a linha do livro não muda e não some ───────────────
-- Vale para TODO MUNDO, inclusive fora da RLS. Um livro que o dono
-- reescreve não é livro.
do $$
declare v_falhas text := ''; v_id uuid;
begin
  reset role;
  select id into v_id from public.stock_movements limit 1;

  begin update public.stock_movements set quantity = 999 where id = v_id;
        v_falhas := v_falhas || ' alterou'; exception when others then null; end;
  begin delete from public.stock_movements where id = v_id;
        v_falhas := v_falhas || ' apagou'; exception when others then null; end;

  if v_falhas = ''
    then raise notice 'ES7) OK: lancamento nao muda e nao some, nem para o dono do banco';
    else raise notice 'ES7) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── ES8: o vendedor LÊ o estoque ────────────────────────────
-- Negar isso a ele é empurrar a pergunta "tem em estoque?" para o WhatsApp.
set role authenticated;
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e002', false);

do $$
declare v_saldo numeric; v_movimentos int;
begin
  select quantity into v_saldo from public.product_stock where code = 'EST-DRONE';
  select count(*)::int into v_movimentos from public.stock_movements;
  if v_saldo = 3 and v_movimentos >= 4
    then raise notice 'ES8) OK: vendedor ve saldo % e % lancamento(s)', v_saldo, v_movimentos;
    else raise notice 'ES8) FALHA: saldo % / movimentos %', v_saldo, v_movimentos; end if;
end $$;

-- ── ES9: mas não lança nada ─────────────────────────────────
do $$
declare v_falhas text := '';
begin
  begin
    perform public.register_stock_movement(
      (select id from public.products where code = 'EST-DRONE'), 'adjustment', 10, null);
    v_falhas := v_falhas || ' pela funcao';
  exception when insufficient_privilege then null;
  when others then v_falhas := v_falhas || ' funcao-erro-errado'; end;

  begin
    insert into public.stock_movements (product_id, reason, quantity)
    select id, 'adjustment', 10 from public.products where code = 'EST-DRONE';
    v_falhas := v_falhas || ' pelo insert';
  exception when others then null; end;

  if v_falhas = ''
    then raise notice 'ES9) OK: vendedor nao lanca estoque, nem pela funcao nem pelo insert';
    else raise notice 'ES9) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── Pedido do vendedor: 1 drone + 2 kits + 1 item avulso ────
do $$
declare v_q uuid; v_o uuid; v_comp jsonb;
begin
  insert into public.quotes (customer_id, owner_id)
  select c.id, '21212121-0000-4000-8000-00000000e002'
    from public.customers c where c.name = 'Cliente do Estoque'
  returning id into v_q;

  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
  select v_q, p.id, p.name, p.code, 1, 12000, 1 from public.products p where p.code = 'EST-DRONE';

  -- Kit com os dois componentes escolhidos, mais um terceiro NÃO
  -- escolhido: o não escolhido não pode sair do estoque.
  select jsonb_build_array(
           jsonb_build_object('product_id', (select id from public.products where code='EST-BAT'),
                              'code','EST-BAT','name','Bateria','unit','UN','brand',null,
                              'quantity_milli', 1000, 'unit_price_cents', 90000,
                              'item_type','required','selected', true),
           jsonb_build_object('product_id', (select id from public.products where code='EST-HEL'),
                              'code','EST-HEL','name','Helice','unit','UN','brand',null,
                              'quantity_milli', 4000, 'unit_price_cents', 6000,
                              'item_type','required','selected', true),
           jsonb_build_object('product_id', (select id from public.products where code='EST-DRONE'),
                              'code','EST-DRONE','name','Drone com serie','unit','UN','brand',null,
                              'quantity_milli', 1000, 'unit_price_cents', 1200000,
                              'item_type','optional','selected', false)
         ) into v_comp;

  insert into public.quote_items (quote_id, kind, kit_id, name_snapshot, code_snapshot,
                                  quantity, unit_price, sort_order, components_snapshot)
  select v_q, 'kit', k.id, k.name, k.code, 2, 1140, 2, v_comp
    from public.kits k where k.code = 'EST-KIT';

  insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price, sort_order)
  values (v_q, 'custom', 'Servico de instalacao', 1, 500, 3);

  update public.quotes set status = 'sent'     where id = v_q;
  update public.quotes set status = 'approved' where id = v_q;

  select public.create_order_from_quote(v_q) into v_o;
  update public.orders set status = 'picking' where id = v_o;
  raise notice 'ESX) pedido de estoque preparado';
end $$;

-- ── ES10: faturar baixa o estoque sozinho ───────────────────
do $$
declare v_o uuid; v_drone numeric; v_bat numeric; v_hel numeric; v_custom int;
begin
  select id into v_o from public.orders
   where customer_id = (select id from public.customers where name='Cliente do Estoque');

  update public.orders set status = 'invoiced' where id = v_o;

  select quantity into v_drone from public.product_stock where code = 'EST-DRONE';
  select quantity into v_bat   from public.product_stock where code = 'EST-BAT';
  select quantity into v_hel   from public.product_stock where code = 'EST-HEL';

  -- Drone: 3 − 1 = 2. Bateria: 0 − (1 × 2 kits) = −2.
  -- Hélice: 0 − (4 × 2 kits) = −8. Serviço avulso: nada.
  select count(*)::int into v_custom from public.stock_movements m
    join public.order_items oi on oi.id = m.order_item_id
   where oi.kind = 'custom';

  if v_drone = 2 and v_bat = -2 and v_hel = -8 and v_custom = 0
    then raise notice 'ES10) OK: drone %, bateria %, helice % — avulso nao mexeu no estoque', v_drone, v_bat, v_hel;
    else raise notice 'ES10) FALHA: drone % / bateria % / helice % / avulso %', v_drone, v_bat, v_hel, v_custom; end if;
end $$;

-- ── ES11: o opcional não escolhido não saiu ─────────────────
do $$
declare v_saidas int;
begin
  select count(*)::int into v_saidas from public.stock_movements m
    join public.order_items oi on oi.id = m.order_item_id
   where oi.kind = 'kit'
     and m.product_id = (select id from public.products where code = 'EST-DRONE');
  if v_saidas = 0
    then raise notice 'ES11) OK: componente opcional nao escolhido nao saiu do estoque';
    else raise notice 'ES11) FALHA: % saida(s) do opcional', v_saidas; end if;
end $$;

-- ── ES12: sem saldo, passa e fica negativo ──────────────────
-- É a decisão comercial: avisar, não travar. Enquanto a contagem inicial
-- não estiver feita, barrar o faturamento pararia a empresa.
do $$
declare v_negativos int;
begin
  -- Só os produtos desta suíte: a suíte de pedidos também fatura, e o
  -- gatilho é do banco inteiro — contar tudo mediria o vizinho.
  select count(*)::int into v_negativos from public.product_stock
   where quantity < 0 and code like 'EST-%';
  if v_negativos = 2
    then raise notice 'ES12) OK: faturou sem saldo e deixou % produto(s) negativos, a acertar', v_negativos;
    else raise notice 'ES12) FALHA: % produto(s) negativos (esperado 2)', v_negativos; end if;
end $$;

-- ── ES13: o custo do momento fica congelado ─────────────────
-- O custo do catálogo muda; o valor do que saiu não pode ser recalculado
-- com o custo de outro mês.
do $$
declare v_custo numeric;
begin
  reset role;
  update public.product_costs set cost_price = 99999
   where product_id = (select id from public.products where code = 'EST-DRONE');

  select mc.unit_cost into v_custo
    from public.stock_movements m
    join public.stock_movement_costs mc on mc.movement_id = m.id
   where m.reason = 'sale'
     and m.product_id = (select id from public.products where code = 'EST-DRONE');

  if v_custo = 8000
    then raise notice 'ES13) OK: custo da saida congelado em % apesar do catalogo mudar', v_custo;
    else raise notice 'ES13) FALHA: custo % (esperado 8000)', v_custo; end if;
end $$;

-- ── ES13b: e o vendedor NÃO lê esse custo ───────────────────
-- É o motivo de o custo morar em tabela irmã: o vendedor precisa do
-- saldo, e o saldo não pode vir junto com quanto a empresa paga.
set role authenticated;
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e002', false);

do $$
declare v_admin int; v_vendedor int;
begin
  select count(*)::int into v_vendedor from public.stock_movement_costs;

  reset role;
  select count(*)::int into v_admin from public.stock_movement_costs;

  if v_vendedor = 0 and v_admin > 0
    then raise notice 'ES13b) OK: administrador ve % custo(s) de lancamento; vendedor ve %', v_admin, v_vendedor;
    else raise notice 'ES13b) FALHA: admin % / vendedor %', v_admin, v_vendedor; end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e001', false);

-- ── ES14: a baixa não acontece duas vezes ───────────────────
do $$
declare v_o uuid; v_antes int; v_depois int;
begin
  select id into v_o from public.orders
   where customer_id = (select id from public.customers where name='Cliente do Estoque');

  select count(*)::int into v_antes from public.stock_movements where order_id = v_o;
  update public.orders set status = 'delivered' where id = v_o;
  update public.orders set invoiced_at = now()  where id = v_o;
  select count(*)::int into v_depois from public.stock_movements where order_id = v_o;

  if v_antes = v_depois
    then raise notice 'ES14) OK: % lancamento(s), nenhuma baixa repetida', v_depois;
    else raise notice 'ES14) FALHA: antes % / depois %', v_antes, v_depois; end if;
end $$;

-- ── ES15: devolução estorna, sem apagar nada ────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e001', false);

do $$
declare v_o uuid; v_quantos int; v_drone numeric; v_linhas int;
begin
  select id into v_o from public.orders
   where customer_id = (select id from public.customers where name='Cliente do Estoque');

  select public.return_order_stock(v_o, 'Cliente desistiu') into v_quantos;

  select quantity into v_drone from public.product_stock where code = 'EST-DRONE';
  select count(*)::int into v_linhas from public.stock_movements where order_id = v_o;

  -- Voltou ao saldo de antes do faturamento (3), e as saídas continuam
  -- no livro: 3 saídas + 3 estornos.
  if v_drone = 3 and v_quantos = 3 and v_linhas = 6
    then raise notice 'ES15) OK: % estorno(s), saldo do drone de volta a %, livro com % linhas', v_quantos, v_drone, v_linhas;
    else raise notice 'ES15) FALHA: drone % / estornos % / linhas %', v_drone, v_quantos, v_linhas; end if;
end $$;

-- ── ES16: devolver duas vezes, não ──────────────────────────
do $$
declare v_o uuid;
begin
  select id into v_o from public.orders
   where customer_id = (select id from public.customers where name='Cliente do Estoque');
  begin
    perform public.return_order_stock(v_o, null);
    raise notice 'ES16) FALHA: devolveu duas vezes';
  exception when unique_violation then
    raise notice 'ES16) OK: segunda devolucao do mesmo pedido recusada';
  end;
end $$;

-- ============================================================
-- Números de série
-- ============================================================

-- ── SN1: série normaliza e não repete no mesmo produto ──────
do $$
declare v_lida text; v_erro text;
begin
  insert into public.product_serials (product_id, serial)
  select id, '  1abc-7742  ' from public.products where code = 'EST-DRONE';

  select serial into v_lida from public.product_serials limit 1;

  begin
    insert into public.product_serials (product_id, serial)
    select id, '1abc-7742' from public.products where code = 'EST-DRONE';
    raise notice 'SN1) FALHA: aceitou serie repetida';
  exception when unique_violation then
    raise notice 'SN1) OK: "  1abc-7742  " virou "%" e a repetida foi barrada', v_lida;
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'SN1) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── SN2: a mesma série em OUTRO produto é permitida ─────────
-- Fabricantes diferentes usam formatos que podem coincidir; barrar isso
-- rejeitaria cadastro legítimo.
do $$
declare v_quantos int;
begin
  insert into public.product_serials (product_id, serial)
  select id, '1ABC-7742' from public.products where code = 'EST-BAT';
  select count(*)::int into v_quantos from public.product_serials where upper(serial) = '1ABC-7742';
  if v_quantos = 2
    then raise notice 'SN2) OK: a mesma serie convive em produtos diferentes (% linhas)', v_quantos;
    else raise notice 'SN2) FALHA: % linha(s)', v_quantos; end if;
end $$;

-- ── SN3: aparelho vincula ao pedido faturado ────────────────
do $$
declare v_serial uuid; v_item uuid; v_status public.serial_status; v_vendido timestamptz;
begin
  select id into v_serial from public.product_serials
   where product_id = (select id from public.products where code = 'EST-DRONE');

  select oi.id into v_item from public.order_items oi
    join public.orders o on o.id = oi.order_id
   where o.customer_id = (select id from public.customers where name='Cliente do Estoque')
     and oi.kind = 'product';

  perform public.assign_serial_to_order(v_serial, v_item);

  select status, sold_at into v_status, v_vendido
    from public.product_serials where id = v_serial;

  if v_status = 'sold' and v_vendido is not null
    then raise notice 'SN3) OK: aparelho vendido e a data de saida foi carimbada sozinha';
    else raise notice 'SN3) FALHA: status % / sold_at %', v_status, v_vendido; end if;
end $$;

-- ── SN4: o aparelho errado não entra no item ────────────────
do $$
declare v_serial uuid; v_item uuid;
begin
  select id into v_serial from public.product_serials
   where product_id = (select id from public.products where code = 'EST-BAT');

  select oi.id into v_item from public.order_items oi
    join public.orders o on o.id = oi.order_id
   where o.customer_id = (select id from public.customers where name='Cliente do Estoque')
     and oi.kind = 'product';

  begin
    perform public.assign_serial_to_order(v_serial, v_item);
    raise notice 'SN4) FALHA: vinculou aparelho de outro produto';
  exception when check_violation then
    raise notice 'SN4) OK: aparelho de outro produto recusado no item';
  end;
end $$;

-- ── SN5: aparelho já vendido não se vincula de novo ─────────
do $$
declare v_serial uuid; v_item uuid;
begin
  select id into v_serial from public.product_serials
   where product_id = (select id from public.products where code = 'EST-DRONE');
  select oi.id into v_item from public.order_items oi
    join public.orders o on o.id = oi.order_id
   where o.customer_id = (select id from public.customers where name='Cliente do Estoque')
     and oi.kind = 'product';
  begin
    perform public.assign_serial_to_order(v_serial, v_item);
    raise notice 'SN5) FALHA: vinculou aparelho ja vendido';
  exception when check_violation then
    raise notice 'SN5) OK: aparelho ja vendido nao se vincula de novo';
  end;
end $$;

-- ── SN6: desvincular devolve ao galpão ──────────────────────
do $$
declare v_serial uuid; v_status public.serial_status; v_pedido uuid; v_vendido timestamptz;
begin
  select id into v_serial from public.product_serials
   where product_id = (select id from public.products where code = 'EST-DRONE');

  perform public.release_serial(v_serial);

  select status, order_id, sold_at into v_status, v_pedido, v_vendido
    from public.product_serials where id = v_serial;

  if v_status = 'in_stock' and v_pedido is null and v_vendido is null
    then raise notice 'SN6) OK: aparelho de volta ao galpao, sem vinculo e sem data';
    else raise notice 'SN6) FALHA: status % / pedido % / data %', v_status, v_pedido, v_vendido; end if;
end $$;

-- ── SN7: o vendedor lê os aparelhos, mas não cadastra ───────
select set_config('request.jwt.claim.sub', '21212121-0000-4000-8000-00000000e002', false);

do $$
declare v_vistos int; v_falhas text := '';
begin
  select count(*)::int into v_vistos from public.product_serials;

  begin
    insert into public.product_serials (product_id, serial)
    select id, 'VEND-001' from public.products where code = 'EST-DRONE';
    v_falhas := v_falhas || ' cadastrou'; exception when others then null; end;
  begin
    update public.product_serials set notes = 'mexido pelo vendedor';
    if found then v_falhas := v_falhas || ' alterou'; end if;
    exception when others then null; end;
  begin
    delete from public.product_serials;
    if found then v_falhas := v_falhas || ' apagou'; end if;
    exception when others then null; end;

  if v_vistos >= 2 and v_falhas = ''
    then raise notice 'SN7) OK: vendedor ve % aparelho(s) e nao cadastra, nao altera, nao apaga', v_vistos;
    else raise notice 'SN7) FALHA: viu % / passou em ->%', v_vistos, v_falhas; end if;
end $$;

-- ── SN8: anônimo não alcança estoque nem série ──────────────
do $$
declare v_falhas text := '';
begin
  reset role;
  set local role anon;
  begin perform 1 from public.stock_movements; v_falhas := v_falhas || ' movimentos';
        exception when others then null; end;
  begin perform 1 from public.product_serials;  v_falhas := v_falhas || ' series';
        exception when others then null; end;
  if v_falhas = ''
    then raise notice 'SN8) OK: anonimo sem privilegio em estoque e em serie';
    else raise notice 'SN8) FALHA: alcancou ->%', v_falhas; end if;
end $$;

reset role;
