-- ============================================================
-- 0700 · Compartilhamento público e parâmetros da empresa
-- ============================================================

create table public.quote_share_tokens (
  id         uuid primary key default gen_random_uuid(),
  quote_id   uuid not null references public.quotes(id) on delete cascade,
  token      text not null default encode(gen_random_bytes(24), 'hex'),
  expires_at timestamptz,
  revoked_at timestamptz,
  view_count integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index idx_share_tokens_token on public.quote_share_tokens (token);
create index idx_share_tokens_quote on public.quote_share_tokens (quote_id);

-- Parâmetros gerais (dados da empresa, textos padrão do PDF...).
create table public.app_settings (
  key         text primary key,
  value       jsonb not null default '{}'::jsonb,
  description text,
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now()
);

create trigger trg_app_settings_updated_at before update on public.app_settings
  for each row execute function public.set_updated_at();
