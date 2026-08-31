import "server-only";

import { QUANTITY_SCALE } from "@/lib/format/quantity";
import type { QuoteStatus, UserRole } from "@/types/db";
import * as kits from "@/modules/kits/service";
import * as products from "@/modules/products/service";
import * as repository from "./repository";
import type {
  AddKitInput,
  AddProductInput,
  CatalogSearch,
  QuoteCommercialInput,
  QuoteFilters,
  QuoteHeaderInput,
  UpdateItemInput,
} from "./schema";
import {
  ADMIN_ONLY_FROM,
  CATALOG_SEARCH_LIMIT,
  STATUS_TRANSITIONS,
  type KitCandidate,
  type KitComponentSnapshot,
  type KitConfiguration,
  type ProductCandidate,
  type QuoteItemView,
  type QuotePage,
  type QuoteView,
  type QuoteWithItems,
} from "./types";

/**
 * Regras de negócio de Orçamentos.
 * Sem React, sem Next, sem Supabase — só domínio.
 *
 * ────────────────────────────────────────────────────────────
 * A regra que manda em todas as outras: O ORÇAMENTO CONGELA.
 *
 * No instante em que um item entra, copiamos código, nome, unidade,
 * marca, preço e — no caso do kit — a composição inteira. A partir daí o
 * orçamento não consulta mais o cadastro para nada que apareça no
 * documento. Produto pode mudar de preço, de nome, ser desativado ou
 * excluído; kit pode ganhar e perder componentes: o orçamento emitido
 * continua exatamente como foi emitido.
 *
 * Por isso este arquivo lê `products` e `kits` apenas na ENTRADA do item.
 * Nenhuma função de leitura de orçamento toca o catálogo.
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

// ── Leitura ──────────────────────────────────────────────────

export function listQuotes(filters: QuoteFilters): Promise<QuotePage> {
  return repository.findMany(filters);
}

export function getQuote(id: string): Promise<QuoteView | null> {
  return repository.findById(id);
}

export async function getQuoteWithItems(id: string): Promise<QuoteWithItems | null> {
  const quote = await repository.findById(id);
  if (!quote) return null;
  const items = await repository.findItems(id);
  return { ...quote, items };
}

export function getCustomerOptions() {
  return repository.findCustomerOptions();
}

export function getOwnerOptions() {
  return repository.findOwnerOptions();
}

/**
 * O orçamento aceita alterações?
 *
 * Espelha `quote_is_editable()` do banco (migration 1700) — que é quem de
 * fato recusa a escrita. Aqui a regra existe para a mensagem ser
 * compreensível em vez de "permissão negada".
 */
export function quoteIsEditable(quote: QuoteView, role: UserRole, userId: string): boolean {
  if (role === "admin") return true;
  if (quote.owner_id !== userId) return false;
  return quote.status !== "approved" && quote.status !== "cancelled";
}

function assertEditable(quote: QuoteView, role: UserRole, userId: string) {
  if (quoteIsEditable(quote, role, userId)) return;

  if (quote.owner_id !== userId) {
    throw new BusinessError("Este orçamento é de outro vendedor.");
  }
  if (quote.status === "approved") {
    throw new BusinessError(
      "Orçamento aprovado não pode ser alterado. Peça a um administrador para reabri-lo.",
    );
  }
  throw new BusinessError("Orçamento cancelado não pode ser alterado. Reabra-o para editar.");
}

// ── Cabeçalho ────────────────────────────────────────────────

function toHeaderRecord(input: QuoteHeaderInput) {
  return {
    customer_id: input.customer_id,
    ...(input.issue_date ? { issue_date: input.issue_date } : {}),
    valid_until: input.valid_until ?? null,
    payment_terms: input.payment_terms ?? null,
    delivery_terms: input.delivery_terms ?? null,
    notes: input.notes ?? null,
    internal_notes: input.internal_notes ?? null,
  };
}

async function assertCustomerIsUsable(customerId: string) {
  const usable = await repository.customerIsUsable(customerId);
  if (!usable) {
    throw new BusinessError("O cliente selecionado está inativo ou não existe.", "customer_id");
  }
}

