-- ============================================================
-- instagram_curator — as migrations recuperadas
-- (20260910151115 e 20260910151534).
--
-- A lacuna que este arquivo fecha: o schema existia em produção e não
-- existia no Git. A primeira tentativa foi escrever uma "baseline" nova
-- a partir do catálogo; a revisão de 11/09 mostrou que isso era pior do
-- que o problema — a baseline substituía funções, recriava gatilhos e
-- policies e mexia em permissões, e ainda assim era descrita como
-- "no-op estrutural". Foi descartada.
--
-- O que existe agora são as migrations ORIGINAIS, recuperadas byte a
-- byte de `supabase_migrations.schema_migrations.statements` e
-- conferidas por md5. Não há reescrita: é o que rodou em produção.
--
-- O que este arquivo prova:
--   IC1  a estrutura inteira nasce do Git;
--   IC2  toda função com `search_path` fixo;
--   IC3  `anon` e `authenticated` não enxergam o schema;
--   IC4  a trava distribuída funciona;
--   IC5  os checks de identidade da referência e o carimbo automático;
--   IC6  reaplicar as duas migrations não muda ESTRUTURA nem CONTEÚDO,
--        com dados representativos nas SEIS tabelas — comparação por
--        md5 do conteúdo ordenado, não por contagem;
--   IC7  o que a reaplicação REALMENTE faz (não é no-op incondicional).
-- ============================================================
reset role;

-- ── IC1: a estrutura veio inteira do Git ─────────────────────
do $$
declare
  v_tabelas int; v_enums int; v_funcs int; v_policies int; v_rls int; v_idx int; v_coment int;
begin
  select count(*) into v_tabelas from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r';
  select count(*) into v_enums from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'instagram_curator' and t.typtype = 'e';
  select count(*) into v_funcs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator';
  select count(*) into v_policies from pg_policies where schemaname = 'instagram_curator';
  select count(*) into v_rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r' and c.relrowsecurity;
  select count(*) into v_idx from pg_indexes where schemaname = 'instagram_curator';
  select count(*) into v_coment from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0
   where n.nspname = 'instagram_curator' and col_description(c.oid, a.attnum) is not null;

  if v_tabelas <> 6 or v_enums <> 2 or v_funcs <> 4 or v_policies <> 6
     or v_rls <> 6 or v_idx <> 17 or v_coment <> 2 then
    raise exception 'IC1 FALHOU: % tabelas, % enums, % funcoes, % policies, % com RLS, % indices, % comentarios de coluna',
      v_tabelas, v_enums, v_funcs, v_policies, v_rls, v_idx, v_coment;
  end if;
  if obj_description('instagram_curator'::regnamespace, 'pg_namespace') is null then
    raise exception 'IC1 FALHOU: o comentario do schema se perdeu';
  end if;
  raise notice ' IC1) OK: 6 tabelas (todas com RLS), 2 enums, 4 funcoes, 6 policies, 17 indices, 3 comentarios';
end
$$;

-- ── IC2: toda função com search_path fixo ────────────────────
do $$
declare v_frouxa text;
begin
  select string_agg(p.proname, ', ') into v_frouxa
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator'
     and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%';
  if v_frouxa is not null then
    raise exception 'IC2 FALHOU: sem search_path fixo: %', v_frouxa;
  end if;
  raise notice ' IC2) OK: as 4 funcoes tem search_path fixo';
end
$$;

-- ── IC3: o ERP não enxerga o curador ─────────────────────────
do $$
declare v_anon boolean; v_auth boolean; v_tab int;
begin
  v_anon := has_schema_privilege('anon', 'instagram_curator', 'usage');
  v_auth := has_schema_privilege('authenticated', 'instagram_curator', 'usage');
  select count(*) into v_tab
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
     and (has_table_privilege('anon', c.oid, 'select')
          or has_table_privilege('authenticated', c.oid, 'select'));
  if v_anon or v_auth or v_tab > 0 then
    raise exception 'IC3 FALHOU: anon=% authenticated=% tabelas legiveis=%', v_anon, v_auth, v_tab;
  end if;
  raise notice ' IC3) OK: anon e authenticated sem USAGE no schema e sem SELECT em nenhuma tabela';
end
$$;

-- ── IC4: a trava distribuída ─────────────────────────────────
insert into instagram_curator.runs (executor) values ('teste-baseline');

do $$
declare
  v_run uuid;
  v_dono1 uuid := '26262626-0000-4000-8000-000000000001';
  v_dono2 uuid := '26262626-0000-4000-8000-000000000002';
  v_a boolean; v_b boolean; v_c boolean; v_d boolean;
