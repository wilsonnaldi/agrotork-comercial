-- ============================================================
-- APLICAR A FASE 1 DO BRAIN — projeto nedmdkdhchkadijtdnja
--
-- ⚠ ESTE ARQUIVO É GERADO. Não edite.
--   Fonte:  supabase/operacao/02-aplicar-brain.template.sql
--   Gerador: supabase/operacao/gerar-consolidado.sh
--   Conferência: supabase/db-tests/conferir-operacao.sh regera e compara.
--
-- ── CAMINHO DE EXECUÇÃO: UM SÓ ──────────────────────────────
--
-- **SQL Editor do Supabase.** Cole este arquivo inteiro, de uma vez, e
-- rode. É por isso que ele é gerado com as migrations JÁ EMBUTIDAS: o
-- `\i` do psql não existe no editor, e manter os dois caminhos era ter
-- dois roteiros divergindo em silêncio.
--
-- Não use `psql -f` neste arquivo, não rode em pedaços e não use
-- `supabase db push` para esta aplicação: nenhum dos três põe aplicação,
-- validações e registro na MESMA transação, que é a garantia inteira
-- deste roteiro.
--
-- ── PRÉ-REQUISITOS, conferidos aqui dentro ──────────────────
--   · PostgreSQL 17 (produção é 17.6);
--   · as nove migrations de 09/09 já reconciliadas (roteiro 01);
--   · `instagram_curator` presente e registrado;
--   · `public.audit_capture()` no md5 conhecido;
--   · o schema `brain` ainda não existe;
--   · nenhuma versão do BRAIN registrada.
--
-- ── MODO DESACOPLADO ────────────────────────────────────────
--
-- Este deploy entra com as TRÊS PONTES DESABILITADAS. Os gatilhos são
-- criados (o código está aplicado e testado) e em seguida desligados por
-- 20260911200000. Nenhum processamento do BRAIN acontece dentro da
-- transação de orçamento ou de pedido.
--
-- A sincronização é periódica, por `brain.reconciliar_erp()` chamada
-- pelo pg_cron a cada minuto. O passo de agendar o cron vem DEPOIS do
-- COMMIT — ver supabase/operacao/05-agendar-reconciliacao.sql.
--
-- ── PÓS-CONDIÇÕES, conferidas aqui dentro ───────────────────
--   · 9 tabelas, todas com RLS; view `journey_entries` security_invoker;
--   · toda função com `search_path` vazio, nenhuma executável por `anon`,
--     nenhuma `immutable` indevida;
--   · 3 gatilhos em `public`, todos AFTER e todos DESABILITADOS;
--   · `audit_capture()` no md5 esperado DEPOIS da mudança;
--   · nenhum dado comercial existente alterado;
--   · fumaça COMPLETA do fluxo DESACOPLADO — orçamento → pedido sem
--     nenhum evento, reconciliação reproduzindo o fato, relatório vazio
--     — e sem resíduo.
--
-- Falhou qualquer uma? A exceção aborta a transação, e o COMMIT lá
-- embaixo é executado como ROLLBACK. Não há resgate: este roteiro não
-- usa `savepoint`.
-- ============================================================

begin;

-- ── Pré-condições ───────────────────────────────────────────
do $$
declare v_md5 text; v_versao int;
begin
  v_versao := current_setting('server_version_num')::int;
  if v_versao < 170000 or v_versao >= 180000 then
    raise exception 'Este roteiro foi ensaiado em PostgreSQL 17; aqui e % — PARADO.',
      current_setting('server_version');
  end if;

  if exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain JA EXISTE. Este roteiro e de primeira aplicacao — PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations where version like '2026090914%') then
    raise exception 'As nove migrations de 09/09 ainda estao com a versao errada. Rode 01-reconciliar-registro.sql antes — PARADO.';
  end if;

  if not exists (select 1 from pg_namespace where nspname = 'instagram_curator')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151115')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151534') then
    raise exception 'instagram_curator ausente ou sem registro — o banco nao e o que a auditoria descreveu. PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations where version like '20260911%') then
    raise exception 'Alguma versao do BRAIN ja esta registrada — PARADO.';
  end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from '24fd65a7eb791b2e2644abe1b2ba876b' then
    raise exception 'public.audit_capture() esta em md5 % e a auditoria conferiu 24fd65a7eb791b2e2644abe1b2ba876b. Alguem a mudou depois; o diff semantico precisa ser refeito antes de sobrescrever — PARADO.', coalesce(v_md5, '(inexistente)');
  end if;

  raise notice 'Pre-condicoes conferidas: PostgreSQL %, registro reconciliado, audit_capture no md5 esperado.',
    current_setting('server_version');
end
$$;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911130000_brain_foundation.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- Renumerada em 11/09/2026 de 20260910120000 para 20260911130000. Motivo:
-- as duas migrations do `instagram_curator` (20260910151115 e
-- 20260910151534) já estão aplicadas em produção, e uma migration local
-- com versão ANTERIOR a uma já aplicada entra fora de ordem no
-- `supabase db push`. O BRAIN nunca foi aplicado, então renumerar o
-- arquivo não reescreve história nenhuma — só a põe na ordem certa.
-- ============================================================
-- AGROTORK BRAIN — Fase 1: fundação (CRM + eventos)
--
-- O BRAIN é a camada que responde "de onde veio, por onde passou e
-- virou o quê" para cada contato comercial. Ele NÃO é um segundo ERP:
-- cliente, produto, orçamento, pedido e vendedor continuam morando em
-- `public`, e tudo aqui aponta para lá por chave estrangeira.
--
-- O que nasce neste schema, e por quê:
--
--   brain.channels       de onde as pessoas chegam (tabela, não enum:
--                        canal novo é linha, não migration)
--   brain.attributions   origem detalhada (UTM, campanha, anúncio, clique)
--                        capturada UMA vez e referenciada por lead,
--                        evento e oportunidade — a base da atribuição
--   brain.leads          o contato antes (ou além) de ser cliente;
--                        `customer_id` liga ao cadastro oficial quando
--                        se descobre que é o mesmo alguém
--   brain.identities     telefone, WhatsApp, e-mail, Instagram, visitor…
--                        normalizados e ÚNICOS: é como o BRAIN reconhece
--                        que quem chegou pelo Instagram é quem mandou
--                        WhatsApp semana passada
--   brain.interactions   cada conversa, ligação, visita, formulário
--   brain.opportunities  o interesse concreto (produto, valor, etapa),
--                        ligado ao orçamento e ao pedido do ERP
--   brain.tasks          a próxima ação de quem vende (ou, no futuro,
--                        do agente)
--   brain.events         o barramento: tudo que aconteceu, de qualquer
--                        sistema, imutável e idempotente por
--                        (source, external_id)
--   brain.lead_merges    registro auditável de quando dois leads viraram
--                        um — nunca automático, nunca destrutivo
--   brain.journey_entries a jornada cronológica: eventos + interações +
--                        oportunidades + orçamentos + pedidos
--
-- Auditoria: ALTERAÇÃO DE DADOS continua em `public.audit_log`, pelo
-- mesmo `audit_capture()` (lead, oportunidade, tarefa, identidade,
-- merge). EVENTO DE NEGÓCIO fica em `brain.events`. São coisas
-- diferentes: o primeiro diz "quem mudou o quê"; o segundo diz "o que
-- aconteceu com o cliente".
--
-- Segurança: mesmos papéis do ERP (`public.is_admin()`,
-- `public.is_active_user()`), RLS em toda tabela, `anon` sem USAGE no
-- schema. Vendedor enxerga os leads dele e os SEM dono (a fila), e tudo
-- que pende deles; administrador enxerga tudo. Escrita em `events` só
-- por função — a API não insere evento cru.
--
-- Fora desta fase (de propósito): pgvector, agentes, n8n, APIs externas.
-- O modelo só precisa não ATRAPALHAR o que vem depois.
-- ============================================================

create schema if not exists brain;

comment on schema brain is
  'AGROTORK BRAIN: CRM, identidade, eventos e jornada. Aponta para public; nunca duplica o ERP.';

grant usage on schema brain to authenticated, service_role;
revoke all on schema brain from anon, public;

-- Nenhum objeto novo neste schema nasce concedido a quem não pedimos.
alter default privileges in schema brain revoke all on tables    from public;
alter default privileges in schema brain revoke all on functions from public;
alter default privileges in schema brain revoke all on sequences from public;

-- ════════════════════════════════════════════════════════════
-- Tipos
-- ════════════════════════════════════════════════════════════
create type brain.lead_status as enum
  ('new', 'contacted', 'qualified', 'unqualified', 'converted', 'lost');

create type brain.temperature as enum ('cold', 'warm', 'hot');

create type brain.identity_kind as enum
  ('phone', 'whatsapp', 'email', 'instagram', 'facebook', 'visitor', 'external');

create type brain.interaction_type as enum
  ('message', 'call', 'email', 'visit', 'form', 'meeting', 'note', 'system');

create type brain.interaction_direction as enum ('inbound', 'outbound', 'internal');

create type brain.opportunity_stage as enum
  ('prospecting', 'qualified', 'proposal', 'negotiation', 'won', 'lost');

create type brain.task_kind as enum
  ('call', 'message', 'email', 'visit', 'send_quote', 'follow_up', 'check_stock', 'other');

create type brain.task_priority as enum ('low', 'normal', 'high', 'urgent');

create type brain.task_status as enum ('pending', 'in_progress', 'done', 'cancelled');

create type brain.actor_origin as enum ('human', 'system', 'agent');

create type brain.event_processing as enum ('pending', 'processed', 'failed', 'skipped');

-- ════════════════════════════════════════════════════════════
-- Canais
-- ════════════════════════════════════════════════════════════
-- Tabela e não enum: Instagram hoje, TikTok amanhã, feira agrícola
-- depois — canal novo é uma linha inserida pelo administrador.
create table brain.channels (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  name        text not null,
  -- Agrupa para relatório: mídia paga, orgânico, direto, interno.
  kind        text not null default 'other'
              check (kind in ('paid', 'organic', 'direct', 'internal', 'other')),
  is_active   boolean not null default true,
  sort_order  integer not null default 0,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger trg_channels_updated_at before update on brain.channels
  for each row execute function public.set_updated_at();

insert into brain.channels (key, name, kind, sort_order) values
  ('website',        'Site',              'organic',  10),
  ('instagram',      'Instagram',         'organic',  20),
  ('facebook',       'Facebook',          'organic',  30),
  ('whatsapp',       'WhatsApp',          'direct',   40),
  ('google_ads',     'Google Ads',        'paid',     50),
  ('google_organic', 'Google (orgânico)', 'organic',  60),
  ('phone',          'Telefone',          'direct',   70),
  ('email',          'E-mail',            'direct',   80),
  ('store',          'Loja',              'direct',   90),
  ('salesperson',    'Vendedor',          'internal', 100),
  ('import',         'Importação',        'internal', 110),
  ('other',          'Outro',             'other',    120);

-- ════════════════════════════════════════════════════════════
-- Atribuição de origem
-- ════════════════════════════════════════════════════════════
-- Uma linha por "toque" com origem conhecida. O lead guarda o PRIMEIRO
-- toque (`first_attribution_id`); cada evento e cada oportunidade podem
-- guardar o seu. Assim primeira e última atribuição saem por consulta,
-- sem decidir hoje qual modelo de atribuição a empresa vai usar.
create table brain.attributions (
  id                   uuid primary key default gen_random_uuid(),
  channel_key          text references brain.channels(key) on delete restrict,
  source               text,     -- utm_source / plataforma
  medium               text,     -- utm_medium: cpc, social, organic…
  campaign             text,     -- utm_campaign
  content              text,     -- utm_content: criativo, post
  term                 text,     -- utm_term
  referrer             text,
  landing_page         text,
  external_campaign_id text,     -- id da campanha na plataforma
  external_adset_id    text,
  external_ad_id       text,
  click_id             text,     -- gclid, fbclid…
  captured_at          timestamptz not null default now(),
  metadata             jsonb not null default '{}'::jsonb
);

create index idx_attributions_campaign on brain.attributions (campaign) where campaign is not null;
create index idx_attributions_external on brain.attributions (external_campaign_id) where external_campaign_id is not null;
create index idx_attributions_channel  on brain.attributions (channel_key, captured_at desc);

-- ════════════════════════════════════════════════════════════
-- Leads
-- ════════════════════════════════════════════════════════════
create table brain.leads (
  id                   uuid primary key default gen_random_uuid(),

  -- Quando o BRAIN descobre que este contato É um cliente do ERP.
  customer_id          uuid references public.customers(id) on delete set null,
  -- O vendedor responsável. Nulo = na fila, qualquer vendedor pode pegar.
  owner_id             uuid references public.profiles(id)  on delete set null,

  name                 text not null,
  company_name         text,
  -- Contato principal, normalizado (só dígitos / minúsculas). A lista
  -- completa de formas de contato mora em `identities`.
  phone                text,
  whatsapp             text,
  email                text,
  city                 text,
  state                char(2),

  status               brain.lead_status not null default 'new',
  temperature          brain.temperature not null default 'cold',
  score                integer not null default 0 check (score between 0 and 100),

  channel_key          text references brain.channels(key) on delete restrict,
  source_detail        text,     -- "post do dia 12", "feira Londrina", nome do formulário
  first_attribution_id uuid references brain.attributions(id) on delete set null,

  first_touch_at       timestamptz not null default now(),
  last_touch_at        timestamptz not null default now(),
  converted_at         timestamptz,
  lost_reason          text,

  -- Identidade: quando este lead foi unificado em outro, aponta para o
  -- sobrevivente. A linha fica — é histórico, e o merge é auditável.
  merged_into_lead_id  uuid references brain.leads(id) on delete set null,

  notes                text,
  metadata             jsonb not null default '{}'::jsonb,

  created_by           uuid references public.profiles(id) on delete set null,
  updated_by           uuid references public.profiles(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint chk_lead_not_self_merged check (merged_into_lead_id is distinct from id)
);

create index idx_leads_owner_status on brain.leads (owner_id, status) where merged_into_lead_id is null;
create index idx_leads_status       on brain.leads (status, last_touch_at desc) where merged_into_lead_id is null;
create index idx_leads_temperature  on brain.leads (temperature, last_touch_at desc) where merged_into_lead_id is null;
create index idx_leads_customer     on brain.leads (customer_id) where customer_id is not null;
create index idx_leads_recent       on brain.leads (created_at desc);
create index idx_leads_channel      on brain.leads (channel_key);

create trigger trg_leads_updated_at before update on brain.leads
  for each row execute function public.set_updated_at();

comment on table brain.leads is
  'Contato comercial antes/alem de ser cliente. customer_id liga ao cadastro oficial quando e o mesmo alguem. owner_id nulo = fila.';

-- ════════════════════════════════════════════════════════════
-- Identidades — como o BRAIN reconhece a mesma pessoa
-- ════════════════════════════════════════════════════════════
-- Uma linha por (tipo, valor normalizado). ÚNICA: um telefone pertence a
-- um lead (e/ou a um cliente). Quando um novo contato chega, o valor é
-- normalizado e procurado aqui antes de qualquer lead ser criado.
create table brain.identities (
  id            uuid primary key default gen_random_uuid(),
  kind          brain.identity_kind not null,
  value         text not null,          -- normalizado
  value_raw     text,                   -- como chegou
  lead_id       uuid references brain.leads(id) on delete cascade,
  customer_id   uuid references public.customers(id) on delete set null,
  channel_key   text references brain.channels(key) on delete set null,
  verified      boolean not null default false,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  metadata      jsonb not null default '{}'::jsonb,

  constraint chk_identity_has_owner check (lead_id is not null or customer_id is not null),
  constraint chk_identity_value check (value <> '')
);

create unique index idx_identities_unique on brain.identities (kind, value);
create index idx_identities_lead     on brain.identities (lead_id) where lead_id is not null;
create index idx_identities_customer on brain.identities (customer_id) where customer_id is not null;

comment on table brain.identities is
  'Telefone, WhatsApp, e-mail, Instagram, visitor, id externo — normalizados e unicos. E por aqui que um contato novo e reconhecido.';

-- ════════════════════════════════════════════════════════════
-- Interações
-- ════════════════════════════════════════════════════════════
create table brain.interactions (
  id               uuid primary key default gen_random_uuid(),
  lead_id          uuid references brain.leads(id) on delete cascade,
  customer_id      uuid references public.customers(id) on delete set null,
  opportunity_id   uuid,                 -- FK adicionada depois da tabela existir
  channel_key      text references brain.channels(key) on delete restrict,
  interaction_type brain.interaction_type not null default 'message',
  direction        brain.interaction_direction not null default 'inbound',
  summary          text not null,
  occurred_at      timestamptz not null default now(),
  -- Quem registrou (vendedor) — nulo quando veio de sistema.
  actor_id         uuid references public.profiles(id) on delete set null,
  -- De que sistema veio e qual o id de lá: a chave da idempotência.
  source           text not null default 'app',
  external_id      text,
  event_id         bigint,               -- FK adicionada depois de `events`
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),

  constraint chk_interaction_has_subject check (lead_id is not null or customer_id is not null)
);

create unique index idx_interactions_external on brain.interactions (source, external_id)
  where external_id is not null;
create index idx_interactions_lead     on brain.interactions (lead_id, occurred_at desc);
create index idx_interactions_customer on brain.interactions (customer_id, occurred_at desc) where customer_id is not null;
create index idx_interactions_recent   on brain.interactions (occurred_at desc);

-- ════════════════════════════════════════════════════════════
-- Oportunidades
-- ════════════════════════════════════════════════════════════
create table brain.opportunities (
  id                  uuid primary key default gen_random_uuid(),
  lead_id             uuid references brain.leads(id) on delete set null,
  customer_id         uuid references public.customers(id) on delete set null,
  owner_id            uuid references public.profiles(id)  on delete set null,
  -- O interesse. Produto do catálogo quando existe; texto livre quando
  -- ainda não ("um drone para 300 ha").
  product_id          uuid references public.products(id) on delete set null,
  title               text not null,
  stage               brain.opportunity_stage not null default 'prospecting',
  temperature         brain.temperature not null default 'warm',
  estimated_value     numeric(14,2) check (estimated_value is null or estimated_value >= 0),
  probability         integer not null default 0 check (probability between 0 and 100),
  expected_close_date date,
  next_action_at      timestamptz,
  -- A ponte com o ERP. `set null`: apagar o orçamento não apaga o
  -- interesse que o gerou.
  quote_id            uuid references public.quotes(id) on delete set null,
  order_id            uuid references public.orders(id) on delete set null,
  channel_key         text references brain.channels(key) on delete restrict,
  attribution_id      uuid references brain.attributions(id) on delete set null,
  lost_reason         text,
  closed_at           timestamptz,
  notes               text,
  metadata            jsonb not null default '{}'::jsonb,
  created_by          uuid references public.profiles(id) on delete set null,
  updated_by          uuid references public.profiles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint chk_opportunity_has_subject check (lead_id is not null or customer_id is not null),
  constraint chk_opportunity_closed check (
    (stage in ('won', 'lost') and closed_at is not null) or
    (stage not in ('won', 'lost') and closed_at is null)
  )
);

create index idx_opportunities_open     on brain.opportunities (owner_id, stage, next_action_at)
  where stage not in ('won', 'lost');
create index idx_opportunities_lead     on brain.opportunities (lead_id) where lead_id is not null;
create index idx_opportunities_customer on brain.opportunities (customer_id) where customer_id is not null;
create index idx_opportunities_product  on brain.opportunities (product_id) where product_id is not null;
create index idx_opportunities_quote    on brain.opportunities (quote_id) where quote_id is not null;
create index idx_opportunities_order    on brain.opportunities (order_id) where order_id is not null;

create trigger trg_opportunities_updated_at before update on brain.opportunities
  for each row execute function public.set_updated_at();

alter table brain.interactions
  add constraint interactions_opportunity_id_fkey
  foreign key (opportunity_id) references brain.opportunities(id) on delete set null;

-- Etapa fechada carimba `closed_at`; reaberta limpa. Nunca digitado.
create or replace function brain.stamp_opportunity_stage()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.stage in ('won', 'lost') then
    if old.stage is distinct from new.stage or new.closed_at is null then
      new.closed_at := now();
    end if;
  else
    new.closed_at := null;
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_opportunity_stage() from public, anon, authenticated;

create trigger trg_opportunities_stage before insert or update on brain.opportunities
  for each row execute function brain.stamp_opportunity_stage();

-- ════════════════════════════════════════════════════════════
-- Tarefas
-- ════════════════════════════════════════════════════════════
create table brain.tasks (
  id             uuid primary key default gen_random_uuid(),
  lead_id        uuid references brain.leads(id) on delete cascade,
  customer_id    uuid references public.customers(id) on delete set null,
  opportunity_id uuid references brain.opportunities(id) on delete cascade,
  assignee_id    uuid references public.profiles(id) on delete set null,
  kind           brain.task_kind not null default 'follow_up',
  title          text not null,
  description    text,
  priority       brain.task_priority not null default 'normal',
  status         brain.task_status not null default 'pending',
  due_at         timestamptz,
  completed_at   timestamptz,
  completed_by   uuid references public.profiles(id) on delete set null,
  -- Quem pediu a tarefa: pessoa, gatilho do sistema ou (futuro) agente.
  origin         brain.actor_origin not null default 'human',
  origin_ref     text,
  metadata       jsonb not null default '{}'::jsonb,
  created_by     uuid references public.profiles(id) on delete set null,
  updated_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint chk_task_done check (
    (status = 'done' and completed_at is not null) or (status <> 'done')
  )
);

create index idx_tasks_assignee_due on brain.tasks (assignee_id, due_at)
  where status in ('pending', 'in_progress');
create index idx_tasks_overdue on brain.tasks (due_at)
  where status in ('pending', 'in_progress') and due_at is not null;
create index idx_tasks_lead        on brain.tasks (lead_id) where lead_id is not null;
create index idx_tasks_opportunity on brain.tasks (opportunity_id) where opportunity_id is not null;

create trigger trg_tasks_updated_at before update on brain.tasks
  for each row execute function public.set_updated_at();

create or replace function brain.stamp_task_status()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.status = 'done' and (tg_op = 'INSERT' or old.status is distinct from 'done') then
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := coalesce(new.completed_by, (select auth.uid()));
  elsif new.status <> 'done' then
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_task_status() from public, anon, authenticated;

create trigger trg_tasks_status before insert or update on brain.tasks
  for each row execute function brain.stamp_task_status();

-- ════════════════════════════════════════════════════════════
-- Barramento de eventos
-- ════════════════════════════════════════════════════════════
-- Append-only. Um evento é um FATO: "aconteceu X, vindo de Y, às Z".
-- Fatos não se editam; o que muda é só o carimbo de processamento
-- (quando o n8n/agente consumir a fila, na Fase 2+).
create table brain.events (
  id                bigint generated always as identity primary key,
  -- dominio.verbo — `instagram.message_received`, `quote.approved`
  event_name        text not null check (event_name ~ '^[a-z0-9_]+\.[a-z0-9_]+$'),
  event_version     integer not null default 1 check (event_version >= 1),
  -- Sistema que produziu: 'erp', 'n8n', 'website', 'meta'…
  source            text not null,
  channel_key       text references brain.channels(key) on delete restrict,

  lead_id           uuid references brain.leads(id)          on delete set null,
  customer_id       uuid references public.customers(id)     on delete set null,
  opportunity_id    uuid references brain.opportunities(id)  on delete set null,
  product_id        uuid references public.products(id)      on delete set null,
  actor_id          uuid references public.profiles(id)      on delete set null,
  attribution_id    uuid references brain.attributions(id)   on delete set null,

  session_id        text,
  visitor_id        text,
  -- Id do evento no sistema de origem. Com `source`, é a chave da
  -- idempotência: o mesmo webhook entregue duas vezes vira UM evento.
  external_id       text,

  occurred_at       timestamptz not null default now(),
  received_at       timestamptz not null default now(),
  payload           jsonb not null default '{}'::jsonb,
  metadata          jsonb not null default '{}'::jsonb,

  processing        brain.event_processing not null default 'pending',
  processed_at      timestamptz,
  processing_error  text
);

create unique index idx_events_dedupe on brain.events (source, external_id)
  where external_id is not null;
create index idx_events_name_time   on brain.events (event_name, occurred_at desc);
create index idx_events_source_time on brain.events (source, occurred_at desc);
create index idx_events_lead        on brain.events (lead_id, occurred_at desc)      where lead_id is not null;
create index idx_events_customer    on brain.events (customer_id, occurred_at desc)  where customer_id is not null;
create index idx_events_product     on brain.events (product_id, occurred_at desc)   where product_id is not null;
create index idx_events_attribution on brain.events (attribution_id)                 where attribution_id is not null;
create index idx_events_visitor     on brain.events (visitor_id, occurred_at desc)   where visitor_id is not null;
create index idx_events_pending     on brain.events (received_at) where processing = 'pending';

comment on table brain.events is
  'Barramento append-only. Idempotente por (source, external_id). Fato de negocio; nao e auditoria de dados.';

-- Só as colunas de processamento mudam; o fato, nunca. Vale para todo
-- mundo, inclusive para quem entra pelo painel com a chave de serviço.
create or replace function brain.protect_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'O barramento nao se esvazia. Evento e fato: no maximo marca-se como ignorado.'
      using errcode = 'restrict_violation';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Evento nao se apaga. E fato: no maximo marca-se como ignorado (processing = skipped).'
      using errcode = 'restrict_violation';
  end if;
  if new.event_name     is distinct from old.event_name
  or new.event_version  is distinct from old.event_version
  or new.source         is distinct from old.source
  or new.external_id    is distinct from old.external_id
  or new.occurred_at    is distinct from old.occurred_at
  or new.received_at    is distinct from old.received_at
  or new.payload        is distinct from old.payload
  or new.session_id     is distinct from old.session_id
  or new.visitor_id     is distinct from old.visitor_id
  or new.actor_id       is distinct from old.actor_id then
    raise exception 'Evento e imutavel; so o processamento e os vinculos (lead, cliente, oportunidade) podem ser preenchidos depois.'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

revoke execute on function brain.protect_event() from public, anon, authenticated;

create trigger trg_events_immutable before update or delete on brain.events
  for each row execute function brain.protect_event();
create trigger trg_events_no_truncate before truncate on brain.events
  for each statement execute function brain.protect_event();

alter table brain.interactions
  add constraint interactions_event_id_fkey
  foreign key (event_id) references brain.events(id) on delete set null;

-- ════════════════════════════════════════════════════════════
-- Merges de lead — auditáveis, nunca automáticos
-- ════════════════════════════════════════════════════════════
create table brain.lead_merges (
  id             uuid primary key default gen_random_uuid(),
  source_lead_id uuid not null references brain.leads(id) on delete restrict,
  target_lead_id uuid not null references brain.leads(id) on delete restrict,
  merged_by      uuid references public.profiles(id) on delete set null,
  origin         brain.actor_origin not null default 'human',
  reason         text,
  -- Foto do lead de origem antes do merge: reversível por leitura.
  snapshot       jsonb not null default '{}'::jsonb,
  merged_at      timestamptz not null default now(),
  constraint chk_merge_distinct check (source_lead_id <> target_lead_id)
);

create index idx_lead_merges_target on brain.lead_merges (target_lead_id);

-- ════════════════════════════════════════════════════════════
-- Visibilidade — quem enxerga o quê
-- ════════════════════════════════════════════════════════════
-- `security definer` pelo mesmo motivo de `owns_quote`: a policy de
-- `interactions` precisa olhar `leads`, e a policy de `leads` não pode
-- ser reavaliada em recursão. Nenhuma linha sai daqui — só true/false.
create or replace function brain.can_see_lead(p_lead_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select ((select auth.uid()) is null or (select public.is_active_user()))
     and exists (
    select 1 from brain.leads l
     where l.id = p_lead_id
       and ((select public.is_admin())
            or l.owner_id is null
            or l.owner_id = (select auth.uid()))
  );
$$;

create or replace function brain.can_see_opportunity(p_opportunity_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select ((select auth.uid()) is null or (select public.is_active_user()))
     and exists (
    select 1 from brain.opportunities o
     where o.id = p_opportunity_id
       and ((select public.is_admin())
            or o.owner_id = (select auth.uid())
            or (o.lead_id is not null and brain.can_see_lead(o.lead_id)))
  );
$$;

-- Quem está chamando? Três casos, e só três:
--   · chamada interna (gatilho da ponte ERP, com a marca `brain.internal`
--     aberta na transação) — confiável por construção;
--   · sessão sem JWT que não é papel de API (migration, pg_cron, SQL
--     Editor, service_role) — o próprio banco;
--   · usuário da aplicação — precisa estar ATIVO. `anon` nunca.
-- Ausência de `auth.uid()` sozinha não autoriza: `anon` também não tem uid.
create or replace function brain.is_internal()
returns boolean language sql stable security invoker set search_path = '' as $$
  select coalesce(pg_catalog.current_setting('brain.internal', true), 'off') = 'on';
$$;

create or replace function brain.assert_caller()
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_role text := coalesce(nullif(pg_catalog.current_setting('role', true), 'none'), session_user::text);
begin
  if brain.is_internal() then return; end if;
  if v_role = 'anon' then
    raise exception 'Acesso anonimo ao BRAIN nao e permitido' using errcode = 'insufficient_privilege';
  end if;
  if (select auth.uid()) is not null and not (select public.is_active_user()) then
    raise exception 'Usuario inativo' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

-- Administrador, ou o banco falando consigo mesmo.
create or replace function brain.is_privileged()
returns boolean language sql stable security definer set search_path = '' as $$
  select brain.is_internal()
      or (select public.is_admin())
      or ((select auth.uid()) is null
          and coalesce(nullif(pg_catalog.current_setting('role', true), 'none'), session_user::text)
              not in ('anon', 'authenticated'));
$$;

revoke execute on function brain.is_internal()    from public, anon;
revoke execute on function brain.assert_caller()  from public, anon;
revoke execute on function brain.is_privileged()  from public, anon;
grant  execute on function brain.is_internal()    to authenticated, service_role;
grant  execute on function brain.assert_caller()  to authenticated, service_role;
grant  execute on function brain.is_privileged()  to authenticated, service_role;

revoke execute on function brain.can_see_lead(uuid)        from public, anon;
revoke execute on function brain.can_see_opportunity(uuid) from public, anon;
grant  execute on function brain.can_see_lead(uuid)        to authenticated, service_role;
grant  execute on function brain.can_see_opportunity(uuid) to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- RLS
-- ════════════════════════════════════════════════════════════
alter table brain.channels      enable row level security;
alter table brain.attributions  enable row level security;
alter table brain.leads         enable row level security;
alter table brain.identities    enable row level security;
alter table brain.interactions  enable row level security;
alter table brain.opportunities enable row level security;
alter table brain.tasks         enable row level security;
alter table brain.events        enable row level security;
alter table brain.lead_merges   enable row level security;

-- Canais: todo usuário ativo lê; administrador mantém.
create policy channels_select on brain.channels for select to authenticated
  using ((select public.is_active_user()));
create policy channels_admin_write on brain.channels for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Atribuição: não tem dado pessoal; quem trabalha lê e registra.
create policy attributions_select on brain.attributions for select to authenticated
  using ((select public.is_active_user()));
create policy attributions_insert on brain.attributions for insert to authenticated
  with check ((select public.is_active_user()));
create policy attributions_admin_update on brain.attributions for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Leads: o dono, a fila (sem dono) e o administrador.
create policy leads_select on brain.leads for select to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())));
-- Vendedor cria lead para si ou para a fila; só administrador atribui a terceiro.
create policy leads_insert on brain.leads for insert to authenticated
  with check ((select public.is_active_user())
              and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())));
