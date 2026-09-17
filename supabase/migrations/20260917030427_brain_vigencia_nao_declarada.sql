-- ============================================================
-- BRAIN Fase 2 — vigencia NAO declarada deixa de virar data inventada
-- ============================================================
-- O defeito, medido no lote JR Solucoes (docs/brain/fase-2-jr-solucoes.md §4):
--
--   new.valid_from := coalesce(new.valid_from, new.document_date, current_date);
--
-- Ao ativar uma versao sem inicio de vigencia declarado, o banco CARIMBAVA a
-- data da ativacao. O resultado nao era "nao sabemos quando comeca": era uma
-- data com cara de oficial, que nao vem do documento e nao vem de ninguem —
-- vem do dia em que alguem apertou o botao. Uma tabela de precos de JAN/26
-- ativada em setembro passava a declarar vigencia a partir de setembro.
--
-- O `document_date` tambem nao serve de substituto automatico, e isso nao e
-- teoria: a versao ARAG em producao carrega, no proprio `provenance_note`,
--
--   "valid_from corresponde a data tecnica do arquivo observada no sistema de
--    arquivos; nao ha vigencia comercial declarada"
--
-- ou seja, a data do arquivo subiu a vigencia comercial por promocao
-- silenciosa do coalesce. Sao conceitos diferentes e ficam separados:
--
--   document_date  data documental/tecnica, quando houver
--   valid_from     inicio comercial EXPLICITAMENTE conhecido
--   valid_to       fim comercial EXPLICITAMENTE conhecido
--
-- A partir daqui, `valid_from` so recebe o que for informado. NULL passa a
-- significar o que sempre deveria: "vigencia inicial nao declarada" — e nao
-- "use hoje". Toda a leitura ja tratava NULL corretamente (`current_version`
-- e a CTE de vigencia da busca fazem `valid_from is null or valid_from <=
-- current_date`); quem inventava data era so este gatilho.
--
-- PROSPECTIVA. Este e um gatilho BEFORE e o trecho so roda na transicao para
-- `active`: Magnojet V41 e ARAG, ja ativos e com data gravada, nao sao
-- tocados. A migration nao faz UPDATE em linha nenhuma.
--
-- Testes: supabase/db-tests/38_brain_vigencia_nao_declarada.sql (V1-V8).
--
-- SOBRE O NUMERO DESTE ARQUIVO. Ele nasceu `20260917120000`. Ao ser aplicada
-- em producao, a migration foi registrada no ledger do Supabase com o carimbo
-- do momento da aplicacao — `20260917030427` — e nao com o numero do arquivo.
-- Ficaram dois numeros para a mesma migration: um no Git, outro no banco.
-- Isso nao e cosmetico: o CLI decide o que falta aplicar comparando o prefixo
-- do ARQUIVO com o ledger, entao um `db push` veria `20260917120000` como
-- pendente e rodaria esta migration de novo, criando uma segunda linha no
-- ledger para algo que ja esta la.
--
-- O arquivo foi renomeado para bater com o ledger. O numero nao e um horario
-- escolhido: e o carimbo real da aplicacao em producao, e por isso fica.
-- Nada foi reexecutado — a funcao em producao ja e esta, conferido por
-- conteudo e nao pelo ledger (md5 sem comentario, os dois lados:
-- 8830c13918777460cc7bcc8da69bf453).
-- ============================================================

