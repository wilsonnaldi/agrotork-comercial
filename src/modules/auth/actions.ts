"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { signInSchema } from "./schema";

export type ActionState = { error?: string; fieldErrors?: Record<string, string> };

/**
 * Login por e-mail e senha.
 * Toda entrada é revalidada no servidor, mesmo já tendo passado pelo formulário.
 */
export async function signIn(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = signInSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    next: formData.get("next") ?? undefined,
  });

  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = issue.path[0];
      if (typeof key === "string" && !fieldErrors[key]) fieldErrors[key] = issue.message;
    }
    return { fieldErrors };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) {
    // Mensagem genérica de propósito: não revela se o e-mail existe.
    return { error: "E-mail ou senha incorretos." };
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("is_active")
      .eq("id", user.id)
      .maybeSingle();

    if (profile && !profile.is_active) {
      await supabase.auth.signOut();
      return { error: "Seu acesso está desativado. Fale com o administrador." };
    }
  }

  // Redirecionamento seguro: aceita apenas caminho interno. `//host` e
  // `/\host` comecam com "/" mas o navegador resolve como URL absoluta,
  // entao o startsWith("/") sozinho permitia sair do dominio depois do login.
  const bruto = parsed.data.next ?? "";
  const target = /^\/(?![/\\])/.test(bruto) ? bruto : "/dashboard";
  revalidatePath("/", "layout");
  redirect(target);
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/login");
}
