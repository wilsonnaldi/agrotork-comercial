#!/usr/bin/env bash
# ============================================================
# Ensaio do lote JR Soluções: tabela de preços para revendas,
# num PostgreSQL descartável.
#
#   PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
#     bash supabase/db-tests/ensaiar-jr.sh "/caminho/TABELA REV JAN261.pdf"
#
# O PDF NÃO está no repositório: é documento de fornecedor com preço. O
# ensaio recebe o caminho como argumento e por isso não entra no `run.mjs`.
#
# ESTADO EM 16/09/2026: este ensaio FALHA, e falha por um motivo real —
# a extração deste PDF não está boa o bastante para ingerir. Ele não é um
# teste quebrado: é o gate do lote. Cada asserção diz o que o lote precisa
# entregar; as que falham são exatamente o que falta consertar no worker.
# Detalhe em docs/brain/fase-2-jr-solucoes.md.
#
# G1–G10  golden: código exato, descrição, REVENDAS, SUGERIDO, inexistente,
#         NCM, proveniência, isolamento de fonte
# A–L     adversariais: preço não vira código, NCM não domina, JR não
#         devolve ARAG nem Magnojet, degradada não vaza, ERP intacto
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PDF="${1:?informe o caminho do PDF TABELA REV JAN261.pdf}"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp/pgrun}"; P="${PGPORT:-5433}"; U="${PGUSER:-postgres}"
DB=ensaio_jr
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -At "$@"; }

echo "▶ banco descartável $DB + migrations"
adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
q -c "create extension if not exists pgcrypto" >/dev/null
q -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql; do q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  ✗ migration $f"; exit 1; }; done
echo "  ok $(ls supabase/migrations/*.sql | wc -l) migrations"

echo "▶ fonte e documento"
q -c "insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing)
      values ('jr_solucoes','JR Soluções','manufacturer','commercial','forbidden');
      insert into brain.documents (source_key, slug, title, document_type, access_level)
      values ('jr_solucoes','jr-solucoes-tabela-revendas','Tabela de preços para revendas — JR Soluções','price_list','commercial')" >/dev/null

echo "▶ ingestão"
export BRAIN_DB_URL="postgresql://$U@/$DB?host=$H&port=$P"
# --date 2026-01-01: NAO e conveniencia. O gatilho de ativacao faz
# `valid_from := coalesce(valid_from, document_date, current_date)` — sem uma
# data declarada, a versao seria carimbada com o DIA DA ATIVACAO, que nao tem
# relacao nenhuma com o documento. Entre um carimbo mudo e a competencia que o
# proprio PDF declara ("atualizacao Janeiro 26"), a segunda e a honesta.
( cd brain/worker && python3 -m brain_worker ingest "$PDF" --document jr-solucoes-tabela-revendas \
    --label 'JAN/26' --date 2026-01-01 --ocr never --price-table ) | sed 's/^/  /'
q -c "update brain.document_versions set status='active' where version_label='JAN/26'" >/dev/null

echo "▶ retrato da extração"
q -c "select '  paginas: ' || (select count(*) from brain.document_pages)
          || ' | trechos: ' || (select count(*) from brain.document_chunks)
          || ' | tabelas: ' || (select count(*) from brain.document_chunks where kind in ('table','price_table'))
          || ' | degradadas: ' || (select count(*) from brain.document_chunks
                where kind in ('table','price_table')
                  and (coalesce(table_data->'audit'->>'quality','trusted')='degraded'
                       or coalesce((table_data->'audit'->>'fatal')::boolean,false)))
          || ' | linhas em rows: ' || (select coalesce(sum(jsonb_array_length(table_data->'rows')),0)
                from brain.document_chunks where table_data ? 'rows')"

