import "server-only";

import { createClient } from "@/lib/supabase/server";
import { toQuoteListRow } from "@/types/db";
import type { QuoteListRow } from "@/types/db";

export type DashboardSummary = {
  customers: number;
  products: number;
  kits: number;
  openQuotes: number;
  openQuotesTotal: number;
  recentQuotes: QuoteListRow[];
};

const EMPTY: DashboardSummary = {
  customers: 0,
  products: 0,
  kits: 0,
  openQuotes: 0,
  openQuotesTotal: 0,
  recentQuotes: [],
};

/**
 * Contadores do painel.
 * O RLS já limita o que cada papel enxerga — o vendedor conta só os seus orçamentos.
 */
export async function getDashboardSummary(): Promise<DashboardSummary> {
  const supabase = await createClient();

  const [customers, products, kits, openQuotes, recent] = await Promise.all([
    supabase.from("customers").select("id", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("products").select("id", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("kits").select("id", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("quotes").select("total").in("status", ["draft", "sent"]).is("deleted_at", null),
    supabase.from("quotes_list").select("*").order("created_at", { ascending: false }).limit(5),
  ]);

  if (customers.error && products.error && kits.error) return EMPTY;

  const openList = openQuotes.data ?? [];

  return {
    customers: customers.count ?? 0,
    products: products.count ?? 0,
    kits: kits.count ?? 0,
    openQuotes: openList.length,
    openQuotesTotal: openList.reduce((sum, quote) => sum + Number(quote.total ?? 0), 0),
    recentQuotes: (recent.data ?? []).map(toQuoteListRow),
  };
}
