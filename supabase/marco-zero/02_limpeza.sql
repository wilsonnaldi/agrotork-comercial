-- ============================================================
-- MARCO ZERO · 2 de 4 — LIMPEZA DOS DADOS COMERCIAIS
--
-- ⚠ NÃO EXECUTADO. Este arquivo apaga dados. Só roda quando a
--   AGROTORK autorizar, e depois de `01_inventario.sql` confirmar
--   que o banco está no estado que os guards abaixo esperam.
--
-- ENSAIO (não altera nada): troque o COMMIT final por ROLLBACK.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 02_limpeza.sql
--
-- O QUE APAGA — e só isto:
--   orçamentos e tudo que pende deles, clientes, kits, produtos e
--   seus custos, e os dois cadastros nomeados "AGROTORK TESTE".
--
-- O QUE NÃO TOCA:
--   schema, migrations, funções, triggers, RLS, policies, grants,
--   units, categories do seed, brands do seed, price_conditions,
--   app_settings (inclusive os dados reais da empresa), profiles,
--   auth.users, storage.
--
-- audit_log NÃO É APAGÁVEL. A migration 20260901060000 instalou
-- guardas de UPDATE, DELETE e TRUNCATE: nem o dono da tabela apaga.
-- A trilha do período de testes sobrevive de propósito — ela é a
-- prova de que esta limpeza aconteceu e de quem a fez.
-- ============================================================

begin;

-- ── PARÂMETROS DE DECISÃO ───────────────────────────────────
-- Marcas de FABRICANTE não são dado de teste; são cadastro. Por
-- padrão JR SOLUÇÕES e TOYAMA ficam. Mude para true só se a
-- AGROTORK decidir remover.
create temporary table _opcoes (
  remover_marca_jr     boolean not null,
  remover_marca_toyama boolean not null,
  zerar_sequencia      boolean not null
) on commit drop;
insert into _opcoes values (false, false, true);

-- ════════════════════════════════════════════════════════════
-- GUARDS — se o banco não for o que a auditoria descreveu, para
-- ════════════════════════════════════════════════════════════
do $$
declare
  v integer;
  v_txt text;
begin
  -- G1 · as duas migrations da Fase B precisam estar aplicadas
  select count(*) into v from supabase_migrations.schema_migrations
   where version in ('20260902120000','20260902120100');
  if v <> 2 then
    raise exception 'G1: as migrations da Fase B nao estao aplicadas (achei %/2)', v;
  end if;

  -- G2 · precisa existir exatamente um administrador ativo, e ele
  --      tem de sobreviver. Sem isto ninguem entra no sistema depois.
  select count(*) into v from public.profiles where role='admin' and is_active;
  if v < 1 then raise exception 'G2: nenhum administrador ativo — abortando'; end if;

  -- G3 · fotografia dos dados comerciais (auditoria de 2026-09-02)
  select count(*) into v from public.products;
  if v <> 94 then raise exception 'G3: esperava 94 produtos, achei %. O banco mudou desde a auditoria.', v; end if;

  select count(*) into v from public.product_costs;
  if v <> 93 then raise exception 'G3: esperava 93 linhas de custo, achei %', v; end if;

  select count(*) into v from public.customers;
  if v <> 1 then raise exception 'G3: esperava 1 cliente, achei %', v; end if;

  select count(*) into v from public.quotes;
  if v <> 1 then raise exception 'G3: esperava 1 orcamento, achei %', v; end if;

  select count(*) into v from public.quote_items;
  if v <> 2 then raise exception 'G3: esperava 2 itens de orcamento, achei %', v; end if;

  select count(*) into v from public.quote_share_tokens;
  if v <> 2 then raise exception 'G3: esperava 2 links de compartilhamento, achei %', v; end if;

  select count(*) into v from public.kits;
  if v <> 2 then raise exception 'G3: esperava 2 kits, achei %', v; end if;

  select count(*) into v from public.kit_items;
  if v <> 2 then raise exception 'G3: esperava 2 itens de kit, achei %', v; end if;

  -- G4 · nenhum orcamento APROVADO. Aprovado seria venda de verdade,
  --      e venda de verdade nao se apaga sem decisao explicita.
  select count(*) into v from public.quotes where status::text = 'approved';
  if v > 0 then
    raise exception 'G4: existem % orcamento(s) APROVADO(S). Isto nao e dado de teste — pare e decida caso a caso.', v;
  end if;

  -- G5 · nenhum produto com preco de venda definido, exceto o de teste.
  --      Preco definido significa decisao comercial tomada.
  select count(*), coalesce(string_agg(code, ', '), '') into v, v_txt
    from public.products where sale_price_set_at is not null and code <> '333';
  if v > 0 then
    raise exception 'G5: % produto(s) com preco de venda DEFINIDO fora do de teste: %. Pare e revise.', v, v_txt;
  end if;

  -- G6 · cadastros de apoio intactos
  select count(*) into v from public.units;            if v <> 9 then raise exception 'G6: esperava 9 unidades, achei %', v; end if;
  select count(*) into v from public.price_conditions; if v <> 2 then raise exception 'G6: esperava 2 condicoes de preco, achei %', v; end if;
  select count(*) into v from public.categories;       if v <> 8 then raise exception 'G6: esperava 8 categorias, achei %', v; end if;
  select count(*) into v from public.brands;           if v <> 11 then raise exception 'G6: esperava 11 marcas, achei %', v; end if;

  -- G7 · os dados da empresa precisam existir e vao ficar como estao
  select count(*) into v from public.app_settings
   where key='company' and value->>'legal_name' is not null and value->>'legal_name' <> '';
  if v <> 1 then raise exception 'G7: app_settings.company ausente ou sem razao social'; end if;

  raise notice 'GUARDS OK — o banco esta no estado que a auditoria descreveu.';
