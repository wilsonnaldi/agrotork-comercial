-- ============================================================
-- RECONCILIAR O REGISTRO DE MIGRATIONS — projeto nedmdkdhchkadijtdnja
--
-- O problema: nove migrations de 09/09 foram APLICADAS, mas a ferramenta
-- gravou a HORA DA EXECUÇÃO no lugar da VERSÃO DO ARQUIVO. Enquanto isso
-- não for acertado, `supabase db push` acha que as nove faltam, tenta
-- aplicar de novo e falha em "already exists".
--
-- ── COMO ESTE SCRIPT SE COMPORTA ────────────────────────────
--
-- Ele é UMA transação. Toda conferência é feita dentro de um bloco
-- `do $$ ... $$` que levanta exceção — e exceção dentro de transação
-- aborta a transação inteira. Não existe aqui "SELECT de conferência
-- seguido de COMMIT": se alguma pré ou pós-condição não bater, NADA é
-- gravado.
--
-- Antes de tocar em qualquer linha ele guarda uma CÓPIA INTEGRAL do
-- registro numa tabela datada, e confere que a cópia tem o mesmo número
-- de linhas do original.
--
-- Cada uma das nove linhas cai em exatamente um destes casos:
--   · POR ACERTAR   — existe com a versão errada e o nome de origem certo;
--   · JÁ ACERTADA   — existe com a versão certa e nenhuma linha errada;
--   · INCONSISTENTE — qualquer outra coisa: nome que não bate, versão de
--                     destino ocupada por outra linha, as duas presentes,
--                     nenhuma das duas. Aí ele PARA.
--
-- Rodar duas vezes é seguro: na segunda todas caem em JÁ ACERTADA e a
-- transação confirma sem alterar nada.
--
-- ── O QUE ELE NÃO FAZ ───────────────────────────────────────
--
-- Não registra o BRAIN. A versão 20260911130000 só entra quando a
-- aplicação estiver PROVADA — e quem prova isso é
-- supabase/operacao/02-aplicar-brain.sql, que registra no mesmo COMMIT
-- em que aplica. Registrar aqui seria afirmar um fato que não aconteceu.
--
-- Não mexe nas duas migrations do `instagram_curator` (20260910151115 e
-- 20260910151534): elas estão CERTAS em produção. O que faltava era o
-- arquivo no Git, e isso foi resolvido recuperando o texto original de
-- `statements` — não mexendo no registro.
-- ============================================================

begin;

-- ── Cópia integral, antes de qualquer escrita ───────────────
do $$
declare
  v_tabela text := 'schema_migrations_antes_20260911';
  v_origem int;
  v_copia  int;
begin
  if to_regclass('supabase_migrations.' || v_tabela) is not null then
    raise exception 'A copia %.% ja existe. Confira-a antes de rodar de novo: se for de uma tentativa anterior, renomeie-a.',
      'supabase_migrations', v_tabela using errcode = 'duplicate_table';
  end if;

  execute format('create table supabase_migrations.%I as select * from supabase_migrations.schema_migrations', v_tabela);

  select count(*) into v_origem from supabase_migrations.schema_migrations;
  execute format('select count(*) from supabase_migrations.%I', v_tabela) into v_copia;
  if v_origem <> v_copia then
    raise exception 'A copia saiu com % linhas e o original tem % — abortado antes de tocar em nada', v_copia, v_origem;
  end if;
  raise notice 'Copia integral guardada em supabase_migrations.% (% linhas)', v_tabela, v_copia;
end
$$;

-- ── As nove, uma a uma, com veredito por linha ──────────────
do $$
declare
  r record;
  v_errada   int;
  v_certa    int;
  v_nome_ok  int;
  v_mexidas  int;
  v_acertar  int := 0;
  v_ja       int := 0;
  v_afetadas int;
  v_total_antes int;
  v_total_depois int;