begin
  select id into v_run from instagram_curator.runs where executor = 'teste-baseline';

  v_a := instagram_curator.acquire_lock('curador', v_dono1, 60, v_run);
  v_b := instagram_curator.acquire_lock('curador', v_dono2, 60, v_run);
  v_c := instagram_curator.heartbeat_lock('curador', v_dono2, 60);
  v_d := instagram_curator.heartbeat_lock('curador', v_dono1, 60);

  if not v_a or v_b or v_c or not v_d then
    raise exception 'IC4 FALHOU: pegou=% invasor_pegou=% invasor_renovou=% dono_renovou=%', v_a, v_b, v_c, v_d;
  end if;

  begin
    perform instagram_curator.acquire_lock('curador', v_dono1, 10, v_run);
    raise exception 'IC4 FALHOU: aceitou ttl de 10s';
  exception when others then
    if sqlerrm not like '%lock ttl%' then raise; end if;
  end;

  -- `locks_expiry_order` exige expires_at > acquired_at: para simular um
  -- vencimento é preciso recuar a aquisição junto.
  update instagram_curator.locks
     set acquired_at  = now() - interval '10 minutes',
         heartbeat_at = now() - interval '10 minutes',
         expires_at   = now() - interval '1 minute'
   where lock_name = 'curador';
  if not instagram_curator.acquire_lock('curador', v_dono2, 60, v_run) then
    raise exception 'IC4 FALHOU: trava vencida nao foi tomada';
  end if;
  if instagram_curator.release_lock('curador', v_dono1) then
    raise exception 'IC4 FALHOU: quem nao e dono soltou a trava';
  end if;
  if not instagram_curator.release_lock('curador', v_dono2) then
    raise exception 'IC4 FALHOU: o dono nao soltou a trava';
  end if;

  raise notice ' IC4) OK: um dono por vez, ttl entre 30s e 3600s, trava vencida e tomada, so o dono solta';
end
$$;

-- ── IC5: identidade da referência e carimbo automático ───────
do $$
declare v_id uuid; v_depois timestamptz;
begin
  begin
    insert into instagram_curator."references" (shortcode, origin) values ('ABC123', 'teste');
    raise exception 'IC5 FALHOU: aceitou shortcode sem URL';
  exception when check_violation then null;
  end;

  begin
    insert into instagram_curator."references" (shortcode, canonical_url, observed_route, origin)
    values ('ABC123', 'https://instagram.com/p/OUTRO/', 'p', 'teste');
    raise exception 'IC5 FALHOU: aceitou URL de outro shortcode';
  exception when check_violation then null;
  end;

  insert into instagram_curator."references" (shortcode, canonical_url, observed_route, origin)
  values ('ABC123', 'https://www.instagram.com/p/ABC123/', 'p', 'teste')
  returning id into v_id;

  begin
    update instagram_curator."references" set status = 'completed' where id = v_id;
    raise exception 'IC5 FALHOU: aceitou completed sem completed_at';
  exception when check_violation then null;
  end;

  -- `now()` não anda dentro de uma transação: quem prova o gatilho é a
  -- tentativa de escrever um `updated_at` mentiroso e vê-lo ser ignorado.
  update instagram_curator."references"
     set topic = 'pulverizacao', updated_at = timestamptz '2000-01-01 00:00:00+00'
   where id = v_id;
  select updated_at into v_depois from instagram_curator."references" where id = v_id;
  if v_depois <> now() or v_depois = timestamptz '2000-01-01 00:00:00+00' then
    raise exception 'IC5 FALHOU: updated_at ficou em % — o gatilho nao carimbou', v_depois;
  end if;

  raise notice ' IC5) OK: meia-identidade, URL trocada e completed sem data recusados; updated_at mentiroso foi sobrescrito';
end
$$;

