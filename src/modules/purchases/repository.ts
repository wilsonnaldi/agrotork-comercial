import "server-only";

import { createClient } from "@/lib/supabase/server";
import { toPurchaseListRow } from "@/types/db";
import type { InsertOf, Purchase, PurchaseItem, UpdateOf } from "@/types/db";
import { centsToDecimalString, dbValueToCents } from "@/lib/format/money";
import { milliToDecimalString } from "@/lib/format/quantity";
import type { PurchaseFilters, PurchaseInput, PurchaseItemInput } from "./schema";
import {
  PURCHASES_PAGE_SIZE,
  type PurchaseItemView,
  type PurchaseListItem,
  type PurchasePage,
  type PurchaseView,
} from "./types";

/**
 * Acesso a dados de Entrada de mercadoria. ÚNICO lugar do módulo que fala
 * com o Supabase.
 *
 * Totais NÃO são enviados daqui: quem soma `items_total` e `total` é o
 * gatilho do banco. Mandar o total calculado na tela seria abrir a porta
 * para os dois discordarem.
 */

const LIST_COLUMNS =
  "id, number, status, issue_date, received_date, invoice_number, items_total, total, created_at, updated_at, supplier_id, supplier_name, supplier_city, condition_name, items_count";

export async function findMany(filters: PurchaseFilters): Promise<PurchasePage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * PURCHASES_PAGE_SIZE;

  let query = supabase.from("purchases_list").select(LIST_COLUMNS, { count: "exact" });

  if (filters.status !== "all") query = query.eq("status", filters.status);
  if (filters.supplier) query = query.eq("supplier_id", filters.supplier);
  if (filters.q) {
    const termo = `%${filters.q}%`;
    query = query.or(`number.ilike.${termo},invoice_number.ilike.${termo},supplier_name.ilike.${termo}`);
  }

  const { data, count, error } = await query
    .order("issue_date", { ascending: false })
    .order("created_at", { ascending: false })
    .range(from, from + PURCHASES_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map((linha) => {
      const row = toPurchaseListRow(linha as never);
      const { items_total, total: totalNota, ...resto } = row;
      return {
        ...resto,
        items_total_cents: dbValueToCents(items_total) ?? 0,
        total_cents: dbValueToCents(totalNota) ?? 0,
      } satisfies PurchaseListItem;
    }),
    total,
    page,
    pageSize: PURCHASES_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / PURCHASES_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<PurchaseView | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("purchases")
    .select("*, suppliers(name), price_conditions(name)")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) return null;

  const bruto = data as unknown as Purchase & {
    suppliers: { name: string } | null;
    price_conditions: { name: string } | null;
  };

  return {
    id: bruto.id,
    number: bruto.number,
    status: bruto.status,
    supplier_id: bruto.supplier_id,
    supplier_name: bruto.suppliers?.name ?? "—",
    condition_id: bruto.condition_id,
    condition_name: bruto.price_conditions?.name ?? "—",
    invoice_number: bruto.invoice_number,
    invoice_series: bruto.invoice_series,
    invoice_key: bruto.invoice_key,
    issue_date: bruto.issue_date,
    received_date: bruto.received_date,
    freight_amount_cents: dbValueToCents(bruto.freight_amount) ?? 0,
    other_amount_cents: dbValueToCents(bruto.other_amount) ?? 0,
    discount_amount_cents: dbValueToCents(bruto.discount_amount) ?? 0,
    items_total_cents: dbValueToCents(bruto.items_total) ?? 0,
    total_cents: dbValueToCents(bruto.total) ?? 0,
    notes: bruto.notes,
    received_at: bruto.received_at,
    cancelled_at: bruto.cancelled_at,
    created_at: bruto.created_at,
    updated_at: bruto.updated_at,
  };
}

export async function findItems(purchaseId: string): Promise<PurchaseItemView[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("purchase_items")
    .select("*, products(code, name, units(code))")
    .eq("purchase_id", purchaseId)
    .order("sort_order", { ascending: true })
    .order("id", { ascending: true });

  if (error) throw new Error(error.message);

  return (data ?? []).map((linha) => {
    const bruto = linha as unknown as PurchaseItem & {
      products: { code: string; name: string; units: { code: string } | null } | null;
    };
    return {
      id: bruto.id,
      purchase_id: bruto.purchase_id,
      product_id: bruto.product_id,
      product_name: bruto.products?.name ?? "—",
      product_code: bruto.products?.code ?? "—",
      unit_code: bruto.products?.units?.code ?? null,
      quantity_milli: Math.round(Number(bruto.quantity) * 1000),
      unit_cost_cents: dbValueToCents(bruto.unit_cost) ?? 0,
      line_total_cents: dbValueToCents(bruto.line_total) ?? 0,
      freight_share_cents: dbValueToCents(bruto.freight_share) ?? 0,
      landed_cost_decimillis:
        bruto.landed_cost === null ? null : Math.round(Number(bruto.landed_cost) * 10000),
      previous_cost_cents: dbValueToCents(bruto.previous_cost),
      sort_order: bruto.sort_order,
      notes: bruto.notes,
    } satisfies PurchaseItemView;
  });
}

