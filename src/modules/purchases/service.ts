import "server-only";

import * as repository from "./repository";
import type { PurchaseFilters, PurchaseInput, PurchaseItemInput } from "./schema";
import { isEditable, type PurchasePage, type PurchaseWithItems } from "./types";

/**
 * Regras de negócio de Entrada de mercadoria.
 *
 * A regra pesada — rateio, estoque, custo, congelamento — mora no banco,
 * em `receive_purchase()`, porque as três escritas precisam acontecer na
 * mesma transação. Aqui ficam as recusas que fazem sentido antes de
 * chegar lá, e a tradução das que vêm de lá.
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

function traduzir(error: unknown): never {
  const mensagem = error instanceof Error ? error.message : "";

  if (mensagem.includes("idx_purchases_invoice")) {
    throw new BusinessError(
      "Esta nota deste fornecedor já foi lançada. Procure por ela na listagem.",
      "invoice_number",
    );
  }
  if (mensagem.includes("idx_purchase_items_unico")) {
    throw new BusinessError(
      "Este produto já está na nota. Some as quantidades na linha que já existe.",
      "product_id",
    );
  }
  if (mensagem.includes("Somente administrador")) {
    throw new BusinessError("Somente administrador trabalha com entrada de mercadoria.");
  }
  if (mensagem.includes("não muda de conteúdo")) {
    throw new BusinessError(
      "Nota já recebida não muda de conteúdo. Para corrigir, lance um ajuste no estoque.",
    );
  }
  if (mensagem.includes("Nota sem itens")) {
    throw new BusinessError("Adicione ao menos um item antes de dar entrada.");
  }
  if (mensagem.includes("já foi recebida")) {
    throw new BusinessError("Esta nota já foi recebida.");
  }
  if (mensagem.includes("já foi cancelada")) {
    throw new BusinessError("Esta nota foi cancelada.");
  }
  if (mensagem.includes("não se cancela")) {
    throw new BusinessError(
      "Nota já recebida não se cancela. Registre a devolução ao fornecedor no estoque.",
    );
  }
  if (mensagem.includes("Nota não encontrada")) {
    throw new BusinessError("Nota não encontrada.");
  }
  if (mensagem.includes("row-level security") || mensagem.includes("Sem permissão")) {
    throw new BusinessError("Sem permissão para esta operação.");
  }
  throw error;
}

export function listPurchases(filters: PurchaseFilters): Promise<PurchasePage> {
  return repository.findMany(filters);
}

export async function getPurchaseWithItems(id: string): Promise<PurchaseWithItems | null> {
  const nota = await repository.findById(id);
  if (!nota) return null;
  const items = await repository.findItems(id);
  return { ...nota, items };
}

export async function createPurchase(input: PurchaseInput, userId: string): Promise<string> {
  try {
    return await repository.insert(input, userId);
  } catch (error) {
    traduzir(error);
  }
}

export async function updatePurchase(
  id: string,
  input: PurchaseInput,
  userId: string,
): Promise<void> {
  const atual = await repository.findById(id);
  if (!atual) throw new BusinessError("Nota não encontrada.");
  if (!isEditable(atual.status)) {
    throw new BusinessError("Só rascunho se edita. Esta nota já foi recebida.");
  }

  try {
    await repository.update(id, input, userId);
  } catch (error) {
    traduzir(error);
  }
}

export async function addItem(purchaseId: string, input: PurchaseItemInput): Promise<void> {
  try {
    await repository.addItem(purchaseId, input);
  } catch (error) {
    traduzir(error);
  }
}

export async function removeItem(itemId: string): Promise<void> {
  try {
    await repository.removeItem(itemId);
  } catch (error) {
    traduzir(error);
  }
}

/**
 * O momento em que a nota vira estoque e vira custo. Devolve quantos
 * itens entraram, para a tela poder dizer o que aconteceu.
 */
export async function receivePurchase(id: string): Promise<number> {
  try {
    return await repository.receive(id);
  } catch (error) {
    traduzir(error);
  }
}

export async function cancelPurchase(id: string): Promise<void> {
  try {
    await repository.cancel(id);
  } catch (error) {
    traduzir(error);
  }
}

export const getSupplierOptions = repository.supplierOptions;
export const getConditionOptions = repository.conditionOptions;
export const getProductOptions = repository.productOptions;
