import { z } from "zod";
import { onlyDigits } from "@/lib/format";
import { isValidCNPJ, isValidCPF } from "@/lib/format/validators";
import { STATE_CODES } from "@/config/locale";

/**
 * Validação de entrada do módulo Clientes.
 *
 * Esta é a fronteira: tudo que chega do formulário passa por aqui
 * NO SERVIDOR, mesmo já tendo sido validado no navegador.
 */

/** Campo de texto opcional: "" vira undefined em vez de string vazia no banco. */
const optionalText = (max = 255) =>
  z
    .string()
    .trim()
    .max(max, `Máximo de ${max} caracteres`)
    .transform((value) => (value === "" ? undefined : value))
    .optional();

const optionalDigits = (min: number, max: number, message: string) =>
  z
    .string()
    .trim()
    .transform((value) => onlyDigits(value))
    .refine((value) => value === "" || (value.length >= min && value.length <= max), message)
    .transform((value) => (value === "" ? undefined : value))
    .optional();

export const personTypeSchema = z.enum(["individual", "company"]);

export const customerSchema = z
  .object({
    person_type: personTypeSchema.default("company"),

    name: z
      .string()
      .trim()
      .min(2, "Informe o nome ou razão social")
      .max(180, "Máximo de 180 caracteres"),

    trade_name: optionalText(180),

    document: z
      .string()
      .trim()
      .transform((value) => onlyDigits(value))
      .transform((value) => (value === "" ? undefined : value))
      .optional(),

    state_registration: optionalText(30),

    phone: optionalDigits(10, 11, "Telefone deve ter DDD + 8 ou 9 dígitos"),
    whatsapp: optionalDigits(10, 11, "WhatsApp deve ter DDD + 8 ou 9 dígitos"),

    email: z
      .string()
      .trim()
      .transform((value) => (value === "" ? undefined : value))
      .optional()
      .refine((value) => value === undefined || z.string().email().safeParse(value).success, {
        message: "E-mail inválido",
      }),

    address: optionalText(180),
    address_number: optionalText(20),
    address_complement: optionalText(80),
    district: optionalText(120),
    city: optionalText(120),

    state: z
      .string()
      .trim()
      .toUpperCase()
      .transform((value) => (value === "" ? undefined : value))
      .optional()
      .refine((value) => value === undefined || STATE_CODES.includes(value as never), {
        message: "UF inválida",
      }),

    zip_code: optionalDigits(8, 8, "CEP deve ter 8 dígitos"),

    notes: optionalText(2000),
    is_active: z.boolean().default(true),
  })
  // O documento precisa combinar com o tipo de pessoa — CPF para física, CNPJ para jurídica.
  .superRefine((data, ctx) => {
    if (!data.document) return;

    const expected = data.person_type === "individual" ? 11 : 14;
    const label = data.person_type === "individual" ? "CPF" : "CNPJ";

    if (data.document.length !== expected) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["document"],
        message: `${label} deve ter ${expected} dígitos`,
      });
      return;
    }

    const valid = data.person_type === "individual" ? isValidCPF(data.document) : isValidCNPJ(data.document);
    if (!valid) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["document"], message: `${label} inválido` });
    }
  });

export type CustomerInput = z.infer<typeof customerSchema>;

/** Filtros da listagem. Tudo opcional — a tela abre sem filtro nenhum. */
export const customerFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  state: z.string().trim().toUpperCase().max(2).optional(),
  status: z.enum(["all", "active", "inactive"]).default("active"),
  page: z.coerce.number().int().min(1).default(1),
});

export type CustomerFilters = z.infer<typeof customerFiltersSchema>;

/** Lê os campos do FormData no formato que o schema espera. */
export function customerFormData(formData: FormData) {
  const text = (key: string) => (formData.get(key) as string | null) ?? "";
  return {
    person_type: text("person_type") || "company",
    name: text("name"),
    trade_name: text("trade_name"),
    document: text("document"),
    state_registration: text("state_registration"),
    phone: text("phone"),
    whatsapp: text("whatsapp"),
    email: text("email"),
    address: text("address"),
    address_number: text("address_number"),
    address_complement: text("address_complement"),
    district: text("district"),
    city: text("city"),
    state: text("state"),
    zip_code: text("zip_code"),
    notes: text("notes"),
    is_active: formData.get("is_active") !== "false",
  };
}
