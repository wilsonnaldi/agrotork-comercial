-- ============================================================
-- instagram_curator — BASELINE reprodutível
--
-- O schema `instagram_curator` foi criado direto em produção por outra
-- frente de trabalho e nunca existiu nas migrations. Resultado: um banco
-- novo montado a partir do Git NÃO reproduzia produção. Esta migration
-- paga essa dívida.
--
-- Ela é uma FOTOGRAFIA da estrutura que já está em produção, obtida por
-- engenharia reversa do catálogo em 11/09/2026. Não inventa nada: cada
-- coluna, check, índice, função, trigger, policy e grant aqui foi lido de
-- `pg_catalog` no projeto nedmdkdhchkadijtdnja.
--
-- REGRA DESTA MIGRATION: ela não apaga, não recria, não trunca e não
-- sobrescreve dado nenhum. Tudo é `if not exists` ou `create or replace`.
-- Em produção ela é um no-op estrutural; em banco novo ela constrói.
--
-- O único objeto que é derrubado e recriado é trigger e policy — que não
-- guardam dado — e só quando já existem com o mesmo nome, para garantir
-- que a definição final seja idêntica à de produção.
-- ============================================================

create schema if not exists instagram_curator;

-- ── Tipos ─────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'instagram_curator' and t.typname = 'reference_status'
  ) then
    create type instagram_curator.reference_status as enum
      ('discovered', 'pending', 'processing', 'completed', 'discarded', 'deferred', 'failed');
  end if;

  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'instagram_curator' and t.typname = 'run_status'
  ) then
    create type instagram_curator.run_status as enum
      ('running', 'succeeded', 'failed', 'blocked', 'partial', 'no_change');
  end if;
end
$$;

-- ── Tabelas ───────────────────────────────────────────────────
-- `references` é palavra reservada: sempre entre aspas.

create table if not exists instagram_curator.runs (
  id                      uuid not null default gen_random_uuid(),
  executor                text not null,
  status                  instagram_curator.run_status not null default 'running',
  started_at              timestamptz not null default now(),
  finished_at             timestamptz,
  navigation_attempts     integer not null default 0,
  counters                jsonb not null default '{}'::jsonb,
  stop_reason             text,
  error_sanitized         text,
  checkpoints             jsonb not null default '[]'::jsonb,
  baseline_mode           boolean not null default true,
  audit_mode              boolean not null default false,
  declared_complete_scan  boolean not null default false,
  metadata                jsonb not null default '{}'::jsonb
);

