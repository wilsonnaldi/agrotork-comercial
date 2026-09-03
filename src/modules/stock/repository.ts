import "server-only";

import { createClient } from "@/lib/supabase/server";
import { toProductStockRow } from "@/types/db";
import type { ProductSerial } from "@/types/db";
import { milliToDecimalString } from "@/lib/format/quantity";
import type { MovementInput, SerialInput, StockFilters } from "./schema";
import {
  MOVEMENTS_PAGE_SIZE,
  STOCK_PAGE_SIZE,
  type MovementRow,
  type SerialRow,
  type StockPage,
  type StockRow,
} from "./types";

/**
 * Acesso a dados de Estoque. ÚNICO lugar do módulo que fala com o Supabase.
 *
 * O saldo NUNCA é somado aqui: quem soma é a view `product_stock`, no
 * banco. Somar em JavaScript exigiria trazer o livro inteiro para a
 * memória e daria um número diferente do que o banco entende por saldo.
 */

const STOCK_COLUMNS =
  "product_id, code, name, unit_id, category_id, brand_id, is_active, tracks_serial, quantity, last_movement_at";

export async function findStock(filters: StockFilters): Promise<StockPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * STOCK_PAGE_SIZE;

  const aplicar = <T extends { eq: unknown }>(query: T) => {
    let q = query as never as {
      eq: (c: string, v: unknown) => typeof q;
      lt: (c: string, v: unknown) => typeof q;
      gt: (c: string, v: unknown) => typeof q;
      or: (f: string) => typeof q;
    };
    if (filters.category) q = q.eq("category_id", filters.category);
    if (filters.situacao === "negative") q = q.lt("quantity", 0);
    if (filters.situacao === "zero") q = q.eq("quantity", 0);
    if (filters.situacao === "positive") q = q.gt("quantity", 0);
    if (filters.q) {
      const termo = `%${filters.q}%`;
      q = q.or(`name.ilike.${termo},code.ilike.${termo}`);
    }
    return q as never as T;
  };

  const ordem =
    filters.sort === "quantity"
      ? { coluna: "quantity", asc: true }
      : filters.sort === "recent"
        ? { coluna: "last_movement_at", asc: false }
        : { coluna: "name", asc: true };

  const [lista, negativos] = await Promise.all([
    aplicar(supabase.from("product_stock").select(STOCK_COLUMNS, { count: "exact" }))
      .order(ordem.coluna, { ascending: ordem.asc, nullsFirst: false })
      .range(from, from + STOCK_PAGE_SIZE - 1),
    // A contagem de negativos ignora o filtro de situação de propósito: é
    // o aviso "existem N produtos a acertar", e ele precisa aparecer
    // mesmo quando a pessoa está olhando outra fatia.
    supabase.from("product_stock").select("product_id", { count: "exact", head: true }).lt("quantity", 0),
  ]);

  if (lista.error) throw new Error(lista.error.message);
  if (negativos.error) throw new Error(negativos.error.message);

  const unidades = await unitCodes(
    (lista.data ?? []).map((linha) => (linha as { unit_id: string }).unit_id),
  );

  const total = lista.count ?? 0;
  return {
    items: (lista.data ?? []).map((linha) => {
      const row = toProductStockRow(linha as never);
      return { ...row, unit_code: unidades.get(row.unit_id) ?? null } satisfies StockRow;
    }),
    total,
    page,
    pageSize: STOCK_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / STOCK_PAGE_SIZE), 1),
    negativeCount: negativos.count ?? 0,
  };
}

/** Uma consulta para todas as unidades da página, em vez de uma por linha. */
async function unitCodes(ids: string[]): Promise<Map<string, string>> {
  const unicos = [...new Set(ids)];
  if (unicos.length === 0) return new Map();

  const supabase = await createClient();
  const { data, error } = await supabase.from("units").select("id, code").in("id", unicos);
  if (error) throw new Error(error.message);
  return new Map((data ?? []).map((u) => [u.id, u.code]));
}

export async function findStockByProduct(productId: string): Promise<StockRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("product_stock")
    .select(STOCK_COLUMNS)
    .eq("product_id", productId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) return null;

  const row = toProductStockRow(data as never);
  const unidades = await unitCodes([row.unit_id]);
  return { ...row, unit_code: unidades.get(row.unit_id) ?? null };
}

