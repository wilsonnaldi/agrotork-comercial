-- ============================================================
-- REMOVER SÓ O LOTE B (ingestão) — voltando ao Lote A aprovado
-- ============================================================
-- Caminho de volta do Lote B, sem tocar no Lote A (já em produção e aprovado
-- separadamente) nem na Fase 1. Desfaz a migration 20260912030000 e nada
-- mais: ao final, os objetos que o Lote B alterou em brain.document_chunks
-- (`heading_norm`, `fts`, `idx_chunks_fts`, `uq_chunk_content`,
-- `stamp_chunk()`) ficam no formato exato do Lote A, e o ledger volta a ter
-- só 20260912010000 e 20260912020000.
--
-- Recusa-se a rodar quando:
--   · o Lote B não está aplicado (nada a fazer);
--   · existe conteúdo REPETIDO em páginas diferentes da mesma versão — o
--     Lote A tem `uq_chunk_content (version_id, content_sha256)`, e voltar
--     a ela apagaria ou quebraria esse conteúdo. Nesse caso, exporte/decida
--     à mão. Com a memória vazia (checkpoint pré-piloto) roda limpo.
-- A trilha de consulta (brain.knowledge_queries) é registro de perguntas,
-- não conhecimento: sai junto, e o roteiro avisa quantas linhas tinha.
--
-- Uma transação. Qualquer pré ou pós-condição que falhe aborta tudo.
-- COMO RODAR: SQL Editor do Supabase, colado inteiro.
-- Para remover A + B de uma vez, use o 06-remover-memoria-sem-dados.sql.
-- ============================================================

begin;

-- ── Pré-condições ───────────────────────────────────────────
do $$
declare v_n int; v_trilha bigint; v_retrato text;
begin
  if to_regclass('brain.document_chunks') is null then
    raise exception 'O Lote A nao esta aplicado. Nada a remover. PARADO.';
  end if;
  if to_regclass('brain.knowledge_queries') is null
     and not exists (select 1 from pg_attribute where attrelid = 'brain.document_chunks'::regclass and attname = 'heading_norm' and not attisdropped) then
    raise exception 'O Lote B nao esta aplicado (sem knowledge_queries e sem heading_norm). Nada a remover. PARADO.';
  end if;

  -- Conteudo repetido entre paginas da mesma versao: incompativel com a constraint do Lote A.
  select count(*) into v_n from (
    select version_id, content_sha256 from brain.document_chunks group by 1, 2 having count(*) > 1
  ) d;
  if v_n <> 0 then
    raise exception 'Ha % combinacao(oes) de conteudo repetido em paginas diferentes da mesma versao — incompativel com uq_chunk_content do Lote A. Exporte/decida a mao. PARADO.', v_n;
  end if;

  select count(*) into v_trilha from brain.knowledge_queries;
  if v_trilha > 0 then
    raise notice 'A trilha de consulta tem % linha(s); sai junto com o Lote B (e registro de perguntas, nao conhecimento).', v_trilha;
  end if;

  -- Retrato da Fase 1 antes: as 9 tabelas e as 3 pontes.
  select md5(string_agg(x, ',' order by x)) into v_retrato from (
    select 'tab:' || tablename as x from pg_tables where schemaname = 'brain'
       and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges')
    union all
    select 'trg:' || tgname || '=' || tgenabled::text from pg_trigger where tgname like 'trg_brain%'
  ) t;
  perform set_config('memoria.retrato_fase1', v_retrato, true);
  raise notice 'Pre-condicoes: Lote B aplicado, sem conteudo repetido entre paginas. Retrato da Fase 1: %.', v_retrato;
end
$$;

-- ── Remoção do que só o Lote B criou ─────────────────────────
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

-- ── Reversão do que o Lote B alterou no Lote A ───────────────
-- brain.document_chunks: fts volta a ser so o conteudo; heading_norm sai;
-- a unicidade volta a (version_id, content_sha256).
alter table brain.document_chunks drop column fts;
alter table brain.document_chunks drop column heading_norm;
alter table brain.document_chunks add column fts tsvector generated always as (to_tsvector('portuguese'::regconfig, content_norm)) stored;
create index idx_chunks_fts on brain.document_chunks using gin (fts);
alter table brain.document_chunks drop constraint uq_chunk_content;
alter table brain.document_chunks add constraint uq_chunk_content unique (version_id, content_sha256);

