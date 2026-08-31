import type { KitItemType, KitListRow } from "@/types/db";

/**
 * Kit no formato usado pela aplicação: dinheiro em **centavos**,
 * quantidade em **milésimos**. A conversão acontece no repository.
 */
export type KitView = Omit<
  KitListRow,
  "components_total" | "optional_total" | "suggested_price" | "discount_percent"
> & {
  discount_percent: number;
  /** Preço-base: soma apenas dos itens obrigatórios. */
  components_total_cents: number;
  /** Soma dos opcionais. Informativo — só entra no orçamento se escolhido. */
  optional_total_cents: number;
  suggested_price_cents: number;
};

/** Componente do kit, já com os dados do produto para exibição. */
export type KitItemView = {
  id: string;
  kit_id: string;
  product_id: string;
  item_type: KitItemType;
  quantity_milli: number;
  sort_order: number;
  /** Snapshot de leitura — vem do produto AGORA, não é congelado. */
  product_code: string;
  product_name: string;
  manufacturer_code: string | null;
  brand_name: string | null;
  unit_code: string | null;
  unit_allows_fraction: boolean;
  sale_price_cents: number;
  product_is_active: boolean;
  /** Subtotal da linha: quantidade × preço de venda. Nunca inclui custo. */
  line_total_cents: number;
};

export type KitComposition = {
  required: KitItemView[];
  optional: KitItemView[];
};

export type KitPage = {
  items: KitView[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

/** Produto candidato a componente, na busca do editor de composição. */
export type ComponentCandidate = {
  id: string;
  code: string;
  name: string;
  manufacturer_code: string | null;
  brand_name: string | null;
  unit_code: string | null;
  unit_allows_fraction: boolean;
  sale_price_cents: number;
  /** Já está no kit? Então não pode entrar de novo (unique kit_id+product_id). */
  already_in_kit: boolean;
};

export const KITS_PAGE_SIZE = 20;
export const COMPONENT_SEARCH_LIMIT = 12;
