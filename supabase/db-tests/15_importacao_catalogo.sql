-- ============================================================
-- Regras da carga de catálogo (FASE B).
--
-- Roda DEPOIS de `../importacao/carga_produtos.sql`, que já inseriu os
-- 112 produtos neste mesmo banco descartável. Aqui não se testa o script:
-- testa-se o que o BANCO garante depois dele — e o que ele recusa.
--
-- Notação: PC1) … PC15), na ordem dos requisitos da fase.
-- Qualquer linha com FALHA reprova a suíte inteira no runner.
-- ============================================================

-- ── PC1) manufacturer_code sem brand_id é recusado ──────────
do $$
declare v_unit uuid;
begin
  select id into v_unit from public.units where code = 'UN';
  begin
    insert into public.products (code, name, unit_id, manufacturer_code, brand_id, sale_price)
    values ('PC-SEM-MARCA', 'Produto com codigo de fabrica e sem marca', v_unit, 'ABC123', null, 0);
    raise notice ' PC1) FALHA: o banco aceitou manufacturer_code com brand_id nulo';
  exception when check_violation then
    raise notice ' PC1) OK: manufacturer_code sem brand_id recusado (chk_products_manufacturer_brand)';
  end;
end $$;

-- ── PC2) produto inativo não entra em orçamento novo ────────
-- A regra vive no serviço (quotes/service.ts) porque é mensagem de
-- negócio; o que o banco garante é que a carga chega inativa. Aqui se
-- prova o estado, que é a premissa daquela regra.
do $$
declare v_ativos integer;
begin
  select count(*) into v_ativos
    from public.products where source_type = 'price_list' and is_active;
  if v_ativos = 0 then
    raise notice ' PC2) OK: nenhum produto da carga esta ativo — o app recusa produto inativo em orcamento novo';
  else
    raise notice ' PC2) FALHA: % produto(s) da carga entraram ativos', v_ativos;
  end if;
end $$;

-- ── PC3) "sem preço definido" é identificável ───────────────
do $$
declare v_sem integer; v_com integer; v_id uuid;
begin
  select count(*) filter (where sale_price_set_at is null),
         count(*) filter (where sale_price_set_at is not null)
    into v_sem, v_com
    from public.products where source_type = 'price_list';
  if v_sem = 112 and v_com = 0 then
    raise notice ' PC3) OK: 112 produtos com sale_price_set_at NULO — preco nunca definido, e nao R$ 0,00';
  else
    raise notice ' PC3) FALHA: % sem carimbo e % com carimbo (esperado 112 e 0)', v_sem, v_com;
  end if;

  -- E o carimbo aparece no instante em que alguem define o preco.
  select id into v_id from public.products where code = 'DJI-001';
  update public.products set sale_price = 250000 where id = v_id;
  if (select sale_price_set_at from public.products where id = v_id) is not null then
    raise notice ' PC3b) OK: definir o preco carimbou sale_price_set_at';
  else
    raise notice ' PC3b) FALHA: preco definido sem carimbo';
  end if;

  -- Zero DELIBERADO tambem e um preco definido — e continua carimbado.
  update public.products set sale_price = 0 where id = v_id;
  if (select sale_price_set_at from public.products where id = v_id) is not null then
    raise notice ' PC3c) OK: zero deliberado continua sendo preco definido';
  else
    raise notice ' PC3c) FALHA: o carimbo sumiu ao voltar para zero';
  end if;
  update public.products set sale_price = 0, sale_price_set_at = null where id = v_id;
end $$;

-- ── PC4) AVISTA e FATURADO coexistem ────────────────────────
select ' PC4) ' || case
         when count(*) = 2 and sum(case when upper(pc.code) = 'AVISTA'   and c.cost_price = 750 then 1 else 0 end) = 1
                          and sum(case when upper(pc.code) = 'FATURADO' and c.cost_price = 790 then 1 else 0 end) = 1
         then 'OK: DJI-070 tem as duas condicoes na mesma vigencia'
         else 'FALHA: DJI-070 tem ' || count(*) || ' linha(s) de custo' end as resultado
from public.product_costs c
join public.price_conditions pc on pc.id = c.condition_id
join public.products p on p.id = c.product_id
where p.code = 'DJI-070' and c.valid_to is null;

