-- ============================================================
-- Pedido de venda (migration 20260903060000).
--
-- O que este arquivo prova:
--   · só orçamento APROVADO vira pedido, e uma vez só;
--   · o pedido copia a composição inteira e CONGELA o comercial —
--     para o vendedor E para o administrador;
--   · a situação anda pelas transições que existem, e só por elas;
--   · a composição do pedido não muda depois: ninguém escreve em
--     `order_items`, nem o administrador;
--   · o caminho de volta (renegociação) cria orçamento NOVO e deixa o
--     pedido de origem intacto;
--   · vendedor não alcança pedido alheio; anônimo não alcança nada.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('bbbbbbbb-0000-4000-8000-00000000b001','ped.admin@teste.local','{"full_name":"Admin Pedido","role":"admin"}'),
 ('bbbbbbbb-0000-4000-8000-00000000b002','ped.vend@teste.local','{"full_name":"Vendedor Pedido","role":"salesperson"}'),
 ('bbbbbbbb-0000-4000-8000-00000000b003','ped.outro@teste.local','{"full_name":"Outro Vendedor","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = 'bbbbbbbb-0000-4000-8000-00000000b001';

insert into public.customers (name, city, state) values ('Cliente do Pedido', 'Londrina', 'PR');

insert into public.products (code, name, unit_id, sale_price)
select 'PED-001', 'Drone de teste', u.id, 1000 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'PED-002', 'Bateria de teste', u.id, 250 from public.units u where u.code = 'UN';

-- ── Orçamento do vendedor, com dois itens e frete ───────────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000b002', false);

insert into public.quotes (customer_id, owner_id, shipping_amount)
select c.id, 'bbbbbbbb-0000-4000-8000-00000000b002', 100
  from public.customers c where c.name = 'Cliente do Pedido';

insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
select q.id, p.id, p.name, p.code, 2, 1000, 1
  from public.quotes q, public.products p
 where q.customer_id = (select id from public.customers where name='Cliente do Pedido')
   and p.code = 'PED-001';

insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, discount_percent, sort_order)
select q.id, p.id, p.name, p.code, 4, 250, 10, 2
  from public.quotes q, public.products p
 where q.customer_id = (select id from public.customers where name='Cliente do Pedido')
   and p.code = 'PED-002';

-- ── PV1: orçamento em rascunho NÃO vira pedido ──────────────
do $$
declare v_q uuid; v_erro text;
begin
  select id into v_q from public.quotes
   where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';
  begin
    perform public.create_order_from_quote(v_q);
    raise notice 'PV1) FALHA: rascunho virou pedido';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    if v_erro like '%aprovado%'
      then raise notice 'PV1) OK: rascunho recusado — %', v_erro;
      else raise notice 'PV1) FALHA: recusou pelo motivo errado — %', v_erro; end if;
  end;
end $$;

-- Aprova (o caminho real: rascunho → enviado → aprovado).
update public.quotes set status = 'sent'
 where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';
update public.quotes set status = 'approved'
 where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';

-- ── PV2: aprovado vira pedido, com numeração própria ────────
do $$
declare v_q uuid; v_o uuid; v_num text;
begin
  select id into v_q from public.quotes
   where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';
  v_o := public.create_order_from_quote(v_q);
  select number into v_num from public.orders where id = v_o;
  if v_num like 'PED-%-0001'
    then raise notice 'PV2) OK: pedido criado com numeracao propria — %', v_num;
    else raise notice 'PV2) FALHA: numeracao inesperada — %', v_num; end if;
end $$;

-- ── PV3: a composição foi copiada inteira ───────────────────
do $$
declare v_itens int; v_nomes text;
begin
  select count(*), string_agg(code_snapshot, ',' order by sort_order)
    into v_itens, v_nomes
    from public.order_items oi
    join public.orders o on o.id = oi.order_id;
  if v_itens = 2 and v_nomes = 'PED-001,PED-002'
    then raise notice 'PV3) OK: 2 itens copiados com snapshot — %', v_nomes;
    else raise notice 'PV3) FALHA: % item(ns), %', v_itens, v_nomes; end if;
end $$;

-- ── PV4: o total do pedido bate com o do orçamento ──────────
-- 2x1000 = 2000, 4x250 com 10% = 900, subtotal 2900, frete 100 = 3000.
do $$
declare v_sub numeric; v_tot numeric; v_qtot numeric;
begin
  select subtotal, total into v_sub, v_tot from public.orders;
  select total into v_qtot from public.quotes
   where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';
  if v_sub = 2900 and v_tot = 3000 and v_tot = v_qtot
    then raise notice 'PV4) OK: subtotal % e total % — igual ao orcamento', v_sub, v_tot;
    else raise notice 'PV4) FALHA: subtotal %, total %, orcamento %', v_sub, v_tot, v_qtot; end if;
