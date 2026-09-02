/**
 * Validação de ponta a ponta do módulo ORÇAMENTOS — Fase 4.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-orcamentos.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") => {
  const linha = `${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`;
  // Falha aparece na hora: se a suíte quebrar mais adiante, o motivo já
  // está no log em vez de se perder com o resumo final.
  if (!pass) console.log(linha);
  results.push(linha);
};
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

async function buscar(page, termo) {
  await page.fill('input[type="search"]', termo);
  await page.waitForTimeout(1200);
}

/** Total gravado no banco, em texto — a fonte de verdade do teste. */
const totalDoBanco = (numero) =>
  sql(`select total::text from public.quotes where number = '${numero}';`);
const subtotalDoBanco = (numero) =>
  sql(`select subtotal::text from public.quotes where number = '${numero}';`);

let numeroAdmin = "";
let idAdmin = "";

// ── ADMIN: ciclo completo ───────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  // ── listagem vazia ─────────────────────────────────────
  await page.goto(`${BASE}/orcamentos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("listagem de orçamentos abre", contem(body, "Orçamentos"));
  check("admin vê o botão de novo orçamento", contem(body, "Novo orçamento"));

  // ── criação ────────────────────────────────────────────
  await page.goto(`${BASE}/orcamentos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(400);
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1300);
  body = await page.innerText("body");
  check("cliente é obrigatório", contem(body, "Selecione o cliente"));

  const idCliente = sql("select id from public.customers where name = 'Fazenda São João';");
  await page.selectOption("#customer_id", idCliente);
  await page.fill("#payment_terms", "30/60/90 dias");
  await page.fill("#delivery_terms", "15 dias após confirmação");
  await page.fill("#notes", "Proposta gerada pelo e2e");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/orcamentos\/[0-9a-f-]{36}\/editar/, { timeout: 15000 });
  await page.waitForTimeout(600);
  const editarUrl = page.url().split("?")[0];
  idAdmin = editarUrl.split("/").slice(-2)[0];
  numeroAdmin = sql(`select number from public.quotes where id = '${idAdmin}';`);
  body = await page.innerText("body");
  check("criação leva direto para a montagem", contem(body, "criado"));
  check("número é gerado pelo sistema", /^ORC-\d{4}-\d{4}$/.test(numeroAdmin), numeroAdmin);
  check("orçamento nasce como rascunho",
    sql(`select status from public.quotes where id='${idAdmin}';`) === "draft");

  // ── produto avulso ─────────────────────────────────────
  await buscar(page, "P-001");
  body = await page.innerText("body");
  check("busca de produto encontra", contem(body, "Bico de pulverização"));

  await page.locator('form input[name="quantity"]').last().fill("2");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);
  check("produto entra com quantidade 2 e total de linha correto",
    sql(`select line_total::text from public.quote_items qi join public.quotes q on q.id=qi.quote_id
         where q.id='${idAdmin}' and qi.code_snapshot='P-001';`) === "300.00");
  check("subtotal recalculado pelo banco", subtotalDoBanco(numeroAdmin) === "300.00");

  // ── segundo produto ────────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await buscar(page, "P-002");
  await page.locator('form input[name="quantity"]').last().fill("3");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);
  check("segundo produto soma ao subtotal", subtotalDoBanco(numeroAdmin) === "396.00",
    subtotalDoBanco(numeroAdmin));

  // ── quantidade fracionada em unidade UN ────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await buscar(page, "P-004");
  await page.locator('form input[name="quantity"]').last().fill("1,5");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("unidade UN recusa quantidade fracionada", contem(body, "não aceita quantidade fracionada"));
  check("produto fracionado não entrou",
    sql(`select count(*) from public.quote_items qi join public.quotes q on q.id=qi.quote_id
         where q.id='${idAdmin}' and qi.code_snapshot='P-004';`) === "0");

  // ── produto inativo não é oferecido ────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await buscar(page, "Controlador de vazão");
  body = await page.innerText("body");
  check("produto inativo não aparece na busca",
    !contem(body, "Controlador de vazão AGRES") || contem(body, "Nenhum produto ativo encontrado"));

  // Não basta some da busca: o servidor tem de recusar o id forjado. É a
  // trava em que a carga de catálogo se apoia — 112 produtos entram
  // inativos justamente porque este caminho não existe.
  const idProdutoInativo = sql("select id from public.products where is_active = false limit 1;");
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await buscar(page, "P-001");
  await page.$eval(
    'form input[name="product_id"]',
    (el, valor) => { el.value = valor; },
    idProdutoInativo,
  );
  await page.locator('form input[name="quantity"]').last().fill("1");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("servidor recusa produto inativo pelo id forjado", contem(body, "está inativo"));
  check("produto inativo não entrou no orçamento",
    sql(`select count(*) from public.quote_items qi
         join public.products p on p.id = qi.product_id
         where qi.quote_id='${idAdmin}' and p.is_active = false;`) === "0");

  // ── kits: incompleto e inativo ficam de fora ───────────
  await page.goto(`${editarUrl}?aba=kits`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(900);
  body = await page.innerText("body");
  check("kit utilizável é oferecido", contem(body, "KIT NAVEGAÇÃO"));
  check("kit INCOMPLETO não é oferecido", !contem(body, "KIT INCOMPLETO"));
  check("kit DESATIVADO não é oferecido", !contem(body, "KIT DESATIVADO"));

  // servidor recusa mesmo com o id forjado
  const idIncompleto = sql("select id from public.kits where code='K-003';");
  const idInativo = sql("select id from public.kits where code='K-004';");
  await page.goto(`${editarUrl}?kit=${idIncompleto}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.click('button[type="submit"]:has-text("Adicionar kit")');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("servidor recusa kit incompleto pela URL", contem(body, "não tem nenhum item obrigatório"));

  await page.goto(`${editarUrl}?kit=${idInativo}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.click('button[type="submit"]:has-text("Adicionar kit")');
  await page.waitForTimeout(1500);
  body = await page.innerText("body");
  check("servidor recusa kit inativo pela URL", contem(body, "está inativo"));
  check("nenhum kit inválido entrou",
    sql(`select count(*) from public.quote_items where quote_id='${idAdmin}' and kind='kit';`) === "0");

  // ── kit com opcionais ──────────────────────────────────
  const idKit = sql("select id from public.kits where code='K-002';");
  await page.goto(`${editarUrl}?kit=${idKit}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("tela de opcionais mostra obrigatórios e opcionais",
    contem(body, "Obrigatórios — sempre entram") && contem(body, "escolha o que entra nesta venda"));
  check("tela avisa que a escolha não altera o cadastro do kit",
    contem(body, "Não altera o cadastro do kit"));

  const obrigatorios = await page.locator('input[type="checkbox"][disabled]').count();
  check("obrigatório aparece marcado e bloqueado", obrigatorios >= 1, `${obrigatorios} bloqueado(s)`);

  // adiciona SEM opcionais: preço-base R$ 150,00
  await page.click('button[type="submit"]:has-text("Adicionar kit")');
  await page.waitForTimeout(1800);
  check("kit entra com o preço-base dos obrigatórios",
    sql(`select unit_price::text from public.quote_items where quote_id='${idAdmin}' and kind='kit';`) === "150.00");
  check("snapshot guarda TODOS os componentes do kit",
    sql(`select jsonb_array_length(components_snapshot) from public.quote_items
         where quote_id='${idAdmin}' and kind='kit';`) === "3");
  check("opcionais não escolhidos ficam registrados como não selecionados",
    sql(`select count(*) from public.quote_items qi, jsonb_array_elements(qi.components_snapshot) c
         where qi.quote_id='${idAdmin}' and qi.kind='kit' and (c->>'selected')::boolean = false;`) === "2");

  // ── ajustar opcionais do kit já no orçamento ───────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("composição do kit aparece na linha do orçamento", contem(body, "Opcionais não incluídos"));

  await page.click('a:has-text("Ajustar opcionais deste kit")');
  await page.waitForURL(/item=/, { timeout: 15000 });
  await page.waitForTimeout(700);
  body = await page.innerText("body");
  check("ajuste usa os preços congelados", contem(body, "congelados"));

  // marca o opcional P-002 (R$ 32,00) -> kit passa a R$ 182,00
  const idP002 = sql("select id from public.products where code='P-002';");
  await page.check(`input[name="opcional"][value="${idP002}"]`);
  await page.click('button[type="submit"]:has-text("Salvar opcionais")');
  await page.waitForTimeout(1800);
  check("opcional marcado entra no preço do kit",
    sql(`select unit_price::text from public.quote_items where quote_id='${idAdmin}' and kind='kit';`) === "182.00");

  // desmarca de novo
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.click('a:has-text("Ajustar opcionais deste kit")');
  await page.waitForTimeout(800);
  await page.uncheck(`input[name="opcional"][value="${idP002}"]`);
  await page.click('button[type="submit"]:has-text("Salvar opcionais")');
  await page.waitForTimeout(1800);
  check("desmarcar opcional volta o preço do kit",
    sql(`select unit_price::text from public.quote_items where quote_id='${idAdmin}' and kind='kit';`) === "150.00");

  // marca de novo, para o resto do teste
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  await page.click('a:has-text("Ajustar opcionais deste kit")');
  await page.waitForTimeout(800);
  await page.check(`input[name="opcional"][value="${idP002}"]`);
  await page.click('button[type="submit"]:has-text("Salvar opcionais")');
  await page.waitForTimeout(1800);

  // ── quantidade do kit ──────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const linhaKit = page.locator('form:has(input[name="item_id"])').last();
  await linhaKit.locator('input[name="quantity"]').fill("3");
  await linhaKit.locator('button[value="atualizar"]').click();
  await page.waitForTimeout(1800);
  check("quantidade do kit multiplica a linha",
    sql(`select line_total::text from public.quote_items where quote_id='${idAdmin}' and kind='kit';`) === "546.00");

  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("composição mostra a quantidade efetiva do componente", contem(body, "3 UN"));

  // kit não aceita fração
  const linhaKit2 = page.locator('form:has(input[name="item_id"])').last();
  await linhaKit2.locator('input[name="quantity"]').fill("1,5");
  await linhaKit2.locator('button[value="atualizar"]').click();
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("kit não aceita quantidade fracionada", contem(body, "não aceita quantidade fracionada"));

  // ── desconto de item ───────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const linhaProduto = page.locator('form:has(input[name="item_id"])').first();
  await linhaProduto.locator('input[name="discount_percent"]').fill("10");
  await linhaProduto.locator('button[value="atualizar"]').click();
  await page.waitForTimeout(1800);
  check("desconto por item aplicado pelo banco",
    sql(`select line_total::text from public.quote_items
         where quote_id='${idAdmin}' and code_snapshot='P-001';`) === "270.00");

  // ── desconto e frete do orçamento ──────────────────────
  const subtotalAtual = subtotalDoBanco(numeroAdmin);
  check("subtotal com produtos, kit e desconto de item", subtotalAtual === "912.00", subtotalAtual);

  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.fill("#discount_percent", "10");
  await page.fill("#shipping_amount", "5000"); // R$ 50,00 digitando só números
  await page.click('button[type="submit"]:has-text("Aplicar")');
  await page.waitForTimeout(1800);
  check("desconto percentual e frete no total",
    totalDoBanco(numeroAdmin) === "870.80", totalDoBanco(numeroAdmin));

  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("tela mostra subtotal, desconto, frete e total",
    contem(body, "Subtotal") && contem(body, "Frete") && contem(body, "R$ 870,80"));
  check("tela declara que o total vem do banco", contem(body, "calculados pelo banco"));

  // desconto acima de 100% é recusado
  await page.fill("#discount_percent", "150");
  await page.click('button[type="submit"]:has-text("Aplicar")');
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("desconto acima de 100% é recusado", contem(body, "não passa de 100"));
  check("total não mudou com o desconto inválido", totalDoBanco(numeroAdmin) === "870.80");

  await page.screenshot({ path: "docs/screenshots/orcamentos-editor-desktop.png", fullPage: true });

  // ── remover item ───────────────────────────────────────
  await page.goto(editarUrl, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const antes = Number(sql(`select count(*) from public.quote_items where quote_id='${idAdmin}';`));
  await page.locator('button:has-text("Remover")').nth(1).click();
  await page.waitForTimeout(1800);
  const depois = Number(sql(`select count(*) from public.quote_items where quote_id='${idAdmin}';`));
  check("remover item funciona", depois === antes - 1, `${antes} → ${depois}`);

  // ── salvar e reabrir ───────────────────────────────────
  await page.goto(`${BASE}/orcamentos/${idAdmin}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  const totalGravado = totalDoBanco(numeroAdmin);
  check("ficha reabre com o número", contem(body, numeroAdmin));
  check("ficha mostra o cliente", contem(body, "Fazenda São João"));
  check("ficha mostra as condições comerciais",
    contem(body, "30/60/90 dias") && contem(body, "15 dias após confirmação"));
  check("ficha mostra a composição congelada do kit", contem(body, "Opcionais não incluídos"));
  check("ficha explica o congelamento", contem(body, "cópias congeladas"));
  await page.screenshot({ path: "docs/screenshots/orcamentos-ficha-desktop.png", fullPage: true });

  // ── HISTÓRICO: o catálogo muda, o orçamento não ────────
  const itensAntes = sql(`select md5(string_agg(qi.code_snapshot || qi.name_snapshot || qi.unit_price::text || qi.line_total::text || coalesce(qi.components_snapshot::text,''), '|' order by qi.sort_order))
                          from public.quote_items qi where qi.quote_id='${idAdmin}';`);

  sql(`update public.products set sale_price = 9999, name = 'NOME TROCADO PELO TESTE' where code in ('P-001','P-002');`);
  sql(`delete from public.kit_items ki using public.products p, public.kits k
       where ki.product_id=p.id and ki.kit_id=k.id and k.code='K-002' and p.code='P-002';`);
  sql(`update public.kits set name='KIT RENOMEADO', is_active=false where code='K-002';`);

  await page.goto(`${BASE}/orcamentos/${idAdmin}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(900);
  body = await page.innerText("body");
  const itensDepois = sql(`select md5(string_agg(qi.code_snapshot || qi.name_snapshot || qi.unit_price::text || qi.line_total::text || coalesce(qi.components_snapshot::text,''), '|' order by qi.sort_order))
                           from public.quote_items qi where qi.quote_id='${idAdmin}';`);

  check("itens do orçamento não mudaram com o catálogo", itensAntes === itensDepois);
  check("total do orçamento não mudou", totalDoBanco(numeroAdmin) === totalGravado);
  check("nome antigo do produto continua no orçamento", contem(body, "Bico de pulverização"));
  check("nome novo do produto NÃO aparece", !contem(body, "NOME TROCADO PELO TESTE"));
  check("nome antigo do kit continua no orçamento", contem(body, "KIT NAVEGAÇÃO"));
  check("kit renomeado NÃO aparece", !contem(body, "KIT RENOMEADO"));

  // ── status ─────────────────────────────────────────────
  await page.click('button:has-text("Marcar como Enviado")');
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("rascunho vira enviado", contem(body, "Situação atualizada"));
  check("carimbo de envio gravado",
    sql(`select sent_at is not null from public.quotes where id='${idAdmin}';`) === "t");

  await page.click('button:has-text("Marcar como Aprovado")');
  await page.waitForTimeout(1600);
  check("enviado vira aprovado",
    sql(`select status from public.quotes where id='${idAdmin}';`) === "approved");

  await page.goto(`${BASE}/orcamentos/${idAdmin}/editar`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  check("admin ainda edita orçamento aprovado", page.url().includes("/editar"),
    page.url().replace(BASE, ""));

  // ── orçamento vazio não pode ser enviado ───────────────
  await page.goto(`${BASE}/orcamentos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(400);
  await page.selectOption("#customer_id", idCliente);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/editar/, { timeout: 15000 });
  const idVazio = page.url().split("/").slice(-2)[0].split("?")[0];
  await page.goto(`${BASE}/orcamentos/${idVazio}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.click('button:has-text("Marcar como Enviado")');
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("orçamento sem itens não pode ser enviado", contem(body, "sem itens não pode ser enviado"));

  // ── descartar rascunho ─────────────────────────────────
  await page.click('button:has-text("Descartar rascunho")');
  await page.waitForTimeout(400);
  await page.click('button:has-text("Sim, descartar")');
  await page.waitForTimeout(1600);
  body = await page.innerText("body");
  check("rascunho é descartado", contem(body, "Rascunho descartado"));
  check("descarte é lógico, não físico",
    sql(`select deleted_at is not null from public.quotes where id='${idVazio}';`) === "t");

  // ── busca e filtro ─────────────────────────────────────
  await page.goto(`${BASE}/orcamentos?status=approved`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("filtro por situação funciona", contem(body, numeroAdmin));

  await page.goto(`${BASE}/orcamentos?q=zzzzzz`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("busca sem resultado mostra estado vazio", contem(body, "Nenhum orçamento encontrado"));

  await page.goto(`${BASE}/orcamentos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("listagem mostra número, cliente, total e situação",
    contem(body, numeroAdmin) && contem(body, "Fazenda São João") && contem(body, "Aprovado"));
  check("admin vê a coluna de vendedor", contem(body, "Vendedor"));
  await page.screenshot({ path: "docs/screenshots/orcamentos-lista-desktop.png" });

  await ctx.close();
}

// ── VENDEDOR: isolamento ────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/orcamentos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  let body = await page.innerText("body");
  check("vendedor NÃO vê orçamento de outro vendedor", !contem(body, numeroAdmin));
  check("vendedor não tem filtro por vendedor", !contem(body, "Todos os vendedores"));

  // acesso direto ao orçamento alheio
  await page.goto(`${BASE}/orcamentos/${idAdmin}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("vendedor é barrado ao abrir orçamento alheio",
    contem(body, "não encontrada") || contem(body, "404") || !contem(body, numeroAdmin));

  // cria o próprio
  await page.goto(`${BASE}/orcamentos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  const idCliente = sql("select id from public.customers where name = 'Agropecuária Canedo Ltda';");
  await page.selectOption("#customer_id", idCliente);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/editar/, { timeout: 15000 });
  await page.waitForTimeout(600);
  const idVendedor = page.url().split("/").slice(-2)[0].split("?")[0];
  check("vendedor cria o próprio orçamento",
    sql(`select owner_id from public.quotes where id='${idVendedor}';`) ===
      "bbbbbbbb-0000-4000-8000-000000000002");

  await buscar(page, "P-001");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);
  check("vendedor monta o próprio orçamento",
    sql(`select count(*) from public.quote_items where quote_id='${idVendedor}';`) === "1");

  await page.goto(`${BASE}/orcamentos/${idVendedor}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("vendedor NÃO vê custo no orçamento", !contem(body, "R$ 100,00"));
  await page.screenshot({ path: "docs/screenshots/orcamentos-ficha-celular.png", fullPage: true });

  // aprovado trava o vendedor.
  // O atalho `draft -> approved` deixou de existir: a migration
  // 20260901201459 passou a validar a máquina de estados no banco, e o
  // trigger trg_quotes_validate_status_transition recusa o salto. O caminho
  // válido é o mesmo que a interface oferece — enviar e só então aprovar.
  sql(`update public.quotes set status='sent'     where id='${idVendedor}';`);
  sql(`update public.quotes set status='approved' where id='${idVendedor}';`);
  await page.goto(`${BASE}/orcamentos/${idVendedor}/editar`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("vendedor é redirecionado ao tentar editar aprovado",
    page.url().includes("bloqueado") && contem(body, "não pode ser editado"),
    page.url().replace(BASE, ""));
  check("vendedor não vê botão de editar em aprovado", !contem(body, "Editar itens"));

  await ctx.close();
}

// ── Sem rolagem horizontal ──────────────────────────────────
{
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await login(ctx, "admin@teste.local");

    const rotas = [
      ["/orcamentos", "listagem"],
      ["/orcamentos/novo", "formulário"],
      [`/orcamentos/${idAdmin}`, "ficha"],
      [`/orcamentos/${idAdmin}/editar`, "montagem"],
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
      await page.goto(`${BASE}/orcamentos`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(700);
      await page.screenshot({ path: "docs/screenshots/orcamentos-lista-celular.png" });
      await page.goto(`${BASE}/orcamentos/${idAdmin}/editar`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(700);
      await page.screenshot({ path: "docs/screenshots/orcamentos-editor-celular.png", fullPage: true });
    }
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DO MÓDULO ORÇAMENTOS ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