echo "▶ GOLDEN"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'GOLDEN'
do $$
declare n int; passes int:=0; falhas int:=0;
begin
  -- G1) codigo de produto exato: 2141 = DRONE FEEDER 500
  select count(*) into n from brain.search_knowledge('2141') s where s.content like '%DRONE FEEDER 500%';
  if n>=1 then passes:=passes+1; raise notice 'G1  PASS  2141 → DRONE FEEDER 500';
  else falhas:=falhas+1; raise warning 'G1  FALHA: o código de produto 2141 não acha nada (% hit(s))', n; end if;

  -- G2) segundo codigo exato: 879 = MEDIDOR DE FLUXO DIGITAL
  select count(*) into n from brain.search_knowledge('879') s where s.content like '%MEDIDOR DE FLUXO DIGITAL%';
  if n>=1 then passes:=passes+1; raise notice 'G2  PASS  879 → MEDIDOR DE FLUXO DIGITAL';
  else falhas:=falhas+1; raise warning 'G2  FALHA: o código 879 não acha nada (% hit(s))', n; end if;

  -- G3) busca por descricao
  select count(*) into n from brain.search_knowledge('tanque de água limpa 410 litros pickup') s
   where s.content like '%TANQUE DE AGUA LIMPA 410L%';
  if n>=1 then passes:=passes+1; raise notice 'G3  PASS  descrição em linguagem natural acha o tanque de 410L';
  else falhas:=falhas+1; raise warning 'G3  FALHA'; end if;

  -- G4) preco REVENDAS legivel na linha estruturada
  select count(*) into n from brain.document_chunks c, lateral jsonb_array_elements(c.table_data->'rows') r
   where (r->>2) = '2141' and (r::text like '%11700%' or r::text like '%11.700%');
  if n>=1 then passes:=passes+1; raise notice 'G4  PASS  REVENDAS do 2141 (11.700) na linha estruturada';
  else falhas:=falhas+1; raise warning 'G4  FALHA: REVENDAS do 2141 não está em nenhuma linha'; end if;

  -- G5) preco SUGERIDO legivel
  select count(*) into n from brain.document_chunks c, lateral jsonb_array_elements(c.table_data->'rows') r
   where (r->>2) = '2141' and (r::text like '%16900%' or r::text like '%16.900%');
  if n>=1 then passes:=passes+1; raise notice 'G5  PASS  SUGERIDO do 2141 (16.900) na linha estruturada';
  else falhas:=falhas+1; raise warning 'G5  FALHA: SUGERIDO do 2141 não está em nenhuma linha'; end if;

  -- G6) codigo inexistente
  select count(*) into n from brain.search_knowledge('9999');
  if n=0 then passes:=passes+1; raise notice 'G6  PASS  código inexistente (9999) → zero';
  else falhas:=falhas+1; raise warning 'G6  FALHA: % hit(s)', n; end if;

  -- G7) o codigo do produto tem de estar em `codes`
  select count(*) into n from brain.document_chunks c where c.codes @> array['2141'];
  if n>=1 then passes:=passes+1; raise notice 'G7  PASS  2141 está em codes (coluna CÓDIGO reconhecida)';
  else falhas:=falhas+1; raise warning 'G7  FALHA: NENHUM código de produto entrou em codes'; end if;

  -- G8) o NCM NAO deve ser o identificador da peca
  select count(*) into n from brain.search_knowledge('84368000') s where s.rank_exact is not null;
  if n=0 then passes:=passes+1; raise notice 'G8  PASS  NCM 84368000 não responde pelo braço de código';
  else falhas:=falhas+1; raise warning 'G8  FALHA: o NCM 84368000 entra pelo braço de código em % chunk(s) — é classificação fiscal compartilhada, não identifica peça', n; end if;

  -- G9) proveniencia completa
  select count(*) into n from brain.search_knowledge('DRONE FEEDER 500') s
   where s.source_key='jr_solucoes' and s.version_label='JAN/26' and s.page_from=1
     and s.document_id is not null and s.version_id is not null;
  if n>=1 then passes:=passes+1; raise notice 'G9  PASS  proveniência: fonte jr_solucoes, versão JAN/26, página 1';
  else falhas:=falhas+1; raise warning 'G9  FALHA'; end if;

  -- G10) isolamento: so a fonte JR responde neste banco
  select count(*) into n from brain.search_knowledge('DRONE MIX') s where s.source_key <> 'jr_solucoes';
  if n=0 then passes:=passes+1; raise notice 'G10 PASS  nenhuma outra fonte responde';
  else falhas:=falhas+1; raise warning 'G10 FALHA: % hit(s) de outra fonte', n; end if;

  raise notice '--- GOLDEN JR: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Golden JR com % falha(s)', falhas; end if;
end $$;
GOLDEN
GOK=$?

