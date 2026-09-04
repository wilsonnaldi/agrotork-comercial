-- ============================================================
-- Financeiro (migration 20260903150000).
--
-- O que este arquivo prova:
--   · faturar o pedido cria o título a receber, uma vez só;
--   · receber a nota cria o título a pagar, com o prazo da condição;
--   · o status é DERIVADO da soma das baixas — nunca digitado;
--   · baixa parcial existe e deixa o título "parcial";
--   · baixa maior do que se deve é recusada; estorno é permitido;
--   · a baixa não muda e não some, nem para o dono do banco;
--   · parcelar troca um título por N, e os centavos fecham;
--   · vencido conta só o que ainda deve;
--   · o vendedor não enxerga o caixa da empresa.
--
-- Prefixo de UUID = número da suíte.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('23232323-0000-4000-8000-00000000f001','fin.admin@teste.local','{"full_name":"Admin Financeiro","role":"admin"}'),
 ('23232323-0000-4000-8000-00000000f002','fin.vend@teste.local','{"full_name":"Vendedor Financeiro","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = '23232323-0000-4000-8000-00000000f001';

insert into public.customers (name, city, state) values ('Cliente do Financeiro', 'Londrina', 'PR');
insert into public.suppliers (name, document) values ('Fornecedor do Financeiro', '99888777000166');

insert into public.products (code, name, unit_id, sale_price)
select 'FIN-001', 'Produto financeiro', u.id, 500 from public.units u where u.code = 'UN';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '23232323-0000-4000-8000-00000000f001', false);

-- ── Pedido do vendedor, aprovado e faturado ─────────────────
do $$
declare v_q uuid; v_o uuid;
begin
  insert into public.quotes (customer_id, owner_id)
  select c.id, '23232323-0000-4000-8000-00000000f002'
    from public.customers c where c.name = 'Cliente do Financeiro'
  returning id into v_q;

  insert into public.quote_items (quote_id, product_id, name_snapshot, quantity, unit_price, sort_order)
  select v_q, p.id, p.name, 2, 500, 1 from public.products p where p.code = 'FIN-001';

  update public.quotes set status = 'sent'     where id = v_q;
  update public.quotes set status = 'approved' where id = v_q;

  select public.create_order_from_quote(v_q) into v_o;
  update public.orders set status = 'picking'  where id = v_o;
  update public.orders set status = 'invoiced' where id = v_o;
end $$;

-- ── FI1: faturar criou o título a receber ───────────────────
do $$
declare v_valor numeric; v_status public.financial_status; v_desc text; v_venc date;
begin
  select amount, status, description, due_date into v_valor, v_status, v_desc, v_venc
    from public.financial_entries
   where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');

  if v_valor = 1000 and v_status = 'open' and v_desc like 'Pedido PED-%' and v_venc = current_date
    then raise notice 'FI1) OK: "%" de % vencendo hoje, em aberto', v_desc, v_valor;
    else raise notice 'FI1) FALHA: % / % / % / %', v_desc, v_valor, v_status, v_venc; end if;
end $$;

-- ── FI2: e não cria duas vezes ──────────────────────────────
do $$
declare v_o uuid; v_antes int; v_depois int;
begin
  select id into v_o from public.orders
   where customer_id = (select id from public.customers where name = 'Cliente do Financeiro');

  select count(*)::int into v_antes from public.financial_entries where order_id = v_o;
  update public.orders set status = 'delivered' where id = v_o;
  select count(*)::int into v_depois from public.financial_entries where order_id = v_o;

  if v_antes = 1 and v_depois = 1
    then raise notice 'FI2) OK: um titulo por pedido, sem repetir';
    else raise notice 'FI2) FALHA: antes % / depois %', v_antes, v_depois; end if;
end $$;

