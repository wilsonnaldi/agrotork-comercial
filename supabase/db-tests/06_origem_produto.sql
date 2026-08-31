-- ============================================================
-- Origem do produto e código do fabricante (migration 1300).
-- Prepara a importação de catálogos sem implementá-la.
-- ============================================================

-- AD) padrão de origem para quem cadastra à mão
insert into public.products (code, name, unit_id, sale_price)
select 'ORI-001','Produto digitado à mão', u.id, 100 from public.units u where u.code='UN';

select 'AD) origem padrão é manual' as teste,
       case when source_type = 'manual' then 'OK' else 'FALHA: ' || source_type end as resultado
from public.products where code='ORI-001';

-- AE) código de fabricante exige fabricante
do $$ begin
  insert into public.products (code, name, unit_id, sale_price, manufacturer_code)
  select 'ORI-002','Sem marca', u.id, 100, 'ABC-123' from public.units u where u.code='UN';
  raise notice 'AE) FALHA: aceitou codigo de fabricante sem marca';
exception when check_violation then raise notice 'AE) OK: codigo de fabricante exige marca';
end $$;

-- AF) mesmo código em fabricantes diferentes é permitido
insert into public.products (code, name, unit_id, sale_price, brand_id, manufacturer_code, source_type, source_brand, source_catalog, source_version, technical_data)
select 'ORI-003','Monitor de plantio', u.id, 5000, b.id, 'AGR-9001', 'manufacturer_catalog', 'AGRES', 'AGRIS 2026', '2026.04', '{"tensao":"12V","linhas":36}'::jsonb
from public.units u, public.brands b where u.code='UN' and b.name='AGRES';

insert into public.products (code, name, unit_id, sale_price, brand_id, manufacturer_code)
select 'ORI-004','Válvula reguladora', u.id, 800, b.id, 'AGR-9001'
from public.units u, public.brands b where u.code='UN' and b.name='ARAG';

select 'AF) mesmo codigo em marcas diferentes' as teste,
       case when count(*) = 2 then 'OK: dois produtos' else 'FALHA: ' || count(*) end as resultado
from public.products where manufacturer_code = 'AGR-9001';

-- AG) duplicidade dentro do MESMO fabricante é bloqueada (inclusive em outra caixa)
do $$ begin
  insert into public.products (code, name, unit_id, sale_price, brand_id, manufacturer_code)
  select 'ORI-005','Repetido', u.id, 10, b.id, 'agr-9001'
  from public.units u, public.brands b where u.code='UN' and b.name='AGRES';
  raise notice 'AG) FALHA: aceitou codigo repetido no mesmo fabricante';
exception when unique_violation then raise notice 'AG) OK: codigo repetido no mesmo fabricante bloqueado';
end $$;

-- AH) dados técnicos vêm na view, e sem preço dentro
select 'AH) dados tecnicos e procedencia na view' as teste,
       source_catalog, source_version, technical_data ->> 'tensao' as tensao,
       case when technical_data ? 'preco' or technical_data ? 'price'
            then 'FALHA: preco no cadastro tecnico' else 'OK: sem preco' end as separacao
from public.products_list where code='ORI-003';

-- AI) massa de teste é identificável e removível
insert into public.products (code, name, unit_id, sale_price, source_type, source_reference)
select 'TEST-001','Massa de teste 1', u.id, 10, 'test_data', 'AGROTORK 23.xlsx' from public.units u where u.code='UN';
insert into public.products (code, name, unit_id, sale_price, source_type, source_reference)
select 'TEST-002','Massa de teste 2', u.id, 20, 'test_data', 'AGROTORK 23.xlsx' from public.units u where u.code='UN';

-- um kit e um orçamento usam a massa de teste: nada disso pode travar a limpeza
insert into public.kits (code, name) values ('KIT-TESTE','Kit da massa de teste');
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 2 from public.kits k, public.products p
where k.code='KIT-TESTE' and p.code='TEST-001';

insert into public.quotes (customer_id, owner_id)
select c.id, pr.id from public.customers c, public.profiles pr limit 1;
insert into public.quote_items (quote_id, kind, product_id, name_snapshot, quantity, unit_price)
select q.id, 'product', p.id, p.name, 1, 10
from public.quotes q, public.products p where p.code='TEST-001'
order by q.created_at desc limit 1;

select 'AI) massa de teste identificavel' as teste, count(*) as produtos
from public.products where source_type = 'test_data';

select 'AJ) purge_test_products()' as teste, public.purge_test_products() as removidos;

select 'AK) apos a limpeza' as teste,
       case when count(*) = 0 then 'OK: nenhum produto de teste' else 'FALHA: sobraram ' || count(*) end as resultado
from public.products where source_type = 'test_data';

select 'AL) produto legitimo preservado' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from public.products where code='ORI-003';

-- O item do orçamento continua lá, com o nome congelado — só perdeu a referência.
select 'AM) historico do orcamento intacto' as teste,
       name_snapshot,
       case when product_id is null then 'OK: referencia limpa' else 'FALHA: ainda aponta' end as referencia
from public.quote_items where name_snapshot = 'Massa de teste 1';

-- AN) função de limpeza fora do alcance do usuário comum
set role authenticated;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles limit 1), false);
do $$ begin
  perform public.purge_test_products();
  raise notice 'AN) FALHA: usuario comum executou purge_test_products()';
exception when insufficient_privilege then raise notice 'AN) OK: purge_test_products() negada';
end $$;
reset role;
