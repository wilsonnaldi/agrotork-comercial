/**
 * Validação de ponta a ponta dos CADASTROS DE APOIO
 * (marcas, categorias e unidades de medida) — Fase 1.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-cadastros.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);
const norm = (texto) => texto.replace(/ /g, " ").toLowerCase();
const contem = (texto, trecho) => norm(texto).includes(norm(trecho));

/** Consulta direta ao banco — só para obter ids que a interface esconde. */
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

/** Abre a ficha de um registro a partir da listagem. */
async function abrir(page, listaUrl, rotulo) {
  await page.goto(listaUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.locator("a:visible", { hasText: rotulo }).first().click();
  await page.waitForURL(/[0-9a-f-]{36}$/, { timeout: 15000 });
  await page.waitForTimeout(400);
}

async function desativar(page, botao) {
  await page.click(`button:has-text("${botao}")`);
  await page.waitForTimeout(300);
  await page.click('button:has-text("Sim, desativar")');
  await page.waitForTimeout(1200);
}

// ── ADMIN ───────────────────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  // ── índice de Configurações ────────────────────────────
  await page.goto(`${BASE}/configuracoes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  let body = await page.innerText("body");
  check("Configurações reúne os três cadastros",
    contem(body, "Marcas") && contem(body, "Categorias") && contem(body, "Unidades de medida"));
  check("marca é apresentada como marca comercial, não fornecedor",
    contem(body, "Marca comercial que identifica o produto"));
  check("admin vê Configurações na navegação", contem(body, "Configurações"));
  await page.screenshot({ path: "docs/screenshots/configuracoes-desktop.png" });

  // ── MARCAS: listagem ───────────────────────────────────
  await page.goto(`${BASE}/configuracoes/marcas`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("listagem traz as marcas semeadas", contem(body, "ARAG") && contem(body, "MAGNOJET"));
  check("listagem mostra a situação", contem(body, "Ativo"));

  // ── MARCAS: validação ──────────────────────────────────
  await page.goto(`${BASE}/configuracoes/marcas/nova`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "A");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1200);
  body = await page.innerText("body");
  check("nome curto de marca é recusado", contem(body, "Informe o nome da marca"));
  check("o que foi digitado não se perde", (await page.inputValue("#name")) === "A");

  // ── MARCAS: criação ────────────────────────────────────
  await page.fill("#name", "Jacto");
  await page.fill("#description", "Marca comercial de pulverizadores");
  await page.click('button[type="submit"]');
  await page.waitForURL(/criado=1/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("criação de marca confirma e volta para a lista", contem(body, "Cadastro criado"));
  check("marca nova aparece na lista", contem(body, "Jacto"));

  // ── MARCAS: duplicidade ────────────────────────────────
  await page.goto(`${BASE}/configuracoes/marcas/nova`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "jacto"); // caixa diferente, mesma marca
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("marca duplicada é bloqueada, ignorando maiúsculas", contem(body, "Já existe uma marca chamada"));

  // ── MARCAS: edição ─────────────────────────────────────
  await abrir(page, `${BASE}/configuracoes/marcas?q=Jacto`, "Jacto");
  await page.fill("#name", "Jacto Máquinas");
  await page.click('button[type="submit"]');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("edição de marca salva", contem(body, "Alterações salvas") && contem(body, "Jacto Máquinas"));

  // ── MARCAS: busca e filtro ─────────────────────────────
  await page.goto(`${BASE}/configuracoes/marcas?q=kuhn`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca de marca funciona", contem(body, "KUHN") && !contem(body, "MAGNOJET"));

  await page.goto(`${BASE}/configuracoes/marcas?q=zzzzzz`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca sem resultado mostra estado vazio", contem(body, "Nenhum registro encontrado"));

  // ── MARCAS: desativação sem produtos ───────────────────
  await abrir(page, `${BASE}/configuracoes/marcas?q=DJI`, "DJI");
  const fichaDji = page.url();
  await page.click('button:has-text("Desativar marca")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("desativação pede confirmação antes", contem(body, "Sim, desativar"));
  await page.click('button:has-text("Cancelar")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("é possível desistir da desativação", !contem(body, "Sim, desativar"));

  await desativar(page, "Desativar marca");
  body = await page.innerText("body");
  check("marca desativada mostra situação Inativa",
    contem(body, "Inativa") && contem(body, "Reativar marca"));

  await page.goto(`${BASE}/configuracoes/marcas?status=inactive`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro de inativos encontra a marca desativada", contem(body, "DJI"));

  // marca inativa some do formulário de produto
  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const marcasOfertadas = await page.locator("#brand_id option").allInnerTexts();
  check("marca inativa não é oferecida em produto novo", !marcasOfertadas.some((o) => o.trim() === "DJI"),
    marcasOfertadas.length + " opções");

  // ── Registro inativo: a interface esconde, o SERVIDOR recusa ──
  // Simula uma tela velha (ou um POST forjado) reinserindo a opção
  // removida. Se a proteção estivesse só no HTML, isto passaria.
  const idDji = sql("select id from public.brands where name = 'DJI';");
  await page.fill("#code", "STALE-1");
  await page.fill("#name", "Produto com marca inativa");
  const unidade = await page.locator("#unit_id option", { hasText: "UN" }).first().getAttribute("value");
  await page.selectOption("#unit_id", unidade);
  await page.fill("#sale_price", "10000");
  await page.evaluate((id) => {
    const select = document.querySelector("#brand_id");
    const option = document.createElement("option");
    option.value = id;
    option.textContent = "DJI";
    select.appendChild(option);
    select.value = id;
  }, idDji);
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("servidor recusa marca inativa mesmo com o campo forjado",
    contem(body, "A marca selecionada está inativa"));
  check("produto com marca inativa não foi criado",
    sql("select count(*) from public.products where code = 'STALE-1';") === "0");

  // ── MARCAS: reativação ─────────────────────────────────
  await page.goto(fichaDji, { waitUntil: "domcontentloaded" });
  await page.click('button:has-text("Reativar marca")');
  await page.waitForTimeout(1200);
  body = await page.innerText("body");
  // "Inativa" contém "ativa": o sinal confiável é o botão do estado oposto.
  check("reativação de marca funciona",
    contem(body, "Desativar marca") && !contem(body, "Reativar marca"));

  // ── Desativar marca COM produtos preserva tudo ─────────
  await abrir(page, `${BASE}/configuracoes/marcas?q=ARAG`, "ARAG");
  body = await page.innerText("body");
  check("ficha avisa quantos produtos usam a marca", /\d+ produto\(s\) usam esta marca/.test(body));
  await page.click('button:has-text("Desativar marca")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("aviso explica que os produtos continuam vinculados",
    contem(body, "continuam vinculados e nada é perdido"));
  await page.click('button:has-text("Sim, desativar")');
  await page.waitForTimeout(1200);

  await page.goto(`${BASE}/produtos?q=P-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("produto da marca desativada continua na listagem", contem(body, "Bico de pulverização"));

  await page.locator("a:visible", { hasText: "Bico de pulverização" }).first().click();
  await page.waitForURL(/\/produtos\/[0-9a-f-]{36}/, { timeout: 15000 });
  await page.waitForTimeout(500);
  const fichaProduto = page.url().split("?")[0];
  body = await page.innerText("body");
  check("vínculo com a marca desativada é preservado na ficha", contem(body, "ARAG"));

  // o produto continua editável: desativar não invalida o que já existe
  await page.goto(`${fichaProduto}/editar`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  await page.fill("#sale_price", "16000");
  await page.click('button[type="submit"]');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("produto de marca desativada continua editável", contem(body, "R$ 160,00"));

  // devolve o estado
  await abrir(page, `${BASE}/configuracoes/marcas?q=ARAG&status=inactive`, "ARAG");
  await page.click('button:has-text("Reativar marca")');
  await page.waitForTimeout(1000);

  // ── CATEGORIAS ─────────────────────────────────────────
  await page.goto(`${BASE}/configuracoes/categorias`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("listagem de categorias carrega", contem(body, "Implementos") && contem(body, "Pulverização"));

  await page.goto(`${BASE}/configuracoes/categorias/nova`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "Colheita");
  await page.fill("#description", "Plataformas, esteiras e peças de colheita");
  await page.click('button[type="submit"]');
  await page.waitForURL(/criado=1/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("categoria criada aparece na lista", contem(body, "Colheita"));

  await page.goto(`${BASE}/configuracoes/categorias/nova`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", "colheita");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("categoria duplicada é bloqueada", contem(body, "Já existe uma categoria chamada"));

  await abrir(page, `${BASE}/configuracoes/categorias?q=Colheita`, "Colheita");
  await desativar(page, "Desativar categoria");
  body = await page.innerText("body");
  check("categoria desativada", contem(body, "Reativar categoria"));

  await page.goto(`${BASE}/produtos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const categoriasOfertadas = await page.locator("#category_id option").allInnerTexts();
  check("categoria inativa não é oferecida em produto novo",
    !categoriasOfertadas.some((o) => o.trim() === "Colheita"));

  // ── UNIDADES ───────────────────────────────────────────
  await page.goto(`${BASE}/configuracoes/unidades`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("listagem de unidades carrega", contem(body, "UN") && contem(body, "KG"));

  await page.goto(`${BASE}/configuracoes/unidades/nova`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("tela avisa que L e LT não são equivalentes",
    contem(body, "não são tratados") || contem(body, "não são tratadas"));

  await page.fill("#code", "C X"); // espaço não é permitido
  await page.fill("#name", "Caixa");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código de unidade com espaço é recusado", contem(body, "Use apenas letras, números ou barra"));

  await page.fill("#code", "cx"); // minúsculo de propósito
  await page.fill("#name", "Caixa");
  await page.click('button[type="submit"]');
  await page.waitForURL(/criado=1/, { timeout: 15000 });
  await page.waitForTimeout(600);
  body = await page.innerText("body");
  check("código da unidade é normalizado para maiúsculas",
    body.includes("CX") && sql("select code from public.units where upper(code) = 'CX';") === "CX");

  await page.goto(`${BASE}/configuracoes/unidades/nova`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "CX");
  await page.fill("#name", "Caixa repetida");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código de unidade duplicado é bloqueado", contem(body, "já está em uso"));

  // LT é uma unidade nova, distinta de L. Nada é presumido.
  await page.fill("#code", "LT");
  await page.fill("#name", "Litro");
  await page.click('button[type="submit"]');
  await page.waitForURL(/criado=1/, { timeout: 15000 });
  await page.waitForTimeout(600);
  check("LT e L coexistem como unidades distintas",
    sql("select count(*) from public.units where upper(code) in ('L','LT');") === "2");

  await page.goto(`${BASE}/configuracoes/unidades?q=LT`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca de unidade por código funciona", contem(body, "LT"));

  // fração
  await abrir(page, `${BASE}/configuracoes/unidades?q=CX`, "CX");
  check("unidade nova nasce sem fração", !(await page.isChecked('input[name="allows_fraction"]')));
  await page.check('input[name="allows_fraction"]');
  await page.click('button[type="submit"]');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  check("fração é gravada",
    sql("select allows_fraction from public.units where code = 'CX';") === "t");

  // desativar unidade usada por produto preserva o produto.
  // A busca por "UN" também casa com "Conjunto" e "Unidade"; aqui o alvo
  // precisa ser exato, então a ficha é aberta pelo id.
  const idUn = sql("select id from public.units where code = 'UN';");
  await page.goto(`${BASE}/configuracoes/unidades/${idUn}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("ficha da unidade avisa quantos produtos a usam", /\d+ produto\(s\) usam esta unidade/.test(body));
  await desativar(page, "Desativar unidade");

  await page.goto(`${BASE}/produtos?q=P-001`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("produto de unidade desativada continua listado", contem(body, "Bico de pulverização"));

  await page.goto(`${BASE}/configuracoes/unidades/${idUn}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  await page.click('button:has-text("Reativar unidade")');
  await page.waitForTimeout(1000);
  body = await page.innerText("body");
  check("reativação de unidade funciona",
    contem(body, "Desativar unidade") && !contem(body, "Reativar unidade"));

  await page.goto(`${BASE}/configuracoes/marcas`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.screenshot({ path: "docs/screenshots/cadastros-marcas-desktop.png" });
  await ctx.close();
}

// ── VENDEDOR: consulta o catálogo, não administra os cadastros ──
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("vendedor não vê Configurações na navegação", !contem(body, "Configurações"));

  const barradas = [
    ["/configuracoes", "índice"],
    ["/configuracoes/marcas", "marcas"],
    ["/configuracoes/marcas/nova", "nova marca"],
    ["/configuracoes/categorias", "categorias"],
    ["/configuracoes/unidades", "unidades"],
    ["/configuracoes/unidades/nova", "nova unidade"],
  ];
  for (const [rota, nome] of barradas) {
    await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(600);
    check(`vendedor é barrado em ${nome}`,
      page.url().includes("/dashboard") && page.url().includes("sem-permissao"),
      page.url().replace(BASE, ""));
  }

  // o que ele PODE: enxergar os cadastros ativos através do catálogo
  await page.goto(`${BASE}/produtos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("vendedor consulta marcas e categorias pelo catálogo",
    contem(body, "ARAG") || contem(body, "Pulverização"));

  const filtroMarcas = await page
    .locator('select[aria-label="Filtrar por marca"] option')
    .allInnerTexts();
  check("vendedor tem os cadastros ativos nos filtros", filtroMarcas.length > 1,
    filtroMarcas.length + " opções");

  await ctx.close();
}

// ── Sem rolagem horizontal ──────────────────────────────────
{
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await login(ctx, "admin@teste.local");

    const rotas = [
      ["/configuracoes", "índice"],
      ["/configuracoes/marcas", "listagem"],
      ["/configuracoes/marcas/nova", "formulário"],
      ["/configuracoes/unidades", "unidades"],
    ];
    for (const [rota, nome] of rotas) {
      await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
      const over = await page.evaluate(
        () => document.documentElement.scrollWidth - window.innerWidth,
      );
      check(`${nome} sem rolagem horizontal em ${width}px`, over <= 0, `sobra ${over}px`);
    }

    if (width === 360) {
      await page.goto(`${BASE}/configuracoes/marcas`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
      await page.screenshot({ path: "docs/screenshots/cadastros-marcas-celular.png" });
      await page.goto(`${BASE}/configuracoes/unidades/nova`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
      await page.screenshot({ path: "docs/screenshots/cadastros-form-celular.png" });
    }
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DOS CADASTROS DE APOIO ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