-- ── FI3: baixa parcial deixa o título "parcial" ─────────────
-- Cliente que paga metade é terça-feira, não exceção.
do $$
declare v_id uuid; v_status public.financial_status; v_pago numeric; v_falta numeric;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  perform public.register_financial_payment(v_id, 400, current_date, 'PIX', 'Entrada');

  select status into v_status from public.financial_entries where id = v_id;
  select paid_amount, open_amount into v_pago, v_falta
    from public.financial_position where id = v_id;

  if v_status = 'partial' and v_pago = 400 and v_falta = 600
    then raise notice 'FI3) OK: pagou %, falta %, situacao %', v_pago, v_falta, v_status;
    else raise notice 'FI3) FALHA: % / pago % / falta %', v_status, v_pago, v_falta; end if;
end $$;

-- ── FI4: baixa maior do que se deve é recusada ──────────────
do $$
declare v_id uuid; v_erro text;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  begin
    perform public.register_financial_payment(v_id, 700, null, null, null);
    raise notice 'FI4) FALHA: aceitou baixa maior do que o saldo';
  exception when check_violation then
    raise notice 'FI4) OK: baixa de 700 recusada — faltavam 600';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'FI4) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── FI5: quitar fecha o título sozinho ──────────────────────
do $$
declare v_id uuid; v_status public.financial_status; v_falta numeric;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  perform public.register_financial_payment(v_id, 600, current_date, 'Boleto', null);

  select status into v_status from public.financial_entries where id = v_id;
  select open_amount into v_falta from public.financial_position where id = v_id;

  if v_status = 'settled' and v_falta = 0
    then raise notice 'FI5) OK: quitado — o status veio da soma das baixas, ninguem digitou';
    else raise notice 'FI5) FALHA: % / falta %', v_status, v_falta; end if;
end $$;

-- ── FI6: estorno volta o título para parcial ────────────────
do $$
declare v_id uuid; v_status public.financial_status; v_pago numeric; v_baixas int;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  perform public.register_financial_payment(v_id, -600, current_date, null, 'Cheque devolvido');

  select status into v_status from public.financial_entries where id = v_id;
  select paid_amount into v_pago from public.financial_position where id = v_id;
  select count(*)::int into v_baixas from public.financial_payments where entry_id = v_id;

  -- Três linhas no livro: 400, 600 e -600. Nenhuma foi apagada.
  if v_status = 'partial' and v_pago = 400 and v_baixas = 3
    then raise notice 'FI6) OK: estorno devolveu a % com % linhas no livro', v_status, v_baixas;
    else raise notice 'FI6) FALHA: % / pago % / baixas %', v_status, v_pago, v_baixas; end if;
end $$;

-- ── FI7: a baixa não muda e não some ────────────────────────
do $$
declare v_falhas text := ''; v_id uuid;
begin
  reset role;
  select id into v_id from public.financial_payments limit 1;

  begin update public.financial_payments set amount = 999 where id = v_id;
        v_falhas := v_falhas || ' alterou'; exception when others then null; end;
  begin delete from public.financial_payments where id = v_id;
        v_falhas := v_falhas || ' apagou'; exception when others then null; end;

  if v_falhas = ''
    then raise notice 'FI7) OK: baixa nao muda e nao some, nem para o dono do banco';
    else raise notice 'FI7) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── FI8: título com baixa não se cancela ────────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '23232323-0000-4000-8000-00000000f001', false);

do $$
declare v_id uuid;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  begin
    perform public.cancel_financial_entry(v_id, 'tentativa');
    raise notice 'FI8) FALHA: cancelou titulo com baixa';
  exception when check_violation then
    raise notice 'FI8) OK: com baixa nao se cancela — o caminho e o estorno';
  end;
end $$;

-- ── FI9: e não se parcela depois que o dinheiro andou ───────
do $$
declare v_id uuid;
begin
  select id into v_id from public.financial_entries where kind = 'receivable'
     and customer_id = (select id from public.customers where name = 'Cliente do Financeiro');
  begin
    perform public.split_financial_entry(v_id, 3, null, 30);
    raise notice 'FI9) FALHA: parcelou titulo que ja tinha baixa';
  exception when check_violation then
    raise notice 'FI9) OK: so titulo aberto e sem baixa se parcela';
  end;
