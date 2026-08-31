-- ============================================================
-- 0200 · Tipos enumerados e funções utilitárias
-- ============================================================

create type public.user_role    as enum ('admin', 'salesperson');
create type public.quote_status as enum ('draft', 'sent', 'approved', 'rejected', 'expired');
create type public.person_type  as enum ('individual', 'company');
create type public.item_kind    as enum ('product', 'kit', 'custom');

-- Mantém updated_at sempre correto, sem depender da aplicação.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Slug simples e estável para categorias/marcas.
create or replace function public.slugify(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from
    regexp_replace(lower(public.unaccent(coalesce(value, ''))), '[^a-z0-9]+', '-', 'g')
  );
$$;

-- Remove tudo que não for dígito (CPF/CNPJ/CEP/telefone).
create or replace function public.only_digits(value text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(value, ''), '\D', '', 'g'), '');
$$;
