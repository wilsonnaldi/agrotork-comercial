import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Category, InsertOf, MarginRule, UpdateOf } from "@/types/db";

/** Acesso a dados da margem por setor. Sem regra de negócio. */

/** Uma linha do ensaio: o que mudaria se a regra fosse aplicada. */
export type MarginChange = {
  product_id: string;
  code: string;
  name: string;
  categoria: string | null;
  preco_atual: number;
  preco_sugerido: number;
  aplicado: boolean;
};

/** Produto com o custo vigente, para a tela mostrar a faixa do setor. */
export type ProductCostRow = {
  id: string;
  code: string;
  category_id: string | null;
  sale_price: number;
  custo: number | null;
};

export async function listRules(): Promise<MarginRule[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("margin_rules").select("*");
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listCategories(): Promise<Category[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("categories").select("*").order("name");
  if (error) throw new Error(error.message);
  return data ?? [];
}

/**
 * Produtos com o custo vigente mais alto entre as condições.
 *
 * O número que a tela mostra é INFORMATIVO — a faixa de custo do setor.
 * O preço em si nunca é calculado aqui: quem calcula é
 * `suggested_sale_price()` no banco, para não existirem duas contas.
 */
export async function listProductCosts(): Promise<ProductCostRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("products")
    .select("id, code, category_id, sale_price, product_costs(cost_price, valid_to)")
    .is("deleted_at", null);
  if (error) throw new Error(error.message);

  return (data ?? []).map((row) => {
    const vigentes = (row.product_costs ?? [])
      .filter((cost) => cost.valid_to === null)
      .map((cost) => cost.cost_price);
    return {
      id: row.id,
      code: row.code,
      category_id: row.category_id,
      sale_price: row.sale_price,
      custo: vigentes.length > 0 ? Math.max(...vigentes) : null,
    };
  });
}

/** Regra de um setor. `null` busca a regra padrão. */
export async function findRule(categoryId: string | null): Promise<MarginRule | null> {
  const supabase = await createClient();
  const query = supabase.from("margin_rules").select("*");
  const { data, error } = await (
    categoryId === null ? query.is("category_id", null) : query.eq("category_id", categoryId)
  ).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

export async function insertRule(record: InsertOf<"margin_rules">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("margin_rules").insert(record);
  if (error) throw new Error(error.message);
}

export async function updateRule(id: string, record: UpdateOf<"margin_rules">): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.from("margin_rules").update(record).eq("id", id);
  if (error) throw new Error(error.message);
}

/**
 * Chama `apply_margin_rules` no banco.
 *
 * `dryRun` verdadeiro é ENSAIO: devolve o que mudaria e não escreve nada.
 * É o padrão da função no banco também — precisa de um `false` explícito
 * para gravar.
 */
export async function runMarginRules(options: {
  categoryId?: string | null;
  todas?: boolean;
  dryRun: boolean;
}): Promise<MarginChange[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("apply_margin_rules", {
    // `undefined` vira nulo no PostgREST, que é o setor "sem categoria".
    p_category_id: options.categoryId ?? undefined,
    p_todas: options.todas ?? false,
    p_dry_run: options.dryRun,
  });
  if (error) throw new Error(error.message);
  return data ?? [];
}
