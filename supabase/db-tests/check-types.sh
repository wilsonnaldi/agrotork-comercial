#!/usr/bin/env bash
# ============================================================
# Confere a TIPAGEM contra o schema REAL.
#
# Duas coisas são conferidas, e a segunda é a que importa hoje:
#
#   1. `src/types/database.types.ts` (gerado pelo Supabase) tem todas as
#      tabelas, colunas e enums que as migrations criam;
#   2. `src/types/db.ts` — a camada de domínio — não envelheceu: as listas
#      escritas à mão lá (colunas `numeric` e colunas preenchidas por
#      trigger) continuam batendo com o banco. O TypeScript não tem como
#      conferir isso sozinho: para ele, `numeric` e `integer` são `number`,
#      e trigger não aparece em lugar nenhum.
#
#   bash supabase/db-tests/check-types.sh
# ============================================================
set -euo pipefail

HOST="${PGHOST:-/tmp/pgrun}"
PORT="${PGPORT:-5433}"
USER="${PGUSER:-postgres}"
DB="agrotork_types_$$"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL="psql -h $HOST -p $PORT -U $USER"

$PSQL -q -c "create database $DB;"
trap '$PSQL -q -c "drop database if exists $DB;" >/dev/null 2>&1' EXIT

$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -c "create extension if not exists pgcrypto;"
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$ROOT/supabase/db-tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  $PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f"
done

$PSQL -d "$DB" -t -A -F'|' -c "
  select c.relname, a.attname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid
  where n.nspname = 'public'
    and c.relkind in ('r','v')
    and a.attnum > 0 and not a.attisdropped
  order by c.relname, a.attnum;
" > /tmp/schema-real.txt

$PSQL -d "$DB" -t -A -F'|' -c "
  select t.typname, e.enumlabel
  from pg_type t join pg_enum e on e.enumtypid = t.oid
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public'
  order by t.typname, e.enumsortorder;
" > /tmp/enums-real.txt

$PSQL -d "$DB" -t -A -c "
  select p.proname from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
  order by 1;
" > /tmp/definers-real.txt

# Colunas `numeric` — o gerador não distingue de `integer`.
$PSQL -d "$DB" -t -A -F'|' -c "
  select c.relname, a.attname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid
  join pg_type t on t.oid = a.atttypid
  where n.nspname = 'public' and c.relkind = 'r'
    and a.attnum > 0 and not a.attisdropped and t.typname = 'numeric'
  order by 1, 2;
" > /tmp/numeric-real.txt

# Colunas `not null` SEM default: o insert só funciona se algo as preencher.
$PSQL -d "$DB" -t -A -F'|' -c "
  select c.relname, a.attname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid
  left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
  where n.nspname = 'public' and c.relkind = 'r'
    and a.attnum > 0 and not a.attisdropped
    and a.attnotnull and d.adbin is null and a.attidentity = ''
  order by 1, 2;
" > /tmp/required-real.txt

node "$ROOT/supabase/db-tests/check-types.mjs"
