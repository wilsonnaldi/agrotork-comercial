-- ============================================================
-- 20260902120100 · "Sem preço definido" deixa de ser R$ 0,00
--
-- MOTIVO
-- `products.sale_price` é `not null default 0`. Isso torna R$ 0,00 e
-- "ainda não definido" indistinguíveis — e a carga de catálogo que vem a
-- seguir tem 112 produtos exatamente nesse estado: fonte comercial
-- confirmada, preço de venda ainda não aprovado. Sem esta coluna, o
-- catálogo nasceria valendo zero sem ninguém perceber.
--
-- DECISÃO
-- `sale_price` continua `numeric(14,2) not null` — nenhum cálculo do
-- sistema precisa lidar com nulo. Quem carrega a semântica é
-- `sale_price_set_at`:
--
--   sale_price_set_at IS NULL      → preço nunca foi definido
--   sale_price_set_at IS NOT NULL  → preço definido, mesmo que 0,00
--
-- RETROCOMPATIBILIDADE
-- Nenhum código lê ou grava esta coluna hoje. O formulário de produto já
-- exige `sale_price > 0` (products/schema.ts), então todo produto criado
-- pelo aplicativo tem preço deliberado — por isso o backfill carimba os
-- que têm `sale_price > 0` e deixa nulo o que estiver em zero, que é
-- justamente o estado que não sabemos explicar.
-- ============================================================

alter table public.products
  add column sale_price_set_at timestamptz;

comment on column public.products.sale_price_set_at is
  'Quando o preço de venda foi definido. Nulo = nunca definido (diferente de definido como R$ 0,00). Preenchida por trigger.';

-- Backfill conservador: só carimba o que tem preço maior que zero. Não
-- inventa data — usa a criação do registro, a única evidência disponível.
update public.products
   set sale_price_set_at = created_at
 where sale_price > 0
   and sale_price_set_at is null;

-- ── O carimbo é do banco, não da aplicação ──────────────────
-- Assim vale para qualquer caminho de escrita: formulário, importador,
-- SQL direto do administrador.
create or replace function public.stamp_sale_price_set_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Inserir com zero é o caso da importação: preço ainda não definido.
    -- Quem quiser inserir um zero DELIBERADO informa o carimbo na mão.
    if new.sale_price_set_at is null and new.sale_price > 0 then
      new.sale_price_set_at := now();
    end if;
  elsif new.sale_price is distinct from old.sale_price then
    -- Mudou o preço: passou a ser definido, inclusive se mudou PARA zero.
    new.sale_price_set_at := now();
  end if;
  return new;
end;
$$;

create trigger trg_products_sale_price_set_at
  before insert or update on public.products
  for each row execute function public.stamp_sale_price_set_at();

revoke execute on function public.stamp_sale_price_set_at() from public, anon, authenticated;

-- ── A listagem passa a mostrar o estado do preço ────────────
-- Coluna acrescentada ao fim: nenhuma posição existente muda.
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
  p.sale_price_set_at,
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
left join public.price_conditions dc on dc.is_default
left join public.product_costs pc
       on pc.product_id = p.id
      and pc.condition_id = dc.id
      and pc.valid_to is null
left join public.categories c on c.id = p.category_id
left join public.brands     b on b.id = p.brand_id
left join public.units      u on u.id = p.unit_id
where p.deleted_at is null;
