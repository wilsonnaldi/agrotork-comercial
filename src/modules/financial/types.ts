import type { FinancialKind, FinancialPositionRow, FinancialStatus } from "@/types/db";

/**
 * Título no formato da aplicação: dinheiro em **centavos**.
 * A conversão acontece no repository.
 */

export type EntryRow = Omit<
  FinancialPositionRow,
  "amount" | "paid_amount" | "open_amount"
> & {
  amount_cents: number;
  paid_cents: number;
  open_cents: number;
  order_number: string | null;
  purchase_number: string | null;
  order_id: string | null;
  purchase_id: string | null;
};

export type PaymentRow = {
  id: string;
  amount_cents: number;
  paid_on: string;
  method: string | null;
  notes: string | null;
  author_name: string | null;
};

/**
 * O resumo do topo da tela. Cada número responde uma pergunta que se faz
 * em voz alta: "quanto está atrasado?", "quanto vence essa semana?",
 * "quanto entrou esse mês?".
 */
export type FinancialSummary = {
  overdueCount: number;
  overdueCents: number;
  dueSoonCents: number;
  openCents: number;
};

export type EntryPage = {
  items: EntryRow[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
  summary: FinancialSummary;
};

export const ENTRIES_PAGE_SIZE = 30;

/** Quantos dias para a frente contam como "vence logo". */
export const DUE_SOON_DAYS = 7;

export const KIND_VALUES: FinancialKind[] = ["receivable", "payable"];
export const STATUS_VALUES: FinancialStatus[] = ["open", "partial", "settled", "cancelled"];
