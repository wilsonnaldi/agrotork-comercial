import "server-only";

import { marginPercent } from "@/lib/format/money";
import * as repository from "./repository";
import type { ProductFilters, ProductInput } from "./schema";
import type { CatalogOptions, ProductPage, ProductView } from "./types";

/**
 * Regras de negócio de Produtos.
 * Sem React, sem Next, sem Supabase — só domínio.
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

export function listProducts(filters: ProductFilters): Promise<ProductPage> {
  return repository.findMany(filters);
}

export function getProduct(id: string): Promise<ProductView | null> {
  return repository.findById(id);
}

export function getCatalogOptions(): Promise<CatalogOptions> {
  return repository.findCatalogOptions();
}

/** Produto pronto para virar item de orçamento, com a regra da unidade junto. */
export function getProductForSale(productId: string) {
  return repository.findForSale(productId);
}

export function countKitUsage(productId: string): Promise<number> {
  return repository.countKitUsage(productId);
}

/**
 * Margem é sempre **derivada** de custo e preço de venda.
 * Nunca é gravada: assim não existe estado em que margem, custo e preço
 * discordem entre si. O formulário usa a margem só como atalho para
 * calcular o preço de venda; o que se persiste são os dois preços.
 */
export function computeMargin(costCents: number | null, saleCents: number | null): number | null {
  return marginPercent(costCents, saleCents);
}

/** Código é único entre produtos não excluídos. */
async function assertCodeIsFree(code: string, exceptId?: string) {
  const existing = await repository.findByCode(code, exceptId);
  if (existing) {
    throw new BusinessError(`O código ${code.toUpperCase()} já está em uso por "${existing.name}".`, "code");
  }
}

/** Código de fabricante é único por marca. */
async function assertManufacturerCodeIsFree(input: ProductInput, exceptId?: string) {
  if (!input.manufacturer_code || !input.brand_id) return;

  const existing = await repository.findByManufacturerCode(
    input.brand_id,
    input.manufacturer_code,
    exceptId,
  );
  if (existing) {
    throw new BusinessError(
      `O código de fabricante ${input.manufacturer_code} já está em uso nesta marca pelo produto ${existing.code} — "${existing.name}".`,
      "manufacturer_code",
    );
  }
}

/**
 * Marca, categoria ou unidade desativada não entra em produto novo.
 *
 * A regra vale só para o que MUDOU: um produto que já usava um cadastro
 * hoje desativado continua salvável — desativar preserva vínculo e
 * histórico, não invalida o que existe.
 */
async function assertReferencesUsable(input: ProductInput, current?: ProductView | null) {
  const status = await repository.checkReferencesActive({
    brandId: input.brand_id && input.brand_id !== current?.brand_id ? input.brand_id : null,
    categoryId: input.category_id && input.category_id !== current?.category_id ? input.category_id : null,
    unitId: input.unit_id && input.unit_id !== current?.unit_id ? input.unit_id : null,
  });

  if (!status.brand) {
    throw new BusinessError("A marca selecionada está inativa. Reative-a ou escolha outra.", "brand_id");
  }
  if (!status.category) {
    throw new BusinessError(
      "A categoria selecionada está inativa. Reative-a ou escolha outra.",
      "category_id",
    );
  }
  if (!status.unit) {
    throw new BusinessError("A unidade selecionada está inativa. Reative-a ou escolha outra.", "unit_id");
  }
}

function toRecord(input: ProductInput) {
  return {
    code: input.code,
    manufacturer_code: input.manufacturer_code ?? null,
    name: input.name,
    description: input.description ?? null,
    category_id: input.category_id ?? null,
    brand_id: input.brand_id ?? null,
    unit_id: input.unit_id,
    sale_price_cents: input.sale_price_cents,
    image_url: input.image_url ?? null,
    notes: input.notes ?? null,
    is_active: input.is_active,
  };
}

export async function createProduct(input: ProductInput, userId: string): Promise<string> {
  await assertCodeIsFree(input.code);
  await assertManufacturerCodeIsFree(input);
  await assertReferencesUsable(input);

  const id = await repository.insert(toRecord(input), userId);

  // O custo é opcional; só grava quando informado. A escrita passa pelo
  // RLS de `product_costs`, então um vendedor jamais chega aqui.
  if (input.cost_price_cents > 0) {
    await repository.upsertCost(id, input.cost_price_cents, userId);
  }

  return id;
}

export async function updateProduct(id: string, input: ProductInput, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Produto não encontrado");

  await assertCodeIsFree(input.code, id);
  await assertManufacturerCodeIsFree(input, id);
  await assertReferencesUsable(input, current);
  await repository.update(id, toRecord(input), userId);

  // Só mexe no custo se algo mudou — evita reescrever a linha (e o
  // `updated_by`) a cada salvamento de dados cadastrais.
  if (input.cost_price_cents !== (current.cost_price_cents ?? 0)) {
    await repository.upsertCost(id, input.cost_price_cents, userId);
  }
}

/**
 * Produto não é excluído: é desativado.
 * Some das seleções comerciais, continua no histórico e nos kits.
 */
export async function setProductActive(id: string, isActive: boolean, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Produto não encontrado");

  await repository.setActive(id, isActive, userId);
}
