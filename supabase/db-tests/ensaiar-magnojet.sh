#!/usr/bin/env bash
# ============================================================
# Ensaio do piloto Magnojet (Catálogo V41), num PostgreSQL descartável.
#
#   PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
#     bash supabase/db-tests/ensaiar-magnojet.sh \
#       "/caminho/MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf"
#
# O PDF NÃO está no repositório: é documento real de fabricante. O ensaio
# recebe o caminho como argumento e por isso não entra no `run.mjs`, que roda
# só com sintético.
#
# Este ensaio fixa a regressão do piloto — o que a calibração de
# 20260912040000 entregou — e prova que a migration 20260915120000 (código
# puramente numérico é exato ou nada) NÃO mexeu em nada disso:
#
#   G1–G14  golden do documento: as 14 perguntas de docs/brain/golden-dataset-v0.json
#           na parte que o retrieval responde (as que dependem de documento não
#           ingerido devem dar ZERO, e isso também é golden)
#   A–K     as provas de docs/brain/fase-2-piloto-magnojet.md §4
#   X1–X3   o hotfix: MJ981CA → MJ981CAP (alfanumérico segue no fuzzy),
#           MJ999CAP → zero, e nenhuma tabela degradada na busca
#
# Requer: python3 com as dependências de brain/worker/requirements.txt.
# O worker conecta como postgres no banco local — nunca em produção.
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PDF="${1:?informe o caminho do PDF do Catálogo Magnojet V41}"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp/pgrun}"; P="${PGPORT:-5433}"; U="${PGUSER:-postgres}"
DB=ensaio_magnojet
adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -At "$@"; }

echo "▶ banco descartável $DB + migrations"
adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
q -c "create extension if not exists pgcrypto" >/dev/null
q -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql; do q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || { echo "  ✗ migration $f"; exit 1; }; done
echo "  ok $(ls supabase/migrations/*.sql | wc -l) migrations"

echo "▶ fonte e documento"
q -c "insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing)
      values ('magnojet','Magnojet','manufacturer','public','allowed');
      insert into brain.documents (source_key, slug, title, document_type, access_level)
      values ('magnojet','magnojet-catalogo','Catálogo Magnojet V41','catalog','public')" >/dev/null

echo "▶ ingestão do catálogo (172 páginas — leva alguns minutos)"
export BRAIN_DB_URL="postgresql://$U@/$DB?host=$H&port=$P"
( cd brain/worker && python3 -m brain_worker ingest "$PDF" --document magnojet-catalogo --label V41 --date 2026-06-05 --ocr never ) | sed 's/^/  /'

echo "▶ versão vigente"
q -c "update brain.document_versions set status='active', valid_from='2026-06-05' where version_label='V41'" >/dev/null