create or replace function brain.stamp_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select d.access_level into new.access_level from brain.documents d where d.id = new.document_id;
  if new.access_level is null then
    raise exception 'Versao sem documento: %', new.document_id using errcode = 'foreign_key_violation';
  end if;

  if tg_op = 'UPDATE' then
    if new.file_sha256 is distinct from old.file_sha256
    or new.storage_path is distinct from old.storage_path
    or new.storage_bucket is distinct from old.storage_bucket
    or new.file_size is distinct from old.file_size
    or new.mime_type is distinct from old.mime_type
    or new.original_filename is distinct from old.original_filename
    or new.document_id is distinct from old.document_id then
      raise exception 'O arquivo de uma versao e imutavel (sha256, caminho, tamanho, tipo, nome). Arquivo diferente e versao nova.'
        using errcode = 'restrict_violation';
    end if;
  end if;

  -- Ao ativar, a vigente anterior passa a superseded e as duas se apontam.
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    update brain.document_versions v
       set status = 'superseded',
           superseded_by_id = new.id,
           -- Quando a nova DECLARA inicio, a antiga termina na vespera — e
           -- nunca antes do proprio inicio (ativar uma edicao com data mais
           -- antiga que a vigente e raro, mas nao pode virar excecao de
           -- constraint). Quando a nova NAO declara inicio, nao ha vespera de
           -- que falar: a antiga deixou de valer HOJE, que e o dia em que foi
           -- substituida. Antes, `greatest(null - 1, v.valid_from)` colapsava
           -- em `v.valid_from` e encerrava a antiga no proprio dia em que ela
           -- comecou — uma vigencia de um dia, inventada pela aritmetica.
           valid_to = coalesce(
             v.valid_to,
             case when new.valid_from is null then current_date
                  else greatest(new.valid_from - 1, v.valid_from) end,
             current_date)
     where v.document_id = new.document_id and v.status = 'active' and v.id <> new.id;
    if new.supersedes_id is null then
      select v.id into new.supersedes_id from brain.document_versions v
       where v.document_id = new.document_id and v.superseded_by_id = new.id
       order by v.imported_at desc limit 1;
    end if;
    -- Sem fallback: `valid_from` e o que foi informado, ou nada. O banco nao
    -- deduz vigencia comercial de data tecnica nem do relogio.
    -- Reativar uma edicao (superseded/withdrawn → active) reabre a vigencia,
    -- a menos que o mesmo UPDATE tenha fixado um valid_to de proposito.
    if tg_op = 'UPDATE' and new.valid_to is not distinct from old.valid_to then
      new.valid_to := null;
    end if;
  end if;

  -- Estados sem ambiguidade (auditoria pre-publicacao):
  --   · ativar e um ato de HOJE: `valid_from` no futuro nao existe — a edicao
  --     que ainda nao vale fica `draft` ate o dia, e so entao e ativada. Sem
  --     isso, o documento ficaria sem edicao vigente entre a ativacao e a data.
  --     Sem inicio declarado nao ha futuro a checar: o `is not null` esta
  --     escrito porque a regra e essa, e nao para depender de `null > data`
  --     devolver null por acaso;
  --   · `superseded` sempre tem fim de vigencia: sem `valid_to` seria uma
  --     "antiga" que nunca terminou. Isto vale inclusive para a versao sem
  --     inicio declarado — nao saber quando comecou nao impede saber quando
  --     parou.
  if new.status = 'active' and new.valid_from is not null and new.valid_from > current_date then
    raise exception 'Nao se ativa uma versao com valid_from no futuro (%). Deixe em draft ate la.', new.valid_from
      using errcode = 'check_violation';
  end if;
  if new.status = 'superseded' then
    new.valid_to := coalesce(new.valid_to, current_date);
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_version() from public, anon, authenticated;

comment on function brain.stamp_version() is
  'Carimba access_level do documento, tranca o arquivo, supersede a vigente anterior e fecha vigencia de superseded. NAO inventa valid_from: sem inicio declarado, valid_from fica NULL e significa "vigencia inicial nao declarada".';

comment on column brain.document_versions.valid_from is
  'Inicio da vigencia COMERCIAL, so quando declarado. NULL = nao declarado (a versao ativa vale enquanto for a vigente) — nunca "hoje". Data tecnica do arquivo mora em document_date e nao sobe para ca.';

comment on column brain.document_versions.valid_to is
  'Fim da vigencia comercial, so quando declarado. NULL = sem fim declarado. Uma versao superseded sempre recebe um: deixou de valer no dia em que foi substituida.';

-- Guarda: a definicao entrou e nao ha fallback de data no corpo.
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.proname = 'stamp_version';
  if v_src is null then
    raise exception 'brain.stamp_version() nao existe depois da migration';
  end if;
  if v_src like '%coalesce(new.valid_from%' then
    raise exception 'brain.stamp_version() ainda deduz valid_from por coalesce';
  end if;
  raise notice 'vigencia: valid_from deixou de ganhar data automatica na ativacao';
end
$$;
