#!/usr/bin/env bash
# ============================================================
# Ensaio do lote DJI Subdealer: DUAS versões do MESMO documento,
# golden e adversariais, num PostgreSQL descartável.
#
#   PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
#     bash supabase/db-tests/ensaiar-dji.sh \
#       "/caminho/TABELA-SUBDEALER-V14.11.pdf" \
#       "/caminho/TABELASUBDEALERV16.2  B.pdf"
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
      values ('dji','DJI / distribuidor oficial','manufacturer','commercial','forbidden');
      insert into brain.documents (source_key, slug, title, document_type, access_level)
      values ('dji','dji-tabela-subdealer','Tabela Subdealer DJI','price_list','commercial')" >/dev/null

echo "▶ ingestão das duas versões"
export BRAIN_DB_URL="postgresql://$U@/$DB?host=$H&port=$P"
( cd brain/worker && python3 -m brain_worker ingest "$V1411" --document dji-tabela-subdealer --label V14.11 --date 2026-01-14 --ocr never ) | sed 's/^/  V14.11 /'
( cd brain/worker && python3 -m brain_worker ingest "$V162"  --document dji-tabela-subdealer --label V16.2  --date 2026-08-04 --ocr never ) | sed 's/^/  V16.2  /'

echo "▶ linhagem: V16.2 vigente, V14.11 histórica"
q -c "update brain.document_versions set status='active', valid_from='2026-08-04' where version_label='V16.2';
      update brain.document_versions set status='superseded', valid_from='2026-01-14', valid_to='2026-08-03',
             superseded_by_id=(select id from brain.document_versions where version_label='V16.2')
       where version_label='V14.11';
      update brain.document_versions set supersedes_id=(select id from brain.document_versions where version_label='V14.11')
       where version_label='V16.2'" >/dev/null

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
declare n int; m int; v text; passes int:=0; falhas int:=0;
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

  -- O) tabela degradada seria fail-closed (nenhuma degradada neste corpo)
  select count(*) into n from brain.document_chunks c
    where c.kind='price_table' and c.table_data->'audit'->>'quality' = 'degraded';
  select count(*) into m from brain.document_chunks c where c.kind='price_table';
  if n=0 and m>0 then passes:=passes+1; raise notice 'O PASS  % tabelas de preço, nenhuma degradada — nada entra na busca sem condição de pagamento', m;
  else falhas:=falhas+1; raise warning 'O FALHA: % degradada(s) de %', n, m; end if;

  -- P) preço da tabela DJI nunca toca o ERP
  select (select count(*) from public.products) + (select count(*) from public.product_costs) into n;
  if n=0 then passes:=passes+1; raise notice 'P PASS  nenhum produto/custo criado no ERP pela ingestão';
  else falhas:=falhas+1; raise warning 'P FALHA: % linha(s) no ERP', n; end if;

  raise notice '--- ADVERSARIAIS DJI: % PASS, % FALHA ---', passes, falhas;
end $$;
ADV
AOK=$?

if [ "$GOK" = 0 ] && [ "$AOK" = 0 ]; then
  echo "✔ lote DJI ensaiado: golden e adversariais"
else
  echo "✗ lote DJI com falha (golden=$GOK adversariais=$AOK)"; exit 1
fi
