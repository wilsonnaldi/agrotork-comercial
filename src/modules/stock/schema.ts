import { z } from "zod";
import { parseSignedQuantityToMilli } from "@/lib/format/quantity";
import { MANUAL_REASONS } from "./types";

/**
 * Validação de entrada do módulo Estoque.
 *
 * A quantidade anda em MILÉSIMOS (inteiro), pelo mesmo motivo que o
 * dinheiro anda em centavos: `0.1 + 0.2 !== 0.3` vira meio litro perdido
 * no saldo. A conversão para string decimal acontece no repositório, na
 * fronteira com o Postgres.
 */

export const movementSchema = z.object({
  product_id: z.string().uuid("Produto inválido"),
  reason: z.enum(MANUAL_REASONS),
  quantity_milli: z
    .number()
    .int()
    .refine((value) => value !== 0, "Informe uma quantidade diferente de zero")
    .refine((value) => Math.abs(value) <= 1_000_000_000, "Quantidade fora do razoável"),
  notes: z
    .string()
    .trim()
    .max(500, "Máximo de 500 caracteres")
    .transform((value) => (value === "" ? undefined : value))
    .optional(),
});

export type MovementInput = z.infer<typeof movementSchema>;

export function movementFormData(formData: FormData) {
  const text = (key: string) => ((formData.get(key) as string | null) ?? "").toString();
  return {
    product_id: text("product_id"),
    reason: text("reason"),
    quantity_milli: parseSignedQuantityToMilli(text("quantity")) ?? 0,
    notes: text("notes"),
  };
}

/** Filtros da tela de estoque. */
export const stockFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  category: z.string().trim().uuid().optional().catch(undefined),
  /**
   * `negative` é o filtro que a tela abre sugerindo quando existe algo
   * negativo: é a lista do que precisa ser acertado.
   */
  situacao: z.enum(["all", "negative", "zero", "positive"]).default("all"),
  sort: z.enum(["name", "quantity", "recent"]).default("name"),
  page: z.coerce.number().int().min(1).default(1),
});

export type StockFilters = z.infer<typeof stockFiltersSchema>;

export const serialSchema = z.object({
  product_id: z.string().uuid("Produto inválido"),
  serial: z
    .string()
    .trim()
    .min(3, "Número de série muito curto")
    .max(80, "Máximo de 80 caracteres"),
  notes: z
    .string()
    .trim()
    .max(300)
    .transform((value) => (value === "" ? undefined : value))
    .optional(),
});

export type SerialInput = z.infer<typeof serialSchema>;
