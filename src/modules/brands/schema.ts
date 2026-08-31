import { z } from "zod";

/**
 * Validação do cadastro de MARCAS.
 *
 * `brands` é a marca comercial que identifica o produto — não é
 * fornecedor nem distribuidor. Esses conceitos, quando existirem,
 * entram como cadastros próprios.
 */

export const brandSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Informe o nome da marca")
    .max(80, "Máximo de 80 caracteres"),

  description: z
    .string()
    .trim()
    .max(500, "Máximo de 500 caracteres")
    .transform((value) => (value === "" ? undefined : value))
    .optional(),

  is_active: z.boolean().default(true),
});

export type BrandInput = z.infer<typeof brandSchema>;

export const brandFiltersSchema = z.object({
  q: z.string().trim().max(80).optional(),
  status: z.enum(["all", "active", "inactive"]).default("all"),
  page: z.coerce.number().int().min(1).default(1),
});

export type BrandFilters = z.infer<typeof brandFiltersSchema>;

export function brandFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    name: text("name"),
    description: text("description"),
    is_active: formData.get("is_active") !== "false",
  };
}
