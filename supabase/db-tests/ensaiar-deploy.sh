#!/usr/bin/env bash
# ============================================================
# Ensaio do deploy e das duas reversões, em PostgreSQL 17.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/ensaiar-deploy.sh
#
# D1  aplicar: as migrations + conferências + registro, num COMMIT
# D2  pós-condição FALSA: prova que NÃO confirma
# D3  pré-condição FALSA (audit_capture mais nova): prova que NÃO aplica
# D4  remover logo após o deploy, sem dados
# D5  remover com dados: PARA e manda para o roteiro 04
# D6  incidente com dados: copia, desliga a ponte, não apaga
# D7  religar a ponte e reconciliar o período desligado
# D8  EVENTO COMERCIAL REAL barra a remoção "sem dados"
# D9  view em public dependendo de brain barra a remoção
# D10 função clássica citando brain barra a remoção
# D11 chave estrangeira de public para brain barra a remoção
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
DB=ensaio_deploy
FALHAS=0

adm() { "$PSQL" -h "$H" -p "$P" -U "$U" -d postgres -q -At "$@"; }
q()   { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -At "$@"; }
ok()  { echo "  ✓ $1"; }
nok() { echo "  ✗ $1"; FALHAS=$((FALHAS+1)); }

montar_pre_brain() {
  adm -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  q -q -c "create extension if not exists pgcrypto" -f supabase/db-tests/00_supabase_stub.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do
    case "$f" in *_brain_*) continue;; esac
    q -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1
  done
  q -q -f supabase/db-tests/registro-producao-20260911.sql >/dev/null 2>&1
  # O ensaio parte do registro JÁ reconciliado e com o instagram no lugar.
  q -q -f supabase/operacao/01-reconciliar-registro.sql >/dev/null 2>&1
  q -q -c "do \$\$ declare t text; begin for t in select tablename from pg_tables where schemaname='supabase_migrations' and tablename like 'schema_migrations\\_antes\\_%' loop execute format('drop table supabase_migrations.%I', t); end loop; end \$\$" >/dev/null 2>&1
  # Um cliente e um administrador, para a fumaça ter em que pegar.
  q -q -c "insert into auth.users (id, email, raw_user_meta_data) values ('aaaaaaaa-0000-4000-8000-00000000d001','deploy.admin@teste.local','{\"full_name\":\"Admin Deploy\",\"role\":\"admin\"}') on conflict do nothing" \
       -c "update public.profiles set role='admin' where id='aaaaaaaa-0000-4000-8000-00000000d001'" \
       -c "insert into public.customers (name, city, state) values ('Cliente do Deploy','Londrina','PR')" >/dev/null
}

echo "▶ D1: aplicar"
montar_pre_brain
SAIDA=$(q -f supabase/operacao/02-aplicar-brain.sql 2>&1)
TAB=$(q -c "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='brain' and c.relkind='r'")
REG=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '202609111%'")
SUJEIRA=$(q -c "select (select count(*) from brain.leads) + (select count(*) from brain.events) + (select count(*) from public.quotes) + (select count(*) from public.orders) + (select count(*) from public.products where code = 'FUMACA-DEPLOY')")
if [ "$TAB" = "9" ] && [ "$REG" = "7" ] && [ "$SUJEIRA" = "0" ]; then
  ok "D1: 9 tabelas, 7 versões registradas, 0 resíduo de fumaça"
  echo "$SAIDA" | grep -q "oportunidade ganha; lead convertido" && ok "D1: a fumaça foi até pedido, oportunidade ganha e lead convertido" || nok "D1: a fumaça não completou o fluxo"
  echo "$SAIDA" | grep -q "Fumaca desfeita" && ok "D1: a fumaça se desfez por inteiro" || nok "D1: a fumaça não se desfez"
else
  nok "D1: tabelas=$TAB registro=$REG sujeira=$SUJEIRA"; echo "$SAIDA" | tail -5
fi

echo "▶ D2: pós-condição falsa — não pode confirmar"
montar_pre_brain
# Estraga a pós-condição: a view deixa de ser security_invoker no meio da
# transação. O COMMIT tem de não acontecer.
sed 's|^-- ── Pós-condições estruturais|alter view brain.journey_entries set (security_invoker = false);\n-- ── Pós-condições estruturais|' \
  supabase/operacao/02-aplicar-brain.sql > /tmp/02-sabotado.sql
