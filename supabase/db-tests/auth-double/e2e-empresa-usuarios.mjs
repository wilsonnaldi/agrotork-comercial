/**
 * Validação de ponta a ponta do fechamento da FASE 1:
 * Dados da empresa (com logotipo) e gestão de Usuários.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois: BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-empresa-usuarios.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);

function sql(query) {
  return execFileSync(
    "psql",
    ["-h", process.env.PGHOST ?? "/tmp/pgrun", "-p", process.env.PGPORT ?? "5433",
     "-U", process.env.PGUSER ?? "postgres", "-d", process.env.PGDATABASE ?? "agrotork_dev",
     "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1", "-c", query],
    { stdio: "pipe" },
  ).toString().trim();
}

const browser = await chromium.launch(
  process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {},
);

async function login(ctx, email) {
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: "domcontentloaded" });
  await page.fill("#email", email);
  await page.fill("#password", "teste1234");
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 15000 });
  return page;
}

// ── 1. Dados da empresa, como administrador ─────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  await page.goto(`${BASE}/configuracoes`, { waitUntil: "domcontentloaded" });
  const hub = await page.textContent("main");
  check("Configurações lista Dados da empresa", hub.includes("Dados da empresa"));
  check("Configurações lista Usuários", hub.includes("Usuários"));

  await page.goto(`${BASE}/configuracoes/empresa`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  check("tela de empresa abre para o admin", page.url().includes("/configuracoes/empresa"));

  await page.fill("#legal_name", "AGROTORK COMERCIO DE IMPLEMENTOS LTDA");
  await page.fill("#trade_name", "AgroTork");
  await page.fill("#city", "Londrina");
  await page.fill("#state", "PR");
  await page.fill("#email", "comercial@agrotork.com.br");
  await page.click('button[type="submit"]:has-text("Salvar dados")');
  await page.waitForTimeout(1500);

  const salvo = sql("select value ->> 'legal_name' from public.app_settings where key='company';");
  check("razão social gravada", salvo === "AGROTORK COMERCIO DE IMPLEMENTOS LTDA", salvo);
  const cidade = sql("select value ->> 'city' from public.app_settings where key='company';");
  check("cidade gravada", cidade === "Londrina", cidade);

  // Campo obrigatório: razão social vazia não passa.
  await page.goto(`${BASE}/configuracoes/empresa`, { waitUntil: "domcontentloaded" });
  await page.fill("#legal_name", "");
  await page.click('button[type="submit"]:has-text("Salvar dados")');
  await page.waitForTimeout(1200);
  const aindaLa = sql("select value ->> 'legal_name' from public.app_settings where key='company';");
  check("razão social vazia é recusada", aindaLa === "AGROTORK COMERCIO DE IMPLEMENTOS LTDA", aindaLa);

  await ctx.close();
}

// ── 2. Vendedor não chega perto ─────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/configuracoes/empresa`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  check("vendedor é barrado nos dados da empresa", !page.url().includes("/configuracoes/empresa"), page.url());

  await page.goto(`${BASE}/configuracoes/usuarios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  check("vendedor é barrado em usuários", !page.url().includes("/configuracoes/usuarios"), page.url());

  await ctx.close();
}

// ── 3. Usuários, como administrador ─────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  await page.goto(`${BASE}/configuracoes/usuarios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const lista = await page.textContent("main");
  check("lista mostra o administrador", lista.includes("Administrador de Teste"));
  check("lista mostra o vendedor", lista.includes("Vendedor de Teste"));
  check("marca quem é você", lista.includes("você"));
  check("explica de onde vêm contas novas", lista.includes("Invite user"));

  // Cada botão vive num <form> com o id do usuário num input escondido —
  // é o jeito estável de mirar a linha certa, sem depender do layout.
  const idAdmin = sql("select id from public.profiles where email='admin@teste.local';");
  const idVend = sql("select id from public.profiles where email='vendedor@teste.local';");
  const formDe = (id, rotulo) =>
    page.locator(`form:has(input[value="${id}"])`).filter({ has: page.locator(`button:has-text("${rotulo}")`) });

  // O próprio admin não pode se rebaixar nem se desativar.
  check(
    "botão de rebaixar a si mesmo está desabilitado",
    await formDe(idAdmin, "Tornar vendedor").locator("button").first().isDisabled(),
  );
  check(
    "botão de desativar a si mesmo está desabilitado",
    await formDe(idAdmin, "Desativar").locator("button").first().isDisabled(),
  );

  // Promover o vendedor e voltar atrás.
  await formDe(idVend, "Tornar administrador").locator("button").first().click();
  await page.waitForTimeout(1800);
  let papel = sql("select role from public.profiles where email='vendedor@teste.local';");
  check("admin promove o vendedor", papel === "admin", papel);

  await page.goto(`${BASE}/configuracoes/usuarios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await formDe(idVend, "Tornar vendedor").locator("button").first().click();
  await page.waitForTimeout(1800);
  papel = sql("select role from public.profiles where email='vendedor@teste.local';");
  check("admin rebaixa de volta", papel === "salesperson", papel);

  // Desativar e reativar.
  await page.goto(`${BASE}/configuracoes/usuarios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await formDe(idVend, "Desativar").locator("button").first().click();
  await page.waitForTimeout(1800);
  let ativo = sql("select is_active from public.profiles where email='vendedor@teste.local';");
  check("admin desativa o vendedor", ativo === "f", ativo);

  await page.goto(`${BASE}/configuracoes/usuarios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await formDe(idVend, "Reativar").locator("button").first().click();
  await page.waitForTimeout(1800);
  ativo = sql("select is_active from public.profiles where email='vendedor@teste.local';");
  check("admin reativa o vendedor", ativo === "t", ativo);

  await ctx.close();
}

// ── 4. Responsividade ───────────────────────────────────────
for (const largura of [360, 768, 1440]) {
  const ctx = await browser.newContext({ viewport: { width: largura, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  for (const rota of ["/configuracoes/empresa", "/configuracoes/usuarios"]) {
    await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const sobra = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check(`${rota} sem rolagem horizontal em ${largura}px`, sobra <= 0, `sobra ${sobra}px`);
  }
  await ctx.close();
}

await browser.close();

for (const linha of results) console.log(linha);
const falhas = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - falhas}/${results.length} verificações OK`);
process.exit(falhas === 0 ? 0 : 1);
