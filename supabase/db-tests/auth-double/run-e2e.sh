#!/usr/bin/env bash
# ============================================================
# Executa as validações de ponta a ponta contra o duplê.
#
#   BASE_URL=http://localhost:3402 bash supabase/db-tests/auth-double/run-e2e.sh
#
# Cada suíte roda com o banco recém-semeado, porque ambas contam
# registros e uma suja o estado da outra.
#
# Pré-requisitos: duplê no ar e a aplicação servindo em BASE_URL.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

for suite in e2e-autenticacao.mjs e2e-clientes.mjs e2e-produtos.mjs e2e-cadastros.mjs e2e-kits.mjs e2e-orcamentos.mjs e2e-pdf-compartilhamento.mjs e2e-empresa-usuarios.mjs e2e-relatorios.mjs e2e-expiracao.mjs e2e-auditoria.mjs; do
  echo "▶ semeando banco"
  bash supabase/db-tests/dev-seed.sh > /dev/null
  # Recriar o banco derruba o pool do duplê; dá tempo de reconectar.
  sleep 2
  curl -s -o /dev/null "${BASE_URL:-http://localhost:3402}/login" || true
  echo "▶ $suite"
  node "supabase/db-tests/auth-double/$suite"
done
