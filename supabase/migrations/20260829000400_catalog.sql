-- ============================================================
-- 0400 · Catálogo: unidades, categorias, marcas e produtos
-- ============================================================

-- ── Unidades de medida (configuráveis, não fixas no código) ──
create table public.units (
  id              uuid primary key default gen_random_uuid(),
  code            text not null,
  name            text not null,
  allows_fraction boolean not null default false,
  is_active       boolean not null default true,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index idx_units_code on public.units (upper(code));
create trigger trg_units_updated_at before update on public.units
  for each row execute function public.set_updated_at();

-- ── Categorias ───────────────────────────────────────────────
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null,
  parent_id   uuid references public.categories(id) on delete set null,
  description text,
  is_active   boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create unique index idx_categories_slug on public.categories (slug) where deleted_at is null;
create index idx_categories_parent on public.categories (parent_id);
create trigger trg_categories_updated_at before update on public.categories
  for each row execute function public.set_updated_at();

-- ── Marcas ───────────────────────────────────────────────────
create table public.brands (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text not null,
  logo_url   text,
  website    text,
  is_active  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index idx_brands_slug on public.brands (slug) where deleted_at is null;
create trigger trg_brands_updated_at before update on public.brands
  for each row execute function public.set_updated_at();

-- ── Produtos ─────────────────────────────────────────────────
create table public.products (
  id             uuid primary key default gen_random_uuid(),
  code           text not null,
  name           text not null,
  description    text,
  category_id    uuid references public.categories(id) on delete restrict,
  brand_id       uuid references public.brands(id)     on delete restrict,
  unit_id        uuid not null references public.units(id) on delete restrict,

  cost_price     numeric(14,2) not null default 0 check (cost_price >= 0),
  sale_price     numeric(14,2) not null default 0 check (sale_price >= 0),
  -- Margem calculada pelo banco: nunca digitada, nunca desatualizada.
  margin_percent numeric(7,4) generated always as (
    case when cost_price > 0
         then round(((sale_price - cost_price) / cost_price) * 100, 4)
         else null end
  ) stored,

  image_url      text,
  notes          text,
  is_active      boolean not null default true,

  created_by     uuid references public.profiles(id) on delete set null,
  updated_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create unique index idx_products_code on public.products (upper(code)) where deleted_at is null;
create index idx_products_category on public.products (category_id) where deleted_at is null;
create index idx_products_brand    on public.products (brand_id)    where deleted_at is null;
create index idx_products_active   on public.products (is_active)   where deleted_at is null;
create index idx_products_name_trgm on public.products using gin (name gin_trgm_ops);

create trigger trg_products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

-- View sem dados de custo — é o que o vendedor enxerga.
create view public.products_catalog
with (security_invoker = true) as
select p.id, p.code, p.name, p.description, p.category_id, p.brand_id, p.unit_id,
       p.sale_price, p.image_url, p.is_active, p.created_at, p.updated_at
from public.products p
where p.deleted_at is null;

-- ── Clientes ─────────────────────────────────────────────────
create table public.customers (
  id                 uuid primary key default gen_random_uuid(),
  person_type        public.person_type not null default 'company',
  name               text not null,
  trade_name         text,
  document           text,                     -- CPF/CNPJ, somente dígitos
  state_registration text,
  phone              text,
  whatsapp           text,
  email              text,
  address            text,
  address_number     text,
  address_complement text,
  district           text,
  city               text,
  state              char(2),
  zip_code           text,
  notes              text,
  is_active          boolean not null default true,

  created_by         uuid references public.profiles(id) on delete set null,
  updated_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

create unique index idx_customers_document on public.customers (document)
  where document is not null and deleted_at is null;
create index idx_customers_name_trgm on public.customers using gin (name gin_trgm_ops);
create index idx_customers_city on public.customers (city) where deleted_at is null;

create trigger trg_customers_updated_at before update on public.customers
  for each row execute function public.set_updated_at();

-- Normaliza documento/CEP para só dígitos, sempre.
create or replace function public.normalize_customer()
returns trigger language plpgsql as $$
begin
  new.document := public.only_digits(new.document);
  new.zip_code := public.only_digits(new.zip_code);
  new.state    := upper(nullif(new.state, ''));
  return new;
end;
$$;

create trigger trg_customers_normalize
  before insert or update on public.customers
  for each row execute function public.normalize_customer();
