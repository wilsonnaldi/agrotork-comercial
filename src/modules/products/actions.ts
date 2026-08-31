"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { productFormData, productSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * `requirePermission` vem antes de qualquer leitura de dados: esconder
 * o botão na tela não é controle de acesso. E mesmo que esta camada
 * falhasse, o RLS recusaria a escrita no banco.
 */

export type ProductFormState = {
  error?: string;
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  /**
   * Contador de tentativas.
   *
   * O React **reseta o formulário** depois que uma Server Action termina, e
   * campos controlados não voltam a ser sincronizados — a seleção de unidade,
   * marca e categoria sumia da tela mesmo com o valor certo no estado. O
   * formulário usa este número como `key` para remontar com o que o servidor
   * devolveu em `values`.
   */
  attempt?: number;
};

/** Resposta de erro, sempre com o contador incrementado. */
function fail(prev: ProductFormState, patch: Omit<ProductFormState, "attempt">): ProductFormState {
  return { ...patch, attempt: (prev.attempt ?? 0) + 1 };
}

function collectFieldErrors(issues: { path: PropertyKey[]; message: string }[]) {
  const fieldErrors: Record<string, string> = {};
  for (const issue of issues) {
    const key = issue.path[0];
    if (typeof key !== "string") continue;
    // O schema fala em centavos; o formulário, em campos de preço.
    const field = key.replace(/_cents$/, "");
    if (!fieldErrors[field]) fieldErrors[field] = issue.message;
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

export async function createProductAction(
  prev: ProductFormState,
  formData: FormData,
): Promise<ProductFormState> {
  const user = await requirePermission("products.write");

  const parsed = productSchema.safeParse(productFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  let id: string;
  try {
    id = await service.createProduct(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    // Rede de segurança: a constraint única do banco também protege o código.
    const message = error instanceof Error ? error.message : "";
    if (/idx_products_code|duplicate key/i.test(message)) {
      return fail(prev, {
        fieldErrors: { code: "Este código já está em uso." },
        values: rawValues(formData),
      });
    }
    return fail(prev, { error: "Não foi possível salvar o produto.", values: rawValues(formData) });
  }

  revalidatePath("/produtos");
  revalidatePath("/dashboard");
  redirect(`/produtos/${id}?criado=1`);
}

export async function updateProductAction(
  prev: ProductFormState,
  formData: FormData,
): Promise<ProductFormState> {
  const user = await requirePermission("products.write");

  const id = formData.get("id");
  if (typeof id !== "string" || !id) return fail(prev, { error: "Produto não informado." });

  const parsed = productSchema.safeParse(productFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.updateProduct(id, parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        error: error.field ? undefined : error.message,
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        values: rawValues(formData),
      });
    }
    const message = error instanceof Error ? error.message : "";
    if (/idx_products_code|duplicate key/i.test(message)) {
      return fail(prev, { fieldErrors: { code: "Este código já está em uso." }, values: rawValues(formData) });
    }
    return fail(prev, { error: "Não foi possível salvar as alterações.", values: rawValues(formData) });
  }

  revalidatePath("/produtos");
  revalidatePath(`/produtos/${id}`);
  redirect(`/produtos/${id}?salvo=1`);
}

export async function toggleProductActiveAction(formData: FormData): Promise<void> {
  const user = await requirePermission("products.write");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) return;

  await service.setProductActive(id, activate, user.id);
  revalidatePath("/produtos");
  revalidatePath(`/produtos/${id}`);
}
