import "server-only";

import type { KitItemType } from "@/types/db";
import * as repository from "./repository";
import {
  QUANTITY_SCALE,
  type ComponentSearch,
  type KitFilters,
  type KitInput,
  type KitItemInput,
} from "./schema";
import type { ComponentCandidate, KitComposition, KitPage, KitView } from "./types";

/**
 * Regras de negócio de Kits.
 * Sem React, sem Next, sem Supabase — só domínio.
 *
 * ────────────────────────────────────────────────────────────
 * A distinção que sustenta o módulo inteiro:
 *
 *   ITEM OPCIONAL DO KIT     — cadastro. Vive em `kit_items` com
 *                              `item_type = 'optional'`. Diz o que o
 *                              vendedor PODE escolher.
 *   ITEM SELECIONADO NO ORÇAMENTO — venda. Viverá em `quote_items`.
 *                              Diz o que o vendedor ESCOLHEU, com preço
 *                              congelado naquela data.
 *
 * Nada do que o vendedor fizer num orçamento altera o cadastro do kit, e
 * nada que o administrador mudar no kit altera um orçamento já emitido.
 * ────────────────────────────────────────────────────────────
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

export function listKits(filters: KitFilters): Promise<KitPage> {
  return repository.findMany(filters);
}

export function getKit(id: string): Promise<KitView | null> {
  return repository.findById(id);
}

export function getComposition(kitId: string): Promise<KitComposition> {
  return repository.findComposition(kitId);
}

export function countKitQuoteUsage(kitId: string): Promise<number> {
  return repository.countQuoteUsage(kitId);
}

export function searchComponents(kitId: string, filters: ComponentSearch): Promise<ComponentCandidate[]> {
  return repository.searchComponents(kitId, filters);
}

/**
 * Kit sem item obrigatório é INCOMPLETO.
 *
 * DECISÃO: criar um kit vazio é permitido — o cadastro é em dois passos, o
 * kit precisa existir para receber componentes, e exigir o contrário
 * obrigaria a um formulário monolítico que salva tudo de uma vez.
 *
 * Um kit incompleto, porém, não é vendável: a Fase 4 vai consultar esta
 * função para não oferecê-lo em orçamento. Até lá ele aparece marcado como
 * incompleto na listagem e na ficha — visível, não silencioso.
 */
export function kitIsUsable(kit: Pick<KitView, "is_active" | "required_count">): boolean {
  return kit.is_active && kit.required_count > 0;
}

async function assertCodeIsFree(code: string, exceptId?: string) {
  const existing = await repository.findByCode(code, exceptId);
  if (existing) {
    throw new BusinessError(`O código ${code.toUpperCase()} já está em uso pelo kit "${existing.name}".`, "code");
  }
}

export async function createKit(input: KitInput, userId: string): Promise<string> {
  await assertCodeIsFree(input.code);
  return repository.insert(
    {
      code: input.code,
      name: input.name,
      description: input.description ?? null,
      is_active: input.is_active,
    },
    userId,
  );
}

export async function updateKit(id: string, input: KitInput, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Kit não encontrado");

  await assertCodeIsFree(input.code, id);
  await repository.update(
    id,
    {
      code: input.code,
      name: input.name,
      description: input.description ?? null,
      is_active: input.is_active,
    },
    userId,
  );
}

/**
 * Kit não é excluído: é desativado.
 * Some das seleções comerciais, continua no histórico, mantém a composição
 * inteira e todos os produtos vinculados. O banco reforça: a FK de
 * `quote_items.kit_id` é `on delete restrict` desde a migration 1600.
 */
export async function setKitActive(id: string, isActive: boolean, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Kit não encontrado");
  await repository.update(id, { is_active: isActive }, userId);
}

// ── Composição ───────────────────────────────────────────────

/**
 * Quantidade fracionada só onde a unidade permite.
 * É a regra dos cadastros de apoio (Fase 1) valendo aqui: unidade que não
 * aceita fração — UN, PC, JG — não recebe 2,5.
 */
function assertQuantityFitsUnit(quantityMilli: number, allowsFraction: boolean, productName: string) {
  if (quantityMilli <= 0) {
    throw new BusinessError("A quantidade deve ser maior que zero.", "quantity");
  }
  if (!allowsFraction && quantityMilli % QUANTITY_SCALE !== 0) {
    throw new BusinessError(
      `A unidade de "${productName}" não aceita quantidade fracionada. Use um número inteiro.`,
      "quantity",
    );
  }
}

/**
 * Adiciona um componente ao kit.
 *
 * Recusa produto inexistente, produto desativado e produto que já está no
 * kit — este último porque `unique (kit_id, product_id)` é regra de
 * negócio, não detalhe de banco: o mesmo produto não pode ser obrigatório
 * e opcional ao mesmo tempo.
 */
export async function addComponent(kitId: string, input: KitItemInput): Promise<void> {
  const kit = await repository.findById(kitId);
  if (!kit) throw new BusinessError("Kit não encontrado");

  const product = await repository.findProductForKit(input.product_id);
  if (!product) throw new BusinessError("Produto não encontrado.", "product_id");
  if (!product.is_active) {
    throw new BusinessError(
      `O produto ${product.code} está inativo e não pode ser adicionado a um kit.`,
      "product_id",
    );
  }

  const existing = await repository.findItemByProduct(kitId, input.product_id);
  if (existing) {
    throw new BusinessError(
      `O produto ${product.code} já faz parte deste kit como ${
        existing.item_type === "required" ? "obrigatório" : "opcional"
      }. Altere o item existente em vez de adicioná-lo de novo.`,
      "product_id",
    );
  }

  assertQuantityFitsUnit(input.quantity_milli, product.allows_fraction, product.name);

  const sortOrder = await repository.nextSortOrder(kitId);
  await repository.insertItem(kitId, input.product_id, input.quantity_milli, input.item_type, sortOrder);
}

export async function changeComponentQuantity(itemId: string, quantityMilli: number): Promise<void> {
  const item = await repository.findItem(itemId);
  if (!item) throw new BusinessError("Componente não encontrado");

  const product = await repository.findProductForKit(item.product_id);
  // Produto desativado depois de entrar no kit continua editável: desativar
  // preserva o vínculo, não invalida o que já existe.
  assertQuantityFitsUnit(quantityMilli, product?.allows_fraction ?? true, product?.name ?? "produto");

  await repository.updateItem(itemId, { quantityMilli });
}

/** Alterna obrigatório ⇄ opcional. Só muda o cadastro; nenhum orçamento é tocado. */
export async function changeComponentType(itemId: string, itemType: KitItemType): Promise<void> {
  const item = await repository.findItem(itemId);
  if (!item) throw new BusinessError("Componente não encontrado");
  await repository.updateItem(itemId, { itemType });
}

/**
 * Remove um componente do CADASTRO do kit.
 *
 * Não há perda de histórico: um orçamento que já usou este kit guarda a
 * composição congelada em `quote_items.components_snapshot`. Mexer no
 * cadastro nunca reescreve venda passada.
 */
export async function removeComponent(itemId: string): Promise<void> {
  const item = await repository.findItem(itemId);
  if (!item) throw new BusinessError("Componente não encontrado");
  await repository.deleteItem(itemId);
}