SAIDA=$(q -f /tmp/02-sabotado.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
REG=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '202609111%'")
if echo "$SAIDA" | grep -q "journey_entries esta com reloptions" && [ "$EXISTE" = "0" ] && [ "$REG" = "0" ]; then
  ok "D2: abortou na pós-condição; schema brain NÃO existe e nada foi registrado"
else
  nok "D2: existe=$EXISTE registro=$REG"; echo "$SAIDA" | tail -5
fi

echo "▶ D3: pré-condição falsa — audit_capture mais nova"
montar_pre_brain
q -q -c "create or replace function public.audit_capture() returns trigger language plpgsql security definer set search_path='' as \$\$ begin return null; end \$\$" >/dev/null
SAIDA=$(q -f supabase/operacao/02-aplicar-brain.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
if echo "$SAIDA" | grep -q "Alguem a mudou depois" && [ "$EXISTE" = "0" ]; then
  ok "D3: recusou sobrescrever uma audit_capture desconhecida; nada foi aplicado"
else
  nok "D3: existe=$EXISTE"; echo "$SAIDA" | tail -5
fi

echo "▶ D4: remover logo após o deploy, sem dados"
montar_pre_brain
q -q -f supabase/operacao/02-aplicar-brain.sql >/dev/null 2>&1
SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
TRIG=$(q -c "select count(*) from pg_trigger where tgname like 'trg_brain%'")
MD5=$(q -c "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='audit_capture'")
REG=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '202609111%'")
if [ "$EXISTE" = "0" ] && [ "$TRIG" = "0" ] && [ "$MD5" = "24fd65a7eb791b2e2644abe1b2ba876b" ] && [ "$REG" = "0" ]; then
  ok "D4: schema fora, 0 gatilhos, audit_capture no md5 original, registro limpo"
else
  nok "D4: existe=$EXISTE trig=$TRIG md5=$MD5 registro=$REG"; echo "$SAIDA" | tail -5
fi

echo "▶ D5: remover COM dados — tem de parar"
montar_pre_brain
q -q -f supabase/operacao/02-aplicar-brain.sql >/dev/null 2>&1
q -q -c "insert into brain.leads (name) values ('Lead de verdade')" >/dev/null
SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
LEADS=$(q -c "select count(*) from brain.leads")
if echo "$SAIDA" | grep -q "O BRAIN TEM CONTEUDO" && [ "$EXISTE" = "1" ] && [ "$LEADS" = "1" ]; then
  ok "D5: parou, schema intacto, o lead continua lá"
else
  nok "D5: existe=$EXISTE leads=$LEADS"; echo "$SAIDA" | tail -5
fi

echo "▶ D6: incidente com dados — copia e desliga, não apaga"
SAIDA=$(q -f supabase/operacao/04-incidente-com-dados.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
TRIG=$(q -c "select count(*) from pg_trigger where tgname like 'trg_brain%'")
COPIA=$(q -c "select count(*) from brain_arquivo.leads")
LEADS=$(q -c "select count(*) from brain.leads")
REG=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '202609111%'")
if [ "$EXISTE" = "1" ] && [ "$TRIG" = "0" ] && [ "$COPIA" = "1" ] && [ "$LEADS" = "1" ] && [ "$REG" = "7" ]; then
  ok "D6: ponte desligada, brain intacto, cópia com o lead, registro preservado"
else
  nok "D6: existe=$EXISTE trig=$TRIG copia=$COPIA leads=$LEADS registro=$REG"; echo "$SAIDA" | tail -5
fi

echo "▶ D6b: fumaça que falha — o COMMIT tem de virar ROLLBACK"
montar_pre_brain
sed 's/  if v_evento <> v_total then/  v_evento := v_evento + 99;\n  if v_evento <> v_total then/' \
  supabase/operacao/02-aplicar-brain.sql > /tmp/02-fumaca-ruim.sql
SAIDA=$(q -f /tmp/02-fumaca-ruim.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
REG=$(q -c "select count(*) from supabase_migrations.schema_migrations where version like '202609111%'")
QUOTES=$(q -c "select count(*) from public.quotes")
if echo "$SAIDA" | grep -q "Evento com total" && [ "$EXISTE" = "0" ] && [ "$REG" = "0" ] && [ "$QUOTES" = "0" ]; then
  ok "D6b: a fumaça falhou e o COMMIT virou ROLLBACK — sem schema, sem registro, sem orçamento de teste"
else
  nok "D6b: existe=$EXISTE registro=$REG quotes=$QUOTES"; echo "$SAIDA" | tail -5
fi

echo "▶ D7: religar a ponte e repor o que passou"
montar_pre_brain
q -q -f supabase/operacao/02-aplicar-brain.sql >/dev/null 2>&1
q -q -c "insert into brain.leads (name) values ('Lead de verdade')" >/dev/null
q -q -f supabase/operacao/04-incidente-com-dados.sql >/dev/null 2>&1

# Com a ponte fora, um orçamento novo não publica evento.
NOVO=$(q -q -c "insert into public.quotes (customer_id, owner_id) select id, 'aaaaaaaa-0000-4000-8000-00000000d001' from public.customers limit 1 returning id")
# A fumaça do deploy deixou um evento marcado como skipped; o que importa
# aqui é que o orçamento NOVO, feito com a ponte fora, não gerou nenhum.
SEM_EVENTO=$(q -c "select count(*) from brain.events where source='erp' and payload->>'quote_id' = '$NOVO'")
q -q <<'SQL' >/dev/null
begin;
create trigger trg_brain_quotes after insert or update of status
  on public.quotes for each row execute function brain.on_quote_change();
create constraint trigger trg_brain_orders_created after insert
  on public.orders deferrable initially deferred
  for each row execute function brain.on_order_change();
create trigger trg_brain_orders after update of status
  on public.orders for each row execute function brain.on_order_change();
commit;
SQL
FALTANDO=$(q -c "set role postgres" -c "select count(*) from public.quotes q where q.deleted_at is null and not exists (select 1 from brain.events e where e.source='erp' and e.payload->>'quote_id' = q.id::text and e.payload->>'status' = q.status::text)" | tail -1)
REPOSTOS=$(q -c "select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-00000000d001',false)" -c "set role authenticated" -c "select brain.repor_eventos_erp()" | tail -1)
DEPOIS=$(q -c "select count(*) from public.quotes q where q.deleted_at is null and not exists (select 1 from brain.events e where e.source='erp' and e.payload->>'quote_id' = q.id::text and e.payload->>'status' = q.status::text)")
if [ "$SEM_EVENTO" = "0" ] && [ "$FALTANDO" -ge 1 ] && [ "$REPOSTOS" -ge 1 ] && [ "$DEPOIS" = "0" ]; then
  ok "D7: ponte religada; $FALTANDO venda(s) sem evento, $REPOSTOS reposta(s), 0 faltando depois"
else
  nok "D7: sem_evento=$SEM_EVENTO faltando=$FALTANDO repostos=$REPOSTOS depois=$DEPOIS"
fi

echo "▶ D8: evento comercial REAL barra a remoção sem dados"
montar_pre_brain
q -q -f supabase/operacao/02-aplicar-brain.sql >/dev/null 2>&1
# Um orçamento de verdade: a ponte publica o evento, e é só isso que há.
q -q -c "insert into public.quotes (customer_id, owner_id) select id, 'aaaaaaaa-0000-4000-8000-00000000d001' from public.customers limit 1" >/dev/null
EVENTOS=$(q -c "select count(*) from brain.events")
SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
if [ "$EVENTOS" -ge 1 ] && echo "$SAIDA" | grep -q "EVENTO(S)" && [ "$EXISTE" = "1" ]; then
  ok "D8: $EVENTOS evento(s) do ERP barraram a remoção; o schema continua de pé"
else
  nok "D8: eventos=$EVENTOS existe=$EXISTE"; echo "$SAIDA" | tail -4
fi

echo "▶ D9/D10/D11: dependente externo barra a remoção"
for CASO in view funcao fk; do
  montar_pre_brain
  q -q -f supabase/operacao/02-aplicar-brain.sql >/dev/null 2>&1
  case "$CASO" in
    view)   q -q -c "create view public.dep_view as select id, name from brain.leads" >/dev/null;;
    funcao) q -q -c "create function public.dep_funcao() returns int language sql stable as \$\$ select count(*)::int from brain.leads \$\$" >/dev/null;;
    fk)     q -q -c "create table public.dep_fk (id uuid primary key, lead_id uuid references brain.leads(id))" >/dev/null;;
  esac
  SAIDA=$(q -f supabase/operacao/03-remover-brain-sem-dados.sql 2>&1)
  EXISTE=$(q -c "select count(*) from pg_namespace where nspname='brain'")
  if echo "$SAIDA" | grep -qE "Dependente fora do brain|CITA brain" && [ "$EXISTE" = "1" ]; then
    ok "D9/D10/D11 [$CASO]: barrou e o schema continua de pé"
  else
    nok "D9/D10/D11 [$CASO]: existe=$EXISTE"; echo "$SAIDA" | tail -4
  fi
done

adm -c "drop database if exists $DB" >/dev/null
[ "$FALHAS" = "0" ] && echo "✔ deploy e reversão ensaiados nos 11 cenários" || { echo "✗ $FALHAS falha(s)"; exit 1; }
