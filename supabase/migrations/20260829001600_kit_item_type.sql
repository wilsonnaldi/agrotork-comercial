-- ============================================================
-- 1600 · Item obrigatório e item opcional do kit
--
-- Fase 3. O cadastro do kit passa a distinguir dois papéis:
--
--   required  — sempre entra quando o kit é usado; o vendedor não tira.
--   optional  — faz parte do CATÁLOGO DE OPÇÕES do kit; o vendedor
--               escolhe, item a item, na hora de montar o orçamento.
--
-- ATENÇÃO à distinção que dá nome à Fase 4:
--
--   "item opcional DO KIT"        → está aqui, em kit_items. É cadastro.
--   "item selecionado NO ORÇAMENTO" → estará em quote_items. É venda.
--
-- Marcar um item como opcional NÃO o coloca em orçamento nenhum, e
-- escolher opcionais num orçamento NÃO altera o cadastro do kit. São
-- tabelas diferentes de propósito.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── 1. Papel do item ────────────────────────────────────────
create type public.kit_item_type as enum ('required', 'optional');

alter table public.kit_items
  add column item_type public.kit_item_type not null default 'required';

comment on column public.kit_items.item_type is
  'required: sempre entra com o kit. optional: fica disponível para o vendedor escolher no orçamento. A escolha do vendedor vive em quote_items, nunca aqui.';

-- A listagem separa obrigatórios de opcionais em toda tela do módulo.
create index idx_kit_items_kit_type on public.kit_items (kit_id, item_type, sort_order);

-- `unique (kit_id, product_id)` já existe desde a migration 0500 e continua
-- valendo: o mesmo produto não aparece duas vezes no mesmo kit — nem como
-- obrigatório e opcional ao mesmo tempo. Conferido contra as 14 páginas de
-- kit do catálogo Tecomec 2026: nenhum kit repete produto entre os dois
-- grupos, então a restrição não precisa de exceção.

-- ── 2. Preço derivado, agora separando base de opções ───────
-- O preço do kit continua DERIVADO dos componentes, nunca armazenado.
-- Mudança de semântica: `components_total` passa a somar apenas os itens
-- OBRIGATÓRIOS — é o preço-base do kit. O que é opcional só entra no
-- total quando o vendedor escolher, e isso acontece no orçamento.
-- Como todo item existente vira `required` pelo default, nenhum número
-- muda para os kits já cadastrados.
drop view if exists public.kits_with_price;

create view public.kits_with_price
with (security_invoker = true) as
select
  k.id,
  k.code,
  k.name,
  k.description,
  k.category_id,
  k.image_url,
  k.discount_percent,
  k.is_active,
  k.created_at,
  k.updated_at,
  coalesce(c.items_count, 0)      as items_count,
  coalesce(c.required_count, 0)   as required_count,
  coalesce(c.optional_count, 0)   as optional_count,
  -- base do kit: só o que é obrigatório
  coalesce(c.components_total, 0) as components_total,
  -- catálogo de opções: informativo, não entra no preço-base
  coalesce(c.optional_total, 0)   as optional_total,
  round(coalesce(c.components_total, 0) * (1 - k.discount_percent / 100), 2) as suggested_price
from public.kits k
left join lateral (
  select
    count(*)::int                                                     as items_count,
    count(*) filter (where ki.item_type = 'required')::int            as required_count,
    count(*) filter (where ki.item_type = 'optional')::int            as optional_count,
    sum(ki.quantity * p.sale_price) filter (where ki.item_type = 'required') as components_total,
    sum(ki.quantity * p.sale_price) filter (where ki.item_type = 'optional') as optional_total
  from public.kit_items ki
  join public.products p on p.id = ki.product_id
  where ki.kit_id = k.id
) c on true
where k.deleted_at is null;

comment on view public.kits_with_price is
  'Kit com preço derivado. components_total soma apenas os itens obrigatórios (preço-base); optional_total é informativo. Nada de custo aqui: a view lê products.sale_price, e o custo vive em product_costs com RLS de admin.';

-- ── 3. Kit citado em orçamento não é excluído fisicamente ───
-- Até aqui, apagar um kit anulava a referência no histórico
-- (`on delete set null`). A diretriz da Fase 3 é mais forte: kit com
-- referência histórica não se apaga, se desativa. Trocamos por `restrict`,
-- que faz o BANCO recusar a exclusão.
--
-- Por que produto continua com `set null` e kit passa a `restrict`:
-- a massa de teste é composta de PRODUTOS e precisa sair inteira com
-- `purge_test_products()`; nenhum requisito equivalente existe para kits.
-- A assimetria é deliberada, não descuido.
alter table public.quote_items
  drop constraint if exists quote_items_kit_id_fkey;

alter table public.quote_items
  add constraint quote_items_kit_id_fkey
  foreign key (kit_id) references public.kits(id) on delete restrict;

comment on constraint quote_items_kit_id_fkey on public.quote_items is
  'restrict: kit usado em orçamento não pode ser excluído fisicamente. A operação prevista é desativar, que preserva composição e histórico.';

-- ── 4. RLS: nada a alterar ──────────────────────────────────
-- As policies de 0800 já dizem o necessário e foram conferidas:
--   kits_select / kit_items_select  → qualquer usuário ATIVO lê (o vendedor
--       precisa ler inclusive kit desativado, para abrir um orçamento antigo);
--   kits_admin / kit_items_admin    → `for all` sob is_admin(), ou seja, criar,
--       editar, ativar, desativar e excluir são exclusivos do administrador,
--       em kits E em kit_items.
-- O vendedor não tem NENHUMA policy de escrita nas duas tabelas: a recusa
-- vem do banco, não de esconder botão.
