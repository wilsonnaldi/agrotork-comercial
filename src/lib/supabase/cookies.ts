import type { CookieOptions } from "@supabase/ssr";

/**
 * Opções aplicadas a TODO cookie de sessão gravado pelo Supabase.
 *
 * Por que forçar `httpOnly`:
 * o padrão do `@supabase/ssr` deixa o cookie legível por JavaScript, porque
 * prevê um cliente Supabase rodando no navegador. Este sistema é server-first
 * — login, sessão e consultas acontecem em Server Components e Server Actions —
 * então o navegador não precisa ler o token, e um XSS deixa de conseguir
 * roubá-lo.
 *
 * Consequência: um `createBrowserClient` não enxerga a sessão. Se algum dia
 * for preciso (Realtime, por exemplo), o token deve ser passado explicitamente
 * do servidor para o componente, e não lido de `document.cookie`.
 */
export const AUTH_COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: "lax",
  secure: process.env.NODE_ENV === "production",
  path: "/",
} satisfies CookieOptions;

/** Mescla as opções do Supabase com as nossas, que têm prioridade. */
export function withAuthCookieOptions(options: CookieOptions | undefined): CookieOptions {
  return { ...options, ...AUTH_COOKIE_OPTIONS };
}