create table if not exists instagram_curator."references" (
  id                       uuid not null default gen_random_uuid(),
  shortcode                text,
  canonical_url            text,
  observed_route           text,
  source_account           text,
  origin                   text not null,
  topic                    text,
  angle                    text,
  status                   instagram_curator.reference_status not null default 'discovered',
  caption                  text,
  like_position            integer,
  discovered_at            timestamptz,
  first_seen_at            timestamptz not null default now(),
  last_seen_at             timestamptz not null default now(),
  processing_started_at    timestamptz,
  completed_at             timestamptz,
  deferred_until           timestamptz,
  published_at             timestamptz,
  legacy_key               text,
  legacy_folder_label      text,
  legacy_state_unverified  boolean not null default false,
  provenance               jsonb not null default '{}'::jsonb,
  metadata                 jsonb not null default '{}'::jsonb,
  last_error_sanitized     text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create table if not exists instagram_curator.artifacts (
  id              uuid not null default gen_random_uuid(),
  reference_id    uuid not null,
  kind            text not null,
  persistent_uri  text not null,
  checksum        text,
  status          text not null default 'pending',
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists instagram_curator.events (
  id            bigint generated always as identity,
  run_id        uuid not null,
  reference_id  uuid,
  event_type    text not null,
  occurred_at   timestamptz not null default now(),
  details       jsonb not null default '{}'::jsonb
);

create table if not exists instagram_curator.locks (
  lock_name     text not null,
  owner_token   uuid not null,
  run_id        uuid,
  acquired_at   timestamptz not null default now(),
  heartbeat_at  timestamptz not null default now(),
  expires_at    timestamptz not null
);

create table if not exists instagram_curator.editorial_rules (
  rule_key        text not null,
  state           text not null,
  config          jsonb not null,
  rationale       text,
  source          text not null,
  effective_from  timestamptz,
  updated_at      timestamptz not null default now()
);

-- ── Restrições ────────────────────────────────────────────────
-- `alter table ... add constraint` não tem `if not exists`; o bloco
-- confere o catálogo antes de cada uma.

create or replace function instagram_curator.__baseline_add_constraint(
  p_table text, p_name text, p_definition text
) returns void language plpgsql as $$
begin
  if not exists (
    select 1 from pg_constraint c
     where c.conname = p_name
       and c.conrelid = ('instagram_curator.' || p_table)::regclass
  ) then
    execute format('alter table instagram_curator.%s add constraint %I %s',
                   p_table, p_name, p_definition);
  end if;
end
$$;

select instagram_curator.__baseline_add_constraint('runs', 'runs_pkey', 'primary key (id)');
select instagram_curator.__baseline_add_constraint('runs', 'runs_finished_state',
  $c$check (((status = 'running'::instagram_curator.run_status and finished_at is null)
          or (status <> 'running'::instagram_curator.run_status and finished_at is not null)))$c$);
select instagram_curator.__baseline_add_constraint('runs', 'runs_complete_scan_guard',
  $c$check ((not declared_complete_scan) or (audit_mode and stop_reason = 'source_exhausted'))$c$);

select instagram_curator.__baseline_add_constraint('"references"', 'references_pkey', 'primary key (id)');
select instagram_curator.__baseline_add_constraint('"references"', 'references_identity_pair',
  $c$check (((shortcode is null and canonical_url is null and observed_route is null)
          or (shortcode is not null and canonical_url is not null and observed_route is not null)))$c$);
select instagram_curator.__baseline_add_constraint('"references"', 'references_route',
  $c$check ((observed_route is null or observed_route = any (array['p'::text, 'reel'::text, 'tv'::text])))$c$);
select instagram_curator.__baseline_add_constraint('"references"', 'references_shortcode_format',
  $c$check ((shortcode is null or shortcode ~ '^[A-Za-z0-9_-]+$'::text))$c$);
select instagram_curator.__baseline_add_constraint('"references"', 'references_terminal_timestamp',
  $c$check ((status <> 'completed'::instagram_curator.reference_status or completed_at is not null))$c$);
select instagram_curator.__baseline_add_constraint('"references"', 'references_url_canonical',
  $c$check ((canonical_url is null or (canonical_url !~ '[?#]'::text
        and canonical_url ~ '^https://(www\.)?instagram\.com/(p|reel|tv)/[A-Za-z0-9_-]+/?$'::text)))$c$);
select instagram_curator.__baseline_add_constraint('"references"', 'references_url_matches_shortcode',
  $c$check ((canonical_url is null or regexp_replace(canonical_url,
        '^https://(www\.)?instagram\.com/(p|reel|tv)/([A-Za-z0-9_-]+)/?$'::text, '\3'::text) = shortcode))$c$);

select instagram_curator.__baseline_add_constraint('artifacts', 'artifacts_pkey', 'primary key (id)');
select instagram_curator.__baseline_add_constraint('artifacts', 'artifacts_reference_id_kind_key',
  'unique (reference_id, kind)');
select instagram_curator.__baseline_add_constraint('artifacts', 'artifacts_reference_id_fkey',
  'foreign key (reference_id) references instagram_curator."references"(id) on delete restrict');
select instagram_curator.__baseline_add_constraint('artifacts', 'artifacts_kind_check',
  $c$check ((kind = any (array['art'::text, 'caption'::text, 'destination'::text, 'bundle'::text])))$c$);
select instagram_curator.__baseline_add_constraint('artifacts', 'artifacts_status_check',
  $c$check ((status = any (array['pending'::text, 'ready'::text, 'failed'::text, 'superseded'::text])))$c$);

select instagram_curator.__baseline_add_constraint('events', 'events_pkey', 'primary key (id)');
select instagram_curator.__baseline_add_constraint('events', 'events_run_id_fkey',
  'foreign key (run_id) references instagram_curator.runs(id) on delete cascade');
select instagram_curator.__baseline_add_constraint('events', 'events_reference_id_fkey',
  'foreign key (reference_id) references instagram_curator."references"(id) on delete set null');

select instagram_curator.__baseline_add_constraint('locks', 'locks_pkey', 'primary key (lock_name)');
select instagram_curator.__baseline_add_constraint('locks', 'locks_expiry_order',
  'check ((expires_at > acquired_at))');
select instagram_curator.__baseline_add_constraint('locks', 'locks_run_id_fkey',
  'foreign key (run_id) references instagram_curator.runs(id) on delete set null');

select instagram_curator.__baseline_add_constraint('editorial_rules', 'editorial_rules_pkey',
  'primary key (rule_key)');
select instagram_curator.__baseline_add_constraint('editorial_rules', 'editorial_rules_state_check',
  $c$check ((state = any (array['active'::text, 'proposed'::text, 'disabled'::text])))$c$);

drop function instagram_curator.__baseline_add_constraint(text, text, text);

-- ── Índices ───────────────────────────────────────────────────

create index        if not exists runs_started_idx
  on instagram_curator.runs (started_at desc);

create unique index if not exists references_shortcode_uq
  on instagram_curator."references" (shortcode) where shortcode is not null;
create unique index if not exists references_canonical_url_uq
  on instagram_curator."references" (canonical_url) where canonical_url is not null;
create unique index if not exists references_legacy_key_uq
  on instagram_curator."references" (legacy_key) where legacy_key is not null;
create index        if not exists references_queue_idx
  on instagram_curator."references" (status, deferred_until, discovered_at, created_at);
create index        if not exists references_source_topic_idx
  on instagram_curator."references" (source_account, topic, completed_at desc);

create index        if not exists events_run_time_idx
  on instagram_curator.events (run_id, occurred_at);
create index        if not exists events_reference_time_idx
  on instagram_curator.events (reference_id, occurred_at desc) where reference_id is not null;

create index        if not exists locks_expiry_idx
  on instagram_curator.locks (expires_at);
create index        if not exists locks_run_id_idx
  on instagram_curator.locks (run_id) where run_id is not null;

-- ── Funções ───────────────────────────────────────────────────
-- Todas `security invoker` (o padrão) com `search_path` vazio, como em
-- produção. Quem as usa é o `service_role`, pelo backend do curador.

create or replace function instagram_curator.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create or replace function instagram_curator.acquire_lock(
  p_lock_name text, p_owner_token uuid, p_ttl_seconds integer, p_run_id uuid default null
) returns boolean language plpgsql set search_path = '' as $$
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
  p_lock_name text, p_owner_token uuid, p_ttl_seconds integer
) returns boolean language plpgsql set search_path = '' as $$
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
  p_lock_name text, p_owner_token uuid
) returns boolean language plpgsql set search_path = '' as $$
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

