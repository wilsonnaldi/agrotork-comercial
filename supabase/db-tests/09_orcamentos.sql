-- ============================================================
-- ORÇAMENTOS: itens, kits, opcionais, desconto, totais e HISTÓRICO.
--
-- O teste central deste arquivo é o de histórico (EA–EK): o orçamento
-- precisa continuar idêntico depois que o catálogo inteiro muda embaixo
-- dele. Se um dia esse bloco falhar, o sistema perdeu a propriedade mais
-- importante que tem.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

-- ── Massa dedicada ──────────────────────────────────────────
insert into public.customers (name, city, state) values ('Cliente do Orçamento', 'Londrina', 'PR');

insert into public.products (code, name, unit_id, sale_price)
select 'ORC-CTRL', 'Controlador ORC', u.id, 1000 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'ORC-ANT', 'Antena ORC', u.id, 500 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'ORC-SENS', 'Sensor opcional ORC', u.id, 250 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'ORC-SUP', 'Suporte opcional ORC', u.id, 120 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'ORC-AVULSO', 'Produto avulso ORC', u.id, 300 from public.units u where u.code = 'UN';

insert into public.kits (code, name, description) values ('ORC-KIT', 'Kit do orçamento', 'Kit de teste');

insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'required' from public.kits k, public.products p
where k.code = 'ORC-KIT' and p.code = 'ORC-CTRL';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 2, 'required' from public.kits k, public.products p
where k.code = 'ORC-KIT' and p.code = 'ORC-ANT';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code = 'ORC-KIT' and p.code = 'ORC-SENS';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code = 'ORC-KIT' and p.code = 'ORC-SUP';

-- ── CRIAÇÃO ─────────────────────────────────────────────────
insert into public.quotes (customer_id, owner_id, valid_until, payment_terms, delivery_terms, notes)
select c.id, '11111111-1111-1111-1111-111111111111', current_date + 15,
       '30/60/90', '15 dias', 'Proposta de teste'
from public.customers c where c.name = 'Cliente do Orçamento';

select 'DD) orcamento criado com numero automatico' as teste,
       case when number like 'ORC-%' and sequence_number > 0 then 'OK: ' || number
            else 'FALHA' end as resultado
from public.quotes q join public.customers c on c.id = q.customer_id
where c.name = 'Cliente do Orçamento';

select 'DE) prazo de entrega gravado' as teste,
       case when delivery_terms = '15 dias' then 'OK' else 'FALHA' end as resultado
from public.quotes q join public.customers c on c.id = q.customer_id
where c.name = 'Cliente do Orçamento';

select 'DF) rascunho e o status inicial' as teste,
       case when status = 'draft' then 'OK' else 'FALHA: ' || status end as resultado
from public.quotes q join public.customers c on c.id = q.customer_id
where c.name = 'Cliente do Orçamento';

-- ── ITEM DE PRODUTO (snapshot) ──────────────────────────────
insert into public.quote_items
  (quote_id, kind, product_id, code_snapshot, name_snapshot, unit_snapshot, quantity, unit_price)
select q.id, 'product', p.id, p.code, p.name, 'UN', 2, p.sale_price
from public.quotes q, public.products p
join public.customers cc on true
where p.code = 'ORC-AVULSO'
  and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento')
limit 1;

select 'DG) line_total calculado pelo banco' as teste,
       quantity, unit_price, line_total,
       case when line_total = 600.00 then 'OK' else 'FALHA' end as resultado
from public.quote_items where code_snapshot = 'ORC-AVULSO';

select 'DH) subtotal e total por trigger' as teste,
       subtotal, total,
       case when subtotal = 600.00 and total = 600.00 then 'OK' else 'FALHA' end as resultado
from public.quotes q where q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ── ITEM DE KIT com opcional selecionado ────────────────────
-- Composição congelada: TODOS os componentes, com `selected` dizendo
-- quais entraram. Preço da unidade do kit = obrigatórios + escolhidos.
-- 1×1000 + 2×500 + 1×250 (sensor escolhido) = 2250,00
insert into public.quote_items
  (quote_id, kind, kit_id, code_snapshot, name_snapshot, quantity, unit_price, components_snapshot)
