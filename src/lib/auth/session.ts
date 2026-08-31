import "server-only";

import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "@/types/db";
import { can, type Permission } from "@/config/permissions";

export type SessionUser = {
  id: string;
  email: string;
  profile: Profile;
};

/**
 * Usuário da requisição atual. `cache()` evita repetir a consulta
 * quando vários Server Components pedem a sessão na mesma renderização.
 */
export const getSessionUser = cache(async (): Promise<SessionUser | null> => {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).maybeSingle();

  if (!profile || !profile.is_active) return null;

  return { id: user.id, email: user.email ?? profile.email, profile };
});

/** Exige usuário logado; caso contrário manda para o login. */
export async function requireUser(): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  return user;
}

/** Exige uma permissão específica. Use no topo de páginas e Server Actions. */
export async function requirePermission(permission: Permission): Promise<SessionUser> {
  const user = await requireUser();
  if (!can(user.profile.role, permission)) redirect("/dashboard?erro=sem-permissao");
  return user;
}
