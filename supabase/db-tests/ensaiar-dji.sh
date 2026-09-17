#!/usr/bin/env bash
# ============================================================
# Ensaio do lote DJI Subdealer: DUAS versões do MESMO documento,
# golden e adversariais, num PostgreSQL descartável.
#
#   PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
#     bash supabase/db-tests/ensaiar-dji.sh \
#       "/caminho/TABELA-SUBDEALER-V14.11.pdf" \
#       "/caminho/TABELASUBDEALERV16.2  B.pdf" \
#       "/caminho/TABELA-SUBDEALER-V15.1 - B.pdf"
#
# O terceiro argumento (V15.1) e OPCIONAL. Com ele o ensaio monta a cadeia
# completa V14.11 → V15.1 → V16.2 e roda o GOLDEN FINAL de 10 itens; sem ele,
# roda a cadeia curta V14.11 → V16.2 que ja existia.
#
# Os PDFs NÃO estão no repositório e nunca estarão: são documentos reais de
# fornecedor, com custo. O ensaio recebe o caminho deles como argumento —
# por isso ele não entra no `run.mjs`, que roda só com sintético.
#
# G1–G5  golden: bateria avulsa, versão vigente, T100, T25P, T55 (duas configs)
# A–P    adversariais: modelo parecido, versão trocada, condição de pagamento,
#        preço virando código, produto/versão inexistente, ERP intacto
#
# Requer: python3 com as dependências de brain/worker/requirements.txt.
# O worker conecta como postgres no banco local — nunca em produção.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
V1411="${1:?informe o caminho do PDF V14.11}"
V162="${2:?informe o caminho do PDF V16.2}"
V151="${3:-}"   # opcional: habilita a cadeia de tres versoes
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp/pgrun}"; P="${PGPORT:-5433}"; U="${PGUSER:-postgres}"
DB=ensaio_dji
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -At "$@"; }

echo "▶ banco descartável $DB + migrations"
adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
q -c "create extension if not exists pgcrypto" >/dev/null
q -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql; do q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  ✗ migration $f"; exit 1; }; done
echo "  ok $(ls supabase/migrations/*.sql | wc -l) migrations"

echo "▶ fonte e documento (o mesmo documento, duas versões)"
q -c "insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing)
      values ('allcomp','ALLCOMP — distribuidor DJI Agriculture','distributor','commercial','forbidden');
      insert into brain.documents (source_key, slug, title, document_type, access_level)
      values ('allcomp','dji-tabela-subdealer','Tabela Subdealer DJI','price_list','commercial')" >/dev/null

echo "▶ ingestão das duas versões"
export BRAIN_DB_URL="postgresql://$U@/$DB?host=$H&port=$P"
( cd brain/worker && python3 -m brain_worker ingest "$V1411" --document dji-tabela-subdealer --label V14.11 --date 2026-01-14 --ocr never ) | sed 's/^/  V14.11 /'
( cd brain/worker && python3 -m brain_worker ingest "$V162"  --document dji-tabela-subdealer --label V16.2  --date 2026-08-04 --ocr never ) | sed 's/^/  V16.2  /'