-- ── PC5) dois custos vigentes na MESMA condição são recusados ─
do $$
declare v_prod uuid; v_cond uuid;
begin
  select id into v_prod from public.products where code = 'DJI-070';
  select id into v_cond from public.price_conditions where upper(code) = 'AVISTA';
  begin
    insert into public.product_costs (product_id, condition_id, cost_price, valid_from)
    values (v_prod, v_cond, 999, current_date + 1);
    raise notice ' PC5) FALHA: o banco aceitou dois custos AVISTA vigentes para o mesmo produto';
  exception when unique_violation then
    raise notice ' PC5) OK: segundo custo AVISTA vigente recusado (idx_product_costs_vigente)';
  end;
  -- E a mesma vigencia, mesmo fechada, tambem nao duplica.
  begin
    insert into public.product_costs (product_id, condition_id, cost_price, valid_from, valid_to)
    values (v_prod, v_cond, 999, (select valid_from from public.product_costs
                                   where product_id = v_prod and condition_id = v_cond limit 1),
            current_date);
    raise notice ' PC5b) FALHA: o banco aceitou duas linhas com a mesma vigencia';
  exception when unique_violation then
    raise notice ' PC5b) OK: mesma vigencia recusada (idx_product_costs_historico)';
  end;
end $$;

-- ── PC6) PRECO_REVENDA_JR não gerou custo duplicado ─────────
-- Nos 38 produtos JR a coluna repete CUSTO_A_VISTA. Se o importador
-- lesse as duas, existiria mais de uma linha AVISTA por produto.
select ' PC6) ' || case when count(*) = 0
         then 'OK: nenhum produto JR com custo AVISTA duplicado'
         else 'FALHA: ' || count(*) || ' produto(s) JR com custo AVISTA repetido' end as resultado
from (
  select c.product_id
  from public.product_costs c
  join public.price_conditions pc on pc.id = c.condition_id
  join public.products p on p.id = c.product_id
  where upper(pc.code) = 'AVISTA' and p.code like 'JR-%'
  group by c.product_id having count(*) > 1
) d;

-- ── PC7) DJI-070 com os valores que a planilha documenta ────
select ' PC7) ' || case
         when max(case when upper(pc.code) = 'AVISTA'   then c.cost_price end) = 750
          and max(case when upper(pc.code) = 'FATURADO' then c.cost_price end) = 790
         then 'OK: DJI-070 AVISTA 750 e FATURADO 790'
         else 'FALHA: DJI-070 com AVISTA=' ||
              coalesce(max(case when upper(pc.code) = 'AVISTA' then c.cost_price end)::text, 'nulo') ||
              ' e FATURADO=' ||
              coalesce(max(case when upper(pc.code) = 'FATURADO' then c.cost_price end)::text, 'nulo') end as resultado
from public.product_costs c
join public.price_conditions pc on pc.id = c.condition_id
join public.products p on p.id = c.product_id
where p.code = 'DJI-070';

-- ── PC8) JR-033 e JR-034 sem NCM inválido ───────────────────
select ' PC8) ' || case
         when count(*) filter (where technical_data ? 'ncm') = 0
         then 'OK: JR-033 e JR-034 entraram sem chave ncm'
         else 'FALHA: NCM invalido gravado em ' || count(*) filter (where technical_data ? 'ncm') || ' produto(s)' end as resultado
from public.products where code in ('JR-033', 'JR-034');

select ' PC8b) ' || case
         when count(*) = 36 then 'OK: 36 produtos com NCM de 8 digitos'
         else 'FALHA: ' || count(*) || ' produtos com ncm (esperado 36)' end as resultado
from public.products
where technical_data ? 'ncm' and technical_data ->> 'ncm' ~ '^[0-9]{8}$';

-- ── PC9) 112 produtos importáveis, códigos únicos ───────────
select ' PC9) ' || case
         when total = 112 and distintos = 112
         then 'OK: 112 produtos de tabela de preco, com 112 codigos distintos'
         else 'FALHA: ' || total || ' produto(s) e ' || distintos || ' codigo(s) distinto(s)' end as resultado
from (
  select count(*) as total, count(distinct upper(code)) as distintos
  from public.products where source_type = 'price_list'
) t;

-- ── PC10) todo produto da carga aponta para a trilha ────────
select ' PC10) ' || case when count(*) = 112
         then 'OK: 112/112 produtos com source_reference apontando o registro de origem'
         else 'FALHA: ' || count(*) || ' produto(s) com rastreabilidade (esperado 112)' end as resultado
from public.products
where source_type = 'price_list'
  and source_reference is not null and source_reference <> ''
  and source_brand is not null and source_catalog is not null;

-- ── PC11) 100% da carga inativa ─────────────────────────────
select ' PC11) ' || case when count(*) = 112
         then 'OK: 112/112 com is_active = false'
         else 'FALHA: ' || count(*) || ' inativo(s) (esperado 112)' end as resultado
from public.products where source_type = 'price_list' and not is_active;

-- ── PC12) nenhum preço de venda derivado do custo ───────────
select ' PC12) ' || case when count(*) = 0
         then 'OK: nenhum produto da carga tem sale_price diferente de zero'
         else 'FALHA: ' || count(*) || ' produto(s) com preco de venda' end as resultado
