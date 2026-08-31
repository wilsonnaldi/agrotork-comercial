-- ============================================================
-- Cadastros de apoio: MARCAS, CATEGORIAS e UNIDADES (migration 1500).
--
-- Cobre o que a Fase 1 prometeu: criação, edição, duplicidade,
-- ativação/desativação, permissões (admin x vendedor), relacionamento
-- com produtos e o que acontece com um registro inativo.
--
-- Contexto herdado: 02 criou o vendedor 2222…, 01 criou o admin 1111…
-- ============================================================
\set ON_ERROR_STOP on
reset role;

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

-- ── CRIAÇÃO ─────────────────────────────────────────────────
-- Nenhum insert informa `slug`: quem preenche é o trigger. Se a
-- aplicação tivesse de calcular o slug, todo insert vindo da tela
-- falharia no `not null`.
insert into public.brands (name, description) values ('Jacto Fase1', 'Marca comercial de teste');
insert into public.categories (name, description) values ('Colheita Fase1', 'Categoria de teste');
insert into public.units (code, name, allows_fraction) values ('CX', 'Caixa', false);

select 'BA) marca criada com slug automatico' as teste,
       case when slug = 'jacto-fase1' then 'OK: ' || slug else 'FALHA: ' || coalesce(slug,'nulo') end as resultado
from public.brands where name = 'Jacto Fase1';

select 'BB) categoria criada com slug automatico' as teste,
       case when slug = 'colheita-fase1' then 'OK: ' || slug else 'FALHA: ' || coalesce(slug,'nulo') end as resultado
from public.categories where name = 'Colheita Fase1';

select 'BC) unidade criada' as teste,
       case when code = 'CX' and allows_fraction = false then 'OK' else 'FALHA' end as resultado
from public.units where code = 'CX';

-- ── EDIÇÃO ──────────────────────────────────────────────────
update public.brands set name = 'Jacto Máquinas', description = 'Nome corrigido' where name = 'Jacto Fase1';

select 'BD) edicao renomeia e reflete no slug' as teste,
       case when slug = 'jacto-maquinas' then 'OK: ' || slug else 'FALHA: ' || slug end as resultado
from public.brands where name = 'Jacto Máquinas';

update public.units set name = 'Caixa fechada' where code = 'CX';
select 'BE) edicao de unidade' as teste,
       case when name = 'Caixa fechada' then 'OK' else 'FALHA' end as resultado
from public.units where code = 'CX';

-- ── DUPLICIDADE ─────────────────────────────────────────────
-- "BALDAN" e "baldan" são a mesma marca. O banco recusa, mesmo que a
-- aplicação um dia esqueça de checar.
do $$ begin
  insert into public.brands (name) values ('baldan');
  raise notice 'BF) FALHA: aceitou marca duplicada em outra caixa';
exception when unique_violation then raise notice 'BF) OK: marca duplicada bloqueada';
end $$;

do $$ begin
  insert into public.categories (name) values ('peças');
  raise notice 'BG) FALHA: aceitou categoria duplicada em outra caixa';
exception when unique_violation then raise notice 'BG) OK: categoria duplicada bloqueada';
end $$;

do $$ begin
  insert into public.units (code, name) values ('cx', 'Caixa repetida');
  raise notice 'BH) FALHA: aceitou codigo de unidade duplicado';
exception when unique_violation then raise notice 'BH) OK: codigo de unidade duplicado bloqueado';
end $$;

-- LT não é L. O código é a identidade; o nome pode se repetir de
-- propósito, porque a equivalência entre unidades é decisão do usuário,
-- não suposição do sistema.
insert into public.units (code, name, allows_fraction) values ('LT', 'Litro', true);
select 'BI) LT e L coexistem como unidades distintas' as teste,
       case when count(*) = 2 and count(distinct id) = 2 then 'OK: dois registros'
            else 'FALHA: ' || count(*) end as resultado
from public.units where code in ('L','LT');

-- ── RELACIONAMENTO COM PRODUCTS ─────────────────────────────
insert into public.products (code, name, unit_id, sale_price, brand_id, category_id)
select 'CAD-001', 'Produto vinculado ao cadastro', u.id, 250, b.id, c.id
from public.units u, public.brands b, public.categories c
where u.code = 'CX' and b.name = 'Jacto Máquinas' and c.name = 'Colheita Fase1';

select 'BJ) produto vinculado' as teste,
       case when brand_name = 'Jacto Máquinas' and category_name = 'Colheita Fase1' and unit_code = 'CX'
            then 'OK' else 'FALHA' end as resultado
from public.products_list where code = 'CAD-001';

-- Exclusão física é recusada pelo banco enquanto houver produto vinculado.
do $$ begin
  delete from public.brands where name = 'Jacto Máquinas';
  raise notice 'BK) FALHA: apagou marca com produto vinculado';
exception when foreign_key_violation then raise notice 'BK) OK: exclusao de marca com produto recusada';
end $$;

do $$ begin
  delete from public.units where code = 'CX';
  raise notice 'BL) FALHA: apagou unidade com produto vinculado';
