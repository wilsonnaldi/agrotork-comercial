-- ============================================================
-- KITS: composição obrigatória e opcional (migration 1600).
--
-- Cobre o que a Fase 3 prometeu: criação, edição, ativação,
-- desativação, item obrigatório, item opcional, duplicidade,
-- quantidade, produto inativo, permissões (admin × vendedor),
-- preservação da composição e do histórico.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

-- Produtos de apoio, com preço conhecido para conferir o total.
insert into public.products (code, name, unit_id, sale_price)
select 'KIT-CTRL', 'Controlador de teste', u.id, 1000 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'KIT-ANT', 'Antena de teste', u.id, 500 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'KIT-SENS', 'Sensor opcional de teste', u.id, 250 from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price, is_active)
select 'KIT-OFF', 'Produto desativado', u.id, 90, false from public.units u where u.code = 'UN';
insert into public.products (code, name, unit_id, sale_price)
select 'KIT-CABO', 'Cabo por metro', u.id, 12 from public.units u where u.code = 'M';

-- ── CRIAÇÃO ─────────────────────────────────────────────────
insert into public.kits (code, name, description) values
  ('KIT-F3', 'Kit da Fase 3', 'Kit montado pelos testes de banco');

select 'CA) kit criado' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from public.kits where code = 'KIT-F3';

-- Kit sem item nenhum é permitido: o cadastro é em dois passos.
select 'CB) kit vazio existe e conta zero' as teste,
       case when items_count = 0 and required_count = 0 and optional_count = 0
            then 'OK: vazio' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

-- ── ITENS OBRIGATÓRIOS ──────────────────────────────────────
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'required' from public.kits k, public.products p
where k.code = 'KIT-F3' and p.code = 'KIT-CTRL';

insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 2, 'required' from public.kits k, public.products p
where k.code = 'KIT-F3' and p.code = 'KIT-ANT';

select 'CC) item obrigatorio adicionado' as teste,
       case when required_count = 2 then 'OK' else 'FALHA: ' || required_count end as resultado
from public.kits_with_price where code = 'KIT-F3';

-- ── ITEM OPCIONAL ───────────────────────────────────────────
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code = 'KIT-F3' and p.code = 'KIT-SENS';

select 'CD) item opcional adicionado' as teste,
       case when optional_count = 1 and items_count = 3 then 'OK' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

-- Padrão do enum: quem não informa o papel entra como obrigatório.
insert into public.kit_items (kit_id, product_id, quantity)
select k.id, p.id, 1.5 from public.kits k, public.products p
where k.code = 'KIT-F3' and p.code = 'KIT-CABO';

select 'CE) item_type padrao e required' as teste,
       case when item_type = 'required' then 'OK' else 'FALHA: ' || item_type end as resultado
from public.kit_items ki join public.products p on p.id = ki.product_id where p.code = 'KIT-CABO';

-- ── PREÇO DERIVADO: base = só obrigatórios ──────────────────
-- 1×1000 + 2×500 + 1,5×12 = 2018,00 · opcionais 1×250 = 250,00
select 'CF) preco-base soma so os obrigatorios' as teste,
       components_total, optional_total,
       case when components_total = 2018.000 and optional_total = 250.000
            then 'OK' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

-- ── DUPLICIDADE ─────────────────────────────────────────────
-- O mesmo produto não entra duas vezes, nem mudando o papel.
do $$ begin
  insert into public.kit_items (kit_id, product_id, quantity, item_type)
  select k.id, p.id, 1, 'optional' from public.kits k, public.products p
  where k.code = 'KIT-F3' and p.code = 'KIT-CTRL';
  raise notice 'CG) FALHA: aceitou o mesmo produto duas vezes no kit';
exception when unique_violation then
  raise notice 'CG) OK: produto duplicado no mesmo kit bloqueado';
end $$;

-- ── QUANTIDADE ──────────────────────────────────────────────
do $$ begin
  insert into public.kit_items (kit_id, product_id, quantity)
  select k.id, p.id, 0 from public.kits k, public.products p
  where k.code = 'KIT-F3' and p.code = 'KIT-OFF';
  raise notice 'CH) FALHA: aceitou quantidade zero';
exception when check_violation then raise notice 'CH) OK: quantidade zero bloqueada';
end $$;

