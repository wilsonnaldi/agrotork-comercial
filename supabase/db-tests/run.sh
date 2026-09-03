#!/usr/bin/env bash
# ============================================================
# Executa todas as migrations em um PostgreSQL local e valida
# as regras de negócio, o RLS e os privilégios.
#
# Uso:  bash supabase/db-tests/run.sh
# Requer: PostgreSQL 15+ instalado localmente (psql no PATH).
#
# Não toca no projeto do Supabase — usa um banco descartável.
# ============================================================
set -euo pipefail

HOST="${PGHOST:-/tmp/pgrun}"
PORT="${PGPORT:-5433}"
USER="${PGUSER:-postgres}"
DB="agrotork_check_$$"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL="psql -h $HOST -p $PORT -U $USER"

echo "▶ criando banco temporário $DB"
$PSQL -q -c "create database $DB;"
trap '$PSQL -q -c "drop database if exists $DB;" >/dev/null 2>&1' EXIT

$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -c "create extension if not exists pgcrypto;"
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$ROOT/supabase/db-tests/00_supabase_stub.sql"

echo "▶ aplicando migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  $PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f"
  echo "  ok $(basename "$f")"
done

echo "▶ regras de negócio"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/01_regras_de_negocio.sql" | grep -E "^ [0-9]+[a-z]?\)" || true
echo "▶ row level security"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/02_rls.sql" 2>&1 | grep -E "^ [A-K]\)|NOTICE" || true
echo "▶ travas de orçamento e perfil"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/04_travas_de_orcamento.sql" 2>&1 | grep -E "^ [P-U]\)|NOTICE|BRECHA|OK:" || true
echo "▶ isolamento do custo do produto"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/05_custo_produto.sql" 2>&1 | grep -E "^ [V-Z]\)|^ A[A-C]\)|NOTICE" || true
echo "▶ origem do produto e código do fabricante"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/06_origem_produto.sql" 2>&1 | grep -E "^ A[D-N]\)|NOTICE" || true
echo "▶ cadastros de apoio (marcas, categorias, unidades)"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/07_cadastros.sql" 2>&1 | grep -E "^ B[A-Z]\)|NOTICE" || true
echo "▶ kits: obrigatórios e opcionais"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/08_kits.sql" 2>&1 | grep -E "^ [CD][A-Z]\)|NOTICE" || true
echo "▶ orçamentos: itens, kits, opcionais, descontos e histórico"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/09_orcamentos.sql" 2>&1 | grep -E "^ [DEF][A-Z]\)|NOTICE" || true
echo "▶ compartilhamento: token, expiração, revogação e vazamento"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/10_compartilhamento.sql" 2>&1 | grep -E "^ [FG][A-Z]\)|NOTICE" || true
echo "▶ storage: buckets, leitura pública e escrita de admin"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/11_storage.sql" 2>&1 | grep -E "^ G[A-Z]\)|NOTICE" || true
echo "▶ triggers e privilégios"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/03_triggers_e_privilegios.sql" 2>&1 | grep -E "^ [L-O]\)|NOTICE|ORC-" || true

echo "▶ pedido de venda: conversão, congelamento e situações"
$PSQL -d "$DB" -f "$ROOT/supabase/db-tests/18_pedidos.sql" 2>&1 | grep -E "PV[0-9]+\)|NOTICE" || true

echo "✔ concluído"
