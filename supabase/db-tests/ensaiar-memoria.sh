#!/usr/bin/env bash
# ============================================================
# Ensaio do Lote A da Fase 2 (memoria corporativa), em PostgreSQL 17.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/ensaiar-memoria.sh
#
# M1  todas as migrations → suites 33 e 34 passam (17 + 12 asserções, 0 erro)
# M2  a Fase 1 continua igual: 9 tabelas, 3 pontes desligadas, suite 25
# M3  06-remover-memoria: com dados, PARA; sem dados, remove e a Fase 1
#     fica intacta (retrato antes = depois)
# M4  reaplicar as duas migrations depois da remocao → suites 33 e 34 passam de novo
# M5  03-remover-brain (Fase 1) recusa rodar com o Lote A aplicado
# M6  pgvector: nao instalado, nenhuma coluna/indice vetorial, nenhum rotulo
#     "embedding" em enum, nenhuma funcao/tabela com "embedding" no nome
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
DB=ensaio_memoria
FALHAS=0
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -At "$@"; }
ok()  { echo "  ✓ $1"; }
nok() { echo "  ✗ $1"; FALHAS=$((FALHAS+1)); }

montar() {
  adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  q -q -c "create extension if not exists pgcrypto" -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do
    q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  migration falhou: $f"; return 1; }
  done
  q -q -f supabase/db-tests/registro-producao-20260911.sql >/dev/null 2>&1
  q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260912010000','brain_memoria_esquema'), ('20260912020000','brain_memoria_busca') on conflict do nothing" >/dev/null 2>&1
}
suite33() { q -q -f supabase/db-tests/33_brain_memoria.sql 2>&1; q -q -f supabase/db-tests/34_brain_memoria_hardening.sql 2>&1; }
retrato_fase1() { q -q -c "select md5(string_agg(x, ',' order by x)) from (select 'tab:'||tablename as x from pg_tables where schemaname='brain' and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges') union all select 'trg:'||tgname||'='||tgenabled::text from pg_trigger where tgname like 'trg_brain%') t"; }

echo "▶ M1: migrations + suites 33 e 34"
montar || nok "M1: montagem"
SAIDA=$(suite33)
N=$(grep -c "NOTICE" <<< "$SAIDA"); E=$(grep -cE "ERROR|FALHOU" <<< "$SAIDA")
if [ "$N" = "29" ] && [ "$E" = "0" ]; then ok "M1: suites 33 e 34 — 29 asserções, 0 erro"; else nok "M1: asserções=$N erros=$E"; grep -E "ERROR|FALHOU" <<< "$SAIDA" | head -3; fi

echo "▶ M2: Fase 1 intacta ao lado do Lote A"
TAB=$(q -q -c "select count(*) from pg_tables where schemaname='brain' and tablename in ('channels','attributions','leads','identities','interactions','opportunities','tasks','events','lead_merges')")
PONTES=$(q -q -c "select count(*) from pg_trigger where tgname like 'trg_brain%'")
LIGADAS=$(q -q -c "select count(*) from pg_trigger where tgname like 'trg_brain%' and tgenabled <> 'D'")
# As suites da Fase 1 na ordem da bateria (27 limpa o que 25 deixa; rodar 30
# logo depois de 25 falha por isso, com ou sem o Lote A).
#
# Linha de base HONESTA: a suite 25 foi escrita para o modo acoplado e, em
# producao desacoplada (pontes desligadas, cron reconcilia), cinco cenarios
# dela ja falhavam em 7973444 — BR4, BR5, BR6, BR9, BR16 — porque esperam
# o evento no mesmo instante do UPDATE. Isso e pendencia da Fase 1, nao
# deste lote. O que se exige aqui e: exatamente essas cinco, nenhuma a mais,
# e zero ERROR/FALHA nas demais suites. As suites imprimem "FALHA:" e
# "FALHOU:"; as duas grafias contam.
BASE25="BR16 BR4 BR5 BR6 BR9"
EF1=0; NF1=0; FALHAS25=""
for s in 25_brain 27_brain_exclusoes 28_brain_pontes 29_brain_volatilidade 30_brain_reconciliacao 31_brain_fidelidade 32_brain_policies; do
  S=$(q -q -f "supabase/db-tests/$s.sql" 2>&1)
  NF1=$((NF1 + $(grep -c "NOTICE" <<< "$S")))
  if [ "$s" = "25_brain" ]; then
    FALHAS25=$(grep -oE "BR[0-9]+\) FALHA" <<< "$S" | sed 's/) FALHA//' | sort | tr '\n' ' ' | sed 's/ $//')
    EF1=$((EF1 + $(grep -cE "ERROR" <<< "$S")))
  else
    EF1=$((EF1 + $(grep -cE "ERROR|FALHA" <<< "$S")))
  fi
