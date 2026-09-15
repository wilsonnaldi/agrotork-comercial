#!/usr/bin/env bash
# ============================================================
# Ensaio do lote ARAG: planilha INTERNA da AGROTORK com peças ARAG,
# num PostgreSQL descartável.
#
#   PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
#     bash supabase/db-tests/ensaiar-arag.sh "/caminho/Arag.xlsx"
#
# A planilha NÃO está no repositório: é documento comercial com preço. O
# ensaio recebe o caminho como argumento e por isso não entra no `run.mjs`.
#
# Proveniência: a fonte é a AGROTORK (kind `internal`), NÃO a ARAG. O
# documento é um orçamento interno que cita peças ARAG — chamá-lo de catálogo
# do fabricante seria dar a ele uma autoridade que ele não tem.
#
# G1–G5  golden: os dois códigos do golden, valor estruturado, proveniência
#        por aba e intervalo de linhas, blocos separados, coluna COD
# A–N    adversariais: código parecido, preço/telefone/CNPJ como código,
#        exato × aproximado, linha vazia, cabeçalho, fórmula, contexto entre
#        blocos, código repetido, inexistente, degradado, ERP intacto
#
# A, B e F exigem a migration 20260915120000 (código puramente numérico é
# exato ou nada). Sem ela, a busca resolve um código numérico inexistente
# para o vizinho a um dígito — que foi o bloqueio deste lote.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
XLSX="${1:?informe o caminho da planilha ARAG}"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp/pgrun}"; P="${PGPORT:-5433}"; U="${PGUSER:-postgres}"
DB=ensaio_arag
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -At "$@"; }

echo "▶ banco descartável $DB + migrations"
adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
q -c "create extension if not exists pgcrypto" >/dev/null
q -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql; do q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  ✗ migration $f"; exit 1; }; done
echo "  ok $(ls supabase/migrations/*.sql | wc -l) migrations"

echo "▶ fonte INTERNA da AGROTORK (não é catálogo da ARAG)"
q -c "insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing)
      values ('agrotork_interno','AGROTORK — documentos internos','internal','commercial','forbidden');
      insert into brain.documents (source_key, slug, title, document_type, access_level)
      values ('agrotork_interno','agrotork-orcamento-sistemas-arag',
              'Orçamento interno — sistemas ARAG para bicos','internal_note','commercial')" >/dev/null

echo "▶ ingestão da planilha"
export BRAIN_DB_URL="postgresql://$U@/$DB?host=$H&port=$P"
( cd brain/worker && python3 -m brain_worker ingest "$XLSX" --document agrotork-orcamento-sistemas-arag --label 2024-10 --date 2024-10-17 ) | sed 's/^/  /'
q -c "update brain.document_versions set status='active', valid_from='2024-10-17'" >/dev/null

echo "▶ GOLDEN"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'GOLDEN'
do $$
declare n int; m int; v text; passes int:=0; falhas int:=0;
begin
  -- G1: 466113200 → sensor de pressão, com faixa e valor, citável
  select count(*) into n from brain.search_knowledge('466113200') s
   where s.kind='price_table' and s.content like '%SENSOR PRESSAO%'
     and s.content like '%0-20 BAR%';
  if n>=1 then passes:=passes+1; raise notice 'G1 PASS  466113200 → SENSOR PRESSAO, 0-20 BAR (% evidência(s))', n;
  else falhas:=falhas+1; raise warning 'G1 FALHA'; end if;

  -- G1b: o valor unitário do sensor sai do JSONB, não do texto
  select count(*) into n from brain.search_knowledge('466113200') s,
       lateral jsonb_array_elements(s.table_data->'rows') r
   where (r->>2) like '466113200%' and (r->>7)::numeric = 1098;
  if n>=1 then passes:=passes+1; raise notice 'G1b PASS  valor unitário 1098 lido da linha estruturada';
  else falhas:=falhas+1; raise warning 'G1b FALHA'; end if;

  -- G2: 4626215 → fluxômetro Wolf, 2,5-50 l/min, 1630
  select count(*) into n from brain.search_knowledge('4626215') s
   where s.content like '%FLUXOMETRO WOLF%' and s.content like '%2,5-50 l/min%';
  if n>=1 then passes:=passes+1; raise notice 'G2 PASS  4626215 → FLUXOMETRO WOLF, 2,5-50 l/min';
  else falhas:=falhas+1; raise warning 'G2 FALHA'; end if;
  select count(*) into n from brain.search_knowledge('4626215') s,
       lateral jsonb_array_elements(s.table_data->'rows') r
   where (r->>2) like '4626215%' and (r->>7)::numeric = 1630;
  if n>=1 then passes:=passes+1; raise notice 'G2b PASS  valor unitário 1630 lido da linha estruturada';
  else falhas:=falhas+1; raise warning 'G2b FALHA'; end if;

  -- G3: proveniência de planilha = aba + intervalo de linhas (não "página 1")
  select count(*) into n from brain.document_chunks c
   where c.table_data->'notes' @> '["aba: Página1, linhas 1–8"]'::jsonb;
  select count(*) into m from brain.document_chunks c
   where c.table_data->'notes' @> '["aba: Página1, linhas 10–17"]'::jsonb;
  if n=1 and m=1 then passes:=passes+1; raise notice 'G3 PASS  proveniência por aba e intervalo de linhas nos dois blocos';
  else falhas:=falhas+1; raise warning 'G3 FALHA: n=% m=%', n, m; end if;

  -- G4: os dois blocos são tabelas distintas, cada uma com o seu título
  select count(distinct c.table_data->>'title') into n from brain.document_chunks c where c.kind='price_table';
  if n=2 then passes:=passes+1; raise notice 'G4 PASS  dois blocos, dois títulos (hidráulicos e rotativos)';
  else falhas:=falhas+1; raise warning 'G4 FALHA: % titulo(s)', n; end if;

  -- G5: código declarado na coluna COD vira código mesmo começando por dígito
  select count(*) into n from brain.document_chunks c
   where c.codes @> array['46202G'] and c.table_data->>'title' like '%ROTATIVOS%';
  if n=1 then passes:=passes+1; raise notice 'G5 PASS  46202G (começa por dígito) reconhecido pela coluna COD';
  else falhas:=falhas+1; raise warning 'G5 FALHA'; end if;

  raise notice '--- GOLDEN ARAG: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Golden ARAG com % falha(s)', falhas; end if;
