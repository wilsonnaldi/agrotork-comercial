-- ============================================================
-- Importação de NF-e — a memória do de-para (migration 20260903160000).
--
-- O banco não lê XML: ler XML é da aplicação. O que se prova aqui é a
-- MEMÓRIA que faz a segunda nota do mesmo fornecedor entrar sozinha.
--
--   · a correspondência é guardada por (fornecedor, código);
--   · o mesmo código em fornecedores diferentes NÃO se confunde;
--   · corrigir um de-para errado sobrescreve, não duplica;
--   · GTIN é único no catálogo inteiro — é do produto, não de quem vende;
--   · o vendedor não mexe nisso.
--
-- Prefixo de UUID = número da suíte.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('24242424-0000-4000-8000-0000000024a1','nfe.admin@teste.local','{"full_name":"Admin NFe","role":"admin"}'),
 ('24242424-0000-4000-8000-0000000024a2','nfe.vend@teste.local','{"full_name":"Vendedor NFe","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = '24242424-0000-4000-8000-0000000024a1';

insert into public.suppliers (name, document) values
 ('Fornecedor Alfa', '11111111000191'),
 ('Fornecedor Beta', '22222222000172');

insert into public.products (code, name, unit_id, sale_price, gtin)
select 'NFE-A', 'Bateria importada', u.id, 900, '7891234560017' from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'NFE-B', 'Helice importada', u.id, 60 from public.units u where u.code = 'UN';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '24242424-0000-4000-8000-0000000024a1', false);

-- ── NF1: a correspondência é guardada e normalizada ─────────
do $$
declare v_codigo text; v_produto text;
begin
  perform public.remember_supplier_product(
    (select id from public.suppliers where name = 'Fornecedor Alfa'),
    '  bat-6000s  ',
    (select id from public.products where code = 'NFE-A'),
    'BATERIA 6000MAH INTELIGENTE');

  select sp.supplier_code, p.code into v_codigo, v_produto
    from public.supplier_products sp
    join public.products p on p.id = sp.product_id
   where sp.supplier_id = (select id from public.suppliers where name = 'Fornecedor Alfa');

  if v_codigo = 'BAT-6000S' and v_produto = 'NFE-A'
    then raise notice 'NF1) OK: "  bat-6000s  " virou "%" apontando para %', v_codigo, v_produto;
    else raise notice 'NF1) FALHA: % -> %', v_codigo, v_produto; end if;
end $$;

-- ── NF2: a segunda nota reconhece sozinha ───────────────────
-- É o ponto inteiro da fase: a pessoa apontou uma vez, e não aponta mais.
do $$
declare v_quantos int; v_nome text;
begin
  select count(*)::int into v_quantos
    from public.known_supplier_products(
      (select id from public.suppliers where name = 'Fornecedor Alfa'));

  select product_name into v_nome
    from public.known_supplier_products(
      (select id from public.suppliers where name = 'Fornecedor Alfa'))
   where supplier_code = 'BAT-6000S';

  if v_quantos = 1 and v_nome = 'Bateria importada'
    then raise notice 'NF2) OK: o codigo BAT-6000S ja resolve para "%" sem perguntar', v_nome;
    else raise notice 'NF2) FALHA: % conhecido(s), nome %', v_quantos, v_nome; end if;
end $$;

-- ── NF3: o mesmo código em outro fornecedor não se confunde ─
-- "1001" é o código mais comum do Brasil. Se a chave fosse só o código,
-- a nota do Beta entraria com o produto do Alfa.
do $$
declare v_alfa text; v_beta text;
begin
  perform public.remember_supplier_product(
    (select id from public.suppliers where name = 'Fornecedor Alfa'), '1001',
    (select id from public.products where code = 'NFE-A'), null);
  perform public.remember_supplier_product(
    (select id from public.suppliers where name = 'Fornecedor Beta'), '1001',
    (select id from public.products where code = 'NFE-B'), null);

  select product_code into v_alfa from public.known_supplier_products(
    (select id from public.suppliers where name = 'Fornecedor Alfa')) where supplier_code = '1001';
  select product_code into v_beta from public.known_supplier_products(
    (select id from public.suppliers where name = 'Fornecedor Beta')) where supplier_code = '1001';

  if v_alfa = 'NFE-A' and v_beta = 'NFE-B'
    then raise notice 'NF3) OK: "1001" e % no Alfa e % no Beta — nao se misturam', v_alfa, v_beta;
    else raise notice 'NF3) FALHA: alfa % / beta %', v_alfa, v_beta; end if;
end $$;

