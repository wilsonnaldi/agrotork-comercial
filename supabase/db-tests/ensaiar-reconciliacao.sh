#!/usr/bin/env bash
# ============================================================
# Ensaio da reconciliação do registro de migrations.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/ensaiar-reconciliacao.sh
#
# Monta uma CÓPIA do registro de produção (as 53 linhas de 11/09/2026,
# lidas do catálogo) num banco descartável e roda o script de verdade —
# o mesmo arquivo que iria para o SQL Editor, sem adaptação.
#
# Cenários:
#   R1  estado real de produção    → acerta as 9, Git e banco coincidem
#   R2  segunda execução           → tudo "já acertada", nada muda
#   R3  nome divergente na origem  → ABORTA, registro intacto
#   R4  versão ausente             → ABORTA, registro intacto
#   R5  conflito (as duas versões) → ABORTA, registro intacto
#   R6  registro remoto sem arquivo no Git → ABORTA
#
# Em R3 a R6 o que se mede não é a mensagem: é que NADA foi gravado.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
DB=ensaio_registro
FALHAS=0

adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -At "$@"; }

montar() {
  adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  q -q -f "$ROOT/supabase/db-tests/registro-producao-20260911.sql" >/dev/null
}

rodar() { q -f "$ROOT/supabase/operacao/01-reconciliar-registro.sql" 2>&1; }

impressao() { q -c "select md5(string_agg(version || '|' || coalesce(name,''), ',' order by version)) from supabase_migrations.schema_migrations"; }

conferir_intacto() {
  local rotulo="$1" antes="$2"
  local depois; depois=$(impressao)
  if [ "$antes" = "$depois" ]; then
    echo "  ✓ $rotulo: registro INTACTO (md5 $antes)"
  else
    echo "  ✗ $rotulo: o registro MUDOU ($antes → $depois)"; FALHAS=$((FALHAS+1))
  fi
}

echo "▶ R1: estado real de produção"
montar
ANTES=$(impressao)
SAIDA=$(rodar)
if echo "$SAIDA" | grep -q "9 acertada(s) agora, 0 ja estava" && echo "$SAIDA" | grep -q "Git e producao coincidem"; then
  ERRADAS=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '2026090914%'")
  COPIA=$(q -c "select count(*) from supabase_migrations.schema_migrations_antes_20260911")
  TOTAL=$(q -c "select count(*) from supabase_migrations.schema_migrations")
  if [ "$ERRADAS" = "0" ] && [ "$COPIA" = "53" ] && [ "$TOTAL" = "53" ]; then
    echo "  ✓ R1: 9 acertadas, 0 versões erradas, cópia com 53 linhas, total 53"
  else
    echo "  ✗ R1: erradas=$ERRADAS copia=$COPIA total=$TOTAL"; FALHAS=$((FALHAS+1))
  fi
else
  echo "  ✗ R1 não concluiu:"; echo "$SAIDA" | tail -5; FALHAS=$((FALHAS+1))
fi

echo "▶ R2: segunda execução na mesma base"
DEPOIS_R1=$(impressao)
SAIDA=$(q -c "alter table supabase_migrations.schema_migrations_antes_20260911 rename to schema_migrations_antes_20260911_r1" 2>&1; rodar)
if echo "$SAIDA" | grep -q "0 acertada(s) agora, 9 ja estava"; then
  conferir_intacto "R2" "$DEPOIS_R1"
else
  echo "  ✗ R2 não relatou 'já acertadas':"; echo "$SAIDA" | tail -5; FALHAS=$((FALHAS+1))
fi

echo "▶ R3: nome divergente na origem"
montar
q -q -c "update supabase_migrations.schema_migrations set name = 'outra_coisa' where version = '20260909143930'" >/dev/null
ANTES=$(impressao)
SAIDA=$(rodar)
echo "$SAIDA" | grep -q "o nome nao e" && echo "  ✓ R3: abortou com a mensagem certa" || { echo "  ✗ R3: mensagem inesperada"; echo "$SAIDA" | tail -3; FALHAS=$((FALHAS+1)); }
conferir_intacto "R3" "$ANTES"

echo "▶ R4: versão ausente"
montar
q -q -c "delete from supabase_migrations.schema_migrations where version = '20260909144028'" >/dev/null
ANTES=$(impressao)
SAIDA=$(rodar)
echo "$SAIDA" | grep -q "nao existe nem a versao errada" && echo "  ✓ R4: abortou com a mensagem certa" || { echo "  ✗ R4: mensagem inesperada"; echo "$SAIDA" | tail -3; FALHAS=$((FALHAS+1)); }
conferir_intacto "R4" "$ANTES"

echo "▶ R5: conflito — a versão de destino já ocupada"
montar
q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260903140000','compras')" >/dev/null
ANTES=$(impressao)
SAIDA=$(rodar)
echo "$SAIDA" | grep -q "existem AS DUAS versoes" && echo "  ✓ R5: abortou com a mensagem certa" || { echo "  ✗ R5: mensagem inesperada"; echo "$SAIDA" | tail -3; FALHAS=$((FALHAS+1)); }
conferir_intacto "R5" "$ANTES"

echo "▶ R6: registro remoto sem arquivo no Git"
montar
q -q -c "insert into supabase_migrations.schema_migrations (version, name) values ('20260910999999','migration_fantasma')" >/dev/null
ANTES=$(impressao)
SAIDA=$(rodar)
echo "$SAIDA" | grep -q "Registro no banco sem arquivo no Git" && echo "  ✓ R6: abortou com a mensagem certa" || { echo "  ✗ R6: mensagem inesperada"; echo "$SAIDA" | tail -3; FALHAS=$((FALHAS+1)); }
conferir_intacto "R6" "$ANTES"

adm -c "drop database if exists $DB" >/dev/null
[ "$FALHAS" = "0" ] && echo "✔ reconciliação ensaiada nos 6 cenários" || { echo "✗ $FALHAS falha(s)"; exit 1; }
