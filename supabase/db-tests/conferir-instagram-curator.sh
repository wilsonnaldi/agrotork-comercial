#!/usr/bin/env bash
# ============================================================
# Confere que as duas migrations do `instagram_curator` continuam sendo
# o texto RECUPERADO de produção, byte a byte, e que um banco novo
# montado do Git reproduz o schema de produção.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/conferir-instagram-curator.sh <banco>
#
# O retrato de produção fica versionado em
# supabase/db-tests/instantaneo-instagram-curator-producao.txt — obtido
# por LEITURA do catálogo em 11/09/2026. Se produção mudar, este teste
# acusa; a resposta certa é olhar o que mudou, não atualizar o retrato.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${1:-ic_conferencia}"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
FALHAS=0

echo "▶ md5 do texto recuperado (o cabeçalho de comentário não conta)"
conferir_md5() {
  local arquivo="$1" esperado="$2" tamanho="$3"
  # O corpo começa depois da última linha de `-- ====` do cabeçalho.
  # Nada de substituição de comando: ela come quebras de linha e o md5
  # deixa de bater por um byte. Corta-se o cabeçalho contando linhas.
  local fim_cabecalho got tam
  fim_cabecalho=$(grep -n '^-- =\+$' "$ROOT/$arquivo" | sed -n '2p' | cut -d: -f1)
  got=$(tail -n +$((fim_cabecalho + 1)) "$ROOT/$arquivo" | md5sum | cut -d' ' -f1)
  tam=$(tail -n +$((fim_cabecalho + 1)) "$ROOT/$arquivo" | wc -c)
  if [ "$got" = "$esperado" ] && [ "$tam" = "$tamanho" ]; then
    echo "  ✓ $(basename "$arquivo"): md5 $got, $tam bytes"
  else
    echo "  ✗ $(basename "$arquivo"): md5 $got (esperado $esperado), $tam bytes (esperado $tamanho)"
    FALHAS=$((FALHAS+1))
  fi
}
conferir_md5 supabase/migrations/20260910151115_create_private_instagram_curator.sql 0f336f8a8991516ff6a30c3ce265296f 11495
conferir_md5 supabase/migrations/20260910151534_harden_private_instagram_curator.sql b405e852576aff7c7eec6d7fc2dbf22d 632

echo "▶ diff de schema: banco novo do Git × retrato de produção"
"$PSQL" -h "$H" -p "$P" -U "$U" -At -d "$DB" \
  -f "$ROOT/supabase/db-tests/comparador-instagram-curator.sql" > /tmp/ic-git.txt
if diff -u "$ROOT/supabase/db-tests/instantaneo-instagram-curator-producao.txt" /tmp/ic-git.txt > /tmp/ic-diff.txt; then
  echo "  ✓ $(wc -l < /tmp/ic-git.txt) itens, zero divergências"
else
  echo "  ✗ divergências:"; cat /tmp/ic-diff.txt; FALHAS=$((FALHAS+1))
fi

[ "$FALHAS" = "0" ] && echo "✔ instagram_curator confere" || { echo "✗ $FALHAS falha(s)"; exit 1; }