-- Vendedor edita o próprio e "pega" da fila; não transfere para outro.
create policy leads_update on brain.leads for update to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())))
  with check ((select public.is_active_user())
              and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())));
create policy leads_delete on brain.leads for delete to authenticated
  using ((select public.is_admin()));

-- Identidades: acompanham o lead; as de cliente, todo usuário ativo.
create policy identities_select on brain.identities for select to authenticated
  using ((select public.is_active_user())
         and ((lead_id is not null and brain.can_see_lead(lead_id))
              or (lead_id is null and customer_id is not null)));
create policy identities_insert on brain.identities for insert to authenticated
  with check ((select public.is_active_user())
              and (lead_id is null or brain.can_see_lead(lead_id)));
create policy identities_update on brain.identities for update to authenticated
  using ((select public.is_active_user()) and (lead_id is null or brain.can_see_lead(lead_id)))
  with check ((select public.is_active_user()) and (lead_id is null or brain.can_see_lead(lead_id)));
create policy identities_delete on brain.identities for delete to authenticated
  using ((select public.is_admin()));

-- Interações: acompanham o lead; sem lead, acompanham o cliente (compartilhado).
create policy interactions_select on brain.interactions for select to authenticated
  using ((select public.is_active_user())
         and ((lead_id is not null and brain.can_see_lead(lead_id))
              or (lead_id is null and customer_id is not null)));
create policy interactions_insert on brain.interactions for insert to authenticated
  with check ((select public.is_active_user())
              and (lead_id is null or brain.can_see_lead(lead_id)));
-- Quem registrou corrige o próprio registro; administrador, qualquer um.
create policy interactions_update on brain.interactions for update to authenticated
  using ((select public.is_admin()) or actor_id = (select auth.uid()))
  with check ((select public.is_admin()) or actor_id = (select auth.uid()));
create policy interactions_delete on brain.interactions for delete to authenticated
  using ((select public.is_admin()));

-- Oportunidades: dono, ou visível pelo lead, ou administrador.
create policy opportunities_select on brain.opportunities for select to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin())
              or owner_id = (select auth.uid())
              or (lead_id is not null and brain.can_see_lead(lead_id))
              or (lead_id is null and owner_id is null)));
create policy opportunities_insert on brain.opportunities for insert to authenticated
  with check ((select public.is_active_user())
              and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())));
create policy opportunities_update on brain.opportunities for update to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin()) or owner_id = (select auth.uid())
              or (owner_id is null and lead_id is not null and brain.can_see_lead(lead_id))))
  with check ((select public.is_active_user())
              and ((select public.is_admin()) or owner_id is null or owner_id = (select auth.uid())));
create policy opportunities_delete on brain.opportunities for delete to authenticated
  using ((select public.is_admin()));

-- Tarefas: responsável, quem criou, administrador.
create policy tasks_select on brain.tasks for select to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin())
              or assignee_id = (select auth.uid())
              or created_by = (select auth.uid())
              or (assignee_id is null and lead_id is not null and brain.can_see_lead(lead_id))));
create policy tasks_insert on brain.tasks for insert to authenticated
  with check ((select public.is_active_user()));
create policy tasks_update on brain.tasks for update to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin()) or assignee_id = (select auth.uid()) or created_by = (select auth.uid())))
  with check ((select public.is_active_user())
              and ((select public.is_admin()) or assignee_id = (select auth.uid()) or created_by = (select auth.uid())));
create policy tasks_delete on brain.tasks for delete to authenticated
  using ((select public.is_admin()));

-- Eventos: leitura pelo administrador e, para o vendedor, os do lead
-- dele. INSERT só por função (`brain.ingest_event`) — a API não grava
-- evento cru. UPDATE/DELETE: nenhum papel; o gatilho de imutabilidade
-- ainda vale para quem passar por cima.
create policy events_select on brain.events for select to authenticated
  using ((select public.is_active_user())
         and ((select public.is_admin())
              or (lead_id is not null and brain.can_see_lead(lead_id))));

-- Merges: só administrador, e só por função no futuro. Leitura de quem administra.
create policy lead_merges_admin on brain.lead_merges for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- ── Grants (o schema não tem default privilege; tudo explícito) ──
grant select                                on brain.channels      to authenticated;
grant insert, update, delete                on brain.channels      to authenticated;  -- RLS decide (admin)
grant select, insert, update                on brain.attributions  to authenticated;
grant select, insert, update, delete        on brain.leads         to authenticated;
grant select, insert, update, delete        on brain.identities    to authenticated;
grant select, insert, update, delete        on brain.interactions  to authenticated;
grant select, insert, update, delete        on brain.opportunities to authenticated;
grant select, insert, update, delete        on brain.tasks         to authenticated;
grant select                                on brain.events        to authenticated;
grant select, insert                        on brain.lead_merges   to authenticated;
grant all on all tables    in schema brain to service_role;
revoke truncate on all tables in schema brain from service_role, authenticated, public;
alter default privileges in schema brain revoke truncate on tables from service_role, authenticated;
grant all on all sequences in schema brain to service_role;
grant usage, select on all sequences in schema brain to authenticated;

-- ════════════════════════════════════════════════════════════
-- Normalização e identidade
-- ════════════════════════════════════════════════════════════
-- Telefone brasileiro: só dígitos, com o 55 na frente. "(43) 99999-0000",
-- "43999990000" e "+55 43 99999 0000" viram a mesma chave.
create or replace function brain.normalize_phone(p_value text)
returns text language sql immutable security invoker set search_path = '' as $$
  select case
    when d is null or d = '' then null
    when length(d) in (10, 11) then '55' || d
    when length(d) in (12, 13) and d like '55%' then d
    else d
  end
  from (select public.only_digits(p_value) as d) s;
$$;

create or replace function brain.normalize_identity(p_kind brain.identity_kind, p_value text)
returns text language sql immutable security invoker set search_path = '' as $$
  select case p_kind
    when 'phone'     then brain.normalize_phone(p_value)
    when 'whatsapp'  then brain.normalize_phone(p_value)
    when 'email'     then nullif(lower(btrim(p_value)), '')
    when 'instagram' then nullif(lower(ltrim(btrim(p_value), '@')), '')
    else nullif(btrim(p_value), '')
  end;
$$;

