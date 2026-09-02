import "server-only";

import { createClient } from "@/lib/supabase/server";
import { centsToDecimalString, dbValueToCents } from "@/lib/format/money";
import { toProductListRow } from "@/types/db";
import type { Product, ProductListRow } from "@/types/db";
import type { ProductFilters } from "./schema";
import { PRODUCTS_PAGE_SIZE, type CatalogOptions, type ProductPage, type ProductView } from "./types";

/**
 * Acesso a dados de Produtos. ÚNICO lugar do módulo que fala com o Supabase.
 *
 * Também é a fronteira do dinheiro: sai daqui em centavos inteiros e entra
 * como string decimal. Nada acima deste arquivo lida com `numeric`.
 */

const SORT_COLUMNS: Record<ProductFilters["sort"], { column: string; ascending: boolean }> = {
  name: { column: "name", ascending: true },
  code: { column: "code", ascending: true },
  price: { column: "sale_price", ascending: false },
  recent: { column: "created_at", ascending: false },
};

function toView(row: ProductListRow): ProductView {
  const { sale_price, cost_price, margin_percent, ...rest } = row;
  return {
    ...rest,
    sale_price_cents: dbValueToCents(sale_price) ?? 0,
    cost_price_cents: dbValueToCents(cost_price),
    margin_percent: margin_percent === null ? null : Number(margin_percent),
  };
}

export async function findMany(filters: ProductFilters): Promise<ProductPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * PRODUCTS_PAGE_SIZE;

  let query = supabase.from("products_list").select("*", { count: "exact" });

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.brand) query = query.eq("brand_id", filters.brand);
  if (filters.category) query = query.eq("category_id", filters.category);
  if (filters.unit) query = query.eq("unit_id", filters.unit);

  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(
      `code.ilike.${term},manufacturer_code.ilike.${term},name.ilike.${term},description.ilike.${term}`,
    );
  }

  const sort = SORT_COLUMNS[filters.sort];
  const { data, count, error } = await query
    .order(sort.column, { ascending: sort.ascending })
    .range(from, from + PRODUCTS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map(toProductListRow).map(toView),
    total,
    page,
    pageSize: PRODUCTS_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / PRODUCTS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<ProductView | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("products_list").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? toView(toProductListRow(data)) : null;
}

/**
 * Checa unicidade do código do fabricante **dentro da marca**.
 * Dois fabricantes podem usar o mesmo código; o mesmo fabricante, não.
 */
export async function findByManufacturerCode(
  brandId: string,
  manufacturerCode: string,
  exceptId?: string,
): Promise<Pick<Product, "id" | "name" | "code"> | null> {
  const supabase = await createClient();
  let query = supabase
    .from("products")
    .select("id, name, code")
    .eq("brand_id", brandId)
    .eq("manufacturer_code", manufacturerCode.toUpperCase())
    .is("deleted_at", null);

  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

/** Checa unicidade do código. Ignora o próprio registro na edição. */
export async function findByCode(code: string, exceptId?: string): Promise<Pick<Product, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase
    .from("products")
    .select("id, name")
    .eq("code", code.toUpperCase())
    .is("deleted_at", null);

  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

type ProductRecord = {
  code: string;
  manufacturer_code: string | null;
  name: string;
  description: string | null;
  category_id: string | null;
  brand_id: string | null;
  unit_id: string;
  sale_price_cents: number;
  image_url: string | null;
  notes: string | null;
  is_active: boolean;
};

function toRow(record: ProductRecord, userId: string) {
  const { sale_price_cents, ...rest } = record;
  return { ...rest, sale_price: centsToDecimalString(sale_price_cents), updated_by: userId };
}

export async function insert(record: ProductRecord, userId: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products")
    .insert({ ...toRow(record, userId), created_by: userId })
    .select("id")
    .single();

  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, record: ProductRecord, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("products").update(toRow(record, userId)).eq("id", id);
  if (error) throw new Error(error.message);
}

/**
 * Grava o custo na tabela protegida. Se o usuário não for administrador,
 * o RLS recusa — não existe caminho de aplicação que contorne isso.
 *
 * Passa por `set_product_cost()` e não por `upsert` porque desde a
 * migration 20260902120000 a unicidade do custo vigente é um índice
 * PARCIAL (`where valid_to is null`), e o PostgREST não sabe inferir
 * índice parcial em `onConflict`. A função é SECURITY INVOKER: quem
 * autoriza continua sendo a RLS de `product_costs`, não a função.
 *
 * `p_condition_code` fica omitido de propósito — a aplicação ainda
 * trabalha com um único custo, que é o da condição padrão (AVISTA).
 */
export async function upsertCost(productId: string, costCents: number, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_product_cost", {
    p_product_id: productId,
    p_cost_price: centsToDecimalString(costCents),
    p_updated_by: userId,
  });
  if (error) throw new Error(error.message);
}

