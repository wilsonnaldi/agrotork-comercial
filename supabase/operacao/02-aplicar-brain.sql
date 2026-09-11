-- ============================================================
-- APLICAR A FASE 1 DO BRAIN — projeto nedmdkdhchkadijtdnja
--
-- UMA transação. As três migrations entram juntas, as conferências
-- rodam antes do COMMIT e o registro é gravado no MESMO commit em que a
-- aplicação acontece. Se qualquer condição falhar, a exceção aborta a
-- transação e o banco fica exatamente como estava — nada de "SELECT de
-- conferência e depois COMMIT".
--
-- Pré-requisitos, todos conferidos aqui dentro:
--   · PostgreSQL 17 (produção é 17.6);
--   · as nove migrations de 09/09 já reconciliadas (01-reconciliar);
--   · `instagram_curator` presente e registrado;
--   · `public.audit_capture()` no md5 conhecido — se estiver diferente,
--     alguém a mudou depois da auditoria e este script PARA;
--   · o schema `brain` ainda não existe;
--   · as três versões do BRAIN ainda não registradas.
--
-- Pós-condições, todas conferidas aqui dentro:
--   · 9 tabelas, todas com RLS; 1 view `security_invoker`;
--   · toda função do `brain` com `search_path` vazio e sem EXECUTE para
--     `anon`; `anon` sem USAGE no schema;
--   · 3 gatilhos em `public`, todos AFTER;
--   · `audit_capture()` no md5 esperado DEPOIS da mudança;
--   · orçamento e pedido continuam operando (fumaça revertida por
--     savepoint — nenhum dado comercial falso fica).
--
-- COMO RODAR: cole INTEIRO no SQL Editor, de uma vez. Rodar em pedaços
-- quebra a transação e anula a garantia.
-- ============================================================

begin;

-- ── Pré-condições ───────────────────────────────────────────
do $$
declare
  v_md5 text;
  v_versao int;
begin
  v_versao := current_setting('server_version_num')::int;
  if v_versao < 170000 or v_versao >= 180000 then
    raise exception 'Este roteiro foi ensaiado em PostgreSQL 17; aqui e % — PARADO.',
      current_setting('server_version');
  end if;

  if exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain JA EXISTE. Este roteiro e de primeira aplicacao — PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations
              where version like '2026090914%') then
    raise exception 'As nove migrations de 09/09 ainda estao com a versao errada. Rode 01-reconciliar-registro.sql antes — PARADO.';
  end if;

  if not exists (select 1 from pg_namespace where nspname = 'instagram_curator')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151115')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151534') then
    raise exception 'instagram_curator ausente ou sem registro — o banco nao e o que a auditoria descreveu. PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations
              where version in ('20260911130000','20260911140000','20260911150000')) then
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

-- ── As três migrations ──────────────────────────────────────
\i supabase/migrations/20260911130000_brain_foundation.sql
\i supabase/migrations/20260911140000_brain_exclusoes.sql
\i supabase/migrations/20260911150000_brain_pontes.sql

-- ── Pós-condições estruturais ───────────────────────────────
do $$
declare
  v_tab int; v_rls int; v_pol int; v_fun int; v_sem_sp int; v_anon int;
  v_trig int; v_after int; v_view text; v_md5 text; v_canais int;
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
  select array_to_string(c.reloptions, ',') into v_view from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'v' and c.relname = 'journey_entries';
  select count(*) into v_trig from pg_trigger where tgname like 'trg_brain%';
  select count(*) into v_after from pg_trigger
   where tgname like 'trg_brain%' and (tgtype::int & 2) = 0;   -- 2 = BEFORE
  select count(*) into v_canais from brain.channels;

  if v_tab <> 9        then raise exception 'Esperava 9 tabelas no brain, vieram % — PARADO.', v_tab; end if;
  if v_rls <> 9        then raise exception 'Apenas % das 9 tabelas com RLS — PARADO.', v_rls; end if;
  if v_pol < 27        then raise exception 'Esperava ao menos 27 policies, vieram % — PARADO.', v_pol; end if;
  if v_sem_sp <> 0     then raise exception '% funcao(oes) do brain sem search_path fixo — PARADO.', v_sem_sp; end if;
  if v_anon <> 0       then raise exception '% funcao(oes) do brain executaveis por anon — PARADO.', v_anon; end if;
  if has_schema_privilege('anon', 'brain', 'usage') then
    raise exception 'anon tem USAGE no schema brain — PARADO.';
  end if;
  if v_view is distinct from 'security_invoker=true' then
    raise exception 'A view journey_entries esta com reloptions "%" — PARADO.', coalesce(v_view, '(nenhuma)');
  end if;
  if v_trig <> 3       then raise exception 'Esperava 3 gatilhos do brain em public, vieram % — PARADO.', v_trig; end if;
  if v_after <> 3      then raise exception 'Algum gatilho do brain em public nao e AFTER — PARADO.'; end if;
  if v_canais <> 12    then raise exception 'Esperava 12 canais semeados, vieram % — PARADO.', v_canais; end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from 'ee2f5cd583295c30fbe64eb81eec2d9e' then
    raise exception 'audit_capture() ficou em md5 % e o ensaio em PostgreSQL 17.6 deu ee2f5cd583295c30fbe64eb81eec2d9e — PARADO.', v_md5;
  end if;

  raise notice 'Estrutura conferida: 9 tabelas com RLS, % policies, % funcoes, 3 gatilhos AFTER, 12 canais, audit_capture no md5 do ensaio.',
    v_pol, v_fun;
