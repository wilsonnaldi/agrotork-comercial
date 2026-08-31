select json_build_object(
  'tables', (
    select coalesce(json_agg(t order by t->>'name'), '[]'::json) from (
      select json_build_object(
        'name', c.relname,
        'kind', case c.relkind when 'v' then 'view' when 'm' then 'view' else 'table' end,
        'columns', (
          select json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'udt', tt.typname,
            'is_enum', tt.typtype = 'e',
            'notnull', a.attnotnull,
            'has_default', (pg_get_expr(d.adbin, d.adrelid) is not null) or a.attidentity <> ''
          ) order by a.attnum)
          from pg_attribute a
          join pg_type tt on tt.oid = a.atttypid
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        )
      ) as t
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r','v','m')
    ) s
  ),
  'enums', (
    select coalesce(json_agg(json_build_object('name', t.typname,
      'values', (select json_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid))
      order by t.typname), '[]'::json)
    from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname='public' and t.typtype='e'
  ),
  'fks', (
    select coalesce(json_agg(json_build_object(
      'name', con.conname,
      'table', cl.relname,
      'columns', (select json_agg(att.attname order by u.ord) from unnest(con.conkey) with ordinality u(attnum, ord)
                   join pg_attribute att on att.attrelid = cl.oid and att.attnum = u.attnum),
      'ref_table', rcl.relname,
      'ref_columns', (select json_agg(att.attname order by u.ord) from unnest(con.confkey) with ordinality u(attnum, ord)
                   join pg_attribute att on att.attrelid = rcl.oid and att.attnum = u.attnum),
      'is_one_to_one', exists (
        select 1 from pg_index i where i.indrelid = cl.oid and i.indisunique
          and (select array_agg(x order by x) from unnest(i.indkey::int[]) x) = (select array_agg(x order by x) from unnest(con.conkey::int[]) x)
      )) order by cl.relname, con.conname), '[]'::json)
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_class rcl on rcl.oid = con.confrelid
    join pg_namespace n on n.oid = cl.relnamespace
    where con.contype='f' and n.nspname='public'
  ),
  'functions', (
    select coalesce(json_agg(json_build_object(
      'name', p.proname,
      'args', pg_get_function_arguments(p.oid),
      'returns', pg_get_function_result(p.oid)) order by p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and not exists (select 1 from pg_depend dep where dep.objid=p.oid and dep.deptype='e')
  )
);