if [ -n "$V151" ]; then
  # A V15.1 tem 4 paginas e SO A PAGINA 1 e DJI: as paginas 2-3 sao Ddock/
  # GranDdock (faturadas pela Zait) e a 4 e RTK South / piloto Sunnav.
  # Publicar isso como "Tabela Subdealer DJI" seria mentira de proveniencia.
  #
  # Ate 16/09 isto era feito com um documento de PASSAGEM: ingerir o arquivo
  # inteiro num descartavel e copiar a pagina 1 para a versao DJI. Funcionava,
  # mas declarava `page_count = 1` para um PDF de 4 paginas — o arquivo
  # aparecia menor do que e. Desde 17/09 o worker recorta de verdade
  # (`--pages`), e o recorte fica no metadata ao lado do total fisico.
  echo "▶ V15.1: só a página 1 é evidência DJI (--pages 1, sem documento de passagem)"
  ( cd brain/worker && python3 -m brain_worker ingest "$V151" --document dji-tabela-subdealer --label V15.1 --date 2026-05-19 --ocr never --pages 1 ) | sed 's/^/  V15.1  /'

  q -v ON_ERROR_STOP=1 -c "
  do \$recorte\$
  declare v uuid; n int; m jsonb;
  begin
    select id into v from brain.document_versions where version_label='V15.1';
    if v is null then raise exception 'V15.1 nao foi registrada'; end if;
    update brain.document_versions set metadata = metadata || jsonb_build_object('provenance_note',
      'Somente a pagina 1 deste arquivo e evidencia DJI. As paginas 2-3 (Ddock/GranDdock, faturado pela Zait) e a pagina 4 (RTK South / piloto automatico Sunnav) ficam fora deste documento logico. O arquivo fisico original e preservado inteiro e o sha256 e o mesmo.')
     where id = v;
    select metadata into m from brain.document_versions where id = v;
    select count(*) into n from brain.document_pages where version_id=v;
    if n <> 1 then raise exception 'V15.1 DJI ficou com % pagina(s), esperava 1', n; end if;
    select count(*) into n from brain.document_chunks where version_id=v and page_from <> 1;
    if n <> 0 then raise exception 'V15.1 DJI recebeu % trecho(s) fora da pagina 1', n; end if;
    select page_count into n from brain.document_versions where id = v;
    if n <> 4 then raise exception 'page_count da V15.1 = %, esperava 4 (o arquivo tem 4 paginas)', n; end if;
    if m->'ingested_pages' <> '[1]'::jsonb then raise exception 'metadata nao declara o recorte: %', m->'ingested_pages'; end if;
    raise notice 'V15.1 DJI: 1 pagina ingerida de 4 do arquivo, % trecho(s) — paginas 2-4 nao foram lidas',
            (select count(*) from brain.document_chunks where version_id=v);
  end \$recorte\$;" 2>&1 | sed 's/^/  /'

  echo "▶ linhagem: V14.11 → V15.1 → V16.2, V16.2 vigente"
  q -c "update brain.document_versions set status='active', valid_from='2026-08-04' where version_label='V16.2';
        update brain.document_versions set status='superseded', valid_from='2026-05-19', valid_to='2026-08-03',
               superseded_by_id=(select id from brain.document_versions where version_label='V16.2')
         where version_label='V15.1';
        update brain.document_versions set status='superseded', valid_from='2026-01-14', valid_to='2026-05-18',
               superseded_by_id=(select id from brain.document_versions where version_label='V15.1')
         where version_label='V14.11';
        update brain.document_versions set supersedes_id=(select id from brain.document_versions where version_label='V14.11')
         where version_label='V15.1';
        update brain.document_versions set supersedes_id=(select id from brain.document_versions where version_label='V15.1')
         where version_label='V16.2'" >/dev/null
else
  echo "▶ linhagem: V16.2 vigente, V14.11 histórica"
  q -c "update brain.document_versions set status='active', valid_from='2026-08-04' where version_label='V16.2';
        update brain.document_versions set status='superseded', valid_from='2026-01-14', valid_to='2026-08-03',
               superseded_by_id=(select id from brain.document_versions where version_label='V16.2')
         where version_label='V14.11';
        update brain.document_versions set supersedes_id=(select id from brain.document_versions where version_label='V14.11')
         where version_label='V16.2'" >/dev/null
fi

echo "▶ GOLDEN"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'GOLDEN'
do $$
declare
  h record; ok boolean; achou text; n int;
  falhas int := 0; passes int := 0;
  procedure_note text;