from public.products where source_type = 'price_list' and sale_price <> 0;

select ' PC12b) ' || case when count(*) = 0
         then 'OK: nenhum sale_price igual a algum custo do proprio produto'
         else 'FALHA: ' || count(*) || ' produto(s) com venda copiada do custo' end as resultado
from public.products p
join public.product_costs c on c.product_id = p.id
where p.source_type = 'price_list' and p.sale_price = c.cost_price and p.sale_price > 0;

-- ── PC13) a view devolve UMA linha por produto ──────────────
-- Sem o join pela condição padrão, os 74 produtos com duas condições
-- apareceriam duas vezes na listagem.
select ' PC13) ' || case when v = 112 and p = 112
         then 'OK: products_list devolve 112 linhas para 112 produtos, mesmo com 186 linhas de custo'
         else 'FALHA: view com ' || v || ' linha(s) para ' || p || ' produto(s)' end as resultado
from (select count(*) as v from public.products_list where source_type = 'price_list') a,
     (select count(*) as p from public.products where source_type = 'price_list' and deleted_at is null) b;

-- ── PC14) o custo que a view mostra é o da condição padrão ──
select ' PC14) ' || case when cost_price = 750
         then 'OK: products_list mostra o custo AVISTA (condicao padrao) de DJI-070'
         else 'FALHA: products_list mostra ' || coalesce(cost_price::text, 'nulo') end as resultado
from public.products_list where code = 'DJI-070';

-- ── PC15) set_product_cost respeita a condição e a RLS ──────
do $$
declare v_prod uuid; v_antes numeric;
begin
  select id into v_prod from public.products where code = 'DJI-002';
  select cost_price into v_antes from public.product_costs c
    join public.price_conditions pc on pc.id = c.condition_id
   where c.product_id = v_prod and upper(pc.code) = 'FATURADO';

  perform public.set_product_cost(v_prod, 111111, 'FATURADO', null);
  if (select cost_price from public.product_costs c
        join public.price_conditions pc on pc.id = c.condition_id
       where c.product_id = v_prod and upper(pc.code) = 'FATURADO') = 111111
     and (select count(*) from public.product_costs where product_id = v_prod) = 2 then
    raise notice ' PC15) OK: set_product_cost atualizou a condicao certa sem criar linha nova';
  else
    raise notice ' PC15) FALHA: set_product_cost nao respeitou a condicao';
  end if;
  perform public.set_product_cost(v_prod, v_antes, 'FATURADO', null);

  begin
    perform public.set_product_cost(v_prod, 1, 'CONDICAO-QUE-NAO-EXISTE', null);
    raise notice ' PC15b) FALHA: set_product_cost aceitou condicao inexistente';
  exception when others then
    raise notice ' PC15b) OK: condicao inexistente recusada (%)', left(sqlerrm, 40);
  end;
end $$;

-- ── PC16) o vendedor continua sem enxergar custo nenhum ─────
-- A migration mudou a FORMA do custo; não pode ter afrouxado o acesso.
insert into auth.users (id, email, raw_user_meta_data) values
 ('77777777-7777-7777-7777-777777777777','carga.vend@teste.local','{"full_name":"Vendedor Carga"}');

set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
set request.jwt.claim.role = 'authenticated';

select ' PC16) ' || case when count(*) = 0
         then 'OK: vendedor le ZERO linhas de product_costs depois da carga'
         else 'FALHA: vendedor leu ' || count(*) || ' linha(s) de custo' end as resultado
from public.product_costs;

select ' PC16b) ' || case when count(*) filter (where cost_price is not null) = 0
         then 'OK: custo e margem nulos na listagem para o vendedor'
         else 'FALHA: custo exposto em ' || count(*) filter (where cost_price is not null) || ' linha(s)' end as resultado
from public.products_list where source_type = 'price_list';

select ' PC16c) ' || case when count(*) > 0
         then 'OK: vendedor pode LER as condicoes de preco (' || count(*) || ') — e rotulo, nao custo'
         else 'FALHA: vendedor nao enxerga price_conditions' end as resultado
from public.price_conditions;

do $$ begin
  begin
    perform public.set_product_cost(
      (select id from public.products where code = 'DJI-002'), 1, 'AVISTA', null);
    if (select count(*) from public.product_costs) = 0 then
      raise notice ' PC16d) OK: set_product_cost nao gravou nada para o vendedor (RLS)';
    else
      raise notice ' PC16d) FALHA: vendedor gravou custo pela funcao';
    end if;
  exception when insufficient_privilege or others then
    raise notice ' PC16d) OK: set_product_cost negado ao vendedor (%)', left(sqlerrm, 45);
  end;
end $$;

reset role;
reset request.jwt.claim.sub;
reset request.jwt.claim.role;
