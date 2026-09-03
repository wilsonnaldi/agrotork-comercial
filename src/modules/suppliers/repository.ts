import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { InsertOf, Supplier, UpdateOf } from "@/types/db";
import type { SupplierFilters } from "./schema";
import { SUPPLIERS_PAGE_SIZE, type SupplierListItem, type SupplierPage } from "./types";

/**
 * Acesso a dados de Fornecedores. ÚNICO lugar do módulo que fala com o
 * Supabase. Sem regra de negócio aqui — isso é do service.
 */

const LIST_COLUMNS = "id, name, trade_name, person_type, document, phone, city, state, is_active";

export async function findMany(filters: SupplierFilters): Promise<SupplierPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * SUPPLIERS_PAGE_SIZE;

  let query = supabase
    .from("suppliers")
    .select(LIST_COLUMNS, { count: "exact" })
    .is("deleted_at", null);

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.state) query = query.eq("state", filters.state);

  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(
      `name.ilike.${term},trade_name.ilike.${term},document.ilike.${term},city.ilike.${term},contact_name.ilike.${term}`,
    );
  }

  const { data, count, error } = await query
    .order("name", { ascending: true })
    .range(from, from + SUPPLIERS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []) as SupplierListItem[],
    total,
    page,
    pageSize: SUPPLIERS_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / SUPPLIERS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<Supplier | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("suppliers")
    .select("*")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** Usado para impedir documento duplicado. Ignora o próprio registro na edição. */
export async function findByDocument(
  document: string,
  exceptId?: string,
): Promise<Pick<Supplier, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase
    .from("suppliers")
    .select("id, name")
    .eq("document", document)
    .is("deleted_at", null);

  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insert(payload: InsertOf<"suppliers">): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("suppliers").insert(payload).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, payload: UpdateOf<"suppliers">): Promise<void> {
  const supabase = await createClient();
  // `select("id")` de propósito: sem ele, um UPDATE recusado pelo RLS volta
  // sem erro e com zero linhas — a recusa silenciosa que já nos mordeu em
  // `quote_items`. Aqui a contagem denuncia.
  const { data, error } = await supabase.from("suppliers").update(payload).eq("id", id).select("id");
  if (error) throw new Error(error.message);
  if ((data ?? []).length === 0) {
    throw new Error("Sem permissão para alterar este fornecedor");
  }
}

/**
 * Nunca apagamos: a entrada de mercadoria vai depender do fornecedor.
 *
 * Vai por RPC, e não por `update`, porque a policy `suppliers_select`
 * exige `deleted_at is null` — e o PostgreSQL aplica as policies de SELECT
 * também sobre a linha RESULTANTE de um UPDATE, o que faria o banco
 * recusar a exclusão lógica para todo mundo. Ver a migration
 * 20260903100000 e o teste FN7c.
 */
export async function softDelete(id: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("delete_supplier", { p_supplier_id: id });
  if (error) throw new Error(error.message);
}
