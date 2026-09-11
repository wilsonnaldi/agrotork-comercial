select md5(string_agg(linha, chr(10) order by linha)) as retrato from (
  select 'FUNC :: ' || n.nspname || '.' || p.proname || ' :: ' || md5(pg_get_functiondef(p.oid)) as linha
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('brain') or (n.nspname='public' and p.proname='audit_capture')
  union all
  select 'TAB :: ' || table_schema || '.' || table_name from information_schema.tables where table_schema='brain'
  union all
  select 'COL :: ' || table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable
    from information_schema.columns where table_schema='brain'
  union all
  select 'POL :: ' || schemaname || '.' || tablename || ' ' || policyname || ' ' || coalesce(qual,'-') || ' ' || coalesce(with_check,'-')
    from pg_policies where schemaname='brain'
  union all
  select 'IDX :: ' || indexname || ' ' || indexdef from pg_indexes where schemaname='brain'
  union all
  select 'TRG :: ' || t.tgname || ' ' || c.relname || ' ' || t.tgenabled::text
    from pg_trigger t join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('brain','public') and not t.tgisinternal
  union all
  select 'CON :: ' || conname || ' ' || pg_get_constraintdef(con.oid) from pg_constraint con
    join pg_namespace n on n.oid=con.connamespace where n.nspname='brain'
) t;