begin
  -- G1: bateria avulsa T55 e T70P → DB1580, na versão vigente
  select count(*) into n from brain.search_knowledge('Qual bateria avulsa serve para T55 e T70P?') s
   where s.content like '%DB1580%' and s.version_label='V16.2';
  if n >= 1 then passes:=passes+1; raise notice 'G1 PASS  bateria T55/T70P → DB1580 citado em V16.2 (% evidência(s))', n;
  else falhas:=falhas+1; raise warning 'G1 FALHA'; end if;

  -- G1b: contexto — T55 sozinho usa DB1050; T100/T70P usam DB2160
  select count(*) into n from brain.search_knowledge('bateria avulsa T55 DB1050') s where s.content like '%T55 (DB1050)%';
  if n>=1 then passes:=passes+1; raise notice 'G1b PASS  T55 (DB1050) confirmado no documento';
  else falhas:=falhas+1; raise warning 'G1b FALHA'; end if;
  select count(*) into n from brain.search_knowledge('bateria T100 T70P DB2160') s where s.content like '%T100 / T70P (DB2160)%';
  if n>=1 then passes:=passes+1; raise notice 'G1c PASS  T100 / T70P (DB2160) confirmado no documento';
  else falhas:=falhas+1; raise warning 'G1c FALHA'; end if;

  -- G2: versão vigente é a V16.2; V14.11 é histórica
  select version_label into achou from brain.document_versions where status='active';
  if achou='V16.2' then passes:=passes+1; raise notice 'G2 PASS  versão vigente = V16.2 (V14.11 superseded)';
  else falhas:=falhas+1; raise warning 'G2 FALHA: vigente=%', achou; end if;

  -- G3 V16.2: T100 + 3 BAT + C12000 → à vista 161900, faturado 165500, cliente final 225000
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T100 3 BAT CARREGADOR C12000 preço') s
   where s.version_label='V16.2' and s.content like '%161.900,00%' and s.content like '%165.500,00%' and s.content like '%225.000,00%';
  if n>=1 then passes:=passes+1; raise notice 'G3-V16.2 PASS  T100+C12000: 165.500 faturado / 161.900 à vista / 225.000 cliente final';
  else falhas:=falhas+1; raise warning 'G3-V16.2 FALHA'; end if;

  -- G3 V14.11 (histórica, só sob pedido): à vista 159000
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T100 3 BAT CARREGADOR C12000', '{}'::jsonb, 20, true) s
   where s.version_label='V14.11' and s.table_data->>'title' like 'DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000%'
     and (s.table_data->'rows'->0->>2)::numeric = 159000;
  if n>=1 then passes:=passes+1; raise notice 'G3-V14.11 PASS  T100+C12000 à vista 159000 na tabela estruturada da versão histórica';
  else falhas:=falhas+1; raise warning 'G3-V14.11 FALHA'; end if;

  -- G4: T25P + 3 BAT + C8000 (V16.2) 64250 / 61789 / 87000 — pelo table_data, não pelo texto
  select count(*) into n from brain.search_knowledge('T25P carregador C8000') s
   where s.version_label='V16.2' and s.table_data->>'title' = 'DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000'
     and (s.table_data->'rows'->0->>1)::numeric=64250 and (s.table_data->'rows'->0->>2)::numeric=61789
     and (s.table_data->'rows'->1->>2)::numeric=87000;
  if n>=1 then passes:=passes+1; raise notice 'G4 PASS  T25P+C8000: 64250 faturado / 61789 à vista / 87000 cliente final (JSONB)';
  else falhas:=falhas+1; raise warning 'G4 FALHA'; end if;

  -- G5a: T55 + DB1050 + C7000 → 101401 / 96483 / 130000
  select count(*) into n from brain.search_knowledge('T55 DB1050 carregador C7000') s
   where s.version_label='V16.2' and s.table_data->>'title' = 'DRONE AGRAS T55 + 3 BAT DB1050 + CARREGADOR C7000'
     and (s.table_data->'rows'->0->>1)::numeric=101401 and (s.table_data->'rows'->0->>2)::numeric=96483
     and (s.table_data->'rows'->1->>2)::numeric=130000;
  if n>=1 then passes:=passes+1; raise notice 'G5a PASS  T55 DB1050+C7000: 101401 / 96483 / 130000 (JSONB)';
  else falhas:=falhas+1; raise warning 'G5a FALHA'; end if;

  -- G5b: T55 + DB1580 + C12000 → 119400 / 113789 / 156000
  select count(*) into n from brain.search_knowledge('T55 DB1580 carregador C12000') s
   where s.version_label='V16.2' and s.table_data->>'title' = 'DRONE AGRAS T55 + 3 BAT DB1580 + CARREGADOR C12000'
     and (s.table_data->'rows'->0->>1)::numeric=119400 and (s.table_data->'rows'->0->>2)::numeric=113789
     and (s.table_data->'rows'->1->>2)::numeric=156000;
  if n>=1 then passes:=passes+1; raise notice 'G5b PASS  T55 DB1580+C12000: 119400 / 113789 / 156000 (JSONB)';
  else falhas:=falhas+1; raise warning 'G5b FALHA'; end if;

  raise notice '--- GOLDEN DJI: % PASS, % FALHA ---', passes, falhas;
  if falhas > 0 then raise exception 'Golden DJI com % falha(s)', falhas; end if;