end
$$;

-- ── Fumaça: o ERP continua operando, e não fica sujeira ─────
-- TUDO num bloco só, inclusive a limpeza. Nada de `savepoint` +
-- `rollback to savepoint`: esse par RESGATA uma transação abortada, e um
-- roteiro que se resgata de um teste que falhou chegaria ao COMMIT com a
-- pós-condição negativa. Aqui, se qualquer assertiva falhar, a exceção
-- deixa a transação abortada e o COMMIT lá embaixo vira ROLLBACK — que é
-- o comportamento do PostgreSQL para COMMIT em transação abortada.
do $$
declare
  v_cli uuid; v_lead uuid; v_quote uuid; v_admin uuid;
  v_eventos int; v_sobrou int;
begin
  select id into v_cli from public.customers where deleted_at is null order by created_at limit 1;
  select id into v_admin from public.profiles where role = 'admin' order by created_at limit 1;
  if v_cli is null or v_admin is null then
    raise exception 'Sem cliente ou sem administrador cadastrado: a fumaca nao tem em que pegar — PARADO.';
  end if;

  select lead_id into v_lead
    from brain.find_or_create_lead('Fumaca do deploy (sera apagada)', null, null, null, 'other');
  if v_lead is null then
    raise exception 'find_or_create_lead nao devolveu lead — PARADO.';
  end if;

  insert into public.quotes (customer_id, owner_id) values (v_cli, v_admin) returning id into v_quote;

  select count(*) into v_eventos from brain.events
   where source = 'erp' and payload ->> 'quote_id' = v_quote::text;
  if v_eventos <> 1 then
    raise exception 'A ponte do orcamento publicou % evento(s) em vez de 1 — PARADO.', v_eventos;
  end if;

  -- Limpeza, aqui dentro. O evento do barramento NÃO se apaga (é a regra
  -- da tabela), então ele é marcado como ignorado — que é o que o próprio
  -- barramento oferece para um fato que não interessa.
  update brain.events set processing = 'skipped',
         processing_error = 'fumaca do deploy 20260911'
   where source = 'erp' and payload ->> 'quote_id' = v_quote::text;
  delete from public.quotes where id = v_quote;
  delete from brain.leads where id = v_lead;

  select count(*) into v_sobrou from brain.leads;
  if v_sobrou <> 0 then
    raise exception 'A fumaca deixou % lead(s) para tras — PARADO.', v_sobrou;
  end if;
  if exists (select 1 from public.quotes where id = v_quote) then
    raise exception 'A fumaca deixou o orcamento de teste em producao — PARADO.';
  end if;

  raise notice 'Fumaca OK: lead e orcamento criados, 1 evento publicado, e nada sobrou alem do evento marcado como skipped.';
end
$$;

-- ── Registro, no mesmo COMMIT da aplicação ──────────────────
insert into supabase_migrations.schema_migrations (version, name) values
 ('20260911130000', 'brain_foundation'),
 ('20260911140000', 'brain_exclusoes'),
 ('20260911150000', 'brain_pontes');

do $$
begin
  if (select count(*) from supabase_migrations.schema_migrations
       where version in ('20260911130000','20260911140000','20260911150000')) <> 3 then
    raise exception 'O registro das tres versoes do BRAIN nao fechou — PARADO.';
  end if;
  raise notice 'Registro gravado. Pronto para COMMIT.';
end
$$;

commit;

-- Depois do COMMIT, rode os advisors de seguranca e de desempenho e
-- compare com a lista de antes. O caminho de volta a partir daqui e
-- 03-remover-brain-sem-dados.sql (logo apos o deploy) ou
-- 04-incidente-com-dados.sql (se o BRAIN ja recebeu dado real).