export async function findMovements(productId: string): Promise<MovementRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("stock_movements")
    .select("id, reason, quantity, notes, created_at, order_id, orders(number), profiles!stock_movements_created_by_fkey(full_name)")
    .eq("product_id", productId)
    .order("created_at", { ascending: false })
    .limit(MOVEMENTS_PAGE_SIZE);

  if (error) throw new Error(error.message);

  return (data ?? []).map((linha) => {
    const bruto = linha as unknown as {
      id: string;
      reason: MovementRow["reason"];
      quantity: number;
      notes: string | null;
      created_at: string;
      order_id: string | null;
      orders: { number: string } | null;
      profiles: { full_name: string | null } | null;
    };
    return {
      id: bruto.id,
      reason: bruto.reason,
      quantity: bruto.quantity,
      notes: bruto.notes,
      created_at: bruto.created_at,
      order_id: bruto.order_id,
      order_number: bruto.orders?.number ?? null,
      author_name: bruto.profiles?.full_name ?? null,
    } satisfies MovementRow;
  });
}

/**
 * Vai por RPC porque a função do banco confere o papel, corrige o sinal
 * dos motivos que só saem e grava o custo na tabela irmã — três coisas
 * que precisam acontecer na mesma transação.
 */
export async function registerMovement(input: MovementInput): Promise<string> {
  const supabase = await createClient();
  // `p_notes` é opcional no banco (tem default). Mandar `null` seria
  // dizer "grave nulo", que dá no mesmo — mas o tipo gerado é `string?`,
  // e omitir a chave é o que corresponde ao default.
  const { data, error } = await supabase.rpc("register_stock_movement", {
    p_product_id: input.product_id,
    p_reason: input.reason,
    p_quantity: milliToDecimalString(input.quantity_milli) as never,
    ...(input.notes ? { p_notes: input.notes } : {}),
  });
  if (error) throw new Error(error.message);
  return data as string;
}

export async function findSerials(productId: string): Promise<SerialRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("product_serials")
    .select("id, serial, status, order_id, sold_at, notes, orders(number)")
    .eq("product_id", productId)
    .order("status", { ascending: true })
    .order("serial", { ascending: true });

  if (error) throw new Error(error.message);

  return (data ?? []).map((linha) => {
    const bruto = linha as unknown as SerialRow & { orders: { number: string } | null };
    return {
      id: bruto.id,
      serial: bruto.serial,
      status: bruto.status,
      order_id: bruto.order_id,
      sold_at: bruto.sold_at,
      notes: bruto.notes,
      order_number: bruto.orders?.number ?? null,
    } satisfies SerialRow;
  });
}

/** Aparelhos disponíveis de um produto — o que a tela do pedido oferece. */
export async function findAvailableSerials(
  productId: string,
): Promise<Pick<ProductSerial, "id" | "serial">[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("product_serials")
    .select("id, serial")
    .eq("product_id", productId)
    .eq("status", "in_stock")
    .order("serial", { ascending: true })
    .limit(200);

  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function insertSerial(input: SerialInput, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("product_serials").insert({
    product_id: input.product_id,
    serial: input.serial,
    notes: input.notes ?? null,
    created_by: userId,
    updated_by: userId,
  });
  if (error) throw new Error(error.message);
}

export async function assignSerial(serialId: string, orderItemId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_serial_to_order", {
    p_serial_id: serialId,
    p_order_item_id: orderItemId,
  });
  if (error) throw new Error(error.message);
}

export async function releaseSerial(serialId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("release_serial", { p_serial_id: serialId });
  if (error) throw new Error(error.message);
}

/** Aparelhos já vinculados a um pedido, para a ficha do pedido. */
export async function findSerialsByOrder(orderId: string): Promise<
  (Pick<ProductSerial, "id" | "serial" | "order_item_id"> & { product_id: string })[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("product_serials")
    .select("id, serial, order_item_id, product_id")
    .eq("order_id", orderId);

  if (error) throw new Error(error.message);
  return data ?? [];
}

/** Dos produtos informados, quais são controlados aparelho a aparelho. */
export async function findTrackedProductIds(productIds: string[]): Promise<Set<string>> {
  const unicos = [...new Set(productIds)];
  if (unicos.length === 0) return new Set();

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products")
    .select("id")
    .in("id", unicos)
    .eq("tracks_serial", true);

  if (error) throw new Error(error.message);
  return new Set((data ?? []).map((p) => p.id));
}
