"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { supplierFormData, supplierSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 * Toda ação verifica permissão NO SERVIDOR antes de qualquer coisa.
 *
 * A permissão é `suppliers.manage`, do administrador. O vendedor lê a
 * lista pela RLS, mas nenhuma destas ações abre para ele.
 */

export type SupplierFormState = {
  error?: string;
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  /** Ver a explicação em `modules/customers/actions.ts`. */
  attempt?: number;
};

function fail(prev: SupplierFormState, patch: Omit<SupplierFormState, "attempt">): SupplierFormState {
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

/** Devolve o que foi digitado, para o formulário não perder o preenchimento. */
function rawValues(formData: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === "string") values[key] = value;
  }
  return values;
}

export async function createSupplierAction(
  prev: SupplierFormState,
  formData: FormData,
): Promise<SupplierFormState> {
  const user = await requirePermission("suppliers.manage");

  const parsed = supplierSchema.safeParse(supplierFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createSupplier(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível salvar o fornecedor.", values: rawValues(formData) });
  }

  revalidatePath("/configuracoes/fornecedores");
  redirect(`/configuracoes/fornecedores/${id}?criado=1`);
}

export async function updateSupplierAction(
  prev: SupplierFormState,
  formData: FormData,
): Promise<SupplierFormState> {
  const user = await requirePermission("suppliers.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Fornecedor não informado." });

  const parsed = supplierSchema.safeParse(supplierFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateSupplier(id, parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível salvar as alterações.", values: rawValues(formData) });
  }

  revalidatePath("/configuracoes/fornecedores");
  revalidatePath(`/configuracoes/fornecedores/${id}`);
  redirect(`/configuracoes/fornecedores/${id}?salvo=1`);
}

export async function toggleSupplierActiveAction(formData: FormData): Promise<void> {
  const user = await requirePermission("suppliers.manage");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setSupplierActive(id, activate, user.id);
  revalidatePath("/configuracoes/fornecedores");
  revalidatePath(`/configuracoes/fornecedores/${id}`);
}

export async function deleteSupplierAction(formData: FormData): Promise<void> {
  await requirePermission("suppliers.manage");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return;

  try {
    await service.deleteSupplier(id);
  } catch (error) {
    const mensagem = error instanceof BusinessError ? error.message : "Não foi possível excluir o fornecedor.";
    redirect(`/configuracoes/fornecedores/${id}?erro=${encodeURIComponent(mensagem)}`);
  }

  revalidatePath("/configuracoes/fornecedores");
  redirect("/configuracoes/fornecedores?excluido=1");
}
