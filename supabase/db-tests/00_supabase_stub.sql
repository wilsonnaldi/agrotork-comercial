-- ============================================================
-- Base mínima para os testes rodarem nos DOIS ambientes:
--
--   A) PostgreSQL puro e descartável (`npm run db:test`, `check-types.sh`),
--      onde nada do Supabase existe e precisa ser reproduzido;
--   B) Supabase local de verdade (`supabase test db`), onde `auth` e
--      `storage` JÁ existem, são de outros donos e não aceitam que a gente
--      recrie nada dentro deles.
--
-- Por isso cada bloco abaixo só age quando o objeto NÃO existe. No
-- ambiente B o arquivo inteiro vira quase um no-op — e é assim que deve
-- ser: quanto mais nativo o objeto, mais fiel o teste.
-- ============================================================

-- ── Papéis ──────────────────────────────────────────────────
-- No Supabase local já existem; num PostgreSQL puro, não.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;

-- ── Schema auth ─────────────────────────────────────────────
-- `auth.users`, `auth.uid()` e `auth.role()` são do GoTrue. Onde eles
-- existem, usamos os nativos: as duas funções nativas leem
-- `request.jwt.claim.sub` / `request.jwt.claim.role` exatamente como a
-- reprodução abaixo, então os testes não mudam de comportamento.
do $$
begin
  if to_regclass('auth.users') is null then
    create schema if not exists auth;

    create table auth.users (
      id uuid primary key default gen_random_uuid(),
      email text,
      encrypted_password text,          -- no duplê de teste: sha256 do texto informado
      raw_user_meta_data jsonb default '{}'::jsonb,
      created_at timestamptz default now()
    );
  end if;

  if to_regprocedure('auth.uid()') is null then
    execute $fn$
      create function auth.uid() returns uuid
      language sql stable as 'select nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid'
    $fn$;
  end if;

  if to_regprocedure('auth.role()') is null then
    execute $fn$
      create function auth.role() returns text
      language sql stable as 'select current_setting(''request.jwt.claim.role'', true)'
    $fn$;
  end if;
end $$;

-- ── Privilégios do schema public ────────────────────────────
-- Reproduz os default privileges que o Supabase já traz configurados.
-- Idempotente e inofensivo onde já valem.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

-- ── Schema storage ──────────────────────────────────────────
-- Reproduz o mínimo do `storage` do Supabase para que as policies de
-- bucket sejam EXERCITADAS no ambiente A — só `buckets`, `objects` e o
-- que as nossas policies tocam. No ambiente B nada disto roda: o storage
-- nativo é melhor do que qualquer reprodução.
do $$
begin
  if to_regclass('storage.objects') is not null then
    return;
  end if;

  create schema if not exists storage;

  create table storage.buckets (
    id                 text primary key,
    name               text not null,
    public             boolean not null default false,
    file_size_limit    bigint,
    allowed_mime_types text[],
    created_at         timestamptz not null default now()
  );

  create table storage.objects (
    id         uuid primary key default gen_random_uuid(),
    bucket_id  text not null references storage.buckets(id) on delete cascade,
    name       text not null,
    owner      uuid,
    metadata   jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (bucket_id, name)
  );

  -- No Supabase real estas duas tabelas já vêm com RLS ligado.
  alter table storage.buckets enable row level security;
  alter table storage.objects enable row level security;

  grant usage on schema storage to anon, authenticated, service_role;
  grant select on storage.buckets to anon, authenticated;
  grant select, insert, update, delete on storage.objects to authenticated;
  grant select on storage.objects to anon;

  -- `storage.foldername('pasta/arquivo.png')` devolve {pasta}. É a função
  -- que as policies do Supabase usam para separar por pasta.
  execute $fn$
    create function storage.foldername(name text)
    returns text[] language sql immutable as
    'select string_to_array(regexp_replace(name, ''/[^/]*$'', ''''), ''/'')'
  $fn$;
end $$;
