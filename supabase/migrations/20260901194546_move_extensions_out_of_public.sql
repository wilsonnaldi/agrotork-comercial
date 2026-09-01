create schema if not exists extensions;

alter extension pg_trgm set schema extensions;
alter extension unaccent set schema extensions;

create or replace function public.slugify(value text)
returns text
language sql
stable
set search_path = ''
as $$
  select trim(both '-' from
    regexp_replace(lower(extensions.unaccent(coalesce(value, ''))), '[^a-z0-9]+', '-', 'g')
  );
$$;

create or replace function public.set_catalog_slug()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.slug is null or new.slug = '' or (tg_op = 'UPDATE' and new.name is distinct from old.name) then
    new.slug := public.slugify(new.name);
  end if;
  return new;
end;
$$;

revoke all on schema extensions from public;
revoke all on all functions in schema extensions from public;
revoke all on all tables in schema extensions from public;

revoke all on function public.slugify(text) from anon, authenticated, public;
revoke all on function public.set_catalog_slug() from anon, authenticated, public;