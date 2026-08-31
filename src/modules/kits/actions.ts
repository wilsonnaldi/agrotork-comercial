"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import {
  collectFieldErrors,
  fail,
  isUniqueViolation,
  rawValues,
  type FormState,
} from "@/lib/forms/action-state";
import { kitFormData, kitItemFormData, kitItemSchema, kitItemTypeSchema, kitSchema, parseQuantityToMilli } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * `kits.write` é exclusivo do administrador — e mesmo que esta checagem
 * falhasse, o RLS de `kits` e `kit_items` recusaria a escrita. Esconder
 * botão nunca é a proteção.
 */

const LIST_PATH = "/kits";

function handleError(prev: FormState, error: unknown, formData: FormData, fallback: string): FormState {
  if (error instanceof BusinessError) {
    return fail(prev, {
      fieldErrors: error.field ? { [error.field]: error.message } : undefined,
      error: error.field ? undefined : error.message,
      values: rawValues(formData),
    });
  }
  if (isUniqueViolation(error, "idx_kits_code")) {
    return fail(prev, {
      fieldErrors: { code: "Já existe um kit com este código." },
      values: rawValues(formData),
    });
  }
  if (isUniqueViolation(error, "kit_items_kit_id_product_id_key")) {
    return fail(prev, {
      fieldErrors: { product_id: "Este produto já faz parte do kit." },
      values: rawValues(formData),
    });
  }
  return fail(prev, { error: fallback, values: rawValues(formData) });
}

function revalidateKit(id?: string) {
  revalidatePath(LIST_PATH);
  if (id) {
    revalidatePath(`${LIST_PATH}/${id}`);
    revalidatePath(`${LIST_PATH}/${id}/editar`);
  }
}

// ── Cadastro do kit ──────────────────────────────────────────

export async function createKitAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("kits.write");

  const parsed = kitSchema.safeParse(kitFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createKit(parsed.data, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível criar o kit.");
  }

  revalidateKit(id);
  // Vai direto para a montagem: um kit recém-criado está vazio, e é lá que
  // ele ganha composição.
  redirect(`${LIST_PATH}/${id}/editar?criado=1`);
}

export async function updateKitAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("kits.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Kit não informado." });

  const parsed = kitSchema.safeParse(kitFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateKit(id, parsed.data, user.id);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar as alterações.");
  }

  revalidateKit(id);
  redirect(`${LIST_PATH}/${id}?salvo=1`);
}

export async function toggleKitActiveAction(formData: FormData): Promise<void> {
  const user = await requirePermission("kits.write");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setKitActive(id, activate, user.id);
  revalidateKit(id);
}

// ── Composição ───────────────────────────────────────────────

/**
 * Adiciona um componente. O botão que envia o formulário carrega o papel
 * (`item_type=required` ou `optional`), então a mesma linha de resultado
 * serve para os dois grupos, sem checkbox — checkbox aqui confundiria
 * cadastro com seleção de orçamento.
 */
export async function addComponentAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("kits.write");

  const kitId = formData.get("kit_id");
  if (typeof kitId !== "string" || !kitId) return fail(prev, { error: "Kit não informado." });

  const parsed = kitItemSchema.safeParse(kitItemFormData(formData));
  if (!parsed.success) {
    return fail(prev, {
      fieldErrors: collectFieldErrors(parsed.error.issues, /_milli$/),
      values: rawValues(formData),
    });
  }

  try {
    await service.addComponent(kitId, parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível adicionar o componente.");
  }

  revalidateKit(kitId);
  return { attempt: (prev.attempt ?? 0) + 1 };
}

/** Uma linha da composição: alterar quantidade, alternar papel ou remover. */
export async function componentRowAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("kits.write");

  const kitId = formData.get("kit_id");
  const itemId = formData.get("item_id");
  const acao = formData.get("acao");
  if (typeof kitId !== "string" || typeof itemId !== "string" || !kitId || !itemId) {
    return fail(prev, { error: "Componente não informado." });
  }

  try {
    if (acao === "remover") {
      await service.removeComponent(itemId);
    } else if (acao === "alternar") {
      const tipo = kitItemTypeSchema.safeParse(formData.get("para"));
      if (!tipo.success) return fail(prev, { error: "Tipo de item inválido." });
      await service.changeComponentType(itemId, tipo.data);
    } else {
      const quantidade = parseQuantityToMilli(formData.get("quantity") as string | null);
      if (quantidade === null) {
        return fail(prev, { fieldErrors: { [`quantity-${itemId}`]: "Quantidade inválida" } });
      }
      await service.changeComponentQuantity(itemId, quantidade);
    }
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, { error: error.message });
    }
    return handleError(prev, error, formData, "Não foi possível alterar o componente.");
  }

  revalidateKit(kitId);
  return { attempt: (prev.attempt ?? 0) + 1 };
}