-- ── Gatilhos ──────────────────────────────────────────────────

drop trigger if exists references_touch_updated_at on instagram_curator."references";
create trigger references_touch_updated_at
  before update on instagram_curator."references"
  for each row execute function instagram_curator.touch_updated_at();

drop trigger if exists artifacts_touch_updated_at on instagram_curator.artifacts;
create trigger artifacts_touch_updated_at
  before update on instagram_curator.artifacts
  for each row execute function instagram_curator.touch_updated_at();

-- ── RLS ───────────────────────────────────────────────────────
-- Nada aqui é do sistema comercial: só o backend do curador entra, e ele
-- entra como `service_role`. `anon` e `authenticated` não têm sequer
-- USAGE no schema.

alter table instagram_curator.runs             enable row level security;
alter table instagram_curator."references"     enable row level security;
alter table instagram_curator.artifacts        enable row level security;
alter table instagram_curator.events           enable row level security;
alter table instagram_curator.locks            enable row level security;
alter table instagram_curator.editorial_rules  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['runs', '"references"', 'artifacts', 'events', 'locks', 'editorial_rules'] loop
    execute format('drop policy if exists service_role_full_access on instagram_curator.%s', t);
    execute format($p$create policy service_role_full_access on instagram_curator.%s
                      for all to service_role using (true) with check (true)$p$, t);
  end loop;
end
$$;

-- ── Privilégios ───────────────────────────────────────────────

revoke all on schema instagram_curator from public;
revoke usage on schema instagram_curator from anon, authenticated;
grant  usage on schema instagram_curator to service_role;

revoke all on all tables    in schema instagram_curator from public, anon, authenticated;
revoke all on all functions in schema instagram_curator from public, anon, authenticated;
revoke all on all sequences in schema instagram_curator from public, anon, authenticated;

grant select, insert, update, delete on all tables    in schema instagram_curator to service_role;
grant execute                        on all functions in schema instagram_curator to service_role;
grant select, usage                  on all sequences in schema instagram_curator to service_role;

alter default privileges in schema instagram_curator
  grant select, insert, update, delete on tables    to service_role;
alter default privileges in schema instagram_curator
  grant execute                        on functions to service_role;
alter default privileges in schema instagram_curator
  grant select, usage                  on sequences to service_role;
