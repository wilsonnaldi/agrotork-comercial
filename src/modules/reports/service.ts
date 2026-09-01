import "server-only";

import type { QuoteStatus } from "@/types/db";
import * as repository from "./repository";
import { resolverIntervalo, type ReportFilters } from "./schema";
import type { PorSituacao, PorVendedor, RelatorioComercial } from "./types";

/**
 * Situações que contam como DECIDIDAS.
 *
 * `draft` e `sent` ficam de fora: a proposta ainda está viva, e tratá-la
 * como perdida faria a taxa de conversão cair só porque foi emitida
 * ontem. `cancelled` também fica de fora — é desistência nossa, não
 * resposta do cliente, e misturar as duas coisas esconde qual é qual.
 */
const DECIDIDOS: readonly QuoteStatus[] = ["approved", "rejected", "expired"];

/** Aprovados ÷ decididos, em pontos percentuais com uma casa. */
function taxa(aprovados: number, decididos: number): number | null {
  if (decididos === 0) return null;
  return Math.round((aprovados / decididos) * 1000) / 10;
}

export async function getRelatorio(filtros: ReportFilters): Promise<RelatorioComercial> {
  const { de, ate } = resolverIntervalo(filtros);
  const linhas = await repository.findQuotesInPeriod(de, ate, filtros.vendedor);

  const situacoes = new Map<QuoteStatus, PorSituacao>();
  const vendedores = new Map<string, PorVendedor & { decididos: number }>();

  let total_cents = 0;
  let aprovados = 0;
  let aprovados_cents = 0;
  let decididos = 0;

  for (const linha of linhas) {
    total_cents += linha.total_cents;

    const situacao = situacoes.get(linha.status) ?? {
      status: linha.status,
      quantidade: 0,
      total_cents: 0,
    };
    situacao.quantidade += 1;
    situacao.total_cents += linha.total_cents;
    situacoes.set(linha.status, situacao);

    const vendedor = vendedores.get(linha.owner_id) ?? {
      owner_id: linha.owner_id,
      owner_name: linha.owner_name,
      quantidade: 0,
      total_cents: 0,
      aprovados: 0,
      aprovados_cents: 0,
      conversao: null,
      decididos: 0,
    };
    vendedor.quantidade += 1;
    vendedor.total_cents += linha.total_cents;

    if (linha.status === "approved") {
      aprovados += 1;
      aprovados_cents += linha.total_cents;
      vendedor.aprovados += 1;
      vendedor.aprovados_cents += linha.total_cents;
    }
    if (DECIDIDOS.includes(linha.status)) {
      decididos += 1;
      vendedor.decididos += 1;
    }

    vendedores.set(linha.owner_id, vendedor);
  }

  const porVendedor: PorVendedor[] = [...vendedores.values()]
    .map(({ decididos: decididosDoVendedor, ...resto }) => ({
      ...resto,
      conversao: taxa(resto.aprovados, decididosDoVendedor),
    }))
    .sort((a, b) => b.total_cents - a.total_cents);

  return {
    de,
    ate,
    quantidade: linhas.length,
    total_cents,
    aprovados,
    aprovados_cents,
    conversao: taxa(aprovados, decididos),
    decididos,
    ticket_medio_cents: aprovados > 0 ? Math.round(aprovados_cents / aprovados) : null,
    por_situacao: [...situacoes.values()].sort((a, b) => b.quantidade - a.quantidade),
    por_vendedor: porVendedor,
  };
}

export function listOwners() {
  return repository.findOwners();
}
