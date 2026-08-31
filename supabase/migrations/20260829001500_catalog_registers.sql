-- ============================================================
-- 1500 · Cadastros de apoio: marcas, categorias e unidades
--
-- Fase 1. Três ajustes que faltavam para esses cadastros poderem
-- ser mantidos pela interface, e não por SQL:
--
--   1. `brands` não tinha `description`;
--   2. `slug` é `not null` em brands e categories, mas nada o gerava —
--      um insert vindo da aplicação falharia;
--   3. o nome não era único; só o slug era.
--
-- `brands` representa a MARCA comercial que identifica o produto.
-- Fabricante, fornecedor e distribuidor são conceitos distintos e
-- entram como tabelas próprias quando forem necessários — nada aqui
-- impede isso.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── 1. Descrição da marca ───────────────────────────────────
alter table public.brands add column if not exists description text;

-- ── 2. Slug derivado do nome ────────────────────────────────
-- Mantido porque é útil para URL amigável no futuro. Como é `not null`,
-- precisa ser preenchido sozinho: exigir que a aplicação calcule seria
-- uma pegadinha esperando acontecer.
create or replace function public.set_catalog_slug()
returns trigger
language plpgsql
as $$
begin
  if new.slug is null or new.slug = '' or (tg_op = 'UPDATE' and new.name is distinct from old.name) then
    new.slug := public.slugify(new.name);
  end if;
  return new;
end;
$$;

create trigger trg_brands_slug
  before insert or update on public.brands
  for each row execute function public.set_catalog_slug();

create trigger trg_categories_slug
  before insert or update on public.categories
  for each row execute function public.set_catalog_slug();

-- ── 3. Nome único ───────────────────────────────────────────
-- Sem distinguir maiúsculas: "Baldan" e "BALDAN" são a mesma marca.
create unique index idx_brands_name
  on public.brands (lower(name)) where deleted_at is null;

create unique index idx_categories_name
  on public.categories (lower(name)) where deleted_at is null;

-- `units` já tem `unique (upper(code))` desde a migration 0400.
-- O nome da unidade não é único de propósito: "Litro" e "Litro (LT)"
-- podem coexistir enquanto a equivalência entre L e LT não for decidida.

-- ── Ordenação das listagens ─────────────────────────────────
create index if not exists idx_brands_active_name
  on public.brands (is_active, name) where deleted_at is null;

create index if not exists idx_categories_active_name
  on public.categories (is_active, name) where deleted_at is null;

create index if not exists idx_units_active_code
  on public.units (is_active, sort_order, code);

-- ── Observações sobre integridade (nada a alterar) ──────────
--
-- `products.brand_id`, `products.category_id` e `products.unit_id` já são
-- FKs com `on delete restrict`: o banco recusa apagar uma marca, categoria
-- ou unidade que tenha produto vinculado. Não existe exclusão física na
-- interface — só ativar/desativar —, e a FK é a garantia de que nem por
-- outro caminho isso acontece.
--
-- Desativar não mexe em produto nenhum: o vínculo continua, o histórico
-- continua, e a aplicação apenas deixa de oferecer o registro inativo
-- para novos produtos.
--
-- RLS: as policies de 0800 já dizem o necessário — qualquer usuário ativo
-- lê (o vendedor precisa do nome da marca para ler a ficha de um produto,
-- inclusive de marca desativada), e só `is_admin()` escreve.
