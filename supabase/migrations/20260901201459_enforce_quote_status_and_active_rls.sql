create or replace function public.validate_quote_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'draft' and new.status in ('sent', 'cancelled'))
      or (old.status = 'sent' and new.status in ('approved', 'rejected', 'expired', 'draft', 'cancelled'))
      or (old.status = 'approved' and new.status in ('draft', 'cancelled'))
      or (old.status = 'rejected' and new.status in ('draft', 'cancelled'))
      or (old.status = 'expired' and new.status in ('draft', 'cancelled'))
      or (old.status = 'cancelled' and new.status = 'draft')
    ) then
      raise exception 'Transição de orçamento inválida: % -> %', old.status, new.status
        using errcode = 'P0001';
    end if;

    if old.status = 'approved' and not (select public.is_admin()) then
      raise exception 'Somente administradores podem reabrir ou cancelar um orçamento aprovado'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$function$;

revoke execute on function public.validate_quote_status_transition() from public, anon, authenticated;

drop trigger if exists trg_quotes_validate_status_transition on public.quotes;
create trigger trg_quotes_validate_status_transition
before update on public.quotes
for each row
execute function public.validate_quote_status_transition();

drop policy if exists quotes_select on public.quotes;
create policy quotes_select
on public.quotes
for select
to authenticated
using (
  (select public.is_active_user())
  and deleted_at is null
  and ((select public.is_admin()) or owner_id = (select auth.uid()))
);

drop policy if exists quotes_update on public.quotes;
create policy quotes_update
on public.quotes
for update
to authenticated
using (
  (select public.is_active_user())
  and deleted_at is null
  and (
    (select public.is_admin())
    or (
      owner_id = (select auth.uid())
      and status = any (array['draft'::public.quote_status, 'sent'::public.quote_status, 'rejected'::public.quote_status, 'expired'::public.quote_status, 'cancelled'::public.quote_status])
    )
  )
)
with check (
  (select public.is_active_user())
  and ((select public.is_admin()) or owner_id = (select auth.uid()))
);
