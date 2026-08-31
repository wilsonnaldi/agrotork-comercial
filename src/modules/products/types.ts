import type { ProductListRow } from "@/types/db";

/**
 * Produto no formato usado pela aplicação: dinheiro em **centavos**.
 * A conversão acontece no repository, para que nada acima dele
 * precise pensar em `numeric` ou em ponto flutuante.
 */
export type ProductView = Omit<ProductListRow, "sale_price" | "cost_price" | "margin_percent"> & {
  sale_price_cents: number;
  /** Nulo quando o usuário não é administrador — decidido pelo RLS. */
  cost_price_cents: number | null;
  margin_percent: number | null;
};

export type ProductPage = {
  items: ProductView[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

/** Opções dos filtros e do formulário, carregadas dos cadastros de apoio. */
export type CatalogOptions = {
  brands: { id: string; name: string }[];
  categories: { id: string; name: string }[];
  units: { id: string; code: string; name: string }[];
};

export const PRODUCTS_PAGE_SIZE = 20;
