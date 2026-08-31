\set ON_ERROR_STOP on
-- usuário fictício
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'admin@agrotork.com.br', '{"full_name":"Admin Teste","role":"admin"}'::jsonb);

-- O papel NÃO vem mais do metadata (migration 2100): o trigger cria todo
-- mundo como `salesperson`. Promover é operação explícita — exatamente o
-- que o SETUP.md §5.3 manda fazer em produção. A fixture faz o mesmo.
update public.profiles set role = 'admin'
 where id in (
 '11111111-1111-1111-1111-111111111111'
 );


select '1) profile criado por trigger' as teste, full_name, role from public.profiles;

-- produto (o custo vive em product_costs desde a migration 1200)
insert into public.products (code, name, unit_id, sale_price, category_id, brand_id)
select 'P-001', 'Bico de pulverização', u.id, 150.00, c.id, b.id
from public.units u, public.categories c, public.brands b
where u.code='UN' and c.name='Pulverização' and b.name='ARAG';

insert into public.products (code, name, unit_id, sale_price)
select 'P-002', 'Mangueira 3/4', u.id, 32.00 from public.units u where u.code='M';

insert into public.product_costs (product_id, cost_price)
select id, case code when 'P-001' then 100.00 else 20.00 end from public.products;

select '2) margem calculada' as teste, code, cost_price, sale_price, margin_percent
from public.products_list order by code;

-- kit com 2 componentes e 10% de desconto
insert into public.kits (code, name, discount_percent) values ('K-001','KIT PULVERIZAÇÃO', 10);
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 4 from public.kits k, public.products p where k.code='K-001' and p.code='P-001';
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 10 from public.kits k, public.products p where k.code='K-001' and p.code='P-002';

-- esperado: 4*150 + 10*32 = 920 ; com 10% = 828
select '3) preço do kit derivado' as teste, code, items_count, components_total, suggested_price from public.kits_with_price;

-- cliente (documento com máscara deve ser normalizado)
insert into public.customers (name, document, zip_code, state, city)
values ('Fazenda São João', '12.345.678/0001-95', '86.010-000', 'pr', 'Londrina');
select '4) documento/CEP normalizados' as teste, document, zip_code, state from public.customers;

-- orçamento (número gerado pelo banco)
insert into public.quotes (customer_id, owner_id, issue_date, discount_percent)
select c.id, '11111111-1111-1111-1111-111111111111', date '2026-08-29', 5
from public.customers c where c.name='Fazenda São João';
select '5) numeração automática' as teste, number, sequence_year, sequence_number from public.quotes;

-- itens com preço congelado
insert into public.quote_items (quote_id, kind, product_id, name_snapshot, code_snapshot, unit_snapshot, quantity, unit_price, unit_cost_snapshot, discount_percent)
select q.id, 'product', p.id, p.name, p.code, 'UN', 10, 150.00, 100.00, 0 from public.quotes q, public.products p where p.code='P-001';
insert into public.quote_items (quote_id, kind, kit_id, name_snapshot, code_snapshot, quantity, unit_price, discount_percent)
select q.id, 'kit', k.id, k.name, k.code, 1, 828.00, 0 from public.quotes q, public.kits k where k.code='K-001';

-- esperado: subtotal 1500 + 828 = 2328 ; desconto geral 5% = 116.40 ; total 2211.60
select '6) totais recalculados por trigger' as teste, subtotal, discount_percent, total from public.quotes;

-- MUDA O PREÇO DO PRODUTO: o orçamento NÃO pode mudar
update public.products set sale_price = 999.00 where code='P-001';
select '7) preço congelado apos alteracao' as teste, q.subtotal, q.total from public.quotes q;
select '7b) snapshot do item' as teste, name_snapshot, unit_price, line_total from public.quote_items order by created_at;

-- desconto por item recalcula
update public.quote_items set discount_percent = 10 where code_snapshot='P-001';
select '8) desconto por item' as teste, subtotal, total from public.quotes;

-- status carimba data
update public.quotes set status='sent';
select '9) carimbo de status' as teste, status, (sent_at is not null) as sent_at_preenchido from public.quotes;

-- expiração
update public.quotes set valid_until = current_date - 1;
select '10) expire_quotes()' as teste, public.expire_quotes() as expirados;
select '10b) status apos expirar' as teste, status from public.quotes;

-- segundo orçamento: sequência incrementa
insert into public.quotes (customer_id, owner_id) select c.id, '11111111-1111-1111-1111-111111111111' from public.customers c limit 1;
select '11) sequencia incrementa' as teste, number from public.quotes order by sequence_number;

-- RLS está ligada em todas as tabelas?
select '12) tabelas sem RLS' as teste, coalesce(string_agg(tablename, ', '), 'nenhuma') as tabelas
from pg_tables where schemaname='public' and not rowsecurity;