-- ── IC6: reaplicar não muda estrutura NEM conteúdo ──────────
-- Dados representativos nas SEIS tabelas — inclusive linhas com todos os
-- campos preenchidos, jsonb aninhado, acento e caractere de escape — e
-- depois comparação por md5 do conteúdo ORDENADO de cada tabela. Contar
-- linhas não prova nada: uma reaplicação que zerasse um `jsonb` ou
-- reescrevesse um `updated_at` passaria numa contagem.
do $$
declare v_run uuid; v_ref uuid;
begin
  insert into instagram_curator.runs
    (executor, status, started_at, finished_at, navigation_attempts, counters,
     stop_reason, error_sanitized, checkpoints, baseline_mode, audit_mode,
     declared_complete_scan, metadata)
  values
    ('curador-ic6', 'succeeded', timestamptz '2026-09-01 10:00:00+00', timestamptz '2026-09-01 10:30:00+00',
     7, '{"vistos": 120, "novos": 8}'::jsonb, 'source_exhausted', 'erro sanitizado com acento: configuração',
     '[{"at":"2026-09-01T10:10:00Z","n":3}]'::jsonb, false, true, true,
     '{"nota": "aspas '' e barra \\ no texto"}'::jsonb)
  returning id into v_run;

  insert into instagram_curator."references"
    (shortcode, canonical_url, observed_route, source_account, origin, topic, angle, status,
     caption, like_position, discovered_at, first_seen_at, last_seen_at, processing_started_at,
     completed_at, deferred_until, published_at, legacy_key, legacy_folder_label,
     legacy_state_unverified, provenance, metadata, last_error_sanitized)
  values
    ('IC6ref01', 'https://www.instagram.com/reel/IC6ref01/', 'reel', '@agrotork.oficial', 'curadoria',
     'pulverização', 'demonstração de campo', 'completed',
     'Legenda com acento, emoji ausente e aspas "duplas"', 42,
     timestamptz '2026-08-20 08:00:00+00', timestamptz '2026-08-20 08:00:00+00',
     timestamptz '2026-08-29 09:00:00+00', timestamptz '2026-08-30 07:00:00+00',
     timestamptz '2026-08-31 18:00:00+00', null, timestamptz '2026-09-01 12:00:00+00',
     'legado/2026/08/ic6', 'Agosto — pulverização', true,
     '{"fonte":"pasta legada","conferido":false}'::jsonb,
     '{"tags":["arag","magnojet"],"nivel":{"a":1,"b":[2,3]}}'::jsonb,
     'timeout ao carregar mídia')
  returning id into v_ref;

  insert into instagram_curator.artifacts (reference_id, kind, persistent_uri, checksum, status, metadata)
  values (v_ref, 'art',     'storage://curador/ic6/art.png',  'sha256:aaaa', 'ready',      '{"w":1080,"h":1350}'::jsonb),
         (v_ref, 'caption', 'storage://curador/ic6/cap.txt',  null,          'pending',    '{}'::jsonb),
         (v_ref, 'bundle',  'storage://curador/ic6/bundle.zip','sha256:bbbb','superseded', '{"itens":3}'::jsonb);

  insert into instagram_curator.events (run_id, reference_id, event_type, occurred_at, details)
  values (v_run, v_ref,  'reference.discovered', timestamptz '2026-08-20 08:00:00+00', '{"rota":"reel"}'::jsonb),
         (v_run, v_ref,  'reference.completed',  timestamptz '2026-08-31 18:00:00+00', '{"artefatos":3}'::jsonb),
         (v_run, null,   'run.checkpoint',       timestamptz '2026-09-01 10:10:00+00', '{"n":3}'::jsonb);

  insert into instagram_curator.locks (lock_name, owner_token, run_id, acquired_at, heartbeat_at, expires_at)
  values ('curador-ic6', '26262626-0000-4000-8000-0000000000f1', v_run,
          timestamptz '2026-09-01 10:00:00+00', timestamptz '2026-09-01 10:20:00+00',
          timestamptz '2026-09-01 11:00:00+00');

  insert into instagram_curator.editorial_rules (rule_key, state, config, rationale, source, effective_from)
  values ('tom-de-voz', 'active',
          '{"pessoa":"primeira do plural","proibido":["hype","garantido"]}'::jsonb,
          'Regra escrita com acentuação e vírgula, para pegar reescrita silenciosa.',
          'manual-editorial', timestamptz '2026-01-01 00:00:00+00'),
         ('frequencia', 'proposed', '{"posts_semana":3}'::jsonb, null, 'proposta-2026', null);
end
$$;

-- Retrato do conteúdo ANTES.
create temporary table ic6_antes as
select 'runs'            as tabela, md5(string_agg(t::text, '|' order by t::text)) as conteudo from instagram_curator.runs t
union all select 'references',      md5(string_agg(t::text, '|' order by t::text)) from instagram_curator."references" t
union all select 'artifacts',       md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.artifacts t
union all select 'events',          md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.events t
union all select 'locks',           md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.locks t
union all select 'editorial_rules', md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.editorial_rules t;

create temporary table ic6_estrutura_antes as
select c.relname::text || '.' || a.attname as obj,
       pg_catalog.format_type(a.atttypid, a.atttypmod) as v
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
 where n.nspname = 'instagram_curator' and c.relkind = 'r';

\i supabase/migrations/20260910151115_create_private_instagram_curator.sql
\i supabase/migrations/20260910151534_harden_private_instagram_curator.sql