end $$;

-- ── A nota de compra do outro lado ──────────────────────────
do $$
declare v_nota uuid;
begin
  insert into public.purchases (supplier_id, condition_id, invoice_number)
  select s.id, c.id, 'FIN-99'
    from public.suppliers s, public.price_conditions c
   where s.name = 'Fornecedor do Financeiro' and c.code = 'FATURADO'
  returning id into v_nota;

  insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost)
  select v_nota, p.id, 10, 30.01 from public.products p where p.code = 'FIN-001';

  perform public.receive_purchase(v_nota);
end $$;

-- ── FI10: receber a nota criou a conta a pagar, com prazo ───
do $$
declare v_valor numeric; v_venc date; v_desc text; v_forn text;
begin
  select e.amount, e.due_date, e.description, s.name
    into v_valor, v_venc, v_desc, v_forn
    from public.financial_entries e
    join public.suppliers s on s.id = e.supplier_id
   where e.kind = 'payable' and s.name = 'Fornecedor do Financeiro';

  -- 10 × 30,01 = 300,10; condição FATURADO = 30 dias.
  if v_valor = 300.10 and v_venc = current_date + 30 and v_desc like '%NF FIN-99%'
    then raise notice 'FI10) OK: a pagar % para % em %, vindo de "%"', v_valor, v_forn, v_venc, v_desc;
    else raise notice 'FI10) FALHA: % / % / %', v_valor, v_venc, v_desc; end if;
end $$;

-- ── FI11: parcelar troca um título por N, e os centavos fecham ─
-- 300,10 em 3 vezes não divide redondo. A sobra vai para a PRIMEIRA
-- parcela, e a soma tem que bater com o total no centavo.
do $$
declare v_id uuid; v_quantos int; v_soma numeric; v_primeira numeric;
        v_ultima numeric; v_venc_1 date; v_venc_3 date; v_original int;
begin
  select id into v_id from public.financial_entries where kind = 'payable'
     and supplier_id = (select id from public.suppliers where name = 'Fornecedor do Financeiro');
  select public.split_financial_entry(v_id, 3, current_date + 30, 30) into v_quantos;

  select count(*)::int into v_original from public.financial_entries where id = v_id;

  select sum(amount) into v_soma from public.financial_entries where kind = 'payable'
     and supplier_id = (select id from public.suppliers where name = 'Fornecedor do Financeiro');
  select amount, due_date into v_primeira, v_venc_1
    from public.financial_entries where kind = 'payable' and installment = 1
     and supplier_id = (select id from public.suppliers where name = 'Fornecedor do Financeiro');
  select amount, due_date into v_ultima, v_venc_3
    from public.financial_entries where kind = 'payable' and installment = 3
     and supplier_id = (select id from public.suppliers where name = 'Fornecedor do Financeiro');

  if v_quantos = 3 and v_original = 0 and v_soma = 300.10
     and v_primeira = 100.04 and v_ultima = 100.03
     and v_venc_1 = current_date + 30 and v_venc_3 = current_date + 90
    then raise notice 'FI11) OK: 3 parcelas somando % — % + % + %, vencendo de 30 em 30',
         v_soma, v_primeira, v_ultima, v_ultima;
    else raise notice 'FI11) FALHA: % parcelas / original % / soma % / 1a % / 3a % / vencs % e %',
         v_quantos, v_original, v_soma, v_primeira, v_ultima, v_venc_1, v_venc_3; end if;
end $$;

