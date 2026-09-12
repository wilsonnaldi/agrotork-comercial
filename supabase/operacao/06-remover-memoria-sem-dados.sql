-- ============================================================
-- REMOVER OS LOTES A e B DA FASE 2 (memória corporativa) — só sem dados
-- ============================================================
-- Caminho de volta da memória: desfaz as migrations 20260912010000,
-- 20260912020000 e 20260912030000 (se aplicada) e nada mais. A Fase 1 (CRM, eventos, pontes, cron) fica
-- exatamente como está — este roteiro confere isso antes e depois.
--
-- Recusa-se a rodar se QUALQUER linha existir nas sete tabelas da
-- memória: fonte cadastrada, documento, versão, ingestão, página, chunk
-- ou vínculo. A trilha de consulta (knowledge_queries, Lote B) pode ter
-- linhas — é registro de perguntas, não conhecimento — e sai junto. Conhecimento ingerido não é descartável por roteiro; se for
-- o caso, exporte antes, à mão.
--
-- Uma transação. Qualquer pré ou pós-condição que falhe aborta tudo.
-- COMO RODAR: SQL Editor do Supabase, colado inteiro.
-- ============================================================

begin;

-- ── Pré-condições ───────────────────────────────────────────
do $$
declare v_linhas bigint; v_n int; v_retrato text;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe. PARADO.';
  end if;
  if to_regclass('brain.document_chunks') is null then
    raise exception 'O Lote A nao esta aplicado (brain.document_chunks nao existe). Nada a remover. PARADO.';
  end if;

  select (select count(*) from brain.knowledge_sources)
       + (select count(*) from brain.documents)
       + (select count(*) from brain.document_versions)
       + (select count(*) from brain.knowledge_ingestions)
       + (select count(*) from brain.document_pages)
       + (select count(*) from brain.document_chunks)
       + (select count(*) from brain.chunk_products)
    into v_linhas;
  if v_linhas <> 0 then
    raise exception 'A MEMORIA TEM CONTEUDO: % linha(s) nas sete tabelas. Conhecimento ingerido nao se descarta por roteiro — exporte antes. PARADO.', v_linhas;
  end if;

  -- Nenhum objeto fora do brain depende do Lote A.
  select count(*) into v_n
    from pg_depend dep
    join pg_class c on c.oid = dep.refobjid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain'
     and c.relname in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products')
     and dep.deptype = 'n'
     and dep.classid = 'pg_class'::regclass
     and exists (select 1 from pg_class c2 join pg_namespace n2 on n2.oid = c2.relnamespace
                  where c2.oid = dep.objid and n2.nspname <> 'brain');
  if v_n <> 0 then
    raise exception 'Ha % objeto(s) fora do brain dependendo das tabelas da memoria — resolva a mao. PARADO.', v_n;
  end if;

  -- Retrato da Fase 1 antes: as 9 tabelas e as 3 pontes.
  select md5(string_agg(x, ',' order by x)) into v_retrato from (
    select 'tab:' || tablename as x from pg_tables where schemaname = 'brain'
       and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges')
    union all
    select 'trg:' || tgname || '=' || tgenabled::text from pg_trigger where tgname like 'trg_brain%'
  ) t;
  perform set_config('memoria.retrato_fase1', v_retrato, true);
  raise notice 'Pre-condicoes: Lote A aplicado, zero linhas, sem dependente externo. Retrato da Fase 1: %.', v_retrato;
end
$$;

-- ── Remoção, na ordem inversa da criação ────────────────────
-- Lote B (inerte se nunca foi aplicado)
drop function if exists public.brain_search(text, jsonb, integer, boolean);
drop function if exists public.brain_provenance(bigint);
drop function if exists brain.ingestion_record_failure(uuid, text, text, text, text, text, jsonb, boolean, timestamptz);
drop function if exists brain.ingestion_fail(uuid, text, jsonb);
drop function if exists brain.ingestion_finish(uuid, brain.ingestion_status, text, jsonb, jsonb);
drop function if exists brain.ingestion_add_chunk(uuid, integer, brain.chunk_kind, integer, integer, text, text[], jsonb, text[], integer, jsonb);
drop function if exists brain.ingestion_add_page(uuid, integer, text, text, boolean, jsonb, jsonb);
drop function if exists brain.ingestion_start(uuid, text, text, text, text, boolean, integer, boolean);
drop function if exists brain.register_version(uuid, text, text, text, text, bigint, date, integer, jsonb);
drop table if exists brain.knowledge_queries;
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists brain_documents_read   on storage.objects;
    drop policy if exists brain_documents_write  on storage.objects;
    drop policy if exists brain_documents_update on storage.objects;
    drop policy if exists brain_documents_delete on storage.objects;
  end if;
