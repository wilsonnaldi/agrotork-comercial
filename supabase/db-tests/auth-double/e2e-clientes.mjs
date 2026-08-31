/**
 * Validação de ponta a ponta do módulo CLIENTES.
 *
 * Pré-requisitos (mesma sequência do e2e de autenticação):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3401
 *
 * Depois:  BASE_URL=http://localhost:3401 node supabase/db-tests/auth-double/e2e-clientes.mjs
 */
import { chromium } from "playwright";

const BASE = process.env.BASE_URL ?? "http://localhost:3401";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);

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

const NOME = "Sítio Boa Esperança Ltda";
// O título da ficha é exibido em maiúsculas por CSS, e innerText respeita isso.
const contem = (texto, trecho) => texto.toLowerCase().includes(trecho.toLowerCase());
const CNPJ = "11444777000161"; // válido
const CNPJ_INVALIDO = "11111111111111";

// ── ADMIN: ciclo completo ───────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  let body = await page.innerText("body");
  check("listagem carrega os clientes semeados", body.includes("Fazenda São João"));
  check("listagem mostra a contagem", /3 clientes/.test(body));

  // ── validação: documento inválido ──────────────────────
  await page.goto(`${BASE}/clientes/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "Teste Documento");
  await page.fill("#document", CNPJ_INVALIDO);
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1200);
  body = await page.innerText("body");
  check("CNPJ inválido é recusado", /CNPJ inválido/i.test(body) && page.url().includes("/clientes/novo"));
  check("o que foi digitado não se perde", (await page.inputValue("#name")) === "Teste Documento");

  // ── cadastro válido ────────────────────────────────────
  await page.fill("#name", NOME);
  await page.fill("#document", CNPJ);
  await page.fill("#whatsapp", "43999887766");
  await page.fill("#email", "contato@boaesperanca.com.br");
  await page.fill("#city", "Rolândia");
  await page.fill("#zip_code", "86600000");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/clientes\/[0-9a-f-]{36}/, { timeout: 15000 });
  const fichaUrl = page.url();
  check("cadastro válido cria o cliente", /criado=1/.test(fichaUrl));

  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("ficha mostra o nome", contem(body, NOME));
  check("CNPJ aparece formatado", body.includes("11.444.777/0001-61"));
  check("WhatsApp aparece formatado", body.includes("(43) 99988-7766"));
  check("CEP aparece formatado", body.includes("86600-000"));
  check("histórico começa vazio", /Nenhum orçamento ainda/i.test(body));

  // ── documento duplicado ────────────────────────────────
  await page.goto(`${BASE}/clientes/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "Outro nome qualquer");
  await page.fill("#document", CNPJ);
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1200);
  body = await page.innerText("body");
  check("documento duplicado é bloqueado", /já existe um cliente com este documento/i.test(body));

  // ── busca ──────────────────────────────────────────────
  await page.goto(`${BASE}/clientes?q=boa`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por nome parcial encontra", contem(body, NOME) && !contem(body, "Fazenda São João"));

  await page.goto(`${BASE}/clientes?q=11444777`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por documento encontra", contem(body, NOME));

  await page.goto(`${BASE}/clientes?q=Cambé`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por cidade encontra", body.includes("Agropecuária Canedo"));

  await page.goto(`${BASE}/clientes?q=zzzzzz`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca sem resultado mostra estado vazio", /Nenhum cliente encontrado/i.test(body));

  // ── edição ─────────────────────────────────────────────
  await page.goto(`${fichaUrl.split("?")[0]}/editar`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", `${NOME} — Matriz`);
  await page.click('button[type="submit"]');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("edição salva", contem(body, `${NOME} — Matriz`));

  // ── desativar / reativar ───────────────────────────────
  await page.click('button:has-text("Desativar cliente")');
  await page.locator('button:has-text("Reativar cliente")').waitFor({ timeout: 15000 });
  body = await page.innerText("body");
  check("desativar funciona", /Este cliente está inativo/i.test(body));

  await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("inativo some da listagem padrão", !contem(body, `${NOME} — Matriz`));

  await page.goto(`${BASE}/clientes?status=inactive`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro de inativos encontra", contem(body, `${NOME} — Matriz`));

  await page.goto(fichaUrl.split("?")[0], { waitUntil: "domcontentloaded" });
  await page.click('button:has-text("Reativar cliente")');
  await page.locator('button:has-text("Desativar cliente")').waitFor({ timeout: 15000 });
  body = await page.innerText("body");
  check("reativar funciona", !/Este cliente está inativo/i.test(body));

  // ── filtro por UF ──────────────────────────────────────
  await page.goto(`${BASE}/clientes?state=SP`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro por UF sem correspondência", /Nenhum cliente encontrado/i.test(body));

  await ctx.close();
}

// ── VENDEDOR: pode cadastrar, e o histórico respeita o RLS ──
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("vendedor enxerga a carteira de clientes", body.includes("Fazenda São João"));

  await page.goto(`${BASE}/clientes/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "Cliente do Vendedor");
  await page.fill("#phone", "4332221111");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/clientes\/[0-9a-f-]{36}/, { timeout: 15000 });
  check("vendedor consegue cadastrar cliente", page.url().includes("criado=1"));

  // Histórico: o cliente "João Marchioni" tem 1 orçamento, do vendedor.
  await page.goto(`${BASE}/clientes?q=Marchioni`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  // A lista existe em duas apresentações (tabela no desktop, cards no celular);
  // só uma está visível por vez.
  await page.locator("a:visible", { hasText: "João Marchioni" }).first().click();
  await page.waitForURL(/\/clientes\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(600);
  body = await page.innerText("body");
  check("histórico do cliente mostra o orçamento do vendedor", /ORC-2026-/.test(body));

  await page.screenshot({ path: "docs/screenshots/clientes-ficha-celular.png", fullPage: true });

  await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.screenshot({ path: "docs/screenshots/clientes-lista-celular.png" });

  await ctx.close();
}

// ── Um cliente do ADMIN não mostra o orçamento do vendedor ──
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await login(ctx, "vendedor@teste.local");
  await page.goto(`${BASE}/clientes?q=São João`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.locator("a:visible", { hasText: "Fazenda São João" }).first().click();
  await page.waitForURL(/\/clientes\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(600);
  const body = await page.innerText("body");
  check(
    "histórico esconde orçamento de outro vendedor (RLS)",
    /Nenhum orçamento ainda/i.test(body),
  );
  await ctx.close();
}

// ── Overflow horizontal em três larguras ────────────────────
{
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await login(ctx, "admin@teste.local");
    await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(700);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    check(`listagem sem rolagem horizontal em ${width}px`, over <= 0, `sobra ${over}px`);

    await page.goto(`${BASE}/clientes/novo`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const overForm = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    check(`formulário sem rolagem horizontal em ${width}px`, overForm <= 0, `sobra ${overForm}px`);
    if (width === 1440) await page.screenshot({ path: "docs/screenshots/clientes-form-desktop.png" });
    if (width === 1440) {
      await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
      await page.screenshot({ path: "docs/screenshots/clientes-lista-desktop.png" });
    }
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DO MÓDULO CLIENTES ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