function assertValidityIsSane(input: QuoteHeaderInput) {
  if (!input.valid_until) return;
  const issue = input.issue_date ?? new Date().toISOString().slice(0, 10);
  if (input.valid_until < issue) {
    throw new BusinessError("A validade não pode ser anterior à data de emissão.", "valid_until");
  }
}

export async function createQuote(input: QuoteHeaderInput, ownerId: string): Promise<string> {
  await assertCustomerIsUsable(input.customer_id);
  assertValidityIsSane(input);
  return repository.insert(toHeaderRecord(input), ownerId);
}

export async function updateQuoteHeader(
  id: string,
  input: QuoteHeaderInput,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await repository.findById(id);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  assertEditable(quote, role, userId);

  await assertCustomerIsUsable(input.customer_id);
  assertValidityIsSane(input);
  await repository.updateHeader(id, toHeaderRecord(input), userId);
}

/**
 * Desconto e frete do orçamento.
 *
 * O total NÃO é recalculado aqui: gravar desconto ou frete dispara
 * `trg_quotes_recalc` no banco, que refaz subtotal e total. A aplicação
 * não tem como enviar um total — nem por engano, nem de propósito.
 */
export async function updateCommercialTerms(
  id: string,
  input: QuoteCommercialInput,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await repository.findById(id);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  assertEditable(quote, role, userId);

  await repository.updateCommercial(
    id,
    {
      discountPercent: input.discount_percent,
      discountAmountCents: input.discount_amount_cents,
      shippingAmountCents: input.shipping_amount_cents,
    },
    userId,
  );
}

// ── Status ───────────────────────────────────────────────────

export async function changeStatus(
  id: string,
  next: QuoteStatus,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await repository.findById(id);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  if (role !== "admin" && quote.owner_id !== userId) {
    throw new BusinessError("Este orçamento é de outro vendedor.");
  }

  if (quote.status === next) return;

  const permitidas = STATUS_TRANSITIONS[quote.status];
  if (!permitidas.includes(next)) {
    throw new BusinessError(`Um orçamento ${quote.status} não pode passar para ${next}.`);
  }
  if (ADMIN_ONLY_FROM.includes(quote.status) && role !== "admin") {
    throw new BusinessError("Somente um administrador reabre um orçamento aprovado.");
  }

  // Enviar exige conteúdo: proposta vazia não vai para o cliente.
  if (next === "sent") {
    const items = await repository.countItems(id);
    if (items === 0) {
      throw new BusinessError("Um orçamento sem itens não pode ser enviado.");
    }
  }

  await repository.updateStatus(id, next, userId);
}

/** Rascunho é descartável; o resto é histórico e só se cancela. */
export async function deleteDraft(id: string, role: UserRole, userId: string): Promise<void> {
  const quote = await repository.findById(id);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  if (role !== "admin" && quote.owner_id !== userId) {
    throw new BusinessError("Este orçamento é de outro vendedor.");
  }
  if (quote.status !== "draft") {
    throw new BusinessError(
      "Só rascunho pode ser descartado. Um orçamento que já circulou deve ser cancelado, não apagado.",
    );
  }
  await repository.discardDraft(id);
}

// ── Catálogo para montar o orçamento ─────────────────────────

export async function searchProducts(filters: CatalogSearch): Promise<ProductCandidate[]> {
  const page = await products.listProducts({
    q: filters.q,
    status: "active",
    sort: "name",
    page: 1,
  });

  return page.items.slice(0, CATALOG_SEARCH_LIMIT).map((product) => ({
    id: product.id,
    code: product.code,
    name: product.name,
    manufacturer_code: product.manufacturer_code,
    brand_name: product.brand_name,
    unit_code: product.unit_code,
    unit_allows_fraction: true, // conferido de verdade na hora de adicionar
    sale_price_cents: product.sale_price_cents,
  }));
}

/**
 * Kits que podem entrar num orçamento novo.
 *
 * `kitIsUsable()` é a função da Fase 3 — inativo e incompleto ficam de
 * fora pela MESMA regra usada no módulo de Kits, não por uma cópia dela.
 */
