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
