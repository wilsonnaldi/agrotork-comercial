-- ============================================================
-- `brain.dependentes_externos()` — quem, de fora do schema `brain`,
-- depende de alguma coisa dentro dele.
--
-- Existe porque a versão anterior olhava só `pg_class` e por isso enxergava
-- tabela e nada mais. View, chave estrangeira, policy, default de coluna e
-- função de corpo padrão ficavam invisíveis — e `drop schema … cascade`
-- levaria todas embora sem avisar.
--
-- ── O QUE ELA ENXERGA ───────────────────────────────────────
-- Tudo que o `pg_depend` registra, resolvendo o schema do DEPENDENTE por
-- `classid`: tabela e view (`pg_class`), regra de view (`pg_rewrite`),
-- função (`pg_proc`), tipo (`pg_type`), restrição (`pg_constraint`),
-- gatilho (`pg_trigger`), default de coluna (`pg_attrdef`) e policy
-- (`pg_policy`). Um `classid` que ela não conheça volta como
-- `(desconhecido)` e **conta como dependente** — na dúvida, barra.
--
-- ── O QUE ELA NÃO ENXERGA, e por quê ────────────────────────
-- Função de corpo CLÁSSICO (`as $$ … $$`) e função plpgsql NÃO registram
-- dependência nenhuma no catálogo: o corpo é texto, resolvido em tempo de
-- execução. Medido:
--
--   corpo clássico              → 0 linhas em pg_depend
--   corpo padrão (BEGIN ATOMIC) → 1 linha em pg_depend
--
-- Por isso existe a segunda peneira, `brain.funcoes_que_citam_brain()`:
-- varre o TEXTO de toda função fora do schema atrás de `brain.`. É
-- grosseira — pega menção em comentário — e é o que há. As duas juntas
-- cobrem o que o catálogo sabe e o que só o texto conta.
-- ============================================================

create or replace function brain.schema_do_objeto(p_classid oid, p_objid oid)
returns text language sql stable security definer set search_path = '' as $$
  select case p_classid
    when 'pg_catalog.pg_class'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = p_objid)
    when 'pg_catalog.pg_proc'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where p.oid = p_objid)
    when 'pg_catalog.pg_type'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid = t.typnamespace where t.oid = p_objid)
    when 'pg_catalog.pg_constraint'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_constraint c join pg_catalog.pg_namespace n on n.oid = c.connamespace where c.oid = p_objid)
    when 'pg_catalog.pg_trigger'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where t.oid = p_objid)
    when 'pg_catalog.pg_rewrite'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_rewrite r join pg_catalog.pg_class c on c.oid = r.ev_class
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where r.oid = p_objid)
    when 'pg_catalog.pg_attrdef'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_attrdef a join pg_catalog.pg_class c on c.oid = a.adrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where a.oid = p_objid)
    when 'pg_catalog.pg_policy'::pg_catalog.regclass then
      (select n.nspname from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid = p.polrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace where p.oid = p_objid)
    when 'pg_catalog.pg_namespace'::pg_catalog.regclass then
      (select nspname from pg_catalog.pg_namespace where oid = p_objid)
    else null
  end;
$$;

create or replace function brain.dependentes_externos()
returns table (schema_dependente text, dependente text, tipo_dependencia "char")
language sql stable security definer set search_path = '' as $$
  select coalesce(brain.schema_do_objeto(d.classid, d.objid), '(desconhecido)'),
         pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid),
         d.deptype
    from pg_catalog.pg_depend d
   where d.refobjid in (
           select c.oid from pg_catalog.pg_class c where c.relnamespace = 'brain'::pg_catalog.regnamespace
           union all
           select p.oid from pg_catalog.pg_proc p where p.pronamespace = 'brain'::pg_catalog.regnamespace
           union all
           select t.oid from pg_catalog.pg_type t where t.typnamespace = 'brain'::pg_catalog.regnamespace
           union all
           select n.oid from pg_catalog.pg_namespace n where n.nspname = 'brain')
     and d.deptype in ('n', 'a')
     and coalesce(brain.schema_do_objeto(d.classid, d.objid), '(desconhecido)') is distinct from 'brain'
   group by 1, 2, 3;
$$;

create or replace function brain.funcoes_que_citam_brain()
returns table (funcao text, linguagem text)
language sql stable security definer set search_path = '' as $$
  select n.nspname || '.' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
         l.lanname::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    join pg_catalog.pg_language l on l.oid = p.prolang
   where n.nspname not in ('brain', 'pg_catalog', 'information_schema')
     and p.prosrc ~ '\mbrain\.';
$$;

revoke execute on function brain.schema_do_objeto(oid, oid)  from public, anon, authenticated;
revoke execute on function brain.dependentes_externos()      from public, anon;
revoke execute on function brain.funcoes_que_citam_brain()   from public, anon;
grant  execute on function brain.dependentes_externos()      to authenticated, service_role;
grant  execute on function brain.funcoes_que_citam_brain()   to authenticated, service_role;

comment on function brain.dependentes_externos() is
  'Objetos fora do schema brain que dependem de algo dentro dele, pelo catalogo. classid desconhecido conta como dependente — na duvida, barra.';
comment on function brain.funcoes_que_citam_brain() is
  'Segunda peneira: funcao fora do brain cujo TEXTO cita brain. — funcao de corpo classico e plpgsql nao registram dependencia no catalogo.';
