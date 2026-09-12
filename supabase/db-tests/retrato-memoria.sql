-- Retrato ESTRUTURAL da memória corporativa (Lote A + o que o Lote B toca).
-- Devolve um md5 de uma listagem canônica: colunas (nome, tipo, not null,
-- default/expressão gerada — sem posição física), constraints, índices,
-- policies (brain.* e brain_documents_* em storage.objects), funções do
-- brain/public da memória (md5 da definição), rótulos de enum e ledger
-- 20260912*. Usado pelo ensaio para provar que "Lote A → aplica B →
-- remove B" devolve a mesma estrutura.
select md5(string_agg(x, E'\n' order by x)) from (
  select 'col:' || c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
         || ':' || a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '') || ':' || a.attgenerated::text as x
    from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where n.nspname = 'brain' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
     and c.relname in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries')
  union all
  select 'con:' || c.relname || '.' || k.conname || ':' || pg_get_constraintdef(k.oid)
    from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relname in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries')
  union all
  select 'idx:' || indexname || ':' || indexdef from pg_indexes where schemaname = 'brain'
     and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries')
  union all
  select 'pol:' || schemaname || '.' || tablename || '.' || policyname || ':' || cmd || ':' || coalesce(qual, '') || ':' || coalesce(with_check, '')
    from pg_policies where (schemaname = 'brain') or (schemaname = 'storage' and policyname like 'brain_documents%')
  union all
  select 'fn:' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || md5(pg_get_functiondef(p.oid)) || ':' || p.provolatile::text || ':' || p.prosecdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'brain' and p.proname in ('search_knowledge','chunk_provenance','current_version','external_processing_for','caller_access_level','can_read_level','normalize_text','normalize_code','stamp_version','stamp_chunk','stamp_page','stamp_ingestion','stamp_chunk_product','cascade_document_access','cascade_version_access','cascade_chunk_access','register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail','ingestion_record_failure'))
      or (n.nspname = 'public' and p.proname in ('brain_search','brain_provenance'))
  union all
  select 'trg:' || c.relname || '.' || t.tgname || ':' || pg_get_triggerdef(t.oid)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and not t.tgisinternal
     and c.relname in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries')
  union all
  select 'enum:' || t.typname || ':' || string_agg(e.enumlabel, ',' order by e.enumsortorder)
    from pg_enum e join pg_type t on t.oid = e.enumtypid join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'brain' group by t.typname
  union all
  select 'mig:' || version from supabase_migrations.schema_migrations where version like '20260912%'
) s;
