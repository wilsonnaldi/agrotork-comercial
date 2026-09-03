import type { Supplier } from "@/types/db";

/** Colunas que a listagem precisa — evita trazer a ficha inteira. */
export type SupplierListItem = Pick<
  Supplier,
  "id" | "name" | "trade_name" | "person_type" | "document" | "phone" | "city" | "state" | "is_active"
>;

export type SupplierPage = {
  items: SupplierListItem[];
  total: number;
  page: number;
  pageSize: number;
  pageCount: number;
};

export const SUPPLIERS_PAGE_SIZE = 20;
