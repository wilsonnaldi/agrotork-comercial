#!/usr/bin/env bash
# ============================================================
# Diz, em segundos, se a camada de tipos está inteira nesta cópia.
#
#   bash supabase/db-tests/check-arquitetura.sh
#
# Serve para quando `npm run typecheck` acusa dezenas de erros espalhados:
# quase sempre é UM destes cinco pontos faltando, não dezenas de problemas.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
falhas=0
ok()   { printf '  ✔ %s\n' "$1"; }
nao()  { printf '  ✗ %s\n' "$1"; falhas=$((falhas + 1)); }

echo "▶ camada de domínio dos tipos"

[ -f src/types/db.ts ] \
  && ok "src/types/db.ts existe" \
  || nao "src/types/db.ts NÃO existe — é a camada inteira; sem ela nada abaixo funciona"

if grep -q "AcceptsDecimalString" src/types/db.ts 2>/dev/null; then
  ok "ampliação numeric -> string decimal presente"
else
  nao "src/types/db.ts sem AcceptsDecimalString — cópia parcial/antiga do arquivo"
fi

if grep -q "TriggerOwned" src/types/db.ts 2>/dev/null; then
  ok "colunas preenchidas por trigger declaradas"
else
  nao "src/types/db.ts sem TriggerOwned — o insert de orçamento vai exigir number/sequence_*"
fi

clientes=$(grep -l "AppDatabase" src/lib/supabase/server.ts src/lib/supabase/proxy.ts src/lib/supabase/admin.ts 2>/dev/null | wc -l)
[ "$clientes" -eq 3 ] \
  && ok "os 3 clientes Supabase usam AppDatabase" \
  || nao "só $clientes de 3 clientes usam AppDatabase — os outros voltaram a usar o Database gerado"

diretos=$(grep -rl '@/types/database.types' src/ 2>/dev/null | grep -v '^src/types/db.ts$' | wc -l)
[ "$diretos" -eq 0 ] \
  && ok "só src/types/db.ts importa o arquivo gerado" \
  || { nao "$diretos arquivo(s) importam @/types/database.types direto:"; \
       grep -rl '@/types/database.types' src/ | grep -v '^src/types/db.ts$' | sed 's/^/      /'; }

narrow=$(grep -rc "toProductListRow\|toKitListRow\|toQuoteListRow\|assertColumns" src/modules 2>/dev/null | grep -v ':0$' | wc -l)
[ "$narrow" -ge 5 ] \
  && ok "repositories aplicam as projeções de view ($narrow arquivos)" \
  || nao "só $narrow arquivo(s) aplicam as projeções — os repositories são de uma versão anterior"

echo
if [ "$falhas" -eq 0 ]; then
  echo "✔ camada de tipos íntegra. Se o typecheck ainda acusar erro, é outra causa."
else
  echo "✗ $falhas ponto(s) faltando. Corrija-os ANTES de mexer nos módulos:"
  echo "  os erros espalhados em repositories e páginas são consequência, não causa."
  exit 1
fi
