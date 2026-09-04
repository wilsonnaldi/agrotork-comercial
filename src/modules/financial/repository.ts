import "server-only";

import { createClient } from "@/lib/supabase/server";
import { toFinancialPositionRow } from "@/types/db";
import { centsToDecimalString, dbValueToCents } from "@/lib/format/money";
import type { FinancialFilters, PaymentInput, SplitInput } from "./schema";
import {
  DUE_SOON_DAYS,
  ENTRIES_PAGE_SIZE,
  type EntryPage,
  type EntryRow,
  type FinancialSummary,
  type PaymentRow,
} from "./types";

/**
 * Acesso a dados do Financeiro. ÚNICO lugar do módulo que fala com o
 * Supabase.
 *
 * O status do título NUNCA é escrito daqui: quem o mantém é o gatilho,
 * a partir da soma das baixas. Escrever status na aplicação seria abrir
 * a porta para a tela dizer "quitado" e o banco discordar.
 */

const COLUMNS =
  "id, kind, status, description, due_date, amount, installment, installments, created_at, party_name, order_id, order_number, purchase_id, purchase_number, paid_amount, open_amount, is_overdue, days_overdue";

function paraLinha(bruto: unknown): EntryRow {
  const row = toFinancialPositionRow(bruto as never);
  const extra = bruto as {
    order_id: string | null;
    order_number: string | null;
    purchase_id: string | null;
    purchase_number: string | null;
  };
  const { amount, paid_amount, open_amount, ...resto } = row;
  return {
    ...resto,
    amount_cents: dbValueToCents(amount) ?? 0,
    paid_cents: dbValueToCents(paid_amount) ?? 0,
    open_cents: dbValueToCents(open_amount) ?? 0,
    order_id: extra.order_id,
    order_number: extra.order_number,
    purchase_id: extra.purchase_id,
    purchase_number: extra.purchase_number,
  };
}

function hojeISO(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function findMany(filters: FinancialFilters): Promise<EntryPage> {
  const supabase = await createClient();
  const page = Math.max(filters.page, 1);
  const from = (page - 1) * ENTRIES_PAGE_SIZE;
  const hoje = hojeISO();

  let query = supabase.from("financial_position").select(COLUMNS, { count: "exact" });

  if (filters.kind !== "all") query = query.eq("kind", filters.kind);

  if (filters.situacao === "open") query = query.in("status", ["open", "partial"]);
  if (filters.situacao === "settled") query = query.eq("status", "settled");
  if (filters.situacao === "overdue") {
    query = query.in("status", ["open", "partial"]).lt("due_date", hoje);
  }

  if (filters.q) {
    const termo = `%${filters.q}%`;
    query = query.or(`description.ilike.${termo},party_name.ilike.${termo}`);
  }

  // Vencimento crescente: o que vence antes precisa aparecer antes. É a
  // única ordenação que essa tela pode ter por padrão.
  const { data, count, error } = await query
    .order("due_date", { ascending: true })
    .order("created_at", { ascending: true })
    .range(from, from + ENTRIES_PAGE_SIZE - 1);

  if (error) throw new Error(error.message);

  const total = count ?? 0;
  return {
    items: (data ?? []).map(paraLinha),
    total,
    page,
    pageSize: ENTRIES_PAGE_SIZE,
    pageCount: Math.max(Math.ceil(total / ENTRIES_PAGE_SIZE), 1),
    summary: await summary(filters.kind),
  };
}

/**
 * Os números do topo. Somados no banco, e sobre o RECORTE INTEIRO — não
 * sobre a página. "R$ 12.400 atrasados" que muda quando a pessoa vira a
 * página não é informação, é armadilha.
 */
async function summary(kind: FinancialFilters["kind"]): Promise<FinancialSummary> {
  const supabase = await createClient();
  const hoje = hojeISO();
  const limite = new Date(Date.now() + DUE_SOON_DAYS * 86_400_000).toISOString().slice(0, 10);

  const base = () => {
    const q = supabase.from("financial_position").select("open_amount, due_date, is_overdue");
    return kind === "all" ? q : q.eq("kind", kind);
  };

  const { data, error } = await base().in("status", ["open", "partial"]).limit(5000);
  if (error) throw new Error(error.message);

  let overdueCount = 0;
  let overdueCents = 0;
  let dueSoonCents = 0;
  let openCents = 0;

  for (const linha of data ?? []) {
    const bruto = linha as { open_amount: string | number; due_date: string; is_overdue: boolean };
    const cents = dbValueToCents(bruto.open_amount) ?? 0;
    openCents += cents;
    if (bruto.is_overdue) {
      overdueCount += 1;
      overdueCents += cents;
    } else if (bruto.due_date >= hoje && bruto.due_date <= limite) {
      dueSoonCents += cents;
    }
  }

  return { overdueCount, overdueCents, dueSoonCents, openCents };
}

export async function findById(id: string): Promise<EntryRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("financial_position")
    .select(COLUMNS)
    .eq("id", id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data ? paraLinha(data) : null;
}

export async function findPayments(entryId: string): Promise<PaymentRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("financial_payments")
    .select("id, amount, paid_on, method, notes, profiles(full_name)")
    .eq("entry_id", entryId)
    .order("paid_on", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);

  return (data ?? []).map((linha) => {
    const bruto = linha as unknown as {
      id: string;
      amount: string | number;
      paid_on: string;
      method: string | null;
      notes: string | null;
      profiles: { full_name: string | null } | null;
    };
    return {
      id: bruto.id,
      amount_cents: dbValueToCents(bruto.amount) ?? 0,
      paid_on: bruto.paid_on,
      method: bruto.method,
      notes: bruto.notes,
      author_name: bruto.profiles?.full_name ?? null,
    } satisfies PaymentRow;
  });
}

/** Títulos de um pedido — para a ficha do pedido mostrar o recebimento. */
export async function findByOrder(orderId: string): Promise<EntryRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("financial_position")
    .select(COLUMNS)
    .eq("order_id", orderId)
    .order("due_date", { ascending: true });

  if (error) throw new Error(error.message);
  return (data ?? []).map(paraLinha);
}

export async function registerPayment(input: PaymentInput): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("register_financial_payment", {
    p_entry_id: input.entry_id,
    p_amount: centsToDecimalString(input.amount_cents) as never,
    p_paid_on: input.paid_on,
    ...(input.method ? { p_method: input.method } : {}),
    ...(input.notes ? { p_notes: input.notes } : {}),
  });
  if (error) throw new Error(error.message);
}

export async function split(input: SplitInput): Promise<number> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("split_financial_entry", {
    p_entry_id: input.entry_id,
    p_installments: input.installments,
    p_first_due: input.first_due,
    p_interval: input.interval_days,
  });
  if (error) throw new Error(error.message);
  return (data as number) ?? 0;
}

export async function cancel(entryId: string, notes?: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_financial_entry", {
    p_entry_id: entryId,
    ...(notes ? { p_notes: notes } : {}),
  });
  if (error) throw new Error(error.message);
}
