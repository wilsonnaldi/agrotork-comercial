begin;

-- Pin security-definer authorization/public-share helpers to an empty search_path.
alter function public.auth_role() set search_path = '';
alter function public.is_active_user() set search_path = '';
alter function public.is_admin() set search_path = '';
alter function public.owns_quote(uuid) set search_path = '';
alter function public.quote_is_editable(uuid) set search_path = '';
alter function public.discard_quote_draft(uuid) set search_path = '';
alter function public.get_shared_quote(text) set search_path = '';

-- These authorization helpers are internal to RLS. They must not be callable by anon.
revoke execute on function public.auth_role() from public, anon;
revoke execute on function public.is_active_user() from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.owns_quote(uuid) from public, anon;
revoke execute on function public.quote_is_editable(uuid) from public, anon;

grant execute on function public.auth_role() to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.owns_quote(uuid) to authenticated;
grant execute on function public.quote_is_editable(uuid) to authenticated;

-- Preserve public sharing: get_shared_quote remains callable by anon/authenticated.
revoke execute on function public.get_shared_quote(text) from public;
grant execute on function public.get_shared_quote(text) to anon, authenticated;

-- Cache statement-stable auth/helper results as initPlans in the critical RLS policies.
alter policy quotes_select on public.quotes
  using ((deleted_at is null) and ((select public.is_admin()) or (owner_id = (select auth.uid()))));

alter policy quotes_insert on public.quotes
  with check ((select public.is_active_user()) and ((select public.is_admin()) or (owner_id = (select auth.uid()))));

alter policy quotes_update on public.quotes
  using ((deleted_at is null) and ((select public.is_admin()) or ((owner_id = (select auth.uid())) and (status = any (array['draft'::public.quote_status, 'sent'::public.quote_status, 'rejected'::public.quote_status, 'expired'::public.quote_status, 'cancelled'::public.quote_status])))))
  with check ((select public.is_admin()) or (owner_id = (select auth.uid())));

alter policy profiles_update_self on public.profiles
  using ((id = (select auth.uid())) and (select public.is_active_user()))
  with check ((id = (select auth.uid())) and (select public.is_active_user()) and (role = (select public.auth_role())));

commit;