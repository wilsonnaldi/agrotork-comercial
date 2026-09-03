"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { orderStatusSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * Toda ação segue a mesma ordem: permissão → validação Zod → regra de
 * negócio → persistência. E nenhuma delas aceita item, preço, desconto ou
 * total: no pedido esses números não mudam mais. O que o navegador manda é
 * intenção — mover a situação, ou converter de um documento para o outro.
 */

const LIST_PATH = "/pedidos";
const QUOTES_PATH = "/orcamentos";

function revalidateOrder(id?: string) {
  revalidatePath(LIST_PATH);
  if (id) revalidatePath(`${LIST_PATH}/${id}`);
}

// ── Situação ─────────────────────────────────────────────────

export async function changeStatusAction(formData: FormData): Promise<void> {
  const user = await requirePermission("orders.write");

  const id = formData.get("id");
  const status = orderStatusSchema.safeParse(formData.get("status"));
  if (typeof id !== "string" || !id || !status.success) return;

  try {
    await service.changeStatus(id, status.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      revalidateOrder(id);
      redirect(`${LIST_PATH}/${id}?erro=${encodeURIComponent(error.message)}`);
    }
    throw error;
  }

  revalidateOrder(id);
  redirect(`${LIST_PATH}/${id}?situacao=1`);
}

// ── Conversões ───────────────────────────────────────────────

/** Chamada da tela do ORÇAMENTO aprovado: "Gerar pedido". */
export async function createOrderFromQuoteAction(formData: FormData): Promise<void> {
  await requirePermission("orders.write");

  const quoteId = formData.get("quote_id");
  if (typeof quoteId !== "string" || !quoteId) return;

  let orderId: string;
  try {
    orderId = await service.createFromQuote(quoteId);
  } catch (error) {
    if (error instanceof BusinessError) {
      revalidatePath(`${QUOTES_PATH}/${quoteId}`);
      redirect(`${QUOTES_PATH}/${quoteId}?erro=${encodeURIComponent(error.message)}`);
    }
    throw error;
  }

  revalidatePath(`${QUOTES_PATH}/${quoteId}`);
  revalidateOrder(orderId);
  redirect(`${LIST_PATH}/${orderId}?criado=1`);
}

/** Chamada da tela do PEDIDO: "Renegociar" — leva ao orçamento novo. */
export async function renegotiateAction(formData: FormData): Promise<void> {
  await requirePermission("orders.write");

  const orderId = formData.get("id");
  if (typeof orderId !== "string" || !orderId) return;

  let quoteId: string;
  try {
    quoteId = await service.renegotiate(orderId);
  } catch (error) {
    if (error instanceof BusinessError) {
      revalidateOrder(orderId);
      redirect(`${LIST_PATH}/${orderId}?erro=${encodeURIComponent(error.message)}`);
    }
    throw error;
  }

  revalidateOrder(orderId);
  revalidatePath(QUOTES_PATH);
  redirect(`${QUOTES_PATH}/${quoteId}/editar?renegociado=1`);
}
