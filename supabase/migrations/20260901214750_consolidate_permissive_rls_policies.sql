begin;

-- Replace overlapping admin ALL + read policies with equivalent per-command policies.
-- This preserves authorization semantics while avoiding multiple permissive policies.

-- app_settings
drop policy if exists app_settings_admin on public.app_settings;
drop policy if exists app_settings_read_company on public.app_settings;
create policy app_settings_select on public.app_settings
  for select to authenticated
  using ((select is_admin()) or ((select is_active_user()) and key = 'company'));
create policy app_settings_insert on public.app_settings
  for insert to authenticated with check ((select is_admin()));
create policy app_settings_update on public.app_settings
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy app_settings_delete on public.app_settings
  for delete to authenticated using ((select is_admin()));

-- brands
drop policy if exists brands_admin on public.brands;
drop policy if exists brands_select on public.brands;
create policy brands_select on public.brands
  for select to authenticated
  using ((select is_active_user()) and deleted_at is null);
create policy brands_insert on public.brands
  for insert to authenticated with check ((select is_admin()));
create policy brands_update on public.brands
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy brands_delete on public.brands
  for delete to authenticated using ((select is_admin()));

-- categories
drop policy if exists categories_admin on public.categories;
drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select to authenticated
  using ((select is_active_user()) and deleted_at is null);
create policy categories_insert on public.categories
  for insert to authenticated with check ((select is_admin()));
create policy categories_update on public.categories
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy categories_delete on public.categories
  for delete to authenticated using ((select is_admin()));

-- customers
drop policy if exists customers_admin on public.customers;
drop policy if exists customers_insert on public.customers;
drop policy if exists customers_select on public.customers;
drop policy if exists customers_update on public.customers;
create policy customers_select on public.customers
  for select to authenticated
  using ((select is_active_user()) and deleted_at is null);
create policy customers_insert on public.customers
  for insert to authenticated with check ((select is_active_user()));
create policy customers_update on public.customers
  for update to authenticated using ((select is_active_user())) with check ((select is_active_user()));
create policy customers_delete on public.customers
  for delete to authenticated using ((select is_admin()));

-- kit_items
drop policy if exists kit_items_admin on public.kit_items;
drop policy if exists kit_items_select on public.kit_items;
create policy kit_items_select on public.kit_items
  for select to authenticated using ((select is_active_user()));
create policy kit_items_insert on public.kit_items
  for insert to authenticated with check ((select is_admin()));
create policy kit_items_update on public.kit_items
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy kit_items_delete on public.kit_items
  for delete to authenticated using ((select is_admin()));

-- kits
drop policy if exists kits_admin on public.kits;
drop policy if exists kits_select on public.kits;
create policy kits_select on public.kits
  for select to authenticated
  using ((select is_active_user()) and deleted_at is null);
create policy kits_insert on public.kits
  for insert to authenticated with check ((select is_admin()));
create policy kits_update on public.kits
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy kits_delete on public.kits
  for delete to authenticated using ((select is_admin()));

-- products
drop policy if exists products_admin on public.products;
drop policy if exists products_select on public.products;
create policy products_select on public.products
  for select to authenticated
  using ((select is_active_user()) and deleted_at is null);
create policy products_insert on public.products
  for insert to authenticated with check ((select is_admin()));
create policy products_update on public.products
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy products_delete on public.products
  for delete to authenticated using ((select is_admin()));

-- profiles
drop policy if exists profiles_admin_all on public.profiles;
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using ((select is_admin()) or (select is_active_user()));
create policy profiles_insert on public.profiles
  for insert to authenticated with check ((select is_admin()));
create policy profiles_update on public.profiles
  for update to authenticated
  using ((select is_admin()) or ((id = (select auth.uid())) and (select is_active_user())))
  with check ((select is_admin()) or ((id = (select auth.uid())) and (select is_active_user()) and (role = (select auth_role()))));
create policy profiles_delete on public.profiles
  for delete to authenticated using ((select is_admin()));

-- units
drop policy if exists units_admin on public.units;
drop policy if exists units_select on public.units;
create policy units_select on public.units
  for select to authenticated using ((select is_active_user()));
create policy units_insert on public.units
  for insert to authenticated with check ((select is_admin()));
create policy units_update on public.units
  for update to authenticated using ((select is_admin())) with check ((select is_admin()));
create policy units_delete on public.units
  for delete to authenticated using ((select is_admin()));

commit;