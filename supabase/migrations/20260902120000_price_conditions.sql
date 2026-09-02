-- ============================================================
-- 20260902120000 · Condições de preço e custo por condição
--
-- MOTIVO
-- A tabela de preços do fabricante não tem "um custo". Tem um custo À
-- VISTA e outro FATURADO, e os dois valem ao mesmo tempo. A carga de
-- catálogo que vem a seguir traz 73 produtos nessa situação.
--
-- `product_costs` nasceu na migration 1200 com PK em `product_id` —
-- literalmente uma linha por produto. Gravar só o à vista perderia
-- metade do dado; gravar os dois quebraria a PK. Por isso a condição
-- entra ANTES da carga, não depois.
--
-- COMPATIBILIDADE
-- Nenhum `insert into product_costs (product_id, cost_price)` existente
-- precisa mudar: um trigger BEFORE INSERT preenche `condition_id` com a
-- condição padrão quando ela vem nula. A `products_list` continua com as
-- mesmas colunas e continua devolvendo UMA linha por produto — a do
-- custo vigente na condição padrão.
--
-- O único ponto do aplicativo que muda é `upsertCost()`: o PostgREST não
-- infere índice parcial em `onConflict`, então a escrita passa por
-- `set_product_cost()`, que é SECURITY INVOKER — a RLS de administrador
-- continua sendo a única autorização.
-- ============================================================

