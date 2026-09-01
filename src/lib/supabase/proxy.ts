import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import type { AppDatabase } from "@/types/db";
import { buildCsp, newNonce } from "@/lib/security/csp";
import { withAuthCookieOptions } from "./cookies";

/**
 * Rotas que dispensam sessão.
 *
 * `/orcamento-publico` é a página do cliente e `/api/orcamento-publico` é o
 * PDF dela — sem esta segunda entrada o download do link público caía no
 * login, que é exatamente o que o link deveria evitar. Quem autoriza os
 * dois é o TOKEN, validado em `get_shared_quote` no banco.
 */
const PUBLIC_ROUTES = ["/login", "/auth", "/orcamento-publico", "/api/orcamento-publico"];

function isPublic(pathname: string) {
  return PUBLIC_ROUTES.some((route) => pathname === route || pathname.startsWith(`${route}/`));
}

/**
 * Renova a sessão em toda requisição e bloqueia rotas privadas.
 * É a primeira barreira; a segunda (e definitiva) é o RLS no banco.
 */
export async function updateSession(request: NextRequest) {
  // A CSP é montada aqui porque o nonce muda a cada resposta. O Next lê o
  // nonce do cabeçalho da REQUISIÇÃO para assinar as próprias tags de
  // script; por isso ele entra nos dois lados.
  const nonce = newNonce();
  const csp = buildCsp(nonce, process.env.NODE_ENV !== "production");

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);

  const comCsp = (resposta: NextResponse) => {
    resposta.headers.set("Content-Security-Policy", csp);
    return resposta;
  };

  let response = comCsp(NextResponse.next({ request: { headers: requestHeaders } }));

  const { pathname } = request.nextUrl;

  const paraLogin = () => {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/login";
    redirectUrl.searchParams.set("next", pathname);
    return comCsp(NextResponse.redirect(redirectUrl));
  };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Sem configuração o cliente do Supabase não existe, então não há como
  // validar sessão nenhuma. O comportamento é deliberadamente diferente
  // nos dois ambientes:
  //
  //   desenvolvimento — deixa passar, para a tela de setup explicar o que
  //     falta em vez de jogar o dev num login que também não funciona;
  //   produção — falha FECHADO. Se as variáveis sumirem do Netlify, rota
  //     privada nenhuma pode ser servida sem sessão; só o que já é público
  //     continua respondendo (e falha sozinho, com erro próprio).
  if (!url || !key) {
    if (process.env.NODE_ENV !== "production") return response;
    return isPublic(pathname) ? response : paraLogin();
  }

  const supabase = createServerClient<AppDatabase>(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = comCsp(NextResponse.next({ request: { headers: requestHeaders } }));
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, withAuthCookieOptions(options)),
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user && !isPublic(pathname)) return paraLogin();

  if (user && pathname === "/login") {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/dashboard";
    redirectUrl.search = "";
    return comCsp(NextResponse.redirect(redirectUrl));
  }

  return response;
}