select q.id, 'kit', k.id, k.code, k.name, 2, 2250,
  jsonb_build_array(
    jsonb_build_object('product_id', (select id from public.products where code='ORC-CTRL'),
                       'code','ORC-CTRL','name','Controlador ORC','unit','UN',
                       'quantity_milli',1000,'unit_price_cents',100000,
                       'item_type','required','selected',true),
    jsonb_build_object('product_id', (select id from public.products where code='ORC-ANT'),
                       'code','ORC-ANT','name','Antena ORC','unit','UN',
                       'quantity_milli',2000,'unit_price_cents',50000,
                       'item_type','required','selected',true),
    jsonb_build_object('product_id', (select id from public.products where code='ORC-SENS'),
                       'code','ORC-SENS','name','Sensor opcional ORC','unit','UN',
                       'quantity_milli',1000,'unit_price_cents',25000,
                       'item_type','optional','selected',true),
    jsonb_build_object('product_id', (select id from public.products where code='ORC-SUP'),
                       'code','ORC-SUP','name','Suporte opcional ORC','unit','UN',
                       'quantity_milli',1000,'unit_price_cents',12000,
                       'item_type','optional','selected',false)
  )
from public.quotes q, public.kits k
where k.code = 'ORC-KIT'
  and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DI) kit guarda TODOS os componentes' as teste,
       jsonb_array_length(components_snapshot) as componentes,
       case when jsonb_array_length(components_snapshot) = 4 then 'OK: 4 (inclusive o recusado)'
            else 'FALHA' end as resultado
from public.quote_items where kind = 'kit' and code_snapshot = 'ORC-KIT';

select 'DJ) opcional recusado fica registrado' as teste,
       case when exists (
         select 1 from public.quote_items qi,
              jsonb_array_elements(qi.components_snapshot) c
         where qi.code_snapshot = 'ORC-KIT'
           and c ->> 'code' = 'ORC-SUP'
           and (c ->> 'selected')::boolean = false
       ) then 'OK: ORC-SUP marcado como não escolhido' else 'FALHA' end as resultado;

select 'DK) preco do kit soma obrigatorios + escolhidos' as teste,
       unit_price, quantity, line_total,
       case when unit_price = 2250.00 and line_total = 4500.00 then 'OK' else 'FALHA' end as resultado
from public.quote_items where kind = 'kit' and code_snapshot = 'ORC-KIT';

select 'DL) total do orcamento com produto e kit' as teste,
       subtotal, total,
       case when subtotal = 5100.00 and total = 5100.00 then 'OK' else 'FALHA' end as resultado
from public.quotes q where q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ── DESCONTOS ───────────────────────────────────────────────
update public.quotes set discount_percent = 10
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DM) desconto percentual aplicado no banco' as teste,
       subtotal, total,
       case when total = 4590.00 then 'OK' else 'FALHA' end as resultado
from public.quotes where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quotes set discount_amount = 90, shipping_amount = 100
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DN) desconto em valor e frete' as teste,
       total,
       case when total = 4600.00 then 'OK' else 'FALHA' end as resultado
from public.quotes where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

do $$ begin
  update public.quotes set discount_percent = -5
   where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  raise notice 'DO) FALHA: aceitou desconto negativo';
exception when check_violation then raise notice 'DO) OK: desconto negativo bloqueado';
end $$;

do $$ begin
  update public.quotes set discount_percent = 120
   where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  raise notice 'DP) FALHA: aceitou desconto acima de 100%%';
exception when check_violation then raise notice 'DP) OK: desconto acima de 100%% bloqueado';
end $$;

-- Desconto maior que o subtotal não gera total negativo.
update public.quotes set discount_percent = 0, discount_amount = 999999, shipping_amount = 0
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DQ) total nunca fica negativo' as teste,
       subtotal, total,
       case when total = 0 and subtotal = 5100.00 then 'OK: piso em zero' else 'FALHA' end as resultado
from public.quotes where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quotes set discount_amount = 0
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ── QUANTIDADE ──────────────────────────────────────────────
do $$ begin
  insert into public.quote_items (quote_id, kind, product_id, name_snapshot, quantity, unit_price)
  select q.id, 'product', p.id, p.name, 0, 10
  from public.quotes q, public.products p
  where p.code = 'ORC-AVULSO'
    and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  raise notice 'DR) FALHA: aceitou quantidade zero';
