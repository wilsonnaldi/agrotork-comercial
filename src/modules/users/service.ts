import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Profile, UserRole } from "@/types/db";

/**
 * Gestão de usuários — SEM criação de conta.
 *
 * Criar usuário no Auth exige a chave `service_role`, que ignora o RLS por
 * completo. A decisão foi mantê-la fora do ambiente: uma chave que não
 * existe não vaza. Contas novas nascem pelo painel do Supabase
 * (Authentication → Users → Invite), e o trigger `handle_new_user` cria o
 * perfil como VENDEDOR — sempre, qualquer que seja o metadata do convite
 * (migration 2100).
 *
 * O que esta tela faz é o que dá para fazer com o JWT do administrador e a
 * policy `profiles_admin_all`: definir papel e ativar/desativar.
 */

export class BusinessError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BusinessError";
  }
}

export type UserRow = Pick<
  Profile,
  "id" | "full_name" | "email" | "phone" | "role" | "is_active" | "created_at"
>;

export async function listUsers(): Promise<UserRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, phone, role, is_active, created_at")
    .order("is_active", { ascending: false })
    .order("full_name", { ascending: true });

  if (error) throw new Error(error.message);
  return data ?? [];
}

/**
 * Quantos administradores ATIVOS existem.
 *
 * É o número que impede o sistema de ficar sem ninguém que possa
 * administrá-lo — situação que só se resolveria por SQL no painel.
 */
async function countActiveAdmins(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .eq("role", "admin")
    .eq("is_active", true);

  if (error) throw new Error(error.message);
  return count ?? 0;
}

async function findUser(id: string): Promise<UserRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, phone, role, is_active, created_at")
    .eq("id", id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/**
 * Troca o papel.
 *
 * Duas travas, e as duas existem por experiência de sistema, não por
 * capricho: ninguém se rebaixa sozinho (sairia da própria tela no meio da
 * operação) e o último administrador ativo não deixa de ser administrador
 * (sobraria um sistema que só o painel do Supabase destrava).
 */
export async function changeRole(id: string, role: UserRole, actorId: string): Promise<void> {
  const alvo = await findUser(id);
  if (!alvo) throw new BusinessError("Usuário não encontrado.");
  if (alvo.role === role) return;

  if (id === actorId && role !== "admin") {
    throw new BusinessError("Você não pode rebaixar a si mesmo. Peça a outro administrador.");
  }
  if (alvo.role === "admin" && role !== "admin" && (await countActiveAdmins()) <= 1) {
    throw new BusinessError("Este é o único administrador ativo. Promova outro antes de rebaixá-lo.");
  }

  const supabase = await createClient();
  const { error } = await supabase.from("profiles").update({ role }).eq("id", id);
  if (error) throw new Error(error.message);
}

/**
 * Ativa ou desativa. Desativar NÃO apaga nada: o histórico comercial
 * depende do vendedor, e o RLS já barra usuário inativo mesmo com token
 * válido na mão.
 */
export async function setActive(id: string, isActive: boolean, actorId: string): Promise<void> {
  const alvo = await findUser(id);
  if (!alvo) throw new BusinessError("Usuário não encontrado.");
  if (alvo.is_active === isActive) return;

  if (id === actorId && !isActive) {
    throw new BusinessError("Você não pode desativar a si mesmo.");
  }
  if (!isActive && alvo.role === "admin" && (await countActiveAdmins()) <= 1) {
    throw new BusinessError("Este é o único administrador ativo. Promova outro antes de desativá-lo.");
  }

  const supabase = await createClient();
  const { error } = await supabase.from("profiles").update({ is_active: isActive }).eq("id", id);
  if (error) throw new Error(error.message);
}
