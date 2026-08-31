import "server-only";

import { createClient } from "@/lib/supabase/server";
import { centsToDecimalString, dbValueToCents } from "@/lib/format/money";
import { dbValueToMilli, milliToDecimalString } from "@/lib/format/quantity";
import { toQuoteListRow } from "@/types/db";
import type { ItemKind, Quote, QuoteItem, QuoteListRow, QuoteStatus } from "@/types/db";
import { kitComponentsSnapshotSchema, type QuoteFilters } from "./schema";
import {
  QUOTES_PAGE_SIZE,
  type KitComponentSnapshot,
  type QuoteItemView,
  type QuotePage,
  type QuoteView,
} from "./types";

/**
 * Acesso a dados de Orçamentos. ÚNICO lugar do módulo que fala com o Supabase.
 *
 * Duas coisas que este arquivo NÃO faz, de propósito:
 *
 *  1. não calcula `subtotal` nem `total` — quem calcula é o banco, por
 *     trigger (`recalculate_quote_totals`), a cada mudança de item ou de
 *     desconto. Não existe caminho pelo qual o navegador decida preço.
 *  2. não lê `product_costs`. O custo não entra em orçamento nesta fase.
 */

const SORT_COLUMNS: Record<QuoteFilters["sort"], { column: string; ascending: boolean }> = {
  recent: { column: "created_at", ascending: false },
  number: { column: "number", ascending: false },
  total: { column: "total", ascending: false },
  customer: { column: "customer_name", ascending: true },
};

/** `date` chega como 'YYYY-MM-DD'; qualquer sufixo de hora é descartado. */
function toDateOnly(value: string | null): string | null {
  return value ? value.slice(0, 10) : null;
}

function toListItem(row: QuoteListRow) {
  const { subtotal, total, ...rest } = row;
  return {
    ...rest,
    subtotal_cents: dbValueToCents(subtotal) ?? 0,
    total_cents: dbValueToCents(total) ?? 0,
  };
}

