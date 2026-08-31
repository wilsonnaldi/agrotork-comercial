-- ============================================================
-- 1200 · Produtos: custo isolado, margem derivada e índices
--
-- Motivo: `products.cost_price` ficava legível por qualquer usuário
-- autenticado. O Postgres não filtra COLUNA por papel de aplicação,
-- então esconder o custo na interface não era proteção de verdade.
--
-- Solução: o custo sai de `products` e vai para `product_costs`,
-- com RLS exclusiva de admin. A margem passa a ser derivada dele.
-- Um vendedor que chame a API direto recebe custo e margem NULOS.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── Tabela de custo ─────────────────────────────────────────
create table public.product_costs (
  product_id uuid primary key references public.products(id) on delete cascade,
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_product_costs_updated_at
  before update on public.product_costs
  for each row execute function public.set_updated_at();

-- Preserva o que já existir antes de remover as colunas.
insert into public.product_costs (product_id, cost_price, updated_by)
select p.id, p.cost_price, p.updated_by
from public.products p
where p.cost_price is not null
on conflict (product_id) do nothing;

-- `margin_percent` era coluna gerada a partir de `cost_price`;
-- sai junto, porque margem é informação de custo.
alter table public.products drop column if exists margin_percent;
alter table public.products drop column if exists cost_price;

-- ── RLS: somente administrador ──────────────────────────────
alter table public.product_costs enable row level security;

create policy product_costs_admin on public.product_costs
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.product_costs to authenticated;
grant select on public.product_costs to anon;
grant all on public.product_costs to service_role;

-- ── Visão de listagem ───────────────────────────────────────
-- `security_invoker` faz o RLS valer para quem consulta: o LEFT JOIN
-- simplesmente não encontra a linha de custo para o vendedor, e as
-- colunas chegam nulas. Nenhum `if` de aplicação envolvido.
drop view if exists public.products_catalog;

create view public.products_list
with (security_invoker = true) as
select
  p.id,
  p.code,
  p.name,
  p.description,
  p.category_id,
  c.name as category_name,
  p.brand_id,
  b.name as brand_name,
  p.unit_id,
  u.code as unit_code,
  u.name as unit_name,
  p.sale_price,
  pc.cost_price,
  case
    when pc.cost_price is not null and pc.cost_price > 0
      then round(((p.sale_price - pc.cost_price) / pc.cost_price) * 100, 4)
    else null
  end as margin_percent,
  p.image_url,
  p.notes,
  p.is_active,
  p.created_at,
  p.updated_at
from public.products p
left join public.product_costs pc on pc.product_id = p.id
left join public.categories   c  on c.id = p.category_id
left join public.brands       b  on b.id = p.brand_id
left join public.units        u  on u.id = p.unit_id
where p.deleted_at is null;

-- ── Índices de busca e filtro ───────────────────────────────
-- Já existiam: unique(upper(code)), name trgm, brand_id, category_id,
-- is_active, unit_id. Falta apenas a busca parcial por código.
create index if not exists idx_products_code_trgm
  on public.products using gin (code gin_trgm_ops);

-- Ordenação padrão da listagem (nome) com filtro de ativos.
create index if not exists idx_products_active_name
  on public.products (is_active, name) where deleted_at is null;