export async function setActive(id: string, isActive: boolean, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("products")
    .update({ is_active: isActive, updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

/** Marcas, categorias e unidades ativas — para filtros e formulário. */
export async function findCatalogOptions(): Promise<CatalogOptions> {
  const supabase = await createClient();

  const [brands, categories, units] = await Promise.all([
    supabase.from("brands").select("id, name").eq("is_active", true).order("name"),
    supabase.from("categories").select("id, name").eq("is_active", true).order("name"),
    supabase.from("units").select("id, code, name").eq("is_active", true).order("sort_order"),
  ]);

  return {
    brands: brands.data ?? [],
    categories: categories.data ?? [],
    units: units.data ?? [],
  };
}

/**
 * Confere se marca, categoria e unidade informadas estão ativas.
 * Só é chamado para as referências que MUDARAM: um produto antigo
 * continua vinculado ao cadastro que já usava, mesmo desativado.
 */
export async function checkReferencesActive(refs: {
  brandId?: string | null;
  categoryId?: string | null;
  unitId?: string | null;
}): Promise<{ brand: boolean; category: boolean; unit: boolean }> {
  const supabase = await createClient();

  const [brand, category, unit] = await Promise.all([
    refs.brandId
      ? supabase.from("brands").select("is_active").eq("id", refs.brandId).maybeSingle()
      : null,
    refs.categoryId
      ? supabase.from("categories").select("is_active").eq("id", refs.categoryId).maybeSingle()
      : null,
    refs.unitId ? supabase.from("units").select("is_active").eq("id", refs.unitId).maybeSingle() : null,
  ]);

  return {
    brand: brand ? brand.data?.is_active === true : true,
    category: category ? category.data?.is_active === true : true,
    unit: unit ? unit.data?.is_active === true : true,
  };
}

/**
 * Dados comerciais do produto para VENDA — o que um orçamento precisa
 * congelar. Inclui `allows_fraction`, que a view `products_list` não
 * traz porque pertence à unidade.
 */
export async function findForSale(productId: string): Promise<{
  id: string;
  code: string;
  name: string;
  description: string | null;
  brand_name: string | null;
  unit_code: string | null;
  allows_fraction: boolean;
  sale_price_cents: number;
  image_url: string | null;
  is_active: boolean;
} | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products_list")
    .select("*")
    .eq("id", productId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) return null;

  const product = toProductListRow(data);

  const { data: unit } = await supabase
    .from("units")
    .select("allows_fraction")
    .eq("id", product.unit_id)
    .maybeSingle();

  return {
    id: product.id,
    code: product.code,
    name: product.name,
    description: product.description,
    brand_name: product.brand_name,
    unit_code: product.unit_code,
    allows_fraction: unit?.allows_fraction === true,
    sale_price_cents: dbValueToCents(product.sale_price) ?? 0,
    image_url: product.image_url,
    is_active: product.is_active,
  };
}

/** Quantos kits usam este produto. Alimenta o aviso ao desativar. */
export async function countKitUsage(productId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("kit_items")
    .select("id", { count: "exact", head: true })
    .eq("product_id", productId);
  return count ?? 0;
}
