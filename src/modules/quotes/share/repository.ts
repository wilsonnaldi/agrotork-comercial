import "server-only";

import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import { dbValueToCents } from "@/lib/format/money";
import { dbValueToMilli } from "@/lib/format/quantity";
import { formatDocument } from "@/lib/format";
import { COMPANY } from "@/config/company";
import { QUOTE_STATUS_VALUES } from "@/types/db";
import type { QuoteShareToken } from "@/types/db";
import { kitComponentsSnapshotSchema } from "../schema";
import type { DocumentCompany, QuoteDocument } from "./document";

/**
 * Acesso a dados do compartilhamento e do documento comercial.
 *
 * A ESCRITA (gerar e revogar link) passa pela tabela, sob o RLS de 0800 —
 * a policy é a única autoridade sobre quem cria link para qual orçamento.
 * A LEITURA PÚBLICA passa pela função `get_shared_quote`, que é o único
 * caminho pelo qual um visitante sem login enxerga alguma coisa.
 */

// ── Dados da empresa: uma fonte só ───────────────────────────

const EMPTY_COMPANY: DocumentCompany = {
  legal_name: COMPANY.name,
  trade_name: COMPANY.name,
  document: null,
  phone: null,
  whatsapp: null,
  email: null,
  address: null,
  city: COMPANY.city,
  state: COMPANY.state,
  zip_code: null,
  website: COMPANY.website,
  logo_url: null,
};

const text = (value: unknown): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
};

/**
 * Normaliza `app_settings.company`.
 *
 * Campo em branco vira `null` e simplesmente não aparece no documento —
 * é a regra "não inventar dado": se o administrador ainda não preencheu o
 * CNPJ, o PDF sai sem a linha do CNPJ, nunca com um valor de exemplo.
 */
export function toCompany(value: unknown): DocumentCompany {
  const raw = (value ?? {}) as Record<string, unknown>;
  return {
    legal_name: text(raw.legal_name) ?? EMPTY_COMPANY.legal_name,
    trade_name: text(raw.trade_name) ?? text(raw.legal_name) ?? EMPTY_COMPANY.trade_name,
    document: text(raw.document),
    phone: text(raw.phone),
    whatsapp: text(raw.whatsapp),
    email: text(raw.email),
    address: text(raw.address),
    city: text(raw.city) ?? EMPTY_COMPANY.city,
    state: text(raw.state) ?? EMPTY_COMPANY.state,
    zip_code: text(raw.zip_code),
    website: text(raw.website) ?? EMPTY_COMPANY.website,
    logo_url: text(raw.logo_url),
  };
}

export async function findCompany(): Promise<DocumentCompany> {
  const supabase = await createClient();
  const { data } = await supabase.from("app_settings").select("value").eq("key", "company").maybeSingle();
  return toCompany(data?.value);
}

// ── Links ────────────────────────────────────────────────────

export async function findTokens(quoteId: string): Promise<QuoteShareToken[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("quote_share_tokens")
    .select("*")
    .eq("quote_id", quoteId)
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);
  return data ?? [];
}

/**
 * Cria o link. O TOKEN não é gerado aqui: o default da coluna é
 * `encode(gen_random_bytes(24), 'hex')` — 24 bytes do gerador
 * criptográfico do PostgreSQL, 48 caracteres hex. Gerar do lado da
 * aplicação só acrescentaria uma chance de errar.
 */
export async function insertToken(
  quoteId: string,
  expiresAt: string | null,
  userId: string,
): Promise<QuoteShareToken> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("quote_share_tokens")
    .insert({ quote_id: quoteId, expires_at: expiresAt, created_by: userId })
    .select("*")
    .single();

  if (error) throw new Error(error.message);
  return data;
}

export async function revokeToken(tokenId: string): Promise<void> {
  const supabase = await createClient();
  // `revoked_at` não é filtrado por policy nenhuma, então este update
  // comum funciona — ao contrário do `deleted_at` de `quotes` (ver 1800).
  const { error } = await supabase
    .from("quote_share_tokens")
    .update({ revoked_at: new Date().toISOString() })
    .eq("id", tokenId);
  if (error) throw new Error(error.message);
}

