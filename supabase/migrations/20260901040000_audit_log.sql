-- ============================================================
-- 4000 · Fase 6.3 — Trilha de auditoria
--
-- O PROBLEMA
--
-- O sistema sabe QUEM é o dono de cada registro (`created_by`,
-- `updated_by`, `owner_id`) e QUANDO ele mudou pela última vez
-- (`updated_at`), mas não guarda O QUE mudou nem quantas vezes. Depois de
-- um `update`, o estado anterior desaparece. Não há como responder "quem
-- rebaixou o preço deste produto na semana passada", "quem aprovou este
-- orçamento" ou "quem virou administrador e quando".
--
-- A DECISÃO CENTRAL: CAPTURA POR TRIGGER, NÃO PELA APLICAÇÃO
--
-- Três fatos do sistema, verificados antes de escrever isto, empurram
-- para o banco e não para o código:
--
--   1. A expiração automática (Fase 6.2) roda pelo pg_cron como
--      `postgres`: sem `auth.uid()`, sem Server Action, sem requisição
--      HTTP. Registrar `quote.expired` pela aplicação é impossível, e
--      alterar `expire_quotes()` está fora de escopo.
--   2. Trocar o papel de um usuário não tem tela: é `update
--      public.profiles set role='admin'` no SQL Editor (SETUP.md §5.3).
--      É o evento mais sensível do sistema e nenhuma Server Action o vê.
--   3. Toda mutação da aplicação vai pelo PostgREST, e cada requisição é
--      a sua própria transação. Não há como a aplicação fazer
--      `set_config('app.motivo', …)` antes do `update` e o trigger ler.
--      Por isso NÃO existe campo de motivo livre nesta versão: o verbo de
--      negócio é derivado do diff.
--
-- Captura pela aplicação também depende de alguém lembrar de chamar — e a
-- chamada que esquecerem é justamente a que se vai querer investigar.
--
-- A ARMADILHA QUE ESTA MIGRATION PRECISA DESARMAR
--
-- A migration 1000 declarou `alter default privileges in schema public
-- grant select, insert, update, delete on tables to authenticated`, e o
-- Supabase traz os seus próprios defaults. Foi verificado executando: uma
-- tabela criada em `public` nasce com INSERT, SELECT, UPDATE, DELETE e
-- TRUNCATE concedidos a `authenticated` E A `anon`; uma função nova nasce
-- com EXECUTE para os dois. Sem os `revoke` explícitos abaixo, a trilha
-- de auditoria nasceria gravável pelo público, com o RLS como única
-- defesa. Log de auditoria é evidência: não pode depender de uma camada
-- só.
--
-- O QUE ESTA MIGRATION NÃO FAZ
--
-- Não toca em nada da Fase 6.2 (`expire_quotes()`, o job
-- `expirar-orcamentos`, o índice de expiração), nem nas quatro funções de
-- trigger protegidas pela migration 20260901020000, nem nas policies
-- existentes, nem em `quote_sequences`, nem em `auth.*`. Nenhuma migration
-- anterior foi alterada. Nenhuma função existente foi redefinida.
--
-- Fora de escopo por decisão: tela de auditoria, linha do tempo do
-- orçamento para o vendedor, expurgo automático, encadeamento de hash,
-- auditoria de leitura, de Storage e de login.
-- ============================================================

-- ── 1. A tabela ─────────────────────────────────────────────
-- Somente-anexação. Sem chave estrangeira NENHUMA, de propósito: uma FK
-- faria apagar um orçamento apagar (ou travar) a prova de que ele
-- existiu, e apagar um usuário levaria junto o rastro dele. Por isso o
-- ator vai denormalizado — nome, e-mail e papel congelados no instante do
-- fato. Se o papel mudar amanhã, o log continua dizendo o que era hoje.
create table public.audit_log (
  id             bigint generated always as identity primary key,
  occurred_at    timestamptz not null default now(),

  -- QUEM
  actor_kind     text not null default 'user'
                 check (actor_kind in ('user','system','anonymous','unknown')),
  actor_user_id  uuid,                    -- auth.uid(); nulo quando não há sessão
  actor_email    text,
  actor_name     text,
  actor_role     public.user_role,
  actor_db_role  text not null,           -- postgres, authenticated, anon…

  -- O QUÊ
  action         text not null check (action ~ '^[a-z_]+\.[a-z_]+$'),
  operation      text not null check (operation in ('INSERT','UPDATE','DELETE')),

  -- EM QUAL REGISTRO
  -- `text` e não `uuid`: `app_settings` tem chave primária textual.
  entity_type    text not null,
  entity_id      text not null,
  entity_label   text,                    -- 'ORC-2026-0004', 'P-001' — legível
  parent_type    text,                    -- item de kit → 'kit'
  parent_id      text,                    -- item de orçamento → id do orçamento

  -- ANTES E DEPOIS
  -- No UPDATE, só as colunas que mudaram. No INSERT e no DELETE, a linha
  -- inteira. Diff reduz o log, reduz o que vaza se algo der errado e conta
  -- a história direto: {"status": {…}} em vez de 26 colunas em volta.
  changed_fields text[],
  old_data       jsonb,
  new_data       jsonb,

  metadata       jsonb not null default '{}'::jsonb
);

