"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { collectFieldErrors, fail, isUniqueViolation, rawValues, type FormState } from "@/lib/forms/action-state";
import { categoryFormData, categorySchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

const LIST_PATH = "/configuracoes/categorias";

function handleError(prev: FormState, error: unknown, formData: FormData, fallback: string): FormState {
  if (error instanceof BusinessError) {
    return fail(prev, {
      fieldErrors: error.field ? { [error.field]: error.message } : undefined,
      error: error.field ? undefined : error.message,
      values: rawValues(formData),
    });
  }
  if (isUniqueViolation(error, "idx_categories_name", "idx_categories_slug")) {
    return fail(prev, {
      fieldErrors: { name: "Já existe uma categoria com este nome." },
      values: rawValues(formData),
    });
  }
  return fail(prev, { error: fallback, values: rawValues(formData) });
}

export async function createCategoryAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const parsed = categorySchema.safeParse(categoryFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.createCategory(parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar a categoria.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?criado=1`);
}

export async function updateCategoryAction(prev: FormState, formData: FormData): Promise<FormState> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Categoria não informada." });

  const parsed = categorySchema.safeParse(categoryFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateCategory(id, parsed.data);
  } catch (error) {
    return handleError(prev, error, formData, "Não foi possível salvar as alterações.");
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?salvo=1`);
}

export async function toggleCategoryActiveAction(formData: FormData): Promise<void> {
  await requirePermission("catalog.manage");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setCategoryActive(id, activate);
  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
}
