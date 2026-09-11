#!/usr/bin/env bash
# ============================================================
# Gera supabase/operacao/02-aplicar-brain.sql a partir do template,
# embutindo o texto das migrations onde há `-- @incluir <arquivo>`.
#
#   bash supabase/operacao/gerar-consolidado.sh
#
# Existe para que haja UM caminho de execução — colar no SQL Editor —
# sem que o roteiro vire uma cópia das migrations que envelhece sozinha.
# `conferir-operacao.sh` regera e compara: se alguém editar a migration e
# esquecer de regerar, o teste acusa.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TEMPLATE="${TEMPLATE:-supabase/operacao/02-aplicar-brain.template.sql}"
SAIDA="${1:-supabase/operacao/02-aplicar-brain.sql}"

: > "$SAIDA"
while IFS= read -r linha; do
  case "$linha" in
    "-- @incluir "*)
      arquivo="${linha#-- @incluir }"
      [ -f "$arquivo" ] || { echo "gerar-consolidado: $arquivo nao existe" >&2; exit 1; }
      {
        echo ""
        echo "-- ────────────────────────────────────────────────────────────"
        echo "-- INCLUIDO DE: $arquivo"
        echo "-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)"
        echo "-- ────────────────────────────────────────────────────────────"
        cat "$arquivo"
        echo ""
      } >> "$SAIDA"
      ;;
    *)
      printf '%s\n' "$linha" >> "$SAIDA"
      ;;
  esac
done < "$TEMPLATE"
echo "gerado: $SAIDA ($(wc -l < "$SAIDA") linhas)"
