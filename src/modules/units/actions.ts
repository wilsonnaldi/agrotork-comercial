"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { collectFieldErrors, fail, isUniqueViolation, rawValues, type FormState } from "@/lib/forms/action-state";
import { unitFormData, unitSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

const LIST_PATH = "/configuracoes/unidades";

function handleError(prev: FormState, error: unknown, formData: FormData, fallback: string): FormState {
  if (error instanceof BusinessError) {
    return fail(prev, {
      fieldErrors: error.field ? { [error.field]: error.message } : undefined,
      error: error.field ? undefined : error.message,
      values: rawValues(formData),
    });
  }
  if (isUniqueViolation(error, "idx_units_code")) {
    return fail(prev, {
      fieldErrors: { code: "Já existe uma unidade com este código." },
      values: rawValues(formData),
    });
  }
  return fail(prev, { error: fallback, values: rawValues(formData) });
}

export async function createUnitAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const parsed = unitSchema.safeParse(unitFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.createUnit(parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar a unidade.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?criado=1`);
}

export async function updateUnitAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Unidade não informada." });

  const parsed = unitSchema.safeParse(unitFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateUnit(id, parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar as alterações.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?salvo=1`);
}

export async function toggleUnitActiveAction(formData: FormData): Promise<void> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setUnitActive(id, activate);
  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
}
