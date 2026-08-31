-- ============================================================
-- 0800 · Row Level Security
-- Regra do projeto: TODA tabela tem RLS habilitado.
-- A aplicação é a segunda camada; esta aqui é a que vale.
-- ============================================================

alter table public.profiles           enable row level security;
alter table public.units              enable row level security;
alter table public.categories         enable row level security;
alter table public.brands             enable row level security;
alter table public.products           enable row level security;
alter table public.customers          enable row level security;
alter table public.kits               enable row level security;
alter table public.kit_items          enable row level security;
alter table public.quotes             enable row level security;
alter table public.quote_items        enable row level security;
alter table public.quote_share_tokens enable row level security;
alter table public.quote_sequences    enable row level security;
alter table public.app_settings       enable row level security;

-- ── profiles ────────────────────────────────────────────────
create policy profiles_select on public.profiles
  for select to authenticated
  using (public.is_active_user());

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.auth_role());  -- não pode se promover

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ── Tabelas de apoio: leitura para todos, escrita só admin ──
create policy units_select on public.units
  for select to authenticated using (public.is_active_user());
create policy units_admin on public.units
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy categories_select on public.categories
  for select to authenticated using (public.is_active_user() and deleted_at is null);
create policy categories_admin on public.categories
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy brands_select on public.brands
  for select to authenticated using (public.is_active_user() and deleted_at is null);
create policy brands_admin on public.brands
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── products ────────────────────────────────────────────────
-- Vendedor lê o catálogo; somente admin cria/edita preço.
-- OBS.: Postgres não filtra COLUNA por papel de aplicação. O custo e a
-- margem são omitidos pelo repositório do vendedor (products_catalog).
-- Se isso virar exigência forte, a Fase 2 move custo para a tabela
-- `product_costs`, com RLS própria de admin. Está previsto e é barato.
create policy products_select on public.products
  for select to authenticated using (public.is_active_user() and deleted_at is null);
create policy products_admin on public.products
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── customers ───────────────────────────────────────────────
-- Todos leem e cadastram; excluir (soft delete) só admin.
create policy customers_select on public.customers
  for select to authenticated using (public.is_active_user() and deleted_at is null);
create policy customers_insert on public.customers
  for insert to authenticated with check (public.is_active_user());
create policy customers_update on public.customers
  for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
create policy customers_admin on public.customers
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── kits ────────────────────────────────────────────────────
create policy kits_select on public.kits
  for select to authenticated using (public.is_active_user() and deleted_at is null);
create policy kits_admin on public.kits
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy kit_items_select on public.kit_items
  for select to authenticated using (public.is_active_user());
create policy kit_items_admin on public.kit_items
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── quotes ──────────────────────────────────────────────────
create or replace function public.owns_quote(p_quote_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.quotes q
    where q.id = p_quote_id and q.owner_id = auth.uid()
  );
$$;

create policy quotes_select on public.quotes
  for select to authenticated
  using (deleted_at is null and (public.is_admin() or owner_id = auth.uid()));

create policy quotes_insert on public.quotes
  for insert to authenticated
  with check (public.is_active_user() and (public.is_admin() or owner_id = auth.uid()));

-- Orçamento aprovado fica travado para o vendedor: só admin altera.
create policy quotes_update on public.quotes
  for update to authenticated
  using (
    deleted_at is null and (
      public.is_admin() or (owner_id = auth.uid() and status in ('draft','sent','rejected','expired'))
    )
  )
  with check (
    public.is_admin() or (owner_id = auth.uid())
  );

create policy quotes_delete_admin on public.quotes
  for delete to authenticated using (public.is_admin());

-- ── quote_items ─────────────────────────────────────────────
create policy quote_items_select on public.quote_items
  for select to authenticated
  using (public.is_admin() or public.owns_quote(quote_id));

create policy quote_items_write on public.quote_items
  for all to authenticated
  using (public.is_admin() or public.owns_quote(quote_id))
  with check (public.is_admin() or public.owns_quote(quote_id));

-- ── quote_share_tokens ──────────────────────────────────────
create policy share_tokens_all on public.quote_share_tokens
  for all to authenticated
  using (public.is_admin() or public.owns_quote(quote_id))
  with check (public.is_admin() or public.owns_quote(quote_id));

-- ── quote_sequences ─────────────────────────────────────────
-- Ninguém lê nem escreve direto: só a função next_quote_number
-- (security definer) mexe nela. Sem policy = sem acesso.

-- ── app_settings ────────────────────────────────────────────
create policy app_settings_admin on public.app_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Leitura dos dados públicos da empresa (usados no cabeçalho e no PDF).
create policy app_settings_read_company on public.app_settings
  for select to authenticated using (public.is_active_user() and key = 'company');
