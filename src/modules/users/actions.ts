"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import * as service from "./service";
import { BusinessError } from "./service";

const PATH = "/configuracoes/usuarios";

function voltar(erro?: string): never {
  redirect(erro ? `${PATH}?erro=${encodeURIComponent(erro)}` : `${PATH}?salvo=1`);
}

export async function changeRoleAction(formData: FormData): Promise<void> {
  const user = await requirePermission("users.manage");

  const id = formData.get("id");
  const role = formData.get("role");
  if (typeof id !== "string" || (role !== "admin" && role !== "salesperson")) {
    voltar("Dados incompletos.");
  }

  try {
    await service.changeRole(id, role, user.id);
  } catch (error) {
    voltar(error instanceof BusinessError ? error.message : "Não foi possível alterar o papel.");
  }

  revalidatePath(PATH);
  voltar();
}

export async function toggleActiveAction(formData: FormData): Promise<void> {
  const user = await requirePermission("users.manage");

  const id = formData.get("id");
  const activate = formData.get("activate") === "true";
  if (typeof id !== "string" || !id) voltar("Usuário não informado.");

  try {
    await service.setActive(id, activate, user.id);
  } catch (error) {
    voltar(error instanceof BusinessError ? error.message : "Não foi possível alterar a situação.");
  }

  revalidatePath(PATH);
  voltar();
}