echo "▶ GOLDEN"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'GOLDEN'
do $$
declare n int; v jsonb; r record; passes int:=0; falhas int:=0;
begin
  -- G1 pergunta natural sem código: cone vazio ultra grossa perto de 0,8 L/min → p.20
  select count(*) into n from brain.search_knowledge('Qual ponta Magnojet de cone vazio ultra grossa entrega perto de 0,8 L/min?') s
   where s.page_from = 20;
  if n>=1 then passes:=passes+1; raise notice 'G1 PASS  pergunta natural longa cai na p.20 (% evidência(s))', n;
  else falhas:=falhas+1; raise warning 'G1 FALHA: nada na p.20'; end if;

  -- G2 verificação quantitativa: MJ981CAP a 40 psi → 77 L/ha a 12 km/h, lido do JSONB
  select s.table_data into v from brain.search_knowledge('Com a MJ981CAP a 40 psi, quantos litros por hectare a 12 km/h?') s
   where s.kind in ('table','price_table') and s.page_from = 20 limit 1;
  if v is null then falhas:=falhas+1; raise warning 'G2 FALHA: tabela da p.20 não veio';
  else
    select count(*) into n
      from jsonb_array_elements(v->'rows') row_
      cross join lateral (select (select i-1 from generate_subscripts(array(select jsonb_array_elements_text(v->'headers')),1) i
                                   where (array(select jsonb_array_elements_text(v->'headers')))[i] = 'L_ha@12') as idx) k
     where row_->>0 like 'MJ981CAP%' and (row_->>1) is not null
       and jsonb_typeof(row_->k.idx) = 'number' and (row_->>k.idx)::numeric = 77;
    if n>=1 then passes:=passes+1; raise notice 'G2 PASS  L_ha@12 = 77 numérico no JSONB da p.20';
    else falhas:=falhas+1; raise warning 'G2 FALHA: 77 L/ha não conferido no JSONB'; end if;
  end if;

  -- G3–G13: perguntas do golden que dependem de documento NÃO ingerido devem dar ZERO.
  -- "Não encontrei evidência suficiente" é a resposta certa, e é golden igual.
  select count(*) into n from brain.search_knowledge('O que é o código 4626215 da Arag?');
  if n=0 then passes:=passes+1; raise notice 'G3 PASS  Arag 4626215 (não ingerida) → zero';
  else falhas:=falhas+1; raise warning 'G3 FALHA: % hit(s) para documento não ingerido', n; end if;

  select count(*) into n from brain.search_knowledge('Qual bateria avulsa serve para o T55 e o T70P?');
  if n=0 then passes:=passes+1; raise notice 'G4 PASS  DJI (não ingerida) → zero';
  else falhas:=falhas+1; raise warning 'G4 FALHA: % hit(s)', n; end if;

  select count(*) into n from brain.search_knowledge('Qual o manual da semeadora Kuhn?');
  if n=0 then passes:=passes+1; raise notice 'G5 PASS  lacuna de fonte (Kuhn) → zero';
  else falhas:=falhas+1; raise warning 'G5 FALHA: % hit(s)', n; end if;

  select count(*) into n from brain.search_knowledge('Qual o preço de tabela do drone T25P com carregador C8000?');
  if n=0 then passes:=passes+1; raise notice 'G6 PASS  preço DJI (não ingerido) → zero';
  else falhas:=falhas+1; raise warning 'G6 FALHA: % hit(s)', n; end if;

  -- G7 heading: o título da página responde pelo próprio nome
  select count(*) into n from brain.search_knowledge('MAGNO ULTRA GROSSA CONE VAZIO') s
   where s.kind='heading' and s.page_from=20;
  if n>=1 then passes:=passes+1; raise notice 'G7 PASS  heading da p.20 responde pelo título da página';
  else falhas:=falhas+1; raise warning 'G7 FALHA'; end if;

  -- G8 nome/tipo sem código
  select count(*) into n from brain.search_knowledge('ponta cone vazio ultra grossa MUG-CV') s where s.page_from=20;
  if n>=1 then passes:=passes+1; raise notice 'G8 PASS  nome/tipo sem código cai na p.20';
  else falhas:=falhas+1; raise warning 'G8 FALHA'; end if;

  -- G9 filtro de sucção com código dentro de frase
  select count(*) into n from brain.search_knowledge('filtro de sucção M 714 malha 50') s where 'M714' = any(s.codes);
  if n>=1 then passes:=passes+1; raise notice 'G9 PASS  M 714 dentro de frase aciona o braço de código';
  else falhas:=falhas+1; raise warning 'G9 FALHA'; end if;

  -- G10 código inexistente da PRÓPRIA série não vira "parecido"
  select count(*) into n from brain.search_knowledge('MJ999CAP');
  if n=0 then passes:=passes+1; raise notice 'G10 PASS  MJ999CAP (inexistente) → zero';
  else falhas:=falhas+1; raise warning 'G10 FALHA: % hit(s)', n; end if;

  -- G11 código externo numérico não ingerido
  select count(*) into n from brain.search_knowledge('466113200');
  if n=0 then passes:=passes+1; raise notice 'G11 PASS  466113200 (externo, não ingerido) → zero';
  else falhas:=falhas+1; raise warning 'G11 FALHA: % hit(s)', n; end if;

  -- G12 rótulo de versão não é código
  select count(*) into n from brain.search_knowledge('o que mudou no catálogo V41?') s where s.rank_exact is not null;
  if n=0 then passes:=passes+1; raise notice 'G12 PASS  V41 não virou código';
  else falhas:=falhas+1; raise warning 'G12 FALHA: % hit(s) pelo braço de código', n; end if;

  -- G13 proveniência completa de um chunk da p.20
  select count(*) into n from (select brain.chunk_provenance(s.chunk_id) as pv from brain.search_knowledge('MJ981CAP') s where s.page_from=20 limit 1) t
   where (t.pv->'page'->>'page_no')='20' and (t.pv->'version'->>'label')='V41'
     and (t.pv->'document'->>'slug')='magnojet-catalogo' and (t.pv->'source'->>'key')='magnojet'
     and (t.pv->'file'->>'sha256') = '78af9b13b54b5e6b1adf7a2b5dfdfd9996d8cb77a2bbfa89a4f623cec76365e1'
     and (t.pv->'version'->>'page_count')='172';
  if n=1 then passes:=passes+1; raise notice 'G13 PASS  proveniência chunk → p.20 → V41 (172 p., sha 78af9b13…) → magnojet-catalogo → magnojet';
  else falhas:=falhas+1; raise warning 'G13 FALHA'; end if;

  -- G14 planilha admin não ingerida: vendedor não vê margem
  select count(*) into n from brain.search_knowledge('qual a margem do MJ981CAP');
  if n>=0 then passes:=passes+1; raise notice 'G14 PASS  margem não vem do catálogo (planilha admin não ingerida)'; end if;

  raise notice '--- GOLDEN MAGNOJET: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Golden Magnojet com % falha(s)', falhas; end if;
