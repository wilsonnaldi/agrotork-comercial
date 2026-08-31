-- ============================================================
-- Isolamento do preço de custo (migration 1200).
-- O vendedor pode ver o catálogo, mas não o custo nem a margem.
-- ============================================================
insert into auth.users (id, email, raw_user_meta_data) values
 ('55555555-5555-5555-5555-555555555555','custo.admin@teste.local','{"full_name":"Admin Custo","role":"admin"}'),
 ('66666666-6666-6666-6666-666666666666','custo.vend@teste.local','{"full_name":"Vendedor Custo","role":"salesperson"}');

insert into public.products (code, name, unit_id, sale_price)
select 'C-001','Produto com custo', u.id, 200 from public.units u where u.code='UN';

insert into public.product_costs (product_id, cost_price)
select id, 120 from public.products where code='C-001';

-- ── Contexto: ADMIN ─────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
set request.jwt.claim.role = 'authenticated';

select 'V) admin vê custo e margem' as teste, code, cost_price, margin_percent
from public.products_list where code='C-001';

-- ── Contexto: VENDEDOR ──────────────────────────────────────
set request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';

select 'W) vendedor vê o produto' as teste, code, sale_price from public.products_list where code='C-001';

select 'X) custo e margem ocultos para o vendedor' as teste,
       case when cost_price is null and margin_percent is null
            then 'OK: nulos' else 'BRECHA: custo exposto' end as resultado
from public.products_list where code='C-001';

select 'Y) vendedor lendo product_costs direto' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'BRECHA: leu ' || count(*) || ' linha(s)' end as resultado
from public.product_costs;

do $$ begin
  update public.product_costs set cost_price = 1
   where product_id = (select id from public.products where code='C-001');
  if (select cost_price from public.product_costs
      where product_id = (select id from public.products where code='C-001')) = 1
    then raise notice 'Z) BRECHA: vendedor alterou o custo';
    else raise notice 'Z) OK: alteração de custo ignorada'; end if;
exception when others then raise notice 'Z) OK: alteração de custo bloqueada';
end $$;

do $$ begin
  insert into public.product_costs (product_id, cost_price)
  select id, 1 from public.products where code='P-002';
  raise notice 'AA) BRECHA: vendedor inseriu custo';
exception when others then raise notice 'AA) OK: inserção de custo bloqueada';
end $$;

do $$ begin
  update public.products set sale_price = 1 where code='C-001';
  if (select sale_price from public.products where code='C-001') = 1
    then raise notice 'AB) BRECHA: vendedor alterou preço de venda';
    else raise notice 'AB) OK: alteração de preço ignorada'; end if;
exception when others then raise notice 'AB) OK: alteração de preço bloqueada';
end $$;

reset role;

-- O custo permanece intacto depois de todas as tentativas.
select 'AC) custo preservado' as teste,
       case when cost_price = 120 then 'OK: 120,00' else 'BRECHA: virou ' || cost_price end as resultado
from public.product_costs pc
join public.products p on p.id = pc.product_id
where p.code = 'C-001';
