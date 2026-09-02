-- ============================================================
-- MARCO ZERO · 1 de 4 — INVENTÁRIO (SOMENTE LEITURA)
--
-- Nenhum DELETE, UPDATE, INSERT, TRUNCATE ou DROP. Pode rodar em
-- produção a qualquer momento. É a fotografia que os guards de
-- `02_limpeza.sql` esperam encontrar.
--
--   psql "$DATABASE_URL" -f supabase/marco-zero/01_inventario.sql
-- ============================================================

\echo '── CONTAGENS ──'
select 'app_settings' t, count(*) n from public.app_settings
union all select 'audit_log', count(*) from public.audit_log
union all select 'brands', count(*) from public.brands
union all select 'categories', count(*) from public.categories
union all select 'customers', count(*) from public.customers
union all select 'kit_items', count(*) from public.kit_items
union all select 'kits', count(*) from public.kits
union all select 'price_conditions', count(*) from public.price_conditions
union all select 'product_costs', count(*) from public.product_costs
union all select 'products', count(*) from public.products
union all select 'profiles', count(*) from public.profiles
union all select 'quote_items', count(*) from public.quote_items
union all select 'quote_sequences', count(*) from public.quote_sequences
union all select 'quote_share_tokens', count(*) from public.quote_share_tokens
union all select 'quotes', count(*) from public.quotes
union all select 'units', count(*) from public.units
order by 1;

\echo '── PRODUTOS POR PROCEDÊNCIA ──'
select coalesce(source_catalog, '(sem catálogo)') as catalogo,
       source_type::text,
       count(*) as produtos,
       count(*) filter (where is_active) as ativos,
       count(*) filter (where sale_price_set_at is not null) as com_preco_definido,
       min(created_at)::date as primeiro,
       max(created_at)::date as ultimo
from public.products
group by 1, 2 order by 3 desc;

\echo '── CUSTOS POR CONDIÇÃO ──'
select pc.code as condicao, count(*) as linhas,
       count(*) filter (where c.valid_to is null) as vigentes
from public.product_costs c join public.price_conditions pc on pc.id = c.condition_id
group by 1 order by 1;

\echo '── CADASTROS DE APOIO: SEED × ACRESCENTADO ──'
select 'brand' tipo, name, created_at::date as criado,
       case when name in ('AGROTORK','DJI','KUHN','BALDAN','ARAG','MAGNOJET','TRIMBLE','AGRES')
            then 'SEED' else 'ACRESCENTADO' end as origem,
       (select count(*) from public.products p where p.brand_id = b.id) as produtos
from public.brands b
union all
select 'category', name, created_at::date,
       case when name in ('Implementos','Peças','Pulverização','Tecnologia',
                          'Agricultura de Precisão','Serviços','Acessórios')
            then 'SEED' else 'ACRESCENTADO' end,
       (select count(*) from public.products p where p.category_id = k.id)
from public.categories k
order by 1, 4 desc, 2;

\echo '── DADOS COMERCIAIS ──'
select q.number, q.status::text, q.total, c.name as cliente,
       p.email as vendedor, q.created_at::date as criado,
       (select count(*) from public.quote_items i where i.quote_id = q.id) as itens,
       (select count(*) from public.quote_share_tokens t where t.quote_id = q.id) as links
from public.quotes q
left join public.customers c on c.id = q.customer_id
left join public.profiles  p on p.id = q.owner_id
order by q.number;

\echo '── QUEM SOBREVIVE AO MARCO ZERO ──'
select 'perfil' o, email as detalhe, role::text as info, is_active::text as ativo from public.profiles
union all
select 'empresa', value->>'legal_name', value->>'document', '' from public.app_settings where key='company'
union all
select 'sequência', year::text, last_number::text, '' from public.quote_sequences
union all
select 'storage', bucket_id, count(*)::text, '' from storage.objects group by bucket_id;

\echo '── A TRAVA QUE BLOQUEIA A CARGA (marca com acento) ──'
select b.name as marca_no_banco,
       'JR SOLUCOES' as marca_no_csv,
       upper(b.name) = upper('JR SOLUCOES') as o_importador_casaria,
       public.slugify(b.name) = public.slugify('JR SOLUCOES') as o_slug_colide,
       (select count(*) from public.products p where p.brand_id = b.id) as produtos_na_marca
from public.brands b where public.slugify(b.name) = 'jr-solucoes';
