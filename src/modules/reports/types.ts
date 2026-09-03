import type { QuoteStatus } from "@/types/db";

/** Uma linha do resumo por situação. */
export type PorSituacao = {
  status: QuoteStatus;
  quantidade: number;
  total_cents: number;
};

/** Uma linha do resumo por vendedor. */
export type PorVendedor = {
  owner_id: string;
  owner_name: string;
  quantidade: number;
  total_cents: number;
  aprovados: number;
  aprovados_cents: number;
  /** Nulo quando nenhum orçamento do vendedor foi decidido no período. */
  conversao: number | null;
};

export type RelatorioComercial = {
  de: string;
  ate: string;
  /** Todos os orçamentos emitidos no período, exceto os descartados. */
  quantidade: number;
  total_cents: number;
  /** Só os aprovados — é o que virou negócio. */
  aprovados: number;
  aprovados_cents: number;
  /**
   * Aprovados ÷ decididos, em pontos percentuais.
   *
   * "Decidido" é aprovado, recusado ou expirado. Rascunho e enviado ainda
   * estão em aberto: contá-los como perda faria a taxa despencar só porque
   * a proposta é recente. Nulo quando nada foi decidido no período — é
   * diferente de zero por cento.
   */
  conversao: number | null;
  decididos: number;
  /** Valor médio do orçamento aprovado. Nulo quando não houve nenhum. */
  ticket_medio_cents: number | null;
  por_situacao: PorSituacao[];
  por_vendedor: PorVendedor[];
};
