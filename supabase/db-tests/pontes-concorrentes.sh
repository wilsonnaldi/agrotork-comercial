#!/usr/bin/env bash
# ============================================================
# PT4 e PT5 — o que acontece com a venda quando a ponte do BRAIN
# trava numa linha que outra transação segura.
#
#   PGHOST=/tmp PGPORT=5437 PGUSER=postgres PSQL=/opt/pg176/bin/psql \
#     bash supabase/db-tests/pontes-concorrentes.sh <banco>
#
# PT4:  sem lock_timeout na sessão — a ponte tem o DELA, de 250ms
#       (migration 20260911190000), então desiste rápido e a venda passa
#       sem esperar o bloqueio sair.
# PT5:  lock_timeout curto na sessão — 55P03, que OTHERS captura.
# PT5b: statement_timeout — 57014, que OTHERS NÃO captura, e a venda CAI.
#       É esse o limite residual que o relatório declara.
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

echo "▶ PT4: a ponte tem lock_timeout proprio e nao espera o bloqueio sair"
preparar
( q -c "begin; select id from brain.opportunities where quote_id = '$QUOTE' for update; select pg_sleep(5); commit;" >/dev/null 2>&1 ) &
TRAVA=$!
sleep 1
INICIO=$(date +%s%N)
SAIDA=$(q -c "update public.quotes set status = 'sent' where id = '$QUOTE' returning status" 2>&1)
FIM=$(date +%s%N)
MS=$(( (FIM - INICIO) / 1000000 ))
STATUS=$(q -c "select status from public.quotes where id = '$QUOTE'")
wait $TRAVA
if [ "$STATUS" = "sent" ] && [ "$MS" -lt 3000 ]; then
  echo " PT4) OK: a venda passou em ${MS}ms — a ponte desistiu do bloqueio em 250ms em vez de esperar os 5s"
else
  echo " PT4) FALHOU: status=$STATUS tempo=${MS}ms"; echo "$SAIDA" | tail -3; exit 1
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

echo "▶ PT5b: statement_timeout DENTRO da ponte — 57014, e a venda cai"
# Depois da migration 20260911190000 a contenção de lock não produz mais
# 57014: a ponte desiste em 250ms e cai em 55P03, que é capturado. O que
# SOBRA é o tempo de execução da própria ponte. Para exercitar essa
# janela residual, aqui ela é alargada de propósito com um gatilho
# temporário que dorme — e é assim que se vê o limite que continua de pé.
preparar
q >/dev/null <<'SQL'
create or replace function brain.teste_lento() returns trigger language plpgsql as $t$
begin perform pg_sleep(1); return new; end $t$;
create trigger trg_teste_lento before update on brain.opportunities
 for each row execute function brain.teste_lento();
SQL
SAIDA=$(q -c "set statement_timeout = '400ms'; update public.quotes set status = 'sent' where id = '$QUOTE' returning status" 2>&1)
STATUS=$(q -c "select status from public.quotes where id = '$QUOTE'")
q >/dev/null <<'SQL'
drop trigger if exists trg_teste_lento on brain.opportunities;
drop function if exists brain.teste_lento();
SQL
if echo "$SAIDA" | grep -qi "statement timeout" && [ "$STATUS" = "draft" ]; then
  echo " PT5b) OK (e este e o LIMITE RESIDUAL): statement_timeout estourou dentro da ponte e a venda CAIU — o orcamento ficou em '$STATUS'"
else
  echo " PT5b) FALHOU: status='$STATUS'"; echo "--- saida ---"; echo "$SAIDA"; exit 1
fi

echo "▶ PT5c: a ponte devolve o lock_timeout da sessao"
preparar
SAIDA=$(q -c "set lock_timeout = '7s'; update public.quotes set status = 'sent' where id = '$QUOTE'; show lock_timeout" 2>&1 | tail -1)
if [ "$SAIDA" = "7s" ]; then
  echo " PT5c) OK: lock_timeout da sessao continua 7s — a ponte usa o dela e devolve o seu"
else
  echo " PT5c) FALHOU: lock_timeout ficou em '$SAIDA'"; exit 1
fi

q >/dev/null <<SQL
delete from brain.opportunities where title like 'Oportunidade travada%';
delete from public.quotes where notes = 'PT4/PT5';
delete from public.customers where id = '28282828-0000-4000-8000-0000000000c1';
delete from auth.users where id = '28282828-0000-4000-8000-00000000cc01';
SQL
echo "✔ PT4, PT5, PT5b e PT5c concluidos"