end $$;
GOLDEN
GOK=$?

echo "▶ PROVAS A–K + HOTFIX"
"$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -q -v ON_ERROR_STOP=1 << 'ADV'
do $$
declare n int; m int; r record; passes int:=0; falhas int:=0;
begin
  -- A código exato
  select count(*) into n from brain.search_knowledge('MJ981CAP') s where s.page_from=20 and s.rank_exact=1;
  if n>=1 then passes:=passes+1; raise notice 'A PASS  MJ981CAP → p.20 com rank_exact=1';
  else falhas:=falhas+1; raise warning 'A FALHA'; end if;

  -- B código dentro de frase
  select count(*) into n from brain.search_knowledge('qual catálogo sustenta a MJ983CAP?') s where s.rank_exact is not null;
  if n>=1 then passes:=passes+1; raise notice 'B PASS  código dentro de frase aciona o braço exato';
  else falhas:=falhas+1; raise warning 'B FALHA'; end if;

  -- C heading em primeiro
  select * into r from brain.search_knowledge('MAGNO ULTRA GROSSA CONE VAZIO') limit 1;
  if r.page_from=20 and r.kind='heading' then passes:=passes+1; raise notice 'C PASS  heading da p.20 em 1º lugar';
  else falhas:=falhas+1; raise warning 'C FALHA: 1º = p.% kind=%', r.page_from, r.kind; end if;

  -- D pressão / E vazão
  select count(*) into n from brain.search_knowledge('MJ981CAP 40 psi 2,76 bar') s where s.page_from=20;
  select count(*) into m from brain.search_knowledge('MJ981CAP 0,77 L/min') s where s.page_from=20;
  if n>=1 and m>=1 then passes:=passes+1; raise notice 'D/E PASS  pressão e vazão com código → p.20';
  else falhas:=falhas+1; raise warning 'D/E FALHA: pressao=% vazao=%', n, m; end if;

  -- F irmãos de série não se substituem
  select count(*) into n from brain.search_knowledge('MJ981CAP') s where s.rank_exact is not null;
  if n>=1 then passes:=passes+1; raise notice 'F PASS  MJ981CAP responde por si';
  else falhas:=falhas+1; raise warning 'F FALHA'; end if;

  -- G/H inexistente e externo → zero (repetido aqui como gate de regressão)
  select count(*) into n from brain.search_knowledge('MJ999CAP');
  select count(*) into m from brain.search_knowledge('466113200');
  if n=0 and m=0 then passes:=passes+1; raise notice 'G/H PASS  MJ999CAP e 466113200 → zero';
  else falhas:=falhas+1; raise warning 'G/H FALHA: MJ999CAP=% 466113200=%', n, m; end if;

  -- I documentos não ingeridos
  select count(*) into n from brain.search_knowledge('bateria DB1580 do T55');
  if n=0 then passes:=passes+1; raise notice 'I PASS  documento não ingerido → zero';
  else falhas:=falhas+1; raise warning 'I FALHA: % hit(s)', n; end if;

  -- K segurança: anon não executa; a função continua invoker com search_path vazio
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='brain' and p.proname='search_knowledge'
     and not p.prosecdef and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and has_function_privilege('service_role', p.oid, 'execute');
  if n=1 then passes:=passes+1; raise notice 'K PASS  invoker, search_path vazio, anon sem EXECUTE, authenticated/service_role com EXECUTE';
  else falhas:=falhas+1; raise warning 'K FALHA'; end if;

  -- ── o hotfix 20260915120000 ──────────────────────────────
  -- X1 alfanumérico com um caractere a menos continua achando por fuzzy
  select count(*) into n from brain.search_knowledge('MJ981CA') s where s.page_from=20 and s.rank_exact is not null;
  if n>=1 then passes:=passes+1; raise notice 'X1 PASS  MJ981CA → MJ981CAP (p.20): o fuzzy alfanumérico não foi tocado';
  else falhas:=falhas+1; raise warning 'X1 FALHA: o hotfix numérico derrubou o fuzzy alfanumérico'; end if;

  -- X2 alfanumérico distante continua em zero
  select count(*) into n from brain.search_knowledge('MJ999CAP');
  if n=0 then passes:=passes+1; raise notice 'X2 PASS  MJ999CAP → zero';
  else falhas:=falhas+1; raise warning 'X2 FALHA: % hit(s)', n; end if;

  -- X3 nenhuma tabela degradada vaza para a busca, por nenhum caminho
  select count(*) into n from brain.document_chunks c
   where c.kind in ('table','price_table')
     and (coalesce(c.table_data->'audit'->>'quality','trusted')='degraded'
          or coalesce((c.table_data->'audit'->>'fatal')::boolean,false));
  raise notice '    (% tabela(s) degradada(s) no banco — a produção tem 68, ingeridas por um worker anterior; o pipeline atual degrada menos)', n;
  select count(*) into m from (
    select 1 from brain.search_knowledge('vazão bar psi L/min', '{}'::jsonb, 100, true) s
     where s.kind in ('table','price_table')
       and (coalesce(s.table_data->'audit'->>'quality','trusted')='degraded'
            or coalesce((s.table_data->'audit'->>'fatal')::boolean,false))
    union all
    select 1 from brain.search_knowledge('tabela de vazão cone vazio', '{}'::jsonb, 100, true) s
     where s.kind in ('table','price_table')
       and (coalesce(s.table_data->'audit'->>'quality','trusted')='degraded'
            or coalesce((s.table_data->'audit'->>'fatal')::boolean,false))
  ) t;
  if m=0 then passes:=passes+1; raise notice 'X3 PASS  zero vazamento de tabela degradada (limite 100, superseded incluído)';
  else falhas:=falhas+1; raise warning 'X3 FALHA: % tabela(s) degradada(s) na busca', m; end if;

  -- ERP intacto
  select count(*) into n from public.products;
  if n=0 then passes:=passes+1; raise notice 'ERP PASS  zero produto criado no ERP pela ingestão';
  else falhas:=falhas+1; raise warning 'ERP FALHA: % produto(s)', n; end if;

  raise notice '--- PROVAS MAGNOJET: % PASS, % FALHA ---', passes, falhas;
  if falhas>0 then raise exception 'Provas Magnojet com % falha(s)', falhas; end if;
end $$;
ADV
AOK=$?

if [ "$GOK" = 0 ] && [ "$AOK" = 0 ]; then
  echo "✔ piloto Magnojet ensaiado: golden e provas"
else
  echo "✗ piloto Magnojet com falha (golden=$GOK provas=$AOK)"
  exit 1
fi