-- Quem é este contato? Devolve o lead (e/ou cliente) já conhecido para
-- a identidade, olhando primeiro o grafo do BRAIN e depois o cadastro
-- oficial de clientes (telefone, WhatsApp, e-mail).
create or replace function brain.resolve_identity(p_kind brain.identity_kind, p_value text)
returns table (lead_id uuid, customer_id uuid, matched_by text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_norm text := brain.normalize_identity(p_kind, p_value);
begin
  if v_norm is null then return; end if;

  return query
    select i.lead_id, i.customer_id, 'identity'::text
      from brain.identities i
     where i.kind = p_kind and i.value = v_norm
     limit 1;
  if found then return; end if;

  if p_kind in ('phone', 'whatsapp') then
    return query
      select null::uuid, c.id, 'customer_phone'::text
        from public.customers c
       where c.deleted_at is null
         and (brain.normalize_phone(c.phone) = v_norm or brain.normalize_phone(c.whatsapp) = v_norm)
       order by c.created_at
       limit 1;
  elsif p_kind = 'email' then
    return query
      select null::uuid, c.id, 'customer_email'::text
        from public.customers c
       where c.deleted_at is null and lower(btrim(c.email)) = v_norm
       order by c.created_at
       limit 1;
  end if;
end;
$$;

revoke execute on function brain.normalize_phone(text) from public, anon;
revoke execute on function brain.normalize_identity(brain.identity_kind, text) from public, anon;
revoke execute on function brain.resolve_identity(brain.identity_kind, text) from public, anon, authenticated;
grant  execute on function brain.normalize_phone(text) to authenticated, service_role;
grant  execute on function brain.normalize_identity(brain.identity_kind, text) to authenticated, service_role;
grant  execute on function brain.resolve_identity(brain.identity_kind, text) to service_role;  -- interna: quem responde ao usuario e find_or_create_lead

-- Normaliza o contato principal na escrita (BEFORE) e, com o `id` já
-- gravado (AFTER), mantém as identidades em dia: cada telefone/WhatsApp/
-- e-mail vira (ou atualiza) uma linha em `identities`. Um valor que já
-- pertence a OUTRO lead não é roubado — fica onde está, para o merge
-- humano decidir.
create or replace function brain.normalize_lead()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.phone    := brain.normalize_phone(new.phone);
  new.whatsapp := brain.normalize_phone(new.whatsapp);
  new.email    := nullif(lower(btrim(new.email)), '');
  new.state    := upper(nullif(btrim(new.state), ''));
  if new.status = 'converted' and new.converted_at is null then
    new.converted_at := now();
  end if;
  return new;
end;
$$;

revoke execute on function brain.normalize_lead() from public, anon, authenticated;

create trigger trg_leads_a_normalize before insert or update on brain.leads
  for each row execute function brain.normalize_lead();

create or replace function brain.after_lead_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  for r in
    select * from (values
      ('phone'::brain.identity_kind,    new.phone),
      ('whatsapp'::brain.identity_kind, new.whatsapp),
      ('email'::brain.identity_kind,    new.email)
    ) as v(kind, value)
    where value is not null
  loop
    insert into brain.identities (kind, value, value_raw, lead_id, customer_id, channel_key)
    values (r.kind, r.value, r.value, new.id, new.customer_id, new.channel_key)
    on conflict (kind, value) do update
      set last_seen_at = now(),
          customer_id  = coalesce(brain.identities.customer_id, excluded.customer_id)
      where brain.identities.lead_id = excluded.lead_id;
  end loop;
  return null;
end;
$$;

revoke execute on function brain.after_lead_write() from public, anon, authenticated;

create trigger trg_leads_identities after insert or update of phone, whatsapp, email, customer_id on brain.leads
  for each row execute function brain.after_lead_write();


-- ════════════════════════════════════════════════════════════
-- Entrada de contato: achar ou criar o lead
-- ════════════════════════════════════════════════════════════
-- O caminho único para "chegou alguém". Normaliza, procura pelas
-- identidades, procura no cadastro de clientes, e só então cria.
-- Devolve o que aconteceu, para o chamador (tela, n8n, agente) saber
-- se está falando com alguém novo ou com um cliente de anos.
create or replace function brain.find_or_create_lead(
  p_name          text,
  p_phone         text default null,
  p_email         text default null,
  p_instagram     text default null,
  p_channel_key   text default 'other',
  p_source_detail text default null,
  p_company_name  text default null,
  p_city          text default null,
  p_state         text default null,
  p_attribution   jsonb default null,
  p_owner_id      uuid default null
)
returns table (lead_id uuid, created boolean, customer_id uuid, matched_by text)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid       uuid := (select auth.uid());
  v_hit       record;
  v_lead      uuid;
  v_customer  uuid;
  v_matched   text;
  v_attr      uuid;
  v_kind      brain.identity_kind;
  v_value     text;
  v_norm      text;
begin
  perform brain.assert_caller();
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'Informe o nome do contato' using errcode = 'check_violation';
  end if;
  if p_owner_id is not null and p_owner_id <> v_uid and not brain.is_privileged() then
    raise exception 'Somente administrador atribui lead a outro vendedor' using errcode = 'insufficient_privilege';
  end if;

  -- Serializa por identidade: duas chamadas simultâneas com o mesmo
  -- telefone/e-mail entram uma de cada vez, e a segunda encontra o lead
  -- que a primeira criou. Sem isto nasciam dois leads para uma pessoa.
  for v_kind, v_value in
    select * from (values
      ('whatsapp'::brain.identity_kind,  p_phone),
      ('phone'::brain.identity_kind,     p_phone),
      ('email'::brain.identity_kind,     p_email),
      ('instagram'::brain.identity_kind, p_instagram)
    ) as v(kind, value) where value is not null
  loop
    v_norm := brain.normalize_identity(v_kind, v_value);
    if v_norm is not null then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('brain.identity:' || v_kind::text || ':' || v_norm));
    end if;
  end loop;

  -- 1. Já conhecemos alguma dessas identidades? A primeira que bater decide.
  for v_kind, v_value in
    select * from (values
      ('whatsapp'::brain.identity_kind,  p_phone),
      ('phone'::brain.identity_kind,     p_phone),
      ('email'::brain.identity_kind,     p_email),
      ('instagram'::brain.identity_kind, p_instagram)
    ) as v(kind, value) where value is not null
  loop
    select * into v_hit from brain.resolve_identity(v_kind, v_value);
    if found and (v_hit.lead_id is not null or v_hit.customer_id is not null) then
      v_lead := v_hit.lead_id; v_customer := v_hit.customer_id; v_matched := v_hit.matched_by;
      exit;
    end if;
  end loop;

  -- Lead já existe.
  if v_lead is not null then
    select coalesce(l.merged_into_lead_id, l.id) into v_lead from brain.leads l where l.id = v_lead;

    -- De outro vendedor: não se cria duplicata e não se revela nada.
    -- O chamador recebe "existe, mas não é seu" e o administrador decide.
    if not brain.is_privileged() and not brain.can_see_lead(v_lead) then
      return query select null::uuid, false, null::uuid, 'exists_elsewhere'::text;
      return;
    end if;

    select l.customer_id into v_customer from brain.leads l where l.id = v_lead;

    -- Enriquecimento: a identidade nova que veio junto (o e-mail de quem
    -- só tínhamos o Instagram) passa a pertencer a este lead. Se já
    -- pertence a OUTRO lead, não é roubada — fica para o merge humano.
    for v_kind, v_value in
      select * from (values
        ('whatsapp'::brain.identity_kind,  p_phone),
        ('phone'::brain.identity_kind,     p_phone),
        ('email'::brain.identity_kind,     p_email),
        ('instagram'::brain.identity_kind, p_instagram)
      ) as v(kind, value) where value is not null
    loop
      v_norm := brain.normalize_identity(v_kind, v_value);
      if v_norm is not null then
        insert into brain.identities (kind, value, value_raw, lead_id, customer_id, channel_key)
        values (v_kind, v_norm, v_value, v_lead, v_customer, p_channel_key)
        on conflict (kind, value) do update
          set last_seen_at = now()
          where brain.identities.lead_id = excluded.lead_id;
      end if;
    end loop;

    update brain.leads set last_touch_at = now() where id = v_lead;
    return query select v_lead, false, v_customer, v_matched;
    return;
  end if;

  -- 2. Origem, quando informada.
  if p_attribution is not null and p_attribution <> '{}'::jsonb then
    insert into brain.attributions
      (channel_key, source, medium, campaign, content, term, referrer, landing_page,
       external_campaign_id, external_adset_id, external_ad_id, click_id, metadata)
    values
      (p_channel_key,
       p_attribution->>'source', p_attribution->>'medium', p_attribution->>'campaign',
       p_attribution->>'content', p_attribution->>'term', p_attribution->>'referrer',
       p_attribution->>'landing_page', p_attribution->>'external_campaign_id',
       p_attribution->>'external_adset_id', p_attribution->>'external_ad_id',
       p_attribution->>'click_id', p_attribution)
    returning id into v_attr;
  end if;

  -- 3. Lead novo — ligado ao cliente do ERP quando o contato bateu lá.
  insert into brain.leads
    (name, company_name, phone, whatsapp, email, city, state,
     customer_id, owner_id, channel_key, source_detail, first_attribution_id,
     status, created_by, updated_by)
  values
    (btrim(p_name), p_company_name, p_phone, p_phone, p_email, p_city, p_state,
     v_customer, coalesce(p_owner_id, v_uid), p_channel_key, p_source_detail, v_attr,
     'new', v_uid, v_uid)
  returning id into v_lead;

  if p_instagram is not null then
    insert into brain.identities (kind, value, value_raw, lead_id, customer_id, channel_key)
    values ('instagram', brain.normalize_identity('instagram', p_instagram), p_instagram, v_lead, v_customer, 'instagram')
    on conflict (kind, value) do nothing;
  end if;

  return query select v_lead, true, v_customer, coalesce(v_matched, 'none');
end;
$$;

