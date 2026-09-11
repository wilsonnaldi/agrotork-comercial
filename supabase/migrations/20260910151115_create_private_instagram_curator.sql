-- ============================================================
-- instagram_curator — criação do schema privado do curador
--
-- ESTE ARQUIVO NÃO É NOVO. É a migration que já rodou em produção em
-- 10/09/2026 e que nunca tinha sido versionada: o Git não a tinha, e um
-- banco montado a partir do repositório não reproduzia produção.
--
-- O texto abaixo foi RECUPERADO em 11/09/2026 de
-- `supabase_migrations.schema_migrations.statements`, no projeto
-- nedmdkdhchkadijtdnja, e está aqui byte a byte:
--
--   comprimento  11495 caracteres
--   md5          0f336f8a8991516ff6a30c3ce265296f
--
-- Nada foi reescrito, reformatado ou "melhorado" — se fosse, deixaria de
-- ser o registro do que de fato aconteceu. A conferência está em
-- supabase/db-tests/26_instagram_curator.sql (IC7).
--
-- Em produção ela já consta como aplicada (version 20260910151115) e NÃO
-- deve ser executada lá de novo. Em banco novo, é ela que constrói.
-- ============================================================

create schema if not exists instagram_curator;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'instagram_curator' and t.typname = 'reference_status'
  ) then
    create type instagram_curator.reference_status as enum
      ('discovered','pending','processing','completed','discarded','deferred','failed');
  end if;
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'instagram_curator' and t.typname = 'run_status'
  ) then
    create type instagram_curator.run_status as enum
      ('running','succeeded','failed','blocked','partial','no_change');
  end if;
end $$;

create table if not exists instagram_curator.references (
  id uuid primary key default gen_random_uuid(),
  shortcode text,
  canonical_url text,
  observed_route text,
  source_account text,
  origin text not null,
  topic text,
  angle text,
  status instagram_curator.reference_status not null default 'discovered',
  caption text,
  like_position integer,
  discovered_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  processing_started_at timestamptz,
  completed_at timestamptz,
  deferred_until timestamptz,
  published_at timestamptz,
  legacy_key text,
  legacy_folder_label text,
  legacy_state_unverified boolean not null default false,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  last_error_sanitized text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint references_shortcode_format check (
    shortcode is null or shortcode ~ '^[A-Za-z0-9_-]+$'
  ),
  constraint references_route check (
    observed_route is null or observed_route in ('p','reel','tv')
  ),
  constraint references_url_canonical check (
    canonical_url is null or (
      canonical_url !~ '[?#]' and
      canonical_url ~ '^https://(www\.)?instagram\.com/(p|reel|tv)/[A-Za-z0-9_-]+/?$'
    )
  ),
  constraint references_identity_pair check (
    (shortcode is null and canonical_url is null and observed_route is null)
    or
    (shortcode is not null and canonical_url is not null and observed_route is not null)
  ),
  constraint references_url_matches_shortcode check (
    canonical_url is null or
    regexp_replace(
      canonical_url,
      '^https://(www\.)?instagram\.com/(p|reel|tv)/([A-Za-z0-9_-]+)/?$',
      '\3'
    ) = shortcode
  ),
  constraint references_terminal_timestamp check (
    status <> 'completed' or completed_at is not null
  )
);

create unique index if not exists references_shortcode_uq
  on instagram_curator.references (shortcode)
  where shortcode is not null;
create unique index if not exists references_canonical_url_uq
  on instagram_curator.references (canonical_url)
  where canonical_url is not null;
create unique index if not exists references_legacy_key_uq
  on instagram_curator.references (legacy_key)
  where legacy_key is not null;
create index if not exists references_queue_idx
  on instagram_curator.references (status, deferred_until, discovered_at, created_at);
create index if not exists references_source_topic_idx
  on instagram_curator.references (source_account, topic, completed_at desc);

create table if not exists instagram_curator.artifacts (
  id uuid primary key default gen_random_uuid(),
  reference_id uuid not null references instagram_curator.references(id) on delete restrict,
  kind text not null check (kind in ('art','caption','destination','bundle')),
  persistent_uri text not null,
  checksum text,
  status text not null default 'pending'
    check (status in ('pending','ready','failed','superseded')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reference_id, kind)
);

create table if not exists instagram_curator.runs (
  id uuid primary key default gen_random_uuid(),
  executor text not null,
  status instagram_curator.run_status not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  navigation_attempts integer not null default 0,
  counters jsonb not null default '{}'::jsonb,
  stop_reason text,
  error_sanitized text,
  checkpoints jsonb not null default '[]'::jsonb,
  baseline_mode boolean not null default true,
  audit_mode boolean not null default false,
  declared_complete_scan boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  constraint runs_finished_state check (
    (status = 'running' and finished_at is null)
    or
    (status <> 'running' and finished_at is not null)
  ),
  constraint runs_complete_scan_guard check (
    not declared_complete_scan or (audit_mode and stop_reason = 'source_exhausted')
  )
);
create index if not exists runs_started_idx
  on instagram_curator.runs (started_at desc);