do $$ begin
  insert into public.kit_items (kit_id, product_id, quantity)
  select k.id, p.id, -1 from public.kits k, public.products p
  where k.code = 'KIT-F3' and p.code = 'KIT-OFF';
  raise notice 'CI) FALHA: aceitou quantidade negativa';
exception when check_violation then raise notice 'CI) OK: quantidade negativa bloqueada';
end $$;

-- ── PRODUTO INEXISTENTE ─────────────────────────────────────
do $$ begin
  insert into public.kit_items (kit_id, product_id, quantity)
  select k.id, '00000000-0000-4000-8000-000000000000', 1 from public.kits k where k.code = 'KIT-F3';
  raise notice 'CJ) FALHA: aceitou produto inexistente';
exception when foreign_key_violation then raise notice 'CJ) OK: produto inexistente bloqueado';
end $$;

-- ── PRODUTO INATIVO ─────────────────────────────────────────
-- O banco aceita: o vínculo com produto desativado precisa continuar
-- válido para os kits que JÁ o usavam. A recusa de associação NOVA é
-- regra de negócio, no service (kits/service.ts → addComponent), e está
-- coberta pelo e2e. Aqui provamos que o banco não invalida o vínculo.
insert into public.kit_items (kit_id, product_id, quantity, item_type)
select k.id, p.id, 1, 'optional' from public.kits k, public.products p
where k.code = 'KIT-F3' and p.code = 'KIT-OFF';

select 'CK) vinculo com produto inativo permanece valido' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from public.kit_items ki join public.products p on p.id = ki.product_id
where p.code = 'KIT-OFF';

-- ── ALTERNAR PAPEL ──────────────────────────────────────────
update public.kit_items ki set item_type = 'optional'
from public.products p where p.id = ki.product_id and p.code = 'KIT-ANT';

select 'CL) obrigatorio vira opcional' as teste,
       required_count, optional_count,
       case when required_count = 2 and optional_count = 3 then 'OK' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

update public.kit_items ki set item_type = 'required'
from public.products p where p.id = ki.product_id and p.code = 'KIT-ANT';

-- ── EDIÇÃO E SITUAÇÃO ───────────────────────────────────────
update public.kits set name = 'Kit da Fase 3 — revisado' where code = 'KIT-F3';
select 'CM) edicao do kit' as teste,
       case when name = 'Kit da Fase 3 — revisado' then 'OK' else 'FALHA' end as resultado
from public.kits where code = 'KIT-F3';

do $$ begin
  insert into public.kits (code, name) values ('kit-f3', 'Código repetido em outra caixa');
  raise notice 'CN) FALHA: aceitou codigo de kit duplicado';
exception when unique_violation then raise notice 'CN) OK: codigo de kit duplicado bloqueado';
end $$;

update public.kits set is_active = false where code = 'KIT-F3';
select 'CO) desativacao preserva a composicao' as teste,
       is_active, items_count,
       case when is_active = false and items_count = 5 then 'OK: composição intacta' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

update public.kits set is_active = true where code = 'KIT-F3';
select 'CP) reativacao' as teste,
       case when is_active then 'OK' else 'FALHA' end as resultado
from public.kits_with_price where code = 'KIT-F3';

-- ── HISTÓRICO: kit citado em orçamento ──────────────────────
insert into public.quotes (customer_id, owner_id)
select c.id, '11111111-1111-1111-1111-111111111111' from public.customers c limit 1;

insert into public.quote_items (quote_id, kind, kit_id, name_snapshot, quantity, unit_price, components_snapshot)
select q.id, 'kit', k.id, k.name, 1, 2018,
       jsonb_build_array(jsonb_build_object('code','KIT-CTRL','quantity',1,'unit_price',1000))
from public.quotes q, public.kits k
where k.code = 'KIT-F3'
order by q.created_at desc limit 1;

-- Kit com referência histórica não é excluído fisicamente.
do $$ begin
  delete from public.kits where code = 'KIT-F3';
  raise notice 'CQ) FALHA: apagou kit citado em orcamento';
exception when foreign_key_violation then
  raise notice 'CQ) OK: exclusao de kit com historico recusada';
end $$;

-- Mexer no cadastro não reescreve o orçamento.
delete from public.kit_items ki using public.products p
where ki.product_id = p.id and p.code = 'KIT-SENS';

