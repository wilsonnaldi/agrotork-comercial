create or replace function public.owns_quote(p_quote_id uuid)
returns boolean
language sql
stable security definer
set search_path = ''
as $function$
  select (select public.is_active_user()) and exists (
    select 1
    from public.quotes q
    where q.id = p_quote_id
      and q.owner_id = (select auth.uid())
  );
$function$;

create or replace function public.quote_is_editable(p_quote_id uuid)
returns boolean
language sql
stable security definer
set search_path = ''
as $function$
  select (select public.is_active_user()) and exists (
    select 1
    from public.quotes q
    where q.id = p_quote_id
      and q.deleted_at is null
      and (
        (select public.is_admin())
        or (
          q.owner_id = (select auth.uid())
          and q.status not in ('approved', 'cancelled')
        )
      )
  );
$function$;