begin
  select count(*) into v_total_antes from supabase_migrations.schema_migrations;

  for r in
    select * from (values
      ('20260909143542', '20260903100000_suppliers'                 , '20260903100000', 'suppliers'),
      ('20260909143713', '20260903110000_excluir_cliente'           , '20260903110000', 'excluir_cliente'),
      ('20260909143758', '20260903120000_estoque'                   , '20260903120000', 'estoque'),
      ('20260909143830', '20260903130000_numeros_de_serie'          , '20260903130000', 'numeros_de_serie'),
      ('20260909143930', '20260903140000_compras'                   , '20260903140000', 'compras'),
      ('20260909144028', '20260903150000_financeiro'                , '20260903150000', 'financeiro'),
      ('20260909144051', '20260903160000_importacao_nfe'            , '20260903160000', 'importacao_nfe'),
      ('20260909144232', '20260909100000_guards_orcamentos_pedidos' , '20260909100000', 'guards_orcamentos_pedidos'),
      ('20260909144344', '20260909110000_guards_onda2'              , '20260909110000', 'guards_onda2')
    ) as v(origem_versao, origem_nome, destino_versao, destino_nome)
  loop
    select count(*) into v_errada from supabase_migrations.schema_migrations where version = r.origem_versao;
    select count(*) into v_certa  from supabase_migrations.schema_migrations where version = r.destino_versao;
    select count(*) into v_nome_ok from supabase_migrations.schema_migrations
     where version = r.origem_versao and name = r.origem_nome;

    -- JÁ ACERTADA: destino ocupado, origem ausente.
    if v_errada = 0 and v_certa = 1 then
      v_ja := v_ja + 1;
      continue;
    end if;

    -- INCONSISTENTE: nenhuma das duas existe.
    if v_errada = 0 and v_certa = 0 then
      raise exception 'ESTADO INESPERADO em %: nao existe nem a versao errada (%) nem a certa. O registro nao e o que esta auditoria descreveu — nada foi gravado.',
        r.destino_nome, r.origem_versao using errcode = 'data_exception';
    end if;

    -- INCONSISTENTE: as duas existem (aplicada duas vezes?).
    if v_errada = 1 and v_certa = 1 then
      raise exception 'ESTADO INESPERADO em %: existem AS DUAS versoes, % e %. Isso e conflito de destino e precisa de olho humano — nada foi gravado.',
        r.destino_nome, r.origem_versao, r.destino_versao using errcode = 'unique_violation';
    end if;

    -- INCONSISTENTE: origem duplicada.
    if v_errada > 1 then
      raise exception 'ESTADO INESPERADO em %: % linhas com a versao % — nada foi gravado.',
        r.destino_nome, v_errada, r.origem_versao using errcode = 'data_exception';
    end if;

    -- INCONSISTENTE: a versão errada está lá, mas com outro nome.
    if v_nome_ok <> 1 then
      raise exception 'ESTADO INESPERADO em %: a versao % existe mas o nome nao e "%" — e outra migration, nao esta. Nada foi gravado.',
        r.destino_nome, r.origem_versao, r.origem_nome using errcode = 'data_exception';
    end if;

    -- POR ACERTAR: o único caso que escreve.
    update supabase_migrations.schema_migrations
       set version = r.destino_versao, name = r.destino_nome
     where version = r.origem_versao and name = r.origem_nome;

    get diagnostics v_afetadas = row_count;
    if v_afetadas <> 1 then
      raise exception 'O UPDATE de % afetou % linha(s) em vez de 1 — nada foi gravado.',
        r.destino_nome, v_afetadas using errcode = 'data_exception';
    end if;
    v_acertar := v_acertar + 1;
  end loop;

  -- ── Pós-condições ────────────────────────────────────────
  select count(*) into v_total_depois from supabase_migrations.schema_migrations;
  if v_total_depois <> v_total_antes then
    raise exception 'O total de linhas mudou de % para % — nada foi gravado.', v_total_antes, v_total_depois;
  end if;

  select count(*) into v_mexidas from supabase_migrations.schema_migrations
   where version like '2026090914%';
  if v_mexidas <> 0 then
    raise exception 'Sobraram % linha(s) com versao de hora de execucao — nada foi gravado.', v_mexidas;
  end if;

  if v_acertar + v_ja <> 9 then
    raise exception 'Contabilidade errada: % acertadas + % ja acertadas <> 9 — nada foi gravado.', v_acertar, v_ja;
  end if;

  raise notice 'Nove conferidas: % acertada(s) agora, % ja estava(m) certa(s).', v_acertar, v_ja;
