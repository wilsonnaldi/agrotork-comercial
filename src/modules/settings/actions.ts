"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { collectFieldErrors, fail, rawValues, type FormState } from "@/lib/forms/action-state";
import { companyFormData, companySchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

const PATH = "/configuracoes/empresa";

/** Toda tela que mostra o cabeçalho da empresa precisa ser revalidada. */
function revalidarDocumentos() {
  revalidatePath(PATH);
  revalidatePath("/orcamentos", "layout");
}

export async function saveCompanyAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("settings.manage");

  const parsed = companySchema.safeParse(companyFormData(formData));
  if (!parsed.success) {
    return fail(prev, { fieldErrors: collectFieldErrors(parsed.error.issues), values: rawValues(formData) });
  }

  try {
    await service.saveCompany(parsed.data, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, { error: error.message, values: rawValues(formData) });
    }
    return fail(prev, { error: "Não foi possível salvar os dados da empresa.", values: rawValues(formData) });
  }

  revalidarDocumentos();
  redirect(`${PATH}?salvo=1`);
}

export async function uploadLogoAction(prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requirePermission("settings.manage");

  const arquivo = formData.get("logo");
  if (!(arquivo instanceof File)) {
    return fail(prev, { fieldErrors: { logo: "Escolha um arquivo de imagem." } });
  }

  try {
    await service.replaceLogo(arquivo, user.id);
  } catch (error) {
    if (error instanceof BusinessError) {
      return fail(prev, { fieldErrors: error.field ? { [error.field]: error.message } : undefined, error: error.field ? undefined : error.message });
    }
    return fail(prev, { error: "Não foi possível enviar a imagem." });
  }

  revalidarDocumentos();
  redirect(`${PATH}?logo=1`);
}

export async function removeLogoAction(): Promise<void> {
  const user = await requirePermission("settings.manage");
  await service.removeLogo(user.id);
  revalidarDocumentos();
  redirect(`${PATH}?logo=0`);
}
