import type {
  ItemKind,
  PersonType,
  ProductSourceType,
  QuoteStatus,
  UserRole,
} from "@/types/db";

/** Rótulos em português. O banco guarda o valor canônico em inglês. */

export const ROLE_LABELS: Record<UserRole, string> = {
  admin: "Administrador",
  salesperson: "Vendedor",
};

export const PERSON_TYPE_LABELS: Record<PersonType, string> = {
  individual: "Pessoa física",
  company: "Pessoa jurídica",
};

export const ITEM_KIND_LABELS: Record<ItemKind, string> = {
  product: "Produto",
  kit: "Kit",
  custom: "Item livre",
};

export const PRODUCT_SOURCE_LABELS: Record<ProductSourceType, string> = {
  manual: "Cadastro manual",
  manufacturer_catalog: "Catálogo do fabricante",
  price_list: "Tabela de preços",
  test_data: "Massa de teste",
};

export const QUOTE_STATUS_LABELS: Record<QuoteStatus, string> = {
  draft: "Rascunho",
  sent: "Enviado",
  approved: "Aprovado",
  rejected: "Recusado",
  expired: "Expirado",
  cancelled: "Cancelado",
};

export const QUOTE_STATUS_TONE: Record<QuoteStatus, "neutral" | "info" | "success" | "danger" | "warning"> = {
  draft: "neutral",
  sent: "info",
  approved: "success",
  rejected: "danger",
  expired: "warning",
  cancelled: "neutral",
};
