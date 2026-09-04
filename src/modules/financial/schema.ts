import { z } from "zod";
import { parseMoneyToCents } from "@/lib/format/money";

/**
 * Validação de entrada do módulo Financeiro.
 *
 * O valor da baixa aceita SINAL: negativo é estorno, e é assim que se
 * conserta uma baixa errada — a tabela é append-only.
 */

export const paymentSchema = z.object({
  entry_id: z.string().uuid(),
  amount_cents: z
    .number()
    .int()
    .refine((valor) => valor !== 0, "Informe um valor diferente de zero"),
  paid_on: z
    .string()
    .trim()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Data inválida"),
  method: z
    .string()
    .trim()
    .max(60)
    .transform((valor) => (valor === "" ? undefined : valor))
    .optional(),
  notes: z
    .string()
    .trim()
    .max(300)
    .transform((valor) => (valor === "" ? undefined : valor))
    .optional(),
});

export type PaymentInput = z.infer<typeof paymentSchema>;

export function paymentFormData(formData: FormData) {
  const text = (key: string) => ((formData.get(key) as string | null) ?? "").toString();
  const bruto = text("amount").trim();
  const negativo = bruto.startsWith("-");
  const cents = parseMoneyToCents(bruto.replace(/^[+-]/, ""));

  return {
    entry_id: text("entry_id"),
    paid_on: text("paid_on") || new Date().toISOString().slice(0, 10),
    method: text("method"),
    notes: text("notes"),
    amount_cents: cents === null ? 0 : negativo ? -cents : cents,
  };
}

export const splitSchema = z.object({
  entry_id: z.string().uuid(),
  installments: z.coerce
    .number()
    .int()
    .min(2, "O parcelamento vai de 2 a 60 vezes")
    .max(60, "O parcelamento vai de 2 a 60 vezes"),
  first_due: z
    .string()
    .trim()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Data inválida"),
  interval_days: z.coerce.number().int().min(1, "Intervalo inválido").max(365).default(30),
});

export type SplitInput = z.infer<typeof splitSchema>;

export const financialFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  kind: z.enum(["all", "receivable", "payable"]).default("receivable"),
  /**
   * `overdue` é a fatia que a tela abre sugerindo quando existe atraso:
   * é a lista do que precisa de telefonema hoje.
   */
  situacao: z.enum(["open", "overdue", "settled", "all"]).default("open"),
  page: z.coerce.number().int().min(1).default(1),
});

export type FinancialFilters = z.infer<typeof financialFiltersSchema>;
