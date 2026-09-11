#!/usr/bin/env bash
# ============================================================
# Confere que os roteiros de supabase/operacao/ não divergiram do código
# versionado. É a resposta a "script externo que envelhece em silêncio".
#
#   bash supabase/db-tests/conferir-operacao.sh
#
# O que se confere:
#   1. `audit_capture-antes-do-brain.sql` é byte a byte o texto da
#      migration 20260909100000 — se alguém editar a migration e esquecer
#      a cópia, a reversão restauraria uma função errada;
#   2. os roteiros aplicam as migrations por `\i`, nunca por cópia colada;
#   3. as versões citadas nos roteiros existem como arquivo.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
FALHAS=0

echo "▶ 1. audit_capture-antes-do-brain.sql × migration 20260909100000"
DA_MIGRATION=$(awk 'NR>=400' supabase/migrations/20260909100000_guards_orcamentos_pedidos.sql \
  | awk '/^\$\$;$/{print; exit} {print}' | md5sum | cut -d' ' -f1)
FIM=$(grep -n '^-- =\+$' supabase/operacao/audit_capture-antes-do-brain.sql | sed -n '2p' | cut -d: -f1)
DA_COPIA=$(tail -n +$((FIM+1)) supabase/operacao/audit_capture-antes-do-brain.sql | md5sum | cut -d' ' -f1)
if [ "$DA_MIGRATION" = "$DA_COPIA" ]; then
  echo "  ✓ idênticas (md5 $DA_COPIA)"
else
  echo "  ✗ divergiram: migration=$DA_MIGRATION cópia=$DA_COPIA"; FALHAS=$((FALHAS+1))
fi

echo "▶ 2. os roteiros aplicam migration por \\i, não por cópia"
if grep -q '^\\i supabase/migrations/' supabase/operacao/02-aplicar-brain.sql; then
  N=$(grep -c '^\\i supabase/migrations/' supabase/operacao/02-aplicar-brain.sql)
  echo "  ✓ 02-aplicar-brain.sql inclui $N migration(s) por \\i"
else
  echo "  ✗ 02-aplicar-brain.sql não usa \\i"; FALHAS=$((FALHAS+1))
fi
if grep -qE '^(create table|create or replace function) (brain|public)\.' supabase/operacao/02-aplicar-brain.sql; then
  echo "  ✗ 02-aplicar-brain.sql tem DDL colado em vez de \\i"; FALHAS=$((FALHAS+1))
else
  echo "  ✓ nenhum DDL de estrutura colado nos roteiros"
fi

echo "▶ 3. toda versão citada existe como arquivo"
for v in $(grep -rhoE "202[0-9]{11}" supabase/operacao/*.sql | sort -u); do
  case "$v" in
    2026090914*) continue;;   # as versões ERRADAS, que o roteiro corrige
  esac
  if ! ls supabase/migrations/${v}_*.sql >/dev/null 2>&1; then
    echo "  ✗ $v citada nos roteiros e sem arquivo em supabase/migrations"; FALHAS=$((FALHAS+1))
  fi
done
[ "$FALHAS" = "0" ] && echo "  ✓ todas as versões citadas têm arquivo"

[ "$FALHAS" = "0" ] && echo "✔ operação confere com o código versionado" || { echo "✗ $FALHAS falha(s)"; exit 1; }
