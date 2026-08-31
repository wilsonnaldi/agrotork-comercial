import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { AppDatabase } from "@/types/db";
import { env } from "@/lib/utils/env";

/**
 * ⚠️ Cliente com a service role key: IGNORA o RLS.
 *
 * Regras de uso:
 *  - Só pode ser importado em código de servidor (o "server-only" garante).
 *  - Use apenas em operações administrativas que o RLS não permite,
 *    como criar usuário no Auth ao convidar um vendedor.
 *  - Sempre verifique o papel do solicitante ANTES de chamar.
 */
export function createAdminClient() {
  return createSupabaseClient<AppDatabase>(env.supabaseUrl(), env.supabaseServiceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
