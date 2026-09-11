-- ============================================================
-- Comparador do schema `instagram_curator`.
--
-- Produz UMA linha por objeto, no formato
--     CATEGORIA :: objeto :: md5(definição normalizada)
-- ordenada, para que dois bancos possam ser comparados por `diff` —
-- inclusive entre versões diferentes do PostgreSQL, e inclusive contra
-- produção, onde só se pode LER.
--
-- Cobre: colunas (tipo, nulidade, identidade, default), restrições,
-- índices, enums, funções, gatilhos, policies, RLS, ACL de tabela,
-- sequência, função e schema, privilégios padrão e COMENTÁRIOS.
--
-- ── Normalizações, uma a uma ────────────────────────────────
--
-- 1. Espaços em branco viram um espaço só. `pg_get_constraintdef()` e
--    `pg_get_functiondef()` quebram linha em pontos diferentes conforme
--    a versão; a quebra não é estrutura.
--
-- 2. `arwdDxtm` → `arwdDxt` na ACL do DONO. O PostgreSQL 17 acrescentou
--    o privilégio MAINTAIN (`m`) — VACUUM, ANALYZE, REINDEX, CLUSTER,
--    REFRESH — e o concede ao dono junto com os demais. No PostgreSQL 16
--    esse privilégio NÃO EXISTE. É diferença de versão do servidor, não
--    de estrutura do schema: nenhuma migration concede ou revoga
--    MAINTAIN, e a ACL de `service_role` (`arwd`) é idêntica nos dois.
--    Sem esta normalização, comparar um banco 16 com produção 17
--    acusaria 7 divergências falsas.
--
-- Nada mais é normalizado. Em particular, NÃO se normaliza tipo, default,
-- nulidade, corpo de função, predicado de índice, papel de policy nem
-- comentário: aí uma diferença é diferença.
-- ============================================================
with itens as (
  select 'COLUNA'::text as k,
         c.relname::text || '.' || a.attname as o,
         (pg_catalog.format_type(a.atttypid, a.atttypmod)
          || case when a.attnotnull then ' NOT NULL' else '' end
          || case when a.attidentity <> '' then ' IDENTITY:' || a.attidentity::text else '' end
          || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), ''))::text as v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
  union all
  select 'RESTRICAO', con.conrelid::regclass::text || ' ' || con.conname, pg_get_constraintdef(con.oid)
    from pg_constraint con join pg_class r on r.oid = con.conrelid
    join pg_namespace n on n.oid = r.relnamespace where n.nspname = 'instagram_curator'
  union all
  select 'INDICE', tablename || ' ' || indexname, indexdef
    from pg_indexes where schemaname = 'instagram_curator'
  union all
  select 'ENUM', t.typname, string_agg(e.enumlabel, ',' order by e.enumsortorder)
    from pg_type t join pg_namespace n on n.oid = t.typnamespace join pg_enum e on e.enumtypid = t.oid
   where n.nspname = 'instagram_curator' group by t.typname
  union all
  select 'FUNCAO', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'instagram_curator'
  union all
  select 'GATILHO', t.tgrelid::regclass::text || ' ' || t.tgname, pg_get_triggerdef(t.oid)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and not t.tgisinternal
  union all
  select 'POLICY', tablename || ' ' || policyname,
         cmd || '|' || array_to_string(roles, ',') || '|' || coalesce(qual, '-') || '|' || coalesce(with_check, '-')
    from pg_policies where schemaname = 'instagram_curator'
  union all
  select 'RLS', c.relname, c.relrowsecurity::text || '/' || c.relforcerowsecurity::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
  union all
  select 'ACL', c.relkind::text || ' ' || c.relname,
         replace(coalesce(array_to_string(c.relacl, ' '), '(dono)'), 'arwdDxtm', 'arwdDxt')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind in ('r', 'S')
  union all
  select 'ACL FUNCAO', p.proname, coalesce(array_to_string(p.proacl, ' '), '(publico)')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'instagram_curator'
  union all
  select 'ACL SCHEMA', 'instagram_curator', coalesce(array_to_string(nspacl, ' '), '(dono)')
    from pg_namespace where nspname = 'instagram_curator'
  union all
  select 'PRIV PADRAO', d.defaclobjtype::text, array_to_string(d.defaclacl, ' ')
    from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
   where n.nspname = 'instagram_curator'
  union all
  select 'COMENTARIO SCHEMA', 'instagram_curator', obj_description(n.oid, 'pg_namespace')
    from pg_namespace n where n.nspname = 'instagram_curator'
     and obj_description(n.oid, 'pg_namespace') is not null
  union all
  select 'COMENTARIO TABELA', c.relname, obj_description(c.oid, 'pg_class')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
     and obj_description(c.oid, 'pg_class') is not null
  union all
  select 'COMENTARIO COLUNA', c.relname || '.' || a.attname, col_description(c.oid, a.attnum)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
     and col_description(c.oid, a.attnum) is not null
  union all
  select 'COMENTARIO FUNCAO', p.proname, obj_description(p.oid, 'pg_proc')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator' and obj_description(p.oid, 'pg_proc') is not null
)
select k || $$ :: $$ || o || $$ :: $$ || md5(regexp_replace(v, $$[[:space:]]+$$, $$ $$, $$g$$)) as linha
  from itens order by k, o;