export async function searchUsableKits(filters: CatalogSearch): Promise<KitCandidate[]> {
  const page = await kits.listKits({ q: filters.q, status: "active", page: 1 });

  return page.items
    .filter((kit) => kits.kitIsUsable(kit))
    .slice(0, CATALOG_SEARCH_LIMIT)
    .map((kit) => ({
      id: kit.id,
      code: kit.code,
      name: kit.name,
      description: kit.description,
      is_active: kit.is_active,
      required_count: kit.required_count,
      optional_count: kit.optional_count,
      base_price_cents: kit.components_total_cents,
    }));
}

/** Um componente do kit vira snapshot. Preço do produto AGORA. */
function toComponentSnapshot(
  item: {
    product_id: string;
    product_code: string;
    product_name: string;
    unit_code: string | null;
    brand_name: string | null;
    quantity_milli: number;
    sale_price_cents: number;
    item_type: "required" | "optional";
  },
  selected: boolean,
): KitComponentSnapshot {
  return {
    product_id: item.product_id,
    code: item.product_code,
    name: item.product_name,
    unit: item.unit_code,
    brand: item.brand_name,
    quantity_milli: item.quantity_milli,
    unit_price_cents: item.sale_price_cents,
    item_type: item.item_type,
    selected,
  };
}

/** Tela de escolha dos opcionais, antes de o kit entrar no orçamento. */
export async function getKitConfiguration(kitId: string): Promise<KitConfiguration | null> {
  const kit = await kits.getKit(kitId);
  if (!kit) return null;

  const composition = await kits.getComposition(kitId);
  return {
    kit: {
      id: kit.id,
      code: kit.code,
      name: kit.name,
      description: kit.description,
      is_active: kit.is_active,
      required_count: kit.required_count,
      optional_count: kit.optional_count,
      base_price_cents: kit.components_total_cents,
    },
    required: composition.required.map((item) => toComponentSnapshot(item, true)),
    optional: composition.optional.map((item) => toComponentSnapshot(item, false)),
  };
}

// ── Itens ────────────────────────────────────────────────────

/** Quantidade fracionada só onde a unidade permite. Regra da Fase 1. */
function assertQuantityFitsUnit(quantityMilli: number, allowsFraction: boolean, nome: string) {
  if (!allowsFraction && quantityMilli % QUANTITY_SCALE !== 0) {
    throw new BusinessError(
      `A unidade de "${nome}" não aceita quantidade fracionada. Use um número inteiro.`,
      "quantity",
    );
  }
}

export async function addProductItem(
  quoteId: string,
  input: AddProductInput,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await repository.findById(quoteId);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  assertEditable(quote, role, userId);

  const product = await products.getProductForSale(input.product_id);
  if (!product) throw new BusinessError("Produto não encontrado.", "product_id");
  if (!product.is_active) {
    throw new BusinessError(
      `O produto ${product.code} está inativo e não pode entrar em um orçamento novo.`,
      "product_id",
    );
  }
  assertQuantityFitsUnit(input.quantity_milli, product.allows_fraction, product.name);

  const sortOrder = await repository.nextSortOrder(quoteId);
  // Aqui é o instante do congelamento.
  await repository.insertItem(
    quoteId,
    {
      kind: "product",
      product_id: product.id,
      kit_id: null,
      code_snapshot: product.code,
      name_snapshot: product.name,
      description_snapshot: product.description,
      unit_snapshot: product.unit_code,
      brand_snapshot: product.brand_name,
      image_url_snapshot: product.image_url,
      components: null,
      quantity_milli: input.quantity_milli,
      unit_price_cents: product.sale_price_cents,
      discount_percent: 0,
    },
    sortOrder,
  );
}

/** Preço de uma unidade do kit: obrigatórios + opcionais escolhidos. */
export function kitUnitPriceCents(components: KitComponentSnapshot[]): number {
  return components
    .filter((component) => component.selected)
    .reduce(
      (total, component) =>
        total + Math.round((component.quantity_milli * component.unit_price_cents) / QUANTITY_SCALE),
      0,
    );
}