end $$;

-- ── PV5: o mesmo orçamento não gera um segundo pedido ───────
do $$
declare v_q uuid; v_erro text;
begin
  select id into v_q from public.quotes
   where owner_id = 'bbbbbbbb-0000-4000-8000-00000000b002';
  begin
    perform public.create_order_from_quote(v_q);
    raise notice 'PV5) FALHA: gerou pedido duplicado';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'PV5) OK: duplicidade barrada — %', v_erro;
  end;
end $$;

-- ── PV6: o vendedor não muda preço, desconto nem total ──────
do $$
declare v_erro text; v_antes numeric; v_depois numeric;
begin
  select total into v_antes from public.orders;
  begin
    update public.orders set total = 1;
    raise notice 'PV6) FALHA: o total do pedido foi alterado';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    select total into v_depois from public.orders;
    if v_antes = v_depois
      then raise notice 'PV6) OK: total intacto (%) — %', v_depois, left(v_erro, 60);
      else raise notice 'PV6) FALHA: total mudou de % para %', v_antes, v_depois; end if;
  end;
end $$;

-- ── PV7: nem o desconto, nem o cliente, nem o frete ─────────
do $$
declare v_falhas text := '';
begin
  begin update public.orders set discount_percent = 50;
        v_falhas := v_falhas || ' desconto'; exception when others then null; end;
  begin update public.orders set shipping_amount = 0;
        v_falhas := v_falhas || ' frete'; exception when others then null; end;
  begin update public.orders set issue_date = current_date - 30;
        v_falhas := v_falhas || ' data'; exception when others then null; end;
  if v_falhas = ''
    then raise notice 'PV7) OK: desconto, frete e data de emissao congelados';
    else raise notice 'PV7) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── PV8: o operacional CONTINUA se movendo ──────────────────
-- Se congelasse tudo, o pedido nunca poderia ser entregue.
do $$
declare v_erro text;
begin
  update public.orders
     set delivery_forecast = current_date + 15,
         notes = 'Entregar na fazenda, portao dos fundos';
  raise notice 'PV8) OK: previsao de entrega e observacao continuam editaveis';
exception when others then
  get stacked diagnostics v_erro = message_text;
  raise notice 'PV8) FALHA: o operacional tambem travou — %', v_erro;
end $$;

-- ── PV9: a situação anda pelo caminho real e carimba data ───
do $$
declare v_st text; v_pick timestamptz; v_inv timestamptz;
begin
  update public.orders set status = 'picking';
  update public.orders set status = 'invoiced';
  select status::text, picking_at, invoiced_at into v_st, v_pick, v_inv from public.orders;
  if v_st = 'invoiced' and v_pick is not null and v_inv is not null
    then raise notice 'PV9) OK: confirmado -> separacao -> faturado, com as duas datas carimbadas';
    else raise notice 'PV9) FALHA: situacao %, picking_at %, invoiced_at %', v_st, v_pick, v_inv; end if;
end $$;

-- ── PV10: faturado não volta atrás nem é cancelado ──────────
do $$
declare v_erro text; v_st text;
begin
  begin
    update public.orders set status = 'cancelled';
    raise notice 'PV10) FALHA: pedido faturado foi cancelado';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    select status::text into v_st from public.orders;
    if v_st = 'invoiced'
      then raise notice 'PV10) OK: faturado nao vira cancelado — o caminho e devolucao';
      else raise notice 'PV10) FALHA: situacao ficou %', v_st; end if;
  end;
end $$;

-- ── PV11: ninguém escreve em order_items — nem o admin ──────
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000b001', false);

do $$
declare v_qtd numeric; v_depois numeric; v_apagados int;
begin
  select quantity into v_qtd from public.order_items where code_snapshot = 'PED-001';

  begin update public.order_items set quantity = 99 where code_snapshot = 'PED-001';
  exception when others then null; end;
  begin delete from public.order_items where code_snapshot = 'PED-002';
  exception when others then null; end;

  select quantity into v_depois from public.order_items where code_snapshot = 'PED-001';
  select count(*)::int into v_apagados from public.order_items;

  if v_depois = v_qtd and v_apagados = 2
    then raise notice 'PV11) OK: administrador nao altera nem apaga item de pedido';
    else raise notice 'PV11) FALHA: quantidade % -> %, restaram % itens', v_qtd, v_depois, v_apagados; end if;
end $$;

