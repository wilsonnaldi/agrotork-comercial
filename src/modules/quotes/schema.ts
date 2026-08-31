import { z } from "zod";

import { MAX_QUANTITY_MILLI, parseQuantityToMilli } from "@/lib/format/quantity";
import { MAX_MONEY_CENTS, parseMoneyToCents } from "@/lib/format/money";

/**
 * Validação do módulo ORÇAMENTOS.
 *
 * Tudo o que chega do navegador passa por aqui, no servidor — inclusive o
 * que o formulário já validou. E nada que envolva TOTAL é aceito: subtotal
 * e total são calculados pelo banco (`recalculate_quote_totals`), nunca
 * enviados pela tela.
 */

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo de ${max} caracteres`)
    .transform((value) => (value === "" ? undefined : value))
    .optional();

/** Cabeçalho: o que o vendedor preenche antes de montar os itens. */
export const quoteHeaderSchema = z.object({
  customer_id: z.string().uuid("Selecione o cliente"),
  issue_date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Data inválida")
    .optional(),
  valid_until: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Data inválida")
    .optional()
    .or(z.literal("").transform(() => undefined)),
  payment_terms: optionalText(200),
  delivery_terms: optionalText(200),
  notes: optionalText(2000),
  internal_notes: optionalText(2000),
});

export type QuoteHeaderInput = z.infer<typeof quoteHeaderSchema>;

/**
 * Descontos e frete do orçamento.
 * O banco aceita percentual E valor; os dois são aplicados em sequência,
 * na ordem em que `recalculate_quote_totals` os usa.
 */
export const quoteCommercialSchema = z.object({
  discount_percent: z
    .number()
    .min(0, "O desconto não pode ser negativo")
    .max(100, "O desconto não passa de 100%"),
  discount_amount_cents: z
    .number()
    .int()
    .min(0, "O desconto não pode ser negativo")
    .max(MAX_MONEY_CENTS, "Valor acima do limite"),
  shipping_amount_cents: z
    .number()
    .int()
    .min(0, "O frete não pode ser negativo")
    .max(MAX_MONEY_CENTS, "Valor acima do limite"),
});

export type QuoteCommercialInput = z.infer<typeof quoteCommercialSchema>;

const quantityField = z
  .number()
  .int()
  .positive("A quantidade deve ser maior que zero")
  .max(MAX_QUANTITY_MILLI, "Quantidade acima do limite");

const itemDiscountField = z
  .number()
  .min(0, "O desconto não pode ser negativo")
  .max(100, "O desconto não passa de 100%");

/** Produto avulso entrando no orçamento. */
export const addProductSchema = z.object({
  product_id: z.string().uuid("Selecione um produto"),
  quantity_milli: quantityField,
});

export type AddProductInput = z.infer<typeof addProductSchema>;

/**
 * Kit entrando no orçamento.
 *
 * `selected_optionals` são os `product_id` dos OPCIONAIS que o vendedor
 * marcou nesta venda. Os obrigatórios não vêm do formulário de propósito:
 * quem decide o que é obrigatório é o cadastro do kit, e aceitar essa
 * lista do navegador seria deixar o cliente escolher o que é obrigatório.
 */
export const addKitSchema = z.object({
  kit_id: z.string().uuid("Selecione um kit"),
  quantity_milli: quantityField,
  selected_optionals: z.array(z.string().uuid()).default([]),
});

export type AddKitInput = z.infer<typeof addKitSchema>;

/** Alteração de uma linha já no orçamento. */
export const updateItemSchema = z.object({
  quantity_milli: quantityField,
  discount_percent: itemDiscountField,
});

export type UpdateItemInput = z.infer<typeof updateItemSchema>;

export const quoteStatusSchema = z.enum([
  "draft",
  "sent",
  "approved",
  "rejected",
  "expired",
  "cancelled",
]);

export const quoteFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  status: z
    .enum(["all", "draft", "sent", "approved", "rejected", "expired", "cancelled"])
    .default("all"),
  customer: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  owner: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  sort: z.enum(["recent", "number", "total", "customer"]).default("recent"),
  page: z.coerce.number().int().min(1).default(1),
});

export type QuoteFilters = z.infer<typeof quoteFiltersSchema>;

/** Busca de item para adicionar ao orçamento. */
export const catalogSearchSchema = z.object({
  q: z.string().trim().max(120).optional(),
  aba: z.enum(["produtos", "kits"]).default("produtos"),
});

export type CatalogSearch = z.infer<typeof catalogSearchSchema>;

// ── Leitura de FormData ──────────────────────────────────────

const text = (formData: FormData, key: string) => (formData.get(key) as string | null) ?? "";

export function quoteHeaderFormData(formData: FormData) {
  return {
    customer_id: text(formData, "customer_id"),
    issue_date: text(formData, "issue_date") || undefined,
    valid_until: text(formData, "valid_until"),
    payment_terms: text(formData, "payment_terms"),
    delivery_terms: text(formData, "delivery_terms"),
    notes: text(formData, "notes"),
    internal_notes: text(formData, "internal_notes"),
  };
}

/** Percentual digitado em pt-BR ("12,5") -> número. `null` se inválido. */
export function parsePercent(input: string | null | undefined): number | null {
  if (input === null || input === undefined) return null;
  const cleaned = input.trim().replace(/\s|%/g, "").replace(",", ".");
  if (cleaned === "") return 0;
  if (!/^\d+(\.\d{1,4})?$/.test(cleaned)) return null;
  return Number(cleaned);
}

export function quoteCommercialFormData(formData: FormData) {
  return {
    discount_percent: parsePercent(text(formData, "discount_percent")) ?? -1,
    discount_amount_cents: parseMoneyToCents(text(formData, "discount_amount")) ?? 0,
    shipping_amount_cents: parseMoneyToCents(text(formData, "shipping_amount")) ?? 0,
  };
}

export function addProductFormData(formData: FormData) {
  return {
    product_id: text(formData, "product_id"),
    quantity_milli: parseQuantityToMilli(text(formData, "quantity")) ?? 0,
  };
}

export function addKitFormData(formData: FormData) {
  return {
    kit_id: text(formData, "kit_id"),
    quantity_milli: parseQuantityToMilli(text(formData, "quantity")) ?? 0,
    selected_optionals: formData
      .getAll("opcional")
      .filter((value): value is string => typeof value === "string"),
  };
}

export function updateItemFormData(formData: FormData) {
  return {
    quantity_milli: parseQuantityToMilli(text(formData, "quantity")) ?? 0,
    discount_percent: parsePercent(text(formData, "discount_percent")) ?? -1,
  };
}

/**
 * Composição do kit congelada em `quote_items.components_snapshot`.
 *
 * A coluna é `jsonb`: o TypeScript não tem como saber o que veio de lá. Em
 * vez de afirmar o formato com um cast, ele é CONFERIDO na leitura — o
 * snapshot é o que sustenta o histórico do orçamento, e um campo faltando
 * precisa aparecer aqui, não no PDF do cliente.
 */
export const kitComponentSnapshotSchema = z.object({
  product_id: z.string().nullable(),
  code: z.string(),
  name: z.string(),
  unit: z.string().nullable(),
  brand: z.string().nullable(),
  quantity_milli: z.number(),
  unit_price_cents: z.number(),
  item_type: z.enum(["required", "optional"]),
  selected: z.boolean(),
});

export const kitComponentsSnapshotSchema = z.array(kitComponentSnapshotSchema);