exception when foreign_key_violation then raise notice 'BL) OK: exclusao de unidade com produto recusada';
end $$;

-- ── DESATIVAÇÃO ─────────────────────────────────────────────
update public.brands     set is_active = false where name = 'Jacto Máquinas';
update public.categories set is_active = false where name = 'Colheita Fase1';
update public.units      set is_active = false where code = 'CX';

select 'BM) desativar preserva o produto e o vinculo' as teste,
       case when count(*) = 1 then 'OK: produto intacto' else 'FALHA: ' || count(*) end as resultado
from public.products_list
where code = 'CAD-001' and brand_name = 'Jacto Máquinas' and category_name = 'Colheita Fase1';

-- O produto continua editável mesmo com o cadastro desativado: desativar
-- tira o registro da vitrine, não invalida o que já existe. A regra que
-- impede USAR um cadastro inativo em vínculo NOVO é do serviço da
-- aplicação (products/service.ts) e está coberta pelo e2e — aqui provamos
-- que o banco não trava o que já estava vinculado.
update public.products set sale_price = 275 where code = 'CAD-001';
select 'BN) produto com cadastro inativo continua editavel' as teste,
       case when sale_price = 275 then 'OK' else 'FALHA' end as resultado
from public.products where code = 'CAD-001';

select 'BO) cadastro inativo sai das opcoes ativas' as teste,
       case when count(*) = 0 then 'OK: fora da selecao' else 'FALHA: ainda aparece' end as resultado
from public.brands where name = 'Jacto Máquinas' and is_active;

-- ── REATIVAÇÃO ──────────────────────────────────────────────
update public.brands set is_active = true where name = 'Jacto Máquinas';
select 'BP) reativacao' as teste,
       case when is_active then 'OK' else 'FALHA' end as resultado
from public.brands where name = 'Jacto Máquinas';

-- ── PERMISSÕES: ADMIN ADMINISTRA ────────────────────────────
insert into public.brands (name) values ('Marca Descartavel');
update public.brands set description = 'editada pelo admin' where name = 'Marca Descartavel';
delete from public.brands where name = 'Marca Descartavel';
select 'BQ) admin administra (criar, editar, apagar sem vinculo)' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA' end as resultado
from public.brands where name = 'Marca Descartavel';

-- ── PERMISSÕES: VENDEDOR ────────────────────────────────────
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'BR) vendedor consulta marcas' as teste,
       case when count(*) > 0 then 'OK: ' || count(*) || ' marcas' else 'FALHA: nao le' end as resultado
from public.brands;

select 'BS) vendedor consulta categorias e unidades' as teste,
       (select count(*) from public.categories) as categorias,
       (select count(*) from public.units) as unidades;

-- O vendedor precisa LER o cadastro desativado para abrir a ficha de um
-- produto antigo — o que ele não pode é escolher esse cadastro em algo novo.
select 'BT) vendedor le cadastro desativado (ficha do produto)' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from public.categories where name = 'Colheita Fase1' and is_active = false;

do $$ begin
  insert into public.brands (name) values ('Marca do Vendedor');
  raise notice 'BU) FALHA DE SEGURANCA: vendedor criou marca';
exception when insufficient_privilege or others then
  raise notice 'BU) OK: vendedor bloqueado ao criar marca';
end $$;

do $$ declare afetadas int; begin
  update public.brands set name = 'Sequestrada' where name = 'Jacto Máquinas';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'BV) OK: alteracao de marca pelo vendedor ignorada';
  else raise notice 'BV) FALHA DE SEGURANCA: vendedor alterou % marca(s)', afetadas;
  end if;
end $$;

do $$ declare afetadas int; begin
  update public.categories set is_active = true where name = 'Colheita Fase1';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'BW) OK: desativacao/ativacao pelo vendedor ignorada';
  else raise notice 'BW) FALHA DE SEGURANCA: vendedor ativou % categoria(s)', afetadas;
  end if;
end $$;

do $$ declare afetadas int; begin
  update public.units set code = 'XX' where code = 'CX';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'BX) OK: alteracao de unidade pelo vendedor ignorada';
  else raise notice 'BX) FALHA DE SEGURANCA: vendedor alterou % unidade(s)', afetadas;
  end if;
end $$;

do $$ declare afetadas int; begin
  delete from public.units where code = 'LT';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'BY) OK: exclusao pelo vendedor ignorada';
  else raise notice 'BY) FALHA DE SEGURANCA: vendedor apagou % unidade(s)', afetadas;
  end if;
end $$;

-- Confirma que nada acima passou por baixo do pano.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select 'BZ) estado final integro' as teste,
       case when (select count(*) from public.brands where name = 'Jacto Máquinas') = 1
             and (select count(*) from public.brands where name = 'Sequestrada') = 0
             and (select count(*) from public.categories where name = 'Colheita Fase1' and is_active = false) = 1
             and (select count(*) from public.units where code = 'CX') = 1
             and (select count(*) from public.units where code = 'LT') = 1
            then 'OK: cadastros preservados' else 'FALHA' end as resultado;

reset role;