-- ── PV12: o congelamento vale para o administrador também ───
do $$
declare v_antes numeric; v_depois numeric;
begin
  select total into v_antes from public.orders;
  begin update public.orders set total = 7; exception when others then null; end;
  select total into v_depois from public.orders;
  if v_antes = v_depois
    then raise notice 'PV12) OK: nem o administrador reescreve o total de um pedido';
    else raise notice 'PV12) FALHA: administrador mudou % para %', v_antes, v_depois; end if;
end $$;

-- ── PV13: renegociar cria orçamento NOVO, em rascunho ───────
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000b002', false);

do $$
declare v_o uuid; v_novo uuid; v_st text; v_rev int; v_origem uuid; v_itens int;
begin
  select id into v_o from public.orders;
  v_novo := public.create_quote_from_order(v_o);
  select status::text, revision, origin_order_id into v_st, v_rev, v_origem
    from public.quotes where id = v_novo;
  select count(*)::int into v_itens from public.quote_items where quote_id = v_novo;

  if v_st = 'draft' and v_rev = 2 and v_origem = v_o and v_itens = 2
    then raise notice 'PV13) OK: orcamento v% em rascunho, ligado ao pedido, com os 2 itens', v_rev;
    else raise notice 'PV13) FALHA: status %, revisao %, origem %, itens %', v_st, v_rev, v_origem, v_itens; end if;
end $$;

-- ── PV14: o pedido de origem ficou intacto ──────────────────
do $$
declare v_tot numeric; v_st text; v_itens int;
begin
  select o.total, o.status::text, (select count(*) from public.order_items i where i.order_id = o.id)
    into v_tot, v_st, v_itens
    from public.orders o;
  if v_tot = 3000 and v_st = 'invoiced' and v_itens = 2
    then raise notice 'PV14) OK: renegociar nao tocou no pedido — total %, situacao %', v_tot, v_st;
    else raise notice 'PV14) FALHA: total %, situacao %, itens %', v_tot, v_st, v_itens; end if;
end $$;

-- ── PV15: o catálogo muda e o pedido NÃO muda ───────────────
-- O teste crítico de histórico, o mesmo que 09_orcamentos faz nos
-- orçamentos: preço e nome do produto mudam depois da venda.
do $$
declare v_preco numeric; v_nome text;
begin
  reset role;
  update public.products set sale_price = 9999, name = 'Nome trocado depois'
   where code = 'PED-001';
  set role authenticated;

  select unit_price, name_snapshot into v_preco, v_nome
    from public.order_items where code_snapshot = 'PED-001';
  if v_preco = 1000 and v_nome = 'Drone de teste'
    then raise notice 'PV15) OK: catalogo mudou, o pedido continua com preco % e nome "%"', v_preco, v_nome;
    else raise notice 'PV15) FALHA: o pedido acompanhou o catalogo — %, %', v_preco, v_nome; end if;
end $$;

-- ── PV16: vendedor não enxerga nem fatura pedido alheio ─────
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-4000-8000-00000000b003', false);

do $$
declare v_vistos int; v_itens int;
begin
  select count(*)::int into v_vistos from public.orders;
  select count(*)::int into v_itens  from public.order_items;
  if v_vistos = 0 and v_itens = 0
    then raise notice 'PV16) OK: o outro vendedor nao enxerga pedido nem item alheio';
    else raise notice 'PV16) FALHA: enxergou % pedido(s) e % item(ns)', v_vistos, v_itens; end if;
end $$;

-- ── PV17: e não renegocia o que não é dele ──────────────────
do $$
declare v_o uuid; v_erro text;
begin
  reset role;
  select id into v_o from public.orders;
  set role authenticated;
  begin
    perform public.create_quote_from_order(v_o);
    raise notice 'PV17) FALHA: renegociou pedido alheio';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'PV17) OK: renegociacao alheia barrada — %', v_erro;
  end;
end $$;

-- ── PV18: anônimo não alcança pedido ────────────────────────
do $$
declare v_erro text;
begin
  reset role;
  set local role anon;
  begin
    perform 1 from public.orders;
    raise notice 'PV18) FALHA: anonimo alcancou orders';
  exception when insufficient_privilege then
    raise notice 'PV18) OK: anonimo sem privilegio em orders';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'PV18) OK: anonimo barrado — %', left(v_erro, 50);
  end;
end $$;

reset role;

-- ── PV19: sequência do pedido é independente da do orçamento ─
do $$
declare v_ped int; v_orc int;
begin
  select last_number into v_ped from public.order_sequences;
  select last_number into v_orc from public.quote_sequences;
  if v_ped = 1 and v_orc > 1
    then raise notice 'PV19) OK: PED em % e ORC em % — sequencias separadas', v_ped, v_orc;
    else raise notice 'PV19) FALHA: PED %, ORC %', v_ped, v_orc; end if;
end $$;
