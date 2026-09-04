"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { paymentFormData, paymentSchema, splitSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 * Tudo aqui é `financial.manage`, do administrador.
 */

function voltar(entryId: string, chave: string, mensagem?: string): never {
  redirect(
    mensagem
      ? `/financeiro/${entryId}?erro=${encodeURIComponent(mensagem)}`
      : `/financeiro/${entryId}?${chave}=1`,
  );
}

export async function registerPaymentAction(formData: FormData): Promise<void> {
  await requirePermission("financial.manage");

  const dados = paymentFormData(formData);
  const parsed = paymentSchema.safeParse(dados);
  if (!parsed.success) {
    voltar(dados.entry_id, "baixa", parsed.error.issues[0]?.message ?? "Valor inválido.");
  }

  try {
    await service.registerPayment(parsed.data);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível registrar a baixa.";
    voltar(parsed.data.entry_id, "baixa", mensagem);
  }

  revalidatePath("/financeiro");
  revalidatePath(`/financeiro/${parsed.data.entry_id}`);
  voltar(parsed.data.entry_id, "baixa");
}

export async function splitEntryAction(formData: FormData): Promise<void> {
  await requirePermission("financial.manage");

  const entryId = (formData.get("entry_id") as string | null) ?? "";
  const parsed = splitSchema.safeParse({
    entry_id: entryId,
    installments: (formData.get("installments") as string | null) ?? "",
    first_due:
      (formData.get("first_due") as string | null) || new Date().toISOString().slice(0, 10),
    interval_days: (formData.get("interval_days") as string | null) || "30",
  });

  if (!parsed.success) {
    voltar(entryId, "parcelado", parsed.error.issues[0]?.message ?? "Parcelamento inválido.");
  }

  try {
    await service.splitEntry(parsed.data);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível parcelar o título.";
    voltar(entryId, "parcelado", mensagem);
  }

  // O título original deixa de existir: voltar para ele daria 404. A
  // listagem é o destino certo, e é lá que as parcelas novas aparecem.
  revalidatePath("/financeiro");
  redirect("/financeiro?parcelado=1");
}

export async function cancelEntryAction(formData: FormData): Promise<void> {
  await requirePermission("financial.manage");

  const entryId = formData.get("entry_id");
  if (typeof entryId !== "string" || !entryId) return;

  try {
    await service.cancelEntry(entryId);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível cancelar o título.";
    voltar(entryId, "cancelado", mensagem);
  }

  revalidatePath("/financeiro");
  voltar(entryId, "cancelado");
}