done
if [ "$TAB" = "9" ] && [ "$PONTES" = "3" ] && [ "$LIGADAS" = "0" ] && [ "$EF1" = "0" ] && [ "$FALHAS25" = "$BASE25" ]; then
  ok "M2: 9 tabelas da Fase 1, 3 pontes desligadas, suites 27–32 verdes e suite 25 com as mesmas 5 falhas herdadas do modo desacoplado ($NF1 asserções) ao lado do Lote A"
else nok "M2: tab=$TAB pontes=$PONTES ligadas=$LIGADAS erros=$EF1 falhas25=[$FALHAS25] esperado=[$BASE25]"; fi

echo "▶ M3: 06-remover-memoria — com dados PARA; sem dados remove"
q -q -c "insert into brain.knowledge_sources (key, name) values ('ensaio', 'Fonte do ensaio')" >/dev/null
SAIDA=$(q -f supabase/operacao/06-remover-memoria-sem-dados.sql 2>&1)
EXISTE=$(q -q -c "select count(*) from pg_tables where schemaname='brain' and tablename='document_chunks'")
if grep -q "A MEMORIA TEM CONTEUDO" <<< "$SAIDA" && [ "$EXISTE" = "1" ]; then ok "M3a: com 1 linha, parou e nada foi removido"; else nok "M3a: existe=$EXISTE"; tail -3 <<< "$SAIDA"; fi
q -q -c "delete from brain.knowledge_sources where key='ensaio'" >/dev/null
ANTES=$(retrato_fase1)
SAIDA=$(q -f supabase/operacao/06-remover-memoria-sem-dados.sql 2>&1)
DEPOIS=$(retrato_fase1)
EXISTE=$(q -q -c "select count(*) from pg_tables where schemaname='brain' and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products')")
TIPOS=$(q -q -c "select count(*) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='brain' and t.typname in ('access_level','knowledge_hit')")
REG=$(q -q -c "select count(*) from supabase_migrations.schema_migrations where version like '20260912%'")
DIV=$(q -q -c "select count(*) from brain.divergencias_erp()")
if [ "$EXISTE" = "0" ] && [ "$TIPOS" = "0" ] && [ "$REG" = "0" ] && [ "$ANTES" = "$DEPOIS" ] && [ "$DIV" = "0" ]; then
  ok "M3b: sem dados removeu tudo do Lote A; Fase 1 com o mesmo retrato ($ANTES); divergencias_erp() responde"
else nok "M3b: existe=$EXISTE tipos=$TIPOS reg=$REG antes=$ANTES depois=$DEPOIS div=$DIV"; grep ERROR <<< "$SAIDA" | head -3; fi

echo "▶ M4: reaplicar depois da remocao"
for f in supabase/migrations/20260912010000_brain_memoria_esquema.sql supabase/migrations/20260912020000_brain_memoria_busca.sql; do
  q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || nok "M4: reaplicar $f"
done
SAIDA=$(suite33)
N=$(grep -c "NOTICE" <<< "$SAIDA"); E=$(grep -cE "ERROR|FALHOU" <<< "$SAIDA")
if [ "$N" = "29" ] && [ "$E" = "0" ]; then ok "M4: reaplicado, suites 33 e 34 passam de novo (29/0)"; else nok "M4: asserções=$N erros=$E"; fi

echo "▶ M5: 03-remover-brain recusa com o Lote A aplicado"
SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
EXISTE=$(q -q -c "select count(*) from pg_namespace where nspname='brain'")
if grep -q "Rode 06-remover-memoria-sem-dados.sql antes" <<< "$SAIDA" && [ "$EXISTE" = "1" ]; then ok "M5: 03 parou e mandou rodar o 06 primeiro; schema de pe"; else nok "M5: existe=$EXISTE"; tail -3 <<< "$SAIDA"; fi

echo "▶ M6: nada de vetor"
VEC=$(q -q -c "select (select count(*) from pg_extension where extname='vector') + (select count(*) from information_schema.columns where table_schema='brain' and udt_name in ('vector','halfvec','sparsevec')) + (select count(*) from pg_indexes where schemaname='brain' and (indexdef ilike '%hnsw%' or indexdef ilike '%ivfflat%'))")
EMB=$(q -q -c "select (select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid join pg_namespace n on n.oid=t.typnamespace where n.nspname='brain' and e.enumlabel ilike '%embed%') + (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='brain' and c.relname ilike '%embed%') + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='brain' and p.proname ilike '%embed%')")
if [ "$VEC" = "0" ] && [ "$EMB" = "0" ]; then ok "M6: pgvector nao instalado, zero colunas/indices vetoriais, nenhum rotulo/objeto 'embedding'"; else nok "M6: vec=$VEC emb=$EMB"; fi

adm -c "drop database if exists $DB" >/dev/null
[ "$FALHAS" = "0" ] && echo "✔ memoria corporativa ensaiada nos 6 cenarios" || { echo "✗ $FALHAS falha(s)"; exit 1; }
