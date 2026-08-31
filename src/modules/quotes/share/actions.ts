"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePermission } from "@/lib/auth/session";
import { BusinessError } from "../service";
import * as service from "./service";

/**
 * Server Actions do compartilhamento.
 *
 * Só duas operações mudam estado — gerar e revogar link —, e as duas
 * verificam permissão, dono e situação do orçamento antes de escrever.
 * Nenhuma delas toca item, preço, desconto ou snapshot.
 */

const LIST_PATH = "/orcamentos";

/**
 * URL de base do link público.
 *
 * Vem do cabeçalho da requisição em vez de variável de ambiente porque o
 * sistema roda em domínios diferentes (local, prévia, produção) e o link
 * precisa apontar para onde o usuário realmente está.
 */
export async function currentBaseUrl(): Promise<string> {
  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "localhost:3000";
  const protocol = headerList.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${protocol}://${host}`;
}

function fail(quoteId: string, error: unknown): never {
  if (error instanceof BusinessError) {
    redirect(`${LIST_PATH}/${quoteId}?erro=${encodeURIComponent(error.message)}`);
  }
  throw error;
}

export async function createShareLinkAction(formData: FormData): Promise<void> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  if (typeof quoteId !== "string" || !quoteId) return;

  try {
    await service.createLink(quoteId, user.profile.role, user.id, await currentBaseUrl());
  } catch (error) {
    fail(quoteId, error);
  }

  revalidatePath(`${LIST_PATH}/${quoteId}`);
  revalidatePath(LIST_PATH);
  redirect(`${LIST_PATH}/${quoteId}?link=1`);
}

export async function revokeShareLinkAction(formData: FormData): Promise<void> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  const tokenId = formData.get("token_id");
  if (typeof quoteId !== "string" || typeof tokenId !== "string" || !quoteId || !tokenId) return;

  try {
    await service.revokeLink(tokenId, quoteId, user.profile.role, user.id);
  } catch (error) {
    fail(quoteId, error);
  }

  revalidatePath(`${LIST_PATH}/${quoteId}`);
  redirect(`${LIST_PATH}/${quoteId}?revogado=1`);
}
