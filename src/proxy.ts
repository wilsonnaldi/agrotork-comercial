import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";

/**
 * Executa antes de toda requisição (convenção "proxy" do Next.js 16,
 * sucessora do antigo middleware.ts).
 *
 * Responsabilidades:
 *  1. renovar a sessão do Supabase (cookies httpOnly);
 *  2. barrar rotas privadas para quem não está logado.
 *
 * Isto é a primeira barreira. A definitiva é o RLS no banco.
 */
export default async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    // Todas as rotas, exceto arquivos estáticos e imagens.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
