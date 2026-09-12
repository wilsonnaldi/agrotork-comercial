#!/usr/bin/env bash
# ============================================================
# Ensaio do Lote B da Fase 2 (ingestao sem vetores), de ponta a ponta.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/ensaiar-ingestao.sh
#
# I1  todas as migrations → suite 35 passa (30 asserções, 0 erro)
# I2  worker de verdade: PDF SINTETICO (reportlab) → versao → 3 paginas →
#     chunks → tabela JSONB; busca acha; proveniencia cita a pagina;
#     reexecutar e idempotente; --replace reproduz os mesmos chunks
# I3  testes do worker (pytest, unidade + banco): inclui replace atomico com
#     falha forcada em 4 pontos (D7), primeira ingestao falhada (D8) e
#     duas conexoes na mesma versao (D9)
# I4  06-remover-memoria remove A e B juntos; 03 recusa antes disso;
#     reaplicar as tres migrations → suites 33/34/35 passam de novo
# I5  nada de vetor; nenhum documento real no repositorio (so sinteticos)
# I6  o bucket NAO e criado por migration; o roteiro 07 exige as policies
# I7  rollback SO do Lote B (08): Lote A puro → retrato → aplica B → suite 35
#     → 08 → retrato igual; 33/34 passam; Fase 1 intacta; ledger 010000/020000
#     ficam, 030000 sai; pgvector ausente
# I8  08 recusa com conteudo repetido entre paginas (incompativel com o Lote A)
#
# Requer: python3 com pdfplumber, openpyxl, psycopg, reportlab, pytest
# (brain/worker/requirements.txt). O worker conecta como postgres via
# socket/porta locais — nunca com credencial de producao.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
DB=ensaio_ingestao
FALHAS=0
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -At "$@"; }
ok()  { echo "  ✓ $1"; }
nok() { echo "  ✗ $1"; FALHAS=$((FALHAS+1)); }

# URL de conexao para o worker: socket (unix) ou host TCP, sem senha em texto
# (o ambiente local/CI usa trust ou PGPASSWORD ja exportada).
if [ -S "$H/.s.PGSQL.$P" ]; then DSN="postgresql://$U@/$DB?host=$H&port=$P"; else DSN="postgresql://$U@$H:$P/$DB"; fi
[ -n "${PGPASSWORD:-}" ] && DSN="postgresql://$U:$PGPASSWORD@$H:$P/$DB"

montar() {
  adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  q -q -c "create extension if not exists pgcrypto" -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do
    q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  migration falhou: $f"; return 1; }
  done
  q -q -f supabase/db-tests/registro-producao-20260911.sql >/dev/null 2>&1
  q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260912010000','brain_memoria_esquema'), ('20260912020000','brain_memoria_busca'), ('20260912030000','brain_ingestao') on conflict do nothing" >/dev/null 2>&1
}
suites() { for s in 33_brain_memoria 34_brain_memoria_hardening 35_brain_ingestao; do q -q -f "supabase/db-tests/$s.sql" 2>&1; done; }
retrato_fase1() { q -q -c "select md5(string_agg(x, ',' order by x)) from (select 'tab:'||tablename as x from pg_tables where schemaname='brain' and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges') union all select 'trg:'||tgname||'='||tgenabled::text from pg_trigger where tgname like 'trg_brain%') t"; }

echo "▶ I1: migrations + suite 35"
montar || nok "I1: montagem"
SAIDA=$(q -q -f supabase/db-tests/35_brain_ingestao.sql 2>&1)
N=$(grep -c "NOTICE" <<< "$SAIDA"); E=$(grep -cE "ERROR|FALHOU" <<< "$SAIDA")
if [ "$N" = "30" ] && [ "$E" = "0" ]; then ok "I1: suite 35 — 30 asserções, 0 erro"; else nok "I1: asserções=$N erros=$E"; grep -E "ERROR|FALHOU" <<< "$SAIDA" | head -3; fi

echo "▶ I2: worker de ponta a ponta com PDF sintetico"
TMP=$(mktemp -d)
python3 - "$TMP" <<'EOF' >/dev/null 2>&1 || nok "I2: gerar PDF sintetico"
import sys; from pathlib import Path
sys.path.insert(0, 'brain/worker/tests'); from fixtures import make_catalog_pdf
make_catalog_pdf(Path(sys.argv[1]) / 'catalogo_sintetico.pdf')
EOF
q -q -c "insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values ('ens_sol','Pontas Sol (ensaio)','manufacturer','public','allowed');
         insert into brain.documents (source_key, slug, title, document_type, access_level) values ('ens_sol','ens-catalogo','Catálogo Sol (ensaio)','catalog','public')" >/dev/null
