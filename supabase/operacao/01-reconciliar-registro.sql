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
-- `do $$ … $$` que levanta exceção — e exceção dentro de transação aborta
-- a transação inteira. Não existe aqui "SELECT de conferência seguido de
-- COMMIT": se alguma pré ou pós-condição não bater, NADA é gravado.
--
-- ── O QUE ELE CONFERE EM CADA UMA DAS NOVE ──────────────────
--
-- Não basta a versão. Para cada linha ele confere TRÊS coisas:
--
--   1. a VERSÃO — errada (por acertar) ou certa (já acertada);
--   2. o NOME — tem de ser exatamente o de origem ou o de destino;
--   3. o CONTEÚDO — `statements` tem de existir e conter a MARCA daquela
--      migration: o nome de um objeto que só ela cria. Uma linha com a
--      versão certa e o corpo de outra migration é pior do que uma linha
--      com a versão errada, e sem esta conferência passaria batido.
--
-- A conferência de conteúdo vale **também para as linhas já acertadas**.
-- Rodar de novo não é passar batido: é conferir de novo.
--
-- Por que MARCA e não md5 do arquivo: o `statements` guarda o SQL como a
-- ferramenta o enviou, sem os comentários. Medido em 11/09 — o arquivo
-- `20260903100000_suppliers.sql` tem 7.347 bytes e o `statements` dela
-- tem 4.023. Comparar md5 de arquivo com md5 de `statements` acusaria
-- divergência em todas as nove, sempre. A marca sobrevive à limpeza de
-- comentários e ainda amarra a linha ao arquivo certo.
--
-- Cada linha cai em exatamente um destes casos:
--   · POR ACERTAR   — versão errada, nome de origem certo, marca presente;
--   · JÁ ACERTADA   — versão certa, nome de destino certo, marca presente;
--   · INCONSISTENTE — qualquer outra coisa. Aí ele PARA.
--
-- ── RODAR DUAS VEZES ────────────────────────────────────────
--
-- É seguro e é esperado. Na segunda execução as nove caem em JÁ ACERTADA,
-- as três conferências correm de novo, a transação confirma e **nada
-- muda**. A cópia do registro leva carimbo de hora no nome, então
-- execuções diferentes NÃO brigam e nenhuma sobrescreve a anterior —
-- todas as cópias ficam guardadas.
--
-- ── O QUE ELE NÃO FAZ ───────────────────────────────────────
--
-- Não registra o BRAIN. As versões `202609111…` só entram quando a
-- aplicação estiver PROVADA — e quem prova isso é
-- supabase/operacao/02-aplicar-brain.sql, que registra no mesmo COMMIT em
-- que aplica.
--
-- Não mexe nas duas migrations do `instagram_curator` (20260910151115 e
-- 20260910151534): elas estão CERTAS em produção. O que faltava era o
-- arquivo no Git, resolvido recuperando o texto original de `statements`.
-- ============================================================

begin;

-- ── Cópia integral, antes de qualquer escrita ───────────────
-- O nome leva carimbo de hora: a cópia de uma execução anterior NÃO é
-- sobrescrita nem precisa ser renomeada à mão.
do $$
declare
  v_base   text := 'schema_migrations_antes_' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS');
  v_tabela text := v_base;
  v_sufixo int  := 1;
  v_origem int;
  v_copia  int;
  v_antigas int;