-- brain.stamp_chunk(): texto do Lote A (migration 20260912010000), byte a byte.
create or replace function brain.stamp_chunk()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select v.access_level into new.access_level from brain.document_versions v where v.id = new.version_id;
  if new.access_level is null then
    raise exception 'Chunk sem versao: %', new.version_id using errcode = 'foreign_key_violation';
  end if;
  if not exists (select 1 from brain.knowledge_ingestions i where i.id = new.ingestion_id and i.version_id = new.version_id) then
    raise exception 'A ingestao % nao e desta versao %', new.ingestion_id, new.version_id using errcode = 'foreign_key_violation';
  end if;
  new.content_norm   := coalesce(brain.normalize_text(new.content), '');
  new.content_sha256 := encode(sha256(convert_to(new.content, 'UTF8')), 'hex');
  new.codes := coalesce((select array_agg(distinct c order by c)
                           from unnest(new.codes) raw, lateral (select brain.normalize_code(raw)) n(c)
                          where c is not null), '{}');
  return new;
end;
$$;

revoke execute on function brain.stamp_chunk() from public, anon, authenticated;

delete from supabase_migrations.schema_migrations where version = '20260912030000';

-- ── Pós-condições ───────────────────────────────────────────
do $$
declare v_n int; v_retrato text; v_expr text; v_cols text;
begin
  if to_regclass('brain.knowledge_queries') is not null then raise exception 'knowledge_queries sobrou — PARADO.'; end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'public' and p.proname in ('brain_search', 'brain_provenance'))
      or (n.nspname = 'brain' and p.proname in ('register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail','ingestion_record_failure'));
  if v_n <> 0 then raise exception 'Sobrou funcao do Lote B — PARADO.'; end if;
  if to_regclass('storage.objects') is not null
     and exists (select 1 from pg_policies where schemaname = 'storage' and policyname like 'brain_documents%') then
    raise exception 'Sobrou policy de storage do Lote B — PARADO.';
  end if;
  if exists (select 1 from pg_attribute where attrelid = 'brain.document_chunks'::regclass and attname = 'heading_norm' and not attisdropped) then
    raise exception 'heading_norm sobrou — PARADO.';
  end if;
  select pg_get_expr(d.adbin, d.adrelid) into v_expr
    from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'brain.document_chunks'::regclass and a.attname = 'fts';
  if v_expr <> 'to_tsvector(''portuguese''::regconfig, content_norm)' then
    raise exception 'fts nao voltou ao formato do Lote A: % — PARADO.', v_expr;
  end if;
  select string_agg(a.attname, ',' order by k.ord) into v_cols
    from pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
   where c.conrelid = 'brain.document_chunks'::regclass and c.conname = 'uq_chunk_content';
  if v_cols <> 'version_id,content_sha256' then raise exception 'uq_chunk_content = (%) — PARADO.', v_cols; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'brain' and indexname = 'idx_chunks_fts') then raise exception 'idx_chunks_fts nao voltou — PARADO.'; end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260912030000') then raise exception 'Registro 20260912030000 nao saiu — PARADO.'; end if;
  if (select count(*) from supabase_migrations.schema_migrations where version in ('20260912010000','20260912020000')) <> 2 then
    raise exception 'Registros do Lote A nao estao os dois — PARADO.';
  end if;
  -- Lote A inteiro de pe.
  if (select count(*) from pg_tables where schemaname = 'brain'
        and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products')) <> 7 then
    raise exception 'Faltou tabela do Lote A — PARADO.';
  end if;
  if to_regprocedure('brain.search_knowledge(text, jsonb, integer, boolean)') is null or to_regprocedure('brain.chunk_provenance(bigint)') is null then
    raise exception 'Faltou funcao do Lote A — PARADO.';
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
  if exists (select 1 from pg_extension where extname = 'vector') then raise exception 'pgvector presente — PARADO.'; end if;
  raise notice 'Lote B removido; Lote A e Fase 1 intactos (retrato %). Pronto para COMMIT.', v_retrato;
end
$$;

commit;
