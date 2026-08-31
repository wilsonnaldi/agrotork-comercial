import "server-only";

import { formatDocument, formatPhone, formatZipCode } from "@/lib/format";
import * as customers from "@/modules/customers/service";
import type { QuoteShareToken, UserRole } from "@/types/db";
import { BusinessError, changeStatus, getQuoteWithItems } from "../service";
import type { QuoteDocument } from "./document";
import * as repository from "./repository";

/**
 * Regras do compartilhamento e do documento comercial.
 *
 * ────────────────────────────────────────────────────────────
 * COMPARTILHAR É SOMENTE LEITURA.
 *
 * Gerar ou abrir um link não altera preço, item, desconto nem snapshot.
 * A única coisa que muda ao gerar o primeiro link de um RASCUNHO é o
 * status, que passa a `sent` — porque compartilhar É enviar, e essa é a
 * regra que o ROADMAP definiu na Fase 0 ("marcar automaticamente como
 * Enviado ao compartilhar"). A transição usa `changeStatus` do módulo,
 * não uma segunda regra paralela: valem a matriz de transições e o RLS.
 *
 * Abrir o link não muda nada: só incrementa `view_count`.
 * ────────────────────────────────────────────────────────────
 */

/** Validade padrão do link quando o orçamento não tem validade comercial. */
const DEFAULT_TOKEN_DAYS = 30;

export type ShareLink = {
  id: string;
  token: string;
  url: string;
  created_at: string;
  expires_at: string | null;
  revoked_at: string | null;
  view_count: number;
  /** Vencido tecnicamente: não abre mais. */
  is_expired: boolean;
  is_active: boolean;
};

export function publicPath(token: string): string {
  return `/orcamento-publico/${token}`;
}

function toLink(row: QuoteShareToken, baseUrl: string): ShareLink {
  const isExpired = row.expires_at !== null && new Date(row.expires_at).getTime() < Date.now();
  return {
    id: row.id,
    token: row.token,
    url: `${baseUrl}${publicPath(row.token)}`,
    created_at: row.created_at,
    expires_at: row.expires_at,
    revoked_at: row.revoked_at,
    view_count: row.view_count,
    is_expired: isExpired,
    is_active: row.revoked_at === null && !isExpired,
  };
}

export async function listLinks(quoteId: string, baseUrl: string): Promise<ShareLink[]> {
  const rows = await repository.findTokens(quoteId);
  return rows.map((row) => toLink(row, baseUrl));
}

/**
 * Situações que circulam. Espelha `quote_is_shareable()` do banco —
 * a função é `immutable` lá e a lista está aqui só para a mensagem de
 * erro ser compreensível.
 */
const SHAREABLE = new Set(["sent", "approved", "expired"]);

/**
 * Valade do TOKEN, que não se confunde com a validade COMERCIAL.
 *
 * O token acompanha a validade da proposta quando ela existe — não faz
 * sentido um link vivo para sempre. Sem validade comercial definida,
 * 30 dias. Passado esse prazo o link deixa de abrir; a proposta em si
 * continua no sistema, e um link novo pode ser gerado.
 */
function defaultExpiry(validUntil: string | null): string {
  if (validUntil) {
    // Fim do dia da validade, no fuso de Brasília (UTC−3).
    return new Date(`${validUntil}T23:59:59-03:00`).toISOString();
  }
  const date = new Date();
  date.setDate(date.getDate() + DEFAULT_TOKEN_DAYS);
  return date.toISOString();
}

export async function createLink(
  quoteId: string,
  role: UserRole,
  userId: string,
  baseUrl: string,
): Promise<ShareLink> {
  const quote = await getQuoteWithItems(quoteId);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  if (role !== "admin" && quote.owner_id !== userId) {
    throw new BusinessError("Este orçamento é de outro vendedor.");
  }

  // Rascunho: compartilhar é enviar. `changeStatus` recusa orçamento sem
  // itens, então não existe link para proposta vazia.
  if (quote.status === "draft") {
    await changeStatus(quoteId, "sent", role, userId);
  } else if (!SHAREABLE.has(quote.status)) {
    throw new BusinessError(
      quote.status === "cancelled"
        ? "Orçamento cancelado não circula. Reabra-o antes de compartilhar."
        : "Orçamento recusado não circula. Reabra-o antes de compartilhar.",
    );
  }

  const row = await repository.insertToken(quoteId, defaultExpiry(quote.valid_until), userId);
  return toLink(row, baseUrl);
}