echo "▶ ADVERSARIAIS"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'ADV'
do $$
declare n int; passes int:=0; falhas int:=0;
begin
  -- A) preco nao vira codigo
  select count(*) into n from brain.document_chunks c
   where c.codes && array['11700','16900','5600','8200','220','330'];
  if n=0 then passes:=passes+1; raise notice 'A  PASS  nenhum preço virou código';
  else falhas:=falhas+1; raise warning 'A  FALHA: % chunk(s) com preço em codes', n; end if;

  -- B) o NCM nao pode dominar a busca por codigo
  select count(*) into n from brain.search_knowledge('84368000');
  if n <= 1 then passes:=passes+1; raise notice 'B  PASS  NCM não devolve o catálogo inteiro (% hit(s))', n;
  else falhas:=falhas+1; raise warning 'B  FALHA: o NCM 84368000 devolve % chunk(s) — uma classificação fiscal virou identificador de peça', n; end if;

  -- C) numero de veiculo dentro da descricao nao e codigo de peca
  select count(*) into n from brain.document_chunks c where c.codes && array['1867','1957'];
  if n=0 then passes:=passes+1; raise notice 'C  PASS  "SAVEIRO 1867 OU STRADA 1957" não virou código de peça';
  else falhas:=falhas+1; raise warning 'C  FALHA'; end if;

  -- D) produto inexistente
  select count(*) into n from brain.search_knowledge('DRONE MIX 9000L TURBO');
  if n=0 then passes:=passes+1; raise notice 'D  PASS  produto inexistente → zero';
  else falhas:=falhas+1; raise warning 'D  FALHA: % hit(s)', n; end if;

  -- E) documento inexistente
  select count(*) into n from brain.search_knowledge('manual da colheitadeira New Holland');
  if n=0 then passes:=passes+1; raise notice 'E  PASS  documento inexistente → zero';
  else falhas:=falhas+1; raise warning 'E  FALHA: % hit(s)', n; end if;

  -- F) tabela degradada nao vaza
  select count(*) into n from brain.search_knowledge('preço revendas sugerido','{}'::jsonb,100,true) s
   where s.kind in ('table','price_table')
     and (coalesce(s.table_data->'audit'->>'quality','trusted')='degraded'
          or coalesce((s.table_data->'audit'->>'fatal')::boolean,false));
  if n=0 then passes:=passes+1; raise notice 'F  PASS  nenhuma tabela degradada na busca';
  else falhas:=falhas+1; raise warning 'F  FALHA: % degradada(s) vazaram', n; end if;

  -- G) toda tabela que a busca aceita tem de ter cabecalho de verdade
  select count(*) into n from brain.document_chunks c
   where c.kind='price_table'
     and coalesce(c.table_data->'audit'->>'quality','trusted')='trusted'
     and exists (select 1 from jsonb_array_elements_text(c.table_data->'labels') l
                  where l ~ '^\d{3,4}$' or l ~ '^\d{8}$');
  if n=0 then passes:=passes+1; raise notice 'G  PASS  nenhuma tabela trusted tem dado no lugar do cabeçalho';
  else falhas:=falhas+1; raise warning 'G  FALHA: % tabela(s) TRUSTED com linha de dados engolida no cabeçalho — a busca aceitaria como evidência', n; end if;

  -- H) nenhuma linha de produto pode se perder
  select coalesce(sum(jsonb_array_length(c.table_data->'rows')),0) into n
    from brain.document_chunks c where c.table_data ? 'rows';
  if n >= 38 then passes:=passes+1; raise notice 'H  PASS  % linhas de produto preservadas (PDF tem 38 legíveis)', n;
  else falhas:=falhas+1; raise warning 'H  FALHA: só % linha(s) preservada(s); o PDF tem 38 legíveis', n; end if;

  -- I) acesso abaixo de commercial nao ve nada
  select count(*) into n from brain.documents d where d.slug='jr-solucoes-tabela-revendas' and d.access_level='commercial';
  if n=1 then passes:=passes+1; raise notice 'I  PASS  documento em nível commercial';
  else falhas:=falhas+1; raise warning 'I  FALHA'; end if;

  -- J) ERP intacto
  select (select count(*) from public.products) + (select count(*) from public.product_costs) into n;
  if n=0 then passes:=passes+1; raise notice 'J  PASS  zero produto/custo criado no ERP pela ingestão';
  else falhas:=falhas+1; raise warning 'J  FALHA: % linha(s) no ERP', n; end if;

  -- K) a fonte e o fabricante, nao a AGROTORK
  select count(*) into n from brain.knowledge_sources
   where key='jr_solucoes' and kind='manufacturer' and external_processing='forbidden';
  if n=1 then passes:=passes+1; raise notice 'K  PASS  fonte é o fabricante, processamento externo proibido';
  else falhas:=falhas+1; raise warning 'K  FALHA'; end if;

  -- L) a versao carrega a competencia declarada
  select count(*) into n from brain.document_versions where version_label='JAN/26' and valid_from='2026-01-01';
  if n=1 then passes:=passes+1; raise notice 'L  PASS  versão JAN/26 com valid_from declarado, não carimbado na ativação';
  else falhas:=falhas+1; raise warning 'L  FALHA'; end if;

  raise notice '--- ADVERSARIAIS JR: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Adversariais JR com % falha(s)', falhas; end if;
end $$;
ADV
AOK=$?

if [ "$GOK" = 0 ] && [ "$AOK" = 0 ]; then
  echo "✔ lote JR ensaiado: golden e adversariais"
else
  echo "✗ LOTE JR BLOQUEADO (golden=$GOK adversariais=$AOK)"
  echo "  As falhas acima NÃO são do ensaio: são da extração deste PDF."
  echo "  Ver docs/brain/fase-2-jr-solucoes.md — em resumo, a tabela não tem"
  echo "  cabeçalho repetido por bloco, então cada bloco engole a primeira"
  echo "  linha de produto como cabeçalho, e só o NCM entra em codes."
  exit 1
fi