create table if not exists instagram_curator.events (
  id bigint generated always as identity primary key,
  run_id uuid not null references instagram_curator.runs(id) on delete cascade,
  reference_id uuid references instagram_curator.references(id) on delete set null,
  event_type text not null,
  occurred_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);
create index if not exists events_run_time_idx
  on instagram_curator.events (run_id, occurred_at);
create index if not exists events_reference_time_idx
  on instagram_curator.events (reference_id, occurred_at desc)
  where reference_id is not null;

create table if not exists instagram_curator.editorial_rules (
  rule_key text primary key,
  state text not null check (state in ('active','proposed','disabled')),
  config jsonb not null,
  rationale text,
  source text not null,
  effective_from timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists instagram_curator.locks (
  lock_name text primary key,
  owner_token uuid not null,
  run_id uuid references instagram_curator.runs(id) on delete set null,
  acquired_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint locks_expiry_order check (expires_at > acquired_at)
);
create index if not exists locks_expiry_idx
  on instagram_curator.locks (expires_at);

create or replace function instagram_curator.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists references_touch_updated_at on instagram_curator.references;
create trigger references_touch_updated_at
before update on instagram_curator.references
for each row execute function instagram_curator.touch_updated_at();

drop trigger if exists artifacts_touch_updated_at on instagram_curator.artifacts;
create trigger artifacts_touch_updated_at
before update on instagram_curator.artifacts
for each row execute function instagram_curator.touch_updated_at();

create or replace function instagram_curator.acquire_lock(
  p_lock_name text,
  p_owner_token uuid,
  p_ttl_seconds integer,
  p_run_id uuid default null
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_acquired boolean;
begin
  if p_ttl_seconds < 30 or p_ttl_seconds > 3600 then
    raise exception 'lock ttl must be between 30 and 3600 seconds';
  end if;

  insert into instagram_curator.locks
    (lock_name, owner_token, run_id, acquired_at, heartbeat_at, expires_at)
  values
    (p_lock_name, p_owner_token, p_run_id, now(), now(), now() + make_interval(secs => p_ttl_seconds))
  on conflict (lock_name) do update
    set owner_token = excluded.owner_token,
        run_id = excluded.run_id,
        acquired_at = now(),
        heartbeat_at = now(),
        expires_at = now() + make_interval(secs => p_ttl_seconds)
  where instagram_curator.locks.expires_at <= now()
     or instagram_curator.locks.owner_token = excluded.owner_token
  returning true into v_acquired;

  return coalesce(v_acquired, false);
end
$$;

create or replace function instagram_curator.heartbeat_lock(
  p_lock_name text,
  p_owner_token uuid,
  p_ttl_seconds integer
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_ttl_seconds < 30 or p_ttl_seconds > 3600 then
    raise exception 'lock ttl must be between 30 and 3600 seconds';
  end if;

  update instagram_curator.locks
     set heartbeat_at = now(),
         expires_at = now() + make_interval(secs => p_ttl_seconds)
   where lock_name = p_lock_name
     and owner_token = p_owner_token
     and expires_at > now();

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end
$$;

create or replace function instagram_curator.release_lock(
  p_lock_name text,
  p_owner_token uuid
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from instagram_curator.locks
   where lock_name = p_lock_name
     and owner_token = p_owner_token;
  get diagnostics v_deleted = row_count;
  return v_deleted = 1;
end
$$;

alter table instagram_curator.references enable row level security;
alter table instagram_curator.artifacts enable row level security;
alter table instagram_curator.runs enable row level security;
alter table instagram_curator.events enable row level security;
alter table instagram_curator.editorial_rules enable row level security;
alter table instagram_curator.locks enable row level security;

revoke all on schema instagram_curator from public, anon, authenticated;
revoke all on all tables in schema instagram_curator from public, anon, authenticated;
revoke all on all sequences in schema instagram_curator from public, anon, authenticated;
revoke all on all functions in schema instagram_curator from public, anon, authenticated;

grant usage on schema instagram_curator to service_role;
grant select, insert, update, delete on all tables in schema instagram_curator to service_role;
grant usage, select on all sequences in schema instagram_curator to service_role;
grant execute on all functions in schema instagram_curator to service_role;

alter default privileges in schema instagram_curator
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema instagram_curator
  revoke all on sequences from public, anon, authenticated;
alter default privileges in schema instagram_curator
  revoke execute on functions from public, anon, authenticated;
alter default privileges in schema instagram_curator
  grant select, insert, update, delete on tables to service_role;
alter default privileges in schema instagram_curator
  grant usage, select on sequences to service_role;
alter default privileges in schema instagram_curator
  grant execute on functions to service_role;

comment on schema instagram_curator is
  'Private source of truth for AGROTORK Instagram content curation; not exposed to anon/authenticated.';
comment on column instagram_curator.references.legacy_state_unverified is
  'True when a legacy folder or Markdown entry does not prove publication, completion, or artifact creation.';
comment on column instagram_curator.runs.declared_complete_scan is
  'May be true only for an audit run that exhausted the source; heuristic or load-limit stops are never a complete scan.';
