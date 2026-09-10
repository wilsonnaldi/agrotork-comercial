-- ============================================================
-- 0910120000 · AGROTORK BRAIN — Fase 1: fundação (CRM + eventos)
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
  select exists (
    select 1 from brain.leads l
     where l.id = p_lead_id
       and ((select public.is_admin())
            or l.owner_id is null
            or l.owner_id = (select auth.uid()))
  );
$$;

create or replace function brain.can_see_opportunity(p_opportunity_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from brain.opportunities o
     where o.id = p_opportunity_id
       and ((select public.is_admin())
            or o.owner_id = (select auth.uid())
            or (o.lead_id is not null and brain.can_see_lead(o.lead_id)))
  );
$$;

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
revoke execute on function brain.resolve_identity(brain.identity_kind, text) from public, anon;
grant  execute on function brain.normalize_phone(text) to authenticated, service_role;
grant  execute on function brain.normalize_identity(brain.identity_kind, text) to authenticated, service_role;
grant  execute on function brain.resolve_identity(brain.identity_kind, text) to authenticated, service_role;

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
begin
  if not (select public.is_active_user()) and v_uid is not null then
    raise exception 'Usuario inativo' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'Informe o nome do contato' using errcode = 'check_violation';
  end if;
  if p_owner_id is not null and p_owner_id <> v_uid and not (select public.is_admin()) then
    raise exception 'Somente administrador atribui lead a outro vendedor' using errcode = 'insufficient_privilege';
  end if;

  -- 1. Já conhecemos alguma dessas identidades? Ordem: WhatsApp/telefone,
  --    e-mail, Instagram. A primeira que bater decide.
  for v_kind, v_value in
    select * from (values
      ('whatsapp'::brain.identity_kind, p_phone),
      ('phone'::brain.identity_kind,    p_phone),
      ('email'::brain.identity_kind,    p_email),
      ('instagram'::brain.identity_kind, p_instagram)
    ) as v(kind, value) where value is not null
  loop
    select * into v_hit from brain.resolve_identity(v_kind, v_value);
    if found and (v_hit.lead_id is not null or v_hit.customer_id is not null) then
      v_lead := v_hit.lead_id; v_customer := v_hit.customer_id; v_matched := v_hit.matched_by;
      exit;
    end if;
  end loop;

  -- Lead já existe: segue o sobrevivente se ele foi unificado, carimba o toque.
  if v_lead is not null then
    select coalesce(l.merged_into_lead_id, l.id), l.customer_id
      into v_lead, v_customer
      from brain.leads l where l.id = v_lead;
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
begin
  if v_uid is not null and not brain.can_see_lead(p_lead_id) then
    raise exception 'Lead fora do seu alcance' using errcode = 'insufficient_privilege';
  end if;
  select customer_id into v_cust from brain.leads where id = p_lead_id;
  if not found then
    raise exception 'Lead nao encontrado' using errcode = 'no_data_found';
  end if;

  if p_external_id is not null then
    select id into v_id from brain.interactions where source = p_source and external_id = p_external_id;
    if found then
      return query select v_id, true;
      return;
    end if;
  end if;

  insert into brain.interactions
    (lead_id, customer_id, opportunity_id, channel_key, interaction_type, direction,
     summary, occurred_at, actor_id, source, external_id, event_id, metadata)
  values
    (p_lead_id, v_cust, p_opportunity_id, p_channel_key, p_interaction_type, p_direction,
     p_summary, coalesce(p_occurred_at, now()), v_uid, p_source, p_external_id, p_event_id, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_id;

  -- O evento cru que originou a interação ganha o vínculo com o lead —
  -- é o que faz a jornada começar na origem, não no primeiro contato.
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
  v_uid uuid := (select auth.uid());
  v_id  bigint;
begin
  if v_uid is not null and not (select public.is_active_user()) then
    raise exception 'Usuario inativo' using errcode = 'insufficient_privilege';
  end if;

  if p_external_id is not null then
    select id into v_id from brain.events where source = p_source and external_id = p_external_id;
    if found then
      return query select v_id, true;
      return;
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

  -- Corrida: outra transação gravou o mesmo external_id entre o SELECT e o INSERT.
  if v_id is null then
    select id into v_id from brain.events where source = p_source and external_id = p_external_id;
    return query select v_id, true;
    return;
  end if;

  return query select v_id, false;
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
    'quote:' || new.id::text || ':' || v_event,
    now(), 'salesperson', v_lead, new.customer_id, v_opp, null, null, null, null, 1, '{}'::jsonb);

  -- Orçamento aprovado empurra a oportunidade para negociação.
  if v_opp is not null and new.status = 'approved' then
    update brain.opportunities set stage = 'negotiation'
     where id = v_opp and stage in ('prospecting', 'qualified', 'proposal');
  elsif v_opp is not null and new.status = 'sent' then
    update brain.opportunities set stage = 'proposal'
     where id = v_opp and stage in ('prospecting', 'qualified');
  end if;

  return null;
end;
$$;

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  r       record;
begin
  if tg_op = 'INSERT' then
    v_event := 'order.created';
  elsif new.status is distinct from old.status then
    v_event := 'order.' || new.status::text;
  else
    return null;
  end if;

  -- A oportunidade que apontava para o orçamento de origem ganha o pedido.
  if tg_op = 'INSERT' and new.quote_id is not null then
    for r in
      update brain.opportunities
         set order_id = new.id, stage = 'won', customer_id = coalesce(customer_id, new.customer_id)
       where quote_id = new.quote_id and stage not in ('won', 'lost')
       returning id, lead_id
    loop
      if r.lead_id is not null then
        update brain.leads
           set status = 'converted',
               converted_at = coalesce(converted_at, now()),
               customer_id = coalesce(customer_id, new.customer_id)
         where id = r.lead_id;
      end if;
    end loop;
  end if;

  perform brain.ingest_event(
    v_event, 'erp',
    jsonb_build_object('order_id', new.id, 'number', new.number, 'status', new.status,
                       'total', new.total, 'quote_id', new.quote_id, 'owner_id', new.owner_id),
    'order:' || new.id::text || ':' || v_event,
    now(), 'salesperson',
    (select o.lead_id from brain.opportunities o where o.order_id = new.id order by o.created_at limit 1),
    new.customer_id,
    (select o.id from brain.opportunities o where o.order_id = new.id order by o.created_at limit 1),
    null, null, null, null, 1, '{}'::jsonb);

  return null;
end;
$$;

revoke execute on function brain.on_quote_change() from public, anon, authenticated;
revoke execute on function brain.on_order_change() from public, anon, authenticated;

create trigger trg_brain_quotes after insert or update of status on public.quotes
  for each row execute function brain.on_quote_change();
create trigger trg_brain_orders after insert or update of status on public.orders
  for each row execute function brain.on_order_change();

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

-- `interactions` e `events` NÃO são auditados: eles SÃO o registro.

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
    -- Carimbos de toque e score sobem a cada interação/evento: são
    -- consequência, não decisão. A interação em si já é o registro.
    v_ignore := v_ignore || array['first_touch_at', 'last_touch_at', 'score'];
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
