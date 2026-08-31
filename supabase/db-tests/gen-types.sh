#!/usr/bin/env bash
# ============================================================
# Gera `src/types/database.types.ts` a partir das migrations, em um
# PostgreSQL local descartável — mesmo formato que o Supabase entrega.
#
#   npm run db:types:local
#
# O comando oficial continua sendo `npm run db:types` (Supabase, projeto
# vinculado). Este aqui existe para quem precisa do arquivo sem projeto
# provisionado, e para conferir offline que a tipagem bate com o schema.
# ============================================================
set -euo pipefail

HOST="${PGHOST:-127.0.0.1}"; PORT="${PGPORT:-5433}"; USER="${PGUSER:-postgres}"
DB="agrotork_types_$$"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL="psql -h $HOST -p $PORT -U $USER"

$PSQL -q -c "create database $DB;"
trap '$PSQL -q -c "drop database if exists $DB;" >/dev/null 2>&1' EXIT

$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -c "create extension if not exists pgcrypto;"
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$ROOT/supabase/db-tests/00_supabase_stub.sql" > /dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do
  $PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f" > /dev/null
done

$PSQL -d "$DB" -At -f "$ROOT/supabase/db-tests/introspect.sql" > "/tmp/$DB.json"
node "$ROOT/supabase/db-tests/gen-types.mjs" "/tmp/$DB.json" > "$ROOT/src/types/database.types.ts"
rm -f "/tmp/$DB.json"

echo "✔ src/types/database.types.ts gerado a partir das migrations"