end $$;
-- Lote A
drop function if exists brain.current_version(uuid);
drop function if exists brain.chunk_provenance(bigint);
drop function if exists brain.search_knowledge(text, jsonb, integer, boolean);
drop type if exists brain.knowledge_hit;

-- A policy de leitura das fontes consulta documents: sai antes da tabela.
drop policy if exists knowledge_sources_select on brain.knowledge_sources;
drop table if exists brain.chunk_products;
drop table if exists brain.document_chunks;
drop table if exists brain.document_pages;
drop table if exists brain.knowledge_ingestions;
drop table if exists brain.document_versions;
drop table if exists brain.documents;
drop table if exists brain.knowledge_sources;

drop function if exists brain.external_processing_for(uuid);
drop function if exists brain.cascade_chunk_access();
drop function if exists brain.cascade_version_access();
drop function if exists brain.cascade_document_access();
drop function if exists brain.stamp_chunk_product();
drop function if exists brain.stamp_ingestion();
drop function if exists brain.stamp_page();
drop function if exists brain.stamp_chunk();
drop function if exists brain.stamp_version();
drop function if exists brain.normalize_code(text);
drop function if exists brain.normalize_text(text);
drop function if exists brain.can_read_level(brain.access_level);
drop function if exists brain.caller_access_level();

drop type if exists brain.knowledge_role;
drop type if exists brain.external_processing;
drop type if exists brain.link_origin;
drop type if exists brain.chunk_kind;
drop type if exists brain.ingestion_status;
drop type if exists brain.version_status;
drop type if exists brain.document_type;
drop type if exists brain.access_level;

delete from supabase_migrations.schema_migrations
 where version in ('20260912010000', '20260912020000', '20260912030000');

-- ── Pós-condições ───────────────────────────────────────────
do $$
declare v_n int; v_retrato text;
begin
  select count(*) into v_n from pg_tables where schemaname = 'brain'
     and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries');
  if v_n <> 0 then raise exception 'Sobrou tabela da memoria — PARADO.'; end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('brain_search', 'brain_provenance');
  if v_n <> 0 then raise exception 'Sobrou funcao brain_* em public — PARADO.'; end if;
  select count(*) into v_n from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'brain' and t.typname in ('access_level','document_type','version_status','ingestion_status','chunk_kind','link_origin','external_processing','knowledge_role','knowledge_hit');
  if v_n <> 0 then raise exception 'Sobrou tipo da memoria — PARADO.'; end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.proname in ('search_knowledge','chunk_provenance','current_version','external_processing_for','caller_access_level','can_read_level','normalize_text','normalize_code','stamp_version','stamp_chunk','stamp_page','stamp_ingestion','stamp_chunk_product','cascade_document_access','cascade_version_access','cascade_chunk_access','register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail','ingestion_record_failure');
  if v_n <> 0 then raise exception 'Sobrou funcao da memoria — PARADO.'; end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version in ('20260912010000','20260912020000','20260912030000')) then
    raise exception 'Registro do Lote A nao saiu — PARADO.';
  end if;

  -- A Fase 1 continua exatamente como estava.
  select md5(string_agg(x, ',' order by x)) into v_retrato from (
    select 'tab:' || tablename as x from pg_tables where schemaname = 'brain'
       and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges')
    union all
    select 'trg:' || tgname || '=' || tgenabled::text from pg_trigger where tgname like 'trg_brain%'
  ) t;
  if v_retrato is distinct from current_setting('memoria.retrato_fase1', true) then
    raise exception 'O retrato da Fase 1 mudou durante a remocao — PARADO.';
  end if;
  if (select count(*) from pg_trigger where tgname like 'trg_brain%' and tgenabled <> 'D') <> 0 then
    raise exception 'Uma ponte ficou habilitada — PARADO.';
  end if;
  perform brain.divergencias_erp();
  raise notice 'Lote A removido; Fase 1 intacta (retrato %). Pronto para COMMIT.', v_retrato;
end
$$;

commit;
