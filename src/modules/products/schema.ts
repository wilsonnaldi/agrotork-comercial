import { z } from "zod";
import { MAX_MONEY_CENTS, parseMoneyToCents } from "@/lib/format/money";

/**
 * Validação de entrada do módulo Produtos.
 *
 * Dinheiro entra como texto em pt-BR e sai daqui como **centavos inteiros**.
 * Nenhuma conta monetária acontece em ponto flutuante.
 */

const optionalText = (max = 255) =>
  z
    .string()
    .trim()
    .max(max, `Máximo de ${max} caracteres`)
    .transform((value) => (value === "" ? undefined : value))
    .optional();

const optionalUuid = z
  .string()
  .trim()
  .transform((value) => (value === "" ? undefined : value))
  .optional()
  .refine((value) => value === undefined || z.string().uuid().safeParse(value).success, {
    message: "Seleção inválida",
  });

/** Campo monetário: texto pt-BR -> centavos. */
const moneyCents = (label: string, { required = false } = {}) =>
  z
    .string()
    .trim()
    .transform((value, ctx) => {
      if (value === "") {
        if (required) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Informe o ${label}` });
          return z.NEVER;
        }
        return 0;
      }

      const cents = parseMoneyToCents(value);
      if (cents === null) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${label} inválido` });
        return z.NEVER;
      }
      if (cents < 0) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${label} não pode ser negativo` });
        return z.NEVER;
      }
      if (cents > MAX_MONEY_CENTS) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${label} acima do limite` });
        return z.NEVER;
      }
      return cents;
    });

export const productSchema = z
  .object({
    code: z
      .string()
      .trim()
      .min(1, "Informe o código")
      .max(40, "Máximo de 40 caracteres")
      .regex(/^[A-Za-z0-9][A-Za-z0-9._/-]*$/, "Use letras, números, ponto, hífen ou barra")
      .transform((value) => value.toUpperCase()),

    /**
     * Código original de fábrica. É a chave que o futuro importador usa
     * para casar catálogo, tabela de preços e cadastro — por isso é
     * guardado em maiúsculas e sem espaços nas pontas.
     */
    manufacturer_code: z
      .string()
      .trim()
      .max(60, "Máximo de 60 caracteres")
      .transform((value) => (value === "" ? undefined : value.toUpperCase()))
      .optional(),

    name: z.string().trim().min(2, "Informe o nome").max(180, "Máximo de 180 caracteres"),

    description: optionalText(2000),

    category_id: optionalUuid,
    brand_id: optionalUuid,

    unit_id: z.string().trim().uuid("Selecione a unidade de medida"),

    cost_price_cents: moneyCents("preço de custo"),
    sale_price_cents: moneyCents("preço de venda", { required: true }),

    image_url: z
      .string()
      .trim()
      .transform((value) => (value === "" ? undefined : value))
      .optional()
      .refine((value) => value === undefined || /^https?:\/\/\S+$/i.test(value), {
        message: "Informe um endereço começando com http:// ou https://",
      }),

    notes: optionalText(2000),
    is_active: z.boolean().default(true),
  })
  .superRefine((data, ctx) => {
    // Código de fabricante sem fabricante não identifica nada — o banco
    // tem a mesma checagem (chk_products_manufacturer_brand).
    if (data.manufacturer_code && !data.brand_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["brand_id"],
        message: "Selecione a marca para poder informar o código do fabricante",
      });
    }

    // Venda abaixo do custo é quase sempre erro de digitação. Não bloqueia
    // (promoção e queima de estoque existem), mas o service avisa.
    if (data.sale_price_cents === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["sale_price_cents"],
        message: "O preço de venda precisa ser maior que zero",
      });
    }
  });

export type ProductInput = z.infer<typeof productSchema>;

export const PRODUCT_SORTS = ["name", "code", "price", "recent"] as const;
export type ProductSort = (typeof PRODUCT_SORTS)[number];

export const productFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  brand: z.string().trim().optional(),
  category: z.string().trim().optional(),
  unit: z.string().trim().optional(),
  status: z.enum(["all", "active", "inactive"]).default("active"),
  sort: z.enum(PRODUCT_SORTS).default("name"),
  page: z.coerce.number().int().min(1).default(1),
});

export type ProductFilters = z.infer<typeof productFiltersSchema>;

/** Lê os campos do FormData no formato que o schema espera. */
export function productFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    code: text("code"),
    manufacturer_code: text("manufacturer_code"),
    name: text("name"),
    description: text("description"),
    category_id: text("category_id"),
    brand_id: text("brand_id"),
    unit_id: text("unit_id"),
    cost_price_cents: text("cost_price"),
    sale_price_cents: text("sale_price"),
    image_url: text("image_url"),
    notes: text("notes"),
    is_active: formData.get("is_active") !== "false",
  };
}