exception when check_violation then raise notice 'DR) OK: quantidade zero bloqueada';
end $$;

do $$ begin
  insert into public.quote_items (quote_id, kind, product_id, name_snapshot, quantity, unit_price)
  select q.id, 'product', p.id, p.name, 1, -5
  from public.quotes q, public.products p
  where p.code = 'ORC-AVULSO'
    and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  raise notice 'DS) FALHA: aceitou preco negativo';
exception when check_violation then raise notice 'DS) OK: preco negativo bloqueado';
end $$;

-- ── INTEGRIDADE REFERENCIAL ─────────────────────────────────
do $$ begin
  insert into public.quote_items (quote_id, kind, product_id, kit_id, name_snapshot, quantity, unit_price)
  select q.id, 'product', p.id, k.id, 'Referência cruzada', 1, 10
  from public.quotes q, public.products p, public.kits k
  where p.code = 'ORC-AVULSO' and k.code = 'ORC-KIT'
    and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  raise notice 'DT) FALHA: aceitou item de produto apontando para kit';
exception when check_violation then raise notice 'DT) OK: referencia cruzada bloqueada';
end $$;

do $$ begin
  delete from public.kits where code = 'ORC-KIT';
  raise notice 'DU) FALHA: apagou kit citado em orcamento';
exception when foreign_key_violation then raise notice 'DU) OK: exclusao de kit com orcamento recusada';
end $$;

do $$ begin
  delete from public.customers where name = 'Cliente do Orçamento';
  raise notice 'DV) FALHA: apagou cliente com orcamento';
exception when foreign_key_violation then raise notice 'DV) OK: exclusao de cliente com orcamento recusada';
end $$;

-- ── STATUS ──────────────────────────────────────────────────
update public.quotes set status = 'sent'
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DW) carimbo de envio' as teste,
       case when sent_at is not null then 'OK' else 'FALHA' end as resultado
from public.quotes where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quotes set status = 'cancelled'
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

select 'DX) status cancelado existe' as teste,
       case when status = 'cancelled' then 'OK' else 'FALHA' end as resultado
from public.quotes where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quotes set status = 'draft'
 where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ══════════════════════════════════════════════════════════════
-- TESTE CRÍTICO DE HISTÓRICO
-- O catálogo inteiro muda embaixo do orçamento. Nada pode mexer nele.
-- ══════════════════════════════════════════════════════════════

create temporary table orc_antes as
select qi.id, qi.code_snapshot, qi.name_snapshot, qi.unit_snapshot,
       qi.quantity, qi.unit_price, qi.line_total, qi.components_snapshot
from public.quote_items qi
join public.quotes q on q.id = qi.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

create temporary table orc_totais_antes as
select subtotal, total from public.quotes
where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- 8. preço do produto muda
update public.products set sale_price = 9999 where code in ('ORC-AVULSO','ORC-CTRL','ORC-ANT','ORC-SENS','ORC-SUP');
-- 9. nome do produto muda
update public.products set name = 'NOME TROCADO' where code in ('ORC-AVULSO','ORC-CTRL','ORC-ANT');
-- 9b. produto é desativado
update public.products set is_active = false where code = 'ORC-AVULSO';
-- 10. composição do kit muda: some um obrigatório, entra outro item,
--     e um opcional vira obrigatório
delete from public.kit_items ki using public.products p
 where ki.product_id = p.id and p.code = 'ORC-ANT';
update public.kit_items ki set item_type = 'required'
  from public.products p where p.id = ki.product_id and p.code = 'ORC-SENS';
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 5, 'required' from public.kits k, public.products p
where k.code = 'ORC-KIT' and p.code = 'ORC-AVULSO';
-- 10b. o kit é renomeado e desativado
update public.kits set name = 'KIT RENOMEADO', is_active = false where code = 'ORC-KIT';

-- 13. conferência
select 'EA) preco do item nao mudou' as teste,
       case when count(*) = 0 then 'OK: nenhum item alterado'
            else 'FALHA: ' || count(*) || ' item(ns) mudaram' end as resultado
from public.quote_items qi
join orc_antes a on a.id = qi.id
where qi.unit_price is distinct from a.unit_price
   or qi.line_total is distinct from a.line_total;

