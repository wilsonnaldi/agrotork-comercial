/**
 * Validação de ponta a ponta da autenticação.
 *
 * Requer, nesta ordem:
 *   1. bash supabase/db-tests/dev-seed.sh          (banco local com dados)
 *   2. node supabase/db-tests/auth-double/server.mjs   (duplê do Supabase)
 *   3. npm run build && npx next start -p 3302      (a aplicação)
 *
 * Depois:  BASE_URL=http://localhost:3302 node supabase/db-tests/auth-double/e2e-autenticacao.mjs
 *
 * Exercita o código de sessão DO SISTEMA. Não valida o GoTrue real —
 * ver README.md nesta pasta.
 */
import { chromium } from "playwright";

const BASE = process.env.BASE_URL ?? "http://localhost:3302";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);

const browser = await chromium.launch(
  process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {},
);

// ── 1. Usuário não autenticado ──────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();

  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  check("rota protegida redireciona para login", page.url().includes("/login"), page.url().replace(BASE, ""));
  check("redirect preserva o destino (?next=)", page.url().includes("next=%2Fdashboard"));

  await page.goto(`${BASE}/configuracoes/perfil`, { waitUntil: "domcontentloaded" });
  check("outra rota protegida também redireciona", page.url().includes("/login"));

  await page.goto(`${BASE}/`, { waitUntil: "domcontentloaded" });
  check("raiz manda para o login quando sem sessão", page.url().includes("/login"));
  await ctx.close();
}

// ── 2. Login com credencial errada ──────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: "domcontentloaded" });
  await page.fill("#email", "admin@teste.local");
  await page.fill("#password", "senha-errada");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1500);
  const body = await page.innerText("body");
  check("senha errada é recusada", page.url().includes("/login") && /incorret/i.test(body ?? ""));
  check("mensagem não revela se o e-mail existe", !/não encontrado|not found|no user/i.test(body ?? ""));
  await ctx.close();
}