end $$;
GOLDEN
GOK=$?
echo "▶ ADVERSARIAIS"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'ADV'
do $$
declare n int; m int; v_leak int; v text; passes int:=0; falhas int:=0;
begin
  -- A) T25P ≠ T25: a busca por T25 não devolve a tabela do T25P como se fosse dele
  select count(*) into n from brain.search_knowledge('T25P') s
    where s.kind='price_table' and s.table_data->>'title' like '%T25P%';
  select count(*) into m from brain.search_knowledge('T25P') s
    where s.kind='price_table' and s.table_data->>'title' like '%T25 %' and s.table_data->>'title' not like '%T25P%';
  if n>=1 and m=0 then passes:=passes+1; raise notice 'A PASS  T25P não traz tabela de T25 (%, %)', n, m;
  else falhas:=falhas+1; raise warning 'A FALHA n=% m=%', n, m; end if;

  -- B) T55 DB1050 ≠ T55 DB1580: preços diferentes, tabelas diferentes
  select count(distinct s.table_data->>'title') into n from brain.search_knowledge('T55') s
    where s.kind='price_table' and s.table_data->>'title' like '%DB10%';
  select count(*) into m from brain.document_chunks c
    where c.kind='price_table' and c.table_data->>'title' like '%DB1050%'
      and jsonb_typeof(c.table_data->'rows'->0->1)='number'
      and (c.table_data->'rows'->0->>1)::numeric = (select (c2.table_data->'rows'->0->>1)::numeric from brain.document_chunks c2
             where c2.table_data->>'title' like '%DB1580 + CARREGADOR%'
               and jsonb_typeof(c2.table_data->'rows'->0->1)='number' limit 1);
  if m=0 then passes:=passes+1; raise notice 'B PASS  DB1050 e DB1580 nunca compartilham preço';
  else falhas:=falhas+1; raise warning 'B FALHA'; end if;

  -- C) T100 ≠ T70P / D) C7000 ≠ C12000
  select count(*) into n from brain.document_chunks c where c.kind='price_table'
    and c.table_data->>'title' like '%T100%' and c.table_data->>'title' like '%T70P%';
  if n=0 then passes:=passes+1; raise notice 'C PASS  nenhuma tabela mistura T100 e T70P';
  else falhas:=falhas+1; raise warning 'C FALHA: % tabela(s)', n; end if;
  select count(*) into n from brain.document_chunks c where c.kind='price_table'
    and c.table_data->>'title' like '%C7000%' and c.table_data->>'title' like '%C12000%';
  if n=0 then passes:=passes+1; raise notice 'D PASS  nenhuma tabela mistura C7000 e C12000';
  else falhas:=falhas+1; raise warning 'D FALHA'; end if;

  -- E) V14.11 ≠ V16.2: o preço à vista do T100 mudou; a vigente não devolve o antigo
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T100 3 BAT CARREGADOR C12000') s
    where s.content like '%159.000,00%'
       or (jsonb_typeof(s.table_data->'rows'->0->2)='number' and (s.table_data->'rows'->0->>2)::numeric = 159000);
  if n=0 then passes:=passes+1; raise notice 'E PASS  preço de V14.11 (159.000) não aparece na busca normal';
  else falhas:=falhas+1; raise warning 'E FALHA: % hit(s) com preço histórico', n; end if;

  -- F/G) à vista ≠ faturado ≠ cliente final mínimo, na mesma tabela
  select count(*) into n from brain.document_chunks c where c.kind='price_table'
    and jsonb_typeof(c.table_data->'rows'->0->1)='number' and jsonb_typeof(c.table_data->'rows'->0->2)='number'
    and (c.table_data->'rows'->0->>1)::numeric = (c.table_data->'rows'->0->>2)::numeric;
  if n=0 then passes:=passes+1; raise notice 'F PASS  faturado e à vista nunca colapsam no mesmo valor';
  else falhas:=falhas+1; raise warning 'F FALHA: % tabela(s)', n; end if;
  select count(*) into n from brain.document_chunks c where c.kind='price_table'
    and jsonb_typeof(c.table_data->'rows'->1->2)='number' and jsonb_typeof(c.table_data->'rows'->0->2)='number'
    and (c.table_data->'rows'->1->>2)::numeric = (c.table_data->'rows'->0->>2)::numeric;
  if n=0 then passes:=passes+1; raise notice 'G PASS  cliente final mínimo nunca igual ao preço de revenda';
  else falhas:=falhas+1; raise warning 'G FALHA: % tabela(s)', n; end if;

  -- H) "3 BAT" não virou preço / I) preço não virou código
  select count(*) into n from brain.document_chunks c where c.kind='price_table'
    and exists (select 1 from jsonb_array_elements(c.table_data->'rows') r
                where r::text ~ '\m3\M' and (r->>1) = '3');
  if n=0 then passes:=passes+1; raise notice 'H PASS  "3 BAT" não virou valor de preço';
  else falhas:=falhas+1; raise warning 'H FALHA'; end if;
  select count(*) into n from brain.document_chunks c
    where exists (select 1 from unnest(c.codes) x where x ~ '^\d{5,6}$' or x ~ '^R');
  if n=0 then passes:=passes+1; raise notice 'I PASS  nenhum valor monetário virou código de produto';
  else falhas:=falhas+1; raise warning 'I FALHA: % chunk(s)', n; end if;

  -- J) preço isolado não produz match FALSO. Casar o trecho que realmente
  -- contém aquele valor é acerto, não erro — o que não pode é devolver um
  -- trecho que não tem o número, nem inventar evidência para um valor que
  -- não existe em documento nenhum.
  select count(*) into n from brain.search_knowledge('161900') s
    where s.content not like '%161900%' and s.content not like '%161.900%';
  select count(*) into m from brain.search_knowledge('987654');
  if n=0 and m=0 then passes:=passes+1; raise notice 'J PASS  valor isolado só devolve trecho que o contém; valor inexistente → zero';
  else falhas:=falhas+1; raise warning 'J FALHA: % hit(s) sem o valor, % hit(s) para valor inexistente', n, m; end if;

  -- K) produto inexistente → zero
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T999');
  if n=0 then passes:=passes+1; raise notice 'K PASS  produto inexistente (T999) → zero, sem evidência inventada';
  else falhas:=falhas+1; raise warning 'K FALHA: % hit(s)', n; end if;

  -- L) versão inexistente não devolve versão próxima como exata
  select count(*) into n from brain.search_knowledge('tabela subdealer V15.9');
  if n=0 then passes:=passes+1; raise notice 'L PASS  V15.9 (inexistente) não devolve V16.2 como se fosse ela';
  else falhas:=falhas+1; raise warning 'L FALHA: % hit(s)', n; end if;

  -- M) consulta histórica não mistura versões
  select count(distinct s.version_label) into n from brain.search_knowledge(
     'DRONE AGRAS T100 3 BAT CARREGADOR C12000', '{"version_label":"V14.11"}'::jsonb, 20, true) s;
  select version_label into v from brain.search_knowledge(
     'DRONE AGRAS T100 3 BAT CARREGADOR C12000', '{"version_label":"V14.11"}'::jsonb, 20, true) s limit 1;
  if n=1 and v='V14.11' then passes:=passes+1; raise notice 'M PASS  pedido histórico devolve só V14.11';
  else falhas:=falhas+1; raise warning 'M FALHA: % versao(oes), primeira=%', n, v; end if;

  -- N) busca normal privilegia a versão vigente
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T100 3 BAT CARREGADOR C12000') s
    where s.version_label <> 'V16.2';
  if n=0 then passes:=passes+1; raise notice 'N PASS  busca normal só devolve a versão vigente';
  else falhas:=falhas+1; raise warning 'N FALHA: % hit(s) fora da vigente', n; end if;

  -- O) tabela degradada e fail-closed. V14.11 e V16.2 nao tem nenhuma. A V15.1
  --    tem DUAS — "DRONE AVULSO (SO CAIXA, COM CONTROLE)" e "BATERIA AVULSA" —
  --    porque naquela pagina os precos estao RISCADOS e a reconstrucao derruba
  --    a linha de cabecalho para dentro dos dados. Nao e defeito do ensaio: e o
  --    worker marcando o que nao entendeu, e a busca recusando como evidencia.
  --    Nenhum item do golden depende desses dois blocos.
  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where c.kind='price_table' and c.table_data->'audit'->>'quality'='degraded'
     and v.version_label in ('V14.11','V16.2');
  if n<>0 then falhas:=falhas+1; raise warning 'O FALHA: % degradada(s) em V14.11/V16.2', n; end if;

  select count(*) into m from brain.document_chunks c where c.kind='price_table';
  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where c.kind='price_table' and c.table_data->'audit'->>'quality'='degraded'
     and v.version_label='V15.1';

  -- e o que esta degradado nao chega na busca, por nenhum caminho
  select count(*) into v_leak from brain.search_knowledge('drone avulso bateria avulsa preço','{}'::jsonb,100,true) s
   where s.kind in ('table','price_table')
     and (coalesce(s.table_data->'audit'->>'quality','trusted')='degraded'
          or coalesce((s.table_data->'audit'->>'fatal')::boolean,false));
  if v_leak <> 0 then falhas:=falhas+1; raise warning 'O FALHA: % degradada(s) vazaram para a busca', v_leak; end if;

  if n=0 and v_leak=0 then passes:=passes+1; raise notice 'O PASS  % tabelas de preço, nenhuma degradada', m;
  elsif n=2 and v_leak=0 then passes:=passes+1;
    raise notice 'O PASS  % tabelas de preço; as 2 degradadas são da V15.1 (preços riscados: DRONE AVULSO e BATERIA AVULSA) e a busca as recusa — zero vazamento', m;
  elsif v_leak=0 then falhas:=falhas+1;
    raise warning 'O FALHA: % degradada(s) na V15.1 — esperava 0 ou 2, o corpo mudou', n;
  end if;

  -- P) preço da tabela DJI nunca toca o ERP
  select (select count(*) from public.products) + (select count(*) from public.product_costs) into n;
  if n=0 then passes:=passes+1; raise notice 'P PASS  nenhum produto/custo criado no ERP pela ingestão';
  else falhas:=falhas+1; raise warning 'P FALHA: % linha(s) no ERP', n; end if;

  raise notice '--- ADVERSARIAIS DJI: % PASS, % FALHA ---', passes, falhas;
