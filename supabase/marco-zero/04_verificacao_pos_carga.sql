-- ============================================================
-- MARCO ZERO · 4 de 4 — VERIFICAÇÃO PÓS-CARGA (SOMENTE LEITURA)
--
-- Roda depois de `supabase/importacao/carga_produtos.sql`.
-- Cada linha diz OK ou FALHA.
-- ============================================================

with e as (
  select
    (select count(*) from public.products)                                            as produtos,
    (select count(*) from public.products where is_active)                            as ativos,
    (select count(*) from public.products where sale_price_set_at is not null)         as com_preco,
    (select count(*) from public.products where sale_price <> 0)                       as venda_nao_zero,
    (select count(*) from public.product_costs)                                        as custos,
    (select count(*) from public.product_costs c join public.price_conditions p on p.id=c.condition_id where p.code='AVISTA')   as avista,
    (select count(*) from public.product_costs c join public.price_conditions p on p.id=c.condition_id where p.code='FATURADO') as faturado,
    (select count(*) from public.products where code like 'EXC-%')                     as excluidos,
    (select count(*) from public.products
      where source_type::text='price_list' and source_reference is not null and source_reference <> '') as com_trilha,
    (select count(*) from public.products p
      where p.manufacturer_code is not null and p.brand_id is null)                    as codfab_sem_marca,
    (select count(*) from public.products where technical_data ? 'ncm'
       and technical_data->>'ncm' !~ '^[0-9]{8}$')                                     as ncm_invalido,
    (select count(*) from public.products_list)                                        as linhas_da_view,
    (select count(*) from public.products p join public.product_costs c on c.product_id=p.id
      where p.sale_price > 0 and p.sale_price = c.cost_price)                          as venda_igual_custo,
    (select count(*) from public.customers)                                            as clientes,
    (select count(*) from public.quotes)                                               as orcamentos
)
select * from (values
  ('produtos da carga',                     (select produtos from e),        112),
  ('produtos ATIVOS',                       (select ativos from e),            0),
  ('produtos com preço de venda DEFINIDO',  (select com_preco from e),         0),
  ('produtos com sale_price diferente de 0',(select venda_nao_zero from e),    0),
  ('linhas de custo (112 + 74)',            (select custos from e),          186),
  ('custos AVISTA',                         (select avista from e),          112),
  ('custos FATURADO',                       (select faturado from e),         74),
  ('produtos EXC- (excluídos da planilha)', (select excluidos from e),         0),
  ('produtos com rastreabilidade',          (select com_trilha from e),      112),
  ('código de fabricante sem marca',        (select codfab_sem_marca from e),  0),
  ('NCM em formato inválido',               (select ncm_invalido from e),      0),
  ('linhas em products_list (sem duplicar)',(select linhas_da_view from e),  112),
  ('venda copiada do custo',                (select venda_igual_custo from e), 0),
  ('clientes',                              (select clientes from e),          0),
  ('orçamentos',                            (select orcamentos from e),        0)
) as v(verificacao, encontrado, esperado)
cross join lateral (select case when encontrado = esperado then 'OK' else 'FALHA' end as resultado) r;

\echo ''
\echo '── A MARCA JR FOI RESOLVIDA EM UMA SÓ ──'
select b.name, public.slugify(b.name) as slug,
       (select count(*) from public.products p where p.brand_id=b.id) as produtos,
       case when count(*) over () = 1 then 'OK: uma única marca' else 'FALHA: marca duplicada' end as veredito
from public.brands b where public.slugify(b.name) = 'jr-solucoes';

\echo ''
\echo '── DOIS PRODUTOS QUE PROVAM A CARGA ──'
select p.code, p.name,
       (select string_agg(pc.code||'='||c.cost_price, ' / ' order by pc.code)
          from public.product_costs c join public.price_conditions pc on pc.id=c.condition_id
         where c.product_id = p.id) as custos,
       coalesce(p.technical_data->>'ncm','(sem ncm)') as ncm
from public.products p where p.code in ('DJI-070','JR-033','JR-001') order by p.code;