end
$$;

-- ── Git e produção têm de falar a mesma lista ───────────────
-- A lista abaixo é o conjunto de versões dos arquivos em
-- supabase/migrations, exceto a do BRAIN, que ainda não foi aplicada.
do $$
declare
  v_so_no_git  text;
  v_so_no_banco text;
begin
  create temporary table versoes_do_git (version text primary key) on commit drop;
  insert into versoes_do_git (version) values
    ('20260829000100'),
  ('20260829000200'),
  ('20260829000300'),
  ('20260829000400'),
  ('20260829000500'),
  ('20260829000600'),
  ('20260829000700'),
  ('20260829000800'),
  ('20260829000900'),
  ('20260829001000'),
  ('20260829001100'),
  ('20260829001200'),
  ('20260829001300'),
  ('20260829001400'),
  ('20260829001500'),
  ('20260829001600'),
  ('20260829001700'),
  ('20260829001800'),
  ('20260829001900'),
  ('20260829002000'),
  ('20260831002100'),
  ('20260901052518'),
  ('20260901052525'),
  ('20260901055000'),
  ('20260901060000'),
  ('20260901190230'),
  ('20260901190334'),
  ('20260901191225'),
  ('20260901193812'),
  ('20260901193926'),
  ('20260901194546'),
  ('20260901195103'),
  ('20260901201459'),
  ('20260901211122'),
  ('20260901211340'),
  ('20260901214750'),
  ('20260902120000'),
  ('20260902120100'),
  ('20260903020000'),
  ('20260903040000'),
  ('20260903060000'),
  ('20260903080000'),
  ('20260903100000'),
  ('20260903110000'),
  ('20260903120000'),
  ('20260903130000'),
  ('20260903140000'),
  ('20260903150000'),
  ('20260903160000'),
  ('20260909100000'),
  ('20260909110000'),
  ('20260910151115'),
  ('20260910151534'),
  ('20260911130000'),
  ('20260911140000'),
  ('20260911150000');

  -- O BRAIN ainda não foi aplicado: sai da comparação, e a ausência dele
  -- no banco é conferida explicitamente logo abaixo.
  delete from versoes_do_git where version in ('20260911130000', '20260911140000', '20260911150000');

  select string_agg(g.version, ', ' order by g.version) into v_so_no_git
    from versoes_do_git g
   where not exists (select 1 from supabase_migrations.schema_migrations m where m.version = g.version);

  select string_agg(m.version, ', ' order by m.version) into v_so_no_banco
    from supabase_migrations.schema_migrations m
   where not exists (select 1 from versoes_do_git g where g.version = m.version);

  if v_so_no_git is not null then
    raise exception 'Arquivo no Git sem registro no banco: % — nada foi gravado.', v_so_no_git;
  end if;
  if v_so_no_banco is not null then
    raise exception 'Registro no banco sem arquivo no Git: % — e exatamente a divergencia que esta rodada veio eliminar. Nada foi gravado.', v_so_no_banco;
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations
              where version in ('20260911130000', '20260911140000', '20260911150000')) then
    raise exception 'O BRAIN aparece como aplicado e nao deveria — quem registra isso e 02-aplicar-brain.sql, no mesmo COMMIT em que aplica. Nada foi gravado.';
  end if;

  raise notice 'Git e producao coincidem: % versoes, nenhuma sobrando dos dois lados.',
    (select count(*) from versoes_do_git);
end
$$;

commit;

-- Depois do COMMIT, a cópia continua em
-- supabase_migrations.schema_migrations_antes_20260911. Ela é o caminho
-- de volta: `truncate` + `insert select` a partir dela restaura o
-- registro exatamente como estava.
