import "server-only";

import { createClient } from "@/lib/supabase/server";
import { dbValueToCents } from "@/lib/format/money";
import type { QuoteStatus } from "@/types/db";

/**
 * Leitura dos orçamentos de um período, para os relatórios.
 *
 * A agregação é feita na aplicação, não em SQL. Duas razões: nenhuma
 * migration nova é necessária, e o RLS continua sendo o único a decidir o
 * que cada um enxerga — um vendedor recebe só os próprios orçamentos e,
 * portanto, só soma os próprios.
 *
 * O limite disso é conhecido e está aqui de propósito: o período inteiro
 * vem para a memória. Com o volume de uma revenda isso é irrelevante; se
 * um dia forem dezenas de milhares de orçamentos por ano, a soma migra
 * para uma view agregada no banco.
 */

export type LinhaRelatorio = {
  status: QuoteStatus;
  owner_id: string;
  owner_name: string;
  total_cents: number;
};

export async function findQuotesInPeriod(de: string, ate: string, vendedor?: string): Promise<LinhaRelatorio[]> {
  const supabase = await createClient();

  let query = supabase
    .from("quotes_list")
    .select("status, owner_id, owner_name, total")
    .gte("issue_date", de)
    .lte("issue_date", ate);

  if (vendedor) query = query.eq("owner_id", vendedor);

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  const linhas: LinhaRelatorio[] = [];
  for (const linha of data ?? []) {
    // A view já exclui os descartados (deleted_at is null). Uma linha sem
    // situação ou sem dono não existe no schema; se aparecer, é sinal de
    // que a view mudou — e aí ela fica de fora em vez de virar zero.
    if (!linha.status || !linha.owner_id) continue;
    linhas.push({
      status: linha.status,
      owner_id: linha.owner_id,
      owner_name: linha.owner_name ?? "—",
      total_cents: dbValueToCents(linha.total) ?? 0,
    });
  }
  return linhas;
}

/** Vendedores que aparecem no filtro. O RLS decide quem é visível. */
export async function findOwners(): Promise<{ id: string; full_name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name")
    .order("full_name", { ascending: true });

  if (error) throw new Error(error.message);
  return data ?? [];
}