export async function findTokenById(tokenId: string): Promise<QuoteShareToken | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("quote_share_tokens")
    .select("*")
    .eq("id", tokenId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

// ── Leitura pública ──────────────────────────────────────────

/**
 * Formato devolvido por `get_shared_quote` (migration 1900).
 *
 * A função devolve `jsonb`, então o cliente tipado entrega `Json` — o
 * TypeScript não tem como saber o que tem dentro. Este schema CONFERE o
 * conteúdo em vez de afirmá-lo: é a leitura que alimenta a página pública
 * e o PDF do cliente, e um campo fora do lugar precisa virar 404, não uma
 * página com "undefined" impresso.
 *
 * O dinheiro chega como texto de propósito (`::text` na migration), para
 * não passar por ponto flutuante no caminho.
 */
const sharedPayloadSchema = z.object({
  number: z.string(),
  status: z.enum(QUOTE_STATUS_VALUES),
  issue_date: z.string(),
  valid_until: z.string().nullable().default(null),
  payment_terms: z.string().nullable().default(null),
  delivery_terms: z.string().nullable().default(null),
  notes: z.string().nullable().default(null),
  subtotal: z.string(),
  discount_percent: z.string(),
  discount_amount: z.string(),
  shipping_amount: z.string(),
  total: z.string(),
  owner_name: z.string().nullable().default(null),
  customer: z
    .object({
      name: z.string(),
      document: z.string().nullable().default(null),
      city: z.string().nullable().default(null),
      state: z.string().nullable().default(null),
    })
    .nullable()
    .default(null),
  items: z
    .array(
      z.object({
        kind: z.enum(["product", "kit", "custom"]),
        code: z.string().nullable().default(null),
        name: z.string(),
        description: z.string().nullable().default(null),
        unit: z.string().nullable().default(null),
        brand: z.string().nullable().default(null),
        image_url: z.string().nullable().default(null),
        components: kitComponentsSnapshotSchema.nullable().default(null),
        quantity: z.string(),
        unit_price: z.string(),
        discount_percent: z.string(),
        line_total: z.string(),
      }),
    )
    .default([]),
  company: z.unknown(),
  commercially_expired: z.boolean().default(false),
});

/**
 * Documento comercial a partir do TOKEN, sem login.
 *
 * Devolve `null` para token inexistente, revogado, expirado, de orçamento
 * excluído ou de orçamento em situação que não circula — sem distinguir
 * entre os casos, para não confirmar a existência de nada a quem tenta
 * adivinhar.
 */
export async function findSharedDocument(token: string): Promise<QuoteDocument | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_shared_quote", { p_token: token });
  if (error) throw new Error(error.message);
  if (!data) return null;

  const parsed = sharedPayloadSchema.safeParse(data);
  if (!parsed.success) return null;
  const payload = parsed.data;

  return {
    number: payload.number,
    status: payload.status,
    issue_date: payload.issue_date,
    valid_until: payload.valid_until,
    payment_terms: payload.payment_terms,
    delivery_terms: payload.delivery_terms,
    notes: payload.notes,
    owner_name: payload.owner_name?.trim() || "—",
    customer: {
      name: payload.customer?.name ?? "—",
      document: payload.customer?.document ? formatDocument(payload.customer.document) : null,
      city: payload.customer?.city ?? null,
      state: payload.customer?.state ?? null,
      // A página pública não mostra endereço, telefone nem e-mail: o link
      // pode ser repassado a qualquer um.
      address: null,
      phone: null,
      email: null,
    },
    company: toCompany(payload.company),
    items: (payload.items ?? []).map((item) => ({
      kind: item.kind,
      code: item.code,
      name: item.name,
      description: item.description,
      unit: item.unit,
      brand: item.brand,
      image_url: item.image_url,
      components: item.components,
      quantity_milli: dbValueToMilli(item.quantity),
      unit_price_cents: dbValueToCents(item.unit_price) ?? 0,
      discount_percent: Number(item.discount_percent),
      line_total_cents: dbValueToCents(item.line_total) ?? 0,
    })),
    subtotal_cents: dbValueToCents(payload.subtotal) ?? 0,
    discount_percent: Number(payload.discount_percent),
    discount_amount_cents: dbValueToCents(payload.discount_amount) ?? 0,
    shipping_amount_cents: dbValueToCents(payload.shipping_amount) ?? 0,
    total_cents: dbValueToCents(payload.total) ?? 0,
    commercially_expired: payload.commercially_expired === true,
  };
}