revoke execute on function brain.find_or_create_lead(text, text, text, text, text, text, text, text, text, jsonb, uuid) from public, anon;
grant  execute on function brain.find_or_create_lead(text, text, text, text, text, text, text, text, text, jsonb, uuid) to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- Interação: registrar, sem duplicar, e tocar o lead
-- ════════════════════════════════════════════════════════════
create or replace function brain.log_interaction(
  p_lead_id          uuid,
  p_summary          text,
  p_channel_key      text default 'other',
  p_interaction_type brain.interaction_type default 'message',
  p_direction        brain.interaction_direction default 'inbound',
  p_occurred_at      timestamptz default now(),
  p_source           text default 'app',
  p_external_id      text default null,
  p_opportunity_id   uuid default null,
  p_event_id         bigint default null,
  p_metadata         jsonb default '{}'::jsonb
)
returns table (interaction_id uuid, duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid  uuid := (select auth.uid());
  v_id   uuid;
  v_cust uuid;
  v_ev   record;
begin
  perform brain.assert_caller();
  if not brain.is_privileged() and not brain.can_see_lead(p_lead_id) then
    raise exception 'Lead fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if p_opportunity_id is not null and not brain.is_privileged() and not brain.can_see_opportunity(p_opportunity_id) then
    raise exception 'Oportunidade fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  select customer_id into v_cust from brain.leads where id = p_lead_id;
  if not found then
    raise exception 'Lead nao encontrado' using errcode = 'no_data_found';
  end if;

  -- O evento só se liga à interação quando é O MESMO fato (mesma origem,
  -- mesmo id externo) ou quando quem liga é privilegiado. Conhecer o
  -- número de um evento não dá acesso a ele.
  if p_event_id is not null then
    select id, source, external_id, lead_id into v_ev from brain.events where id = p_event_id;
    if not found then
      raise exception 'Evento nao encontrado' using errcode = 'no_data_found';
    end if;
    if not brain.is_privileged()
       and not (v_ev.source = p_source and v_ev.external_id is not distinct from p_external_id and p_external_id is not null) then
      raise exception 'Evento nao corresponde a esta interacao' using errcode = 'insufficient_privilege';
    end if;
    if v_ev.lead_id is not null and v_ev.lead_id <> p_lead_id then
      raise exception 'Evento ja pertence a outro lead' using errcode = 'check_violation';
    end if;
  end if;

  -- Idempotente de verdade: o INSERT decide, e a corrida cai no `on
  -- conflict` em vez de estourar unicidade.
  insert into brain.interactions
    (lead_id, customer_id, opportunity_id, channel_key, interaction_type, direction,
     summary, occurred_at, actor_id, source, external_id, event_id, metadata)
  values
    (p_lead_id, v_cust, p_opportunity_id, p_channel_key, p_interaction_type, p_direction,
     p_summary, coalesce(p_occurred_at, now()), v_uid, p_source, p_external_id, p_event_id, coalesce(p_metadata, '{}'::jsonb))
  on conflict (source, external_id) where external_id is not null do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from brain.interactions where source = p_source and external_id = p_external_id;
    return query select v_id, true;
    return;
  end if;

  if p_event_id is not null then
    update brain.events
       set lead_id = coalesce(lead_id, p_lead_id),
           customer_id = coalesce(customer_id, v_cust),
           opportunity_id = coalesce(opportunity_id, p_opportunity_id)
     where id = p_event_id;
  end if;

  return query select v_id, false;
end;
$$;

revoke execute on function brain.log_interaction(uuid, text, text, brain.interaction_type, brain.interaction_direction, timestamptz, text, text, uuid, bigint, jsonb) from public, anon;
grant  execute on function brain.log_interaction(uuid, text, text, brain.interaction_type, brain.interaction_direction, timestamptz, text, text, uuid, bigint, jsonb) to authenticated, service_role;

-- Toda interação move `last_touch_at` (e `first_touch_at` se veio antes).
create or replace function brain.touch_lead_from_interaction()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.lead_id is not null then
    update brain.leads
       set last_touch_at  = greatest(last_touch_at, new.occurred_at),
           first_touch_at = least(first_touch_at, new.occurred_at),
           status = case when status = 'new' and new.direction = 'outbound' then 'contacted' else status end
     where id = new.lead_id;
  end if;
  return null;
end;
$$;

revoke execute on function brain.touch_lead_from_interaction() from public, anon, authenticated;

create trigger trg_interactions_touch_lead after insert on brain.interactions
  for each row execute function brain.touch_lead_from_interaction();

-- ════════════════════════════════════════════════════════════
-- Barramento: ingestão idempotente
-- ════════════════════════════════════════════════════════════
create or replace function brain.ingest_event(
  p_event_name     text,
  p_source         text,
  p_payload        jsonb default '{}'::jsonb,
  p_external_id    text default null,
  p_occurred_at    timestamptz default now(),
  p_channel_key    text default null,
  p_lead_id        uuid default null,
  p_customer_id    uuid default null,
  p_opportunity_id uuid default null,
  p_product_id     uuid default null,
  p_visitor_id     text default null,
  p_session_id     text default null,
  p_attribution_id uuid default null,
  p_event_version  integer default 1,
  p_metadata       jsonb default '{}'::jsonb
)
returns table (event_id bigint, duplicate boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_id    bigint;
  v_lead  uuid;
begin
  perform brain.assert_caller();

  -- O caminho humano (vendedor pela aplicação) não fala em nome do ERP
  -- nem publica fato de orçamento/pedido: esses nascem dos gatilhos.
  if not brain.is_privileged() then
    if p_source in ('erp', 'brain') or p_event_name ~ '^(quote|order|erp|brain)\.' then
      raise exception 'Origem e evento reservados ao sistema' using errcode = 'insufficient_privilege';
    end if;
    if p_lead_id is not null and not brain.can_see_lead(p_lead_id) then
      raise exception 'Lead fora do seu alcance' using errcode = 'insufficient_privilege';
    end if;
    if p_opportunity_id is not null and not brain.can_see_opportunity(p_opportunity_id) then
      raise exception 'Oportunidade fora do seu alcance' using errcode = 'insufficient_privilege';
    end if;
  end if;

  insert into brain.events
    (event_name, event_version, source, channel_key, lead_id, customer_id, opportunity_id,
     product_id, actor_id, attribution_id, session_id, visitor_id, external_id,
     occurred_at, payload, metadata)
  values
    (p_event_name, coalesce(p_event_version, 1), p_source, p_channel_key, p_lead_id, p_customer_id,
     p_opportunity_id, p_product_id, v_uid, p_attribution_id, p_session_id, p_visitor_id, p_external_id,
     coalesce(p_occurred_at, now()), coalesce(p_payload, '{}'::jsonb), coalesce(p_metadata, '{}'::jsonb))
  on conflict (source, external_id) where external_id is not null do nothing
  returning id into v_id;

  if v_id is not null then
    return query select v_id, false;
    return;
  end if;

  -- Duplicado: devolve o id só a quem pode ver o evento que já existe.
  select id, lead_id into v_id, v_lead from brain.events where source = p_source and external_id = p_external_id;
  if brain.is_privileged() or (v_lead is not null and brain.can_see_lead(v_lead)) then
    return query select v_id, true;
  else
    return query select null::bigint, true;
  end if;
end;
$$;

revoke execute on function brain.ingest_event(text, text, jsonb, text, timestamptz, text, uuid, uuid, uuid, uuid, text, text, uuid, integer, jsonb) from public, anon;
grant  execute on function brain.ingest_event(text, text, jsonb, text, timestamptz, text, uuid, uuid, uuid, uuid, text, text, uuid, integer, jsonb) to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- Ponte com o ERP: orçamento e pedido viram eventos e fecham o ciclo
-- ════════════════════════════════════════════════════════════
-- O ERP não sabe que o BRAIN existe — e não precisa. Estes gatilhos
-- escutam `public.quotes` e `public.orders` e:
--   · publicam `quote.created / quote.<status>` e `order.created /
--     order.<status>` no barramento (idempotentes por chave interna);
--   · ligam a oportunidade ao orçamento e ao pedido quando o vínculo é
--     inequívoco (a oportunidade já apontava para o orçamento);
--   · quando o pedido nasce, a oportunidade vira GANHA e o lead vira
--     CONVERTIDO, apontando para o cliente do pedido.
create or replace function brain.on_quote_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_lead  uuid;
  v_opp   uuid;
begin
  if tg_op = 'INSERT' then
    v_event := 'quote.created';
  elsif new.status is distinct from old.status then
    v_event := 'quote.' || new.status::text;
  else
    return null;
  end if;

  -- A ponte é interna e NUNCA derruba a operação do ERP: se o BRAIN
  -- falhar, o orçamento continua sendo salvo e o erro vai para o log.
  begin
    perform pg_catalog.set_config('brain.internal', 'on', true);

    select id, lead_id into v_opp, v_lead from brain.opportunities
     where quote_id = new.id order by created_at limit 1;
    if v_lead is null then
      select id into v_lead from brain.leads
       where customer_id = new.customer_id and merged_into_lead_id is null
       order by created_at limit 1;
    end if;

    -- Chave por transação: cada mudança real vira um evento; a mesma
    -- transação não publica duas vezes.
    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('quote_id', new.id, 'number', new.number, 'status', new.status,
                         'total', new.total, 'owner_id', new.owner_id),
      'quote:' || new.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson', v_lead, new.customer_id, v_opp, null, null, null, null, 1, '{}'::jsonb);

    if v_opp is not null and new.status = 'approved' then
      update brain.opportunities set stage = 'negotiation'
       where id = v_opp and stage in ('prospecting', 'qualified', 'proposal');
    elsif v_opp is not null and new.status = 'sent' then
      update brain.opportunities set stage = 'proposal'
       where id = v_opp and stage in ('prospecting', 'qualified');
    end if;

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning 'brain: ponte de orcamento falhou (%): %', v_event, sqlerrm;
  end;

  return null;
end;
$$;

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_order public.orders%rowtype;
  r       record;
begin
  -- No INSERT este gatilho é DEFERRED: dispara no commit, quando os itens
  -- já entraram e o total já foi recalculado. Lê a linha de novo para
  -- publicar o valor FINAL da venda, não o cabeçalho vazio.
  select * into v_order from public.orders where id = new.id;
  if not found then return null; end if;

  if tg_op = 'INSERT' then
    v_event := 'order.created';
  elsif new.status is distinct from old.status then
    v_event := 'order.' || new.status::text;
  else
    return null;
  end if;

  begin
    perform pg_catalog.set_config('brain.internal', 'on', true);

    if tg_op = 'INSERT' and v_order.quote_id is not null then
      -- A oportunidade que apontava para o orçamento de origem ganha o pedido.
      for r in
        update brain.opportunities
           set order_id = v_order.id, stage = 'won',
               customer_id = coalesce(customer_id, v_order.customer_id)
         where quote_id = v_order.quote_id and stage not in ('won', 'lost')
         returning id, lead_id
      loop
        if r.lead_id is not null then
          update brain.leads
             set status = 'converted',
                 converted_at = coalesce(converted_at, now()),
                 customer_id = coalesce(customer_id, v_order.customer_id)
           where id = r.lead_id;
        end if;
      end loop;
    elsif v_event = 'order.cancelled' then
      -- Venda desfeita: a oportunidade volta à negociação. O pedido fica
      -- referenciado (é histórico) e o lead continua convertido — o
      -- cliente existe; o que não existe mais é esta venda.
      update brain.opportunities set stage = 'negotiation'
       where order_id = v_order.id and stage = 'won';
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('order_id', v_order.id, 'number', v_order.number, 'status', v_order.status,
                         'total', v_order.total, 'quote_id', v_order.quote_id, 'owner_id', v_order.owner_id),
      'order:' || v_order.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson',
      (select o.lead_id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      v_order.customer_id,
      (select o.id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      null, null, null, null, 1, '{}'::jsonb);

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning 'brain: ponte de pedido falhou (%): %', v_event, sqlerrm;
  end;

  return null;
end;
$$;

revoke execute on function brain.on_quote_change() from public, anon, authenticated;
revoke execute on function brain.on_order_change() from public, anon, authenticated;

create trigger trg_brain_quotes after insert or update of status on public.quotes
  for each row execute function brain.on_quote_change();

-- INSERT adiado para o commit (ver o comentário da função): o pedido nasce
-- vazio e é preenchido na mesma transação por create_order_from_quote.
create constraint trigger trg_brain_orders_created
  after insert on public.orders
  deferrable initially deferred
  for each row execute function brain.on_order_change();
create trigger trg_brain_orders after update of status on public.orders
  for each row execute function brain.on_order_change();

-- ════════════════════════════════════════════════════════════
-- Vínculos: uma FK prova que existe, não que é seu
-- ════════════════════════════════════════════════════════════
-- `security invoker` de propósito: o `exists` em quotes/orders passa
-- pelo RLS do ERP, então "não enxergo" vira "não posso vincular". Para o
-- lead e a oportunidade vale a visibilidade do BRAIN. Autoria não é
-- campo de formulário: `created_by`/`actor_id` são quem está logado.
create or replace function brain.check_links()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_row jsonb := to_jsonb(new);
  v_lead uuid := (v_row ->> 'lead_id')::uuid;
  v_opp  uuid := (v_row ->> 'opportunity_id')::uuid;
  v_cust uuid := (v_row ->> 'customer_id')::uuid;
  v_quote uuid := (v_row ->> 'quote_id')::uuid;
  v_order uuid := (v_row ->> 'order_id')::uuid;
begin
  if tg_op = 'INSERT' then
    if tg_table_name in ('opportunities', 'tasks') and v_uid is not null then
      new.created_by := v_uid;
      new.updated_by := v_uid;
    elsif tg_table_name = 'interactions' and v_uid is not null then
      new.actor_id := v_uid;
    end if;
  elsif tg_table_name in ('opportunities', 'tasks') then
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if v_uid is not null then new.updated_by := v_uid; end if;
  elsif tg_table_name = 'interactions' then
    new.actor_id := old.actor_id;
  end if;

  if brain.is_privileged() then
    return new;
  end if;

  if v_lead is not null and not brain.can_see_lead(v_lead) then
    raise exception 'Lead fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if tg_table_name <> 'opportunities' and v_opp is not null and not brain.can_see_opportunity(v_opp) then
    raise exception 'Oportunidade fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_cust is not null and not exists (select 1 from public.customers c where c.id = v_cust) then
    raise exception 'Cliente fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_quote is not null and not exists (select 1 from public.quotes q where q.id = v_quote) then
    raise exception 'Orcamento fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_order is not null and not exists (select 1 from public.orders o where o.id = v_order) then
    raise exception 'Pedido fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  -- Lead e oportunidade têm de falar da mesma pessoa.
  if tg_table_name in ('tasks', 'interactions') and v_lead is not null and v_opp is not null
     and not exists (select 1 from brain.opportunities o where o.id = v_opp and o.lead_id = v_lead) then
    raise exception 'Oportunidade nao pertence a este lead' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function brain.check_links() from public, anon, authenticated;

create trigger trg_opportunities_a_links before insert or update on brain.opportunities
  for each row execute function brain.check_links();
create trigger trg_tasks_a_links before insert or update on brain.tasks
  for each row execute function brain.check_links();
create trigger trg_interactions_a_links before insert or update on brain.interactions
  for each row execute function brain.check_links();

-- ════════════════════════════════════════════════════════════
-- A jornada — uma linha do tempo por lead/cliente
-- ════════════════════════════════════════════════════════════
create view brain.journey_entries
with (security_invoker = true) as
select 'event'::text        as kind, e.id::text as ref_id, e.lead_id, e.customer_id, e.opportunity_id,
       e.occurred_at, e.event_name as title, e.channel_key, e.source, e.payload as details
  from brain.events e
union all
select 'interaction', i.id::text, i.lead_id, i.customer_id, i.opportunity_id,
       i.occurred_at, i.interaction_type::text || ' ' || i.direction::text || ': ' || i.summary,
       i.channel_key, i.source, i.metadata
  from brain.interactions i
union all
select 'opportunity', o.id::text, o.lead_id, o.customer_id, o.id,
       o.created_at, 'oportunidade: ' || o.title, o.channel_key, 'brain',
       jsonb_build_object('stage', o.stage, 'estimated_value', o.estimated_value, 'product_id', o.product_id)
  from brain.opportunities o
union all
select 'quote', q.id::text, o.lead_id, q.customer_id, o.id,
       q.created_at, 'orçamento ' || q.number, 'salesperson', 'erp',
       jsonb_build_object('status', q.status, 'total', q.total, 'quote_id', q.id)
  from public.quotes q
  left join brain.opportunities o on o.quote_id = q.id
 where q.deleted_at is null
union all
select 'order', od.id::text, o.lead_id, od.customer_id, o.id,
       od.created_at, 'pedido ' || od.number, 'salesperson', 'erp',
       jsonb_build_object('status', od.status, 'total', od.total, 'order_id', od.id)
  from public.orders od
  left join brain.opportunities o on o.order_id = od.id
 where od.deleted_at is null;

grant select on brain.journey_entries to authenticated, service_role;

comment on view brain.journey_entries is
  'Linha do tempo: eventos, interacoes, oportunidades, orcamentos e pedidos de um lead/cliente. security_invoker: cada um ve o que o RLS deixa.';

-- ════════════════════════════════════════════════════════════
-- Auditoria de ALTERAÇÃO (não de negócio): mesma trilha do ERP
-- ════════════════════════════════════════════════════════════
create trigger trg_audit_leads after insert or update or delete on brain.leads
  for each row execute function public.audit_capture('lead', 'id', 'name', '', '');
create trigger trg_audit_opportunities after insert or update or delete on brain.opportunities
  for each row execute function public.audit_capture('opportunity', 'id', 'title', 'lead', 'lead_id');
create trigger trg_audit_tasks after insert or update or delete on brain.tasks
  for each row execute function public.audit_capture('task', 'id', 'title', 'lead', 'lead_id');
create trigger trg_audit_identities after insert or update or delete on brain.identities
  for each row execute function public.audit_capture('identity', 'id', 'value', 'lead', 'lead_id');
create trigger trg_audit_lead_merges after insert on brain.lead_merges
  for each row execute function public.audit_capture('lead_merge', 'id', '', 'lead', 'target_lead_id');
create trigger trg_audit_channels after insert or update or delete on brain.channels
  for each row execute function public.audit_capture('channel', 'key', 'name', '', '');

-- `events` não é auditado: é imutável e É o registro. `interactions`
-- audita só correção e exclusão — o INSERT já é o fato.
create trigger trg_audit_interactions after update or delete on brain.interactions
  for each row execute function public.audit_capture('interaction', 'id', 'summary', 'lead', 'lead_id');

-- Texto integral de `audit_capture` (20260909100000) mais: colunas de
-- toque do lead ignoradas (senão toda interação geraria um `lead.updated`
-- fantasma) e verbos próprios para lead, oportunidade e tarefa.
create or replace function public.audit_capture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity      text := tg_argv[0];
  v_pk          text := tg_argv[1];
  v_label_col   text := nullif(tg_argv[2], '');
  v_parent_type text := nullif(tg_argv[3], '');
  v_parent_col  text := nullif(tg_argv[4], '');

  v_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  v_new jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_row jsonb;

  -- Ruído de auditoria: `updated_at`/`updated_by` mudam em toda escrita e
  -- não contam nada que o log já não diga (ator e horário são colunas
  -- próprias). As demais são DERIVADAS — ver o comentário do bloco.
  v_ignore  text[] := array['updated_at', 'updated_by'];
  v_secret  text[] := array[]::text[];

  v_changed  text[];
  v_old_diff jsonb := '{}'::jsonb;
  v_new_diff jsonb := '{}'::jsonb;
  v_campo    text;

  v_uid   uuid := auth.uid();
  v_kind  text;
  v_email text;
  v_name  text;
  v_role  public.user_role;

  -- CUIDADO: dentro de uma função `security definer`, `current_user` é o
  -- DONO da função (postgres), não quem disparou a escrita — usá-lo aqui
  -- classificaria todo mundo como sistema. O que sobrevive ao
  -- `security definer` é o GUC `role`, que é exatamente o que o PostgREST
  -- define (`set local role authenticated` / `anon`). Sem SET ROLE ele vale
  -- 'none', e aí o papel real é o do login — o caso do pg_cron.
  v_db_role text := coalesce(nullif(current_setting('role', true), 'none'), session_user);

  v_action    text;
  v_entity_id text;
  v_label     text;
  v_parent_id text;
begin
  v_row := coalesce(v_new, v_old);

  -- ── Colunas derivadas e segredos, por tabela ──────────────
  -- `subtotal`/`total` de `quotes` são recalculados por
  -- `recalculate_quote_totals()` a cada mudança de item: sem esta exceção,
  -- adicionar um item ao orçamento geraria DOIS eventos — o do item e um
  -- `quote.updated` fantasma. `line_total` é coluna gerada.
  -- `view_count` sobe a cada visita anônima ao link público: seriam
  -- centenas de linhas sem ator e sem decisão.
  if tg_table_name = 'quotes' then
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'quote_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'orders' then
    -- `recalculate_order_totals()` reescreve subtotal/total logo depois do
    -- INSERT do pedido: sem isto, todo pedido nasceria com um
    -- `order.updated` fantasma colado ao `order.created`.
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'order_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'purchases' then
    v_ignore := v_ignore || array['items_total', 'total'];
  elsif tg_table_name = 'purchase_items' then
    -- Rateio e custo final são escritos pelo recebimento, linha a linha;
    -- o evento que importa é o `purchase.received`, não N `item_changed`.
    v_ignore := v_ignore || array['line_total', 'freight_share', 'landed_cost', 'previous_cost'];
  elsif tg_table_name = 'leads' then
    -- Carimbos de toque sobem a cada interação: são consequência, não
    -- decisão — a interação em si já é o registro. `score` é editável e
    -- fica auditado.
    v_ignore := v_ignore || array['first_touch_at', 'last_touch_at'];
  elsif tg_table_name = 'identities' then
    v_ignore := v_ignore || array['last_seen_at'];
  elsif tg_table_name = 'financial_entries' then
    -- `status` é derivado da soma das baixas; a baixa em si já é evento.
    v_ignore := v_ignore || array['status'];
  elsif tg_table_name = 'quote_share_tokens' then
    v_ignore := v_ignore || array['view_count'];
    -- O token é credencial de capacidade: quem o tem abre o orçamento sem
    -- login. É o único segredo que existe em `public`. Redigido AQUI, na
    -- escrita — filtrar só na leitura se contorna.
    v_secret := array['token'];
  end if;

  -- ── Antes e depois ────────────────────────────────────────
  if tg_op = 'UPDATE' then
    for v_campo in select k from jsonb_object_keys(v_new) as k loop
      continue when v_campo = any (v_ignore);
      if v_new -> v_campo is distinct from v_old -> v_campo then
        v_changed  := coalesce(v_changed, array[]::text[]) || v_campo;
        v_old_diff := v_old_diff || jsonb_build_object(v_campo, v_old -> v_campo);
        v_new_diff := v_new_diff || jsonb_build_object(v_campo, v_new -> v_campo);
      end if;
    end loop;

    -- Nada relevante mudou: não existe evento. É isto que mantém o log
    -- legível quando o recálculo de totais dispara o trigger.
    if v_changed is null then
      return null;
    end if;
  else
    v_old_diff := v_old;   -- nulo no INSERT
    v_new_diff := v_new;   -- nulo no DELETE
  end if;

  foreach v_campo in array v_secret loop
    if v_old_diff ? v_campo then
      v_old_diff := jsonb_set(v_old_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
    if v_new_diff ? v_campo then
      v_new_diff := jsonb_set(v_new_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
  end loop;

  -- ── Quem ──────────────────────────────────────────────────
  -- `auth.uid()` primeiro: ele sobrevive a funções `security definer`
  -- (lê o claim do JWT), então `discard_quote_draft()` continua sendo
  -- atribuída ao usuário de verdade, e não a `postgres`.
  if v_uid is not null then
    v_kind := 'user';
    select p.email, p.full_name, p.role
      into v_email, v_name, v_role
      from public.profiles p
     where p.id = v_uid;
  elsif v_db_role in ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role') then
    v_kind := 'system';        -- pg_cron, migration, SQL Editor, GoTrue
  elsif v_db_role = 'anon' then
    v_kind := 'anonymous';     -- link público
  else
    v_kind := 'unknown';
  end if;

  -- ── O verbo de negócio ────────────────────────────────────
  -- Derivado do diff, porque a aplicação não consegue informá-lo. Quando
  -- mais de uma coisa muda na mesma escrita, o evento mais específico
  -- vence — mas `changed_fields` continua listando tudo.
  if tg_op = 'DELETE' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_removed'
      when 'order_item'        then 'order.item_removed'
      when 'purchase_item'     then 'purchase.item_removed'
      when 'kit_item'          then 'kit.item_removed'
      when 'quote_share_token' then 'quote.link_deleted'
      when 'product_cost'      then 'product.cost_removed'
      else v_entity || '.deleted'
    end;

  elsif tg_op = 'INSERT' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_added'
      when 'order_item'        then 'order.item_added'
      when 'purchase_item'     then 'purchase.item_added'
      when 'financial_payment' then 'financial.payment_registered'
      when 'kit_item'          then 'kit.item_added'
      when 'quote_share_token' then 'quote.link_created'
      when 'product_cost'      then 'product.cost_changed'
      else v_entity || '.created'
    end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is not null then
    -- Exclusão lógica é o evento mais forte da escrita, venha ela de onde vier.
    v_action := case v_entity when 'quote' then 'quote.discarded'
                              else v_entity || '.deleted' end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is null then
    v_action := v_entity || '.restored';

  elsif v_entity = 'user' and 'role' = any (v_changed) then
    v_action := 'user.role_changed';

  elsif 'is_active' = any (v_changed) then
    v_action := v_entity || case when (v_new ->> 'is_active')::boolean
                                 then '.activated' else '.deactivated' end;

  elsif v_entity = 'quote' and 'status' = any (v_changed) then
    v_action := case v_new ->> 'status'
      when 'approved'  then 'quote.approved'
      when 'rejected'  then 'quote.rejected'
      when 'cancelled' then 'quote.cancelled'
      when 'expired'   then 'quote.expired'
      else 'quote.status_changed'
    end;

  elsif v_entity = 'order' and 'status' = any (v_changed) then
    -- picking / invoiced / delivered / cancelled: o verbo é a situação nova.
    v_action := 'order.' || (v_new ->> 'status');

  elsif v_entity = 'purchase' and 'status' = any (v_changed) then
    v_action := 'purchase.' || (v_new ->> 'status');

  elsif v_entity = 'financial_entry' and 'cancelled_at' = any (v_changed)
        and (v_new ->> 'cancelled_at') is not null then
    v_action := 'financial.cancelled';

  elsif v_entity = 'lead' and 'status' = any (v_changed) then
    v_action := 'lead.' || (v_new ->> 'status');

  elsif v_entity = 'lead' and 'owner_id' = any (v_changed) then
    v_action := 'lead.assigned';

  elsif v_entity = 'lead' and 'merged_into_lead_id' = any (v_changed) then
    v_action := 'lead.merged';

  elsif v_entity = 'opportunity' and 'stage' = any (v_changed) then
    v_action := 'opportunity.' || (v_new ->> 'stage');

  elsif v_entity = 'task' and 'status' = any (v_changed) then
    v_action := 'task.' || (v_new ->> 'status');

  elsif v_entity = 'quote_share_token' and 'revoked_at' = any (v_changed)
        and (v_new ->> 'revoked_at') is not null then
    v_action := 'quote.link_revoked';

  elsif v_entity = 'product_cost' then
    v_action := 'product.cost_changed';

  elsif v_entity = 'product' and 'sale_price' = any (v_changed) then
    v_action := 'product.price_changed';

  elsif v_entity = 'kit' and 'discount_percent' = any (v_changed) then
    v_action := 'kit.discount_changed';

  elsif v_entity = 'kit_item' and 'item_type' = any (v_changed) then
    v_action := 'kit.item_type_changed';

  elsif v_entity = 'kit_item' and 'quantity' = any (v_changed) then
    v_action := 'kit.item_quantity_changed';

  elsif v_entity = 'quote_item'        then v_action := 'quote.item_changed';
  elsif v_entity = 'order_item'        then v_action := 'order.item_changed';
  elsif v_entity = 'purchase_item'     then v_action := 'purchase.item_changed';
  elsif v_entity = 'kit_item'          then v_action := 'kit.item_changed';
  elsif v_entity = 'quote_share_token' then v_action := 'quote.link_changed';
  elsif v_entity = 'user'              then v_action := 'user.profile_updated';
  else                                      v_action := v_entity || '.updated';
  end if;

  -- ── Onde ──────────────────────────────────────────────────
  v_entity_id := v_row ->> v_pk;
  v_label     := case when v_label_col  is null then null else v_row ->> v_label_col  end;
  v_parent_id := case when v_parent_col is null then null else v_row ->> v_parent_col end;

  insert into public.audit_log (
    actor_kind, actor_user_id, actor_email, actor_name, actor_role, actor_db_role,
    action, operation,
    entity_type, entity_id, entity_label, parent_type, parent_id,
    changed_fields, old_data, new_data, metadata
  ) values (
    v_kind, v_uid, v_email, v_name, v_role, v_db_role,
    v_action, tg_op,
    v_entity, v_entity_id, v_label, v_parent_type, v_parent_id,
    v_changed, v_old_diff, v_new_diff,
    jsonb_build_object('txid', txid_current(), 'table', tg_table_name)
  );

  return null;   -- trigger AFTER: o retorno é ignorado
end;
$$;

revoke execute on function public.audit_capture() from public, anon, authenticated;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911140000_brain_exclusoes.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — o ERP volta a poder excluir
--
-- A revisão independente de 11/09 mostrou que a fundação da Fase 1
-- BLOQUEIA exclusões físicas legítimas do ERP. Nove casos reproduzidos
-- (bancada em supabase/db-tests/27_brain_exclusoes.sql):
--
--   D1  cliente ligado a identidade sem lead  → chk_identity_has_owner
--   D2  cliente ligado a interação sem lead   → chk_interaction_has_subject
--   D3  cliente ligado a oportunidade s/ lead → chk_opportunity_has_subject
--   D4  perfil citado em events.actor_id      → protect_event()
--   D5  perfil em tasks.created_by            → check_links() restaurava o valor
--   D6  perfil em opportunities.created_by    → idem
--   D7  perfil em interactions.actor_id       → idem
--   D8  lead com oportunidade sem cliente     → chk_opportunity_has_subject
--   D9  exclusão física do perfil inteiro     → soma de D4 a D7
--
-- A causa é sempre a mesma: a FK anula o vínculo (`on delete set null`),
-- e um CHECK ou um gatilho recusa a linha resultante. O BRAIN, que não
-- deveria nem existir para o ERP, virava um veto.
--
-- ── A REGRA, escrita de uma vez ─────────────────────────────
--
-- Quando a entidade referenciada deixa de existir, o BRAIN **anula o
-- vínculo e guarda um rótulo textual de quem era**.
--
--   · nenhuma linha do BRAIN é apagada por causa de exclusão no ERP;
--   · nenhuma exclusão do ERP é bloqueada pelo BRAIN;
--   · o rótulo é escrito SÓ por gatilho, a partir do registro real —
--     nunca aceito do cliente, nunca inventado;
--   · autoria só pode virar nula, e só quando o perfil sumiu de fato.
--
-- Isso é exclusão FÍSICA. A exclusão LÓGICA do ERP (`deleted_at`, o botão
-- de "excluir cliente" que na verdade desativa) nunca esteve em jogo:
-- `delete_customer()` só remove fisicamente quem não tem orçamento nem
-- pedido, e nada disso encosta em `deleted_at`.
--
-- Uma exceção deliberada: `identities.lead_id` continua `on delete
-- cascade`. Identidade é chave — `unique (kind, value)`. Uma identidade
-- órfã envenenaria o índice: o mesmo telefone nunca mais poderia ser
-- ligado a um lead novo. Identidade pertence ao lead e vai com ele; o
-- fato (interação, evento) fica.
-- ============================================================

-- ── 1. Rótulos: quem era, quando o vínculo se perder ────────
-- Todos anuláveis e todos escritos por gatilho. Nenhum tem default.

alter table brain.leads          add column if not exists customer_label   text;
alter table brain.leads          add column if not exists owner_label      text;

alter table brain.identities     add column if not exists customer_label   text;
alter table brain.identities     add column if not exists lead_label       text;

alter table brain.interactions   add column if not exists customer_label   text;
alter table brain.interactions   add column if not exists lead_label       text;
alter table brain.interactions   add column if not exists actor_label      text;

alter table brain.opportunities  add column if not exists customer_label   text;
alter table brain.opportunities  add column if not exists lead_label       text;
alter table brain.opportunities  add column if not exists owner_label      text;
alter table brain.opportunities  add column if not exists created_by_label text;

alter table brain.tasks          add column if not exists customer_label   text;
alter table brain.tasks          add column if not exists lead_label       text;
alter table brain.tasks          add column if not exists assignee_label   text;
alter table brain.tasks          add column if not exists created_by_label text;

alter table brain.events         add column if not exists actor_label      text;

comment on column brain.leads.customer_label is
  'Nome do cliente no momento do vínculo. Sobrevive à exclusão física do cliente — é o que resta da conversão.';
comment on column brain.events.actor_label is
  'Nome de quem disparou o evento. Sobrevive à exclusão do perfil: o evento continua sabendo de quem foi.';

-- ── 2. Os CHECKs passam a aceitar "teve sujeito" ────────────
-- Não é afrouxamento: rótulo só existe se um gatilho o copiou de um
-- registro real. Linha nova sem id nenhum continua recusada.

alter table brain.identities    drop constraint if exists chk_identity_has_owner;
alter table brain.identities    add  constraint chk_identity_has_owner
  check (lead_id is not null or customer_id is not null
      or lead_label is not null or customer_label is not null);

alter table brain.interactions  drop constraint if exists chk_interaction_has_subject;
alter table brain.interactions  add  constraint chk_interaction_has_subject
  check (lead_id is not null or customer_id is not null
      or lead_label is not null or customer_label is not null);

alter table brain.opportunities drop constraint if exists chk_opportunity_has_subject;
alter table brain.opportunities add  constraint chk_opportunity_has_subject
  check (lead_id is not null or customer_id is not null
      or lead_label is not null or customer_label is not null);

-- ── 3. O fato sobrevive ao lead ─────────────────────────────
-- Interação e tarefa são acontecimentos: uma ligação que houve não
-- deixa de ter havido porque o cadastro do lead foi removido. Passam a
-- `set null` + rótulo. (`identities.lead_id` fica em cascade — ver o
-- cabeçalho.)

alter table brain.interactions drop constraint if exists interactions_lead_id_fkey;
alter table brain.interactions add  constraint interactions_lead_id_fkey
  foreign key (lead_id) references brain.leads(id) on delete set null;

alter table brain.tasks drop constraint if exists tasks_lead_id_fkey;
alter table brain.tasks add  constraint tasks_lead_id_fkey
  foreign key (lead_id) references brain.leads(id) on delete set null;

alter table brain.tasks drop constraint if exists tasks_opportunity_id_fkey;
alter table brain.tasks add  constraint tasks_opportunity_id_fkey
  foreign key (opportunity_id) references brain.opportunities(id) on delete set null;

-- ── 4. "O perfil sumiu mesmo?" ──────────────────────────────
-- `security definer` de propósito: se a resposta dependesse do RLS de
-- quem pergunta, esconder um perfil viraria licença para apagar autoria.

create or replace function brain.profile_missing(p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_id is not null
     and not exists (select 1 from public.profiles p where p.id = p_id);
$$;

revoke execute on function brain.profile_missing(uuid) from public, anon;
grant  execute on function brain.profile_missing(uuid) to authenticated, service_role;

comment on function brain.profile_missing(uuid) is
  'Verdadeiro quando o perfil nao existe mais. Unica porta pela qual uma autoria pode virar nula.';

-- ── 5. Autoria: só some quando o autor sumiu ────────────────
-- `check_links()` restaurava `created_by`/`actor_id` sem condição, o que
-- desfazia o `set null` da FK e derrubava a exclusão do perfil. Agora a
-- restauração continua para TODA troca — menos a única transição
-- legítima: virar nulo porque o perfil não existe mais.

create or replace function brain.keep_authorship(p_new uuid, p_old uuid)
returns uuid language sql immutable security invoker set search_path = '' as $$
  select case
    when p_new is not distinct from p_old then p_old
    when p_new is null and p_old is not null and brain.profile_missing(p_old) then null
    else p_old        -- qualquer outra troca é falsificação: ignora-se
  end;
$$;

revoke execute on function brain.keep_authorship(uuid, uuid) from public, anon;
grant  execute on function brain.keep_authorship(uuid, uuid) to authenticated, service_role;

-- ── 6. Os rótulos, carimbados por gatilho ───────────────────
-- `security definer` porque copiar um nome não é decisão de autorização:
-- se o rótulo dependesse do RLS de quem escreve, ele sairia vazio para
-- metade dos casos e a história se perderia em silêncio.
--
-- Regra em três linhas, igual nas cinco tabelas:
--   id preenchido          → rótulo = nome de verdade, agora
--   id nulo no INSERT      → rótulo nulo (não se inventa sujeito)
--   id nulo no UPDATE      → mantém o rótulo anterior (a FK acabou de
--                            limpar o vínculo; é exatamente esta a hora)

create or replace function brain.label_customer(p_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select c.name from public.customers c where c.id = p_id;
$$;

create or replace function brain.label_lead(p_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select l.name from brain.leads l where l.id = p_id;
$$;

create or replace function brain.label_profile(p_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(p.full_name, p.email) from public.profiles p where p.id = p_id;
$$;

revoke execute on function brain.label_customer(uuid) from public, anon, authenticated;
revoke execute on function brain.label_lead(uuid)     from public, anon, authenticated;
revoke execute on function brain.label_profile(uuid)  from public, anon, authenticated;
grant  execute on function brain.label_customer(uuid) to service_role;
grant  execute on function brain.label_lead(uuid)     to service_role;
grant  execute on function brain.label_profile(uuid)  to service_role;

create or replace function brain.stamp_labels()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_insert boolean := (tg_op = 'INSERT');
begin
  if tg_table_name = 'leads' then
    new.customer_label := case
      when new.customer_id is not null then brain.label_customer(new.customer_id)
      when v_insert                    then null
      else old.customer_label end;
    new.owner_label := case
      when new.owner_id is not null then brain.label_profile(new.owner_id)
      when v_insert                 then null
      else old.owner_label end;

  elsif tg_table_name = 'identities' then
    new.customer_label := case
      when new.customer_id is not null then brain.label_customer(new.customer_id)
      when v_insert                    then null
      else old.customer_label end;
    new.lead_label := case
      when new.lead_id is not null then brain.label_lead(new.lead_id)
      when v_insert                then null
      else old.lead_label end;

  elsif tg_table_name = 'interactions' then
    new.customer_label := case
      when new.customer_id is not null then brain.label_customer(new.customer_id)
      when v_insert                    then null
      else old.customer_label end;
    new.lead_label := case
      when new.lead_id is not null then brain.label_lead(new.lead_id)
      when v_insert                then null
      else old.lead_label end;
    new.actor_label := case
      when new.actor_id is not null then brain.label_profile(new.actor_id)
      when v_insert                 then null
      else old.actor_label end;

  elsif tg_table_name = 'opportunities' then
    new.customer_label := case
      when new.customer_id is not null then brain.label_customer(new.customer_id)
      when v_insert                    then null
      else old.customer_label end;
    new.lead_label := case
      when new.lead_id is not null then brain.label_lead(new.lead_id)
      when v_insert                then null
      else old.lead_label end;
    new.owner_label := case
      when new.owner_id is not null then brain.label_profile(new.owner_id)
      when v_insert                 then null
      else old.owner_label end;
    new.created_by_label := case
      when new.created_by is not null then brain.label_profile(new.created_by)
      when v_insert                   then null
      else old.created_by_label end;

  elsif tg_table_name = 'tasks' then
    new.customer_label := case
      when new.customer_id is not null then brain.label_customer(new.customer_id)
      when v_insert                    then null
      else old.customer_label end;
    new.lead_label := case
      when new.lead_id is not null then brain.label_lead(new.lead_id)
      when v_insert                then null
      else old.lead_label end;
    new.assignee_label := case
      when new.assignee_id is not null then brain.label_profile(new.assignee_id)
      when v_insert                    then null
      else old.assignee_label end;
    new.created_by_label := case
      when new.created_by is not null then brain.label_profile(new.created_by)
      when v_insert                   then null
      else old.created_by_label end;
  end if;

  return new;
end;
$$;

revoke execute on function brain.stamp_labels() from public, anon, authenticated;

-- Os nomes têm `b_` porque a ordem de disparo é alfabética: primeiro
-- `_a_links` (autorização e autoria), depois o carimbo, que copia o
-- valor já decidido.
drop trigger if exists trg_leads_b_labels         on brain.leads;
create trigger trg_leads_b_labels         before insert or update on brain.leads
  for each row execute function brain.stamp_labels();

drop trigger if exists trg_identities_b_labels    on brain.identities;
create trigger trg_identities_b_labels    before insert or update on brain.identities
  for each row execute function brain.stamp_labels();

drop trigger if exists trg_interactions_b_labels  on brain.interactions;
create trigger trg_interactions_b_labels  before insert or update on brain.interactions
  for each row execute function brain.stamp_labels();

drop trigger if exists trg_opportunities_b_labels on brain.opportunities;
create trigger trg_opportunities_b_labels before insert or update on brain.opportunities
  for each row execute function brain.stamp_labels();

drop trigger if exists trg_tasks_b_labels         on brain.tasks;
create trigger trg_tasks_b_labels         before insert or update on brain.tasks
  for each row execute function brain.stamp_labels();

-- ── 7. `check_links()`: a única mudança é a autoria ─────────
-- Texto integral da versão de 20260911130000, trocando as três
-- atribuições cruas de autoria por `keep_authorship()`.

create or replace function brain.check_links()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_row jsonb := to_jsonb(new);
  v_lead uuid := (v_row ->> 'lead_id')::uuid;
  v_opp  uuid := (v_row ->> 'opportunity_id')::uuid;
  v_cust uuid := (v_row ->> 'customer_id')::uuid;
  v_quote uuid := (v_row ->> 'quote_id')::uuid;
  v_order uuid := (v_row ->> 'order_id')::uuid;
begin
  if tg_op = 'INSERT' then
    if tg_table_name in ('opportunities', 'tasks') and v_uid is not null then
      new.created_by := v_uid;
      new.updated_by := v_uid;
    elsif tg_table_name = 'interactions' and v_uid is not null then
      new.actor_id := v_uid;
    end if;
  elsif tg_table_name in ('opportunities', 'tasks') then
    -- A autoria não se troca. A ÚNICA transição aceita é virar nula
    -- porque o perfil do autor deixou de existir — é assim que a FK
    -- `on delete set null` consegue limpar sem derrubar a exclusão.
    new.created_by := brain.keep_authorship(new.created_by, old.created_by);
    new.created_at := old.created_at;
    if v_uid is not null then new.updated_by := v_uid; end if;
  elsif tg_table_name = 'interactions' then
    new.actor_id := brain.keep_authorship(new.actor_id, old.actor_id);
  end if;

  if brain.is_privileged() then
    return new;
  end if;

  if v_lead is not null and not brain.can_see_lead(v_lead) then
    raise exception 'Lead fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if tg_table_name <> 'opportunities' and v_opp is not null and not brain.can_see_opportunity(v_opp) then
    raise exception 'Oportunidade fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_cust is not null and not exists (select 1 from public.customers c where c.id = v_cust) then
    raise exception 'Cliente fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_quote is not null and not exists (select 1 from public.quotes q where q.id = v_quote) then
    raise exception 'Orcamento fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if v_order is not null and not exists (select 1 from public.orders o where o.id = v_order) then
    raise exception 'Pedido fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  if tg_table_name in ('tasks', 'interactions') and v_lead is not null and v_opp is not null
     and not exists (select 1 from brain.opportunities o where o.id = v_opp and o.lead_id = v_lead) then
    raise exception 'Oportunidade nao pertence a este lead' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- ── 8. `protect_event()`: o evento continua imutável ────────
-- Duas mudanças, ambas estreitas:
--   · `actor_label` entra na lista de imutáveis — o nome de quem fez
--     não se reescreve;
--   · `actor_id` pode virar nulo, e SÓ isso, e SÓ quando o perfil
--     sumiu. Trocar por outro perfil continua recusado.

create or replace function brain.protect_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'O barramento nao se esvazia. Evento e fato: no maximo marca-se como ignorado.'
      using errcode = 'restrict_violation';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Evento nao se apaga. E fato: no maximo marca-se como ignorado (processing = skipped).'
      using errcode = 'restrict_violation';
  end if;

  if new.actor_id is distinct from old.actor_id then
    if new.actor_id is null and old.actor_id is not null and brain.profile_missing(old.actor_id) then
      null;   -- o perfil foi excluido; o vinculo cai, o `actor_label` fica
    else
      raise exception 'O autor do evento nao se troca.'
        using errcode = 'restrict_violation';
    end if;
  end if;

  if new.event_name     is distinct from old.event_name
  or new.event_version  is distinct from old.event_version
  or new.source         is distinct from old.source
  or new.external_id    is distinct from old.external_id
  or new.occurred_at    is distinct from old.occurred_at
  or new.received_at    is distinct from old.received_at
  or new.payload        is distinct from old.payload
  or new.session_id     is distinct from old.session_id
  or new.visitor_id     is distinct from old.visitor_id
  or new.actor_label    is distinct from old.actor_label then
    raise exception 'Evento e imutavel; so o processamento e os vinculos (lead, cliente, oportunidade) podem ser preenchidos depois.'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

-- O `actor_label` do evento é carimbado na entrada e nunca mais muda.
create or replace function brain.stamp_event_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.actor_label := case
    when new.actor_id is not null then brain.label_profile(new.actor_id)
    else null end;
  return new;
end;
$$;

revoke execute on function brain.stamp_event_actor() from public, anon, authenticated;

drop trigger if exists trg_events_a_actor on brain.events;
create trigger trg_events_a_actor before insert on brain.events
  for each row execute function brain.stamp_event_actor();

-- ── 9. Rótulos das linhas que já existem ────────────────────
-- Em produção o BRAIN ainda não foi aplicado, então isto roda em cima
-- de tabelas vazias. Em qualquer outro banco, preenche o que já houver
-- sem tocar em mais nada.

update brain.leads         set customer_label = brain.label_customer(customer_id) where customer_id is not null and customer_label is null;
update brain.leads         set owner_label    = brain.label_profile(owner_id)     where owner_id    is not null and owner_label    is null;
update brain.identities    set customer_label = brain.label_customer(customer_id) where customer_id is not null and customer_label is null;
update brain.identities    set lead_label     = brain.label_lead(lead_id)         where lead_id     is not null and lead_label     is null;
update brain.interactions  set customer_label = brain.label_customer(customer_id) where customer_id is not null and customer_label is null;
update brain.interactions  set lead_label     = brain.label_lead(lead_id)         where lead_id     is not null and lead_label     is null;
update brain.interactions  set actor_label    = brain.label_profile(actor_id)     where actor_id    is not null and actor_label    is null;
update brain.opportunities set customer_label = brain.label_customer(customer_id) where customer_id is not null and customer_label is null;
update brain.opportunities set lead_label     = brain.label_lead(lead_id)         where lead_id     is not null and lead_label     is null;
update brain.opportunities set owner_label    = brain.label_profile(owner_id)     where owner_id    is not null and owner_label    is null;
update brain.opportunities set created_by_label = brain.label_profile(created_by) where created_by  is not null and created_by_label is null;
update brain.tasks         set customer_label = brain.label_customer(customer_id) where customer_id is not null and customer_label is null;
update brain.tasks         set lead_label     = brain.label_lead(lead_id)         where lead_id     is not null and lead_label     is null;
update brain.tasks         set assignee_label = brain.label_profile(assignee_id)  where assignee_id is not null and assignee_label is null;
update brain.tasks         set created_by_label = brain.label_profile(created_by) where created_by  is not null and created_by_label is null;

-- `brain.events` não aceita UPDATE de `actor_label` por gatilho próprio;
-- o retrato dos eventos antigos é feito com o gatilho desligado, porque
-- é migração de estrutura, não escrita de usuário.
alter table brain.events disable trigger trg_events_immutable;
update brain.events set actor_label = brain.label_profile(actor_id)
 where actor_id is not null and actor_label is null;
alter table brain.events enable trigger trg_events_immutable;

-- ── 10. Índices dos rótulos não existem de propósito ────────
-- Rótulo é memória, não caminho de consulta: ninguém procura lead por
-- nome de cliente excluído. Índice aqui só custaria escrita.


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911150000_brain_pontes.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — as pontes do ERP, com a garantia que elas de fato dão
--
-- O relatório de 11/09 afirmou que `exception when others` protege a
-- venda de QUALQUER falha do BRAIN. Está errado, e a prova é de uma
-- linha (supabase/db-tests/28_brain_pontes.sql, PT1):
--
--   set statement_timeout = '250ms';
--   do $$ begin
--     begin perform pg_sleep(2);
--     exception when others then raise notice 'capturado'; end;
--   end $$;
--   → ERROR: canceling statement due to statement timeout
--
-- O manual do PostgreSQL diz literalmente que `OTHERS` casa com tudo
-- MENOS `query_canceled` e `assert_failure`. E `statement_timeout` levanta
-- justamente `query_canceled`.
--
-- Capturar `query_canceled` de propósito seria pior do que o problema: o
-- pedido de cancelamento continua pendente e volta no próximo ponto de
-- interrupção, e engolir um `statement_timeout` quebra o limite que o
-- Supabase impõe por papel. Então não se engole.
--
-- ── O QUE A PONTE GARANTE, sem retórica ─────────────────────
--
-- ISOLADO — o BRAIN falha, a venda é salva do mesmo jeito:
--   · qualquer erro SQL comum dentro do bloco protegido — unique, check,
--     FK, RLS, tipo, divisão por zero, deadlock detectado, disco cheio
--     numa tabela do BRAIN;
--   · `lock_timeout` estourado esperando uma linha do BRAIN. Medido, não
--     suposto: `lock_timeout` levanta `lock_not_available` (55P03), e
--     esse OTHERS captura. É o PT5 de pontes-concorrentes.sh.
--
-- NÃO ISOLADO — a transação comercial cai junto:
--   · `query_canceled` (57014): `statement_timeout` da sessão, ou alguém
--     cancelando a consulta. O Supabase põe 8s em `authenticated`, então
--     este caso é real, não teórico — PT5b;
--   · `assert_failure`;
--   · o que é FATAL e derruba a conexão (queda do servidor, fim do backend).
--
-- ── O QUE ESTA MIGRATION MUDA ───────────────────────────────
--
-- 1. Não sobra NENHUMA instrução fora do bloco protegido. Em
--    `on_order_change()` a releitura de `public.orders` estava fora dele:
--    um deadlock ali derrubava a venda por um motivo que era do BRAIN.
--    Agora o bloco começa na primeira instrução e termina na última.
--
-- 2. A janela de exposição ao cancelamento encolhe ao mínimo: a ponte
--    faz consultas com índice e nada mais.
--
-- 3. Existe como DESCOBRIR o que faltou. Quando a ponte falha ela só
--    escreve `warning` no log do Postgres — que ninguém lê. Agora
--    `brain.erp_events_faltando()` responde a pergunta certa ("que venda
--    não chegou no barramento?") e `brain.repor_eventos_erp()` repõe,
--    sem duplicar o que já existe.
--
-- ── O LIMITE QUE NÃO SE RESOLVE AQUI ────────────────────────
--
-- Isolamento absoluto exige que a ponte NÃO rode dentro da transação
-- comercial. A menor solução adequada é uma fila durável (`pgmq`, que o
-- projeto já tem disponível e desligado): o gatilho enfileira uma linha
-- e um processador publica depois, fora da transação. Isso é mudança de
-- arquitetura, fica proposta para a Fase 1.1 — e não se promete aqui o
-- que só ela entrega.
-- ============================================================

-- ── 1. Índices para a reconciliação ─────────────────────────
-- Sem eles, procurar "que pedido não tem evento" varre o barramento
-- inteiro. Parciais: só eventos do ERP interessam.

create index if not exists idx_events_erp_quote
  on brain.events ((payload ->> 'quote_id'), (payload ->> 'status'))
  where source = 'erp' and payload ? 'quote_id';

create index if not exists idx_events_erp_order
  on brain.events ((payload ->> 'order_id'), (payload ->> 'status'))
  where source = 'erp' and payload ? 'order_id';

-- ── 2. A ponte do orçamento ─────────────────────────────────

create or replace function brain.on_quote_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_lead  uuid;
  v_opp   uuid;
begin
  -- TUDO daqui para baixo está dentro do bloco protegido. Não sobra
  -- instrução nenhuma fora: erro do BRAIN não é motivo para perder um
  -- orçamento, nem quando acontece na primeira linha.
  begin
    if tg_op = 'INSERT' then
      v_event := 'quote.created';
    elsif new.status is distinct from old.status then
      v_event := 'quote.' || new.status::text;
    else
      return null;
    end if;

    perform pg_catalog.set_config('brain.internal', 'on', true);

    select id, lead_id into v_opp, v_lead from brain.opportunities
     where quote_id = new.id order by created_at limit 1;
    if v_lead is null then
      select id into v_lead from brain.leads
       where customer_id = new.customer_id and merged_into_lead_id is null
       order by created_at limit 1;
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('quote_id', new.id, 'number', new.number, 'status', new.status,
                         'total', new.total, 'owner_id', new.owner_id),
      'quote:' || new.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson', v_lead, new.customer_id, v_opp, null, null, null, null, 1, '{}'::jsonb);

    if v_opp is not null and new.status = 'approved' then
      update brain.opportunities set stage = 'negotiation'
       where id = v_opp and stage in ('prospecting', 'qualified', 'proposal');
    elsif v_opp is not null and new.status = 'sent' then
      update brain.opportunities set stage = 'proposal'
       where id = v_opp and stage in ('prospecting', 'qualified');
    end if;

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    -- `OTHERS` não cobre cancelamento nem timeout — ver o cabeçalho.
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning '[brain-ponte] orcamento % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

-- ── 3. A ponte do pedido ────────────────────────────────────

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_order public.orders%rowtype;
  r       record;
begin
  begin
    -- No INSERT este gatilho é DEFERRED: dispara no commit, quando os
    -- itens já entraram e o total já foi recalculado. A releitura vive
    -- AQUI DENTRO — antes ela estava fora do bloco, e um deadlock nela
    -- derrubava a venda.
    select * into v_order from public.orders where id = new.id;
    if not found then return null; end if;

    if tg_op = 'INSERT' then
      v_event := 'order.created';
    elsif new.status is distinct from old.status then
      v_event := 'order.' || new.status::text;
    else
      return null;
    end if;

    perform pg_catalog.set_config('brain.internal', 'on', true);

    if tg_op = 'INSERT' and v_order.quote_id is not null then
      for r in
        update brain.opportunities
           set order_id = v_order.id, stage = 'won',
               customer_id = coalesce(customer_id, v_order.customer_id)
         where quote_id = v_order.quote_id and stage not in ('won', 'lost')
         returning id, lead_id
      loop
        if r.lead_id is not null then
          update brain.leads
             set status = 'converted',
                 converted_at = coalesce(converted_at, now()),
                 customer_id = coalesce(customer_id, v_order.customer_id)
           where id = r.lead_id;
        end if;
      end loop;
    elsif v_event = 'order.cancelled' then
      update brain.opportunities set stage = 'negotiation'
       where order_id = v_order.id and stage = 'won';
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('order_id', v_order.id, 'number', v_order.number, 'status', v_order.status,
                         'total', v_order.total, 'quote_id', v_order.quote_id, 'owner_id', v_order.owner_id),
      'order:' || v_order.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson',
      (select o.lead_id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      v_order.customer_id,
      (select o.id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      null, null, null, null, 1, '{}'::jsonb);

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning '[brain-ponte] pedido % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

-- ── 4. Descobrir o que a ponte deixou passar ────────────────
-- A pergunta prática é "que venda não chegou ao barramento?". A resposta
-- não depende da chave de deduplicação (que carrega o txid e por isso
-- não se recalcula): compara-se o ESTADO ATUAL da venda com o que existe
-- publicado para ela.

create or replace function brain.erp_events_faltando()
returns table (
  entidade      text,
  id            uuid,
  numero        text,
  status        text,
  atualizado_em timestamptz
)
language sql stable security definer set search_path = '' as $$
  select 'quote'::text, q.id, q.number::text, q.status::text, q.updated_at
    from public.quotes q
   where q.deleted_at is null
     and (select public.is_admin())
     and not exists (
       select 1 from brain.events e
        where e.source = 'erp'
          and e.payload ->> 'quote_id' = q.id::text
          and e.payload ->> 'status'   = q.status::text)
  union all
  select 'order'::text, o.id, o.number::text, o.status::text, o.updated_at
    from public.orders o
   where o.deleted_at is null
     and (select public.is_admin())
     and not exists (
       select 1 from brain.events e
        where e.source = 'erp'
          and e.payload ->> 'order_id' = o.id::text
          and e.payload ->> 'status'   = o.status::text)
  order by 5 desc;
$$;

revoke execute on function brain.erp_events_faltando() from public, anon;
grant  execute on function brain.erp_events_faltando() to authenticated, service_role;

comment on function brain.erp_events_faltando() is
  'Orcamentos e pedidos cujo estado atual nunca foi publicado no barramento. E o antidoto do `raise warning`, que so vive no log do Postgres. So administrador enxerga.';

-- ── 5. Repor o que faltou ───────────────────────────────────
-- Idempotente por construção: republica só o que `erp_events_faltando()`
-- ainda acusa, e cada evento reposto carrega `reposto_em` no metadata —
-- reposição é fato administrativo e fica registrada como tal.

create or replace function brain.repor_eventos_erp(p_limite integer default 500)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  r      record;
  v_n    integer := 0;
begin
  if not (select public.is_admin()) then
    raise exception 'Somente administrador repoe evento do barramento'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite de reposicao fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  for r in select * from brain.erp_events_faltando() limit p_limite loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        case when r.status = 'draft' then 'quote.created' else 'quote.' || r.status end,
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reposicao:' || r.atualizado_em::text,
        r.atualizado_em, 'salesperson', null,
        (select q.customer_id from public.quotes q where q.id = r.id),
        null, null, null, null, null, 1,
        jsonb_build_object('reposto_em', now(), 'reposto_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        case when r.status = 'draft' then 'order.created' else 'order.' || r.status end,
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reposicao:' || r.atualizado_em::text,
        r.atualizado_em, 'salesperson', null,
        (select o.customer_id from public.orders o where o.id = r.id),
        null, null, null, null, null, 1,
        jsonb_build_object('reposto_em', now(), 'reposto_por', (select auth.uid())));
    end if;
    v_n := v_n + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);
  return v_n;
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.repor_eventos_erp(integer) from public, anon;
grant  execute on function brain.repor_eventos_erp(integer) to authenticated, service_role;

comment on function brain.repor_eventos_erp(integer) is
  'Republica no barramento o estado atual das vendas que `erp_events_faltando()` acusa. Idempotente: rodar duas vezes nao duplica.';


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911160000_brain_volatilidade.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — `keep_authorship` não é IMMUTABLE
--
-- O defeito: `brain.keep_authorship()` foi declarada `immutable` em
-- 20260911140000. Ela não é: chama `brain.profile_missing()`, que LÊ
-- `public.profiles`. Uma função que lê tabela é `stable`, no máximo.
--
-- Por que isso importa, medido e não suposto
-- (supabase/db-tests/29_brain_volatilidade.sql, VL1):
--
--   insert  perfil
--   prepare fixa as select brain.keep_authorship(null::uuid, '<perfil>'::uuid);
--   execute fixa;        -- devolve o uuid  (certo: o perfil existe)
--   ... 4 execuções, o plano genérico entra ...
--   delete  perfil
--   execute fixa;        -- AINDA devolve o uuid  ← ERRADO
--   select brain.profile_missing('<perfil>');  -- t: o perfil sumiu
--
-- `immutable` autoriza o planejador a AVALIAR a chamada com argumento
-- constante e congelar o resultado dentro do plano. O plano em cache
-- passa a mentir sobre um dado que mudou.
--
-- A consequência prática é exatamente o defeito que 20260911140000 veio
-- consertar: `check_links()` chamaria `keep_authorship` e receberia o
-- valor velho, restaurando a autoria que a FK acabou de anular — e a
-- exclusão do perfil voltaria a falhar. O gatilho passa parâmetros, não
-- constantes, o que esconde o problema no caminho comum; mas a
-- declaração continua errada, e o dia em que alguém chamar a função com
-- constante — numa view, num `check`, num índice de expressão — o erro
-- aparece calado.
--
-- A correção é uma palavra: `stable`.
-- ============================================================

-- `create or replace` não muda volatilidade de uma função SQL já
-- existente? Muda — mas só se a nova definição a declarar. Aqui declara.
create or replace function brain.keep_authorship(p_new uuid, p_old uuid)
returns uuid language sql stable security invoker set search_path = '' as $$
  select case
    when p_new is not distinct from p_old then p_old
    when p_new is null and p_old is not null and brain.profile_missing(p_old) then null
    else p_old        -- qualquer outra troca é falsificação: ignora-se
  end;
$$;

revoke execute on function brain.keep_authorship(uuid, uuid) from public, anon;
grant  execute on function brain.keep_authorship(uuid, uuid) to authenticated, service_role;

-- Guarda: nenhuma função do BRAIN que leia tabela pode voltar a ser
-- `immutable`. As únicas imutáveis legítimas são as que só fazem conta
-- sobre o argumento — normalização de telefone, de identidade.
do $$
declare v_errada text;
begin
  select string_agg(p.proname, ', ') into v_errada
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain'
     and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  if v_errada is not null then
    raise exception 'Funcao(oes) do brain declarada(s) IMMUTABLE sem ser: %', v_errada;
  end if;
end
$$;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911170000_brain_reconciliacao.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — reconciliação de verdade: evento E estado comercial
--
-- O defeito: `brain.repor_eventos_erp()` republicava o evento que a
-- ponte perdeu e parava aí. Mas a ponte não publica só evento — ela
-- também move o estágio da oportunidade, marca a venda como ganha e
-- converte o lead. Quando ela falha, TUDO isso deixa de acontecer, e
-- repor só o evento devolvia um barramento arrumado em cima de um CRM
-- errado.
--
-- Pior: "zero eventos faltantes" virava critério de sucesso, e era um
-- critério que podia estar satisfeito com a oportunidade parada em
-- `prospecting` e o lead nunca convertido.
--
-- ── O QUE ENTRA ─────────────────────────────────────────────
--
-- `brain.divergencias_erp()` — o relatório. Uma linha por desacordo
-- entre a venda no ERP e o que o BRAIN sabe dela. Seis tipos:
--
--   evento_ausente        o estado atual da venda nunca foi publicado
--   estagio_atrasado      orçamento enviado/aprovado e a oportunidade
--                         ficou para trás
--   venda_nao_ganha       pedido vivo e a oportunidade não está `won`
--   venda_desfeita        pedido cancelado e a oportunidade ainda `won`
--   pedido_nao_ligado     pedido vivo e a oportunidade sem `order_id`
--   lead_nao_convertido   pedido vivo e o lead do negócio não convertido
--
-- `brain.reconciliar_erp()` — conserta o que pode e devolve a contagem
-- por tipo. É ela que passa a ser chamada; `repor_eventos_erp()` fica
-- como apelido, para não quebrar quem já a conhece.
--
-- ── O QUE ELA NÃO ATROPELA ──────────────────────────────────
--
-- · Oportunidade em `lost` fica em `lost`. Alguém decidiu isso depois, e
--   a reconciliação não desfaz decisão humana — é a mesma regra que a
--   ponte já segue (`stage not in ('won','lost')`).
-- · Pedido cancelado devolve a oportunidade para `negotiation`, nunca
--   para `lost`: quem perde a venda decide, não o script.
-- · Lead convertido continua convertido mesmo se o pedido for cancelado.
--   É a regra da ponte, escrita lá: o cliente existe; o que não existe
--   mais é esta venda.
-- · Estágio NUNCA anda para trás por conta do orçamento. Se a
--   oportunidade já está em `negotiation` e o orçamento só foi enviado,
--   não se rebaixa para `proposal`.
--
-- ── IDEMPOTÊNCIA ────────────────────────────────────────────
--
-- Rodar duas vezes dá o mesmo resultado, e a segunda não faz nada: toda
-- escrita é condicionada ao estado errado. A suíte mede isso pelo md5
-- do estado do CRM antes e depois da segunda execução (RC7).
-- ============================================================

-- ── 1. O relatório de divergências ──────────────────────────

create or replace function brain.divergencias_erp()
returns table (
  tipo          text,
  entidade      text,
  id            uuid,
  numero        text,
  situacao      text,
  detalhe       text
)
language sql stable security definer set search_path = '' as $$
  with permitido as (select (select public.is_admin()) as pode),

  -- Orçamento cujo estado atual nunca foi publicado.
  ev_quote as (
    select 'evento_ausente'::text, 'quote'::text, q.id, q.number::text, q.status::text,
           'nenhum evento do ERP com status ' || q.status::text
      from public.quotes q, permitido p
     where p.pode and q.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'quote_id' = q.id::text
                          and e.payload ->> 'status'   = q.status::text)
  ),
  ev_order as (
    select 'evento_ausente'::text, 'order'::text, o.id, o.number::text, o.status::text,
           'nenhum evento do ERP com status ' || o.status::text
      from public.orders o, permitido p
     where p.pode and o.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'order_id' = o.id::text
                          and e.payload ->> 'status'   = o.status::text)
  ),

  -- Orçamento andou e a oportunidade ficou para trás.
  estagio as (
    select 'estagio_atrasado'::text, 'opportunity'::text, op.id, q.number::text, op.stage::text,
           'orcamento em ' || q.status::text || ' e oportunidade em ' || op.stage::text
      from brain.opportunities op
      join public.quotes q on q.id = op.quote_id, permitido p
     where p.pode and q.deleted_at is null
       and op.stage not in ('won', 'lost')
       and ((q.status = 'approved' and op.stage in ('prospecting', 'qualified', 'proposal'))
         or (q.status = 'sent'     and op.stage in ('prospecting', 'qualified')))
  ),

  -- Pedido vivo e a oportunidade não ganhou.
  nao_ganha as (
    select 'venda_nao_ganha'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido em ' || o.status::text || ' e oportunidade em ' || op.stage::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id)), permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.stage <> 'won' and op.stage <> 'lost'
  ),

  -- Pedido cancelado e a oportunidade continua ganha.
  desfeita as (
    select 'venda_desfeita'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido cancelado e oportunidade ainda em won'
      from public.orders o
      join brain.opportunities op on op.order_id = o.id, permitido p
     where p.pode and o.status = 'cancelled' and op.stage = 'won'
  ),

  -- Pedido vivo, oportunidade ganha, mas sem o vínculo.
  sem_vinculo as (
    select 'pedido_nao_ligado'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'oportunidade sem order_id apontando para o pedido'
      from public.orders o
      join brain.opportunities op on op.quote_id = o.quote_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.order_id is null and op.stage <> 'lost'
  ),

  -- Pedido vivo e o lead do negócio não foi convertido.
  lead_parado as (
    select 'lead_nao_convertido'::text, 'lead'::text, l.id, o.number::text, l.status::text,
           'pedido vivo e lead em ' || l.status::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
      join brain.leads l on l.id = op.lead_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and l.status <> 'converted' and l.status <> 'lost'
       and op.stage <> 'lost'
  )

  select * from ev_quote
  union all select * from ev_order
  union all select * from estagio
  union all select * from nao_ganha
  union all select * from desfeita
  union all select * from sem_vinculo
  union all select * from lead_parado;
$$;

revoke execute on function brain.divergencias_erp() from public, anon;
grant  execute on function brain.divergencias_erp() to authenticated, service_role;

comment on function brain.divergencias_erp() is
  'Uma linha por desacordo entre a venda no ERP e o que o BRAIN sabe dela. Vazio e o criterio de sucesso da reconciliacao — "zero eventos faltantes" sozinho nao era.';

-- A função antiga continua existindo e agora é uma vista estreita do
-- relatório novo: só os eventos ausentes.
create or replace function brain.erp_events_faltando()
returns table (
  entidade      text,
  id            uuid,
  numero        text,
  status        text,
  atualizado_em timestamptz
)
language sql stable security definer set search_path = '' as $$
  select d.entidade, d.id, d.numero, d.situacao,
         coalesce((select q.updated_at from public.quotes q where q.id = d.id),
                  (select o.updated_at from public.orders o where o.id = d.id))
    from brain.divergencias_erp() d
   where d.tipo = 'evento_ausente'
   order by 5 desc nulls last;
$$;

revoke execute on function brain.erp_events_faltando() from public, anon;
grant  execute on function brain.erp_events_faltando() to authenticated, service_role;

-- ── 2. A reconciliação ──────────────────────────────────────

create or replace function brain.reconciliar_erp(p_limite integer default 500)
returns table (
  tipo       text,
  corrigidas integer
)
language plpgsql security definer set search_path = '' as $$
declare
  r          record;
  v_eventos  int := 0;
  v_estagio  int := 0;
  v_ganhas   int := 0;
  v_desfeitas int := 0;
  v_ligadas  int := 0;
  v_leads    int := 0;
  v_n        int;
begin
  if not (select public.is_admin()) then
    raise exception 'Somente administrador reconcilia o BRAIN com o ERP'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  -- ── 2.1 Pedido cancelado desfaz a venda ganha ─────────────
  -- Vem PRIMEIRO: assim um pedido cancelado nunca é "ganho" por um passo
  -- posterior e depois desfeito — a ordem evita o vaivém.
  update brain.opportunities op
     set stage = 'negotiation'
    from public.orders o
   where op.order_id = o.id and o.status = 'cancelled' and op.stage = 'won';
  get diagnostics v_desfeitas = row_count;

  -- ── 2.2 Pedido vivo: liga, ganha e converte ───────────────
  for r in
    select o.id as pedido, o.customer_id, op.id as oportunidade, op.lead_id
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
     where o.deleted_at is null and o.status <> 'cancelled' and op.stage <> 'lost'
     order by o.created_at
     limit p_limite
  loop
    update brain.opportunities
       set order_id = r.pedido
     where id = r.oportunidade and order_id is null;
    get diagnostics v_n = row_count;  v_ligadas := v_ligadas + v_n;

    update brain.opportunities
       set stage = 'won',
           customer_id = coalesce(customer_id, r.customer_id)
     where id = r.oportunidade and stage <> 'won';
    get diagnostics v_n = row_count;  v_ganhas := v_ganhas + v_n;

    if r.lead_id is not null then
      update brain.leads
         set status = 'converted',
             converted_at = coalesce(converted_at, now()),
             customer_id = coalesce(customer_id, r.customer_id)
       where id = r.lead_id and status not in ('converted', 'lost');
      get diagnostics v_n = row_count;  v_leads := v_leads + v_n;
    end if;
  end loop;

  -- ── 2.3 Estágio atrasado pelo orçamento ───────────────────
  -- Só avança. `greatest` não existe para enum, então são dois UPDATEs
  -- com a condição escrita por extenso — e a condição é justamente a
  -- que impede voltar atrás.
  update brain.opportunities op
     set stage = 'negotiation'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'approved'
     and op.stage in ('prospecting', 'qualified', 'proposal');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  update brain.opportunities op
     set stage = 'proposal'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'sent'
     and op.stage in ('prospecting', 'qualified');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  -- ── 2.4 Os eventos que faltaram ───────────────────────────
  for r in
    select d.entidade, d.id, d.situacao
      from brain.divergencias_erp() d
     where d.tipo = 'evento_ausente'
     limit p_limite
  loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        case when r.situacao = 'draft' then 'quote.created' else 'quote.' || r.situacao end,
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reconciliacao:' || r.situacao,
        (select q.updated_at from public.quotes q where q.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        (select q.customer_id from public.quotes q where q.id = r.id),
        (select op.id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        case when r.situacao = 'draft' then 'order.created' else 'order.' || r.situacao end,
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reconciliacao:' || r.situacao,
        (select o.updated_at from public.orders o where o.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        (select o.customer_id from public.orders o where o.id = r.id),
        (select op.id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    end if;
    v_eventos := v_eventos + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);

  return query
    select * from (values
      ('evento_ausente',      v_eventos),
      ('estagio_atrasado',    v_estagio),
      ('venda_nao_ganha',     v_ganhas),
      ('venda_desfeita',      v_desfeitas),
      ('pedido_nao_ligado',   v_ligadas),
      ('lead_nao_convertido', v_leads)
    ) as t(tipo, corrigidas);
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.reconciliar_erp(integer) from public, anon;
grant  execute on function brain.reconciliar_erp(integer) to authenticated, service_role;

comment on function brain.reconciliar_erp(integer) is
  'Poe o BRAIN de acordo com o ERP: evento, estagio, venda ganha, venda desfeita, vinculo do pedido e conversao do lead. Nao atropela decisao humana (lost fica lost) e rodar duas vezes nao muda nada.';

-- `repor_eventos_erp()` continua existindo e agora chama a reconciliação
-- inteira — quem só repunha evento passa a arrumar o CRM junto.
create or replace function brain.repor_eventos_erp(p_limite integer default 500)
returns integer language sql security definer set search_path = '' as $$
  select coalesce(sum(corrigidas), 0)::integer from brain.reconciliar_erp(p_limite);
$$;

revoke execute on function brain.repor_eventos_erp(integer) from public, anon;
grant  execute on function brain.repor_eventos_erp(integer) to authenticated, service_role;

comment on function brain.repor_eventos_erp(integer) is
  'Apelido de brain.reconciliar_erp(): devolve o total de correcoes. Mantido para nao quebrar quem ja o chamava.';

-- Índice do caminho que a reconciliação percorre.
create index if not exists idx_opportunities_quote_stage
  on brain.opportunities (quote_id, stage) where quote_id is not null;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911180000_brain_dependentes.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- `brain.dependentes_externos()` — quem, de fora do schema `brain`,
-- depende de alguma coisa dentro dele.
--
-- Existe porque a versão anterior olhava só `pg_class` e por isso enxergava
-- tabela e nada mais. View, chave estrangeira, policy, default de coluna e
-- função de corpo padrão ficavam invisíveis — e `drop schema … cascade`
-- levaria todas embora sem avisar.
--
-- ── O QUE ELA ENXERGA ───────────────────────────────────────
-- Tudo que o `pg_depend` registra, resolvendo o schema do DEPENDENTE por
-- `classid`: tabela e view (`pg_class`), regra de view (`pg_rewrite`),
-- função (`pg_proc`), tipo (`pg_type`), restrição (`pg_constraint`),
-- gatilho (`pg_trigger`), default de coluna (`pg_attrdef`) e policy
-- (`pg_policy`). Um `classid` que ela não conheça volta como
-- `(desconhecido)` e **conta como dependente** — na dúvida, barra.
--
-- ── O QUE ELA NÃO ENXERGA, e por quê ────────────────────────
-- Função de corpo CLÁSSICO (`as $$ … $$`) e função plpgsql NÃO registram
-- dependência nenhuma no catálogo: o corpo é texto, resolvido em tempo de
-- execução. Medido:
--
--   corpo clássico              → 0 linhas em pg_depend
--   corpo padrão (BEGIN ATOMIC) → 1 linha em pg_depend
--
-- Por isso existe a segunda peneira, `brain.funcoes_que_citam_brain()`:
-- varre o TEXTO de toda função fora do schema atrás de `brain.`. É
-- grosseira — pega menção em comentário — e é o que há. As duas juntas
-- cobrem o que o catálogo sabe e o que só o texto conta.
-- ============================================================

create or replace function brain.schema_do_objeto(p_classid oid, p_objid oid)
returns text language sql stable security definer set search_path = '' as $$
  select case p_classid
    when 'pg_catalog.pg_class'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = p_objid)
    when 'pg_catalog.pg_proc'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where p.oid = p_objid)
    when 'pg_catalog.pg_type'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace where t.oid = p_objid)
    when 'pg_catalog.pg_constraint'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_constraint c join pg_catalog.pg_namespace n on n.oid = c.connamespace where c.oid = p_objid)
    when 'pg_catalog.pg_trigger'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where t.oid = p_objid)
    when 'pg_catalog.pg_rewrite'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_rewrite r join pg_catalog.pg_class c on c.oid = r.ev_class
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where r.oid = p_objid)
    when 'pg_catalog.pg_attrdef'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_attrdef a join pg_catalog.pg_class c on c.oid = a.adrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where a.oid = p_objid)
    when 'pg_catalog.pg_policy'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid = p.polrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where p.oid = p_objid)
    when 'pg_catalog.pg_namespace'::pg_catalog.regclass then
      (select nspname from pg_catalog.pg_namespace where oid = p_objid)
    else null
  end;
$$;

create or replace function brain.dependentes_externos()
returns table (schema_dependente text, dependente text, tipo_dependencia "char")
language sql stable security definer set search_path = '' as $$
  select coalesce(brain.schema_do_objeto(d.classid, d.objid), '(desconhecido)'),
         pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid),
         d.deptype
    from pg_catalog.pg_depend d
   where d.refobjid in (
           select c.oid from pg_catalog.pg_class c where c.relnamespace = 'brain'::pg_catalog.regnamespace
           union all
           select p.oid from pg_catalog.pg_proc p where p.pronamespace = 'brain'::pg_catalog.regnamespace
           union all
           select t.oid from pg_catalog.pg_type t where t.typnamespace = 'brain'::pg_catalog.regnamespace
           union all
           select n.oid from pg_catalog.pg_namespace n where n.nspname = 'brain')
     and d.deptype in ('n', 'a')
     and coalesce(brain.schema_do_objeto(d.classid, d.objid), '(desconhecido)') is distinct from 'brain'
   group by 1, 2, 3;
$$;

create or replace function brain.funcoes_que_citam_brain()
returns table (funcao text, linguagem text)
language sql stable security definer set search_path = '' as $$
  select n.nspname || '.' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
         l.lanname::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    join pg_catalog.pg_language l on l.oid = p.prolang
   where n.nspname not in ('brain', 'pg_catalog', 'information_schema')
     and p.prosrc ~ '\mbrain\.';
$$;

revoke execute on function brain.schema_do_objeto(oid, oid)  from public, anon, authenticated;
revoke execute on function brain.dependentes_externos()      from public, anon;
revoke execute on function brain.funcoes_que_citam_brain()   from public, anon;
grant  execute on function brain.dependentes_externos()      to authenticated, service_role;
grant  execute on function brain.funcoes_que_citam_brain()   to authenticated, service_role;

comment on function brain.dependentes_externos() is
  'Objetos fora do schema brain que dependem de algo dentro dele, pelo catalogo. classid desconhecido conta como dependente — na duvida, barra.';
comment on function brain.funcoes_que_citam_brain() is
  'Segunda peneira: funcao fora do brain cujo TEXTO cita brain. — funcao de corpo classico e plpgsql nao registram dependencia no catalogo.';


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911190000_brain_janela.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — encolher a janela em que a ponte pode derrubar uma venda
--
-- O que está em jogo: `exception when others` NÃO captura
-- `query_canceled` (57014). Enquanto a ponte roda dentro da transação
-- comercial, um `statement_timeout` que estoure LÁ DENTRO derruba a
-- venda. Isso não some com esta migration — e não se promete que suma.
-- O que dá para fazer é encolher a janela, e é o que ela faz.
--
-- ── A MEDIDA ────────────────────────────────────────────────
--
-- A janela tem dois pedaços:
--
--   (a) o tempo que a ponte gasta fazendo o trabalho dela —
--       meia dúzia de consultas com índice;
--   (b) o tempo que ela passa ESPERANDO um bloqueio de linha, quando
--       outra transação está mexendo na mesma oportunidade.
--
-- (b) é o que dominava, e é justamente o pedaço perigoso: esperar não
-- consome nada, só relógio, e o relógio é o `statement_timeout` de 8s
-- que o Supabase põe em `authenticated`. Quem espera 8s num lock leva
-- 57014 — o código que escapa do `OTHERS`.
--
-- ── A CORREÇÃO ──────────────────────────────────────────────
--
-- `lock_timeout` local de 250ms dentro do bloco protegido. Espera de
-- bloqueio passa a levantar `lock_not_available` (55P03) — que o
-- `OTHERS` CAPTURA. O pedaço (b) sai da faixa perigosa e entra na faixa
-- isolada: a venda passa, o evento se perde, e
-- `brain.divergencias_erp()` acusa depois.
--
-- Medido em PT5 e PT5b: `lock_timeout` → 55P03, capturado, venda passa;
-- `statement_timeout` → 57014, escapa, venda cai. Esta migration faz o
-- caso comum cair sempre no primeiro.
--
-- O valor da sessão é salvo e devolvido nos dois caminhos — sucesso e
-- exceção. A ponte não deixa herança de configuração.
--
-- ── O QUE SOBRA ─────────────────────────────────────────────
--
-- Sobra (a): o tempo de execução da própria ponte. Se o
-- `statement_timeout` da venda estourar exatamente dentro desses
-- milissegundos, a venda cai. É risco residual declarado, com a medida
-- ao lado — ver o relatório, seção do acoplamento.
-- ============================================================

create or replace function brain.on_quote_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_lead  uuid;
  v_opp   uuid;
  v_lock  text;
begin
  begin
    if tg_op = 'INSERT' then
      v_event := 'quote.created';
    elsif new.status is distinct from old.status then
      v_event := 'quote.' || new.status::text;
    else
      return null;
    end if;

    -- Esperar bloqueio é o pedaço perigoso: 250ms e desiste, no codigo
    -- que o OTHERS captura. O valor da sessao volta ao que era.
    v_lock := pg_catalog.current_setting('lock_timeout', true);
    perform pg_catalog.set_config('lock_timeout', '250ms', true);
    perform pg_catalog.set_config('brain.internal', 'on', true);

    select id, lead_id into v_opp, v_lead from brain.opportunities
     where quote_id = new.id order by created_at limit 1;
    if v_lead is null then
      select id into v_lead from brain.leads
       where customer_id = new.customer_id and merged_into_lead_id is null
       order by created_at limit 1;
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('quote_id', new.id, 'number', new.number, 'status', new.status,
                         'total', new.total, 'owner_id', new.owner_id),
      'quote:' || new.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson', v_lead, new.customer_id, v_opp, null, null, null, null, 1, '{}'::jsonb);

    if v_opp is not null and new.status = 'approved' then
      update brain.opportunities set stage = 'negotiation'
       where id = v_opp and stage in ('prospecting', 'qualified', 'proposal');
    elsif v_opp is not null and new.status = 'sent' then
      update brain.opportunities set stage = 'proposal'
       where id = v_opp and stage in ('prospecting', 'qualified');
    end if;

    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
  exception when others then
    -- `OTHERS` não cobre cancelamento nem timeout de statement — ver o
    -- cabeçalho de 20260911150000.
    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
    raise warning '[brain-ponte] orcamento % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_order public.orders%rowtype;
  r       record;
  v_lock  text;
begin
  begin
    v_lock := pg_catalog.current_setting('lock_timeout', true);
    perform pg_catalog.set_config('lock_timeout', '250ms', true);

    -- No INSERT este gatilho é DEFERRED: dispara no commit, quando os
    -- itens já entraram e o total já foi recalculado.
    select * into v_order from public.orders where id = new.id;
    if not found then
      perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
      return null;
    end if;

    if tg_op = 'INSERT' then
      v_event := 'order.created';
    elsif new.status is distinct from old.status then
      v_event := 'order.' || new.status::text;
    else
      perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
      return null;
    end if;

    perform pg_catalog.set_config('brain.internal', 'on', true);

    if tg_op = 'INSERT' and v_order.quote_id is not null then
      for r in
        update brain.opportunities
           set order_id = v_order.id, stage = 'won',
               customer_id = coalesce(customer_id, v_order.customer_id)
         where quote_id = v_order.quote_id and stage not in ('won', 'lost')
         returning id, lead_id
      loop
        if r.lead_id is not null then
          update brain.leads
             set status = 'converted',
                 converted_at = coalesce(converted_at, now()),
                 customer_id = coalesce(customer_id, v_order.customer_id)
           where id = r.lead_id;
        end if;
      end loop;
    elsif v_event = 'order.cancelled' then
      update brain.opportunities set stage = 'negotiation'
       where order_id = v_order.id and stage = 'won';
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('order_id', v_order.id, 'number', v_order.number, 'status', v_order.status,
                         'total', v_order.total, 'quote_id', v_order.quote_id, 'owner_id', v_order.owner_id),
      'order:' || v_order.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson',
      (select o.lead_id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      v_order.customer_id,
      (select o.id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      null, null, null, null, 1, '{}'::jsonb);

    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
    raise warning '[brain-ponte] pedido % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911200000_brain_desacoplado.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- BRAIN — modo DESACOPLADO: as pontes nascem desligadas
--
-- Decisão de arquitetura tomada no GO condicionado de 11/09/2026: no
-- primeiro deploy em produção, NENHUM processamento do BRAIN acontece
-- dentro da transação de orçamento ou de pedido.
--
-- Os três gatilhos continuam EXISTINDO — o código está aplicado,
-- revisado e testado — mas ficam `DISABLE`. A sincronização ERP → BRAIN
-- passa a ser periódica:
--
--   ERP confirma orçamento/pedido
--     → a transação comercial termina (sem nada do BRAIN dentro)
--     → pg_cron chama brain.reconciliar_erp()
--     → divergencias_erp() acha o que falta
--     → reconciliar_erp() corrige
--     → o BRAIN recebe evento, vínculo e estágio
--     → a execução seguinte devolve relatório vazio
--
-- O preço é latência: o BRAIN sabe da venda no minuto seguinte, não no
-- instante. O ganho é que o risco residual do `statement_timeout` — o
-- único que sobrava depois de 20260911190000 — cai a ZERO, porque não há
-- mais código do BRAIN dentro da transação comercial.
--
-- ── COMO RELIGAR, quando for a hora ─────────────────────────
-- Não é editando este arquivo. É uma migration nova, com
-- `alter table ... enable trigger`, depois de a reconciliação periódica
-- ter rodado tempo suficiente para se confiar nela. Até lá, um banco
-- montado do Git reproduz produção: pontes desligadas.
-- ============================================================

alter table public.quotes disable trigger trg_brain_quotes;
alter table public.orders disable trigger trg_brain_orders;
alter table public.orders disable trigger trg_brain_orders_created;

-- ── A reconciliação precisa ser alcançável pelo pg_cron ─────
-- `is_admin()` responde pelo JWT, e o pg_cron não tem JWT nenhum: roda
-- como `postgres`, sem `auth.uid()`. `brain.is_privileged()` já sabe
-- distinguir isso — ela é verdadeira para administrador, para o marcador
-- interno e para papel de confiança sem JWT (postgres, service_role), e
-- FALSA para `anon` e para vendedor autenticado.
--
-- Trocar `is_admin()` por `is_privileged()` nas duas funções é o que
-- deixa o cron entrar sem abrir nada para quem não deve.

create or replace function brain.divergencias_erp()
returns table (
  tipo          text,
  entidade      text,
  id            uuid,
  numero        text,
  situacao      text,
  detalhe       text
)
language sql stable security definer set search_path = '' as $$
  with permitido as (select brain.is_privileged() as pode),

  ev_quote as (
    select 'evento_ausente'::text, 'quote'::text, q.id, q.number::text, q.status::text,
           'nenhum evento do ERP com status ' || q.status::text
      from public.quotes q, permitido p
     where p.pode and q.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'quote_id' = q.id::text
                          and e.payload ->> 'status'   = q.status::text)
  ),
  ev_order as (
    select 'evento_ausente'::text, 'order'::text, o.id, o.number::text, o.status::text,
           'nenhum evento do ERP com status ' || o.status::text
      from public.orders o, permitido p
     where p.pode and o.deleted_at is null
       and not exists (select 1 from brain.events e
                        where e.source = 'erp'
                          and e.payload ->> 'order_id' = o.id::text
                          and e.payload ->> 'status'   = o.status::text)
  ),
  estagio as (
    select 'estagio_atrasado'::text, 'opportunity'::text, op.id, q.number::text, op.stage::text,
           'orcamento em ' || q.status::text || ' e oportunidade em ' || op.stage::text
      from brain.opportunities op
      join public.quotes q on q.id = op.quote_id, permitido p
     where p.pode and q.deleted_at is null
       and op.stage not in ('won', 'lost')
       and ((q.status = 'approved' and op.stage in ('prospecting', 'qualified', 'proposal'))
         or (q.status = 'sent'     and op.stage in ('prospecting', 'qualified')))
  ),
  nao_ganha as (
    select 'venda_nao_ganha'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido em ' || o.status::text || ' e oportunidade em ' || op.stage::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id)), permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.stage <> 'won' and op.stage <> 'lost'
  ),
  desfeita as (
    select 'venda_desfeita'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'pedido cancelado e oportunidade ainda em won'
      from public.orders o
      join brain.opportunities op on op.order_id = o.id, permitido p
     where p.pode and o.status = 'cancelled' and op.stage = 'won'
  ),
  sem_vinculo as (
    select 'pedido_nao_ligado'::text, 'opportunity'::text, op.id, o.number::text, op.stage::text,
           'oportunidade sem order_id apontando para o pedido'
      from public.orders o
      join brain.opportunities op on op.quote_id = o.quote_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and op.order_id is null and op.stage <> 'lost'
  ),
  lead_parado as (
    select 'lead_nao_convertido'::text, 'lead'::text, l.id, o.number::text, l.status::text,
           'pedido vivo e lead em ' || l.status::text
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
      join brain.leads l on l.id = op.lead_id, permitido p
     where p.pode and o.deleted_at is null and o.status <> 'cancelled'
       and l.status <> 'converted' and l.status <> 'lost'
       and op.stage <> 'lost'
  )

  select * from ev_quote
  union all select * from ev_order
  union all select * from estagio
  union all select * from nao_ganha
  union all select * from desfeita
  union all select * from sem_vinculo
  union all select * from lead_parado;
$$;

-- Só a porta de entrada muda; o corpo é o mesmo de 20260911170000.
create or replace function brain.reconciliar_erp(p_limite integer default 500)
returns table (
  tipo       text,
  corrigidas integer
)
language plpgsql security definer set search_path = '' as $$
declare
  r           record;
  v_eventos   int := 0;
  v_estagio   int := 0;
  v_ganhas    int := 0;
  v_desfeitas int := 0;
  v_ligadas   int := 0;
  v_leads     int := 0;
  v_n         int;
begin
  if not brain.is_privileged() then
    raise exception 'Somente administrador (ou o processo periodico) reconcilia o BRAIN com o ERP'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  update brain.opportunities op
     set stage = 'negotiation'
    from public.orders o
   where op.order_id = o.id and o.status = 'cancelled' and op.stage = 'won';
  get diagnostics v_desfeitas = row_count;

  for r in
    select o.id as pedido, o.customer_id, op.id as oportunidade, op.lead_id
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
     where o.deleted_at is null and o.status <> 'cancelled' and op.stage <> 'lost'
     order by o.created_at
     limit p_limite
  loop
    update brain.opportunities set order_id = r.pedido
     where id = r.oportunidade and order_id is null;
    get diagnostics v_n = row_count;  v_ligadas := v_ligadas + v_n;

    update brain.opportunities
       set stage = 'won', customer_id = coalesce(customer_id, r.customer_id)
     where id = r.oportunidade and stage <> 'won';
    get diagnostics v_n = row_count;  v_ganhas := v_ganhas + v_n;

    if r.lead_id is not null then
      update brain.leads
         set status = 'converted',
             converted_at = coalesce(converted_at, now()),
             customer_id = coalesce(customer_id, r.customer_id)
       where id = r.lead_id and status not in ('converted', 'lost');
      get diagnostics v_n = row_count;  v_leads := v_leads + v_n;
    end if;
  end loop;

  update brain.opportunities op
     set stage = 'negotiation'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'approved'
     and op.stage in ('prospecting', 'qualified', 'proposal');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  update brain.opportunities op
     set stage = 'proposal'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'sent'
     and op.stage in ('prospecting', 'qualified');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  for r in
    select d.entidade, d.id, d.situacao
      from brain.divergencias_erp() d
     where d.tipo = 'evento_ausente'
     limit p_limite
  loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        case when r.situacao = 'draft' then 'quote.created' else 'quote.' || r.situacao end,
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reconciliacao:' || r.situacao,
        (select q.updated_at from public.quotes q where q.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        (select q.customer_id from public.quotes q where q.id = r.id),
        (select op.id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        case when r.situacao = 'draft' then 'order.created' else 'order.' || r.situacao end,
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reconciliacao:' || r.situacao,
        (select o.updated_at from public.orders o where o.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        (select o.customer_id from public.orders o where o.id = r.id),
        (select op.id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    end if;
    v_eventos := v_eventos + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);

  return query
    select * from (values
      ('evento_ausente',      v_eventos),
      ('estagio_atrasado',    v_estagio),
      ('venda_nao_ganha',     v_ganhas),
      ('venda_desfeita',      v_desfeitas),
      ('pedido_nao_ligado',   v_ligadas),
      ('lead_nao_convertido', v_leads)
    ) as t(tipo, corrigidas);
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.divergencias_erp()          from public, anon;
revoke execute on function brain.reconciliar_erp(integer)    from public, anon;
grant  execute on function brain.divergencias_erp()          to authenticated, service_role;
grant  execute on function brain.reconciliar_erp(integer)    to authenticated, service_role;

-- ── O que o pg_cron chama ───────────────────────────────────
-- Uma função sem argumento, que engole a própria falha: se a
-- reconciliação quebrar, o job NÃO pode ficar em estado de erro
-- permanente nem poluir o log a cada minuto. Ela registra o problema
-- como `warning` e devolve o total corrigido (ou -1 quando falhou), e a
-- execução seguinte tenta de novo.
--
-- Isto NÃO é a ponte: roda na sessão do pg_cron, fora de qualquer
-- transação comercial. Uma falha aqui não tem como tocar num orçamento.

create or replace function brain.reconciliar_erp_periodico()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_total integer := 0; r record;
begin
  for r in select * from brain.reconciliar_erp(500) loop
    v_total := v_total + r.corrigidas;
  end loop;
  return v_total;
exception when others then
  raise warning '[brain-reconciliacao] falhou: % (%)', sqlerrm, sqlstate;
  return -1;
end;
$$;

revoke execute on function brain.reconciliar_erp_periodico() from public, anon, authenticated;
grant  execute on function brain.reconciliar_erp_periodico() to service_role;

comment on function brain.reconciliar_erp_periodico() is
  'Ponto de entrada do pg_cron. Roda fora de qualquer transacao comercial; se falhar, registra warning e devolve -1, e o minuto seguinte tenta de novo.';

-- ── Quem está ligado, para conferir de fora ─────────────────
create or replace function brain.estado_das_pontes()
returns table (gatilho text, tabela text, habilitado boolean, estado "char")
language sql stable security definer set search_path = '' as $$
  select t.tgname::text, c.relname::text, t.tgenabled <> 'D', t.tgenabled
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
   where t.tgname in ('trg_brain_quotes', 'trg_brain_orders', 'trg_brain_orders_created');
$$;

revoke execute on function brain.estado_das_pontes() from public, anon;
grant  execute on function brain.estado_das_pontes() to authenticated, service_role;

comment on function brain.estado_das_pontes() is
  'Estado dos tres gatilhos da ponte ERP -> BRAIN. No modo desacoplado, os tres tem de vir habilitado = false.';


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/migrations/20260911210000_brain_fidelidade.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ════════════════════════════════════════════════════════════
-- BRAIN — fidelidade do nome do evento reposto
-- ════════════════════════════════════════════════════════════
-- O ensaio do deploy em modo desacoplado pegou uma divergência REAL
-- entre os dois caminhos que publicam o mesmo fato:
--
--   ponte (síncrona)  INSERT em `public.orders` → `order.created`
--   reconciliação     pedido novo               → `order.confirmed`
--
-- O nome vinha do status, e o status de nascimento de um pedido é
-- `confirmed` — `draft` nem existe em `public.order_status`, é status
-- de orçamento. Resultado: `order.created` NUNCA sairia pela
-- reconciliação. Com as pontes desligadas em produção, o BRAIN passaria
-- a receber um histórico com nomes diferentes dos que a ponte produz, e
-- quem for consumir esses eventos na Fase 2 leria dois vocabulários
-- para o mesmo fato.
--
-- A regra passa a ser a da ponte, e não a do status:
--
--   entidade SEM nenhum evento do ERP  →  `X.created`   (é o nascimento)
--   entidade COM evento do ERP         →  `X.<status>`  (é uma mudança)
--
-- Um pedido nascido e ainda `confirmed` recebe `order.created`, igual à
-- ponte. Um pedido que já tem evento e foi para `invoiced` recebe
-- `order.invoiced`, igual à ponte. Um orçamento que nasceu e já foi
-- para `sent` sem nenhum evento recebe `quote.created` carregando o
-- estado atual: o nascimento é o fato mais antigo que faltou, e o
-- `payload` diz a verdade de agora. O evento sai marcado com
-- `reconciliado_em` no metadado — é uma reconstrução, e está dito.
--
-- Idempotência: a chave de deduplicação passa a carregar o nome do
-- evento além do status, então rodar de novo não duplica nada, e o
-- relatório seguinte volta vazio porque `divergencias_erp()` compara
-- `payload ->> 'status'`, que o evento reposto carrega correto nos dois
-- casos.
--
-- Não mexe em ponte, não religa nada, não toca em dado comercial.

create or replace function brain.nome_do_evento_erp(
  p_entidade text, p_id uuid, p_situacao text)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from brain.events e
                  where e.source = 'erp'
                    and e.payload ->> (p_entidade || '_id') = p_id::text)
    then p_entidade || '.' || p_situacao
    else p_entidade || '.created'
  end;
$$;

revoke execute on function brain.nome_do_evento_erp(text, uuid, text) from public, anon;
grant  execute on function brain.nome_do_evento_erp(text, uuid, text) to authenticated, service_role;

comment on function brain.nome_do_evento_erp(text, uuid, text) is
  'Nome do evento que a ponte teria publicado: X.created quando a entidade nao tem nenhum evento do ERP (e o nascimento), X.<status> quando ja tem.';

create or replace function brain.reconciliar_erp(p_limite integer default 500)
returns table (
  tipo       text,
  corrigidas integer
)
language plpgsql security definer set search_path = '' as $$
declare
  r           record;
  v_eventos   int := 0;
  v_estagio   int := 0;
  v_ganhas    int := 0;
  v_desfeitas int := 0;
  v_ligadas   int := 0;
  v_leads     int := 0;
  v_n         int;
begin
  if not brain.is_privileged() then
    raise exception 'Somente administrador (ou o processo periodico) reconcilia o BRAIN com o ERP'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  update brain.opportunities op
     set stage = 'negotiation'
    from public.orders o
   where op.order_id = o.id and o.status = 'cancelled' and op.stage = 'won';
  get diagnostics v_desfeitas = row_count;

  for r in
    select o.id as pedido, o.customer_id, op.id as oportunidade, op.lead_id
      from public.orders o
      join brain.opportunities op
        on (op.order_id = o.id or (op.order_id is null and op.quote_id = o.quote_id))
     where o.deleted_at is null and o.status <> 'cancelled' and op.stage <> 'lost'
     order by o.created_at
     limit p_limite
  loop
    update brain.opportunities set order_id = r.pedido
     where id = r.oportunidade and order_id is null;
    get diagnostics v_n = row_count;  v_ligadas := v_ligadas + v_n;

    update brain.opportunities
       set stage = 'won', customer_id = coalesce(customer_id, r.customer_id)
     where id = r.oportunidade and stage <> 'won';
    get diagnostics v_n = row_count;  v_ganhas := v_ganhas + v_n;

    if r.lead_id is not null then
      update brain.leads
         set status = 'converted',
             converted_at = coalesce(converted_at, now()),
             customer_id = coalesce(customer_id, r.customer_id)
       where id = r.lead_id and status not in ('converted', 'lost');
      get diagnostics v_n = row_count;  v_leads := v_leads + v_n;
    end if;
  end loop;

  update brain.opportunities op
     set stage = 'negotiation'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'approved'
     and op.stage in ('prospecting', 'qualified', 'proposal');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  update brain.opportunities op
     set stage = 'proposal'
    from public.quotes q
   where q.id = op.quote_id and q.deleted_at is null and q.status = 'sent'
     and op.stage in ('prospecting', 'qualified');
  get diagnostics v_n = row_count;  v_estagio := v_estagio + v_n;

  for r in
    select d.entidade, d.id, d.situacao
      from brain.divergencias_erp() d
     where d.tipo = 'evento_ausente'
     limit p_limite
  loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        brain.nome_do_evento_erp('quote', r.id, r.situacao),
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reconciliacao:'
          || brain.nome_do_evento_erp('quote', r.id, r.situacao) || ':' || r.situacao,
        (select q.updated_at from public.quotes q where q.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        (select q.customer_id from public.quotes q where q.id = r.id),
        (select op.id from brain.opportunities op where op.quote_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        brain.nome_do_evento_erp('order', r.id, r.situacao),
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reconciliacao:'
          || brain.nome_do_evento_erp('order', r.id, r.situacao) || ':' || r.situacao,
        (select o.updated_at from public.orders o where o.id = r.id),
        'salesperson',
        (select op.lead_id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        (select o.customer_id from public.orders o where o.id = r.id),
        (select op.id from brain.opportunities op where op.order_id = r.id order by op.created_at limit 1),
        null, null, null, null, 1,
        jsonb_build_object('reconciliado_em', now(), 'reconciliado_por', (select auth.uid())));
    end if;
    v_eventos := v_eventos + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);

  return query
    select * from (values
      ('evento_ausente',      v_eventos),
      ('estagio_atrasado',    v_estagio),
      ('venda_nao_ganha',     v_ganhas),
      ('venda_desfeita',      v_desfeitas),
      ('pedido_nao_ligado',   v_ligadas),
      ('lead_nao_convertido', v_leads)
    ) as t(tipo, corrigidas);
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.reconciliar_erp(integer) from public, anon;
grant  execute on function brain.reconciliar_erp(integer) to authenticated, service_role;

comment on function brain.reconciliar_erp(integer) is
  'Poe o BRAIN de acordo com o ERP: evento (com o nome que a ponte teria dado), estagio, venda ganha, venda desfeita, vinculo do pedido e conversao do lead. Nao atropela decisao humana (lost fica lost) e rodar duas vezes nao muda nada.';


-- ── Pós-condições estruturais ───────────────────────────────
do $$
declare
  v_tab int; v_rls int; v_pol int; v_fun int; v_sem_sp int; v_anon int;
  v_imut text; v_trig int; v_after int; v_ligados int; v_view text; v_md5 text; v_canais int;
begin
  select count(*) into v_tab from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'r';
  select count(*) into v_rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'r' and c.relrowsecurity;
  select count(*) into v_pol from pg_policies where schemaname = 'brain';
  select count(*) into v_fun from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain';
  select count(*) into v_sem_sp from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain'
     and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%';
  select count(*) into v_anon from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and has_function_privilege('anon', p.oid, 'execute');
  select string_agg(p.proname, ', ') into v_imut from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  select array_to_string(c.reloptions, ',') into v_view from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'v' and c.relname = 'journey_entries';
  select count(*) into v_trig from pg_trigger where tgname like 'trg_brain%';
  select count(*) into v_after from pg_trigger
   where tgname like 'trg_brain%' and (tgtype::int & 2) = 0;
  select count(*) into v_ligados from pg_trigger
   where tgname like 'trg_brain%' and tgenabled <> 'D';
  select count(*) into v_canais from brain.channels;

  if v_tab <> 9     then raise exception 'Esperava 9 tabelas no brain, vieram % — PARADO.', v_tab; end if;
  if v_rls <> 9     then raise exception 'Apenas % das 9 tabelas com RLS — PARADO.', v_rls; end if;
  if v_pol < 27     then raise exception 'Esperava ao menos 27 policies, vieram % — PARADO.', v_pol; end if;
  if v_sem_sp <> 0  then raise exception '% funcao(oes) do brain sem search_path fixo — PARADO.', v_sem_sp; end if;
  if v_anon <> 0    then raise exception '% funcao(oes) do brain executaveis por anon — PARADO.', v_anon; end if;
  if v_imut is not null then
    raise exception 'Funcao(oes) do brain declarada(s) IMMUTABLE sem ser: % — PARADO.', v_imut;
  end if;
  if has_schema_privilege('anon', 'brain', 'usage') then
    raise exception 'anon tem USAGE no schema brain — PARADO.';
  end if;
  if v_view is distinct from 'security_invoker=true' then
    raise exception 'A view journey_entries esta com reloptions "%" — PARADO.', coalesce(v_view, '(nenhuma)');
  end if;
  if v_trig <> 3    then raise exception 'Esperava 3 gatilhos do brain em public, vieram % — PARADO.', v_trig; end if;
  if v_after <> 3   then raise exception 'Algum gatilho do brain em public nao e AFTER — PARADO.'; end if;
  -- MODO DESACOPLADO: existem, e estao desligados.
  if v_ligados <> 0 then
    raise exception 'MODO DESACOPLADO violado: % ponte(s) HABILITADA(S). Nenhum codigo do BRAIN pode rodar dentro da transacao comercial — PARADO.', v_ligados;
  end if;
  if v_canais <> 12 then raise exception 'Esperava 12 canais semeados, vieram % — PARADO.', v_canais; end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from 'ee2f5cd583295c30fbe64eb81eec2d9e' then
    raise exception 'audit_capture() ficou em md5 % e o ensaio em PostgreSQL 17.6 deu ee2f5cd583295c30fbe64eb81eec2d9e — PARADO.', v_md5;
  end if;

  raise notice 'Estrutura conferida: 9 tabelas com RLS, % policies, % funcoes, 3 gatilhos AFTER e DESABILITADOS, 12 canais, audit_capture no md5 do ensaio.',
    v_pol, v_fun;
end
$$;

-- ── Fotografia do comercial, ANTES ──────────────────────────
-- Nenhum dado comercial existente pode ser alterado por este deploy. A
-- prova é o md5 do conteúdo das tabelas de negócio, tirado agora e
-- conferido no fim.
create temporary table deploy_comercial_antes on commit drop as
select 'customers'         as tabela, md5(coalesce(string_agg(t::text, '|' order by t::text), '')) as retrato from public.customers t
union all select 'products',          md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.products t
union all select 'quotes',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quotes t
union all select 'quote_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quote_items t
union all select 'orders',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.orders t
union all select 'order_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.order_items t
union all select 'stock_movements',   md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.stock_movements t
union all select 'financial_entries', md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.financial_entries t
union all select 'purchases',         md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.purchases t;

-- ── Fumaça do fluxo DESACOPLADO, e sem resíduo ──────────────
-- Exercita o caminho que produção vai usar de verdade:
--
--   1. o ERP faz a venda inteira — orçamento, itens, enviado, aprovado,
--      pedido — e o BRAIN NÃO é tocado: zero eventos, oportunidade
--      parada, lead não convertido. É isso que "desacoplado" significa;
--   2. `divergencias_erp()` enxerga o que ficou para trás;
--   3. `reconciliar_erp()` reproduz o fato: evento, vínculo, venda
--      ganha, lead convertido;
--   4. `divergencias_erp()` volta VAZIO;
--   5. desfaz tudo, evento incluído, e prova que sobrou zero.
--
-- Num bloco só, sem `savepoint`: `rollback to savepoint` RESGATA uma
-- transação abortada, e uma fumaça que falhasse deixaria de impedir o
-- COMMIT. Aqui, qualquer assertiva que falhe aborta e o COMMIT lá
-- embaixo é executado como ROLLBACK.
--
-- O que sobra em produção depois desta fumaça: as linhas de
-- `public.audit_log` que ela gerou. É append-only por projeto — e é
-- correto que o log registre que a fumaça aconteceu.
do $$
declare
  v_cli uuid; v_admin uuid; v_unidade uuid;
  v_lead uuid; v_quote uuid; v_order uuid; v_prod uuid; v_opp uuid;
  v_total numeric; v_evento numeric;
  v_div int; v_sobrou int; r record; v_corrigidas int := 0;
begin
  select id into v_cli   from public.customers where deleted_at is null order by created_at limit 1;
  select id into v_admin from public.profiles  where role = 'admin'     order by created_at limit 1;
  select id into v_unidade from public.units   where code = 'UN';
  if v_cli is null or v_admin is null or v_unidade is null then
    raise exception 'Fumaca sem cliente, administrador ou unidade UN cadastrados — PARADO.';
  end if;

  insert into public.products (code, name, unit_id, sale_price)
   values ('FUMACA-DEPLOY', 'Produto da fumaca (sera apagado)', v_unidade, 1000.00)
   returning id into v_prod;

  -- O lead e a oportunidade são do CRM, não do ERP: entram direto.
  select lead_id into v_lead
    from brain.find_or_create_lead('Fumaca do deploy (sera apagada)', null, null, null, 'other');
  if v_lead is null then raise exception 'find_or_create_lead nao devolveu lead — PARADO.'; end if;

  insert into public.quotes (customer_id, owner_id) values (v_cli, v_admin) returning id into v_quote;

  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Fumaca do deploy', 'other', v_cli) returning id into v_opp;

  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot,
                                  quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Produto da fumaca (sera apagado)', 'FUMACA-DEPLOY', 2, 1000.00, 1);

  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;

  v_order := public.create_order_from_quote(v_quote);

  -- ── 1. Com as pontes desligadas, o BRAIN não soube de nada ─
  -- `set constraints` continua aqui de propósito: se alguém religar a
  -- ponte do pedido, o gatilho diferido dispararia AQUI e a assertiva
  -- abaixo pegaria — é a rede de segurança do modo desacoplado.
  execute 'set constraints public.trg_brain_orders_created immediate';

  select total into v_total from public.orders where id = v_order;
  if (select count(*) from brain.events) <> 0 then
    raise exception 'MODO DESACOPLADO violado: a ponte publicou % evento(s) dentro da transacao comercial — PARADO.',
      (select count(*) from brain.events);
  end if;
  if (select stage from brain.opportunities where id = v_opp) <> 'prospecting' then
    raise exception 'MODO DESACOPLADO violado: a oportunidade mudou de estagio dentro da transacao comercial — PARADO.';
  end if;
  if (select status from brain.leads where id = v_lead) = 'converted' then
    raise exception 'MODO DESACOPLADO violado: o lead foi convertido dentro da transacao comercial — PARADO.';
  end if;

  raise notice 'Fumaca 1/4: venda concluida (pedido %, total %) SEM nenhum evento no BRAIN — as pontes estao mesmo desligadas.',
    (select number from public.orders where id = v_order), v_total;

  -- ── 2. O relatório enxerga o que ficou para trás ───────────
  select count(*) into v_div from brain.divergencias_erp();
  if v_div = 0 then
    raise exception 'A reconciliacao nao viu a venda que acabou de acontecer — PARADO.';
  end if;
  raise notice 'Fumaca 2/4: divergencias_erp() acusou % pendencia(s).', v_div;

  -- ── 3. A reconciliação reproduz o fato ────────────────────
  for r in select * from brain.reconciliar_erp() loop
    v_corrigidas := v_corrigidas + r.corrigidas;
  end loop;

  select (payload ->> 'total')::numeric into v_evento
    from brain.events where event_name = 'order.created' and payload ->> 'order_id' = v_order::text;

  if v_evento is null then
    raise exception 'A reconciliacao nao publicou order.created — PARADO.';
  end if;
  if v_evento <> v_total then
    raise exception 'Evento com total % e pedido com total % — PARADO.', v_evento, v_total;
  end if;
  if (select stage from brain.opportunities where id = v_opp) <> 'won' then
    raise exception 'A reconciliacao nao marcou a venda como ganha (%) — PARADO.',
      (select stage from brain.opportunities where id = v_opp);
  end if;
  if (select status from brain.leads where id = v_lead) <> 'converted' then
    raise exception 'A reconciliacao nao converteu o lead (%) — PARADO.',
      (select status from brain.leads where id = v_lead);
  end if;
  if (select order_id from brain.opportunities where id = v_opp) is distinct from v_order then
    raise exception 'A reconciliacao nao ligou o pedido a oportunidade — PARADO.';
  end if;

  raise notice 'Fumaca 3/4: reconciliacao corrigiu % coisa(s) — evento com total % = pedido, venda ganha, lead convertido, pedido ligado.',
    v_corrigidas, v_evento;

  -- ── 4. O relatório volta vazio ────────────────────────────
  select count(*) into v_div from brain.divergencias_erp();
  if v_div <> 0 then
    raise exception 'Depois de reconciliar ainda sobraram % divergencia(s) — PARADO.', v_div;
  end if;
  raise notice 'Fumaca 4/4: divergencias_erp() vazio.';

  -- ── Desfazer, tudo ────────────────────────────────────────
  alter table brain.events disable trigger trg_events_immutable;
  delete from brain.events
   where payload ->> 'quote_id' = v_quote::text or payload ->> 'order_id' = v_order::text;
  alter table brain.events enable trigger trg_events_immutable;

  delete from public.order_items where order_id = v_order;
  delete from public.orders      where id = v_order;
  delete from public.quote_items where quote_id = v_quote;
  delete from public.quotes      where id = v_quote;
  delete from brain.opportunities where id = v_opp;
  delete from brain.leads         where id = v_lead;
  delete from public.products     where id = v_prod;

  select (select count(*) from brain.leads)
       + (select count(*) from brain.identities)
       + (select count(*) from brain.interactions)
       + (select count(*) from brain.opportunities)
       + (select count(*) from brain.tasks)
       + (select count(*) from brain.events)
       + (select count(*) from brain.lead_merges)
       + (select count(*) from brain.attributions)
    into v_sobrou;
  if v_sobrou <> 0 then
    raise exception 'A fumaca deixou % linha(s) no BRAIN — PARADO.', v_sobrou;
  end if;
  if exists (select 1 from public.quotes where id = v_quote)
  or exists (select 1 from public.orders where id = v_order)
  or exists (select 1 from public.products where code = 'FUMACA-DEPLOY') then
    raise exception 'A fumaca deixou orcamento, pedido ou produto de teste em producao — PARADO.';
  end if;
  if (select count(*) from brain.channels) <> 12 then
    raise exception 'A fumaca mexeu na semente de canais — PARADO.';
  end if;

  raise notice 'Fumaca desfeita: 0 linha no BRAIN, nenhum orcamento, pedido ou produto de teste, 12 canais intactos.';
end
$$;

-- ── O comercial não mudou ───────────────────────────────────
do $$
declare v_dif text;
begin
  with agora as (
    select 'customers' as tabela, md5(coalesce(string_agg(t::text, '|' order by t::text), '')) as retrato from public.customers t
    union all select 'products',          md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.products t
    union all select 'quotes',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quotes t
    union all select 'quote_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quote_items t
    union all select 'orders',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.orders t
    union all select 'order_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.order_items t
    union all select 'stock_movements',   md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.stock_movements t
    union all select 'financial_entries', md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.financial_entries t
    union all select 'purchases',         md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.purchases t
  )
  select string_agg(a.tabela, ', ') into v_dif
    from deploy_comercial_antes a join agora g on g.tabela = a.tabela
   where a.retrato is distinct from g.retrato;

  if v_dif is not null then
    raise exception 'O deploy ALTEROU dado comercial em: % — PARADO.', v_dif;
  end if;
  raise notice 'Dado comercial intacto: as 9 tabelas de negocio com o mesmo retrato de antes do deploy.';
end
$$;

-- ── Registro, no mesmo COMMIT da aplicação ──────────────────
insert into supabase_migrations.schema_migrations (version, name) values
 ('20260911130000', 'brain_foundation'),
 ('20260911140000', 'brain_exclusoes'),
 ('20260911150000', 'brain_pontes'),
 ('20260911160000', 'brain_volatilidade'),
 ('20260911170000', 'brain_reconciliacao'),
 ('20260911180000', 'brain_dependentes'),
 ('20260911190000', 'brain_janela'),
 ('20260911200000', 'brain_desacoplado'),
 ('20260911210000', 'brain_fidelidade');

do $$
begin
  -- Lista explícita: `like '202609111%'` não pegava 20260911200000 nem
  -- 20260911210000, e o número conferido seria sempre o errado.
  if (select count(*) from supabase_migrations.schema_migrations
       where version in ('20260911130000','20260911140000','20260911150000',
                         '20260911160000','20260911170000','20260911180000',
                         '20260911190000','20260911200000','20260911210000')) <> 9 then
    raise exception 'O registro das nove versoes do BRAIN nao fechou — PARADO.';
  end if;
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'O relatorio de divergencias ja nasce com pendencia — PARADO.';
  end if;
  raise notice 'Registro gravado e relatorio de divergencias vazio. Pronto para COMMIT.';
end
$$;

commit;

-- Depois do COMMIT: rode os advisors de seguranca e de desempenho e
-- compare com a lista de antes. Caminho de volta: 03 (logo apos, sem
-- nada dentro) ou 04 (com dado real).
