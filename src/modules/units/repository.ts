import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { InsertOf, Unit, UpdateOf } from "@/types/db";
import type { UnitFilters } from "./schema";

/** Acesso a dados de Unidades. Sem regra de negócio. */

export const UNITS_PAGE_SIZE = 50;

export type UnitPage = {
  items: Unit[];
  total: number;
  page: number;
  pageCount: number;
};

export async function findMany(filters: UnitFilters): Promise<UnitPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * UNITS_PAGE_SIZE;

  // `units` não tem exclusão lógica: unidade não se apaga, se desativa.
  let query = supabase.from("units").select("*", { count: "exact" });

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.q) {
    const term = `%${filters.q}%`;
    query = query.or(`code.ilike.${term},name.ilike.${term}`);
  }

  const { data, count, error } = await query
    .order("code", { ascending: true })
    .range(from, from + UNITS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: data ?? [],
    total,
    page,
    pageCount: Math.max(Math.ceil(total / UNITS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<Unit | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("units").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

/** Código é único, sem distinguir maiúsculas. */
export async function findByCode(code: string, exceptId?: string): Promise<Pick<Unit, "id" | "code" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase.from("units").select("id, code, name").ilike("code", code);
  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insert(record: InsertOf<"units">): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("units").insert(record).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, record: UpdateOf<"units">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("units").update(record).eq("id", id);
  if (error) throw new Error(error.message);
}

/** Quantos produtos usam a unidade. Alimenta o aviso ao desativar. */
export async function countProducts(unitId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("products")
    .select("id", { count: "exact", head: true })
    .eq("unit_id", unitId)
    .is("deleted_at", null);
  return count ?? 0;
}