select 'EB) nome congelado no item' as teste,
       name_snapshot,
       case when name_snapshot = 'Produto avulso ORC' then 'OK' else 'FALHA' end as resultado
from public.quote_items where code_snapshot = 'ORC-AVULSO';

select 'EC) codigo e unidade congelados' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA' end as resultado
from public.quote_items qi join orc_antes a on a.id = qi.id
where qi.code_snapshot is distinct from a.code_snapshot
   or qi.unit_snapshot is distinct from a.unit_snapshot;

select 'ED) composicao do kit congelada' as teste,
       jsonb_array_length(components_snapshot) as componentes,
       case when components_snapshot = (select components_snapshot from orc_antes where code_snapshot='ORC-KIT')
            then 'OK: idêntica' else 'FALHA' end as resultado
from public.quote_items where code_snapshot = 'ORC-KIT';

select 'EE) componente removido do kit continua no orcamento' as teste,
       case when exists (
         select 1 from public.quote_items qi, jsonb_array_elements(qi.components_snapshot) c
         where qi.code_snapshot = 'ORC-KIT' and c ->> 'code' = 'ORC-ANT'
       ) then 'OK: ORC-ANT preservado' else 'FALHA' end as resultado;

select 'EF) componente novo do kit NAO entrou no orcamento' as teste,
       case when not exists (
         select 1 from public.quote_items qi, jsonb_array_elements(qi.components_snapshot) c
         where qi.code_snapshot = 'ORC-KIT' and c ->> 'code' = 'ORC-AVULSO'
       ) then 'OK: fora' else 'FALHA: entrou sozinho' end as resultado;

select 'EG) opcional que virou obrigatorio continua opcional no historico' as teste,
       case when exists (
         select 1 from public.quote_items qi, jsonb_array_elements(qi.components_snapshot) c
         where qi.code_snapshot = 'ORC-KIT' and c ->> 'code' = 'ORC-SENS'
           and c ->> 'item_type' = 'optional'
       ) then 'OK' else 'FALHA' end as resultado;

select 'EH) preco do componente congelado' as teste,
       case when exists (
         select 1 from public.quote_items qi, jsonb_array_elements(qi.components_snapshot) c
         where qi.code_snapshot = 'ORC-KIT' and c ->> 'code' = 'ORC-CTRL'
           and (c ->> 'unit_price_cents')::int = 100000
       ) then 'OK: 100000 centavos' else 'FALHA' end as resultado;

select 'EI) nome do kit congelado' as teste,
       name_snapshot,
       case when name_snapshot = 'Kit do orçamento' then 'OK' else 'FALHA' end as resultado
from public.quote_items where code_snapshot = 'ORC-KIT';

select 'EJ) totais do orcamento intactos' as teste,
       q.subtotal, q.total,
       case when q.subtotal = a.subtotal and q.total = a.total then 'OK' else 'FALHA' end as resultado
from public.quotes q, orc_totais_antes a
where q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- Produto excluído fisicamente: a referência some, o snapshot fica.
delete from public.kit_items ki using public.products p
 where ki.product_id = p.id and p.code = 'ORC-AVULSO';
delete from public.products where code = 'ORC-AVULSO';

select 'EK) produto excluido: referencia nula, snapshot inteiro' as teste,
       name_snapshot, unit_price,
       case when product_id is null and name_snapshot = 'Produto avulso ORC' and unit_price = 300.00
            then 'OK' else 'FALHA' end as resultado
from public.quote_items where code_snapshot = 'ORC-AVULSO';

-- ── RLS: ISOLAMENTO ENTRE VENDEDORES ────────────────────────
insert into public.quotes (customer_id, owner_id)
select c.id, '22222222-2222-2222-2222-222222222222'
from public.customers c where c.name = 'Cliente do Orçamento';

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'EL) vendedor nao enxerga orcamento de outro' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA: viu ' || count(*) end as resultado
from public.quotes q
where q.owner_id = '11111111-1111-1111-1111-111111111111';

select 'EM) vendedor nao enxerga itens de outro' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA: viu ' || count(*) end as resultado
from public.quote_items where code_snapshot in ('ORC-KIT','ORC-AVULSO');