begin
  -- Duas execuções no mesmo segundo não podem brigar, e nenhuma
  -- sobrescreve a anterior: acha-se um nome livre.
  while to_regclass('supabase_migrations.' || v_tabela) is not null loop
    v_sufixo := v_sufixo + 1;
    v_tabela := v_base || '_' || v_sufixo;
    if v_sufixo > 50 then
      raise exception 'Nao achei nome livre para a copia do registro — PARADO.';
    end if;
  end loop;

  execute format('create table supabase_migrations.%I as select * from supabase_migrations.schema_migrations', v_tabela);

  select count(*) into v_origem from supabase_migrations.schema_migrations;
  execute format('select count(*) from supabase_migrations.%I', v_tabela) into v_copia;
  if v_origem <> v_copia then
    raise exception 'A copia saiu com % linhas e o original tem % — abortado antes de tocar em nada', v_copia, v_origem;
  end if;

  select count(*) into v_antigas from pg_tables
   where schemaname = 'supabase_migrations' and tablename like 'schema_migrations\_antes\_%';
  raise notice 'Copia integral em supabase_migrations.% (% linhas). Copias guardadas ate agora: %.',
    v_tabela, v_copia, v_antigas;
end
$$;

-- ── As nove, uma a uma, com veredito por linha ──────────────
do $$
declare
  r record;
  v_errada int; v_certa int; v_afetadas int;
  v_nome text; v_corpo text;
  v_acertar int := 0;
  v_ja      int := 0;
  v_total_antes int;
  v_total_depois int;
  v_sobraram int;
