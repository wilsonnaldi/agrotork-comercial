import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Category, InsertOf, UpdateOf } from "@/types/db";
import type { CategoryFilters } from "./schema";

/** Acesso a dados de Categorias. Sem regra de negócio. */

export const CATEGORIES_PAGE_SIZE = 50;

export type CategoryPage = {
  items: Category[];
  total: number;
  page: number;
  pageCount: number;
};

export async function findMany(filters: CategoryFilters): Promise<CategoryPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * CATEGORIES_PAGE_SIZE;

  let query = supabase.from("categories").select("*", { count: "exact" }).is("deleted_at", null);

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.q) query = query.ilike("name", `%${filters.q}%`);

  const { data, count, error } = await query
    .order("name", { ascending: true })
    .range(from, from + CATEGORIES_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: data ?? [],
    total,
    page,
    pageCount: Math.max(Math.ceil(total / CATEGORIES_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<Category | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("categories")
    .select("*")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** Nome é único entre categorias não excluídas, sem distinguir maiúsculas. */
export async function findByName(
  name: string,
  exceptId?: string,
): Promise<Pick<Category, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase.from("categories").select("id, name").ilike("name", name).is("deleted_at", null);
  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insert(record: InsertOf<"categories">): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("categories").insert(record).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, record: UpdateOf<"categories">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("categories").update(record).eq("id", id);
  if (error) throw new Error(error.message);
}

/** Quantos produtos usam a categoria. Alimenta o aviso ao desativar. */
export async function countProducts(categoryId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("products")
    .select("id", { count: "exact", head: true })
    .eq("category_id", categoryId)
    .is("deleted_at", null);
  return count ?? 0;
}
