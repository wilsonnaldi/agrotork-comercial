import { z } from "zod";

/** Validação do cadastro de CATEGORIAS de produto. */

export const categorySchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Informe o nome da categoria")
    .max(80, "Máximo de 80 caracteres"),

  description: z
    .string()
    .trim()
    .max(500, "Máximo de 500 caracteres")
    .transform((value) => (value === "" ? undefined : value))
    .optional(),

  is_active: z.boolean().default(true),
});

export type CategoryInput = z.infer<typeof categorySchema>;

export const categoryFiltersSchema = z.object({
  q: z.string().trim().max(80).optional(),
  status: z.enum(["all", "active", "inactive"]).default("all"),
  page: z.coerce.number().int().min(1).default(1),
});

export type CategoryFilters = z.infer<typeof categoryFiltersSchema>;

export function categoryFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    name: text("name"),
    description: text("description"),
    is_active: formData.get("is_active") !== "false",
  };
}
