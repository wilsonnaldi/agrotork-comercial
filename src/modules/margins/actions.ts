"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { collectFieldErrors, fail, rawValues, type FormState } from "@/lib/forms/action-state";
import { marginRuleFormData, marginRuleSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * `catalog.manage` é exclusivo do administrador. Esconder o menu não é
 * controle de acesso: quem barra de verdade é o RLS de `margin_rules`,
 * e esta verificação existe para a mensagem ser decente antes disso.
 */
const LIST_PATH = "/configuracoes/margens";

export async function saveMarginRuleAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("catalog.manage");

  const parsed = marginRuleSchema.safeParse(marginRuleFormData(formData));
  if (!parsed.success) {
    return fail(prev, {
      fieldErrors: collectFieldErrors(parsed.error.issues),
      values: rawValues(formData),
    });
  }

  try {
    await service.saveRule(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, {
        fieldErrors: error.field ? { [error.field]: error.message } : undefined,
        error: error.field ? undefined : error.message,
        values: rawValues(formData),
      });
    }
    return fail(prev, {
      error: "Não foi possível salvar a regra de margem.",
      values: rawValues(formData),
    });
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?salvo=1`);
}

/**
 * Grava os preços do setor. O ensaio já foi visto na tela anterior —
 * este é o passo que escreve, e por isso é uma ação separada.
 */
export async function applyMarginAction(formData: FormData): Promise<void> {
  await requirePermission("catalog.manage");

  const raw = formData.get("category_id");
  const categoryId = typeof raw === "string" && raw !== "" ? raw : null;
  const destino = categoryId ?? "sem-setor";

  let aplicados = 0;
  try {
    const changes = await service.applySector(categoryId);
    aplicados = changes.filter((change) => change.aplicado).length;
  } catch (error) {
    const motivo = error instanceof BusinessError ? error.message : "Não foi possível aplicar a margem.";
    redirect(`${LIST_PATH}/${destino}?erro=${encodeURIComponent(motivo)}`);
  }

  revalidatePath(LIST_PATH);
  revalidatePath("/produtos");
  redirect(`${LIST_PATH}?aplicado=${aplicados}`);
}