comment on table public.audit_log is
  'Trilha de auditoria: somente-anexação, escrita apenas por audit_capture(), legível apenas por administrador. É evidência, não tabela de trabalho.';
comment on column public.audit_log.actor_db_role is
  'Papel do PostgreSQL em efeito na escrita (o GUC `role`, que sobrevive ao security definer). Junto com actor_user_id, é o que distingue "foi o cron" de "foi alguém no painel".';
comment on column public.audit_log.changed_fields is
  'Colunas efetivamente alteradas no UPDATE. Nulo em INSERT e DELETE, onde a linha inteira é gravada.';
comment on column public.audit_log.metadata is
  'txid da transação (permite agrupar eventos de uma mesma ação) e a tabela de origem.';

-- ── 2. Índices: três, e só três ─────────────────────────────
-- "o que aconteceu com ESTE orçamento" — a consulta mais frequente
create index idx_audit_entity on public.audit_log (entity_type, entity_id, occurred_at desc);
-- "o que fulano andou fazendo"
create index idx_audit_actor on public.audit_log (actor_user_id, occurred_at desc)
  where actor_user_id is not null;
-- "o que aconteceu ontem"
create index idx_audit_recente on public.audit_log (occurred_at desc);

-- ── 3. Privilégios ──────────────────────────────────────────
-- Ver "A ARMADILHA" no cabeçalho. O `revoke all` é o que impede a tabela
-- de nascer gravável por anon/authenticated. Só SELECT volta, e mesmo ele
-- só entrega linhas se o RLS deixar.
revoke all on public.audit_log from public, anon, authenticated, service_role;
grant select on public.audit_log to authenticated, service_role;

-- ── 4. RLS: uma única policy, e de leitura ──────────────────
-- Sem policy de INSERT, UPDATE ou DELETE. No PostgreSQL, ausência de
-- policy é negação: nem com privilégio o usuário escreve.
--
-- Por que só administrador lê: a migration 1200 tirou `cost_price` de
-- `products` e o pôs em `product_costs` com RLS de administrador, porque o
-- PostgreSQL não filtra COLUNA por papel. Auditar custo recria esse dado.
-- Se o vendedor lesse a auditoria, o custo vazaria por ali — e
-- `05_custo_produto.sql` continuaria passando, porque ela testa
-- `product_costs`, não o log.
alter table public.audit_log enable row level security;

create policy audit_log_select_admin on public.audit_log
  for select to authenticated
  using (public.is_admin());

comment on policy audit_log_select_admin on public.audit_log is
  'Somente administrador lê a trilha. O vendedor não enxerga nem os eventos dos próprios orçamentos: o log carrega custo e dado de outros vendedores.';

-- ── 5. Imutabilidade ────────────────────────────────────────
-- O `revoke` acima não alcança o dono da tabela. Este trigger alcança:
-- vale para todo mundo, inclusive `postgres`. Desligá-lo exige um
-- `alter table … disable trigger` deliberado, que é em si um ato
-- registrável. TRUNCATE entra na conta porque é justamente o privilégio
-- que os default privileges concedem e que um `delete` bloqueado não
-- cobre.
create or replace function public.audit_log_guard()
returns trigger
language plpgsql
as $$
begin
  raise exception 'public.audit_log é somente-anexação: % recusado', tg_op
    using errcode = 'insufficient_privilege',
          hint = 'Trilha de auditoria é evidência: não se corrige e não se apaga.';
end;
$$;

comment on function public.audit_log_guard() is
  'Recusa UPDATE, DELETE e TRUNCATE em audit_log. Atinge inclusive o dono da tabela, que o REVOKE não alcança.';

create trigger trg_audit_log_no_update
  before update on public.audit_log
  for each row execute function public.audit_log_guard();

create trigger trg_audit_log_no_delete
  before delete on public.audit_log
  for each row execute function public.audit_log_guard();

create trigger trg_audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function public.audit_log_guard();