end $$;

-- ════════════════════════════════════════════════════════════
-- ANTES
-- ════════════════════════════════════════════════════════════
create temporary table _antes as
select 'products' t, count(*) n from public.products
union all select 'product_costs', count(*) from public.product_costs
union all select 'customers', count(*) from public.customers
union all select 'quotes', count(*) from public.quotes
union all select 'quote_items', count(*) from public.quote_items
union all select 'quote_share_tokens', count(*) from public.quote_share_tokens
union all select 'kits', count(*) from public.kits
union all select 'kit_items', count(*) from public.kit_items
union all select 'brands', count(*) from public.brands
union all select 'categories', count(*) from public.categories
union all select 'units', count(*) from public.units
union all select 'price_conditions', count(*) from public.price_conditions
union all select 'profiles', count(*) from public.profiles
union all select 'app_settings', count(*) from public.app_settings
union all select 'audit_log', count(*) from public.audit_log;

-- ════════════════════════════════════════════════════════════
-- EXCLUSÕES — na ordem que as chaves estrangeiras exigem
--
--   quote_share_tokens ─CASCADE→ quotes
--   quote_items ───────CASCADE→ quotes,  SET NULL→ products,  RESTRICT→ kits
--   quotes ────────────RESTRICT→ customers, RESTRICT→ profiles(owner)
--   kit_items ─────────CASCADE→ kits,    RESTRICT→ products
--   product_costs ─────CASCADE→ products, RESTRICT→ price_conditions
--   products ──────────RESTRICT→ brands, categories, units
--
-- Os RESTRICT sao os que mandam na ordem. Nada de CASCADE manual:
-- apagar o pai e deixar o banco decidir esconde o que foi embora.
-- ════════════════════════════════════════════════════════════

-- 1. Links publicos de orcamento
delete from public.quote_share_tokens;

-- 2. Itens de orcamento. O trigger de recalculo atualiza os totais do
--    orcamento — e o caminho normal da aplicacao, nao um atalho.
delete from public.quote_items;

-- 3. Orcamentos (libera clientes e kits)
delete from public.quotes;

-- 4. Clientes
delete from public.customers;

-- 5. Composicao de kit (libera os produtos)
delete from public.kit_items;

