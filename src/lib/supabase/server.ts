import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import type { AppDatabase } from "@/types/db";
import { env } from "@/lib/utils/env";
import { withAuthCookieOptions } from "./cookies";

/**
 * Cliente para Server Components, Server Actions e Route Handlers.
 * Age SEMPRE com o JWT do usuário logado — portanto sujeito ao RLS.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<AppDatabase>(env.supabaseUrl(), env.supabaseAnonKey(), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, withAuthCookieOptions(options)),
          );
        } catch {
          // Server Component não pode escrever cookie: o middleware já renova a sessão.
        }
      },
    },
  });
}