export async function addKitItem(
  quoteId: string,
  input: AddKitInput,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await repository.findById(quoteId);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  assertEditable(quote, role, userId);

  const kit = await kits.getKit(input.kit_id);
  if (!kit) throw new BusinessError("Kit não encontrado.", "kit_id");
  if (!kits.kitIsUsable(kit)) {
    throw new BusinessError(
      kit.is_active
        ? `O kit ${kit.code} não tem nenhum item obrigatório e não pode ser vendido.`
        : `O kit ${kit.code} está inativo e não pode entrar em um orçamento novo.`,
      "kit_id",
    );
  }

  // Kit é um conjunto: meio kit não existe.
  assertQuantityFitsUnit(input.quantity_milli, false, kit.name);

  const composition = await kits.getComposition(input.kit_id);
  const escolhidos = new Set(input.selected_optionals);

  // Obrigatórios entram sempre — a lista NÃO vem do formulário, vem do
  // cadastro. Se viesse do navegador, o cliente escolheria o que é
  // obrigatório.
  const components: KitComponentSnapshot[] = [
    ...composition.required.map((item) => toComponentSnapshot(item, true)),
    ...composition.optional.map((item) => toComponentSnapshot(item, escolhidos.has(item.product_id))),
  ];

  const desconhecidos = [...escolhidos].filter(
    (id) => !composition.optional.some((item) => item.product_id === id),
  );
  if (desconhecidos.length > 0) {
    throw new BusinessError("Um dos opcionais escolhidos não pertence a este kit.", "kit_id");
  }

  const sortOrder = await repository.nextSortOrder(quoteId);
  await repository.insertItem(
    quoteId,
    {
      kind: "kit",
      product_id: null,
      kit_id: kit.id,
      code_snapshot: kit.code,
      name_snapshot: kit.name,
      description_snapshot: kit.description,
      unit_snapshot: null,
      brand_snapshot: null,
      image_url_snapshot: kit.image_url,
      components,
      quantity_milli: input.quantity_milli,
      unit_price_cents: kitUnitPriceCents(components),
      discount_percent: 0,
    },
    sortOrder,
  );
}

async function loadItemForWrite(itemId: string, role: UserRole, userId: string) {
  const item = await repository.findItem(itemId);
  if (!item) throw new BusinessError("Item não encontrado");

  const quote = await repository.findById(item.quote_id);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  assertEditable(quote, role, userId);

  return item;
}

export async function updateItem(
  itemId: string,
  input: UpdateItemInput,
  role: UserRole,
  userId: string,
): Promise<void> {
  const item = await loadItemForWrite(itemId, role, userId);

  if (item.kind === "kit") {
    assertQuantityFitsUnit(input.quantity_milli, false, item.name_snapshot);
  } else if (item.product_id) {
    // A regra da unidade é do PRODUTO, e a unidade não muda de natureza.
    // Se o produto sumiu do cadastro, o snapshot manda: aceita como está.
    const product = await products.getProductForSale(item.product_id);
    assertQuantityFitsUnit(input.quantity_milli, product?.allows_fraction ?? true, item.name_snapshot);
  }

  await repository.updateItem(itemId, {
    quantityMilli: input.quantity_milli,
    discountPercent: input.discount_percent,
  });
}

/**
 * Troca os opcionais de um kit JÁ no orçamento.
 *
 * Trabalha sobre o snapshot, não sobre o cadastro: os componentes e os
 * preços continuam sendo os do momento em que o kit entrou. Mudar de
 * ideia sobre um opcional não é motivo para repreçar a proposta inteira.
 */
export async function updateKitOptionals(
  itemId: string,
  selected: string[],
  role: UserRole,
  userId: string,
): Promise<void> {
  const item = await loadItemForWrite(itemId, role, userId);
  if (item.kind !== "kit" || !item.components) {
    throw new BusinessError("Este item não é um kit.");
  }

  const escolhidos = new Set(selected);
  const components = item.components.map((component) => ({
    ...component,
    selected:
      component.item_type === "required"
        ? true
        : component.product_id !== null && escolhidos.has(component.product_id),
  }));

  await repository.updateItem(itemId, {
    components,
    unitPriceCents: kitUnitPriceCents(components),
  });
}

export async function removeItem(itemId: string, role: UserRole, userId: string): Promise<void> {
  await loadItemForWrite(itemId, role, userId);
  await repository.deleteItem(itemId);
}

/** Quantidade efetiva de um componente: por kit × quantidade da linha. */
export function effectiveComponentQuantity(component: KitComponentSnapshot, item: QuoteItemView): number {
  return Math.round((component.quantity_milli * item.quantity_milli) / QUANTITY_SCALE);
}
