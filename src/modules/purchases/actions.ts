"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import {
  purchaseFormData,
  purchaseItemFormData,
  purchaseItemSchema,
  purchaseSchema,
} from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * Tudo aqui é `purchases.manage`, do administrador: uma nota de entrada é
 * custo da primeira à última linha.
 */

export type PurchaseFormState = {
  error?: string;
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  attempt?: number;
};

function fail(prev: PurchaseFormState, patch: Omit<PurchaseFormState, "attempt">): PurchaseFormState {
  return { ...patch, attempt: (prev.attempt ?? 0) + 1 };
}

function collectFieldErrors(issues: { path: PropertyKey[]; message: string }[]) {
  const fieldErrors: Record<string, string> = {};
  for (const issue of issues) {
    const key = issue.path[0];
    if (typeof key === "string" && !fieldErrors[key]) fieldErrors[key] = issue.message;
  }
  return fieldErrors;
}

function rawValues(formData: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === "string") values[key] = value;
  }
  return values;
}

export async function createPurchaseAction(
  prev: PurchaseFormState,
  formData: FormData,
): Promise<PurchaseFormState> {
  const user = await requirePermission("purchases.manage");

  const parsed = purchaseSchema.safeParse(purchaseFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createPurchase(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível criar a nota.", values: rawValues(formData) });
  }

  revalidatePath("/compras");
  redirect(`/compras/${id}?criada=1`);
}

export async function updatePurchaseAction(
  prev: PurchaseFormState,
  formData: FormData,
): Promise<PurchaseFormState> {
  const user = await requirePermission("purchases.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Nota não informada." });

  const parsed = purchaseSchema.safeParse(purchaseFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updatePurchase(id, parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível salvar a nota.", values: rawValues(formData) });
  }

  revalidatePath(`/compras/${id}`);
  redirect(`/compras/${id}?salva=1`);
}

function voltar(purchaseId: string, chave: string, mensagem?: string): never {
  redirect(
    mensagem
      ? `/compras/${purchaseId}?erro=${encodeURIComponent(mensagem)}`
      : `/compras/${purchaseId}?${chave}=1`,
  );
}

export async function addItemAction(formData: FormData): Promise<void> {
  await requirePermission("purchases.manage");

  const purchaseId = formData.get("purchase_id");
  if (typeof purchaseId !== "string" || !purchaseId) return;

  const parsed = purchaseItemSchema.safeParse(purchaseItemFormData(formData));
  if (!parsed.success) {
    voltar(purchaseId, "item", parsed.error.issues[0]?.message ?? "Item inválido.");
  }

  try {
    await service.addItem(purchaseId, parsed.data);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível adicionar o item.";
    voltar(purchaseId, "item", mensagem);
  }

  revalidatePath(`/compras/${purchaseId}`);
  voltar(purchaseId, "item");
}

export async function removeItemAction(formData: FormData): Promise<void> {
  await requirePermission("purchases.manage");

  const purchaseId = formData.get("purchase_id");
  const itemId = formData.get("item_id");
  if (typeof purchaseId !== "string" || typeof itemId !== "string") return;

  try {
    await service.removeItem(itemId);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível remover o item.";
    voltar(purchaseId, "item", mensagem);
  }

  revalidatePath(`/compras/${purchaseId}`);
  voltar(purchaseId, "removido");
}

export async function receivePurchaseAction(formData: FormData): Promise<void> {
  await requirePermission("purchases.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return;

  try {
    await service.receivePurchase(id);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível dar entrada na nota.";
    voltar(id, "recebida", mensagem);
  }

  // A entrada mexe em estoque E em custo: as duas telas precisam
  // esquecer o que tinham em cache.
  revalidatePath("/compras");
  revalidatePath(`/compras/${id}`);
  revalidatePath("/estoque");
  revalidatePath("/produtos");
  voltar(id, "recebida");
}

export async function cancelPurchaseAction(formData: FormData): Promise<void> {
  await requirePermission("purchases.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return;

  try {
    await service.cancelPurchase(id);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível cancelar a nota.";
    voltar(id, "cancelada", mensagem);
  }

  revalidatePath("/compras");
  voltar(id, "cancelada");
}
