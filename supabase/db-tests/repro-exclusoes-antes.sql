-- ============================================================
-- BANCADA DE REPRODUÇÃO — como as exclusões estavam ANTES da correção.
--
-- Este arquivo NÃO é uma suíte: é a evidência de que os nove bloqueios
-- existiam. Rodado contra o commit 3df85b9 dá "passou=0 bloqueado=9"
-- (docs/evidencias/exclusoes-antes-pg176.txt).
--
-- Rodado contra o código corrigido, D1, D2, D3, D8 e D9 passam — e
-- D4 a D7 CONTINUAM bloqueados de propósito: eles tentam anular a
-- autoria com um UPDATE direto, enquanto o perfil ainda existe. Isso
-- tem de ser recusado, e é o que EX10, EX11 e EX14 provam pelo lado
-- positivo. Quem mede a correção de verdade é a suíte 27.
-- ============================================================
reset role;
set client_min_messages = notice;

do $bancada$
declare
  v_admin uuid := '99999999-0000-4000-8000-0000000000a1';
  v_vend  uuid := '99999999-0000-4000-8000-0000000000a2';
  v_lead  uuid := '99999999-0000-4000-8000-0000000000d1';
  v_cli   uuid;
  v_erro  text;
  v_ok    int := 0;
  v_falha int := 0;

begin
  insert into auth.users (id, email, raw_user_meta_data) values
   (v_admin,'repro.admin@teste.local','{"full_name":"Admin Repro","role":"admin"}'),
   (v_vend ,'repro.vend@teste.local' ,'{"full_name":"Vendedor Repro","role":"salesperson"}');
  update public.profiles set role = 'admin' where id = v_admin;
  insert into brain.leads (id, name) values (v_lead, 'Lead Solitario');

  -- ── D1: cliente ligado a IDENTIDADE sem lead ──────────────
  begin
    insert into public.customers (name) values ('Cliente Identidade') returning id into v_cli;
    insert into brain.identities (kind, value, customer_id) values ('email','so.cliente@exemplo.com', v_cli);
    begin
      delete from public.customers where id = v_cli;
      raise notice 'D1  PASSOU  cliente com identidade sem lead: excluido';
      v_ok := v_ok + 1;
    exception when others then
      v_erro := sqlerrm;
      raise notice 'D1  BLOQUEADO  %', left(v_erro, 90);
      v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D1  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D2: cliente ligado a INTERACAO sem lead ───────────────
  begin
    insert into public.customers (name) values ('Cliente Interacao') returning id into v_cli;
    insert into brain.interactions (customer_id, summary, channel_key) values (v_cli,'Ligacao sem lead','phone');
    begin
      delete from public.customers where id = v_cli;
      raise notice 'D2  PASSOU  cliente com interacao sem lead: excluido';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D2  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D2  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D3: cliente ligado a OPORTUNIDADE sem lead ────────────
  begin
    insert into public.customers (name) values ('Cliente Oportunidade') returning id into v_cli;
    insert into brain.opportunities (customer_id, title, channel_key) values (v_cli,'Oportunidade sem lead','other');
    begin
      delete from public.customers where id = v_cli;
      raise notice 'D3  PASSOU  cliente com oportunidade sem lead: excluido';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D3  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D3  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D4: perfil citado em brain.events.actor_id ────────────
  begin
    insert into brain.events (event_name, source, actor_id, payload)
      values ('teste.repro','app', v_vend, '{}'::jsonb);
    begin
      update brain.events set actor_id = null where actor_id = v_vend;
      raise notice 'D4  PASSOU  actor_id do evento anulado (perfil removido)';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D4  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D4  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D5: perfil citado em brain.tasks.created_by ───────────
  begin
    insert into brain.tasks (title, created_by, lead_id) values ('Tarefa do vendedor', v_vend, v_lead);
    begin
      update brain.tasks set created_by = null where created_by = v_vend;
      if exists (select 1 from brain.tasks where created_by = v_vend) then
        raise exception 'check_links() restaurou created_by — a FK vai falhar';
      end if;
      raise notice 'D5  PASSOU  created_by da tarefa anulado';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D5  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D5  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D6: perfil citado em brain.opportunities.created_by ───
  begin
    insert into brain.opportunities (lead_id, title, channel_key, created_by)
      values (v_lead,'Oportunidade do vendedor','other', v_vend);
    begin
      update brain.opportunities set created_by = null where created_by = v_vend;
      if exists (select 1 from brain.opportunities where created_by = v_vend) then
        raise exception 'check_links() restaurou created_by — a FK vai falhar';
      end if;
      raise notice 'D6  PASSOU  created_by da oportunidade anulado';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D6  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D6  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D7: perfil citado em brain.interactions.actor_id ──────
  begin
    insert into brain.interactions (lead_id, summary, channel_key, actor_id)
      values (v_lead,'Nota do vendedor','other', v_vend);
    begin
      update brain.interactions set actor_id = null where actor_id = v_vend;
      if exists (select 1 from brain.interactions where actor_id = v_vend) then
        raise exception 'check_links() restaurou actor_id — a FK vai falhar';
      end if;
      raise notice 'D7  PASSOU  actor_id da interacao anulado';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D7  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D7  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D8: excluir LEAD com oportunidade sem cliente ─────────
  begin
    insert into brain.opportunities (lead_id, title, channel_key)
      values (v_lead,'Oportunidade so do lead','other');
    begin
      delete from brain.leads where id = v_lead;
      raise notice 'D8  PASSOU  lead com oportunidade sem cliente: excluido';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D8  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D8  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  -- ── D9: exclusão FÍSICA do perfil inteiro (auth.users) ────
  begin
    insert into brain.events (event_name, source, actor_id, payload) values ('teste.d9','app', v_vend, '{}'::jsonb);
    insert into brain.tasks (title, created_by) values ('Tarefa D9', v_vend);
    insert into brain.opportunities (title, channel_key, created_by, customer_id)
      select 'Oportunidade D9','other', v_vend, id from public.customers limit 1;
    insert into brain.interactions (summary, channel_key, actor_id, customer_id)
      select 'Nota D9','other', v_vend, id from public.customers limit 1;
    begin
      delete from auth.users where id = v_vend;
      raise notice 'D9  PASSOU  perfil excluido com evento, tarefa, oportunidade e interacao ligados';
      v_ok := v_ok + 1;
    exception when others then
      raise notice 'D9  BLOQUEADO  %', left(sqlerrm, 90); v_falha := v_falha + 1;
      raise exception using errcode = 'P0001', message = '__rollback__';
    end;
  exception when others then
    if sqlerrm <> '__rollback__' then raise notice 'D9  ERRO INESPERADO  %', sqlerrm; end if;
  end;

  raise notice '';
  raise notice 'RESUMO  passou=%  bloqueado=%', v_ok, v_falha;
end
$bancada$;