export async function insert(input: PurchaseInput, userId: string): Promise<string> {
  const supabase = await createClient();

  // `number`, `sequence_year` e `sequence_number` NÃO vão daqui: quem
  // numera é o gatilho, e mandar um número da tela criaria a chance de
  // dois usuários gravarem o mesmo.
  const registro = {
    supplier_id: input.supplier_id,
    condition_id: input.condition_id,
    invoice_number: input.invoice_number ?? null,
    invoice_series: input.invoice_series ?? null,
    invoice_key: input.invoice_key ?? null,
    issue_date: input.issue_date,
    freight_amount: centsToDecimalString(input.freight_amount_cents),
    other_amount: centsToDecimalString(input.other_amount_cents),
    discount_amount: centsToDecimalString(input.discount_amount_cents),
    notes: input.notes ?? null,
    created_by: userId,
    updated_by: userId,
  } as unknown as InsertOf<"purchases">;

  const { data, error } = await supabase.from("purchases").insert(registro).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, input: PurchaseInput, userId: string): Promise<void> {
  const supabase = await createClient();
  const registro = {
    supplier_id: input.supplier_id,
    condition_id: input.condition_id,
    invoice_number: input.invoice_number ?? null,
    invoice_series: input.invoice_series ?? null,
    invoice_key: input.invoice_key ?? null,
    issue_date: input.issue_date,
    freight_amount: centsToDecimalString(input.freight_amount_cents),
    other_amount: centsToDecimalString(input.other_amount_cents),
    discount_amount: centsToDecimalString(input.discount_amount_cents),
    notes: input.notes ?? null,
    updated_by: userId,
  } as unknown as UpdateOf<"purchases">;

  const { data, error } = await supabase.from("purchases").update(registro).eq("id", id).select("id");
  if (error) throw new Error(error.message);
  if ((data ?? []).length === 0) throw new Error("Sem permissão para alterar esta nota");
}

export async function addItem(purchaseId: string, input: PurchaseItemInput): Promise<void> {
  const supabase = await createClient();
  const registro = {
    purchase_id: purchaseId,
    product_id: input.product_id,
    quantity: milliToDecimalString(input.quantity_milli),
    unit_cost: centsToDecimalString(input.unit_cost_cents),
    notes: input.notes ?? null,
  } as unknown as InsertOf<"purchase_items">;

  const { error } = await supabase.from("purchase_items").insert(registro);
  if (error) throw new Error(error.message);
}

export async function removeItem(itemId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("purchase_items").delete().eq("id", itemId);
  if (error) throw new Error(error.message);
}

export async function receive(purchaseId: string): Promise<number> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("receive_purchase", { p_purchase_id: purchaseId });
  if (error) throw new Error(error.message);
  return (data as number) ?? 0;
}

export async function cancel(purchaseId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_purchase", { p_purchase_id: purchaseId });
  if (error) throw new Error(error.message);
}

/** Fornecedores ativos, para o seletor da nota. */
export async function supplierOptions(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("suppliers")
    .select("id, name")
    .is("deleted_at", null)
    .eq("is_active", true)
    .order("name", { ascending: true })
    .limit(500);

  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function conditionOptions(): Promise<{ id: string; name: string; is_default: boolean }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("price_conditions")
    .select("id, name, is_default")
    .eq("is_active", true)
    .order("sort_order", { ascending: true });

  if (error) throw new Error(error.message);
  return data ?? [];
}

/** Produtos ativos, para escolher o item da nota. */
export async function productOptions(
  termo?: string,
): Promise<{ id: string; code: string; name: string }[]> {
  const supabase = await createClient();
  let query = supabase
    .from("products")
    .select("id, code, name")
    .is("deleted_at", null)
    .eq("is_active", true);

  if (termo) {
    const like = `%${termo}%`;
    query = query.or(`name.ilike.${like},code.ilike.${like}`);
  }

  const { data, error } = await query.order("name", { ascending: true }).limit(50);
  if (error) throw new Error(error.message);
  return data ?? [];
}

// ── Importação de NF-e ──────────────────────────────────────

export async function findSupplierByDocument(
  document: string,
): Promise<{ id: string; name: string } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("suppliers")
    .select("id, name")
    .eq("document", document)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** O de-para que já existe deste fornecedor, mais o GTIN de cada produto. */
export async function knownSupplierProducts(supplierId: string): Promise<
  { supplier_code: string; product_id: string; product_code: string; product_name: string; gtin: string | null }[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("known_supplier_products", {
    p_supplier_id: supplierId,
  });
  if (error) throw new Error(error.message);
  return (data ?? []) as never;
}

/** Produtos com GTIN, para casar pelo código de barras da nota. */
export async function findProductsByGtin(
  gtins: string[],
): Promise<{ id: string; code: string; name: string; gtin: string | null }[]> {
  const unicos = [...new Set(gtins.filter(Boolean))];
  if (unicos.length === 0) return [];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products")
    .select("id, code, name, gtin")
    .in("gtin", unicos)
    .is("deleted_at", null);

  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function rememberSupplierProduct(
  supplierId: string,
  code: string,
  productId: string,
  description?: string | null,
): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("remember_supplier_product", {
    p_supplier_id: supplierId,
    p_code: code,
    p_product_id: productId,
    ...(description ? { p_description: description } : {}),
  });
  if (error) throw new Error(error.message);
}

export async function insertSupplierFromNfe(dados: {
  name: string;
  trade_name: string | null;
  document: string | null;
  state_registration: string | null;
  address: string | null;
  address_number: string | null;
  district: string | null;
  city: string | null;
  state: string | null;
  zip_code: string | null;
  phone: string | null;
}, userId: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("suppliers")
    .insert({ ...dados, created_by: userId, updated_by: userId } as never)
    .select("id")
    .single();

  if (error) throw new Error(error.message);
  return data.id;
}
