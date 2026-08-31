import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Brand, InsertOf, UpdateOf } from "@/types/db";
import type { BrandFilters } from "./schema";

/** Acesso a dados de Marcas. Sem regra de negócio. */

export const BRANDS_PAGE_SIZE = 50;

export type BrandPage = {
  items: Brand[];
  total: number;
  page: number;
  pageCount: number;
};

export async function findMany(filters: BrandFilters): Promise<BrandPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * BRANDS_PAGE_SIZE;

  let query = supabase.from("brands").select("*", { count: "exact" }).is("deleted_at", null);

  if (filters.status === "active") query = query.eq("is_active", true);
  if (filters.status === "inactive") query = query.eq("is_active", false);
  if (filters.q) query = query.ilike("name", `%${filters.q}%`);

  const { data, count, error } = await query
    .order("name", { ascending: true })
    .range(from, from + BRANDS_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: data ?? [],
    total,
    page,
    pageCount: Math.max(Math.ceil(total / BRANDS_PAGE_SIZE), 1),
  };
}

export async function findById(id: string): Promise<Brand | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("brands")
    .select("*")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** Nome é único entre marcas não excluídas, sem distinguir maiúsculas. */
export async function findByName(name: string, exceptId?: string): Promise<Pick<Brand, "id" | "name"> | null> {
  const supabase = await createClient();
  let query = supabase.from("brands").select("id, name").ilike("name", name).is("deleted_at", null);
  if (exceptId) query = query.neq("id", exceptId);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insert(record: InsertOf<"brands">): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("brands").insert(record).select("id").single();
  if (error) throw new Error(error.message);
  return data.id;
}

export async function update(id: string, record: UpdateOf<"brands">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("brands").update(record).eq("id", id);
  if (error) throw new Error(error.message);
}

/** Quantos produtos usam a marca. Alimenta o aviso ao desativar. */
export async function countProducts(brandId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("products")
    .select("id", { count: "exact", head: true })
    .eq("brand_id", brandId)
    .is("deleted_at", null);
  return count ?? 0;
}