-- 6. Kits
delete from public.kits;

-- 7. Custos (libera products; o CASCADE faria sozinho, mas explicito
--    e auditavel)
delete from public.product_costs;

-- 8. Produtos
delete from public.products;

-- 9. Cadastros nomeados "AGROTORK TESTE" — criados pela tela em
--    2026-08-31 durante o teste do formulario. Agora sem produtos.
delete from public.categories where name = 'AGROTORK TESTE';
delete from public.brands     where name = 'AGROTORK TESTE';

-- 10. Marcas de fabricante: só saem se a AGROTORK mandar.
delete from public.brands b
 using _opcoes o
 where o.remover_marca_jr and public.slugify(b.name) = 'jr-solucoes';
delete from public.brands b
 using _opcoes o
 where o.remover_marca_toyama and public.slugify(b.name) = 'toyama';

-- 11. Sequência de numeração: o primeiro orçamento de verdade volta a
--     ser ORC-2026-0001.
update public.quote_sequences qs
   set last_number = 0
  from _opcoes o
 where o.zerar_sequencia;

-- ════════════════════════════════════════════════════════════
-- DEPOIS + CONFERÊNCIA
-- ════════════════════════════════════════════════════════════
do $$
declare v integer; v_txt text;
begin
  -- O que tinha de zerar, zerou.
  for v_txt in select unnest(array['products','product_costs','customers','quotes',
                                   'quote_items','quote_share_tokens','kits','kit_items'])
  loop
    execute format('select count(*) from public.%I', v_txt) into v;
    if v <> 0 then raise exception 'POS: % ainda tem % linha(s)', v_txt, v; end if;
  end loop;

  -- O que tinha de sobreviver, sobreviveu.
  select count(*) into v from public.profiles where role='admin' and is_active;
  if v < 1 then raise exception 'POS: o administrador sumiu — ROLLBACK'; end if;

  select count(*) into v from public.units;
  if v <> 9 then raise exception 'POS: unidades foram alteradas (%/9)', v; end if;

  select count(*) into v from public.price_conditions;
  if v <> 2 then raise exception 'POS: condicoes de preco foram alteradas (%/2)', v; end if;

  select count(*) into v from public.categories;
  if v <> 7 then raise exception 'POS: esperava as 7 categorias do seed, achei %', v; end if;

  select count(*) into v from public.app_settings
   where key='company' and value->>'legal_name' <> '';
  if v <> 1 then raise exception 'POS: os dados da empresa se perderam — ROLLBACK'; end if;

  select count(*) into v from public.brands
   where name in ('AGROTORK','DJI','KUHN','BALDAN','ARAG','MAGNOJET','TRIMBLE','AGRES');
  if v <> 8 then raise exception 'POS: as 8 marcas do seed foram alteradas (%/8)', v; end if;

  raise notice 'MARCO ZERO OK — dados comerciais zerados, estrutura e configuracao intactas.';
end $$;

select a.t as tabela, a.n as antes,
       case a.t
         when 'products' then (select count(*) from public.products)
         when 'product_costs' then (select count(*) from public.product_costs)
         when 'customers' then (select count(*) from public.customers)
         when 'quotes' then (select count(*) from public.quotes)
         when 'quote_items' then (select count(*) from public.quote_items)
         when 'quote_share_tokens' then (select count(*) from public.quote_share_tokens)
         when 'kits' then (select count(*) from public.kits)
         when 'kit_items' then (select count(*) from public.kit_items)
         when 'brands' then (select count(*) from public.brands)
         when 'categories' then (select count(*) from public.categories)
         when 'units' then (select count(*) from public.units)
         when 'price_conditions' then (select count(*) from public.price_conditions)
         when 'profiles' then (select count(*) from public.profiles)
         when 'app_settings' then (select count(*) from public.app_settings)
         when 'audit_log' then (select count(*) from public.audit_log)
       end as depois
from _antes a order by a.t;

-- ⚠ Para ENSAIAR sem alterar nada, troque a linha abaixo por ROLLBACK;
commit;
