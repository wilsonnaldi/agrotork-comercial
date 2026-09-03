import type { ProductSerial, ProductStockRow, StockMovement } from "@/types/db";

/** Uma linha da tela de estoque: saldo do produto, mais o rótulo da unidade. */
export type StockRow = ProductStockRow & { unit_code: string | null };

export type StockPage = {
  items: StockRow[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
  /** Quantos produtos estão negativos NO FILTRO INTEIRO, não só nesta página. */
  negativeCount: number;
};

/** Uma linha do livro, já com o nome de quem lançou. */
export type MovementRow = Pick<
  StockMovement,
  "id" | "reason" | "quantity" | "notes" | "created_at" | "order_id"
> & {
  order_number: string | null;
  author_name: string | null;
};

export type SerialRow = Pick<
  ProductSerial,
  "id" | "serial" | "status" | "order_id" | "sold_at" | "notes"
> & { order_number: string | null };

export const STOCK_PAGE_SIZE = 30;
export const MOVEMENTS_PAGE_SIZE = 40;

/**
 * Motivos que a tela oferece. `sale` fica de fora de propósito: saída de
 * venda nasce do pedido faturado, e a função do banco recusa lançá-la à
 * mão (ver a migration 20260903120000).
 */
export const MANUAL_REASONS = [
  "initial",
  "purchase",
  "return_in",
  "return_out",
  "adjustment",
  "loss",
] as const;

export type ManualReason = (typeof MANUAL_REASONS)[number];