export async function findMany(filters: QuoteFilters): Promise<QuotePage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * QUOTES_PAGE_SIZE;

  // O RLS já limita o vendedor aos próprios orçamentos; o filtro por
  // vendedor abaixo é conveniência do administrador.
  let query = supabase.from("quotes_list").select("*", { count: "exact" });

  if (filters.status !== "all") query = query.eq("status", filters.status);
  if (filters.customer) query = query.eq("customer_id", filters.customer);
  if (filters.owner) query = query.eq("owner_id", filters.owner);
  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(`number.ilike.${term},customer_name.ilike.${term}`);
  }

  const sort = SORT_COLUMNS[filters.sort];
  const { data, count, error } = await query
    .order(sort.column, { ascending: sort.ascending })
    .range(from, from + QUOTES_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map(toQuoteListRow).map(toListItem),
    total,
    page,
    pageSize: QUOTES_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / QUOTES_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<QuoteView | null> {
  const supabase = await createClient();

  const { data: quote, error } = await supabase.from("quotes").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(error.message);
  if (!quote || quote.deleted_at) return null;

  const [{ data: customer }, { data: owner }] = await Promise.all([
    supabase
      .from("customers")
      .select("name, city, document")
      .eq("id", quote.customer_id)
      .maybeSingle(),
    supabase.from("profiles").select("full_name").eq("id", quote.owner_id).maybeSingle(),
  ]);

  return {
    id: quote.id,
    number: quote.number,
    status: quote.status,
    customer_id: quote.customer_id,
    customer_name: customer?.name ?? "—",
    customer_city: customer?.city ?? null,
    customer_document: customer?.document ?? null,
    owner_id: quote.owner_id,
    owner_name: owner?.full_name ?? "—",
    issue_date: toDateOnly(quote.issue_date) ?? quote.issue_date,
    valid_until: toDateOnly(quote.valid_until),
    payment_terms: quote.payment_terms,
    delivery_terms: quote.delivery_terms,
    notes: quote.notes,
    internal_notes: quote.internal_notes,
    discount_percent: Number(quote.discount_percent),
    discount_amount_cents: dbValueToCents(quote.discount_amount) ?? 0,
    shipping_amount_cents: dbValueToCents(quote.shipping_amount) ?? 0,
    subtotal_cents: dbValueToCents(quote.subtotal) ?? 0,
    total_cents: dbValueToCents(quote.total) ?? 0,
    sent_at: quote.sent_at,
    approved_at: quote.approved_at,
    rejected_at: quote.rejected_at,
    created_at: quote.created_at,
    updated_at: quote.updated_at,
  };
}

/**
 * Lê `components_snapshot` conferindo o formato. `null` quando a coluna
 * está vazia (item que não é kit) ou quando o conteúdo não bate com o
 * formato esperado — melhor mostrar o item sem composição do que montar
 * um PDF com campo indefinido.
 */
function parseComponentsSnapshot(value: QuoteItem["components_snapshot"]): KitComponentSnapshot[] | null {
  if (value === null || value === undefined) return null;
  const parsed = kitComponentsSnapshotSchema.safeParse(value);
  return parsed.success ? parsed.data : null;
}

function toItemView(row: QuoteItem): QuoteItemView {
  return {
    id: row.id,
    quote_id: row.quote_id,
    kind: row.kind,
    product_id: row.product_id,
    kit_id: row.kit_id,
    code_snapshot: row.code_snapshot,
    name_snapshot: row.name_snapshot,
    description_snapshot: row.description_snapshot,
    unit_snapshot: row.unit_snapshot,
    brand_snapshot: row.brand_snapshot,
    // O snapshot é lido como veio; nada é completado com o cadastro atual.
    // A conferência é de FORMATO, não de conteúdo: preço e nome antigos
    // continuam exatamente como foram congelados.
    components: parseComponentsSnapshot(row.components_snapshot),
    quantity_milli: dbValueToMilli(row.quantity),
    unit_price_cents: dbValueToCents(row.unit_price) ?? 0,
    discount_percent: Number(row.discount_percent),
    line_total_cents: dbValueToCents(row.line_total) ?? 0,
    sort_order: row.sort_order,
    notes: row.notes,
  };
}

export async function findItems(quoteId: string): Promise<QuoteItemView[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("quote_items")
    .select("*")
    .eq("quote_id", quoteId)
    .order("sort_order", { ascending: true });

  if (error) throw new Error(error.message);
  return (data ?? []).map(toItemView);
}

export async function findItem(itemId: string): Promise<QuoteItemView | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("quote_items").select("*").eq("id", itemId).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? toItemView(data) : null;
}

// ── Escrita do cabeçalho ─────────────────────────────────────

type HeaderRecord = {
  customer_id: string;
  issue_date?: string;
  valid_until: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  notes: string | null;
  internal_notes: string | null;
};

export async function insert(record: HeaderRecord, ownerId: string): Promise<string> {
  const supabase = await createClient();
  // `number`, `sequence_year` e `sequence_number` são preenchidos pelo
  // trigger `assign_quote_number` — a aplicação não numera orçamento.
  const { data, error } = await supabase
    .from("quotes")
    .insert({ ...record, owner_id: ownerId, created_by: ownerId, updated_by: ownerId })
    .select("id")
    .single();

  if (error) throw new Error(error.message);
  return data.id;
}

