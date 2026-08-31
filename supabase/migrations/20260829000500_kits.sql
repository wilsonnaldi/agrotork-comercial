-- ============================================================
-- 0500 · Kits e seus componentes
-- ============================================================

create table public.kits (
  id               uuid primary key default gen_random_uuid(),
  code             text not null,
  name             text not null,
  description      text,
  category_id      uuid references public.categories(id) on delete set null,
  image_url        text,
  discount_percent numeric(7,4) not null default 0 check (discount_percent >= 0 and discount_percent <= 100),
  is_active        boolean not null default true,

  created_by       uuid references public.profiles(id) on delete set null,
  updated_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

create unique index idx_kits_code on public.kits (upper(code)) where deleted_at is null;
create index idx_kits_active on public.kits (is_active) where deleted_at is null;
create index idx_kits_name_trgm on public.kits using gin (name gin_trgm_ops);

create trigger trg_kits_updated_at before update on public.kits
  for each row execute function public.set_updated_at();

create table public.kit_items (
  id         uuid primary key default gen_random_uuid(),
  kit_id     uuid not null references public.kits(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity   numeric(14,3) not null default 1 check (quantity > 0),
  sort_order integer not null default 0,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (kit_id, product_id)
);

create index idx_kit_items_kit on public.kit_items (kit_id, sort_order);
create trigger trg_kit_items_updated_at before update on public.kit_items
  for each row execute function public.set_updated_at();

-- Preço do kit é DERIVADO dos componentes — nunca armazenado,
-- para não ficar desatualizado quando um produto muda de preço.
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
  coalesce(c.items_count, 0)                                            as items_count,
  coalesce(c.components_total, 0)                                       as components_total,
  round(coalesce(c.components_total, 0) * (1 - k.discount_percent / 100), 2) as suggested_price
from public.kits k
left join lateral (
  select count(*)::int                       as items_count,
         sum(ki.quantity * p.sale_price)     as components_total
  from public.kit_items ki
  join public.products p on p.id = ki.product_id
  where ki.kit_id = k.id
) c on true
where k.deleted_at is null;
