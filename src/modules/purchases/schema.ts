import { z } from "zod";
import { parseMoneyToCents } from "@/lib/format/money";
import { parseQuantityToMilli } from "@/lib/format/quantity";
import { onlyDigits } from "@/lib/format";

/**
 * Validação de entrada do módulo Entrada de mercadoria.
 *
 * Dinheiro em centavos e quantidade em milésimos já na fronteira: o que
 * chega do formulário é texto pt-BR ("1.234,56"), e ele não passa daqui
 * como número de ponto flutuante.
 */

const money = (campo: string) =>
  z
    .string()
    .trim()
    .transform((valor) => (valor === "" ? 0 : (parseMoneyToCents(valor) ?? Number.NaN)))
    .refine((valor) => Number.isFinite(valor) && valor >= 0, `${campo} inválido`);

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo de ${max} caracteres`)
    .transform((valor) => (valor === "" ? undefined : valor))
    .optional();

export const purchaseSchema = z.object({
  supplier_id: z.string().uuid("Escolha o fornecedor"),
  condition_id: z.string().uuid("Escolha a condição de pagamento"),

  invoice_number: optionalText(30),
  invoice_series: optionalText(10),

  // 44 dígitos, ou nada. Aceitar 43 seria aceitar um erro de digitação
  // que só apareceria no dia de cruzar com o XML da NF-e.
  invoice_key: z
    .string()
    .trim()
    .transform((valor) => onlyDigits(valor))
    .transform((valor) => (valor === "" ? undefined : valor))
    .optional()
    .refine((valor) => valor === undefined || valor.length === 44, "A chave da NF-e tem 44 dígitos"),

  issue_date: z
    .string()
    .trim()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Data de emissão inválida"),

  freight_amount_cents: money("Frete"),
  other_amount_cents: money("Outras despesas"),
  discount_amount_cents: money("Desconto"),

  notes: optionalText(2000),
});

export type PurchaseInput = z.infer<typeof purchaseSchema>;

export function purchaseFormData(formData: FormData) {
  const text = (key: string) => ((formData.get(key) as string | null) ?? "").toString();
  const hoje = new Date().toISOString().slice(0, 10);
  return {
    supplier_id: text("supplier_id"),
    condition_id: text("condition_id"),
    invoice_number: text("invoice_number"),
    invoice_series: text("invoice_series"),
    invoice_key: text("invoice_key"),
    issue_date: text("issue_date") || hoje,
    freight_amount_cents: text("freight_amount"),
    other_amount_cents: text("other_amount"),
    discount_amount_cents: text("discount_amount"),
    notes: text("notes"),
  };
}

export const purchaseItemSchema = z.object({
  product_id: z.string().uuid("Escolha o produto"),
  quantity_milli: z
    .number()
    .int()
    .positive("A quantidade precisa ser maior que zero")
    .max(99_999_999_000, "Quantidade fora do razoável"),
  unit_cost_cents: z.number().int().min(0, "Custo inválido"),
  notes: optionalText(300),
});

export type PurchaseItemInput = z.infer<typeof purchaseItemSchema>;

export function purchaseItemFormData(formData: FormData) {
  const text = (key: string) => ((formData.get(key) as string | null) ?? "").toString();
  return {
    product_id: text("product_id"),
    quantity_milli: parseQuantityToMilli(text("quantity")) ?? 0,
    unit_cost_cents: parseMoneyToCents(text("unit_cost")) ?? -1,
    notes: text("notes"),
  };
}

export const purchaseFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  status: z.enum(["all", "draft", "received", "cancelled"]).default("all"),
  supplier: z.string().trim().uuid().optional().catch(undefined),
  page: z.coerce.number().int().min(1).default(1),
});

export type PurchaseFilters = z.infer<typeof purchaseFiltersSchema>;
