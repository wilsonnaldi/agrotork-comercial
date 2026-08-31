import "server-only";

import { createClient } from "@/lib/supabase/server";
import { dbValueToCents } from "@/lib/format/money";
import { assertColumns, toKitListRow, toProductListRow } from "@/types/db";
import type { Kit, KitItem, KitListRow, ProductListRow } from "@/types/db";
import { QUANTITY_SCALE, milliToDecimalString, type KitFilters, type ComponentSearch } from "./schema";
import {
  COMPONENT_SEARCH_LIMIT,
  KITS_PAGE_SIZE,
  type ComponentCandidate,
  type KitComposition,
  type KitItemView,
  type KitPage,
  type KitView,
} from "./types";

/**
 * Acesso a dados de Kits. ÚNICO lugar do módulo que fala com o Supabase.
 *
 * Também é a fronteira das unidades: dinheiro entra e sai em centavos,
 * quantidade em milésimos. Nada acima daqui lida com `numeric`.
 *
 * Composição é montada em duas consultas (itens + produtos) e unida em
 * memória, em vez de embed do PostgREST — assim a consulta continua
 * simples e o RLS de cada tabela é aplicado separadamente.
 */

function toMilli(value: number | string): number {
  return Math.round(Number(value) * QUANTITY_SCALE);
}

function toKitView(row: KitListRow): KitView {
  const { components_total, optional_total, suggested_price, discount_percent, ...rest } = row;
  return {
    ...rest,
    discount_percent: Number(discount_percent),
    components_total_cents: dbValueToCents(components_total) ?? 0,
    optional_total_cents: dbValueToCents(optional_total) ?? 0,
    suggested_price_cents: dbValueToCents(suggested_price) ?? 0,
  };
}

export async function findMany(filters: KitFilters): Promise<KitPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * KITS_PAGE_SIZE;

  let query = supabase.from("kits_with_price").select("*", { count: "exact" });

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(`code.ilike.${term},name.ilike.${term},description.ilike.${term}`);
  }

  const { data, count, error } = await query
    .order("code", { ascending: true })
    .range(from, from + KITS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map(toKitListRow).map(toKitView),
    total,
    page,
    pageSize: KITS_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / KITS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<KitView | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("kits_with_price").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? toKitView(toKitListRow(data)) : null;
}

/** Código é único entre kits não excluídos. Ignora o próprio na edição. */
export async function findByCode(code: string, exceptId?: string): Promise<Pick<Kit, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase.from("kits").select("id, name").ilike("code", code).is("deleted_at", null);
  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

type KitRecord = { code: string; name: string; description: string | null; is_active: boolean };

