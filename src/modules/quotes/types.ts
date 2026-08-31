import type { ItemKind, QuoteListRow, QuoteStatus } from "@/types/db";

/**
 * Orçamento no formato usado pela aplicação: dinheiro em **centavos**,
 * quantidade em **milésimos**. A conversão acontece no repository.
 */

/**
 * Um componente do kit, congelado no orçamento.
 *
 * Guardamos **todos** os componentes — inclusive os opcionais que o
 * vendedor NÃO escolheu — porque a informação "este kit oferecia isto e
 * o cliente não quis" é comercialmente útil e não pode ser reconstruída
 * depois: o cadastro do kit muda, o orçamento não.
 *
 * `quantity_milli` é a quantidade **por unidade do kit**. A quantidade
 * efetiva é `quantity_milli × quantidade da linha do kit`.
 */
export type KitComponentSnapshot = {
  product_id: string | null;
  code: string;
  name: string;
  unit: string | null;
  brand: string | null;
  quantity_milli: number;
  unit_price_cents: number;
  item_type: "required" | "optional";
  /** Entrou nesta venda? Obrigatório é sempre `true`. */
  selected: boolean;
};

export type QuoteItemView = {
  id: string;
  quote_id: string;
  kind: ItemKind;
  product_id: string | null;
  kit_id: string | null;
  code_snapshot: string | null;
  name_snapshot: string;
  description_snapshot: string | null;
  unit_snapshot: string | null;
  brand_snapshot: string | null;
  components: KitComponentSnapshot[] | null;
  quantity_milli: number;
  unit_price_cents: number;
  discount_percent: number;
  line_total_cents: number;
  sort_order: number;
  notes: string | null;
};

export type QuoteView = {
  id: string;
  number: string;
  status: QuoteStatus;
  customer_id: string;
  customer_name: string;
  customer_city: string | null;
  customer_document: string | null;
  owner_id: string;
  owner_name: string;
  issue_date: string;
  valid_until: string | null;
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
  sent_at: string | null;
  approved_at: string | null;
  rejected_at: string | null;
  created_at: string;
  updated_at: string;
};

export type QuoteWithItems = QuoteView & { items: QuoteItemView[] };

export type QuoteListItem = Omit<QuoteListRow, "subtotal" | "total"> & {
  subtotal_cents: number;
  total_cents: number;
};

export type QuotePage = {
  items: QuoteListItem[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

/** Produto candidato a entrar no orçamento. */
export type ProductCandidate = {
  id: string;
  code: string;
  name: string;
  manufacturer_code: string | null;
  brand_name: string | null;
  unit_code: string | null;
  unit_allows_fraction: boolean;
  sale_price_cents: number;
};

/** Kit candidato, já com a composição pronta para a tela de opcionais. */
export type KitCandidate = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  is_active: boolean;
  required_count: number;
  optional_count: number;
  base_price_cents: number;
};

export type KitConfiguration = {
  kit: KitCandidate;
  required: KitComponentSnapshot[];
  optional: KitComponentSnapshot[];
};

export const QUOTES_PAGE_SIZE = 20;
export const CATALOG_SEARCH_LIMIT = 12;

/**
 * Transições de status permitidas.
 *
 * `approved` só sai daqui pelas mãos do administrador — o RLS já trava o
 * vendedor (`quote_is_editable`), e esta tabela repete a regra no domínio
 * para a mensagem de erro ser clara em vez de "permissão negada".
 */
export const STATUS_TRANSITIONS: Record<QuoteStatus, QuoteStatus[]> = {
  draft: ["sent", "cancelled"],
  sent: ["approved", "rejected", "expired", "draft", "cancelled"],
  approved: ["draft", "cancelled"],
  rejected: ["draft", "cancelled"],
  expired: ["draft", "cancelled"],
  cancelled: ["draft"],
};

/** Sair de `approved` é operação de administrador. */
export const ADMIN_ONLY_FROM: QuoteStatus[] = ["approved"];