end $$;
ADV
AOK=$?

# ── GOLDEN FINAL (10 itens) — só com a cadeia de três versões ──────────
G3OK=0
if [ -n "$V151" ]; then
echo "▶ GOLDEN FINAL (cadeia de três versões)"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'G10'
do $$
declare n int; passes int:=0; falhas int:=0;
begin
  -- 1) bateria avulsa DB1580 T55/T70P — produto que so existe na V16.2
  select count(*) into n from brain.search_knowledge('bateria avulsa DB1580 T55 T70P') s
   where s.content like '%DB1580%' and s.version_label='V16.2';
  if n>=1 then passes:=passes+1; raise notice 'F1  PASS  DB1580 avulsa T55/T70P → V16.2 (% evidência(s))', n;
  else falhas:=falhas+1; raise warning 'F1  FALHA: %', n; end if;

  -- 2) DB1050 e do T55
  select count(*) into n from brain.search_knowledge('bateria T55 DB1050') s
   where s.content like '%DB1050%' and s.version_label='V16.2';
  if n>=1 then passes:=passes+1; raise notice 'F2  PASS  DB1050 → T55, V16.2';
  else falhas:=falhas+1; raise warning 'F2  FALHA'; end if;

  -- 3) DB2160 (T100/T70P) atravessa as tres versoes
  select count(distinct v.version_label) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where c.content like '%DB2160%';
  if n=3 then passes:=passes+1; raise notice 'F3  PASS  DB2160 T100/T70P presente nas três versões';
  else falhas:=falhas+1; raise warning 'F3  FALHA: % versão(ões)', n; end if;

  -- 4) cadeia inteira, V16.2 vigente
  select count(*) into n from brain.document_versions v
   where (v.version_label='V16.2'  and v.status='active'
          and v.supersedes_id=(select id from brain.document_versions where version_label='V15.1'))
      or (v.version_label='V15.1'  and v.status='superseded'
          and v.supersedes_id=(select id from brain.document_versions where version_label='V14.11'))
      or (v.version_label='V14.11' and v.status='superseded');
  if n=3 then passes:=passes+1; raise notice 'F4  PASS  cadeia V14.11 → V15.1 → V16.2, V16.2 vigente';
  else falhas:=falhas+1; raise warning 'F4  FALHA: % elo(s)', n; end if;

  -- Nas V15.1 e V16.2 a faixa do T100 fica em chunk de TEXTO: elas vem do Google
  -- Sheets (Skia) e aquela regiao nao tem borda para a reconstrucao morder. So a
  -- V14.11 (Word -> Print to PDF) vira tabela titulada, e por isso F7 le do JSONB.
  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V16.2' and c.content like '%T100 + 3 BAT + CARREGADOR C12000%'
     and c.content like '%165.500,00%' and c.content like '%161.900,00%' and c.content like '%225.000,00%';
  if n>=1 then passes:=passes+1; raise notice 'F5  PASS  T100 V16.2: 165.500 faturado / 161.900 à vista / 225.000 final';
  else falhas:=falhas+1; raise warning 'F5  FALHA'; end if;

  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V15.1' and c.content like '%T100 + 3 BAT + CARREGADOR C12000%'
     and c.content like '%165.500,00%' and c.content like '%161.900,00%' and c.content like '%225.000,00%';
  if n>=1 then passes:=passes+1; raise notice 'F6  PASS  T100 V15.1: 165.500 / 161.900 / 225.000 — igual à V16.2, o preço parou de mudar';
  else falhas:=falhas+1; raise warning 'F6  FALHA'; end if;

  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V14.11' and c.table_data->>'title' like 'DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000%'
     and (c.table_data->'rows'->0->>1)::numeric = 165500
     and (c.table_data->'rows'->0->>2)::numeric = 159000
     and (c.table_data->'rows'->1->>2)::numeric = 225000;
  if n>=1 then passes:=passes+1; raise notice 'F7  PASS  T100 V14.11: 165.500 / 159.000 / 225.000';
  else falhas:=falhas+1; raise warning 'F7  FALHA'; end if;

  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V16.2' and c.table_data->>'title' like 'DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000%'
     and (c.table_data->'rows'->0->>1)::numeric = 64250
     and (c.table_data->'rows'->0->>2)::numeric = 61789
     and (c.table_data->'rows'->1->>2)::numeric = 87000;
  if n>=1 then passes:=passes+1; raise notice 'F8  PASS  T25P V16.2: 64.250 / 61.789 / 87.000';
  else falhas:=falhas+1; raise warning 'F8  FALHA'; end if;

  -- o T25P da V15.1 VIRA tabela (tem borda), entao o valor sai do JSONB
  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V15.1' and c.table_data->>'title' like 'DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000%'
     and (c.table_data->'rows'->0->>1)::numeric = 79000
     and (c.table_data->'rows'->0->>2)::numeric = 77400
     and (c.table_data->'rows'->1->>2)::numeric = 110000;
  if n>=1 then raise notice '    (contraste: T25P na V15.1 era 79.000 / 77.400 / 110.000 — é este item que separa V15.1 de V16.2)';
  else raise warning '    T25P da V15.1 não confere'; falhas:=falhas+1; end if;

  -- 9/10) T55: produto novo, so na V16.2
  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V16.2' and c.table_data->>'title' like 'DRONE AGRAS T55 + 3 BAT DB1050 + CARREGADOR C7000%'
     and (c.table_data->'rows'->0->>1)::numeric = 101401
     and (c.table_data->'rows'->0->>2)::numeric = 96483
     and (c.table_data->'rows'->1->>2)::numeric = 130000;
  if n>=1 then passes:=passes+1; raise notice 'F9  PASS  T55 DB1050+C7000 V16.2: 101.401 / 96.483 / 130.000';
  else falhas:=falhas+1; raise warning 'F9  FALHA'; end if;

  select count(*) into n from brain.document_chunks c
    join brain.document_versions v on v.id=c.version_id
   where v.version_label='V16.2' and c.table_data->>'title' like 'DRONE AGRAS T55 + 3 BAT DB1580 + CARREGADOR C12000%'
     and (c.table_data->'rows'->0->>1)::numeric = 119400
     and (c.table_data->'rows'->0->>2)::numeric = 113789
     and (c.table_data->'rows'->1->>2)::numeric = 156000;
  if n>=1 then passes:=passes+1; raise notice 'F10 PASS  T55 DB1580+C12000 V16.2: 119.400 / 113.789 / 156.000';
  else falhas:=falhas+1; raise warning 'F10 FALHA'; end if;

  select count(*) into n from brain.document_chunks c join brain.document_versions v on v.id=c.version_id
   where v.version_label in ('V14.11','V15.1') and c.content like '%T55%';
  if n=0 then raise notice '    (T55 não existe na V14.11 nem na V15.1 — é produto novo da V16.2)';
  else raise warning '    T55 apareceu em versão anterior: % trecho(s)', n; falhas:=falhas+1; end if;

  -- proveniencia: todo hit traz version_id, label, pagina, fonte e documento
  select count(*) into n from brain.search_knowledge('DRONE AGRAS T100 CARREGADOR C12000','{}'::jsonb,20,true) s
   where s.version_id is null or s.version_label is null or s.page_from is null
      or s.source_key <> 'allcomp' or s.document_id is null or s.title is null;
  if n=0 then raise notice '    (proveniência completa: version_id, label, página, fonte allcomp, documento)';
  else raise warning '    proveniência incompleta em % hit(s)', n; falhas:=falhas+1; end if;

  -- a V15.1 do documento DJI nao pode ter NADA das paginas 2-4
  select count(*) into n from brain.document_chunks c join brain.document_versions v on v.id=c.version_id
   where v.version_label='V15.1'
     and (c.page_from <> 1 or c.content ilike '%GranDdock%' or c.content ilike '%Zait%'
          or c.content ilike '%GALAXY%' or c.content ilike '%Sunnav%');
  if n=0 then raise notice '    (V15.1 DJI limpa: nenhum trecho de Ddock/GranDdock/Zait/RTK South)';
  else raise warning '    V15.1 DJI contaminada: % trecho(s)', n; falhas:=falhas+1; end if;

  raise notice '--- GOLDEN FINAL DJI: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Golden final DJI com % falha(s)', falhas; end if;
end $$;
G10
G3OK=$?
fi

if [ "$GOK" = 0 ] && [ "$AOK" = 0 ] && [ "$G3OK" = 0 ]; then
  echo "✔ lote DJI ensaiado: golden e adversariais"
else
  echo "✗ lote DJI com falha (golden=$GOK adversariais=$AOK)"; exit 1
fi
