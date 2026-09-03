import "server-only";

import * as repository from "./repository";
import type { MovementInput, SerialInput, StockFilters } from "./schema";
import type { MovementRow, SerialRow, StockPage, StockRow } from "./types";

/**
 * Regras de negócio de Estoque.
 *
 * A camada é fina de propósito: as regras que importam moram no banco —
 * o sinal por motivo, a recusa de `sale` à mão, a baixa no faturamento, a
 * imutabilidade do livro. O que sobra aqui é traduzir a recusa para a
 * linguagem de quem está na tela.
 */

export class BusinessError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BusinessError";
  }
}

function traduzir(error: unknown): never {
  const mensagem = error instanceof Error ? error.message : "";

  if (mensagem.includes("Somente administrador")) {
    throw new BusinessError("Somente administrador pode lançar movimento de estoque.");
  }
  if (mensagem.includes("nasce do pedido faturado")) {
    throw new BusinessError(
      "Saída por venda não se lança à mão: ela acontece sozinha quando o pedido é faturado.",
    );
  }
  if (mensagem.includes("Produto não encontrado")) {
    throw new BusinessError("Produto não encontrado.");
  }
  if (mensagem.includes("não se altera nem se apaga")) {
    throw new BusinessError(
      "Lançamento de estoque não se altera nem se apaga. Para corrigir, lance um ajuste.",
    );
  }
  if (mensagem.includes("duplicate key") || mensagem.includes("idx_product_serials_unique")) {
    throw new BusinessError("Este número de série já está cadastrado para este produto.");
  }
  if (mensagem.includes("não está disponível")) {
    throw new BusinessError("Este aparelho não está disponível — já saiu com outro pedido.");
  }
  if (mensagem.includes("não é do produto")) {
    throw new BusinessError("Este aparelho é de outro produto.");
  }
  if (mensagem.includes("se vincula ao faturar")) {
    throw new BusinessError("O aparelho se vincula ao pedido a partir do faturamento.");
  }
  if (mensagem.includes("não está vinculado")) {
    throw new BusinessError("Este aparelho não está vinculado a um pedido.");
  }
  if (mensagem.includes("row-level security")) {
    throw new BusinessError("Sem permissão para esta operação de estoque.");
  }
  throw error;
}

export function listStock(filters: StockFilters): Promise<StockPage> {
  return repository.findStock(filters);
}

export function getProductStock(productId: string): Promise<StockRow | null> {
  return repository.findStockByProduct(productId);
}

export function getMovements(productId: string): Promise<MovementRow[]> {
  return repository.findMovements(productId);
}

export function getSerials(productId: string): Promise<SerialRow[]> {
  return repository.findSerials(productId);
}

export function getAvailableSerials(productId: string) {
  return repository.findAvailableSerials(productId);
}

export function getSerialsByOrder(orderId: string) {
  return repository.findSerialsByOrder(orderId);
}

export async function registerMovement(input: MovementInput): Promise<string> {
  try {
    return await repository.registerMovement(input);
  } catch (error) {
    traduzir(error);
  }
}

export async function createSerial(input: SerialInput, userId: string): Promise<void> {
  try {
    await repository.insertSerial(input, userId);
  } catch (error) {
    traduzir(error);
  }
}

export async function assignSerial(serialId: string, orderItemId: string): Promise<void> {
  try {
    await repository.assignSerial(serialId, orderItemId);
  } catch (error) {
    traduzir(error);
  }
}

export async function releaseSerial(serialId: string): Promise<void> {
  try {
    await repository.releaseSerial(serialId);
  } catch (error) {
    traduzir(error);
  }
}

/**
 * O que a ficha do pedido precisa saber sobre aparelhos.
 *
 * Uma linha por item que exige série, com quantos faltam. Itens que não
 * exigem série não aparecem — mostrar "0 de 0" para uma mangueira é ruído.
 */
export type OrderSerialLine = {
  order_item_id: string;
  product_id: string;
  name: string;
  /** Quantos aparelhos aquele item vendeu. */
  needed: number;
  assigned: { id: string; serial: string }[];
  available: { id: string; serial: string }[];
};

export async function getOrderSerialPlan(
  orderId: string,
  items: { id: string; product_id: string | null; name_snapshot: string; quantity_milli: number }[],
): Promise<OrderSerialLine[]> {
  const comProduto = items.filter(
    (item): item is typeof item & { product_id: string } => item.product_id !== null,
  );
  const rastreados = await repository.findTrackedProductIds(comProduto.map((i) => i.product_id));
  const relevantes = comProduto.filter((item) => rastreados.has(item.product_id));
  if (relevantes.length === 0) return [];

  const vinculados = await repository.findSerialsByOrder(orderId);

  const linhas = await Promise.all(
    relevantes.map(async (item) => ({
      order_item_id: item.id,
      product_id: item.product_id,
      name: item.name_snapshot,
      needed: Math.round(item.quantity_milli / 1000),
      assigned: vinculados
        .filter((s) => s.order_item_id === item.id)
        .map((s) => ({ id: s.id, serial: s.serial })),
      available: await repository.findAvailableSerials(item.product_id),
    })),
  );

  return linhas;
}
