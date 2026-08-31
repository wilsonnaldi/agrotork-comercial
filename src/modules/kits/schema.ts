import { z } from "zod";

import { MAX_QUANTITY_MILLI, parseQuantityToMilli } from "@/lib/format/quantity";

/**
 * Validação do cadastro de KITS.
 *
 * Um kit é uma composição comercial de produtos. O que se valida aqui é o
 * CADASTRO — o que sempre entra e o que fica disponível como opção. A
 * escolha dos opcionais é feita pelo vendedor no orçamento e não passa
 * por este schema.
 */

export const kitSchema = z.object({
  code: z
    .string()
    .trim()
    .min(2, "Informe o código do kit")
    .max(30, "Máximo de 30 caracteres")
    .regex(/^[A-Za-z0-9][A-Za-z0-9\-_./]*$/, "Use letras, números, hífen, ponto ou barra")
    .transform((value) => value.toUpperCase()),

  name: z
    .string()
    .trim()
    .min(3, "Informe o nome do kit")
    .max(120, "Máximo de 120 caracteres"),

  description: z
    .string()
    .trim()
    .max(1000, "Máximo de 1000 caracteres")
    .transform((value) => (value === "" ? undefined : value))
    .optional(),

  is_active: z.boolean().default(true),
});

export type KitInput = z.infer<typeof kitSchema>;

/** Papel do componente. Mesmo domínio do enum `kit_item_type` do banco. */
export const kitItemTypeSchema = z.enum(["required", "optional"]);

/**
 * Quantidade em milésimos — as funções vivem em `lib/format/quantity.ts`,
 * porque Orçamentos precisa exatamente das mesmas. Reexportadas aqui para
 * quem já importava do módulo.
 */
export {
  QUANTITY_SCALE,
  MAX_QUANTITY_MILLI,
  parseQuantityToMilli,
  formatQuantity,
  milliToDecimalString,
} from "@/lib/format/quantity";

export const kitItemSchema = z.object({
  product_id: z.string().uuid("Selecione um produto"),
  item_type: kitItemTypeSchema,
  quantity_milli: z
    .number()
    .int()
    .positive("A quantidade deve ser maior que zero")
    .max(MAX_QUANTITY_MILLI, "Quantidade acima do limite"),
});

export type KitItemInput = z.infer<typeof kitItemSchema>;

export const kitFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  status: z.enum(["all", "active", "inactive"]).default("all"),
  page: z.coerce.number().int().min(1).default(1),
});

export type KitFilters = z.infer<typeof kitFiltersSchema>;

/** Filtros da busca de produto para adicionar ao kit. */
export const componentSearchSchema = z.object({
  q: z.string().trim().max(120).optional(),
  brand: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  category: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
});

export type ComponentSearch = z.infer<typeof componentSearchSchema>;

export function kitFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    code: text("code"),
    name: text("name"),
    description: text("description"),
    is_active: formData.get("is_active") !== "false",
  };
}

export function kitItemFormData(formData: FormData) {
  return {
    product_id: (formData.get("product_id") as string | null) ?? "",
    item_type: (formData.get("item_type") as string | null) ?? "required",
    quantity_milli: parseQuantityToMilli(formData.get("quantity") as string | null) ?? 0,
  };
}
