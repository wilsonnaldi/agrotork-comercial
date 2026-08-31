import type { Customer, QuoteListRow } from "@/types/db";

/** Colunas que a listagem precisa — evita trazer a ficha inteira. */
export type CustomerListItem = Pick<
  Customer,
  "id" | "name" | "trade_name" | "person_type" | "document" | "phone" | "whatsapp" | "city" | "state" | "is_active"
>;

export type CustomerPage = {
  items: CustomerListItem[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

/**
 * Orçamentos do cliente: as cinco colunas que a ficha mostra, tiradas da
 * mesma projeção de `quotes_list` usada na listagem — inclusive o `status`
 * tipado como `QuoteStatus`, e não como texto solto.
 */
export type CustomerQuoteRow = Pick<
  QuoteListRow,
  "id" | "number" | "status" | "issue_date" | "total"
>;

/**
 * Histórico comercial do cliente.
 *
 * Hoje só orçamentos existem. Pedidos, compras e contatos entram aqui
 * conforme os módulos forem criados — sem mudar a ficha do cliente.
 */
export type CustomerHistory = {
  quotes: CustomerQuoteRow[];
  quotesTotal: number;
};

export const CUSTOMERS_PAGE_SIZE = 20;
