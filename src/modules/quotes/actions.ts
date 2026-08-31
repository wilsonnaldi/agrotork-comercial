"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import {
  collectFieldErrors,
  fail,
  rawValues,
  type FormState,
} from "@/lib/forms/action-state";
import {
  addKitFormData,
  addKitSchema,
  addProductFormData,
  addProductSchema,
  quoteCommercialFormData,
  quoteCommercialSchema,
  quoteHeaderFormData,
  quoteHeaderSchema,
  quoteStatusSchema,
  updateItemFormData,
  updateItemSchema,
} from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * Toda ação segue a mesma ordem: permissão → validação Zod → regra de
 * negócio → persistência. E nenhuma delas aceita `subtotal` ou `total`:
 * esses números são do banco. O que o navegador manda é intenção
 * (quantidade, desconto, quais opcionais), nunca resultado.
 */

const LIST_PATH = "/orcamentos";

function handleError(prev: FormState, error: unknown, formData: FormData, fallback: string): FormState {
  if (error instanceof BusinessError) {
    return fail(prev, {
      fieldErrors: error.field ? { [error.field]: error.message } : undefined,
      error: error.field ? undefined : error.message,
      values: rawValues(formData),
    });
  }
  return fail(prev, { error: fallback, values: rawValues(formData) });
}

function revalidateQuote(id?: string) {
  revalidatePath(LIST_PATH);
  if (id) {
    revalidatePath(`${LIST_PATH}/${id}`);
    revalidatePath(`${LIST_PATH}/${id}/editar`);
  }
}

// ── Cabeçalho ────────────────────────────────────────────────

export async function createQuoteAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const parsed = quoteHeaderSchema.safeParse(quoteHeaderFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createQuote(parsed.data, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível criar o orçamento.");
  }

  revalidateQuote(id);
  redirect(`${LIST_PATH}/${id}/editar?criado=1`);
}

export async function updateQuoteHeaderAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Orçamento não informado." });

  const parsed = quoteHeaderSchema.safeParse(quoteHeaderFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateQuoteHeader(id, parsed.data, user.profile.role, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar o cabeçalho.");
  }

  revalidateQuote(id);
  return { attempt: (prev.attempt ?? 0) + 1, values: { salvo: "1" } };
}

export async function updateCommercialAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Orçamento não informado." });

  const parsed = quoteCommercialSchema.safeParse(quoteCommercialFormData(formData));
  if (!parsed.success) {
    return fail(prev, {
      fieldErrors: collectFieldErrors(parsed.error.issues, /_cents$/),
      values: rawValues(formData),
    });
  }

  try {
    await service.updateCommercialTerms(id, parsed.data, user.profile.role, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível aplicar o desconto.");
  }

  revalidateQuote(id);
  return { attempt: (prev.attempt ?? 0) + 1, values: { salvo: "1" } };
}

// ── Itens ────────────────────────────────────────────────────

export async function addProductAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  if (typeof quoteId !== "string" || !quoteId) return fail(prev, { error: "Orçamento não informado." });

  const parsed = addProductSchema.safeParse(addProductFormData(formData));
  if (!parsed.success) {
    return fail(prev, {
      fieldErrors: collectFieldErrors(parsed.error.issues, /_milli$/),
      values: rawValues(formData),
    });
  }

  try {
    await service.addProductItem(quoteId, parsed.data, user.profile.role, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível adicionar o produto.");
  }

  revalidateQuote(quoteId);
  return { attempt: (prev.attempt ?? 0) + 1 };
}

export async function addKitAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  if (typeof quoteId !== "string" || !quoteId) return fail(prev, { error: "Orçamento não informado." });

  const parsed = addKitSchema.safeParse(addKitFormData(formData));
  if (!parsed.success) {
    return fail(prev, {
      fieldErrors: collectFieldErrors(parsed.error.issues, /_milli$/),
      values: rawValues(formData),
    });
  }

  try {
    await service.addKitItem(quoteId, parsed.data, user.profile.role, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível adicionar o kit.");
  }

  revalidateQuote(quoteId);
  redirect(`${LIST_PATH}/${quoteId}/editar?kit_adicionado=1`);
}

/** Uma linha do orçamento: alterar quantidade/desconto ou remover. */
export async function itemRowAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  const itemId = formData.get("item_id");
  const acao = formData.get("acao");
  if (typeof quoteId !== "string" || typeof itemId !== "string" || !quoteId || !itemId) {
    return fail(prev, { error: "Item não informado." });
  }

  try {
    if (acao === "remover") {
      await service.removeItem(itemId, user.profile.role, user.id);
    } else {
      const parsed = updateItemSchema.safeParse(updateItemFormData(formData));
      if (!parsed.success) {
        return fail(prev, { error: parsed.error.issues[0]?.message ?? "Valores inválidos." });
      }
      await service.updateItem(itemId, parsed.data, user.profile.role, user.id);
    }
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível alterar o item.");
  }

  revalidateQuote(quoteId);
  return { attempt: (prev.attempt ?? 0) + 1 };
}

/** Marca e desmarca opcionais de um kit que já está no orçamento. */
export async function updateKitOptionalsAction(
  prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const user = await requirePermission("quotes.write");

  const quoteId = formData.get("quote_id");
  const itemId = formData.get("item_id");
  if (typeof quoteId !== "string" || typeof itemId !== "string" || !quoteId || !itemId) {
    return fail(prev, { error: "Item não informado." });
  }

  const selecionados = formData
    .getAll("opcional")
    .filter((value): value is string => typeof value === "string");

  try {
    await service.updateKitOptionals(itemId, selecionados, user.profile.role, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível atualizar os opcionais.");
  }

  revalidateQuote(quoteId);
  redirect(`${LIST_PATH}/${quoteId}/editar?opcionais=1`);
}

// ── Situação ─────────────────────────────────────────────────

export async function changeStatusAction(formData: FormData): Promise<void> {
  const user = await requirePermission("quotes.write");

  const id = formData.get("id");
  const status = quoteStatusSchema.safeParse(formData.get("status"));
  if (typeof id !== "string" || !id || !status.success) return;

  try {
    await service.changeStatus(id, status.data, user.profile.role, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      revalidateQuote(id);
      redirect(`${LIST_PATH}/${id}?erro=${encodeURIComponent(error.message)}`);
    }
    throw error;
  }

  revalidateQuote(id);
  redirect(`${LIST_PATH}/${id}?status=1`);
}

export async function deleteDraftAction(formData: FormData): Promise<void> {
  const user = await requirePermission("quotes.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return;

  try {
    await service.deleteDraft(id, user.profile.role, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      redirect(`${LIST_PATH}/${id}?erro=${encodeURIComponent(error.message)}`);
    }
    throw error;
  }

  revalidateQuote(id);
  redirect(`${LIST_PATH}?descartado=1`);
}
