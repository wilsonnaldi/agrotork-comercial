import type {
  ItemKind,
  OrderStatus,
  PersonType,
  ProductSourceType,
  QuoteStatus,
  SerialStatus,
  StockReason,
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

export const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  confirmed: "Confirmado",
  picking: "Em separação",
  invoiced: "Faturado",
  delivered: "Entregue",
  cancelled: "Cancelado",
};

export const ORDER_STATUS_TONE: Record<OrderStatus, "neutral" | "info" | "success" | "danger" | "warning"> = {
  confirmed: "info",
  picking: "warning",
  invoiced: "info",
  delivered: "success",
  cancelled: "neutral",
};

/**
 * Estoque. O usuário lê o MOTIVO, nunca o sinal: "Perda" já diz que
 * saiu. Mostrar "−3" e "Perda" lado a lado é dizer a mesma coisa duas
 * vezes, e convida a interpretar errado quando o ajuste é positivo.
 */
export const STOCK_REASON_LABELS: Record<StockReason, string> = {
  initial: "Contagem inicial",
  purchase: "Entrada de mercadoria",
  sale: "Saída por venda",
  return_in: "Devolução do cliente",
  return_out: "Devolução ao fornecedor",
  adjustment: "Ajuste de contagem",
  loss: "Perda",
};

export const SERIAL_STATUS_LABELS: Record<SerialStatus, string> = {
  in_stock: "No estoque",
  sold: "Vendido",
  returned: "Devolvido",
  defective: "Com defeito",
  written_off: "Baixado",
};

export const SERIAL_STATUS_TONE: Record<SerialStatus, "neutral" | "info" | "success" | "danger" | "warning"> = {
  in_stock: "success",
  sold: "info",
  returned: "warning",
  defective: "danger",
  written_off: "neutral",
};