-- ── NF4: corrigir sobrescreve, não duplica ──────────────────
-- Apontar o produto errado na nota passada acontece. Consertar não pode
-- deixar duas respostas para a mesma pergunta.
do $$
declare v_linhas int; v_produto text; v_desc text;
begin
  perform public.remember_supplier_product(
    (select id from public.suppliers where name = 'Fornecedor Alfa'), 'BAT-6000S',
    (select id from public.products where code = 'NFE-B'), null);

  select count(*)::int into v_linhas from public.supplier_products
   where supplier_id = (select id from public.suppliers where name = 'Fornecedor Alfa')
     and supplier_code = 'BAT-6000S';

  select p.code, sp.supplier_description into v_produto, v_desc
    from public.supplier_products sp join public.products p on p.id = sp.product_id
   where sp.supplier_id = (select id from public.suppliers where name = 'Fornecedor Alfa')
     and sp.supplier_code = 'BAT-6000S';

  -- A descrição antiga sobrevive: corrigir o produto não apaga o que o
  -- fornecedor escreveu na nota.
  if v_linhas = 1 and v_produto = 'NFE-B' and v_desc = 'BATERIA 6000MAH INTELIGENTE'
    then raise notice 'NF4) OK: corrigido para % em UMA linha, com a descricao preservada', v_produto;
    else raise notice 'NF4) FALHA: % linha(s), produto %, desc %', v_linhas, v_produto, v_desc; end if;
end $$;

-- ── NF5: código vazio não vira de-para ──────────────────────
-- Nota de serviço e item avulso vêm sem cProd útil. Guardar uma linha
-- com código vazio envenenaria a importação seguinte.
do $$
declare v_resultado uuid; v_linhas int;
begin
  select public.remember_supplier_product(
    (select id from public.suppliers where name = 'Fornecedor Alfa'), '   ',
    (select id from public.products where code = 'NFE-A'), null) into v_resultado;

  select count(*)::int into v_linhas from public.supplier_products
   where supplier_id = (select id from public.suppliers where name = 'Fornecedor Alfa');

  if v_resultado is null and v_linhas = 2
    then raise notice 'NF5) OK: codigo vazio ignorado — seguem % correspondencias', v_linhas;
    else raise notice 'NF5) FALHA: resultado % / % linhas', v_resultado, v_linhas; end if;
end $$;

-- ── NF6: GTIN é único no catálogo inteiro ───────────────────
-- Ao contrário do código do fornecedor, o EAN é do PRODUTO: o mesmo
-- número em qualquer nota, de qualquer fornecedor. Dois produtos com o
-- mesmo EAN é cadastro em duplicata.
do $$
declare v_erro text;
begin
  begin
    update public.products set gtin = '7891234560017' where code = 'NFE-B';
    raise notice 'NF6) FALHA: aceitou o mesmo GTIN em dois produtos';
  exception when unique_violation then
    raise notice 'NF6) OK: GTIN repetido barrado — o EAN identifica o produto, nao a nota';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'NF6) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── NF7: produto sem GTIN continua permitido, e vários ──────
-- Peça de fabricação própria não tem código de barras.
do $$
declare v_sem int;
begin
  select count(*)::int into v_sem from public.products
   where gtin is null and deleted_at is null;
  if v_sem >= 2
    then raise notice 'NF7) OK: % produto(s) sem GTIN convivem', v_sem;
    else raise notice 'NF7) FALHA: so % sem GTIN', v_sem; end if;
end $$;

-- ── NF8: o vendedor não mexe no de-para ─────────────────────
select set_config('request.jwt.claim.sub', '24242424-0000-4000-8000-0000000024a2', false);

do $$
declare v_vistos int; v_falhas text := '';
begin
  select count(*)::int into v_vistos from public.supplier_products;

  begin
    perform public.remember_supplier_product(
      (select id from public.suppliers where name = 'Fornecedor Alfa'), 'VEND-1',
      (select id from public.products where code = 'NFE-A'), null);
    v_falhas := v_falhas || ' pela funcao';
  exception when insufficient_privilege then null;
  when others then v_falhas := v_falhas || ' erro-errado'; end;

  begin
    insert into public.supplier_products (supplier_id, supplier_code, product_id)
    select s.id, 'VEND-2', p.id from public.suppliers s, public.products p
     where s.name = 'Fornecedor Alfa' and p.code = 'NFE-A';
    v_falhas := v_falhas || ' pelo insert';
  exception when others then null; end;

  if v_vistos = 0 and v_falhas = ''
    then raise notice 'NF8) OK: vendedor nao le nem escreve o de-para de compra';
    else raise notice 'NF8) FALHA: viu % / passou em ->%', v_vistos, v_falhas; end if;
end $$;

-- ── NF9: anônimo não alcança ────────────────────────────────
do $$
declare v_falhas text := '';
begin
  reset role;
  set local role anon;
  begin perform 1 from public.supplier_products; v_falhas := ' de-para';
        exception when others then null; end;
  if v_falhas = ''
    then raise notice 'NF9) OK: anonimo sem privilegio no de-para';
    else raise notice 'NF9) FALHA: alcancou ->%', v_falhas; end if;
end $$;

reset role;
