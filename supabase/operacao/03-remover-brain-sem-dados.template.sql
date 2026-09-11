-- ============================================================
-- REMOVER O BRAIN LOGO APÓS O DEPLOY — e só se não houver NADA dentro
--
-- Caminho de volta para a janela curta entre o COMMIT e o primeiro uso.
-- Ele APAGA o schema `brain` inteiro, então só roda se provar que não há
-- nada a perder.
--
-- ── O QUE MUDOU NA v5 ───────────────────────────────────────
--
-- A versão anterior tolerava eventos com `source = 'erp'`, tratando-os
-- como "reconstituíveis". Não são: um `order.created` é o registro de uma
-- venda que aconteceu, com total, número e horário. Agora **qualquer
-- linha** nas nove tabelas — evento do ERP incluído — barra a remoção. O
-- único conteúdo tolerado é a semente de 12 canais, que a própria
-- migration criou.
--
-- E a detecção de dependentes deixou de olhar só tabela. Agora usa
-- `brain.dependentes_externos()` (catálogo: view, FK, policy, default,
-- gatilho, função de corpo padrão) e `brain.funcoes_que_citam_brain()`
-- (texto: função clássica e plpgsql, que o catálogo não registra).
--
-- COMO RODAR: `psql -v ON_ERROR_STOP=1 -f` este arquivo. Ver
-- supabase/operacao/README.md.
-- ============================================================

-- Sem `\set ON_ERROR_STOP`: aquilo é meta-comando do psql e o SQL Editor
-- não entende. Não faz falta — este roteiro é UMA transação, e qualquer
-- exceção aborta tudo; o `commit` lá embaixo executa como `rollback`.
begin;

-- ── Só se não houver NADA a perder ──────────────────────────
do $$
declare
  v_leads int; v_inter int; v_opp int; v_tasks int; v_ident int;
  v_merges int; v_attr int; v_eventos int; v_canais int;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe — nada a remover. PARADO.';
  end if;
  -- A Fase 2 mora no mesmo schema. Se o Lote A (memoria corporativa) estiver
  -- aplicado, derrubar o schema levaria as sete tabelas dele junto, e este
  -- roteiro so confere as nove da Fase 1. Primeiro 06-remover-memoria-sem-dados.sql.
  if to_regclass('brain.document_chunks') is not null then
    raise exception 'A memoria corporativa (Fase 2, Lote A) esta aplicada neste schema. Rode 06-remover-memoria-sem-dados.sql antes. PARADO.';
  end if;

  select count(*) into v_leads   from brain.leads;
  select count(*) into v_inter   from brain.interactions;
  select count(*) into v_opp     from brain.opportunities;
  select count(*) into v_tasks   from brain.tasks;
  select count(*) into v_ident   from brain.identities;
  select count(*) into v_merges  from brain.lead_merges;
  select count(*) into v_attr    from brain.attributions;
  select count(*) into v_eventos from brain.events;
  select count(*) into v_canais  from brain.channels;

  if v_leads + v_inter + v_opp + v_tasks + v_ident + v_merges + v_attr + v_eventos > 0 then
    raise exception
      'O BRAIN TEM CONTEUDO: % lead(s), % interacao(oes), % oportunidade(s), % tarefa(s), % identidade(s), % fusao(oes), % atribuicao(oes), % EVENTO(S). Evento do ERP e o registro de uma venda que aconteceu — nao e descartavel. Use 04-incidente-com-dados.sql. PARADO.',
      v_leads, v_inter, v_opp, v_tasks, v_ident, v_merges, v_attr, v_eventos;
  end if;

  -- Os 12 canais são semente da própria migration, não uso.
  if v_canais <> 12 then
    raise exception 'brain.channels tem % linha(s) e a semente sao 12 — alguem mexeu. PARADO.', v_canais;
  end if;

  raise notice 'Nove tabelas vazias e os 12 canais de semente. Nada a perder.';
end
$$;