export BRAIN_DB_URL="$DSN"
W1=$(cd brain/worker && python3 -m brain_worker ingest "$TMP/catalogo_sintetico.pdf" --document ens-catalogo --label V1 --ocr never 2>&1)
ST=$(grep -oE "^status: .*" <<< "$W1" | cut -d' ' -f2); PG=$(grep -oE "^pages: .*" <<< "$W1" | cut -d' ' -f2); TB=$(grep -oE "^tables: .*" <<< "$W1" | cut -d' ' -f2)
VID=$(q -c "select v.id from brain.document_versions v join brain.documents d on d.id=v.document_id where d.slug='ens-catalogo'")
SHA=$(sha256sum "$TMP/catalogo_sintetico.pdf" | cut -d' ' -f1)
SHADB=$(q -c "select file_sha256 from brain.document_versions where id='$VID'")
if [ "$ST" = "completed" ] && [ "$PG" = "3" ] && [ "$TB" = "1" ] && [ "$SHA" = "$SHADB" ]; then ok "I2a: worker ingeriu: completed, 3 paginas, 1 tabela, sha256 do arquivo = sha256 da versao"; else nok "I2a: status=$ST pages=$PG tables=$TB sha_ok=$([ "$SHA" = "$SHADB" ] && echo s || echo n)"; echo "$W1" | tail -3; fi
q -q -c "update brain.document_versions set status='active', valid_from=current_date where id='$VID'" >/dev/null
HIT=$(q -c "select kind::text||'|'||page_from||'|'||rank_exact||'|'||(table_data->'rows'->1->>5) from brain.search_knowledge('PS981CAP') limit 1")
CIT=$(q -c "select brain.chunk_provenance(chunk_id)->>'citation' from brain.search_knowledge('PS981CAP') limit 1")
if [ "$HIT" = "table|2|1|0.77" ] && [ "$CIT" = "Pontas Sol (ensaio) — Catálogo Sol (ensaio) V1, p. 2" ]; then ok "I2b: busca acha a tabela da p.2 (rank_exact=1, 0,77 L/min no JSONB); citacao \"$CIT\""; else nok "I2b: hit=$HIT cit=$CIT"; fi
ANTES=$(q -c "select md5(string_agg(ordinal||':'||content_sha256||':'||page_from, '|' order by ordinal)) from brain.document_chunks where version_id='$VID'")
W2=$(cd brain/worker && python3 -m brain_worker ingest "$TMP/catalogo_sintetico.pdf" --document ens-catalogo --label V1 --ocr never 2>&1)
ST2=$(grep -oE "^status: .*" <<< "$W2" | cut -d' ' -f2)
W3=$(cd brain/worker && python3 -m brain_worker ingest "$TMP/catalogo_sintetico.pdf" --document ens-catalogo --label V1 --ocr never --replace 2>&1)
ST3=$(grep -oE "^status: .*" <<< "$W3" | cut -d' ' -f2)
DEPOIS=$(q -c "select md5(string_agg(ordinal||':'||content_sha256||':'||page_from, '|' order by ordinal)) from brain.document_chunks where version_id='$VID'")
NV=$(q -c "select count(*) from brain.document_versions where document_id=(select id from brain.documents where slug='ens-catalogo')")
NI=$(q -c "select count(*) from brain.knowledge_ingestions where version_id='$VID'")
if [ "$ST2" = "skipped" ] && [ "$ST3" = "completed" ] && [ "$ANTES" = "$DEPOIS" ] && [ "$NV" = "1" ] && [ "$NI" = "2" ]; then ok "I2c: reexecutar = skipped (1 versao); --replace reproduz os mesmos chunks ($ANTES); 2 ingestoes no historico"; else nok "I2c: st2=$ST2 st3=$ST3 iguais=$([ "$ANTES" = "$DEPOIS" ] && echo s || echo n) versoes=$NV ingestoes=$NI"; fi
ERP=$(q -c "select count(*) from public.products where code like 'PS98%'")
[ "$ERP" = "0" ] && ok "I2d: nenhum produto criado no ERP pelo worker" || nok "I2d: worker escreveu no ERP ($ERP)"
q -q -c "delete from brain.documents where slug='ens-catalogo'; delete from brain.knowledge_sources where key='ens_sol'" >/dev/null

echo "▶ I3: testes do worker (pytest)"
PT=$(BRAIN_TEST_DB_URL="$DSN" python3 -m pytest brain/worker/tests -q 2>&1 | tail -1)
if grep -qE "^[0-9]+ passed" <<< "$PT" && ! grep -qE "failed|error" <<< "$PT"; then ok "I3: $PT"; else nok "I3: $PT"; fi