-- ── Condições de pagamento comprovadas pelas fontes ─────────
-- Só AVISTA e FATURADO. As tabelas DJI e JR não trazem uma terceira.
create table public.price_conditions (
  id           uuid primary key default gen_random_uuid(),
  code         text not null,
  name         text not null,
  description  text,
  payment_days integer not null default 0 check (payment_days >= 0),
  -- Condição usada quando quem grava não diz qual é. Existe no máximo uma.
  is_default   boolean not null default false,
  is_active    boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index idx_price_conditions_code
  on public.price_conditions (upper(code));

-- Índice parcial: garante no máximo UMA condição padrão, sem impedir
-- que todas as outras sejam `false`.
create unique index idx_price_conditions_default
  on public.price_conditions (is_default) where is_default;

create trigger trg_price_conditions_updated_at
  before update on public.price_conditions
  for each row execute function public.set_updated_at();

comment on table public.price_conditions is
  'Condições de pagamento que as tabelas de fabricante comprovam. Não é preço: é o rótulo sob o qual um custo vale.';

insert into public.price_conditions (code, name, description, payment_days, is_default, sort_order) values
  ('AVISTA',   'À vista',          'Pagamento à vista, sem parcelamento.',                          0, true,  1),
  ('FATURADO', 'Faturado 30 dias', '50% de entrada e o saldo em 30 dias — regra 1 da tabela DJI.', 30, false, 2)
on conflict do nothing;

alter table public.price_conditions enable row level security;

-- Leitura para qualquer usuário ativo: é rótulo, não custo. Escrita só
-- administrador, como todo cadastro de apoio do projeto.
create policy price_conditions_select on public.price_conditions
  for select to authenticated
  using ((select public.is_active_user()));
create policy price_conditions_insert on public.price_conditions
  for insert to authenticated with check ((select public.is_admin()));
create policy price_conditions_update on public.price_conditions
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy price_conditions_delete on public.price_conditions
  for delete to authenticated using ((select public.is_admin()));

grant select, insert, update, delete on public.price_conditions to authenticated;
grant all on public.price_conditions to service_role;

-- ── product_costs: uma linha por produto E condição ─────────
alter table public.product_costs
  add column id               uuid not null default gen_random_uuid(),
  add column condition_id     uuid references public.price_conditions(id) on delete restrict,
  add column valid_from       date not null default current_date,
  add column valid_to         date,
  add column source_catalog   text,
  add column source_version   text,
  add column source_reference text;

-- O custo que já existia não tinha rótulo. Ele passa a ser o da condição
-- padrão — a leitura menos surpreendente, e a única que preserva o que a
-- `products_list` já mostrava.
update public.product_costs
   set condition_id = (select id from public.price_conditions where is_default),
       valid_from   = created_at::date
 where condition_id is null;

alter table public.product_costs alter column condition_id set not null;

alter table public.product_costs drop constraint product_costs_pkey;
alter table public.product_costs add constraint product_costs_pkey primary key (id);

alter table public.product_costs
  add constraint chk_product_costs_vigencia
  check (valid_to is null or valid_to >= valid_from);

-- Duas travas diferentes, e as duas são necessárias:
--   1. o mesmo produto/condição não pode ter duas linhas começando no
--      mesmo dia (histórico duplicado);
--   2. o mesmo produto/condição não pode ter dois custos VIGENTES.
create unique index idx_product_costs_historico
  on public.product_costs (product_id, condition_id, valid_from);
create unique index idx_product_costs_vigente
  on public.product_costs (product_id, condition_id) where valid_to is null;

create index idx_product_costs_product on public.product_costs (product_id);

comment on column public.product_costs.condition_id is
  'Sob qual condição de pagamento este custo vale. Preenchida com a condição padrão quando não informada.';
comment on column public.product_costs.valid_to is
  'Nulo = vigente. Histórico fecha a vigência; nunca apaga a linha.';

-- ── Retrocompatibilidade: condição padrão implícita ─────────
-- Sem isto, todo `insert into product_costs (product_id, cost_price)` que
-- já existe no código e nos testes quebraria com not-null violation.
create or replace function public.set_default_price_condition()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.condition_id is null then
    select id into new.condition_id
      from public.price_conditions
     where is_default
     limit 1;
    if new.condition_id is null then
      raise exception 'Nenhuma condicao de preco padrao configurada em price_conditions';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_product_costs_default_condition
  before insert on public.product_costs
  for each row execute function public.set_default_price_condition();

-- Função de trigger não é RPC: sem isto nasceria com EXECUTE para anon e
-- authenticated e viraria aviso do Security Advisor.
revoke execute on function public.set_default_price_condition() from public, anon, authenticated;

-- ── Escrita do custo pela aplicação ─────────────────────────
-- SECURITY INVOKER de propósito: quem autoriza é a RLS de
-- `product_costs`, não a função. Um vendedor que chame isto direto pela
-- API recebe a mesma recusa que receberia no INSERT.
create or replace function public.set_product_cost(
  p_product_id     uuid,
  p_cost_price     numeric,
  p_condition_code text default null,
  p_updated_by     uuid default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_condition uuid;
begin
  select id into v_condition
    from public.price_conditions
   where case when p_condition_code is null
              then is_default
              else upper(code) = upper(p_condition_code)
         end
   limit 1;

  if v_condition is null then
    raise exception 'Condicao de preco % nao existe', coalesce(p_condition_code, '(padrao)');
  end if;

  insert into public.product_costs (product_id, condition_id, cost_price, updated_by)
  values (p_product_id, v_condition, p_cost_price, p_updated_by)
  on conflict (product_id, condition_id) where valid_to is null
  do update set cost_price = excluded.cost_price,
                updated_by = excluded.updated_by;
end;
$$;

comment on function public.set_product_cost(uuid, numeric, text, uuid) is
  'Grava o custo vigente do produto na condição informada (padrão quando omitida). SECURITY INVOKER: a RLS de administrador de product_costs continua sendo a autorização.';

revoke execute on function public.set_product_cost(uuid, numeric, text, uuid) from public, anon;
grant  execute on function public.set_product_cost(uuid, numeric, text, uuid) to authenticated, service_role;

-- ── A view volta a devolver UMA linha por produto ───────────
-- Sem esta recriação, o LEFT JOIN antigo multiplicaria o produto por
-- quantas condições de custo ele tivesse — e a listagem passaria a
-- mostrar o mesmo produto duas vezes.
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
left join public.price_conditions dc on dc.is_default
left join public.product_costs pc
       on pc.product_id = p.id
      and pc.condition_id = dc.id
      and pc.valid_to is null
left join public.categories c on c.id = p.category_id
left join public.brands     b on b.id = p.brand_id
left join public.units      u on u.id = p.unit_id
where p.deleted_at is null;
