#!/usr/bin/env bash
# ============================================================
# PT4 e PT5 — o que acontece com a venda quando a ponte do BRAIN
# trava numa linha que outra transação segura.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/pontes-concorrentes.sh <banco>
#
# PT4: sem lock_timeout — a ponte ESPERA e a venda passa quando o
#      bloqueio sai.
# PT5: com lock_timeout curto — a espera vira `query_canceled`, que
#      `exception when others` NÃO captura, e a venda CAI. É esse o
#      limite que o relatório declara.
# ============================================================
set -uo pipefail
DB="${1:-pontes_conc}"
PSQL="${PSQL:-psql}"
H="${PGHOST:-/tmp}"; P="${PGPORT:-5437}"; U="${PGUSER:-postgres}"
q() { "$PSQL" -h "$H" -p "$P" -U "$U" -d "$DB" -v ON_ERROR_STOP=0 -At "$@"; }

# A suíte 28 limpa a própria massa no fim, então este script monta a sua.
q >/dev/null <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
 values ('28282828-0000-4000-8000-00000000cc01','conc.admin@teste.local','{"full_name":"Admin Concorrente","role":"admin"}')
 on conflict (id) do nothing;
update public.profiles set role = 'admin' where id = '28282828-0000-4000-8000-00000000cc01';
insert into public.customers (id, name, city, state)
 values ('28282828-0000-4000-8000-0000000000c1','Fazenda das Pontes','Londrina','PR')
 on conflict (id) do nothing;
SQL
CLI=$(q -c "select id from public.customers where name = 'Fazenda das Pontes'")
if [ -z "$CLI" ]; then echo "✗ nao consegui preparar o cliente de teste"; exit 1; fi

# Cada rodada usa um orçamento NOVO e trabalha pelo id — o ERP tem
# exclusão lógica, e contar por `notes` acabaria somando o da rodada
# anterior.
preparar() {
  QUOTE=$(q -c "insert into public.quotes (customer_id, owner_id, notes)
                values ('$CLI', '28282828-0000-4000-8000-00000000cc01', 'PT4/PT5')
                returning id" -q)
  q >/dev/null -c "insert into brain.opportunities (quote_id, customer_id, title, channel_key)
                   values ('$QUOTE', '$CLI', 'Oportunidade travada $QUOTE', 'other')"
}

echo "▶ PT4: a ponte espera o bloqueio sair"
preparar
( q -c "begin; select id from brain.opportunities where quote_id = '$QUOTE' for update; select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
TRAVA=$!
sleep 1
INICIO=$(date +%s)
SAIDA=$(q -c "update public.quotes set status = 'sent' where id = '$QUOTE' returning status" 2>&1)
FIM=$(date +%s)
wait $TRAVA
STATUS=$(q -c "select status from public.quotes where id = '$QUOTE'")
if [ "$STATUS" = "sent" ]; then
  echo " PT4) OK: a venda passou depois de esperar $((FIM-INICIO))s pelo bloqueio (status=$STATUS)"
else
  echo " PT4) FALHOU: status=$STATUS saida=$SAIDA"; exit 1
fi

echo "▶ PT5: lock_timeout — a espera vira 55P03, que OTHERS captura"
preparar
( q -c "begin; select id from brain.opportunities where quote_id = '$QUOTE' for update; select pg_sleep(4); commit;" >/dev/null 2>&1 ) &
TRAVA=$!
sleep 1
SAIDA=$(q -c "set lock_timeout = '300ms'; update public.quotes set status = 'sent' where id = '$QUOTE' returning status" 2>&1)
wait $TRAVA
STATUS=$(q -c "select status from public.quotes where id = '$QUOTE'")
if echo "$SAIDA" | grep -qi "lock timeout" && [ "$STATUS" = "sent" ]; then
  echo " PT5) OK: lock_timeout levanta lock_not_available (55P03), OTHERS capturou — a venda passou e o evento se perdeu"
else
  echo " PT5) FALHOU: status='$STATUS'"; echo "--- saida ---"; echo "$SAIDA"; exit 1
fi
# `quote.created` saiu no INSERT, antes do bloqueio existir. O que se
# perdeu foi o `quote.sent` — e e ele que tem de faltar.
ENVIADO=$(q -c "select count(*) from brain.events where payload ->> 'quote_id' = '$QUOTE' and event_name = 'quote.sent'")
if [ "$ENVIADO" != "0" ]; then echo " PT5) FALHOU: esperava 0 evento quote.sent, veio $ENVIADO"; exit 1; fi
FALTANDO=$(q -c "select count(*) from brain.events e where e.source = 'erp' and e.payload ->> 'quote_id' = '$QUOTE' and e.payload ->> 'status' = 'sent'")
if [ "$FALTANDO" != "0" ]; then echo " PT5) FALHOU: reconciliacao nao acusaria a falta"; exit 1; fi
echo "      o quote.sent se perdeu e a reconciliacao acusa a venda como nao publicada"

echo "▶ PT5b: statement_timeout — a espera vira 57014, que OTHERS NAO captura"
preparar
( q -c "begin; select id from brain.opportunities where quote_id = '$QUOTE' for update; select pg_sleep(4); commit;" >/dev/null 2>&1 ) &
TRAVA=$!
sleep 1
SAIDA=$(q -c "set statement_timeout = '400ms'; update public.quotes set status = 'sent' where id = '$QUOTE' returning status" 2>&1)
wait $TRAVA
STATUS=$(q -c "select status from public.quotes where id = '$QUOTE'")
if echo "$SAIDA" | grep -qi "statement timeout" && [ "$STATUS" = "draft" ]; then
  echo " PT5b) OK (e este e o LIMITE): statement_timeout na ponte derrubou a venda — o orcamento ficou em '$STATUS'"
else
  echo " PT5b) FALHOU: status='$STATUS'"; echo "--- saida ---"; echo "$SAIDA"; exit 1
fi

q >/dev/null <<SQL
delete from brain.opportunities where title like 'Oportunidade travada%';
delete from public.quotes where notes = 'PT4/PT5';
delete from public.customers where id = '28282828-0000-4000-8000-0000000000c1';
delete from auth.users where id = '28282828-0000-4000-8000-00000000cc01';
SQL
echo "✔ PT4 e PT5 concluidos"