do $$
declare v_dif text; v_linhas int;
begin
  with depois as (
    select 'runs' as tabela, md5(string_agg(t::text, '|' order by t::text)) as conteudo from instagram_curator.runs t
    union all select 'references',      md5(string_agg(t::text, '|' order by t::text)) from instagram_curator."references" t
    union all select 'artifacts',       md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.artifacts t
    union all select 'events',          md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.events t
    union all select 'locks',           md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.locks t
    union all select 'editorial_rules', md5(string_agg(t::text, '|' order by t::text)) from instagram_curator.editorial_rules t
  )
  select string_agg(a.tabela, ', ') into v_dif
    from ic6_antes a join depois d on d.tabela = a.tabela
   where a.conteudo is distinct from d.conteudo;

  if v_dif is not null then
    raise exception 'IC6 FALHOU: o conteudo mudou em: %', v_dif;
  end if;

  select count(*) into v_linhas from ic6_antes where conteudo is null;
  if v_linhas > 0 then
    raise exception 'IC6 FALHOU: % tabela(s) estavam vazias — o teste nao provaria nada', v_linhas;
  end if;

  if exists (
    select 1 from ic6_estrutura_antes e
    full join (
      select c.relname::text || '.' || a.attname as obj, pg_catalog.format_type(a.atttypid, a.atttypmod) as v
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
       where n.nspname = 'instagram_curator' and c.relkind = 'r'
    ) d on d.obj = e.obj
    where e.obj is null or d.obj is null or e.v is distinct from d.v
  ) then
    raise exception 'IC6 FALHOU: a estrutura de colunas mudou na reaplicacao';
  end if;

  raise notice ' IC6) OK: as duas migrations reaplicadas — conteudo das 6 tabelas identico (md5 por tabela) e colunas identicas';
end
$$;

-- ── IC7: o que a reaplicação DE FATO faz ────────────────────
-- "No-op estrutural" era descrição errada. `create or replace function`
-- SUBSTITUI as quatro funções, `drop trigger if exists` + `create` REFAZ
-- os dois gatilhos, e `grant`/`revoke`/`alter default privileges`
-- REESCREVEM as permissões. Isto aqui mede as duas coisas ao mesmo
-- tempo: os objetos são mesmo trocados (o OID muda), e o valor deles não
-- muda (a definição, o md5 e as ACLs continuam iguais).
create temporary table ic7_antes as
select 'funcao:' || p.proname as obj, p.oid::text as oid,
       md5(pg_get_functiondef(p.oid)) as definicao
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'instagram_curator'
union all
select 'gatilho:' || t.tgname, t.oid::text, md5(pg_get_triggerdef(t.oid))
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'instagram_curator' and not t.tgisinternal
union all
select 'acl:' || c.relname, '-', md5(coalesce(array_to_string(c.relacl, ' '), ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'instagram_curator' and c.relkind = 'r';

\i supabase/migrations/20260910151115_create_private_instagram_curator.sql
\i supabase/migrations/20260910151534_harden_private_instagram_curator.sql

do $$
declare v_trocados int; v_definicao_mudou text; v_acl_mudou text;
begin
  create temporary table ic7_depois as
  select 'funcao:' || p.proname as obj, p.oid::text as oid, md5(pg_get_functiondef(p.oid)) as definicao
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator'
  union all
  select 'gatilho:' || t.tgname, t.oid::text, md5(pg_get_triggerdef(t.oid))
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and not t.tgisinternal
  union all
  select 'acl:' || c.relname, '-', md5(coalesce(array_to_string(c.relacl, ' '), ''))
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r';

  select count(*) into v_trocados
    from ic7_antes a join ic7_depois d on d.obj = a.obj
   where a.oid <> '-' and a.oid is distinct from d.oid;

  select string_agg(a.obj, ', ') into v_definicao_mudou
    from ic7_antes a join ic7_depois d on d.obj = a.obj
   where (a.obj like 'funcao:%' or a.obj like 'gatilho:%')
     and a.definicao is distinct from d.definicao;

  select string_agg(a.obj, ', ') into v_acl_mudou
    from ic7_antes a join ic7_depois d on d.obj = a.obj
   where a.obj like 'acl:%' and a.definicao is distinct from d.definicao;

  if v_definicao_mudou is not null then
    raise exception 'IC7 FALHOU: a definicao mudou em %', v_definicao_mudou;
  end if;
  if v_acl_mudou is not null then
    raise exception 'IC7 FALHOU: a ACL mudou em %', v_acl_mudou;
  end if;
  if v_trocados < 2 then
    raise exception 'IC7 FALHOU: esperava ver os gatilhos serem refeitos (OID novo), vi %', v_trocados;
  end if;

  raise notice ' IC7) OK: a reaplicacao TROCA objetos (% com OID novo — os gatilhos sao drop+create) e NAO muda valor nenhum: definicao e ACL identicas', v_trocados;
  drop table ic7_depois;
end
$$;

-- Limpeza: esta suíte não deixa lixo para as seguintes.
delete from instagram_curator.events;
delete from instagram_curator.artifacts;
delete from instagram_curator.locks;
delete from instagram_curator.editorial_rules;
delete from instagram_curator."references";
delete from instagram_curator.runs;
drop table ic6_antes;
drop table ic6_estrutura_antes;
drop table ic7_antes;
