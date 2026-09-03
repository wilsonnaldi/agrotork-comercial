import type { ItemKind, OrderListRow, OrderStatus } from "@/types/db";

/**
 * Pedido no formato usado pela aplicação: dinheiro em **centavos**,
 * quantidade em **milésimos**. A conversão acontece no repository.
 *
 * O pedido é somente leitura no comercial. Não existe `OrderItemInput`
 * nem edição de item aqui — a composição nasce com o pedido, pela função
 * `create_order_from_quote()`, e o banco recusa qualquer escrita depois.
 */

export type OrderItemView = {
  id: string;
  order_id: string;
  kind: ItemKind;
  product_id: string | null;
  kit_id: string | null;
  code_snapshot: string | null;
  name_snapshot: string;
  description_snapshot: string | null;
  unit_snapshot: string | null;
  brand_snapshot: string | null;
  quantity_milli: number;
  unit_price_cents: number;
  discount_percent: number;
  line_total_cents: number;
  sort_order: number;
  notes: string | null;
};

export type OrderView = {
  id: string;
  number: string;
  status: OrderStatus;
  customer_id: string;
  customer_name: string;
  customer_city: string | null;
  owner_id: string;
  owner_name: string;
  /** Orçamento de origem. Nulo se ele tiver sido apagado depois. */
  quote_id: string | null;
  quote_number: string | null;
  /** Pedido que este substitui, quando nasceu de uma renegociação. */
  supersedes_order_id: string | null;
  issue_date: string;
  delivery_forecast: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  notes: string | null;
  internal_notes: string | null;
  discount_percent: number;
  discount_amount_cents: number;
  shipping_amount_cents: number;
  /** Soma das linhas. Calculado pelo banco. */
  subtotal_cents: number;
  /** Subtotal − descontos + frete. Calculado pelo banco, nunca pela tela. */
  total_cents: number;
  confirmed_at: string;
  picking_at: string | null;
  invoiced_at: string | null;
  delivered_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
};

export type OrderWithItems = OrderView & { items: OrderItemView[] };

export type OrderListItem = Omit<OrderListRow, "subtotal" | "total"> & {
  subtotal_cents: number;
  total_cents: number;
};

export type OrderPage = {
  items: OrderListItem[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

export const ORDERS_PAGE_SIZE = 20;

/**
 * Situações que a tela oferece a partir da atual.
 *
 * É a MESMA tabela do gatilho `validate_order_status_transition` no banco,
 * escrita aqui de novo de propósito: o banco recusa com exceção, a tela
 * precisa saber o que sequer mostrar como botão. Se as duas divergirem,
 * quem manda é o banco — a tela só ofereceria um botão que falha.
 *
 * `delivered` e `cancelled` não têm saída: o pedido terminou. Depois de
 * faturado não há cancelamento — o caminho é devolução, que é assunto da
 * onda fiscal.
 */
export const STATUS_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  confirmed: ["picking", "invoiced", "cancelled"],
  picking: ["invoiced", "cancelled"],
  invoiced: ["delivered"],
  delivered: [],
  cancelled: [],
};