select 'CR) alterar o kit nao altera o orcamento' as teste,
       unit_price, components_snapshot -> 0 ->> 'code' as item_congelado,
       case when unit_price = 2018.00 then 'OK: congelado' else 'FALHA' end as resultado
from public.quote_items where kind = 'kit' and name_snapshot like 'Kit da Fase 3%';

-- ── PERMISSÕES: ADMIN ADMINISTRA ────────────────────────────
insert into public.kits (code, name) values ('KIT-TMP', 'Kit descartável');
update public.kits set description = 'editado pelo admin' where code = 'KIT-TMP';
delete from public.kits where code = 'KIT-TMP';
select 'CS) admin administra (criar, editar, apagar sem historico)' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA' end as resultado
from public.kits where code = 'KIT-TMP';

-- ── PERMISSÕES: VENDEDOR ────────────────────────────────────
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'CT) vendedor consulta kits' as teste,
       case when count(*) > 0 then 'OK: ' || count(*) || ' kit(s)' else 'FALHA' end as resultado
from public.kits_with_price;

select 'CU) vendedor consulta a composicao' as teste,
       case when count(*) = 4 then 'OK' else 'FALHA: ' || count(*) end as resultado
from public.kit_items ki join public.kits k on k.id = ki.kit_id where k.code = 'KIT-F3';

-- O vendedor lê o kit desativado: vai precisar disso para abrir um
-- orçamento antigo. O que ele não pode é escrever.
do $$ begin
  insert into public.kits (code, name) values ('KIT-VEND', 'Kit do vendedor');
  raise notice 'CV) FALHA DE SEGURANCA: vendedor criou kit';
exception when insufficient_privilege or others then
  raise notice 'CV) OK: vendedor bloqueado ao criar kit';
end $$;

do $$ declare afetadas int; begin
  update public.kits set name = 'Sequestrado' where code = 'KIT-F3';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'CW) OK: alteracao de kit pelo vendedor ignorada';
  else raise notice 'CW) FALHA DE SEGURANCA: vendedor alterou % kit(s)', afetadas; end if;
end $$;

do $$ declare afetadas int; begin
  update public.kits set is_active = false where code = 'KIT-F3';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'CX) OK: desativacao pelo vendedor ignorada';
  else raise notice 'CX) FALHA DE SEGURANCA: vendedor desativou % kit(s)', afetadas; end if;
end $$;

do $$ begin
  insert into public.kit_items (kit_id, product_id, quantity)
  select k.id, p.id, 1 from public.kits k, public.products p
  where k.code = 'KIT-F3' and p.code = 'KIT-OFF';
  raise notice 'CY) FALHA DE SEGURANCA: vendedor adicionou componente';
exception when insufficient_privilege or others then
  raise notice 'CY) OK: vendedor bloqueado ao adicionar componente';
end $$;

do $$ declare afetadas int; begin
  update public.kit_items set item_type = 'optional', quantity = 99;
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'CZ) OK: alteracao de kit_items pelo vendedor ignorada';
  else raise notice 'CZ) FALHA DE SEGURANCA: vendedor alterou % componente(s)', afetadas; end if;
end $$;

do $$ declare afetadas int; begin
  delete from public.kit_items;
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'DA) OK: exclusao de kit_items pelo vendedor ignorada';
  else raise notice 'DA) FALHA DE SEGURANCA: vendedor apagou % componente(s)', afetadas; end if;
end $$;

-- ── CUSTO CONTINUA FORA DO ALCANCE ──────────────────────────
select 'DB) vendedor nao alcanca custo pelo kit' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha de custo' else 'FALHA: ' || count(*) end as resultado
from public.product_costs pc
join public.kit_items ki on ki.product_id = pc.product_id
join public.kits k on k.id = ki.kit_id where k.code = 'KIT-F3';

-- ── ESTADO FINAL ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select 'DC) estado final integro' as teste,
       case when (select count(*) from public.kits where code = 'KIT-F3') = 1
             and (select count(*) from public.kits where name = 'Sequestrado') = 0
             and (select items_count from public.kits_with_price where code = 'KIT-F3') = 4
             and (select is_active from public.kits where code = 'KIT-F3')
            then 'OK: kit preservado' else 'FALHA' end as resultado;

reset role;