echo "▶ I4: remocao (A+B) e reaplicacao"
SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
grep -q "Rode 06-remover-memoria-sem-dados.sql antes" <<< "$SAIDA" && ok "I4a: 03-remover-brain recusa com a memoria aplicada" || nok "I4a"
SAIDA=$(q -f supabase/operacao/06-remover-memoria-sem-dados.sql 2>&1)
RESTO=$(q -c "select (select count(*) from pg_tables where schemaname='brain' and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products','knowledge_queries')) + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('brain_search','brain_provenance')) + (select count(*) from pg_policies where schemaname='storage' and policyname like 'brain_documents%') + (select count(*) from supabase_migrations.schema_migrations where version like '20260912%')")
F1=$(q -c "select count(*) from pg_tables where schemaname='brain' and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges')")
if [ "$RESTO" = "0" ] && [ "$F1" = "9" ]; then ok "I4b: 06 removeu A+B (8 tabelas, 2 funcoes public, 4 policies de storage, 3 registros); Fase 1 com 9 tabelas"; else nok "I4b: resto=$RESTO fase1=$F1"; grep ERROR <<< "$SAIDA" | head -3; fi
for f in supabase/migrations/20260912010000_brain_memoria_esquema.sql supabase/migrations/20260912020000_brain_memoria_busca.sql supabase/migrations/20260912030000_brain_ingestao.sql; do
  q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || nok "I4c: reaplicar $f"
done
SAIDA=$(suites)
N=$(grep -c "NOTICE" <<< "$SAIDA"); E=$(grep -cE "ERROR|FALHOU" <<< "$SAIDA")
if [ "$N" = "59" ] && [ "$E" = "0" ]; then ok "I4c: reaplicado; suites 33/34/35 passam (59 asserções, 0 erro)"; else nok "I4c: asserções=$N erros=$E"; grep -E "ERROR|FALHOU" <<< "$SAIDA" | head -3; fi

echo "▶ I5: nada de vetor; nenhum documento real"
VEC=$(q -c "select (select count(*) from pg_extension where extname='vector') + (select count(*) from information_schema.columns where table_schema='brain' and udt_name in ('vector','halfvec','sparsevec')) + (select count(*) from pg_indexes where schemaname='brain' and (indexdef ilike '%hnsw%' or indexdef ilike '%ivfflat%')) + (select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid join pg_namespace n on n.oid=t.typnamespace where n.nspname='brain' and e.enumlabel ilike '%embed%')")
PDFS=$(git ls-files | grep -ciE '\.(pdf|xlsx|docx|pptx)$' || true)
if [ "$VEC" = "0" ] && [ "$PDFS" = "0" ]; then ok "I5: zero vetor/embedding; zero PDF/XLSX/DOCX versionado (documentos so sinteticos, gerados na hora)"; else nok "I5: vec=$VEC arquivos=$PDFS"; fi

echo "▶ I6: bucket nao nasce por migration; roteiro 07 exige as policies"
B=$(q -c "select count(*) from storage.buckets where id='brain-documents'")
POL=$(q -c "select count(*) from pg_policies where schemaname='storage' and policyname like 'brain_documents%'")
q -q -c "delete from storage.buckets where id='brain-documents'" >/dev/null 2>&1
SAIDA=$(q -f supabase/operacao/07-criar-bucket-brain-documents.sql 2>&1)
B2=$(q -c "select count(*)||'|'||coalesce(max(file_size_limit)::text,'') from storage.buckets where id='brain-documents'")
if [ "$B" = "0" ] && [ "$POL" = "4" ] && [ "$B2" = "1|52428800" ]; then ok "I6: sem bucket apos as migrations; 4 policies; roteiro 07 cria o bucket privado (50 MB) so quando rodado"; else nok "I6: bucket_antes=$B policies=$POL depois=$B2"; grep ERROR <<< "$SAIDA" | head -2; fi