do $$ declare afetadas int; begin
  update public.quotes set total = 1, notes = 'invadido'
   where owner_id = '11111111-1111-1111-1111-111111111111';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'EN) OK: vendedor nao altera orcamento alheio';
  else raise notice 'EN) FALHA DE SEGURANCA: alterou % orcamento(s)', afetadas; end if;
end $$;

do $$ begin
  insert into public.quotes (customer_id, owner_id)
  select c.id, '11111111-1111-1111-1111-111111111111'
  from public.customers c where c.name = 'Cliente do Orçamento';
  raise notice 'EO) FALHA DE SEGURANCA: vendedor criou orcamento para outro dono';
exception when others then raise notice 'EO) OK: vendedor bloqueado ao criar para outro dono';
end $$;

-- O vendedor mexe no PRÓPRIO orçamento normalmente.
insert into public.quote_items (quote_id, kind, product_id, code_snapshot, name_snapshot, quantity, unit_price)
select q.id, 'product', p.id, p.code, p.name, 1, 500
from public.quotes q, public.products p
where q.owner_id = '22222222-2222-2222-2222-222222222222'
  and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento')
  and p.code = 'ORC-ANT'
limit 1;

select 'EP) vendedor monta o proprio orcamento' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from public.quote_items qi join public.quotes q on q.id = qi.quote_id
where q.owner_id = '22222222-2222-2222-2222-222222222222'
  and q.customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ── APROVADO É INTOCÁVEL PARA O VENDEDOR ────────────────────
-- A migration 20260901201459 passou a exigir a máquina de estados no banco:
-- não existe mais o salto draft -> approved. O caminho legítimo é via 'sent'.
update public.quotes set status = 'sent'
 where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
update public.quotes set status = 'approved'
 where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