end $$;
GOLDEN
GOK=$?
echo "▶ ADVERSARIAIS"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'ADV'
do $$
declare n int; m int; passes int:=0; falhas int:=0;
begin
  -- A e B) código NUMÉRICO inexistente não pode ser resolvido para o vizinho.
  -- Num código numérico cada dígito é significado: 466113201 é OUTRA peça, não
  -- um erro de digitação de 466113200. Até 20260912040000 o braço aproximado
  -- usava trigrama com limiar 0,6 e, para código numérico longo, um dígito
  -- trocado passava (0,667 e 0,700) — enquanto em código alfanumérico o mesmo
  -- limiar rejeitava corretamente (MJ999CAP × MJ981CAP = 0,385). Estes dois
  -- testes eram o bloqueio do lote ARAG: perguntar por uma peça devolvia o
  -- preço de outra. A migration 20260915120000 fecha isso — par de códigos
  -- puramente numéricos não entra no fuzzy, nem na seleção nem no ranking.
  select count(*) into n from brain.search_knowledge('466113201');
  if n=0 then passes:=passes+1; raise notice 'A PASS  466113201 (inexistente) → zero';
  else falhas:=falhas+1; raise warning 'A FALHA: % hit(s) para código numérico que não existe', n; end if;

  select count(*) into n from brain.search_knowledge('46262150');
  if n=0 then passes:=passes+1; raise notice 'B PASS  46262150 (inexistente) → zero';
  else falhas:=falhas+1; raise warning 'B FALHA: % hit(s) para código numérico que não existe', n; end if;

  -- C) número de preço não é código
  select count(*) into n from brain.document_chunks c where c.codes @> array['1098'] or c.codes @> array['1630'];
  if n=0 then passes:=passes+1; raise notice 'C PASS  preço não virou código';
  else falhas:=falhas+1; raise warning 'C FALHA'; end if;

  -- D) telefone e documento não são código
  select count(*) into n from brain.document_chunks c
   where exists (select 1 from unnest(c.codes) x where x ~ '^(43|12)[0-9]{6,}$');
  if n=0 then passes:=passes+1; raise notice 'D PASS  telefone/CNPJ não viraram código';
  else falhas:=falhas+1; raise warning 'D FALHA'; end if;

  -- E) código exato tem prioridade
  select count(*) into n from brain.search_knowledge('4626215') s where s.rank_exact = 1;
  if n>=1 then passes:=passes+1; raise notice 'E PASS  código exato entra pelo braço exato (rank_exact=1)';
  else falhas:=falhas+1; raise warning 'E FALHA'; end if;

  -- F) código numérico é EXATO OU NADA: nem o vizinho a um dígito nem o distante
  --    respondem. (Antes de 20260915120000 o vizinho respondia — era o defeito.)
  --    O exato continua respondendo, provado em E.
  select count(*) into n from brain.search_knowledge('46611320');
  select count(*) into m from brain.search_knowledge('466119999');
  if n=0 and m=0 then passes:=passes+1; raise notice 'F PASS  46611320 (dígito a menos) e 466119999 (distante) não acham nada — numérico é exato ou nada';
  else falhas:=falhas+1; raise warning 'F FALHA: proximo=% distante=% (esperado 0 e 0)', n, m; end if;

  -- G) linha vazia não virou produto
  select count(*) into n from brain.document_chunks c, lateral jsonb_array_elements(c.table_data->'rows') r
   where c.kind='price_table' and not exists (select 1 from jsonb_array_elements(r) x where x <> 'null'::jsonb);
  if n=0 then passes:=passes+1; raise notice 'G PASS  nenhuma linha vazia virou registro';
  else falhas:=falhas+1; raise warning 'G FALHA: % linha(s)', n; end if;

  -- H) cabeçalho não virou dado
  select count(*) into n from brain.document_chunks c, lateral jsonb_array_elements(c.table_data->'rows') r
   where c.kind='price_table' and (r->>0) = 'QUANTIDADE';
  if n=0 then passes:=passes+1; raise notice 'H PASS  nenhum cabeçalho repetido como linha de dados';
  else falhas:=falhas+1; raise warning 'H FALHA: % linha(s)', n; end if;

  -- I) fórmula não vazou como texto
  select count(*) into n from brain.document_chunks c where c.content like '%=%*%' and c.content ~ '=[A-Z]+[0-9]+\*';
  if n=0 then passes:=passes+1; raise notice 'I PASS  nenhuma fórmula crua no conteúdo';
  else falhas:=falhas+1; raise warning 'I FALHA'; end if;

  -- J) um bloco não empresta contexto ao outro
  select count(*) into n from brain.document_chunks c
   where c.table_data->>'title' like '%HIDRAULICOS%' and c.content like '%ORION%';
  if n=0 then passes:=passes+1; raise notice 'J PASS  item do bloco rotativo não aparece sob o título do hidráulico';
  else falhas:=falhas+1; raise warning 'J FALHA'; end if;

  -- K) código repetido nos dois blocos: as DUAS ocorrências são citadas
  select count(*) into n from brain.search_knowledge('466113200');
  if n=2 then passes:=passes+1; raise notice 'K PASS  466113200 está nos dois sistemas e as duas evidências são devolvidas';
  else falhas:=falhas+1; raise warning 'K FALHA: % hit(s), esperado 2', n; end if;

  -- L) produto inexistente
  select count(*) into n from brain.search_knowledge('MEDIDOR DE VAZAO QUANTICO');
  if n=0 then passes:=passes+1; raise notice 'L PASS  produto inexistente → zero';
  else falhas:=falhas+1; raise warning 'L FALHA: % hit(s)', n; end if;

  -- M) nenhuma tabela degradada entrou; e o fail-closed continua no lugar
  select count(*) into n from brain.document_chunks c
   where c.table_data->'audit'->>'quality' = 'degraded';
  select count(*) into m from brain.document_chunks c where c.kind='price_table';
  if n=0 and m=2 then passes:=passes+1; raise notice 'M PASS  % tabelas, nenhuma degradada', m;
  else falhas:=falhas+1; raise warning 'M FALHA: % degradada(s) de %', n, m; end if;

  -- N) ingestão não escreve no ERP
  select (select count(*) from public.products) + (select count(*) from public.product_costs) into n;
  if n=0 then passes:=passes+1; raise notice 'N PASS  zero produto e zero custo criados no ERP';
  else falhas:=falhas+1; raise warning 'N FALHA: % linha(s)', n; end if;

  raise notice '--- ADVERSARIAIS ARAG: % PASS, % FALHA ---', passes, falhas;
  if falhas > 0 then raise exception 'Adversariais ARAG com % falha(s)', falhas; end if;
end $$;
ADV
AOK=$?

if [ "$GOK" = 0 ] && [ "$AOK" = 0 ]; then
  echo "✔ lote ARAG ensaiado: golden e adversariais"
else
  echo "✗ lote ARAG NAO liberado (golden=$GOK adversariais=$AOK)"
  echo "  A e B cobrem o antigo bloqueio (codigo NUMERICO inexistente resolvido"
  echo "  para o vizinho), fechado pela migration 20260915120000. Se voltarem a"
  echo "  falhar, a migration nao esta aplicada neste banco ou foi revertida."
  echo "  Ver docs/brain/fase-2-arag.md, secao 'Bloqueio para producao'."
  exit 1
fi
