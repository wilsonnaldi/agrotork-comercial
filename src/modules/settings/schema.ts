import { z } from "zod";

/**
 * Dados da empresa que saem no PDF e na página pública do orçamento.
 *
 * Os campos são exatamente os de `DocumentCompany` (`modules/quotes/share/
 * document.ts`), porque é esse tipo que o documento comercial consome. Se
 * um campo for acrescentado lá, o TypeScript acusa aqui.
 *
 * Tudo é gravado em `app_settings` na chave `company`, como `jsonb`. Não há
 * tabela nova: a estrutura já existe desde a migration 0700.
 */

const opcional = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo de ${max} caracteres`)
    .optional()
    .transform((valor) => (valor && valor.length > 0 ? valor : null));

export const companySchema = z.object({
  /** Razão social. É o único campo realmente obrigatório do cabeçalho. */
  legal_name: z.string().trim().min(2, "Informe a razão social").max(120, "Máximo de 120 caracteres"),
  /** Nome fantasia. Vazio cai para a razão social na hora de exibir. */
  trade_name: opcional(80),
  document: opcional(18),
  phone: opcional(20),
  whatsapp: opcional(20),
  email: z
    .string()
    .trim()
    .max(120)
    .optional()
    .transform((valor) => (valor && valor.length > 0 ? valor : null))
    .refine((valor) => valor === null || z.string().email().safeParse(valor).success, "E-mail inválido"),
  address: opcional(160),
  city: opcional(80),
  state: opcional(2),
  zip_code: opcional(9),
  website: opcional(120),
});

export type CompanyInput = z.infer<typeof companySchema>;

export function companyFormData(formData: FormData) {
  const texto = (chave: string) => (formData.get(chave) as string | null) ?? "";
  return {
    legal_name: texto("legal_name"),
    trade_name: texto("trade_name"),
    document: texto("document"),
    phone: texto("phone"),
    whatsapp: texto("whatsapp"),
    email: texto("email"),
    address: texto("address"),
    city: texto("city"),
    state: texto("state").toUpperCase(),
    zip_code: texto("zip_code"),
    website: texto("website"),
  };
}

/** Limites do bucket `public-assets` (migration 2000). Repetidos aqui para
 *  recusar o arquivo ANTES de subir, com mensagem em português. */
export const LOGO_MAX_BYTES = 5 * 1024 * 1024;
export const LOGO_MIME = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"] as const;