-- ── FI12: vencido conta só o que ainda deve ─────────────────
do $$
declare v_id uuid; v_vencido boolean; v_dias int; v_depois boolean;
begin
  -- Um título de ontem, ainda em aberto.
  insert into public.financial_entries
    (kind, customer_id, description, due_date, amount)
  select 'receivable', c.id, 'Titulo atrasado', current_date - 5, 250
    from public.customers c where c.name = 'Cliente do Financeiro'
  returning id into v_id;

  select is_overdue, days_overdue into v_vencido, v_dias
    from public.financial_position where id = v_id;

  -- Quitado, ele para de contar como atraso: é história, não dívida.
  perform public.register_financial_payment(v_id, 250, current_date, 'PIX', null);
  select is_overdue into v_depois from public.financial_position where id = v_id;

  if v_vencido and v_dias = 5 and not v_depois
    then raise notice 'FI12) OK: vencido ha % dias; quitado, sai da lista de atraso', v_dias;
    else raise notice 'FI12) FALHA: vencido % (% dias) / depois %', v_vencido, v_dias, v_depois; end if;
end $$;

-- ── FI13: cliente e fornecedor no mesmo título, não ─────────
-- A constraint existe para o título nunca ficar sem dono nem com dois.
do $$
declare v_falhas text := '';
begin
  begin
    insert into public.financial_entries (kind, description, due_date, amount)
    values ('receivable', 'Sem dono', current_date, 100);
    v_falhas := v_falhas || ' sem-dono'; exception when check_violation then null; end;

  begin
    insert into public.financial_entries (kind, customer_id, supplier_id, description, due_date, amount)
    select 'receivable', c.id, s.id, 'Dois donos', current_date, 100
      from public.customers c, public.suppliers s
     where c.name = 'Cliente do Financeiro' and s.name = 'Fornecedor do Financeiro';
    v_falhas := v_falhas || ' dois-donos'; exception when check_violation then null; end;

  begin
    insert into public.financial_entries (kind, customer_id, description, due_date, amount)
    select 'payable', c.id, 'Receber de cliente como pagar', current_date, 100
      from public.customers c where c.name = 'Cliente do Financeiro';
    v_falhas := v_falhas || ' lado-errado'; exception when check_violation then null; end;

  if v_falhas = ''
    then raise notice 'FI13) OK: titulo sem dono, com dois donos ou do lado errado sao recusados';
    else raise notice 'FI13) FALHA: passou em ->%', v_falhas; end if;
end $$;

-- ── FI14: o vendedor não enxerga o caixa da empresa ─────────
-- Ele vê o pedido dele; não vê quanto entrou nem quanto se deve.
set role authenticated;
select set_config('request.jwt.claim.sub', '23232323-0000-4000-8000-00000000f002', false);

do $$
declare v_titulos int; v_baixas int; v_posicao int; v_pedidos int; v_falhas text := '';
begin
  select count(*)::int into v_titulos  from public.financial_entries;
  select count(*)::int into v_baixas   from public.financial_payments;
  select count(*)::int into v_posicao  from public.financial_position;
  select count(*)::int into v_pedidos  from public.orders
   where owner_id = '23232323-0000-4000-8000-00000000f002';

  begin
    perform public.register_financial_payment(
      (select id from public.financial_entries limit 1), 10, null, null, null);
    v_falhas := ' baixou'; exception when others then null; end;

  if v_titulos = 0 and v_baixas = 0 and v_posicao = 0 and v_pedidos >= 1 and v_falhas = ''
    then raise notice 'FI14) OK: vendedor ve % pedido(s) seu(s) e ZERO titulo, baixa ou posicao', v_pedidos;
    else raise notice 'FI14) FALHA: titulos % / baixas % / posicao % / pedidos % / %',
         v_titulos, v_baixas, v_posicao, v_pedidos, v_falhas; end if;
end $$;

-- ── FI15: anônimo não alcança ───────────────────────────────
do $$
declare v_falhas text := '';
begin
  reset role;
  set local role anon;
  begin perform 1 from public.financial_entries;  v_falhas := v_falhas || ' titulos';
        exception when others then null; end;
  begin perform 1 from public.financial_payments; v_falhas := v_falhas || ' baixas';
        exception when others then null; end;
  if v_falhas = ''
    then raise notice 'FI15) OK: anonimo sem privilegio no financeiro';
    else raise notice 'FI15) FALHA: alcancou ->%', v_falhas; end if;
end $$;

reset role;
