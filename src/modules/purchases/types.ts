import type { PurchaseListRow, PurchaseStatus } from "@/types/db";

/**
 * Nota de entrada no formato da aplicação: dinheiro em **centavos**,
 * quantidade em **milésimos**. A conversão acontece no repository.
 *
 * `landed_cost` é `numeric(14,4)` no banco — quatro casas, porque o
 * rateio do frete dividido por uma quantidade fracionada não fecha em
 * dois. Aqui ele anda em DÉCIMOS DE CENTAVO (inteiro), pelo mesmo motivo
 * que o resto anda em centavos.
 */

export type PurchaseItemView = {
  id: string;
  purchase_id: string;
  product_id: string;
  product_name: string;
  product_code: string;
  unit_code: string | null;
  quantity_milli: number;
  unit_cost_cents: number;
  line_total_cents: number;
  freight_share_cents: number;
  /** Custo unitário final, com frete. Nulo enquanto a nota é rascunho. */
  landed_cost_decimillis: number | null;
  /** O que o produto custava antes desta nota. Nulo se nunca teve custo. */
  previous_cost_cents: number | null;
  sort_order: number;
  notes: string | null;
};

export type PurchaseView = {
  id: string;
  number: string;
  status: PurchaseStatus;
  supplier_id: string;
  supplier_name: string;
  condition_id: string;
  condition_name: string;
  invoice_number: string | null;
  invoice_series: string | null;
  invoice_key: string | null;
  issue_date: string;
  received_date: string | null;
  freight_amount_cents: number;
  other_amount_cents: number;
  discount_amount_cents: number;
  items_total_cents: number;
  total_cents: number;
  notes: string | null;
  received_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PurchaseWithItems = PurchaseView & { items: PurchaseItemView[] };

export type PurchaseListItem = Omit<PurchaseListRow, "items_total" | "total"> & {
  items_total_cents: number;
  total_cents: number;
};

export type PurchasePage = {
  items: PurchaseListItem[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

export const PURCHASES_PAGE_SIZE = 20;

/** Só rascunho se edita. Depois de recebida, a nota é documento. */
export function isEditable(status: PurchaseStatus): boolean {
  return status === "draft";
}
