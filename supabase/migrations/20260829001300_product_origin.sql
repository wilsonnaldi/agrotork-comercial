-- ============================================================
-- 1300 · Origem do produto e código do fabricante
--
-- Prepara `products` para receber, no futuro, catálogos oficiais de
-- fabricantes (AGRES, ARAG, DJI, KUHN…). O importador NÃO é criado
-- aqui — esta migration apenas garante que o modelo não impeça o fluxo:
--
--   CATÁLOGO DO FABRICANTE → IMPORTAÇÃO → ÁREA DE REVISÃO
--   → NOVOS / ALTERAÇÕES / CONFLITOS → APROVAÇÃO → CATÁLOGO AGROTORK
--
-- Duas regras que o modelo passa a sustentar:
--   1. o código do fabricante identifica o produto de forma confiável;
--   2. cadastro técnico e preço são coisas separadas — o catálogo do
--      fabricante nunca traz preço, e a tabela de preços casa pelo
--      código do fabricante.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── De onde veio o cadastro ─────────────────────────────────
create type public.product_source_type as enum (
  'manual',                -- digitado por alguém no sistema
  'manufacturer_catalog',  -- veio de catálogo oficial de fabricante
  'price_list',            -- veio de uma tabela de preços
  'test_data'              -- massa de teste; descartável (ver purge_test_products)
);

alter table public.products
  -- Código original de fábrica. É a chave de correspondência entre o
  -- catálogo do fabricante, a tabela de preços e o nosso cadastro.
  add column manufacturer_code text,

  -- Procedência do registro. Preenchida pelo futuro importador.
  add column source_type        public.product_source_type not null default 'manual',
  add column source_brand       text,   -- ex.: 'AGRES'
  add column source_catalog     text,   -- ex.: 'AGRIS 2026'
  add column source_reference   text,   -- página, linha, arquivo de origem
  add column source_version     text,   -- versão/edição do catálogo
  add column source_imported_at timestamptz,

  -- Características e aplicação vindas do catálogo. Cada fabricante
  -- descreve o produto do seu jeito; um jsonb evita uma migration por
  -- atributo novo. Nada de preço aqui.
  add column technical_data jsonb not null default '{}'::jsonb;

comment on column public.products.manufacturer_code is
  'Código original de fábrica. Chave de correspondência para importação de catálogos e de tabelas de preços.';
comment on column public.products.technical_data is
  'Características técnicas do catálogo do fabricante. Nunca contém preço.';

-- Código de fabricante sem fabricante não identifica nada.
alter table public.products
  add constraint chk_products_manufacturer_brand
  check (manufacturer_code is null or brand_id is not null);

-- Único **por fabricante**: dois fabricantes podem usar o mesmo código.
create unique index idx_products_manufacturer_code
  on public.products (brand_id, upper(manufacturer_code))
  where manufacturer_code is not null and deleted_at is null;

-- ── A view passa a expor procedência ────────────────────────
-- `create or replace` não aceita inserir coluna no meio; recriamos.
drop view if exists public.products_list;

create view public.products_list
with (security_invoker = true) as
select
  p.id,
  p.code,
  p.manufacturer_code,
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
  p.source_type,
  p.source_brand,
  p.source_catalog,
  p.source_reference,
  p.source_version,
  p.source_imported_at,
  p.technical_data,
  p.created_at,
  p.updated_at
from public.products p
left join public.product_costs pc on pc.product_id = p.id
left join public.categories   c  on c.id = p.category_id
left join public.brands       b  on b.id = p.brand_id
left join public.units        u  on u.id = p.unit_id
where p.deleted_at is null;

-- ── Massa de teste: identificável e descartável ─────────────
-- Os produtos vindos das planilhas internas (AGROTORK 23 e afins) entram
-- como `test_data`. Não são catálogo oficial e precisam sair sem deixar
-- rastro quando o catálogo de verdade chegar.
--
-- Orçamentos antigos não se perdem: `quote_items` guarda cópia dos dados
-- e sua FK é `on delete set null`.
create or replace function public.purge_test_products()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removed integer;
begin
  -- Kits de teste que apontam para esses produtos saem junto.
  delete from public.kit_items ki
   using public.products p
   where ki.product_id = p.id
     and p.source_type = 'test_data';

  with removed as (
    delete from public.products
     where source_type = 'test_data'
    returning 1
  )
  select count(*)::int into v_removed from removed;

  return v_removed;
end;
$$;

revoke execute on function public.purge_test_products() from public, anon, authenticated;
grant  execute on function public.purge_test_products() to service_role;
