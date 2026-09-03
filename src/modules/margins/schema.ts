import { z } from "zod";

/**
 * Validação da REGRA DE MARGEM por setor.
 *
 * O setor é a categoria. `category_id` nulo é a regra padrão, que vale
 * para produto ainda sem setor — ela existe justamente para que nenhum
 * produto fique fora de qualquer regra sem alguém perceber.
 */

export const MARGIN_MODES = ["markup", "margin"] as const;
export const COST_BASES = ["avista", "faturado", "maior"] as const;
export const ROUNDINGS = ["none", "ten", "hundred", "ninety"] as const;

export type MarginMode = (typeof MARGIN_MODES)[number];
export type CostBasis = (typeof COST_BASES)[number];
export type Rounding = (typeof ROUNDINGS)[number];

/** Rótulos em português, usados na tela e no resumo da regra. */
export const MODE_LABEL: Record<MarginMode, string> = {
  markup: "Markup sobre o custo",
  margin: "Margem sobre a venda",
};

export const BASIS_LABEL: Record<CostBasis, string> = {
  maior: "O maior dos dois custos",
  avista: "Custo à vista",
  faturado: "Custo faturado",
};

export const ROUNDING_LABEL: Record<Rounding, string> = {
  none: "Sem arredondar",
  ten: "Para a dezena acima",
  hundred: "Para a centena acima",
  ninety: "Terminar em 90",
};

/**
 * Aceita o percentual como o brasileiro digita: "30", "30,5", "30.5",
 * "30 %". Guarda com duas casas, que é a precisão da coluna.
 */
const percent = z
  .string()
  .trim()
  .min(1, "Informe o percentual")
  .transform((value) => value.replace(/[\s%]/g, "").replace(",", "."))
  .refine((value) => /^\d+(\.\d{1,2})?$/.test(value), "Use apenas números, com até duas casas")
  .transform(Number)
  .refine((value) => value <= 900, "No máximo 900%");

export const marginRuleSchema = z
  .object({
    /** Vazio = regra padrão (produto sem setor). */
    category_id: z.string().uuid().nullable(),
    mode: z.enum(MARGIN_MODES),
    percent,
    cost_basis: z.enum(COST_BASES),
    rounding: z.enum(ROUNDINGS),
    is_active: z.boolean(),
  })
  .refine((rule) => rule.mode === "markup" || rule.percent < 100, {
    // Margem de 100% sobre a venda é divisão por zero: preço infinito.
    // O banco também recusa; aqui a mensagem é legível antes de tentar.
    message: "Margem sobre a venda precisa ser menor que 100%",
    path: ["percent"],
  });

export type MarginRuleInput = z.infer<typeof marginRuleSchema>;

export function marginRuleFormData(formData: FormData) {
  const text = (key: string) => ((formData.get(key) as string | null) ?? "").trim();
  const category = text("category_id");
  return {
    category_id: category === "" ? null : category,
    mode: text("mode"),
    percent: text("percent"),
    cost_basis: text("cost_basis"),
    rounding: text("rounding"),
    is_active: formData.get("is_active") === "true",
  };
}
