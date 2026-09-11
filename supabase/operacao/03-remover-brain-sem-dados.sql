-- ============================================================
-- REMOVER O BRAIN LOGO APÓS O DEPLOY — sem dado real dentro
--
-- Este é o caminho de volta para a janela curta entre o COMMIT e o
-- primeiro uso: a Fase 1 entrou, alguma coisa não convenceu, e ninguém
-- chegou a usar o CRM. Ele APAGA o schema `brain` inteiro, e por isso
-- só roda se provar, antes, que não há nada que valha a pena guardar.
--
-- Se já houver lead, interação, oportunidade, tarefa, identidade, fusão
-- ou atribuição, ele PARA e manda usar 04-incidente-com-dados.sql.
--
-- Uma transação, com conferência impeditiva antes e depois.
--
-- O que ele NÃO faz:
--   · não usa `drop schema ... cascade` às cegas: antes de derrubar,
--     lista o que depende do schema e recusa qualquer dependente que
--     não seja do próprio `brain` ou um dos três gatilhos conhecidos;
--   · não sobrescreve uma `audit_capture()` mais nova: se o md5 não for
--     o que o BRAIN deixou, alguém a mudou depois e a restauração
--     pararia em cima de trabalho alheio.
-- ============================================================

begin;

-- ── Só se não houver nada a perder ──────────────────────────
do $$
declare
  v_leads int; v_inter int; v_opp int; v_tasks int; v_ident int;
  v_merges int; v_attr int; v_ev_app int; v_ev_erp int;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe — nada a remover. PARADO.';
  end if;

  select count(*) into v_leads  from brain.leads;
  select count(*) into v_inter  from brain.interactions;
  select count(*) into v_opp    from brain.opportunities;
  select count(*) into v_tasks  from brain.tasks;
  select count(*) into v_ident  from brain.identities;
  select count(*) into v_merges from brain.lead_merges;
  select count(*) into v_attr   from brain.attributions;
  select count(*) into v_ev_app from brain.events where source <> 'erp';
  select count(*) into v_ev_erp from brain.events where source = 'erp';

  if v_leads + v_inter + v_opp + v_tasks + v_ident + v_merges + v_attr + v_ev_app > 0 then
    raise exception
      'O BRAIN JA TEM DADO: % lead(s), % interacao(oes), % oportunidade(s), % tarefa(s), % identidade(s), % fusao(oes), % atribuicao(oes), % evento(s) fora do ERP. Este roteiro apagaria tudo isso. Use 04-incidente-com-dados.sql — PARADO.',
      v_leads, v_inter, v_opp, v_tasks, v_ident, v_merges, v_attr, v_ev_app;
  end if;

  raise notice 'Sem dado de CRM. Ha % evento(s) publicados pela ponte do ERP, que sao reconstituiveis por brain.repor_eventos_erp() depois. Seguindo.', v_ev_erp;
end
$$;

-- ── O que depende do schema, antes de derrubar ──────────────
do $$
declare
  v_estranho text;
  v_dependentes int;
begin
  -- Objetos FORA de `brain` que dependem de algo DENTRO de `brain`.
  -- Os únicos aceitáveis são os três gatilhos da ponte.
  select string_agg(distinct format('%s %s', d.classid::regclass, d.objid::regclass), ', ')
    into v_estranho
    from pg_depend d
    join pg_class dep on dep.oid = d.objid
    join pg_namespace ndep on ndep.oid = dep.relnamespace
   where ndep.nspname <> 'brain'
     and d.refobjid in (
       select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'brain'
     )
     and d.deptype <> 'i';

  if v_estranho is not null then
    raise exception 'Ha objeto fora do brain dependendo dele: %. Nao se derruba o schema as cegas — PARADO.', v_estranho;
  end if;

  select count(*) into v_dependentes from pg_trigger
   where tgname in ('trg_brain_quotes','trg_brain_orders','trg_brain_orders_created');
  if v_dependentes <> 3 then
    raise exception 'Esperava exatamente os 3 gatilhos conhecidos em public, achei % — PARADO.', v_dependentes;
  end if;

  raise notice 'Dependencias externas: so os 3 gatilhos da ponte, que saem antes do schema.';
end
$$;

drop trigger if exists trg_brain_quotes         on public.quotes;
drop trigger if exists trg_brain_orders         on public.orders;
drop trigger if exists trg_brain_orders_created on public.orders;

-- Agora o CASCADE só alcança o que é do próprio `brain` — foi isso que
-- o bloco acima acabou de provar.
drop schema brain cascade;

-- ── `audit_capture()` volta ao texto anterior ao BRAIN ──────
do $$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from 'ee2f5cd583295c30fbe64eb81eec2d9e' then
    raise exception
      'audit_capture() esta em md5 % e o BRAIN a deixou em ee2f5cd583295c30fbe64eb81eec2d9e. Alguem a mudou depois: restaurar a copia historica APAGARIA esse trabalho. Resolva a mao — PARADO.', v_md5;
  end if;
end
$$;

\i supabase/operacao/audit_capture-antes-do-brain.sql

revoke execute on function public.audit_capture() from public, anon, authenticated;

delete from supabase_migrations.schema_migrations
 where version in ('20260911130000','20260911140000','20260911150000');

-- ── Pós-condições ───────────────────────────────────────────
do $$
declare v_md5 text; v_n int;
begin
  if exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain continua existindo — PARADO.';
  end if;
  select count(*) into v_n from pg_trigger where tgname like 'trg_brain%';
  if v_n <> 0 then raise exception 'Sobraram % gatilho(s) do brain — PARADO.', v_n; end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from '24fd65a7eb791b2e2644abe1b2ba876b' then
    raise exception 'audit_capture() ficou em md5 % e o esperado era 24fd65a7eb791b2e2644abe1b2ba876b — PARADO.', v_md5;
  end if;

  select count(*) into v_n from supabase_migrations.schema_migrations
   where version in ('20260911130000','20260911140000','20260911150000');
  if v_n <> 0 then raise exception 'O registro do BRAIN nao saiu — PARADO.'; end if;

  -- O ERP tem de continuar de pé.
  perform 1 from public.quotes limit 1;
  perform 1 from public.orders limit 1;

  raise notice 'BRAIN removido, audit_capture restaurada no md5 original, registro limpo. Pronto para COMMIT.';
end
$$;

commit;
