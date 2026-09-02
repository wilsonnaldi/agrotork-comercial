-- ============================================================
-- MARCO ZERO · 3 de 4 — VERIFICAÇÃO PÓS-LIMPEZA (SOMENTE LEITURA)
--
-- Roda logo depois de `02_limpeza.sql`. Cada linha diz OK ou FALHA.
-- Se qualquer linha disser FALHA, NÃO execute a carga.
-- ============================================================

with e as (
  select
    (select count(*) from public.products)            as produtos,
    (select count(*) from public.product_costs)       as custos,
    (select count(*) from public.customers)           as clientes,
    (select count(*) from public.quotes)              as orcamentos,
    (select count(*) from public.quote_items)         as itens,
    (select count(*) from public.quote_share_tokens)  as links,
    (select count(*) from public.kits)                as kits,
    (select count(*) from public.kit_items)           as kit_itens,
    (select count(*) from public.units)               as unidades,
    (select count(*) from public.categories)          as categorias,
    (select count(*) from public.brands)              as marcas,
    (select count(*) from public.price_conditions)    as condicoes,
    (select count(*) from public.profiles where role='admin' and is_active) as admins,
    (select count(*) from public.app_settings)        as configuracoes,
    (select count(*) from public.audit_log)           as auditoria,
    (select coalesce(max(last_number),-1) from public.quote_sequences) as sequencia,
    (select count(*) from supabase_migrations.schema_migrations)       as migrations
)
select * from (values
  ('produtos comerciais',              (select produtos from e),      0),
  ('custos de produto',                (select custos from e),        0),
  ('clientes',                         (select clientes from e),      0),
  ('orçamentos',                       (select orcamentos from e),    0),
  ('itens de orçamento',               (select itens from e),         0),
  ('links de compartilhamento',        (select links from e),         0),
  ('kits',                             (select kits from e),          0),
  ('itens de kit',                     (select kit_itens from e),     0),
  ('unidades (seed)',                  (select unidades from e),      9),
  ('categorias (seed)',                (select categorias from e),    7),
  ('marcas',                           (select marcas from e),       10),
  ('condições de preço',               (select condicoes from e),     2),
  ('administradores ativos',           (select admins from e),        1),
  ('chaves de configuração',           (select configuracoes from e), 2),
  ('numeração de orçamento zerada',    (select sequencia from e),     0),
  ('migrations aplicadas',             (select migrations from e),   38)
) as v(verificacao, encontrado, esperado)
cross join lateral (select case when encontrado = esperado then 'OK' else 'FALHA' end as resultado) r;

\echo ''
\echo '── O QUE TEM DE CONTINUAR EXISTINDO ──'
select 'administrador' o, email as valor, role::text as detalhe from public.profiles where role='admin'
union all
select 'empresa', value->>'legal_name', value->>'document' from public.app_settings where key='company'
union all
select 'condição', code, name from public.price_conditions
union all
select 'marca', name, public.slugify(name) from public.brands
order by 1, 2;

\echo ''
\echo '── A TRILHA REGISTROU A LIMPEZA ──'
-- audit_log é append-only por trigger: a limpeza não some do histórico.
select operation, entity_type, count(*) as eventos
from public.audit_log
where occurred_at >= now() - interval '1 hour'
group by 1,2 order by 3 desc;

\echo ''
\echo '── PRÉ-REQUISITO DA CARGA: a marca precisa CASAR com o CSV ──'
select b.name as marca_no_banco,
       case when exists (
              select 1 from public.brands x
               where upper(x.name) = upper('JR SOLUCOES') and x.deleted_at is null)
            then 'OK: a carga vai reaproveitar a marca'
            when public.slugify(b.name) = 'jr-solucoes'
            then 'FALHA: a carga vai tentar CRIAR "JR SOLUCOES" e o slug jr-solucoes ja existe — a transacao aborta'
            else 'OK' end as veredito
from public.brands b where public.slugify(b.name) = 'jr-solucoes'
union all
select '(nenhuma marca jr-solucoes)', 'OK: a carga vai criar a marca'
where not exists (select 1 from public.brands where public.slugify(name)='jr-solucoes');
