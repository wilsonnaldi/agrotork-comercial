/**
 * Gera o SQL da carga de catálogo a partir de `dados/integrar_supabase.csv`.
 *
 *   node supabase/importacao/gerar-sql.mjs        # escreve carga_produtos.sql
 *
 * O arquivo gerado NÃO é executado por este script. Nada aqui fala com
 * banco. Gerar e aplicar são passos separados de propósito: o SQL fica
 * versionado, revisável em diff, e só roda quando alguém mandar.
 *
 * Se `validar.mjs` reprovar qualquer linha, nada é gerado.
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { lerCsv, validar, resumo } from "./validar.mjs";

const AQUI = dirname(fileURLToPath(import.meta.url));
const carga = lerCsv(join(AQUI, "dados", "integrar_supabase.csv"));
const trilha = lerCsv(join(AQUI, "dados", "rastreabilidade.csv"));
const { erros, marcasFaltando } = validar(carga, trilha);
if (erros.length) {
  console.error(`✖ ${erros.length} linha(s) rejeitada(s). Rode validar.mjs e corrija a planilha antes de gerar SQL.`);
  process.exit(1);
}

const txt = (v) => (v === "" || v === undefined || v === null ? "null" : `'${String(v).replace(/'/g, "''")}'`);
const num = (v) => (v === "" || v === undefined || v === null ? "null" : String(Number(v)));
const ncmValido = (v) => (/^\d{8}$/.test(v) ? v : "");

const linhas = carga.map((l) => [
  txt(l.CODIGO_SISTEMA), txt(l.NOME_PADRONIZADO), txt(l.CODIGO_FABRICANTE),
  txt(l.MARCA), txt(l.CATEGORIA_AGROTORK), txt(l.UNIDADE),
  num(l.CUSTO_A_VISTA), num(l.CUSTO_FATURADO), txt(l.VIGENCIA_INICIO),
  txt(l.OBSERVACAO), txt(l.SOURCE_TYPE), txt(l.SOURCE_BRAND), txt(l.SOURCE_CATALOG),
  txt(l.SOURCE_VERSION), txt(l.SOURCE_REFERENCE), txt(ncmValido(l.NCM)),
].join(", "));

const r = resumo(carga);
const marcas = marcasFaltando.map((m) => `    (${txt(m)})`).join(",\n");

const sql = `-- ============================================================
-- CARGA DE CATÁLOGO — ${r.total} PRODUTOS (DJI + JR SOLUÇÕES)
--
-- GERADO por supabase/importacao/gerar-sql.mjs a partir de
-- supabase/importacao/dados/integrar_supabase.csv. NÃO EDITE À MÃO:
-- corrija a planilha, reexporte o CSV e gere de novo.
--
-- NÃO É UMA MIGRATION. Migrations mudam o schema; isto insere dados
-- comerciais e roda quando a AGROTORK mandar, não no \`db push\`.
--
-- O QUE ESTE SCRIPT GARANTE
--   1. Transação única: ou entram os ${r.total}, ou não entra nenhum.
--   2. Idempotente: casa por upper(code). Rodar duas vezes não duplica.
--   3. Produto que JÁ EXISTE tem só o cadastro atualizado. Preço de
--      venda, sale_price_set_at e is_active NÃO são tocados — seriam
--      decisões comerciais sobrescritas por uma tabela de fabricante.
--   4. Produto NOVO entra com sale_price = 0, sale_price_set_at NULO
--      (preço nunca definido) e is_active = false.
--   5. manufacturer_code nunca fica com brand_id nulo: a marca que
--      faltar é criada aqui, antes, e a ausência vira erro.
--   6. Custo por condição: AVISTA e/ou FATURADO, uma linha cada.
--      PRECO_REVENDA_JR não é lido — duplicaria o custo à vista.
--   7. Relatório ao final, com o que entrou, o que foi atualizado e o
--      que ficou sem custo.
--
-- COMO RODAR (fora daqui, com autorização):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/importacao/carga_produtos.sql
-- ============================================================

begin;

-- ── 0. Marcas que a carga exige e o seed não tem ────────────
${marcasFaltando.length ? `insert into public.brands (name, sort_order)
select v.nome, 100 + row_number() over (order by v.nome)
from (values
${marcas}
) as v(nome)
where not exists (
  select 1 from public.brands b
   where upper(b.name) = upper(v.nome) and b.deleted_at is null
);` : "-- (nenhuma: todas as marcas da carga já existem no cadastro)"}

-- ── 1. A carga, tal como saiu da planilha ───────────────────
create temporary table _carga (
  code             text primary key,
  name             text not null,
  manufacturer_code text,
  marca            text,
  categoria        text,
  unidade          text not null,
  custo_avista     numeric(14,2),
  custo_faturado   numeric(14,2),
  vigencia         date not null,
  observacao       text,
  source_type      text not null,
  source_brand     text,
  source_catalog   text,
  source_version   text,
  source_reference text,
  ncm              text
) on commit drop;

insert into _carga values
${linhas.map((l) => `  (${l})`).join(",\n")};

-- ── 2. Recusa estrutural: nada entra com referência quebrada ─
do $$
declare
  v_n integer;
  v_lista text;
begin
  if (select count(*) from _carga) <> ${r.total} then
    raise exception 'A carga deveria ter ${r.total} linhas e tem %', (select count(*) from _carga);
  end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.unidade is null
      or not exists (select 1 from public.units u where upper(u.code) = upper(c.unidade));
  if v_n > 0 then raise exception 'Unidade inexistente em % linha(s): %', v_n, v_lista; end if;

  -- A trava que quebraria a carga inteira lá no meio.
  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.manufacturer_code is not null
     and not exists (select 1 from public.brands b
                      where upper(b.name) = upper(c.marca) and b.deleted_at is null);
  if v_n > 0 then
    raise exception 'Codigo de fabricante sem marca cadastrada em % linha(s): % — chk_products_manufacturer_brand recusaria', v_n, v_lista;
  end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.categoria is not null
     and not exists (select 1 from public.categories k
                      where k.name = c.categoria and k.deleted_at is null);
  if v_n > 0 then raise exception 'Categoria inexistente em % linha(s): %', v_n, v_lista; end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga where ncm is not null and ncm !~ '^[0-9]{8}$';
  if v_n > 0 then raise exception 'NCM fora do formato em % linha(s): %', v_n, v_lista; end if;

  if not exists (select 1 from public.price_conditions where upper(code) = 'AVISTA')
     or not exists (select 1 from public.price_conditions where upper(code) = 'FATURADO') then
    raise exception 'price_conditions sem AVISTA/FATURADO: aplique a migration 20260902120000 antes da carga';
  end if;
end $$;

-- ── 3. Produtos ─────────────────────────────────────────────
create temporary table _resultado (code text, acao text) on commit drop;

with resolvido as (
  select
    c.*,
    b.id as brand_id,
    k.id as category_id,
    u.id as unit_id
  from _carga c
  left join public.brands     b on upper(b.name) = upper(c.marca)   and b.deleted_at is null
  left join public.categories k on k.name        = c.categoria      and k.deleted_at is null
  join      public.units      u on upper(u.code) = upper(c.unidade)
),
gravado as (
  insert into public.products (
    code, name, manufacturer_code, brand_id, category_id, unit_id,
    sale_price, is_active, notes,
    source_type, source_brand, source_catalog, source_version,
    source_reference, source_imported_at, technical_data
  )
  select
    r.code, r.name, r.manufacturer_code, r.brand_id, r.category_id, r.unit_id,
    0,                       -- preço de venda ainda não definido…
    false,                   -- …e por isso o produto entra inativo
    r.observacao,
    r.source_type::public.product_source_type,
    r.source_brand, r.source_catalog, r.source_version,
    r.source_reference, now(),
    case when r.ncm is null then '{}'::jsonb else jsonb_build_object('ncm', r.ncm) end
  from resolvido r
  on conflict (upper(code)) where deleted_at is null
  do update set
    name              = excluded.name,
    manufacturer_code = excluded.manufacturer_code,
    brand_id          = excluded.brand_id,
    category_id       = excluded.category_id,
    unit_id           = excluded.unit_id,
    notes             = excluded.notes,
    source_type       = excluded.source_type,
    source_brand      = excluded.source_brand,
    source_catalog    = excluded.source_catalog,
    source_version    = excluded.source_version,
    source_reference  = excluded.source_reference,
    source_imported_at = excluded.source_imported_at,
    technical_data    = public.products.technical_data || excluded.technical_data
    -- sale_price, sale_price_set_at e is_active ficam como estão:
    -- tabela de fabricante não decide preço nem ativação.
  returning code, (xmax = 0) as inserido
)
insert into _resultado select code, case when inserido then 'inserido' else 'atualizado' end from gravado;

-- ── 4. Custo por condição ───────────────────────────────────
-- Uma linha por produto E condição. É exatamente isto que a PK antiga
-- de product_costs (em product_id) impedia.
insert into public.product_costs (
  product_id, condition_id, cost_price, valid_from,
  source_catalog, source_version, source_reference
)
select p.id, pc.id, v.valor, c.vigencia, c.source_catalog, c.source_version, c.source_reference
from _carga c
join public.products p on upper(p.code) = upper(c.code) and p.deleted_at is null
cross join lateral (values
  ('AVISTA',   c.custo_avista),
  ('FATURADO', c.custo_faturado)
) as v(cond, valor)
join public.price_conditions pc on upper(pc.code) = v.cond
where v.valor is not null
on conflict (product_id, condition_id) where valid_to is null
do update set
  cost_price       = excluded.cost_price,
  valid_from       = excluded.valid_from,
  source_catalog   = excluded.source_catalog,
  source_version   = excluded.source_version,
  source_reference = excluded.source_reference;

-- ── 5. Relatório ────────────────────────────────────────────
do $$
declare
  v_ins integer; v_upd integer; v_avista integer; v_fat integer; v_sem integer; v_ativos integer; v_precos integer;
begin
  select count(*) filter (where acao = 'inserido'),
         count(*) filter (where acao = 'atualizado')
    into v_ins, v_upd from _resultado;

  select count(*) filter (where upper(pc.code) = 'AVISTA'),
         count(*) filter (where upper(pc.code) = 'FATURADO')
    into v_avista, v_fat
    from public.product_costs c
    join public.price_conditions pc on pc.id = c.condition_id
    join public.products p on p.id = c.product_id
   where upper(p.code) in (select upper(code) from _carga) and c.valid_to is null;

  select count(*) into v_sem
    from _carga c join public.products p on upper(p.code) = upper(c.code)
   where not exists (select 1 from public.product_costs pk where pk.product_id = p.id);

  select count(*) filter (where p.is_active),
         count(*) filter (where p.sale_price_set_at is not null)
    into v_ativos, v_precos
    from _carga c join public.products p on upper(p.code) = upper(c.code);

  raise notice '──────────── RELATORIO DA CARGA ────────────';
  raise notice 'produtos inseridos.............. %', v_ins;
  raise notice 'produtos atualizados............ %', v_upd;
  raise notice 'linhas de custo AVISTA.......... %', v_avista;
  raise notice 'linhas de custo FATURADO........ %', v_fat;
  raise notice 'produtos sem nenhum custo....... %', v_sem;
  raise notice 'produtos ATIVOS apos a carga.... %  (esperado 0 numa base limpa)', v_ativos;
  raise notice 'produtos COM preco definido..... %  (esperado 0 numa base limpa)', v_precos;
  raise notice '────────────────────────────────────────────';

  if v_ins + v_upd <> ${r.total} then
    raise exception 'A carga gravou % produtos, e deveria gravar ${r.total}', v_ins + v_upd;
  end if;
end $$;

commit;
`;

writeFileSync(join(AQUI, "carga_produtos.sql"), sql);
console.log(`✔ carga_produtos.sql gerado — ${r.total} produtos, ${r.avista} custos à vista, ${r.faturado} faturados.`);
console.log(`  marcas criadas pelo script: ${marcasFaltando.join(", ") || "(nenhuma)"}`);
console.log("  NÃO foi executado em banco nenhum.");
