import { z } from "zod";

/**
 * Validação do cadastro de UNIDADES de medida.
 *
 * O código é a identidade da unidade e é único. `LT` e `L` são unidades
 * **diferentes** enquanto ninguém decidir que são equivalentes — o
 * sistema não presume nada a respeito.
 */

export const unitSchema = z.object({
  code: z
    .string()
    .trim()
    .min(1, "Informe o código")
    .max(10, "Máximo de 10 caracteres")
    .regex(/^[A-Za-z0-9/²³]+$/, "Use apenas letras, números ou barra")
    .transform((value) => value.toUpperCase()),

  name: z
    .string()
    .trim()
    .min(2, "Informe o nome da unidade")
    .max(60, "Máximo de 60 caracteres"),

  /** Peso e volume aceitam fração; unidade e peça, não. */
  allows_fraction: z.boolean().default(false),

  is_active: z.boolean().default(true),
});

export type UnitInput = z.infer<typeof unitSchema>;

export const unitFiltersSchema = z.object({
  q: z.string().trim().max(60).optional(),
  status: z.enum(["all", "active", "inactive"]).default("all"),
  page: z.coerce.number().int().min(1).default(1),
});

export type UnitFilters = z.infer<typeof unitFiltersSchema>;

export function unitFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    code: text("code"),
    name: text("name"),
    allows_fraction: formData.get("allows_fraction") === "true",
    is_active: formData.get("is_active") !== "false",
  };
}
