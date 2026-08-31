-- ============================================================
-- 1100 · Correções de RLS e índices de apoio
--
-- Origem: auditoria de 29/08/2026 (ver supabase/tests/04_auditoria_rls.sql).
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── BRECHA 1 ────────────────────────────────────────────────
-- `quotes` já impedia o vendedor de editar um orçamento APROVADO,
-- mas `quote_items` só checava a posse. Na prática o vendedor
-- conseguia alterar o preço de um item — ou apagá-lo — de um
-- orçamento já aprovado, e o trigger recalculava o total.
-- Proposta aceita não pode mudar de valor por conta própria.

create or replace function public.quote_is_editable(p_quote_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.quotes q
    where q.id = p_quote_id
      and q.deleted_at is null
      and (public.is_admin() or (q.owner_id = auth.uid() and q.status <> 'approved'))
  );
$$;

revoke execute on function public.quote_is_editable(uuid) from public;
grant  execute on function public.quote_is_editable(uuid) to authenticated, service_role;

drop policy if exists quote_items_write on public.quote_items;

create policy quote_items_insert on public.quote_items
  for insert to authenticated
  with check (public.quote_is_editable(quote_id));

create policy quote_items_update on public.quote_items
  for update to authenticated
  using (public.quote_is_editable(quote_id))
  with check (public.quote_is_editable(quote_id));

create policy quote_items_delete on public.quote_items
  for delete to authenticated
  using (public.quote_is_editable(quote_id));

-- ── BRECHA 2 (defesa em profundidade) ───────────────────────
-- Um usuário desativado não deve conseguir tocar no próprio perfil.
-- Hoje o scan da policy de SELECT já barra, mas depender desse
-- efeito colateral é frágil: a regra passa a ser explícita.
drop policy if exists profiles_update_self on public.profiles;

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid() and public.is_active_user())
  with check (
    id = auth.uid()
    and public.is_active_user()
    and role = public.auth_role()          -- não pode se promover
  );

-- ── Índices de apoio a chaves estrangeiras ──────────────────
-- Somente onde há consulta ou verificação real de integridade.
-- Colunas de auditoria (created_by/updated_by) ficam sem índice
-- de propósito: só participam do ON DELETE SET NULL e custariam
-- escrita em todo insert.
create index if not exists idx_kit_items_product   on public.kit_items   (product_id);
create index if not exists idx_quote_items_product on public.quote_items (product_id) where product_id is not null;
create index if not exists idx_quote_items_kit     on public.quote_items (kit_id)     where kit_id is not null;
create index if not exists idx_kits_category       on public.kits        (category_id) where deleted_at is null;
create index if not exists idx_products_unit       on public.products    (unit_id)     where deleted_at is null;