// ── 3. Login do ADMIN ───────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login?next=%2Fconfiguracoes`, { waitUntil: "domcontentloaded" });
  await page.fill("#email", "admin@teste.local");
  await page.fill("#password", "teste1234");
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 15000 });
  check("login válido entra no sistema", !page.url().includes("/login"), page.url().replace(BASE, ""));
  check("respeita o ?next= após entrar", page.url().includes("/configuracoes"));

  const cookies = await ctx.cookies();
  const auth = cookies.filter((c) => c.name.includes("auth-token"));
  check("sessão gravada em cookie", auth.length > 0, `${auth.length} cookie(s)`);
  check("cookie de sessão é httpOnly", auth.every((c) => c.httpOnly));
  check("cookie de sessão é sameSite=Lax", auth.every((c) => c.sameSite === "Lax"));

  // ── Cabeçalhos de segurança ────────────────────────────
  // Conferidos aqui para que uma mudança futura no proxy ou no
  // next.config não os apague sem ninguém perceber.
  const cabecalhos = (await page.request.get(`${BASE}/login`)).headers();
  const csp = cabecalhos["content-security-policy"] ?? "";
  check("Content-Security-Policy presente", csp.length > 0);
  check("CSP usa nonce e strict-dynamic, sem unsafe-inline em script",
    /script-src[^;]*'nonce-/.test(csp) &&
    /script-src[^;]*'strict-dynamic'/.test(csp) &&
    !/script-src[^;]*'unsafe-inline'/.test(csp) &&
    !/script-src[^;]*'unsafe-eval'/.test(csp));
  check("CSP proíbe embutir em iframe", csp.includes("frame-ancestors 'none'"));
  check("CSP restringe destino de formulário", csp.includes("form-action 'self'"));
  check("CSP bloqueia object/embed", csp.includes("object-src 'none'"));

  const outra = (await page.request.get(`${BASE}/login`)).headers()["content-security-policy"] ?? "";
  check("nonce muda a cada resposta", csp !== outra && outra.length > 0);

  check("X-Content-Type-Options", cabecalhos["x-content-type-options"] === "nosniff");
  check("X-Frame-Options", cabecalhos["x-frame-options"] === "DENY");
  check("Referrer-Policy", cabecalhos["referrer-policy"] === "strict-origin-when-cross-origin");
  check("Permissions-Policy presente", (cabecalhos["permissions-policy"] ?? "").includes("camera=()"));
  check("cabeçalho não revela o framework", cabecalhos["x-powered-by"] === undefined);

  // A anon key é pública por natureza (é ela que o RLS limita); a service
  // role NUNCA pode chegar ao navegador.
  const html = await (await page.request.get(`${BASE}/login`)).text();
  check("HTML não contém service role key",
    !/service_role/i.test(html) && !/SUPABASE_SERVICE_ROLE/i.test(html));

  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const dash = await page.innerText("body");
  const stat = (label) => page.locator(`[data-stat="${label}"]`).innerText();
  check("painel abre com sessão", /Painel|Olá/i.test(dash));
  check("admin vê 3 clientes (dado real do banco)", (await stat("Clientes")) === "3");
  check("admin vê os 3 orçamentos (RLS)", (await stat("Em aberto")) === "3");
  check("menu de admin mostra Configurações", dash.includes("Configurações"));

  // sessão persiste em nova aba do mesmo contexto
  const page2 = await ctx.newPage();
  await page2.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  check("sessão persiste em nova aba", !page2.url().includes("/login"));
  await page2.close();

  // login com sessão ativa manda para o painel
  await page.goto(`${BASE}/login`, { waitUntil: "domcontentloaded" });
  check("já logado, /login redireciona ao painel", page.url().includes("/dashboard"));

  // ── logout ───────────────────────────────────────────────
  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  await page.click('button[aria-haspopup="menu"]');
  await page.waitForTimeout(300);
  await page.click('button:has-text("Sair")');
  await page.waitForURL((u) => u.pathname.includes("/login"), { timeout: 15000 });
  check("logout leva de volta ao login", page.url().includes("/login"));

  const after = await ctx.cookies();
  const stillAuth = after.filter((c) => c.name.includes("auth-token") && c.value.length > 10);
  check("logout limpa o cookie de sessão", stillAuth.length === 0, `${stillAuth.length} restante(s)`);

  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  check("depois do logout a rota volta a ser protegida", page.url().includes("/login"));
  await ctx.close();
}

// ── 4. Login do VENDEDOR ────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: "domcontentloaded" });
  await page.fill("#email", "vendedor@teste.local");
  await page.fill("#password", "teste1234");
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 15000 });
  await page.waitForTimeout(800);

  const dash = await page.innerText("body");
  const stat = (label) => page.locator(`[data-stat="${label}"]`).innerText();
  check("vendedor entra no painel", page.url().includes("/dashboard"));
  check("vendedor NÃO vê o menu Configurações", !dash.includes("Configurações"));
  check("vendedor vê só 1 orçamento (RLS aplicado)", (await stat("Em aberto")) === "1");
  check("vendedor vê os 3 clientes (catálogo compartilhado)", (await stat("Clientes")) === "3");

  // acesso direto por URL a uma área de admin
  await page.goto(`${BASE}/configuracoes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const url = page.url();
  const blocked = url.includes("/dashboard") && url.includes("sem-permissao");
  check("vendedor é barrado ao digitar /configuracoes", blocked, url.replace(BASE, ""));
  const msg = await page.innerText("body");
  check("aviso de permissão é exibido", /não tem permissão/i.test(msg));

  await page.screenshot({ path: "docs/screenshots/painel-vendedor-rls.png" });
  await ctx.close();
}

await browser.close();

console.log("\n=== VALIDAÇÃO DE AUTENTICAÇÃO ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
