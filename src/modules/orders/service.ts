import "server-only";

import type { OrderStatus } from "@/types/db";
import { ORDER_STATUS_LABELS } from "@/config/labels";
import * as repository from "./repository";
import type { OrderFilters } from "./schema";
import { STATUS_TRANSITIONS, type OrderPage, type OrderView, type OrderWithItems } from "./types";

/**
 * Regra de negócio do Pedido de venda. Não fala com o Supabase direto e
 * não conhece React nem Next — o repository faz o acesso, as actions
 * fazem a fronteira.
 *
 * A regra central deste módulo é uma ausência: **não existe função que
 * altere o conteúdo comercial de um pedido**. Nem para administrador. Se
 * alguém precisar mudar o que foi vendido, o caminho é `renegotiate()`,
 * que cria um documento novo e deixa o pedido de origem intacto.
 */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

/**
 * Mensagens do banco reescritas para a linguagem do usuário.
 *
 * O banco é a autoridade — estas exceções vêm de gatilho e de RLS, não de
 * verificação nossa. Aqui só trocamos o texto técnico por um que diga o
 * que fazer.
 */
function traduzir(error: unknown): BusinessError {
  const raw = error instanceof Error ? error.message : String(error ?? "");

  if (/conteudo comercial/i.test(raw)) {
    return new BusinessError(
      "Pedido fechado não muda de conteúdo. Para alterar o que foi vendido, use Renegociar.",
    );
  }
  if (/So orcamento aprovado/i.test(raw)) {
    return new BusinessError("Só orçamento aprovado vira pedido.");
  }
  if (/ja gerou pedido/i.test(raw)) {
    return new BusinessError("Este orçamento já gerou um pedido.");
  }
  if (/Sem permissao/i.test(raw)) {
    return new BusinessError("Você não tem permissão para esta operação.");
  }
  if (/Transicao de situacao invalida/i.test(raw)) {
    return new BusinessError("Essa mudança de situação não é permitida.");
  }
  return new BusinessError("Não foi possível concluir a operação.");
}

export async function listOrders(filters: OrderFilters): Promise<OrderPage> {
  return repository.findMany(filters);
}

export async function getOwnerOptions() {
  return repository.findOwnerOptions();
}

export async function getOrder(id: string): Promise<OrderView | null> {
  return repository.findById(id);
}

export async function getOrderWithItems(id: string): Promise<OrderWithItems | null> {
  const order = await repository.findById(id);
  if (!order) return null;
  const items = await repository.findItems(id);
  return { ...order, items };
}

/** O pedido vivo deste orçamento, para a tela do orçamento saber o que mostrar. */
export async function orderForQuote(quoteId: string) {
  return repository.findByQuote(quoteId);
}

/** Situações que fazem sentido oferecer a partir da atual. */
export function availableTransitions(status: OrderStatus): OrderStatus[] {
  return STATUS_TRANSITIONS[status];
}

export async function changeStatus(id: string, next: OrderStatus, userId: string): Promise<void> {
  const order = await repository.findById(id);
  if (!order) throw new BusinessError("Pedido não encontrado.");

  if (order.status === next) return;

  if (!STATUS_TRANSITIONS[order.status].includes(next)) {
    throw new BusinessError(
      `${ORDER_STATUS_LABELS[order.status]} não passa direto para ${ORDER_STATUS_LABELS[next]}.`,
    );
  }

  try {
    await repository.updateStatus(id, next, userId);
  } catch (error) {
    throw traduzir(error);
  }
}

/**
 * Fecha o orçamento aprovado num pedido.
 *
 * Nenhuma verificação de status aqui: quem decide é a função no banco,
 * que roda como `security definer` e confere aprovação, permissão e
 * duplicidade numa transação só. Repetir a checagem aqui abriria a janela
 * entre a nossa leitura e a escrita dela.
 */
export async function createFromQuote(quoteId: string): Promise<string> {
  try {
    return await repository.createFromQuote(quoteId);
  } catch (error) {
    throw traduzir(error);
  }
}

/**
 * Reabre para renegociar: cria um orçamento NOVO em rascunho, com a mesma
 * composição e `revision + 1`, ligado ao pedido de origem.
 *
 * O pedido antigo NÃO é cancelado aqui — a renegociação pode não vingar, e
 * cancelar por conta própria destruiria um pedido válido. Cancelar é
 * decisão de quem está negociando, num segundo passo explícito.
 */
export async function renegotiate(orderId: string): Promise<string> {
  try {
    return await repository.createQuoteFrom(orderId);
  } catch (error) {
    throw traduzir(error);
  }
}
