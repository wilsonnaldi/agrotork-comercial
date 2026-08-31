"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { collectFieldErrors, fail, isUniqueViolation, rawValues, type FormState } from "@/lib/forms/action-state";
import { brandFormData, brandSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 * `catalog.manage` é exclusivo do administrador; o RLS de `brands`
 * recusaria a escrita mesmo que esta checagem falhasse.
 */

const LIST_PATH = "/configuracoes/marcas";

function handleError(prev: FormState, error: unknown, formData: FormData, fallback: string): FormState {
  if (error instanceof BusinessError) {
    return fail(prev, {
      fieldErrors: error.field ? { [error.field]: error.message } : undefined,
      error: error.field ? undefined : error.message,
      values: rawValues(formData),
    });
  }
  if (isUniqueViolation(error, "idx_brands_name", "idx_brands_slug")) {
    return fail(prev, {
      fieldErrors: { name: "Já existe uma marca com este nome." },
      values: rawValues(formData),
    });
  }
  return fail(prev, { error: fallback, values: rawValues(formData) });
}

export async function createBrandAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const parsed = brandSchema.safeParse(brandFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.createBrand(parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar a marca.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?criado=1`);
}

export async function updateBrandAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Marca não informada." });

  const parsed = brandSchema.safeParse(brandFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateBrand(id, parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar as alterações.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?salvo=1`);
}

export async function toggleBrandActiveAction(formData: FormData): Promise<void> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setBrandActive(id, activate);
  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
}
