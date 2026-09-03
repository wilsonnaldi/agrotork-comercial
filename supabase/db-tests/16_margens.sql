-- ============================================================
-- Margem por setor (migration 20260903020000).
--
-- A regra SUGERE o preço; não o impõe. Este arquivo prova que:
--   · sem regra ativa, ninguém precifica nada por acidente;
--   · markup e margem dão preços diferentes, de propósito;
--   · o vendedor não enxerga a regra nem o preço sugerido;
--   · o ensaio (dry run) não escreve.
-- ============================================================
insert into auth.users (id, email, raw_user_meta_data) values
 ('aaaaaaaa-0000-4000-8000-00000000a001','marg.admin@teste.local','{"full_name":"Admin Margem","role":"admin"}'),
 ('aaaaaaaa-0000-4000-8000-00000000a002','marg.vend@teste.local','{"full_name":"Vendedor Margem","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = 'aaaaaaaa-0000-4000-8000-00000000a001';

-- Setor de teste, com um produto de custo redondo para a conta ser óbvia.
insert into public.categories (name) values ('Setor Margem Teste');

insert into public.products (code, name, unit_id, category_id, sale_price)
select 'MG-001', 'Produto para margem', u.id, c.id, 0
  from public.units u, public.categories c
 where u.code = 'UN' and c.name = 'Setor Margem Teste';

-- Dois custos vigentes: à vista 100, faturado 110.
insert into public.product_costs (product_id, condition_id, cost_price)
select p.id, pc.id, case pc.code when 'AVISTA' then 100 else 110 end
  from public.products p, public.price_conditions pc
 where p.code = 'MG-001';

-- Produto sem custo nenhum, no mesmo setor.
insert into public.products (code, name, unit_id, category_id, sale_price)
select 'MG-002', 'Produto sem custo', u.id, c.id, 0
  from public.units u, public.categories c
 where u.code = 'UN' and c.name = 'Setor Margem Teste';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
set request.jwt.claim.sub = 'aaaaaaaa-0000-4000-8000-00000000a001';

-- ── MG1: a regra padrão nasce desligada ─────────────────────
do $$
declare v boolean;
begin
  select is_active into v from public.margin_rules where category_id is null;
  if v then raise notice 'MG1) FALHA: a regra padrao veio ativa';
  else raise notice 'MG1) OK: regra padrao nasce inativa — ninguem precifica sem decidir'; end if;
end $$;

-- ── MG2: sem regra ativa, não há sugestão ───────────────────
do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-001';
  if v is null then raise notice 'MG2) OK: sem regra ativa o preco sugerido e NULO';
  else raise notice 'MG2) FALHA: sugeriu % sem regra ativa', v; end if;
end $$;

-- ── MG3: markup de 30% sobre o custo MAIOR (110) = 143 ──────
insert into public.margin_rules (category_id, mode, percent, cost_basis, rounding, is_active)
select id, 'markup', 30, 'maior', 'none', true from public.categories where name='Setor Margem Teste';

do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-001';
  if v = 143.00 then raise notice 'MG3) OK: markup 30%% sobre o custo maior (110) = 143';
  else raise notice 'MG3) FALHA: esperava 143, veio %', v; end if;
end $$;

-- ── MG4: margem de 30% SOBRE A VENDA = 157,14, não 143 ──────
update public.margin_rules set mode='margin'
 where category_id = (select id from public.categories where name='Setor Margem Teste');

do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-001';
  if round(v,2) = 157.14 then raise notice 'MG4) OK: margem 30%% sobre a venda = 157,14 — diferente do markup, como tem de ser';
  else raise notice 'MG4) FALHA: esperava 157,14, veio %', v; end if;
end $$;

-- ── MG5: base de custo à vista muda o resultado ─────────────
update public.margin_rules set mode='markup', cost_basis='avista'
 where category_id = (select id from public.categories where name='Setor Margem Teste');

do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-001';
  if v = 130.00 then raise notice 'MG5) OK: base a vista (100) da 130; base maior (110) dava 143';
  else raise notice 'MG5) FALHA: esperava 130, veio %', v; end if;
end $$;

-- ── MG6: arredondamento nunca joga o preço para baixo ───────
do $$
declare v_dez numeric; v_cem numeric; v_nov numeric;
begin
  update public.margin_rules set rounding='ten'
   where category_id = (select id from public.categories where name='Setor Margem Teste');
  select public.suggested_sale_price(id) into v_dez from public.products where code='MG-001';
  update public.margin_rules set rounding='hundred'
   where category_id = (select id from public.categories where name='Setor Margem Teste');
  select public.suggested_sale_price(id) into v_cem from public.products where code='MG-001';
  update public.margin_rules set rounding='ninety'
   where category_id = (select id from public.categories where name='Setor Margem Teste');
  select public.suggested_sale_price(id) into v_nov from public.products where code='MG-001';

  if v_dez = 130 and v_cem = 200 and v_nov = 190 and v_dez >= 130 and v_cem >= 130
    then raise notice 'MG6) OK: arredondamento dezena=%, centena=%, noventa=% — nenhum abaixo do calculado', v_dez, v_cem, v_nov;
    else raise notice 'MG6) FALHA: dezena=%, centena=%, noventa=%', v_dez, v_cem, v_nov; end if;

  update public.margin_rules set rounding='none'
   where category_id = (select id from public.categories where name='Setor Margem Teste');
end $$;

-- ── MG7: produto sem custo não recebe preço ─────────────────
do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-002';
  if v is null then raise notice 'MG7) OK: produto sem custo nao recebe preco sugerido';
  else raise notice 'MG7) FALHA: sugeriu % para produto sem custo', v; end if;
end $$;

-- ── MG8: o ensaio não escreve ───────────────────────────────
do $$
declare v_linhas int; v_preco numeric;
begin
  select count(*) into v_linhas from public.apply_margin_rules(
    (select id from public.categories where name='Setor Margem Teste'), false, true);
  select sale_price into v_preco from public.products where code='MG-001';
  if v_linhas = 1 and v_preco = 0
    then raise notice 'MG8) OK: ensaio listou % mudanca(s) e nao escreveu nada', v_linhas;
    else raise notice 'MG8) FALHA: linhas=%, sale_price=%', v_linhas, v_preco; end if;
end $$;

-- ── MG9: aplicar escreve e carimba a data ───────────────────
do $$
declare v_preco numeric; v_carimbo timestamptz;
begin
  perform public.apply_margin_rules(
    (select id from public.categories where name='Setor Margem Teste'), false, false);
  select sale_price, sale_price_set_at into v_preco, v_carimbo
    from public.products where code='MG-001';
  if v_preco = 130.00 and v_carimbo is not null
    then raise notice 'MG9) OK: aplicou 130,00 e carimbou sale_price_set_at';
    else raise notice 'MG9) FALHA: preco=%, carimbo=%', v_preco, v_carimbo; end if;
end $$;

-- ── MG10: a trilha registrou a mudança de preço ─────────────
do $$
declare n int;
begin
  select count(*) into n from public.audit_log
   where entity_type='product' and operation='UPDATE'
     and 'sale_price' = any(changed_fields);
  if n >= 1 then raise notice 'MG10) OK: a auditoria registrou a mudanca de preco (% evento(s))', n;
  else raise notice 'MG10) FALHA: a mudanca de preco nao entrou na trilha'; end if;
end $$;

-- ── Contexto: VENDEDOR ──────────────────────────────────────
set request.jwt.claim.sub = 'aaaaaaaa-0000-4000-8000-00000000a002';

-- ── MG11: vendedor não lê a regra ───────────────────────────
do $$
declare n int;
begin
  select count(*) into n from public.margin_rules;
  if n = 0 then raise notice 'MG11) OK: vendedor le ZERO regras de margem — a regra revela o custo';
  else raise notice 'MG11) BRECHA: vendedor leu % regra(s) de margem', n; end if;
end $$;

-- ── MG12: vendedor não recebe preço sugerido ────────────────
do $$
declare v numeric;
begin
  select public.suggested_sale_price(id) into v from public.products where code='MG-001';
  if v is null then raise notice 'MG12) OK: preco sugerido e NULO para o vendedor (RLS de product_costs)';
  else raise notice 'MG12) BRECHA: vendedor viu preco sugerido %', v; end if;
end $$;

-- ── MG13: vendedor não aplica margem ────────────────────────
do $$
begin
  perform public.apply_margin_rules(null, true, false);
  raise notice 'MG13) BRECHA: vendedor aplicou margem em lote';
exception when others then
  raise notice 'MG13) OK: aplicacao negada ao vendedor (%)', left(sqlerrm, 60);
end $$;

set request.jwt.claim.sub = 'aaaaaaaa-0000-4000-8000-00000000a001';

-- ── MG14: margem de 100% sobre a venda é recusada ───────────
do $$
begin
  insert into public.margin_rules (category_id, mode, percent, is_active)
  select id, 'margin', 100, false from public.categories where name='Setor Margem Teste';
  raise notice 'MG14) FALHA: aceitou margem de 100%% sobre a venda (divisao por zero)';
exception when check_violation then
  raise notice 'MG14) OK: margem de 100%% sobre a venda recusada pela constraint';
end $$;

-- ── MG15: uma regra por setor ───────────────────────────────
do $$
begin
  insert into public.margin_rules (category_id, mode, percent, is_active)
  select id, 'markup', 10, false from public.categories where name='Setor Margem Teste';
  raise notice 'MG15) FALHA: aceitou duas regras para o mesmo setor';
exception when unique_violation then
  raise notice 'MG15) OK: segunda regra para o mesmo setor recusada';
end $$;

-- ── MG16: uma única regra padrão ────────────────────────────
do $$
begin
  insert into public.margin_rules (category_id, mode, percent, is_active)
  values (null, 'markup', 10, false);
  raise notice 'MG16) FALHA: aceitou duas regras padrao';
exception when unique_violation then
  raise notice 'MG16) OK: segunda regra padrao recusada';
end $$;

reset role;