export async function updateHeader(id: string, record: HeaderRecord, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("quotes")
    .update({ ...record, updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

export async function updateCommercial(
  id: string,
  values: { discountPercent: number; discountAmountCents: number; shippingAmountCents: number },
  userId: string,
): Promise<void> {
  const supabase = await createClient();
  // Mudar desconto ou frete dispara `trg_quotes_recalc` no banco.
  const { error } = await supabase
    .from("quotes")
    .update({
      discount_percent: values.discountPercent,
      discount_amount: centsToDecimalString(values.discountAmountCents),
      shipping_amount: centsToDecimalString(values.shippingAmountCents),
      updated_by: userId,
    })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

export async function updateStatus(id: string, status: QuoteStatus, userId: string): Promise<void> {
  const supabase = await createClient();
  // `stamp_quote_status` carimba sent_at / approved_at / rejected_at.
  const { error } = await supabase
    .from("quotes")
    .update({ status, updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

/**
 * Rascunho é excluído logicamente — e isso NÃO pode ser um `update`
 * comum: a policy de SELECT filtra `deleted_at is null`, e o PostgreSQL
 * exige que a linha resultante de um UPDATE continue visível para quem a
 * alterou. Um `set deleted_at = now()` é recusado até para administrador.
 * Ver migration 1800.
 */
export async function discardDraft(id: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("discard_quote_draft", { p_quote_id: id });
  if (error) throw new Error(error.message);
}

// ── Escrita dos itens ────────────────────────────────────────

export type ItemRecord = {
  kind: ItemKind;
  product_id: string | null;
  kit_id: string | null;
  code_snapshot: string | null;
  name_snapshot: string;
  description_snapshot: string | null;
  unit_snapshot: string | null;
  brand_snapshot: string | null;
  image_url_snapshot: string | null;
  components: KitComponentSnapshot[] | null;
  quantity_milli: number;
  unit_price_cents: number;
  discount_percent: number;
};

export async function insertItem(quoteId: string, record: ItemRecord, sortOrder: number): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("quote_items").insert({
    quote_id: quoteId,
    kind: record.kind,
    product_id: record.product_id,
    kit_id: record.kit_id,
    code_snapshot: record.code_snapshot,
    name_snapshot: record.name_snapshot,
    description_snapshot: record.description_snapshot,
    unit_snapshot: record.unit_snapshot,
    brand_snapshot: record.brand_snapshot,
    image_url_snapshot: record.image_url_snapshot,
    components_snapshot: record.components as never,
    quantity: milliToDecimalString(record.quantity_milli),
    unit_price: centsToDecimalString(record.unit_price_cents),
    // `unit_cost_snapshot` fica NULO de propósito — ver migration 1700.
    discount_percent: record.discount_percent,
    sort_order: sortOrder,
  });
  if (error) throw new Error(error.message);
}

export async function updateItem(
  itemId: string,
  patch: {
    quantityMilli?: number;
    discountPercent?: number;
    unitPriceCents?: number;
    components?: KitComponentSnapshot[];
  },
): Promise<void> {
  const supabase = await createClient();
  const record: {
    quantity?: string;
    discount_percent?: number;
    unit_price?: string;
    components_snapshot?: never;
  } = {};

  if (patch.quantityMilli !== undefined) record.quantity = milliToDecimalString(patch.quantityMilli);
  if (patch.discountPercent !== undefined) record.discount_percent = patch.discountPercent;
  if (patch.unitPriceCents !== undefined) record.unit_price = centsToDecimalString(patch.unitPriceCents);
  if (patch.components !== undefined) record.components_snapshot = patch.components as never;

  const { error } = await supabase.from("quote_items").update(record).eq("id", itemId);
  if (error) throw new Error(error.message);
}

export async function deleteItem(itemId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("quote_items").delete().eq("id", itemId);
  if (error) throw new Error(error.message);
}

export async function nextSortOrder(quoteId: string): Promise<number> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("quote_items")
    .select("sort_order")
    .eq("quote_id", quoteId)
    .order("sort_order", { ascending: false })
    .limit(1);

  const last = data?.[0]?.sort_order;
  return typeof last === "number" ? last + 1 : 0;
}

/** Clientes ativos para o seletor do cabeçalho. */
export async function findCustomerOptions(): Promise<{ id: string; name: string; city: string | null }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("customers")
    .select("id, name, city")
    .eq("is_active", true)
    .is("deleted_at", null)
    .order("name");

  if (error) throw new Error(error.message);
  return data ?? [];
}

/** Vendedores, para o filtro do administrador. */
export async function findOwnerOptions(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name")
    .eq("is_active", true)
    .order("full_name");

  if (error) throw new Error(error.message);
  return (data ?? []).map((profile) => ({ id: profile.id, name: profile.full_name }));
}

export async function customerIsUsable(customerId: string): Promise<boolean> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("customers")
    .select("is_active")
    .eq("id", customerId)
    .is("deleted_at", null)
    .maybeSingle();
  return data?.is_active === true;
}

/** Só para conferência: quantos itens o orçamento tem. */
export async function countItems(quoteId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("quote_items")
    .select("id", { count: "exact", head: true })
    .eq("quote_id", quoteId);
  return count ?? 0;
}

export type QuoteRow = Quote;
