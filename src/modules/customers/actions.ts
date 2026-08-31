"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { customerFormData, customerSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 * Toda ação verifica permissão NO SERVIDOR antes de qualquer coisa.
 */

export type CustomerFormState = {
  error?: string;
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  /**
   * Contador de tentativas — ver a explicação em `modules/products/actions.ts`:
   * o React reseta o formulário depois da Server Action, e o `key` derivado
   * daqui remonta o formulário com o que o servidor devolveu.
   */
  attempt?: number;
};

function fail(prev: CustomerFormState, patch: Omit<CustomerFormState, "attempt">): CustomerFormState {
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

export async function createCustomerAction(
  prev: CustomerFormState,
  formData: FormData,
): Promise<CustomerFormState> {
  const user = await requirePermission("customers.write");

  const parsed = customerSchema.safeParse(customerFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createCustomer(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível salvar o cliente.", values: rawValues(formData) });
  }

  revalidatePath("/clientes");
  revalidatePath("/dashboard");
  redirect(`/clientes/${id}?criado=1`);
}

export async function updateCustomerAction(
  prev: CustomerFormState,
  formData: FormData,
): Promise<CustomerFormState> {
  const user = await requirePermission("customers.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Cliente não informado." });

  const parsed = customerSchema.safeParse(customerFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateCustomer(id, parsed.data, user.id);
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

  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  redirect(`/clientes/${id}?salvo=1`);
}

export async function toggleCustomerActiveAction(formData: FormData): Promise<void> {
  const user = await requirePermission("customers.write");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setCustomerActive(id, activate, user.id);
  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
}