begin
  select count(*) into v_total_antes from supabase_migrations.schema_migrations;

  for r in
    select * from (values
      ('20260909143542', '20260903100000_suppliers'                , '20260903100000', 'suppliers'                , 'suppliers'),
      ('20260909143713', '20260903110000_excluir_cliente'          , '20260903110000', 'excluir_cliente'          , 'delete_customer'),
      ('20260909143758', '20260903120000_estoque'                  , '20260903120000', 'estoque'                  , 'stock_movements'),
      ('20260909143830', '20260903130000_numeros_de_serie'         , '20260903130000', 'numeros_de_serie'         , 'product_serials'),
      ('20260909143930', '20260903140000_compras'                  , '20260903140000', 'compras'                  , 'purchase_items'),
      ('20260909144028', '20260903150000_financeiro'               , '20260903150000', 'financeiro'               , 'financial_entries'),
      ('20260909144051', '20260903160000_importacao_nfe'           , '20260903160000', 'importacao_nfe'           , 'remember_supplier_product'),
      ('20260909144232', '20260909100000_guards_orcamentos_pedidos', '20260909100000', 'guards_orcamentos_pedidos', 'protect_quote_control_columns'),
      ('20260909144344', '20260909110000_guards_onda2'             , '20260909110000', 'guards_onda2'             , 'block_purchase_item_move')
    ) as v(origem_versao, origem_nome, destino_versao, destino_nome, marca)
  loop
    select count(*) into v_errada from supabase_migrations.schema_migrations where version = r.origem_versao;
    select count(*) into v_certa  from supabase_migrations.schema_migrations where version = r.destino_versao;

    if v_errada > 1 then
      raise exception 'ESTADO INESPERADO em %: % linhas com a versao % — nada foi gravado.',
        r.destino_nome, v_errada, r.origem_versao using errcode = 'data_exception';
    end if;
    if v_errada = 1 and v_certa = 1 then
      raise exception 'ESTADO INESPERADO em %: existem AS DUAS versoes, % e %. Conflito de destino, precisa de olho humano — nada foi gravado.',
        r.destino_nome, r.origem_versao, r.destino_versao using errcode = 'unique_violation';
    end if;
    if v_errada = 0 and v_certa = 0 then
      raise exception 'ESTADO INESPERADO em %: nao existe nem a versao errada (%) nem a certa (%). O registro nao e o que esta auditoria descreveu — nada foi gravado.',
        r.destino_nome, r.origem_versao, r.destino_versao using errcode = 'data_exception';
    end if;

    -- ── JÁ ACERTADA: confere nome e conteúdo mesmo assim ────
    if v_certa = 1 then
      select name, array_to_string(statements, '') into v_nome, v_corpo
        from supabase_migrations.schema_migrations where version = r.destino_versao;

      if v_nome is distinct from r.destino_nome then
        raise exception 'ESTADO INESPERADO em %: a versao % existe mas o nome e "%" e nao "%" — nada foi gravado.',
          r.destino_nome, r.destino_versao, coalesce(v_nome, '(nulo)'), r.destino_nome using errcode = 'data_exception';
      end if;
      if v_corpo is null or v_corpo = '' then
        raise exception 'ESTADO INESPERADO em %: a versao % esta registrada SEM conteudo (`statements` vazio) — nao da para afirmar que e esta migration. Nada foi gravado.',
          r.destino_nome, r.destino_versao using errcode = 'data_exception';
      end if;
      if position(r.marca in v_corpo) = 0 then
        raise exception 'ESTADO INESPERADO em %: a versao % esta registrada mas o conteudo nao menciona "%" — e o corpo de OUTRA migration. Nada foi gravado.',
          r.destino_nome, r.destino_versao, r.marca using errcode = 'data_exception';
      end if;

      v_ja := v_ja + 1;
      continue;
    end if;

    -- ── POR ACERTAR: nome e conteúdo antes de escrever ──────
    select name, array_to_string(statements, '') into v_nome, v_corpo
      from supabase_migrations.schema_migrations where version = r.origem_versao;

    if v_nome is distinct from r.origem_nome then
      raise exception 'ESTADO INESPERADO em %: a versao % existe mas o nome nao e "%" — e outra migration, nao esta. Nada foi gravado.',
        r.destino_nome, r.origem_versao, r.origem_nome using errcode = 'data_exception';
    end if;
    if v_corpo is null or v_corpo = '' then
      raise exception 'ESTADO INESPERADO em %: a versao % esta registrada SEM conteudo (`statements` vazio) — nada foi gravado.',
        r.destino_nome, r.origem_versao using errcode = 'data_exception';
    end if;
    if position(r.marca in v_corpo) = 0 then
      raise exception 'ESTADO INESPERADO em %: a versao % existe mas o conteudo nao menciona "%" — e o corpo de OUTRA migration. Nada foi gravado.',
        r.destino_nome, r.origem_versao, r.marca using errcode = 'data_exception';
    end if;

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

  select count(*) into v_sobraram from supabase_migrations.schema_migrations
   where version like '2026090914%';
  if v_sobraram <> 0 then
    raise exception 'Sobraram % linha(s) com versao de hora de execucao — nada foi gravado.', v_sobraram;
  end if;

  if v_acertar + v_ja <> 9 then
    raise exception 'Contabilidade errada: % acertadas + % ja acertadas <> 9 — nada foi gravado.', v_acertar, v_ja;
  end if;

  raise notice 'Nove conferidas em versao, nome e conteudo: % acertada(s) agora, % ja estava(m) certa(s).',
    v_acertar, v_ja;
end
$$;

-- ── Git e produção têm de falar a mesma lista ───────────────
do $$
declare
  v_so_no_git   text;
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
    ('20260911150000'),
    ('20260911160000'),
    ('20260911170000'),
    ('20260911180000');

  -- O BRAIN ainda não foi aplicado: sai da comparação, e a ausência dele
  -- no banco é conferida explicitamente logo abaixo.
  delete from versoes_do_git where version like '202609111%';

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

  if exists (select 1 from supabase_migrations.schema_migrations where version like '202609111%') then
    raise exception 'O BRAIN aparece como aplicado e nao deveria — quem registra isso e 02-aplicar-brain.sql, no mesmo COMMIT em que aplica. Nada foi gravado.';
  end if;

  raise notice 'Git e producao coincidem: % versoes, nenhuma sobrando dos dois lados.',
    (select count(*) from versoes_do_git);
end
$$;

commit;

-- Depois do COMMIT, as cópias ficam em
-- supabase_migrations.schema_migrations_antes_<AAAAMMDDHHMMSS>. Elas são
-- o caminho de volta: `truncate` + `insert select` a partir da mais
-- recente restaura o registro exatamente como estava.
