import { z } from "zod";

/**
 * Filtros do relatório comercial.
 *
 * O período é sempre por **data de emissão** do orçamento, não pela data
 * em que foi aprovado: é assim que o vendedor pensa a própria carteira
 * ("o que eu propus em agosto"), e é o que mantém um orçamento no mesmo
 * mês do começo ao fim.
 */

export const PERIODOS = ["mes", "mes_anterior", "90dias", "ano", "personalizado"] as const;
export type Periodo = (typeof PERIODOS)[number];

export const PERIODO_LABELS: Record<Periodo, string> = {
  mes: "Este mês",
  mes_anterior: "Mês anterior",
  "90dias": "Últimos 90 dias",
  ano: "Este ano",
  personalizado: "Período personalizado",
};

export const reportFiltersSchema = z.object({
  periodo: z.enum(PERIODOS).default("mes"),
  /** Só usados quando `periodo = personalizado`. */
  de: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  ate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  /** Vazio = todos. O RLS decide o que "todos" significa para quem pergunta. */
  vendedor: z.string().uuid().optional(),
});

export type ReportFilters = z.infer<typeof reportFiltersSchema>;

const iso = (data: Date) => data.toISOString().slice(0, 10);

/** Converte o período escolhido em duas datas concretas. */
export function resolverIntervalo(filtros: ReportFilters, hoje = new Date()): { de: string; ate: string } {
  const ano = hoje.getUTCFullYear();
  const mes = hoje.getUTCMonth();

  switch (filtros.periodo) {
    case "mes":
      return { de: iso(new Date(Date.UTC(ano, mes, 1))), ate: iso(new Date(Date.UTC(ano, mes + 1, 0))) };
    case "mes_anterior":
      return { de: iso(new Date(Date.UTC(ano, mes - 1, 1))), ate: iso(new Date(Date.UTC(ano, mes, 0))) };
    case "90dias": {
      const inicio = new Date(hoje);
      inicio.setUTCDate(inicio.getUTCDate() - 89);
      return { de: iso(inicio), ate: iso(hoje) };
    }
    case "ano":
      return { de: iso(new Date(Date.UTC(ano, 0, 1))), ate: iso(new Date(Date.UTC(ano, 11, 31))) };
    case "personalizado": {
      const de = filtros.de ?? iso(new Date(Date.UTC(ano, mes, 1)));
      const ate = filtros.ate ?? iso(hoje);
      // Datas invertidas são um engano comum; trocar é mais útil que recusar.
      return de <= ate ? { de, ate } : { de: ate, ate: de };
    }
  }
}
