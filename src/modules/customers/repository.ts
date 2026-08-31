import "server-only";

import { createClient } from "@/lib/supabase/server";
import { assertColumns } from "@/types/db";
import type { Customer, InsertOf, UpdateOf } from "@/types/db";
import type { CustomerFilters } from "./schema";
import { CUSTOMERS_PAGE_SIZE, type CustomerHistory, type CustomerListItem, type CustomerPage } from "./types";

/**
 * Acesso a dados de Clientes. ÚNICO lugar do módulo que fala com o Supabase.
 * Sem regra de negócio aqui — isso é responsabilidade do service.
 */

const LIST_COLUMNS =
  "id, name, trade_name, person_type, document, phone, whatsapp, city, state, is_active";

export async function findMany(filters: CustomerFilters): Promise<CustomerPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * CUSTOMERS_PAGE_SIZE;

  let query = supabase
    .from("customers")
    .select(LIST_COLUMNS, { count: "exact" })
    .is("deleted_at", null);

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.state) query = query.eq("state", filters.state);

  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(`name.ilike.${term},trade_name.ilike.${term},document.ilike.${term},city.ilike.${term}`);
  }

  const { data, count, error } = await query
    .order("name", { ascending: true })
    .range(from, from + CUSTOMERS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []) as CustomerListItem[],
    total,
    page,
    pageSize: CUSTOMERS_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / CUSTOMERS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<Customer | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("customers")
    .select("*")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** Usado para impedir documento duplicado. Ignora o próprio registro na edição. */
export async function findByDocument(document: string, exceptId?: string): Promise<Pick<Customer, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase
    .from("customers")
    .select("id, name")
    .eq("document", document)
    .is("deleted_at", null);

  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insert(payload: InsertOf<"customers">): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("customers").insert(payload).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, payload: UpdateOf<"customers">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("customers").update(payload).eq("id", id);
  if (error) throw new Error(error.message);
}

/** Nunca apagamos: histórico comercial depende do cliente. */
export async function softDelete(id: string, userId: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("customers")
    .update({ deleted_at: new Date().toISOString(), updated_by: userId })
    .eq("id", id);
  if (error) throw new Error(error.message);
}

/** As mesmas garantias de `quotes_list`, para as colunas que a ficha usa. */
const HISTORY_COLUMNS = ["id", "number", "status", "issue_date", "total"] as const;

export async function findHistory(customerId: string): Promise<CustomerHistory> {
  const supabase = await createClient();

  // O RLS decide o que aparece: o vendedor vê apenas os orçamentos dele.
  const { data } = await supabase
    .from("quotes_list")
    .select("id, number, status, issue_date, total")
    .eq("customer_id", customerId)
    .order("issue_date", { ascending: false })
    .limit(20);

  const quotes = (data ?? []).map((row) => {
    assertColumns(row, HISTORY_COLUMNS, "quotes_list");
    return row;
  });

  return {
    quotes,
    quotesTotal: quotes.reduce((sum, quote) => sum + Number(quote.total), 0),
  };
}