-- ── Quem depende do schema, pelas duas peneiras ─────────────
do $$
declare v_estranho text; v_texto text; v_trig int;
begin
  select string_agg(dependente, E'\n    ' order by dependente) into v_estranho
    from brain.dependentes_externos()
   where dependente not in ('trigger trg_brain_quotes on table public.quotes',
                            'trigger trg_brain_orders on table public.orders',
                            'trigger trg_brain_orders_created on table public.orders');
  if v_estranho is not null then
    raise exception E'Dependente fora do brain, alem dos 3 gatilhos conhecidos:\n    %\nNao se derruba o schema as cegas — resolva a mao. PARADO.', v_estranho;
  end if;

  select string_agg(funcao || ' [' || linguagem || ']', E'\n    ' order by funcao) into v_texto
    from brain.funcoes_que_citam_brain();
  if v_texto is not null then
    raise exception E'Funcao fora do brain que CITA brain. no texto (o catalogo nao registra essa dependencia):\n    %\nEla quebraria em silencio depois do drop. PARADO.', v_texto;
  end if;

  select count(*) into v_trig from pg_trigger
   where tgname in ('trg_brain_quotes','trg_brain_orders','trg_brain_orders_created');
  if v_trig <> 3 then
    raise exception 'Esperava exatamente os 3 gatilhos conhecidos, achei % — PARADO.', v_trig;
  end if;

  raise notice 'Dependencias: so os 3 gatilhos da ponte, e nenhuma funcao citando brain no texto.';
end
$$;

-- ── Concorrência: falhar rápido em vez de travar a fila ─────
-- `drop trigger` pede ACCESS EXCLUSIVE em `quotes` e `orders`. Numa base
-- com movimento, esperar por esse lock enfileira TODO MUNDO atrás. Com
-- `lock_timeout` a espera vira erro em 3s, a transação aborta e nada fica
-- pela metade — é só tentar de novo num momento mais calmo.
set local lock_timeout = '3s';

drop trigger if exists trg_brain_quotes         on public.quotes;
drop trigger if exists trg_brain_orders         on public.orders;
drop trigger if exists trg_brain_orders_created on public.orders;

-- O CASCADE aqui só alcança o que é do próprio `brain` — foi isso que os
-- dois blocos acima acabaram de provar.
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

-- @incluir supabase/operacao/audit_capture-antes-do-brain.sql

revoke execute on function public.audit_capture() from public, anon, authenticated;

delete from supabase_migrations.schema_migrations
 where version in ('20260911130000','20260911140000','20260911150000',
                   '20260911160000','20260911170000','20260911180000',
                   '20260911190000','20260911200000','20260911210000',
                   '20260911220000');

-- ── Fim de linha: CRLF vira LF antes de conferir o md5 ──────
-- Mesmo motivo do roteiro 02: este arquivo é colado no SQL Editor e o
-- editor do navegador normaliza a quebra de linha para CRLF. Como
-- `audit_capture()` é definida dentro de `$$ … $$`, o `\r` entraria no
-- corpo e mudaria o md5 — a pós-condição abaixo reprovaria uma restauração
-- que está semanticamente certa. Reescreve-se a função sem os `\r`, para
-- o texto em produção ser o texto auditado.
do $$
declare v_oid oid;
begin
  select p.oid into v_oid
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture'
     and pg_catalog.strpos(p.prosrc, pg_catalog.chr(13)) > 0;
  if v_oid is not null then
    execute pg_catalog.replace(pg_catalog.pg_get_functiondef(v_oid), pg_catalog.chr(13), '');
    raise notice 'Fim de linha: o roteiro chegou com CRLF e audit_capture() foi reescrita com LF.';
  end if;
end
$$;

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
   where version like '20260911%';
  if v_n <> 0 then raise exception 'O registro do BRAIN nao saiu — PARADO.'; end if;

  perform 1 from public.quotes limit 1;
  perform 1 from public.orders limit 1;

  raise notice 'BRAIN removido, audit_capture restaurada, registro limpo. Pronto para COMMIT.';
end
$$;

commit;