echo "▶ I7: rollback so do Lote B (08) devolve exatamente o Lote A"
montar_ate_a() {
  adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  q -q -c "create extension if not exists pgcrypto" -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do
    case "$f" in *20260912030000*) continue;; esac
    q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  migration falhou: $f"; return 1; }
  done
  q -q -f supabase/db-tests/registro-producao-20260911.sql >/dev/null 2>&1
  q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260912010000','brain_memoria_esquema'), ('20260912020000','brain_memoria_busca') on conflict do nothing" >/dev/null 2>&1
}
retrato() { q -q -f supabase/db-tests/retrato-memoria.sql; }
montar_ate_a || nok "I7: montar Lote A"
RA=$(retrato); F1A=$(retrato_fase1)
q -q -v ON_ERROR_STOP=1 -f supabase/migrations/20260912030000_brain_ingestao.sql >/dev/null 2>&1 || nok "I7: aplicar 030000"
q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260912030000','brain_ingestao') on conflict do nothing" >/dev/null
RB=$(retrato)
SAIDA=$(q -q -f supabase/db-tests/35_brain_ingestao.sql 2>&1); N35=$(grep -c "NOTICE" <<< "$SAIDA"); E35=$(grep -cE "ERROR|FALHOU" <<< "$SAIDA")
SAIDA=$(q -f supabase/operacao/08-remover-lote-b-sem-dados.sql 2>&1)
RA2=$(retrato); F1B=$(retrato_fase1)
LEDGER=$(q -c "select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations where version like '20260912%'")
S=$(for s in 33_brain_memoria 34_brain_memoria_hardening; do q -q -f "supabase/db-tests/$s.sql" 2>&1; done); NA=$(grep -c "NOTICE" <<< "$S"); EA=$(grep -cE "ERROR|FALHOU" <<< "$S")
VEC=$(q -c "select count(*) from pg_extension where extname='vector'")
LIG=$(q -c "select count(*) from pg_trigger where tgname like 'trg_brain%' and tgenabled <> 'D'")
if [ "$RA" != "$RB" ] && [ "$RA" = "$RA2" ] && [ "$N35" = "30" ] && [ "$E35" = "0" ] && [ "$LEDGER" = "20260912010000,20260912020000" ] && [ "$NA" = "29" ] && [ "$EA" = "0" ] && [ "$F1A" = "$F1B" ] && [ "$VEC" = "0" ] && [ "$LIG" = "0" ]; then
  ok "I7: retrato Lote A ($RA) ≠ com B ($RB) e IGUAL apos o 08 ($RA2); suite 35 passou antes (30/0); 33/34 passam depois (29/0); ledger $LEDGER; Fase 1 igual; pontes desligadas; sem vector"
else nok "I7: RA=$RA RB=$RB RA2=$RA2 n35=$N35 e35=$E35 ledger=$LEDGER na=$NA ea=$EA f1=$([ "$F1A" = "$F1B" ] && echo igual || echo DIFERENTE) vec=$VEC lig=$LIG"; grep ERROR <<< "$SAIDA" | head -3; fi

echo "▶ I8: 08 recusa conteudo repetido entre paginas (incompativel com uq_chunk_content do Lote A)"
q -q -v ON_ERROR_STOP=1 -f supabase/migrations/20260912030000_brain_ingestao.sql >/dev/null 2>&1
q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260912030000','brain_ingestao') on conflict do nothing" >/dev/null
q -q -c "insert into brain.knowledge_sources (key, name) values ('ens_dup','Fonte dup');
         insert into brain.documents (id, source_key, slug, title, document_type, access_level) values ('ee000000-0000-4000-8000-000000000001','ens_dup','ens-dup','Dup','other','public');
         select brain.register_version('ee000000-0000-4000-8000-000000000001', 'V1', repeat('dd', 32), 'd.pdf', 'application/pdf', 10, null, 2);" >/dev/null
q -q -c "do \$\$ declare v uuid; i uuid; begin select id into v from brain.document_versions where file_sha256 = repeat('dd', 32);
   i := brain.ingestion_start(v, 'pdf_text', 'x', 'lote-b.1', 'ensaio', false, 2);
   perform brain.ingestion_add_page(i, 1, 'p1', 'text_layer'); perform brain.ingestion_add_page(i, 2, 'p2', 'text_layer');
   perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1, 'rodape repetido'); perform brain.ingestion_add_chunk(i, 1, 'text', 2, 2, 'rodape repetido');
   perform brain.ingestion_finish(i, 'completed'); end \$\$;" >/dev/null
SAIDA=$(q -f supabase/operacao/08-remover-lote-b-sem-dados.sql 2>&1)
AINDA=$(q -c "select (to_regclass('brain.knowledge_queries') is not null)::int + (select count(*) from supabase_migrations.schema_migrations where version='20260912030000')")
if grep -q "conteudo repetido em paginas diferentes" <<< "$SAIDA" && [ "$AINDA" = "2" ]; then ok "I8: 08 parou (conteudo repetido entre paginas) e nada foi removido"; else nok "I8: ainda=$AINDA"; tail -3 <<< "$SAIDA"; fi

rm -rf "$TMP"
adm -c "drop database if exists $DB" >/dev/null
[ "$FALHAS" = "0" ] && echo "✔ ingestao ensaiada nos 8 cenarios" || { echo "✗ $FALHAS falha(s)"; exit 1; }
