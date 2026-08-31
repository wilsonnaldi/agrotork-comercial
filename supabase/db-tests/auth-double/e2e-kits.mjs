/**
 * Validação de ponta a ponta do módulo KITS — Fase 3.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-kits.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);
const norm = (texto) => texto.replace(/ /g, " ").toLowerCase();
const contem = (texto, trecho) => norm(texto).includes(norm(trecho));

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

/** Busca um produto no editor de composição e espera o resultado aparecer. */
async function buscarComponente(page, termo) {
  await page.fill('input[type="search"]', termo);
  await page.waitForTimeout(1200);
}

// ── ADMIN: ciclo completo ───────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  // ── listagem ───────────────────────────────────────────
  await page.goto(`${BASE}/kits`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("listagem carrega o kit semeado", contem(body, "KIT PULVERIZAÇÃO"));
  check("listagem mostra as colunas de composição",
    contem(body, "Obrigatórios") && contem(body, "Opcionais") && contem(body, "Preço-base"));
  check("admin vê o botão de novo kit", contem(body, "Novo kit"));

  // ── validação do cabeçalho ─────────────────────────────
  await page.goto(`${BASE}/kits/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "K");
  await page.fill("#name", "ab");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código curto é recusado", contem(body, "Informe o código do kit"));
  check("nome curto é recusado", contem(body, "Informe o nome do kit"));
  check("o que foi digitado não se perde", (await page.inputValue("#code")) === "K");

  // ── criação ────────────────────────────────────────────
  await page.fill("#code", "k-f3"); // minúsculo de propósito
  await page.fill("#name", "Kit de teste Fase 3");
  await page.fill("#description", "Montado pelo e2e");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/kits\/[0-9a-f-]{36}\/editar/, { timeout: 15000 });
  await page.waitForTimeout(500);
  const editarUrl = page.url().split("?")[0];
  const kitId = editarUrl.split("/").slice(-2)[0];
  body = await page.innerText("body");
  check("criação leva direto para a montagem", contem(body, "Kit criado"));
  check("código é normalizado para maiúsculas", contem(body, "K-F3"));
  check("kit nasce vazio e a tela diz isso", contem(body, "Nenhum item obrigatório ainda"));

  // ── código duplicado ───────────────────────────────────
  await page.goto(`${BASE}/kits/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#code", "K-F3");
  await page.fill("#name", "Outro kit qualquer");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("código de kit duplicado é bloqueado", contem(body, "já está em uso pelo kit"));

  // ── adicionar componente obrigatório ───────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  await buscarComponente(page, "P-001");
  body = await page.innerText("body");
  check("busca de componente encontra por código", contem(body, "Bico de pulverização"));
  check("busca oferece os dois papéis", contem(body, "Obrigatório") && contem(body, "Opcional"));

  await page.click('button[name="item_type"][value="required"]');
  await page.waitForTimeout(1500);
  check("componente obrigatório entra no kit",
    sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id
         where k.code='K-F3' and ki.item_type='required';`) === "1");

  // ── adicionar componente opcional ──────────────────────
  await buscarComponente(page, "P-002");
  await page.click('button[name="item_type"][value="optional"]');
  await page.waitForTimeout(1500);
  check("componente opcional entra no kit",
    sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id
         where k.code='K-F3' and ki.item_type='optional';`) === "1");

  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("as duas seções aparecem separadas",
    contem(body, "Itens obrigatórios") && contem(body, "Itens opcionais"));
  check("a tela explica obrigatório × opcional",
    contem(body, "sempre entra quando o kit") && contem(body, "disponível"));
  check("a tela separa cadastro de seleção no orçamento",
    contem(body, "escolha do que entra em cada venda"));

  // ── produto duplicado ──────────────────────────────────
  await buscarComponente(page, "P-001");
  body = await page.innerText("body");
  check("produto que já está no kit é marcado como tal", contem(body, "Já está no kit"));

  // ── quantidade inválida ────────────────────────────────
  await buscarComponente(page, "P-004");
  const qtdInputs = page.locator('form input[name="quantity"]');
  await qtdInputs.last().fill("0");
  await page.click('button[name="item_type"][value="required"]');
  await page.waitForTimeout(1400);
  body = await page.innerText("body");
  check("quantidade zero é recusada", contem(body, "maior que zero"));
  check("produto não entrou com quantidade zero",
    sql(`select count(*) from public.kit_items ki
         join public.kits k on k.id=ki.kit_id join public.products p on p.id=ki.product_id
         where k.code='K-F3' and p.code='P-004';`) === "0");

  // ── fração em unidade que não aceita ───────────────────
  await buscarComponente(page, "P-004");
  await page.locator('form input[name="quantity"]').last().fill("2,5");
  await page.click('button[name="item_type"][value="required"]');
  await page.waitForTimeout(1400);
  body = await page.innerText("body");
  check("unidade UN recusa quantidade fracionada", contem(body, "não aceita quantidade fracionada"));

  // a mesma fração é aceita numa unidade que permite (P-002 usa M)
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const linhaOpcional = page.locator('form:has(input[name="item_id"])').last();
  await linhaOpcional.locator('input[name="quantity"]').fill("2,5");
  await linhaOpcional.locator('button[value="quantidade"]').click();
  await page.waitForTimeout(1500);
  check("unidade M aceita 2,5",
    sql(`select ki.quantity from public.kit_items ki
         join public.kits k on k.id=ki.kit_id join public.products p on p.id=ki.product_id
         where k.code='K-F3' and p.code='P-002';`) === "2.500");

  // ── produto inativo não é oferecido ────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  await buscarComponente(page, "Controlador de vazão");
  body = await page.innerText("body");
  check("produto inativo não aparece na busca de componentes",
    !contem(body, "Controlador de vazão AGRES") || contem(body, "Nenhum produto ativo encontrado"));

  // o servidor recusa mesmo com o campo forjado (tela velha / POST montado)
  const idInativo = sql("select id from public.products where code='P-003';");
  // P-004 ainda não está no kit, então a linha traz os botões de papel.
  await buscarComponente(page, "P-004");
  await page.evaluate((id) => {
    const form = document.querySelector('form input[name="product_id"]')?.closest("form");
    const campo = form?.querySelector('input[name="product_id"]');
    if (campo) campo.value = id;
  }, idInativo);
  await page.click('button[name="item_type"][value="optional"]');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("servidor recusa produto inativo mesmo com o campo forjado",
    contem(body, "está inativo e não pode ser adicionado"));
  check("produto inativo não entrou no kit",
    sql(`select count(*) from public.kit_items ki
         join public.kits k on k.id=ki.kit_id join public.products p on p.id=ki.product_id
         where k.code='K-F3' and p.code='P-003';`) === "0");

  // ── alternar papel ─────────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.locator('button:has-text("Tornar opcional")').first().click();
  await page.waitForTimeout(1500);
  check("obrigatório vira opcional",
    sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id
         where k.code='K-F3' and ki.item_type='optional';`) === "2");

  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.locator('button:has-text("Tornar obrigatório")').first().click();
  await page.waitForTimeout(1500);
  check("opcional volta a obrigatório",
    sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id
         where k.code='K-F3' and ki.item_type='required';`) === "1");

  // ── ficha do kit ───────────────────────────────────────
  await page.goto(`${BASE}/kits/${kitId}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("ficha mostra o cabeçalho", contem(body, "Kit de teste Fase 3") && contem(body, "K-F3"));
  check("ficha separa obrigatórios de opcionais",
    contem(body, "Obrigatórios") && contem(body, "Opcionais"));
  check("ficha mostra o resumo de contagens", contem(body, "Componentes"));
  check("ficha mostra o preço-base", contem(body, "Preço-base"));
  check("ficha explica opcional do kit × selecionado no orçamento",
    contem(body, "preço congelado"));
  check("ficha mostra código e marca dos componentes", contem(body, "ARAG"));

  // preço-base = só os obrigatórios (P-001 a R$ 150,00 × 1)
  check("preço-base soma apenas os obrigatórios", contem(body, "R$ 150,00"));
  await page.screenshot({ path: "docs/screenshots/kits-ficha-desktop.png", fullPage: true });

  // ── remover componente ─────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const antes = Number(sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id where k.code='K-F3';`));
  await page.locator('button:has-text("Remover")').last().click();
  await page.waitForTimeout(1500);
  const depois = Number(sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id where k.code='K-F3';`));
  check("remover componente funciona", depois === antes - 1, `${antes} → ${depois}`);

  // ── editar cabeçalho ───────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.fill("#name", "Kit de teste Fase 3 — revisado");
  await page.click('button[type="submit"]:has-text("Salvar alterações")');
  await page.waitForURL(/salvo=1/, { timeout: 15000 });
  await page.waitForTimeout(500);
  body = await page.innerText("body");
  check("edição do cabeçalho salva", contem(body, "revisado") && contem(body, "Alterações salvas"));

  // ── desativar / reativar ───────────────────────────────
  await page.click('button:has-text("Desativar kit")');
  await page.waitForTimeout(400);
  body = await page.innerText("body");
  check("desativação pede confirmação antes", contem(body, "Sim, desativar"));
  await page.click('button:has-text("Cancelar")');
  await page.waitForTimeout(300);
  body = await page.innerText("body");
  check("é possível desistir da desativação", !contem(body, "Sim, desativar"));

  await page.click('button:has-text("Desativar kit")');
  await page.waitForTimeout(300);
  await page.click('button:has-text("Sim, desativar")');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("kit desativado avisa na ficha", contem(body, "Kit inativo"));
  check("composição é preservada na desativação",
    Number(sql(`select count(*) from public.kit_items ki join public.kits k on k.id=ki.kit_id where k.code='K-F3';`)) === depois);

  await page.click('button:has-text("Reativar kit")');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("reativação funciona", contem(body, "Desativar kit") && !contem(body, "Reativar kit"));

  // ── kit incompleto ─────────────────────────────────────
  sql(`delete from public.kit_items ki using public.kits k where ki.kit_id=k.id and k.code='K-F3';`);
  await page.goto(`${BASE}/kits/${kitId}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("kit sem obrigatórios é marcado como incompleto", contem(body, "Kit incompleto"));

  await page.goto(`${BASE}/kits`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("listagem sinaliza o kit incompleto", contem(body, "Incompleto"));
  await page.screenshot({ path: "docs/screenshots/kits-lista-desktop.png" });

  // ── busca e filtro ─────────────────────────────────────
  await page.goto(`${BASE}/kits?q=pulveriza`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca de kit funciona", contem(body, "KIT PULVERIZAÇÃO") && !contem(body, "K-F3"));

  await page.goto(`${BASE}/kits?q=zzzzzz`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("busca sem resultado mostra estado vazio", contem(body, "Nenhum kit encontrado"));

  sql(`update public.kits set is_active=false where code='K-F3';`);
  await page.goto(`${BASE}/kits?status=inactive`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("filtro de inativos encontra o kit desativado", contem(body, "K-F3"));

  await ctx.close();
}

// ── VENDEDOR: consulta, não administra ──────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/kits`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  let body = await page.innerText("body");
  check("vendedor enxerga os kits ativos", contem(body, "KIT PULVERIZAÇÃO"));
  check("vendedor NÃO vê kit desativado na listagem", !contem(body, "K-F3"));
  check("vendedor NÃO vê botão de novo kit", !contem(body, "Novo kit"));
  check("vendedor não tem filtro de situação", !contem(body, "Inativos"));
  await page.screenshot({ path: "docs/screenshots/kits-lista-celular-vendedor.png" });

  const idAtivo = sql("select id from public.kits where code='K-001';");
  await page.goto(`${BASE}/kits/${idAtivo}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("vendedor abre a ficha e vê a composição", contem(body, "Bico de pulverização"));
  check("vendedor vê o preço de venda do componente", contem(body, "R$ 150,00"));
  check("vendedor NÃO vê custo (R$ 100,00)", !contem(body, "R$ 100,00"));
  check("vendedor NÃO vê Editar kit", !contem(body, "Editar kit"));
  check("vendedor NÃO vê Desativar kit", !contem(body, "Desativar kit"));

  // rotas de escrita
  const barradas = [
    ["/kits/novo", "novo kit"],
    [`/kits/${idAtivo}/editar`, "edição do kit"],
  ];
  for (const [rota, nome] of barradas) {
    await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(600);
    check(`vendedor é barrado em ${nome}`,
      page.url().includes("/dashboard") && page.url().includes("sem-permissao"),
      page.url().replace(BASE, ""));
  }

  await ctx.close();
}

// ── Sem rolagem horizontal ──────────────────────────────────
{
  const idKit = sql("select id from public.kits where code='K-001';");
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await login(ctx, "admin@teste.local");

    const rotas = [
      ["/kits", "listagem"],
      ["/kits/novo", "formulário"],
      [`/kits/${idKit}`, "ficha"],
      [`/kits/${idKit}/editar`, "editor de composição"],
    ];
    for (const [rota, nome] of rotas) {
      await page.goto(`${BASE}${rota}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(700);
      const over = await page.evaluate(
        () => document.documentElement.scrollWidth - window.innerWidth,
      );
      check(`${nome} sem rolagem horizontal em ${width}px`, over <= 0, `sobra ${over}px`);
    }

    if (width === 360) {
      await page.goto(`${BASE}/kits/${idKit}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(700);
      await page.screenshot({ path: "docs/screenshots/kits-ficha-celular.png", fullPage: true });
      await page.goto(`${BASE}/kits/${idKit}/editar`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(700);
      await page.screenshot({ path: "docs/screenshots/kits-editor-celular.png", fullPage: true });
    }
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DO MÓDULO KITS ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
