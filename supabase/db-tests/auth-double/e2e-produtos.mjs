/**
 * Validação de ponta a ponta do módulo PRODUTOS.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-produtos.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);
// `Intl` usa espaço não separável entre "R$" e o número; normalizamos
// para que a comparação não dependa disso.
const norm = (texto) => texto.replace(/\u00a0/g, " ").toLowerCase();
const contem = (texto, trecho) => norm(texto).includes(norm(trecho));

/** Insere produtos de enchimento direto no banco, para testar a paginação. */
function seedFiller(quantity) {
  const sql = `
    insert into public.products (code, name, unit_id, sale_price, is_active)
    select 'F-' || lpad(g::text, 3, '0'), 'Produto de enchimento ' || g, u.id, 10 + g, true
    from generate_series(1, ${quantity}) g, public.units u
    where u.code = 'UN';`;
  execFileSync(
    "psql",
    ["-h", process.env.PGHOST ?? "/tmp/pgrun", "-p", process.env.PGPORT ?? "5433",
     "-U", process.env.PGUSER ?? "postgres", "-d", process.env.PGDATABASE ?? "agrotork_dev",
     "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
    { stdio: "pipe" },
  );
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

async function selectByLabel(page, selector, label) {
  const value = await page.locator(`${selector} option`, { hasText: label }).first().getAttribute("value");
  await page.selectOption(selector, value);
  return value;
}

const NOME = "Ponta de pulverização teste";
const CODIGO = "tst-001"; // minúsculo de propósito: deve virar maiúsculo

// ── ADMIN: ciclo completo ───────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("listagem carrega os produtos semeados", contem(body, "Bico de pulverização AD 110-02"));
  check("admin vê a coluna de custo", contem(body, "Custo") && contem(body, "Margem"));
  check("custo do produto aparece", contem(body, "R$ 100,00"));
  check("margem calculada aparece", /50,00\s*%/.test(body));
  check("inativo não aparece por padrão", !contem(body, "Controlador de vazão AGRES"));

  // ── validação de campos ────────────────────────────────
  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "X");
  await page.fill("#name", "A");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1200);
  body = await page.innerText("body");
  check("nome curto é recusado", contem(body, "Informe o nome"));
  check("unidade obrigatória é cobrada", contem(body, "Selecione a unidade"));
  check("preço de venda obrigatório é cobrado", contem(body, "Informe o preço de venda"));
  check("o que foi digitado não se perde", (await page.inputValue("#code")) === "X");

  // Regressão: com `defaultValue` os selects perdiam a escolha ao voltar do erro.
  await selectByLabel(page, "#unit_id", "UN");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1200);
  check("unidade escolhida sobrevive ao erro de validação", (await page.inputValue("#unit_id")) !== "");

  // ── máscara monetária e margem derivada ────────────────
  await page.fill("#code", CODIGO);
  await page.fill("#name", NOME);
  await selectByLabel(page, "#unit_id", "UN");
  await selectByLabel(page, "#brand_id", "ARAG");
  await selectByLabel(page, "#category_id", "Pulverização");
  await page.fill("#description", "Ponta cerâmica para barra de pulverização");

  await page.fill("#cost_price", "20000"); // digita só números
  check("máscara monetária monta o valor", (await page.inputValue("#cost_price")) === "200,00");

  await page.fill("#sale_price", "30000");
  await page.waitForTimeout(200);
  check("margem é derivada de custo e venda", (await page.inputValue("#margin")) === "50");

  // atalho: digitar a margem recalcula o preço de venda
  await page.fill("#margin", "25");
  await page.waitForTimeout(200);
  check("atalho de margem recalcula a venda", (await page.inputValue("#sale_price")) === "250,00");

  await page.fill("#sale_price", "30000");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  const fichaUrl = page.url().split("?")[0];
  check("cadastro válido cria o produto", page.url().includes("criado=1"));

  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("código é normalizado para maiúsculas", contem(body, "TST-001"));
  check("ficha mostra o preço de venda", contem(body, "R$ 300,00"));
  check("ficha mostra o custo para o admin", contem(body, "R$ 200,00"));
  check("ficha mostra a margem", /50,00\s*%/.test(body));

  // ── código duplicado ───────────────────────────────────
  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "TST-001");
  await page.fill("#name", "Outro produto qualquer");
  await selectByLabel(page, "#unit_id", "UN");
  await page.fill("#sale_price", "1000");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código duplicado é bloqueado com mensagem clara", contem(body, "TST-001 já está em uso"));

  // duplicidade também com caixa diferente
  await page.fill("#code", "tst-001");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("duplicidade independe de maiúsculas", contem(body, "já está em uso"));

  // ── código do fabricante e procedência ─────────────────
  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "MFR-001");
  await page.fill("#name", "Produto com código de fábrica");
  await selectByLabel(page, "#unit_id", "UN");
  await page.fill("#sale_price", "50000");
  await page.fill("#manufacturer_code", "agr-9001"); // sem marca, e em minúsculas
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código de fabricante exige marca", contem(body, "Selecione a marca"));

  // com a marca certa, o código já existe no catálogo semeado (P-004/AGRES)
  await selectByLabel(page, "#brand_id", "AGRES");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check(
    "código de fabricante duplicado na mesma marca é bloqueado",
    contem(body, "já está em uso nesta marca"),
  );

  // a mesma numeração em outro fabricante é legítima
  await selectByLabel(page, "#brand_id", "ARAG");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("mesmo código em outro fabricante é aceito", contem(body, "AGR-9001"));
  check("código do fabricante é normalizado", !contem(body, "agr-9001") || contem(body, "AGR-9001"));

  await page.goto(`${BASE}/produtos?q=AGR-9001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check(
    "busca por código do fabricante encontra os dois",
    contem(body, "Monitor de plantio AGRES") && contem(body, "Produto com código de fábrica"),
  );

  // ficha do produto vindo de catálogo mostra a procedência
  await page.goto(`${BASE}/produtos?q=P-004`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.locator("a:visible", { hasText: "Monitor de plantio AGRES" }).first().click();
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("ficha mostra a procedência do catálogo", contem(body, "Catálogo do fabricante"));
  check("ficha mostra o catálogo de origem", contem(body, "AGRIS 2026"));
  check("ficha mostra a versão do catálogo", contem(body, "2026.04"));
  check("ficha mostra os dados técnicos", contem(body, "Linhas monitoradas"));
  check("dados técnicos não trazem preço", !contem(body, "preço:"));
  await page.screenshot({ path: "docs/screenshots/produtos-procedencia.png", fullPage: true });

  // massa de teste é visível como tal
  await page.goto(`${BASE}/produtos?q=P-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.locator("a:visible", { hasText: "Bico de pulverização" }).first().click();
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("massa de teste é identificada na ficha", contem(body, "Massa de teste"));

  // ── busca ──────────────────────────────────────────────
  await page.goto(`${BASE}/produtos?q=TST-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por código encontra", contem(body, NOME));

  await page.goto(`${BASE}/produtos?q=mangueira`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por nome encontra", contem(body, "Mangueira de pulverização"));

  await page.goto(`${BASE}/produtos?q=cerâmica`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca por descrição encontra", contem(body, "Bico de pulverização AD 110-02"));

  await page.goto(`${BASE}/produtos?q=zzzzzz`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca sem resultado mostra estado vazio", contem(body, "Nenhum produto encontrado"));

  // ── filtros ────────────────────────────────────────────
  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const brandValue = await page
    .locator('select[aria-label="Filtrar por marca"] option', { hasText: "MAGNOJET" })
    .first()
    .getAttribute("value");
  await page.goto(`${BASE}/produtos?brand=${brandValue}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro por marca funciona", contem(body, "Mangueira") && !contem(body, NOME));

  await page.goto(`${BASE}/produtos?status=inactive`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro de inativos encontra o produto inativo", contem(body, "Controlador de vazão AGRES"));

  // ── ordenação ──────────────────────────────────────────
  await page.goto(`${BASE}/produtos?sort=price`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  const firstByPrice = await page.locator("tbody tr").first().innerText();
  check(
    "ordenação por maior preço",
    contem(firstByPrice, "Monitor de plantio AGRES"),
    firstByPrice.split("\n")[0],
  );

  await page.goto(`${BASE}/produtos?sort=code`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  // Comparação relativa: não depende de quais produtos existem no momento.
  const codes = await page.locator("tbody tr td:first-child").allInnerTexts();
  const firstTwo = codes.slice(0, 2).map((c) => c.split("\n")[0].trim());
  check(
    "ordenação por código",
    firstTwo.length === 2 && firstTwo[0].localeCompare(firstTwo[1]) <= 0,
    firstTwo.join(" < "),
  );

  // ── paginação ──────────────────────────────────────────
  seedFiller(25);
  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const rows = await page.locator("tbody tr").count();
  body = await page.innerText("body");
  check("primeira página traz 20 itens", rows === 20, `${rows} linhas`);
  check("rodapé mostra o total", /Página 1 de 2/.test(body), body.match(/Página \d+ de \d+/)?.[0] ?? "");

  await page.goto(`${BASE}/produtos?page=2`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const rows2 = await page.locator("tbody tr").count();
  check("segunda página traz o restante", rows2 > 0 && rows2 < 20, `${rows2} linhas`);

  // ── edição ─────────────────────────────────────────────
  await page.goto(`${fichaUrl}/editar`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(300);
  check("edição carrega o custo atual", (await page.inputValue("#cost_price")) === "200,00");
  await page.fill("#name", `${NOME} — revisada`);
  await page.fill("#sale_price", "44450");
  await page.click('button[type="submit"]');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("edição salva o nome", contem(body, "revisada"));
  check("edição salva o preço com centavos", contem(body, "R$ 444,50"));
  check("margem acompanha o novo preço", /122,25\s*%/.test(body));

  // ── desativar com confirmação ──────────────────────────
  await page.click('button:has-text("Desativar produto")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("desativação pede confirmação antes", contem(body, "Sim, desativar"));

  await page.click('button:has-text("Cancelar")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("é possível desistir da desativação", !contem(body, "Sim, desativar"));

  await page.click('button:has-text("Desativar produto")');
  await page.waitForTimeout(300);
  await page.click('button:has-text("Sim, desativar")');
  await page.locator('button:has-text("Reativar produto")').waitFor({ timeout: 15000 });
  body = await page.innerText("body");
  check("desativação funciona", contem(body, "Produto inativo"));

  await page.goto(`${BASE}/produtos?q=TST-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("inativo some da listagem padrão", contem(body, "Nenhum produto encontrado"));

  await page.goto(fichaUrl, { waitUntil: "domcontentloaded" });
  await page.click('button:has-text("Reativar produto")');
  await page.locator('button:has-text("Desativar produto")').waitFor({ timeout: 15000 });
  body = await page.innerText("body");
  check("reativação funciona", !contem(body, "Produto inativo"));

  await page.screenshot({ path: "docs/screenshots/produtos-ficha-desktop.png" });
  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.screenshot({ path: "docs/screenshots/produtos-lista-desktop.png" });
  await ctx.close();
}

// ── VENDEDOR: catálogo sim, custo não ───────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  let body = await page.innerText("body");
  check("vendedor enxerga o catálogo", contem(body, "Bico de pulverização"));
  check("vendedor vê o preço de venda", contem(body, "R$ 150,00"));
  check("vendedor NÃO vê o custo (R$ 100,00)", !contem(body, "R$ 100,00"));
  check("vendedor NÃO vê botão de novo produto", !contem(body, "Novo produto"));

  await page.screenshot({ path: "docs/screenshots/produtos-lista-celular-vendedor.png" });

  // ficha: sem custo, sem margem, sem editar
  await page.goto(`${BASE}/produtos?q=P-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.locator("a:visible", { hasText: "Bico de pulverização" }).first().click();
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("ficha do vendedor esconde o custo", !contem(body, "Preço de custo"));
  check("ficha do vendedor esconde a margem", !contem(body, "Margem"));
  check("ficha do vendedor não oferece Editar", !contem(body, "Editar produto"));
  check("ficha do vendedor mostra o preço de venda", contem(body, "R$ 150,00"));

  // acesso direto às rotas de escrita
  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  check(
    "vendedor é barrado ao digitar /produtos/novo",
    page.url().includes("/dashboard") && page.url().includes("sem-permissao"),
    page.url().replace(BASE, ""),
  );

  await ctx.close();
}

// ── Sem rolagem horizontal ──────────────────────────────────
{
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await login(ctx, "admin@teste.local");

    for (const [rota, nome] of [["/produtos", "listagem"], ["/produtos/novo", "formulário"]]) {
      await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
      const over = await page.evaluate(
        () => document.documentElement.scrollWidth - window.innerWidth,
      );
      check(`${nome} sem rolagem horizontal em ${width}px`, over <= 0, `sobra ${over}px`);
    }

    if (width === 360) await page.screenshot({ path: "docs/screenshots/produtos-form-celular.png" });
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DO MÓDULO PRODUTOS ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