export async function insert(record: KitRecord, userId: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("kits")
    .insert({ ...record, created_by: userId, updated_by: userId })
    .select("id")
    .single();

  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, record: Partial<KitRecord>, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("kits")
    .update({ ...record, updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

// ── Composição ───────────────────────────────────────────────

/** Mapa de unidade -> aceita fração. A tabela é pequena; uma consulta basta. */
async function findFractionByUnit(): Promise<Record<string, boolean>> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("units").select("id, allows_fraction");
  if (error) throw new Error(error.message);

  const map: Record<string, boolean> = {};
  for (const unit of data ?? []) map[unit.id] = unit.allows_fraction;
  return map;
}

function toItemView(item: KitItem, product: ProductListRow, allowsFraction: boolean): KitItemView {
  const quantity_milli = toMilli(item.quantity);
  const sale_price_cents = dbValueToCents(product.sale_price) ?? 0;
  return {
    id: item.id,
    kit_id: item.kit_id,
    product_id: item.product_id,
    item_type: item.item_type,
    quantity_milli,
    sort_order: item.sort_order,
    product_code: product.code,
    product_name: product.name,
    manufacturer_code: product.manufacturer_code,
    brand_name: product.brand_name,
    unit_code: product.unit_code,
    unit_allows_fraction: allowsFraction,
    sale_price_cents,
    product_is_active: product.is_active,
    // Arredonda no fim, uma vez só: milésimos × centavos.
    line_total_cents: Math.round((quantity_milli * sale_price_cents) / QUANTITY_SCALE),
  };
}

export async function findComposition(kitId: string): Promise<KitComposition> {
  const supabase = await createClient();

  const { data: items, error } = await supabase
    .from("kit_items")
    .select("*")
    .eq("kit_id", kitId)
    .order("sort_order", { ascending: true });

  if (error) throw new Error(error.message);
  if (!items || items.length === 0) return { required: [], optional: [] };

  const [{ data: products, error: productsError }, fractionByUnit] = await Promise.all([
    supabase.from("products_list").select("*").in("id", items.map((item) => item.product_id)),
    findFractionByUnit(),
  ]);
  if (productsError) throw new Error(productsError.message);

  const byId = new Map(
    (products ?? []).map(toProductListRow).map((product) => [product.id, product] as const),
  );
  const views: KitItemView[] = [];
  for (const item of items) {
    const product = byId.get(item.product_id);
    // Produto sem linha visível (excluído logicamente) não some do kit:
    // a composição continua completa, com o que se sabe dele.
    if (!product) continue;
    views.push(toItemView(item, product, fractionByUnit[product.unit_id] ?? false));
  }

  return {
    required: views.filter((view) => view.item_type === "required"),
    optional: views.filter((view) => view.item_type === "optional"),
  };
}

export async function findItem(itemId: string): Promise<KitItem | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("kit_items").select("*").eq("id", itemId).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function findItemByProduct(kitId: string, productId: string): Promise<KitItem | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("kit_items")
    .select("*")
    .eq("kit_id", kitId)
    .eq("product_id", productId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insertItem(
  kitId: string,
  productId: string,
  quantityMilli: number,
  itemType: KitItem["item_type"],
  sortOrder: number,
): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("kit_items").insert({
    kit_id: kitId,
    product_id: productId,
    quantity: milliToDecimalString(quantityMilli),
    item_type: itemType,
    sort_order: sortOrder,
  });
  if (error) throw new Error(error.message);
}

export async function updateItem(
  itemId: string,
  patch: { quantityMilli?: number; itemType?: KitItem["item_type"] },
): Promise<void> {
  const supabase = await createClient();
  const record: { quantity?: string; item_type?: KitItem["item_type"] } = {};
  if (patch.quantityMilli !== undefined) record.quantity = milliToDecimalString(patch.quantityMilli);
  if (patch.itemType !== undefined) record.item_type = patch.itemType;

  const { error } = await supabase.from("kit_items").update(record).eq("id", itemId);
  if (error) throw new Error(error.message);
}

export async function deleteItem(itemId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("kit_items").delete().eq("id", itemId);
  if (error) throw new Error(error.message);
}

export async function nextSortOrder(kitId: string): Promise<number> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("kit_items")
    .select("sort_order")
    .eq("kit_id", kitId)
    .order("sort_order", { ascending: false })
    .limit(1);

  const last = data?.[0]?.sort_order;
  return typeof last === "number" ? last + 1 : 0;
}

// ── Busca de produtos para compor o kit ──────────────────────

/** Só produtos ATIVOS entram em associação nova. */
export async function searchComponents(
  kitId: string,
  filters: ComponentSearch,
): Promise<ComponentCandidate[]> {
  const supabase = await createClient();

  let query = supabase.from("products_list").select("*").eq("is_active", true);
  if (filters.brand) query = query.eq("brand_id", filters.brand);
  if (filters.category) query = query.eq("category_id", filters.category);
  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(
      `code.ilike.${term},manufacturer_code.ilike.${term},name.ilike.${term},brand_name.ilike.${term},category_name.ilike.${term}`,
    );
  }

  const [{ data, error }, { data: existing }, fractionByUnit] = await Promise.all([
    query.order("name", { ascending: true }).range(0, COMPONENT_SEARCH_LIMIT - 1),
    supabase.from("kit_items").select("product_id").eq("kit_id", kitId),
    findFractionByUnit(),
  ]);
  if (error) throw new Error(error.message);

  const inKit = new Set((existing ?? []).map((item) => item.product_id));

  return (data ?? []).map(toProductListRow).map((product) => ({
    id: product.id,
    code: product.code,
    name: product.name,
    manufacturer_code: product.manufacturer_code,
    brand_name: product.brand_name,
    unit_code: product.unit_code,
    unit_allows_fraction: fractionByUnit[product.unit_id] ?? false,
    sale_price_cents: dbValueToCents(product.sale_price) ?? 0,
    already_in_kit: inKit.has(product.id),
  }));
}

/** Produto informado existe, está ativo e aceita fração? */
export async function findProductForKit(productId: string): Promise<{
  id: string;
  name: string;
  code: string;
  is_active: boolean;
  allows_fraction: boolean;
} | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products_list")
    .select("id, name, code, is_active, unit_id")
    .eq("id", productId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) return null;

  // Projeção parcial de `products_list`: valem as mesmas garantias da view,
  // só que para as cinco colunas selecionadas.
  assertColumns(data, ["id", "name", "code", "is_active", "unit_id"] as const, "products_list");

  const fractionByUnit = await findFractionByUnit();
  return {
    id: data.id,
    name: data.name,
    code: data.code,
    is_active: data.is_active,
    allows_fraction: fractionByUnit[data.unit_id] ?? false,
  };
}

/** Quantos itens de orçamento apontam para este kit. Alimenta o aviso de histórico. */
export async function countQuoteUsage(kitId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("quote_items")
    .select("id", { count: "exact", head: true })
    .eq("kit_id", kitId);
  return count ?? 0;
}