do $$ declare afetadas int; begin
  update public.quote_items set unit_price = 1
   where quote_id in (select id from public.quotes where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento'));
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'EQ) OK: item de orcamento aprovado nao muda';
  else raise notice 'EQ) FALHA DE SEGURANCA: alterou % item(ns)', afetadas; end if;
end $$;

do $$ declare afetadas int; begin
  delete from public.quote_items
   where quote_id in (select id from public.quotes where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento'));
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'ER) OK: item de aprovado nao e apagado';
  else raise notice 'ER) FALHA DE SEGURANCA: apagou % item(ns)', afetadas; end if;
end $$;

-- O vendedor também não CONSEGUE tirar o próprio orçamento de aprovado:
-- a policy `quotes_update` só o deixa mexer nos demais status.
do $$ declare afetadas int; begin
  update public.quotes set status = 'draft'
   where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'ES) OK: vendedor nao reabre orcamento aprovado';
  else raise notice 'ES) FALHA DE SEGURANCA: vendedor reabriu % orcamento(s)', afetadas; end if;
end $$;

-- ── CANCELADO TAMBÉM CONGELA (migration 1700) ───────────────
-- Quem reabre o aprovado é o administrador.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quotes set status = 'draft'
 where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'ET) admin reabriu o aprovado' as teste,
       case when status = 'draft' then 'OK' else 'FALHA: ' || status end as resultado
from public.quotes where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quotes set status = 'cancelled'
 where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

do $$ declare afetadas int; begin
  update public.quote_items set quantity = 99
   where quote_id in (select id from public.quotes where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento'));
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'EU) OK: item de cancelado nao muda';
  else raise notice 'EU) FALHA: alterou % item(ns) de orcamento cancelado', afetadas; end if;
end $$;

-- Mas o dono consegue REABRIR o cancelado.
update public.quotes set status = 'draft'
 where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
select 'EV) dono reabre o proprio cancelado' as teste,
       case when status = 'draft' then 'OK' else 'FALHA: ' || status end as resultado
from public.quotes where owner_id = '22222222-2222-2222-2222-222222222222'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- ── ADMIN ───────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select 'EW) admin enxerga orcamento de todos' as teste,
       case when count(*) >= 2 then 'OK: ' || count(*) else 'FALHA: ' || count(*) end as resultado
from public.quotes
where customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

-- Mesmo o admin passa pela máquina de estados: draft -> sent -> approved.
update public.quotes set status = 'sent'
 where owner_id = '11111111-1111-1111-1111-111111111111'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');
update public.quotes set status = 'approved'
 where owner_id = '11111111-1111-1111-1111-111111111111'
   and customer_id = (select id from public.customers where name = 'Cliente do Orçamento');

update public.quote_items set notes = 'ajuste do admin'
 where quote_id in (
   select id from public.quotes
   where owner_id = '11111111-1111-1111-1111-111111111111'
     and customer_id = (select id from public.customers where name = 'Cliente do Orçamento')
 );

select 'EX) admin corrige orcamento aprovado' as teste,
       case when count(*) > 0 then 'OK' else 'FALHA' end as resultado
from public.quote_items where notes = 'ajuste do admin';

-- ── DESCARTE DE RASCUNHO (migration 1800) ───────────────────
-- Exclusão lógica não pode ser um UPDATE comum: a policy de SELECT
-- filtra `deleted_at is null`, e o PostgreSQL exige que a linha
-- resultante de um UPDATE continue visível. Prova disso primeiro:
insert into public.quotes (customer_id, owner_id)
select c.id, '11111111-1111-1111-1111-111111111111'
from public.customers c where c.name = 'Cliente do Orçamento';

do $$
declare v_id uuid;
begin
  select id into v_id from public.quotes
   where owner_id = '11111111-1111-1111-1111-111111111111'
     and status = 'draft' and deleted_at is null
   order by created_at desc limit 1;

  begin
    update public.quotes set deleted_at = now() where id = v_id;
    raise notice 'EZ) FALHA: update direto de deleted_at passou (a policy mudou?)';
  exception when insufficient_privilege then
    raise notice 'EZ) OK: update direto de deleted_at e recusado pelo RLS';
  end;

  perform public.discard_quote_draft(v_id);
  -- Depois de descartado o orçamento some para TODO MUNDO: a policy de
  -- SELECT filtra `deleted_at is null`. Conferir "sumiu" é justamente a
  -- conferência certa — não dá para ler a linha de dentro do RLS.
  if exists (select 1 from public.quotes where id = v_id) then
    raise notice 'FA) FALHA: rascunho continua visivel apos o descarte';
  else
    raise notice 'FA) OK: discard_quote_draft tirou o rascunho de circulacao';
  end if;
end $$;

-- Orçamento que não é rascunho não se descarta: cancela-se.
do $$
declare v_id uuid;
begin
  select id into v_id from public.quotes
   where owner_id = '11111111-1111-1111-1111-111111111111'
     and status = 'approved' and deleted_at is null
   order by created_at desc limit 1;

  begin
    perform public.discard_quote_draft(v_id);
    raise notice 'FB) FALHA: descartou orcamento aprovado';
  exception when check_violation then
    raise notice 'FB) OK: so rascunho e descartado';
  end;
end $$;

-- O vendedor não descarta rascunho alheio.
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
do $$
declare v_id uuid;
begin
  select id into v_id from public.quotes
   where owner_id = '11111111-1111-1111-1111-111111111111' and deleted_at is null
   limit 1;
  if v_id is null then
    -- O vendedor nem enxerga o orçamento alheio; a proteção já valeu.
    raise notice 'FC) OK: vendedor nao alcanca rascunho alheio';
  else
    begin
      perform public.discard_quote_draft(v_id);
      raise notice 'FC) FALHA DE SEGURANCA: vendedor descartou rascunho alheio';
    exception when insufficient_privilege then
      raise notice 'FC) OK: vendedor bloqueado ao descartar rascunho alheio';
    end;
  end if;
end $$;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select 'FD) descartado some da listagem' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA: ' || count(*) end as resultado
from public.quotes_list ql
join public.quotes q on q.id = ql.id
where q.deleted_at is not null;

-- ── ESTADO FINAL ────────────────────────────────────────────
select 'EY) estado final integro' as teste,
       case when (select count(*) from public.quote_items where code_snapshot = 'ORC-KIT') = 1
             and (select unit_price from public.quote_items where code_snapshot = 'ORC-KIT') = 2250.00
             and (select jsonb_array_length(components_snapshot) from public.quote_items where code_snapshot='ORC-KIT') = 4
            then 'OK: historico preservado do inicio ao fim' else 'FALHA' end as resultado;

reset role;
