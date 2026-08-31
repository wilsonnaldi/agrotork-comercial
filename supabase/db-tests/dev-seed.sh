#!/usr/bin/env bash
# ============================================================
# Cria um banco de DESENVOLVIMENTO local com as migrations
# aplicadas e alguns dados de exemplo, para usar junto com o
# duplê de teste (supabase/db-tests/auth-double).
#
#   bash supabase/db-tests/dev-seed.sh
#
# Nada aqui tem relação com o Supabase de produção.
# As senhas são de teste e só valem neste banco local.
# ============================================================
set -euo pipefail
HOST="${PGHOST:-/tmp/pgrun}"; PORT="${PGPORT:-5433}"; USER="${PGUSER:-postgres}"
DB="${PGDATABASE:-agrotork_dev}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL="psql -h $HOST -p $PORT -U $USER"

# O duplê mantém um pool aberto; sem encerrar as conexões o DROP falha.
$PSQL -q -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and pid <> pg_backend_pid();" > /dev/null
$PSQL -q -c "drop database if exists $DB;" -c "create database $DB;"
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -c "create extension if not exists pgcrypto;" -f "$ROOT/supabase/db-tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do $PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f"; done

$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 <<'SQL'
-- Usuários de teste. A senha é guardada como sha256, que é o que o duplê espera.
-- O Supabase real usa bcrypt e nunca recebe senha por SQL.
insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
 ('aaaaaaaa-0000-4000-8000-000000000001','admin@teste.local',
  encode(digest('teste1234','sha256'),'hex'), '{"full_name":"Administrador de Teste","role":"admin"}'),
 ('bbbbbbbb-0000-4000-8000-000000000002','vendedor@teste.local',
  encode(digest('teste1234','sha256'),'hex'), '{"full_name":"Vendedor de Teste","role":"salesperson"}');

insert into public.customers (name, city, state, document, person_type) values
 ('Fazenda São João','Londrina','PR','12345678000195','company'),
 ('Agropecuária Canedo Ltda','Cambé','PR','98765432000110','company'),
 ('João Marchioni','Rolândia','PR','52998224725','individual');

-- Massa de teste: marcada como tal para poder sair com purge_test_products().
insert into public.products (code, name, description, unit_id, sale_price, category_id, brand_id,
                             source_type, source_reference)
select 'P-001','Bico de pulverização AD 110-02','Bico leque duplo em cerâmica, vazão 0,8 L/min a 3 bar',
       u.id, 150, c.id, b.id, 'test_data', 'dev-seed.sh'
from public.units u, public.categories c, public.brands b
where u.code='UN' and c.name='Pulverização' and b.name='ARAG';

insert into public.products (code, name, description, unit_id, sale_price, category_id, brand_id,
                             source_type, source_reference)
select 'P-002','Mangueira de pulverização 3/4"','Mangueira trançada para barra de pulverização',
       u.id, 32, c.id, b.id, 'test_data', 'dev-seed.sh'
from public.units u, public.categories c, public.brands b
where u.code='M' and c.name='Peças' and b.name='MAGNOJET';

insert into public.products (code, name, unit_id, sale_price, category_id, brand_id, is_active,
                             source_type, source_reference)
select 'P-003','Controlador de vazão AGRES', u.id, 4890, c.id, b.id, false, 'test_data', 'dev-seed.sh'
from public.units u, public.categories c, public.brands b
where u.code='UN' and c.name='Agricultura de Precisão' and b.name='AGRES';

-- Exemplo de produto vindo de catálogo de fabricante (o importador ainda
-- não existe; aqui é só para a tela de procedência ter o que mostrar).
insert into public.products (code, name, description, unit_id, sale_price, category_id, brand_id,
                             manufacturer_code, source_type, source_brand, source_catalog,
                             source_version, source_reference, source_imported_at, technical_data)
select 'P-004','Monitor de plantio AGRES','Monitoramento de sementes por linha, com sensor óptico',
       u.id, 18900, c.id, b.id,
       'AGR-9001', 'manufacturer_catalog', 'AGRES', 'AGRIS 2026', '2026.04',
       'Quick-Catal-AGRI_2026 · p. 14', now(),
       '{"Tensão":"12 V","Linhas monitoradas":"até 36","Sensor":"óptico"}'::jsonb
from public.units u, public.categories c, public.brands b
where u.code='UN' and c.name='Agricultura de Precisão' and b.name='AGRES';

-- Custo é dado de administrador: fica em tabela separada, com RLS própria.
insert into public.product_costs (product_id, cost_price)
select id, case code when 'P-001' then 100 when 'P-002' then 20
                    when 'P-004' then 14200 else 3500 end
from public.products;

-- Dados da empresa preenchidos: o PDF e a página pública só mostram o
-- que estiver configurado, então sem isto o cabeçalho sai quase vazio.
update public.app_settings
   set value = value || jsonb_build_object(
     'legal_name', 'AGROTORK COMERCIO DE IMPLEMENTOS AGRICOLAS LTDA',
     'trade_name', 'AGROTORK',
     'document',   '12.345.678/0001-90',
     'phone',      '(43) 3333-4444',
     'whatsapp',   '(43) 99999-8888',
     'email',      'comercial@agrotork.com.br',
     'address',    'Av. Tiradentes, 1500',
     'zip_code',   '86072-000'
   )
 where key = 'company';

insert into public.kits (code, name, discount_percent) values ('K-001','KIT PULVERIZAÇÃO', 10);
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 4 from public.kits k, public.products p where k.code='K-001' and p.code='P-001';

-- Kit COM opcionais: é o que a tela de orçamento precisa para exercitar a
-- escolha do vendedor. Base = P-001 (R$ 150,00); opcionais P-002 e P-004.
insert into public.kits (code, name, description) values
  ('K-002','KIT NAVEGAÇÃO','Kit com itens opcionais para o orçamento');
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'required' from public.kits k, public.products p
where k.code='K-002' and p.code='P-001';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code='K-002' and p.code='P-002';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code='K-002' and p.code='P-004';

-- Kit sem item obrigatório: ativo, porém INCOMPLETO — não pode ser
-- oferecido em orçamento (kitIsUsable).
insert into public.kits (code, name) values ('K-003','KIT INCOMPLETO');

-- Kit desativado: também fora das opções de um orçamento novo.
insert into public.kits (code, name, is_active) values ('K-004','KIT DESATIVADO', false);
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'required' from public.kits k, public.products p
where k.code='K-004' and p.code='P-001';

-- Dois orçamentos do admin e um do vendedor: serve para conferir o RLS no painel.
insert into public.quotes (customer_id, owner_id, status)
select c.id, 'aaaaaaaa-0000-4000-8000-000000000001', 'sent'
from public.customers c where c.name='Fazenda São João';
insert into public.quotes (customer_id, owner_id, status)
select c.id, 'aaaaaaaa-0000-4000-8000-000000000001', 'draft'
from public.customers c where c.name='Agropecuária Canedo Ltda';
insert into public.quotes (customer_id, owner_id, status)
select c.id, 'bbbbbbbb-0000-4000-8000-000000000002', 'draft'
from public.customers c where c.name='João Marchioni';

insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
select q.id, 'custom', 'Item de exemplo', 10, 150 from public.quotes q;
SQL

echo "✔ banco $DB pronto"
$PSQL -d "$DB" -At -c "select 'clientes=' || (select count(*) from public.customers)
  || ' produtos=' || (select count(*) from public.products)
  || ' kits='     || (select count(*) from public.kits)
  || ' orcamentos=' || (select count(*) from public.quotes);"