-- ── 6. O escritor ───────────────────────────────────────────
-- Uma função só, usada por todas as tabelas auditadas. Os parâmetros vêm
-- do CREATE TRIGGER (TG_ARGV), não de quem chama — o navegador não tem
-- como influenciar nada aqui.
--
--   TG_ARGV[0] entity_type   'quote', 'product', 'kit_item'…
--   TG_ARGV[1] coluna da chave primária
--   TG_ARGV[2] coluna do rótulo legível ('' se não houver)
--   TG_ARGV[3] parent_type   ('' se não houver)
--   TG_ARGV[4] coluna do parent_id ('' se não houver)
--
-- `security definer` é necessário: o trigger precisa gravar em uma tabela
-- onde `authenticated` não tem INSERT, e precisa ler `profiles` para
-- congelar o ator. `search_path` fica FIXO em `public` — nunca mutável.
create or replace function public.audit_capture()
returns trigger
language plpgsql
security definer
set search_path = public
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
      when 'kit_item'          then 'kit.item_removed'
      when 'quote_share_token' then 'quote.link_deleted'
      when 'product_cost'      then 'product.cost_removed'
      else v_entity || '.deleted'
    end;

  elsif tg_op = 'INSERT' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_added'
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

comment on function public.audit_capture() is
  'Escritor único da trilha de auditoria. Deriva o verbo de negócio do diff, congela o ator, ignora colunas derivadas e redige segredos na escrita. Chamada apenas por trigger.';

-- Mesma regra da migration 20260901020000: função de trigger não é RPC.
-- Sem isto ela nasceria com EXECUTE para anon e authenticated e apareceria
-- em /rest/v1/rpc/, virando aviso do Security Advisor.
revoke execute on function public.audit_capture()   from public, anon, authenticated;
revoke execute on function public.audit_log_guard() from public, anon, authenticated;

-- ── 7. Os triggers ──────────────────────────────────────────
-- AFTER, nunca BEFORE: `stamp_quote_status` é BEFORE UPDATE e preenche
-- `sent_at`/`approved_at`/`rejected_at`. Um trigger BEFORE registraria
-- valores que ainda não existem.
--
-- Instalados tabela a tabela, nominalmente. Não existe "audita tudo do
-- schema": `quote_sequences` (contador interno) e `auth.*` (onde moram
-- senha, tokens e sessões) ficam de fora por construção, não por filtro.

-- Usuários — o evento mais sensível do sistema, e o único sem tela.
create trigger trg_audit_profiles after insert or update or delete on public.profiles
  for each row execute function public.audit_capture('user', 'id', 'full_name', '', '');

-- Clientes — `is_active` (desativação) e `deleted_at` (exclusão lógica)
-- são coisas diferentes e viram eventos diferentes.
create trigger trg_audit_customers after insert or update or delete on public.customers
  for each row execute function public.audit_capture('customer', 'id', 'name', '', '');

-- Produtos e custo. `product_costs` é o dado mais sensível do sistema.
create trigger trg_audit_products after insert or update or delete on public.products
  for each row execute function public.audit_capture('product', 'id', 'code', '', '');

create trigger trg_audit_product_costs after insert or update or delete on public.product_costs
  for each row execute function public.audit_capture('product_cost', 'product_id', '', 'product', 'product_id');

-- Kits e composição. O item carrega o kit em `parent_id`, para que "o que
-- aconteceu com o KIT-001" seja uma consulta só.
create trigger trg_audit_kits after insert or update or delete on public.kits
  for each row execute function public.audit_capture('kit', 'id', 'code', '', '');

create trigger trg_audit_kit_items after insert or update or delete on public.kit_items
  for each row execute function public.audit_capture('kit_item', 'id', '', 'kit', 'kit_id');

-- Orçamentos.
create trigger trg_audit_quotes after insert or update or delete on public.quotes
  for each row execute function public.audit_capture('quote', 'id', 'number', '', '');

create trigger trg_audit_quote_items after insert or update or delete on public.quote_items
  for each row execute function public.audit_capture('quote_item', 'id', 'name_snapshot', 'quote', 'quote_id');

create trigger trg_audit_share_tokens after insert or update or delete on public.quote_share_tokens
  for each row execute function public.audit_capture('quote_share_token', 'id', '', 'quote', 'quote_id');

-- Configurações da empresa: saem no PDF e na página pública.
create trigger trg_audit_app_settings after insert or update or delete on public.app_settings
  for each row execute function public.audit_capture('setting', 'key', 'key', '', '');

-- Cadastros de apoio. Desativar uma unidade em uso é exatamente o tipo de
-- coisa que ninguém lembra de ter feito.
create trigger trg_audit_units after insert or update or delete on public.units
  for each row execute function public.audit_capture('unit', 'id', 'code', '', '');

create trigger trg_audit_categories after insert or update or delete on public.categories
  for each row execute function public.audit_capture('category', 'id', 'name', '', '');

create trigger trg_audit_brands after insert or update or delete on public.brands
  for each row execute function public.audit_capture('brand', 'id', 'name', '', '');
