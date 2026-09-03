import "server-only";

import { createClient } from "@/lib/supabase/server";
import { dbValueToCents } from "@/lib/format/money";
import { dbValueToMilli } from "@/lib/format/quantity";
import { toOrderListRow } from "@/types/db";
import type { ItemKind, OrderItem, OrderListRow, OrderStatus } from "@/types/db";
import type { OrderFilters } from "./schema";
import {
  ORDERS_PAGE_SIZE,
  type OrderItemView,
  type OrderPage,
  type OrderView,
} from "./types";

/**
 * Acesso a dados de Pedidos. ÚNICO lugar do módulo que fala com o Supabase.
 *
 * Três coisas que este arquivo NÃO faz, de propósito:
 *
 *  1. não calcula `subtotal` nem `total` — quem calcula é o banco, dentro
 *     de `create_order_from_quote()`, e o gatilho `trg_orders_freeze`
 *     recusaria a escrita se tentássemos;
 *  2. não insere pedido nem item. Não existe `insert` aqui: pedido nasce
 *     só pela RPC de conversão, que é `security definer`. Não há policy de
 *     INSERT em `orders`, e nenhuma policy de escrita em `order_items`;
 *  3. não lê custo. `order_items` nem guarda `unit_cost_snapshot`.
 */

const SORT_COLUMNS: Record<OrderFilters["sort"], { column: string; ascending: boolean }> = {
  recent: { column: "created_at", ascending: false },
  number: { column: "number", ascending: false },
  total: { column: "total", ascending: false },
  customer: { column: "customer_name", ascending: true },
};

/** `date` chega como 'YYYY-MM-DD'; qualquer sufixo de hora é descartado. */
function toDateOnly(value: string | null): string | null {
  return value ? value.slice(0, 10) : null;
}

function toListItem(row: OrderListRow) {
  const { subtotal, total, ...rest } = row;
  return {
    ...rest,
    subtotal_cents: dbValueToCents(subtotal) ?? 0,
    total_cents: dbValueToCents(total) ?? 0,
  };
}

export async function findMany(filters: OrderFilters): Promise<OrderPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * ORDERS_PAGE_SIZE;

  // O RLS já limita o vendedor aos próprios pedidos; o filtro por vendedor
  // abaixo é conveniência do administrador.
  let query = supabase.from("orders_list").select("*", { count: "exact" });

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
    .range(from, from + ORDERS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map(toOrderListRow).map(toListItem),
    total,
    page,
    pageSize: ORDERS_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / ORDERS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<OrderView | null> {
  const supabase = await createClient();

  const { data: order, error } = await supabase.from("orders").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(error.message);
  if (!order || order.deleted_at) return null;

  const [{ data: customer }, { data: owner }, { data: quote }] = await Promise.all([
    supabase.from("customers").select("name, city").eq("id", order.customer_id).maybeSingle(),
    supabase.from("profiles").select("full_name").eq("id", order.owner_id).maybeSingle(),
    order.quote_id
      ? supabase.from("quotes").select("number").eq("id", order.quote_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  return {
    id: order.id,
    number: order.number,
    status: order.status as OrderStatus,
    customer_id: order.customer_id,
    customer_name: customer?.name ?? "—",
    customer_city: customer?.city ?? null,
    owner_id: order.owner_id,
    owner_name: owner?.full_name ?? "—",
    quote_id: order.quote_id,
    quote_number: quote?.number ?? null,
    supersedes_order_id: order.supersedes_order_id,
    issue_date: toDateOnly(order.issue_date) ?? order.issue_date,
    delivery_forecast: toDateOnly(order.delivery_forecast),
    payment_terms: order.payment_terms,
    delivery_terms: order.delivery_terms,
    notes: order.notes,
    internal_notes: order.internal_notes,
    discount_percent: Number(order.discount_percent ?? 0),
    discount_amount_cents: dbValueToCents(order.discount_amount) ?? 0,
    shipping_amount_cents: dbValueToCents(order.shipping_amount) ?? 0,
    subtotal_cents: dbValueToCents(order.subtotal) ?? 0,
    total_cents: dbValueToCents(order.total) ?? 0,
    confirmed_at: order.confirmed_at,
    picking_at: order.picking_at,
    invoiced_at: order.invoiced_at,
    delivered_at: order.delivered_at,
    cancelled_at: order.cancelled_at,
    created_at: order.created_at,
    updated_at: order.updated_at,
  };
}

function toItemView(row: OrderItem): OrderItemView {
  return {
    id: row.id,
    order_id: row.order_id,
    kind: row.kind as ItemKind,
    product_id: row.product_id,
    kit_id: row.kit_id,
    code_snapshot: row.code_snapshot,
    name_snapshot: row.name_snapshot,
    description_snapshot: row.description_snapshot,
    unit_snapshot: row.unit_snapshot,
    brand_snapshot: row.brand_snapshot,
    quantity_milli: dbValueToMilli(row.quantity),
    unit_price_cents: dbValueToCents(row.unit_price) ?? 0,
    discount_percent: Number(row.discount_percent ?? 0),
    line_total_cents: dbValueToCents(row.line_total) ?? 0,
    sort_order: row.sort_order,
    notes: row.notes,
  };
}

export async function findItems(orderId: string): Promise<OrderItemView[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("order_items")
    .select("*")
    .eq("order_id", orderId)
    .order("sort_order", { ascending: true });

  if (error) throw new Error(error.message);
  return (data ?? []).map(toItemView);
}

/**
 * Move a situação. É o único `update` do módulo, e manda SÓ a coluna
 * `status`: qualquer outra coluna comercial nesta chamada faria o gatilho
 * `trg_orders_freeze` recusar a operação inteira. As datas de cada
 * situação são carimbadas pelo banco, não daqui.
 */
export async function updateStatus(id: string, status: OrderStatus, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("orders")
    .update({ status, updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

/** Fecha o orçamento aprovado num pedido. Devolve o id do pedido novo. */
export async function createFromQuote(quoteId: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_order_from_quote", { p_quote_id: quoteId });
  if (error) throw new Error(error.message);
  return data as string;
}

/** Reabre para renegociar. Devolve o id do orçamento NOVO, em rascunho. */
export async function createQuoteFrom(orderId: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_quote_from_order", { p_order_id: orderId });
  if (error) throw new Error(error.message);
  return data as string;
}

/** O pedido vivo gerado por este orçamento, se houver. */
export async function findByQuote(quoteId: string): Promise<{ id: string; number: string } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("orders")
    .select("id, number")
    .eq("quote_id", quoteId)
    .is("deleted_at", null)
    .neq("status", "cancelled")
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data ?? null;
}

export async function findOwnerOptions(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name")
    .order("full_name", { ascending: true });

  if (error) throw new Error(error.message);
  return (data ?? []).map((row) => ({ id: row.id, name: row.full_name ?? "—" }));
}