export async function revokeLink(
  tokenId: string,
  quoteId: string,
  role: UserRole,
  userId: string,
): Promise<void> {
  const quote = await getQuoteWithItems(quoteId);
  if (!quote) throw new BusinessError("Orçamento não encontrado");
  if (role !== "admin" && quote.owner_id !== userId) {
    throw new BusinessError("Este orçamento é de outro vendedor.");
  }

  const token = await repository.findTokenById(tokenId);
  // O RLS já impede enxergar token de orçamento alheio; esta conferência
  // fecha a porta de um id de token colado de outro orçamento.
  if (!token || token.quote_id !== quoteId) {
    throw new BusinessError("Link não encontrado neste orçamento.");
  }

  await repository.revokeToken(tokenId);
}

// ── Documento comercial ──────────────────────────────────────

/**
 * Monta o documento a partir do orçamento AUTENTICADO.
 *
 * Tudo o que descreve mercadoria vem de snapshot: `code_snapshot`,
 * `name_snapshot`, `unit_snapshot`, `brand_snapshot`, `components_snapshot`
 * e `unit_price`. Nenhuma consulta a `products`, `kits` ou `kit_items`.
 *
 * O que NÃO é snapshot, e por quê: os dados do CLIENTE e da EMPRESA são
 * lidos ao vivo. O orçamento nunca congelou cadastro de cliente — se o
 * endereço mudou, a proposta reemitida deve sair com o endereço certo.
 * Está documentado como limitação conhecida no ARCHITECTURE.md.
 */
export async function buildDocument(
  quoteId: string,
  role: UserRole,
  userId: string,
): Promise<QuoteDocument | null> {
  const quote = await getQuoteWithItems(quoteId);
  if (!quote) return null;
  if (role !== "admin" && quote.owner_id !== userId) return null;

  // O cadastro do cliente é lido pelo SERVICE de Clientes, não por
  // consulta direta: quem sabe o que é um cliente é aquele módulo.
  const [company, customer] = await Promise.all([
    repository.findCompany(),
    customers.getCustomer(quote.customer_id),
  ]);

  const enderecoCliente = [
    customer?.address,
    customer?.address_number,
    customer?.address_complement,
    customer?.district,
  ]
    .filter((parte): parte is string => Boolean(parte && parte.trim()))
    .join(", ");

  return {
    number: quote.number,
    status: quote.status,
    issue_date: quote.issue_date,
    valid_until: quote.valid_until,
    payment_terms: quote.payment_terms,
    delivery_terms: quote.delivery_terms,
    notes: quote.notes,
    owner_name: quote.owner_name,
    customer: {
      // O PDF é o documento que o vendedor envia deliberadamente ao
      // próprio cliente, então leva o bloco completo de identificação.
      // A página PÚBLICA leva menos: ver `findSharedDocument`.
      name: customer?.name ?? quote.customer_name,
      document: customer?.document ? formatDocument(customer.document) : null,
      city: customer?.city ?? quote.customer_city,
      state: customer?.state ?? null,
      address:
        [enderecoCliente, customer?.zip_code ? `CEP ${formatZipCode(customer.zip_code)}` : null]
          .filter(Boolean)
          .join(" · ") || null,
      phone: customer?.phone ? formatPhone(customer.phone) : null,
      email: customer?.email ?? null,
    },
    company,
    items: quote.items.map((item) => ({
      kind: item.kind,
      code: item.code_snapshot,
      name: item.name_snapshot,
      description: item.description_snapshot,
      unit: item.unit_snapshot,
      brand: item.brand_snapshot,
      image_url: null,
      components: item.components,
      quantity_milli: item.quantity_milli,
      unit_price_cents: item.unit_price_cents,
      discount_percent: item.discount_percent,
      line_total_cents: item.line_total_cents,
    })),
    subtotal_cents: quote.subtotal_cents,
    discount_percent: quote.discount_percent,
    discount_amount_cents: quote.discount_amount_cents,
    shipping_amount_cents: quote.shipping_amount_cents,
    total_cents: quote.total_cents,
    commercially_expired:
      quote.valid_until !== null && quote.valid_until < new Date().toISOString().slice(0, 10),
  };
}

/** Documento a partir do TOKEN, sem login. */
export function getSharedDocument(token: string): Promise<QuoteDocument | null> {
  return repository.findSharedDocument(token);
}
