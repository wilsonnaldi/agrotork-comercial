/**
 * Validação de ponta a ponta do PDF e do COMPARTILHAMENTO — Fase 5.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois: BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-pdf-compartilhamento.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") => {
  const linha = `${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`;
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

/** Extrai o texto do PDF com o pdftotext, para conferir o conteúdo real. */
function pdfText(buffer, nome) {
  const caminho = `/tmp/${nome}`;
  writeFileSync(caminho, buffer);
  return execFileSync("pdftotext", ["-layout", caminho, "-"], { stdio: "pipe" }).toString();
}

/**
 * Busca uma rota AUTENTICADA usando o jarro de cookies do próprio navegador.
 *
 * `page.request` é um cliente HTTP em Node, com jarro de cookies separado,
 * e ele aplica o atributo `Secure` ao pé da letra: cookie Secure só viaja
 * em https. O Chromium é mais permissivo com 127.0.0.1 — trata como origem
 * confiável e manda o cookie mesmo em http —, e é por isso que a sessão
 * funcionava em toda navegação e sumia só nestas chamadas: o proxy não via
 * usuário, redirecionava para /login, o `page.request` seguia o 307 e o
 * teste recebia 200 com o HTML da tela de login no lugar do PDF.
 *
 * O cookie sai Secure porque o e2e sobe a aplicação com `next start`
 * (NODE_ENV=production) e essa é a regra de produção — ela não muda por
 * causa de teste. Buscando de dentro da página, a requisição parte do
 * navegador já autenticado, e o `fetch` de mesma origem enxerga todos os
 * cabeçalhos da resposta, inclusive o `content-disposition`.
 *
 * Devolve a mesma interface do APIResponse do Playwright para as
 * verificações continuarem lendo `status()`, `headers()` e `body()`.
 */
async function buscaAutenticado(page, rota) {
  const bruto = await page.evaluate(async (alvo) => {
    const r = await fetch(alvo, { credentials: "same-origin" });
    const bytes = new Uint8Array(await r.arrayBuffer());
    let binario = "";
    for (const b of bytes) binario += String.fromCharCode(b);
    return { status: r.status, headers: Object.fromEntries(r.headers.entries()), base64: btoa(binario) };
  }, rota);
  return {
    status: () => bruto.status,
    headers: () => bruto.headers,
    body: async () => Buffer.from(bruto.base64, "base64"),
  };
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

let idQuote = "";
let numero = "";
let linkPublico = "";
let tokenPublico = "";

// ── ADMIN: monta o orçamento, gera PDF e link ───────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  // ── orçamento com produto + kit com opcional ───────────
  const idCliente = sql("select id from public.customers where name = 'Fazenda São João';");
  await page.goto(`${BASE}/orcamentos/novo`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  await page.selectOption("#customer_id", idCliente);
  await page.fill("#payment_terms", "30/60/90 dias");
  await page.fill("#delivery_terms", "15 dias após confirmação");
  await page.fill("#notes", "Proposta sujeita a disponibilidade de estoque.");
  await page.fill("#internal_notes", "MARGEM APERTADA NAO MOSTRAR AO CLIENTE");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/editar/, { timeout: 15000 });
  await page.waitForTimeout(600);
  const editarUrl = page.url().split("?")[0];
  idQuote = editarUrl.split("/").slice(-2)[0];
  numero = sql(`select number from public.quotes where id='${idQuote}';`);

  await page.fill('input[type="search"]', "P-001");
  await page.waitForTimeout(1200);
  await page.locator('form input[name="quantity"]').last().fill("2");
  await page.locator('form:has(input[name="product_id"]) button[type="submit"]').last().click();
  await page.waitForTimeout(1600);

  const idKit = sql("select id from public.kits where code='K-002';");
  const idP002 = sql("select id from public.products where code='P-002';");
  await page.goto(`${editarUrl}?kit=${idKit}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  await page.check(`input[name="opcional"][value="${idP002}"]`);
  await page.click('button[type="submit"]:has-text("Adicionar kit")');
  await page.waitForTimeout(1800);

  const totalGravado = sql(`select total::text from public.quotes where id='${idQuote}';`);
  check("orçamento montado com produto e kit",
    sql(`select count(*) from public.quote_items where quote_id='${idQuote}';`) === "2");

  // ── PDF autenticado ────────────────────────────────────
  await page.goto(`${BASE}/orcamentos/${idQuote}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  let body = await page.innerText("body");
  check("ficha oferece o download do PDF", contem(body, "Baixar PDF"));

  let resp = await buscaAutenticado(page, `/api/orcamentos/${idQuote}/pdf`);
  check("PDF responde 200", resp.status() === 200, String(resp.status()));
  check("PDF vem como application/pdf", resp.headers()["content-type"] === "application/pdf");
  check("PDF vem como anexo com nome do orçamento",
    (resp.headers()["content-disposition"] ?? "").includes(`${numero}`),
    resp.headers()["content-disposition"]);

  let pdf = Buffer.from(await resp.body());
  check("arquivo é um PDF de verdade", pdf.subarray(0, 5).toString() === "%PDF-");
  let texto = pdfText(pdf, "e2e-orcamento.pdf");

  // ── conteúdo do PDF ────────────────────────────────────
  check("PDF traz o número do orçamento", contem(texto, numero));
  check("PDF traz o cabeçalho da empresa",
    contem(texto, "AGROTORK") && contem(texto, "12.345.678/0001-90"));
  check("PDF traz contato da empresa configurado",
    contem(texto, "(43) 3333-4444") && contem(texto, "comercial@agrotork.com.br"));
  check("PDF traz o cliente", contem(texto, "Fazenda São João"));
  check("PDF traz o produto do snapshot",
    contem(texto, "P-001") && contem(texto, "Bico de pulverização"));
  check("PDF traz a marca do snapshot", contem(texto, "ARAG"));
  check("PDF traz o kit", contem(texto, "K-002") && contem(texto, "KIT NAVEGAÇÃO"));
  check("PDF mostra a composição incluída",
    contem(texto, "INCLUI") && contem(texto, "Mangueira de pulverização"));
  check("PDF separa os opcionais não incluídos",
    contem(texto, "OPCIONAIS NÃO INCLUÍDOS") && contem(texto, "Monitor de plantio"));
  check("PDF traz as condições comerciais",
    contem(texto, "30/60/90 dias") && contem(texto, "15 dias após confirmação"));
  check("PDF traz as observações", contem(texto, "sujeita a disponibilidade"));
  check("PDF traz o total oficial do banco", contem(texto, "R$ 482,00") && totalGravado === "482.00",
    totalGravado);
  check("PDF traz o vendedor", contem(texto, "Administrador de Teste"));
  check("PDF numera as páginas", /página\s+1\s+de\s+1/i.test(texto));

  // ── o que NÃO pode estar no PDF ────────────────────────
  check("PDF NÃO traz observação interna", !contem(texto, "MARGEM APERTADA"));
  check("PDF NÃO traz custo do produto", !contem(texto, "R$ 100,00"));
  check("PDF NÃO fala em margem nem custo", !contem(texto, "margem") && !contem(texto, "custo"));

  const paginas = execFileSync("pdfinfo", ["/tmp/e2e-orcamento.pdf"], { stdio: "pipe" })
    .toString().match(/Pages:\s+(\d+)/)?.[1];
  check("PDF não gera páginas em branco", paginas === "1", `${paginas} página(s)`);

  // ── link público ───────────────────────────────────────
  body = await page.innerText("body");
  check("ficha avisa que gerar link envia o rascunho", contem(body, "passa a"));

  await page.click('button:has-text("Gerar link público")');
  await page.waitForTimeout(1800);
  body = await page.innerText("body");
  check("link gerado com aviso", contem(body, "Link público gerado"));
  check("compartilhar marcou o orçamento como enviado",
    sql(`select status from public.quotes where id='${idQuote}';`) === "sent");

  linkPublico = await page.locator('[data-testid="share-url"]').first().innerText();
  tokenPublico = linkPublico.trim().split("/").pop() ?? "";
  check("link usa token longo e aleatório",
    /^[0-9a-f]{48}$/.test(tokenPublico), `${tokenPublico.length} caracteres`);
  check("link não expõe o id do orçamento", !linkPublico.includes(idQuote));
  check("ficha mostra a expiração do link", contem(body, "O link expira em"));
  check("ficha explica o que o link não mostra", contem(body, "sem custo"));
  await page.screenshot({ path: "docs/screenshots/orcamentos-compartilhamento.png", fullPage: true });

  // ── TESTE CRÍTICO: catálogo muda, documento não ────────
  // A referência é tirada agora, com o orçamento já em "enviado": o
  // status aparece impresso, e comparar dois documentos de status
  // diferente mediria a coisa errada.
  resp = await buscaAutenticado(page, `/api/orcamentos/${idQuote}/pdf`);
  const pdfAntes = pdfText(Buffer.from(await resp.body()), "e2e-antes.pdf");

  sql(`update public.products set sale_price = 9999, name = 'NOME TROCADO PELO TESTE' where code in ('P-001','P-002');`);
  sql(`delete from public.kit_items ki using public.products p, public.kits k
       where ki.product_id=p.id and ki.kit_id=k.id and k.code='K-002' and p.code='P-002';`);
  sql(`update public.kits set name='KIT RENOMEADO', is_active=false where code='K-002';`);
  sql(`update public.products set is_active=false where code='P-001';`);

  resp = await buscaAutenticado(page, `/api/orcamentos/${idQuote}/pdf`);
  pdf = Buffer.from(await resp.body());
  texto = pdfText(pdf, "e2e-orcamento-depois.pdf");

  check("PDF reemitido continua com o preço antigo", contem(texto, "R$ 482,00"));
  check("PDF reemitido continua com o nome antigo do produto",
    contem(texto, "Bico de pulverização") && !contem(texto, "NOME TROCADO"));
  check("PDF reemitido continua com o nome antigo do kit",
    contem(texto, "KIT NAVEGAÇÃO") && !contem(texto, "KIT RENOMEADO"));
  check("PDF reemitido mantém o componente removido do cadastro",
    contem(texto, "Mangueira de pulverização"));
  check("PDF reemitido é o mesmo documento comercial",
    texto.replace(/\s+/g, " ") === pdfAntes.replace(/\s+/g, " "));

  await ctx.close();
}

// ── PÚBLICO: sem login, só com o token ──────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();

  await page.goto(linkPublico, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(900);
  let body = await page.innerText("body");

  check("página pública abre sem login", !page.url().includes("/login"), page.url().replace(BASE, ""));
  check("página pública mostra o número", contem(body, numero));
  check("página pública mostra a empresa",
    contem(body, "AGROTORK") && contem(body, "12.345.678/0001-90"));
  check("página pública mostra o cliente", contem(body, "Fazenda São João"));
  check("página pública formata o CNPJ do cliente", contem(body, "12.345.678/0001-95"));
  check("página pública mostra os itens do snapshot",
    contem(body, "Bico de pulverização") && contem(body, "KIT NAVEGAÇÃO"));
  check("página pública mostra a composição incluída",
    contem(body, "Inclui") && contem(body, "Mangueira de pulverização"));
  check("página pública separa os opcionais não incluídos",
    contem(body, "Opcionais não incluídos") && contem(body, "Monitor de plantio"));
  check("página pública mostra o total oficial", contem(body, "R$ 482,00"));
  check("página pública mostra as condições", contem(body, "30/60/90 dias"));
  check("página pública mostra o vendedor", contem(body, "Administrador de Teste"));

  // ── o que NÃO pode aparecer ────────────────────────────
  check("página pública NÃO mostra observação interna", !contem(body, "MARGEM APERTADA"));
  check("página pública NÃO mostra custo", !contem(body, "R$ 100,00"));
  check("página pública NÃO fala em margem", !contem(body, "margem"));
  check("página pública NÃO mostra o id do orçamento", !contem(await page.content(), idQuote));
  check("página pública não é indexável",
    (await page.locator('meta[name="robots"]').getAttribute("content") ?? "").includes("noindex"));
  await page.screenshot({ path: "docs/screenshots/orcamento-publico-celular.png", fullPage: true });

  // ── PDF público ────────────────────────────────────────
  const resp = await page.request.get(`${BASE}/api/orcamento-publico/${tokenPublico}/pdf`);
  check("PDF público responde 200", resp.status() === 200, String(resp.status()));
  const texto = pdfText(Buffer.from(await resp.body()), "e2e-publico.pdf");
  check("PDF público traz o orçamento", contem(texto, numero) && contem(texto, "R$ 482,00"));
  check("PDF público NÃO traz observação interna", !contem(texto, "MARGEM APERTADA"));

  // ── segurança do token ─────────────────────────────────
  const invalidos = [
    ["/orcamento-publico/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "token inexistente"],
    ["/orcamento-publico/123", "token curto"],
    [`/orcamento-publico/${idQuote}`, "id do orçamento como token"],
  ];
  for (const [rota, nome] of invalidos) {
    const r = await page.request.get(`${BASE}${rota}`);
    check(`${nome} devolve 404`, r.status() === 404, String(r.status()));
  }

  // token de OUTRO orçamento não abre este
  const idOutro = sql(`insert into public.quotes (customer_id, owner_id)
    select c.id, 'aaaaaaaa-0000-4000-8000-000000000001' from public.customers c
    where c.name='João Marchioni' returning id;`);
  sql(`update public.quotes set status='sent' where id='${idOutro}';`);
  const tokenOutro = sql(`insert into public.quote_share_tokens (quote_id)
    values ('${idOutro}') returning token;`);
  const numeroOutro = sql(`select number from public.quotes where id='${idOutro}';`);

  await page.goto(`${BASE}/orcamento-publico/${tokenOutro}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  body = await page.innerText("body");
  check("token de outro orçamento abre SÓ o outro",
    contem(body, numeroOutro) && !contem(body, numero));

  // ── token expirado ─────────────────────────────────────
  sql(`update public.quote_share_tokens set expires_at = now() - interval '1 hour' where token='${tokenOutro}';`);
  const expirado = await page.request.get(`${BASE}/orcamento-publico/${tokenOutro}`);
  check("token expirado devolve 404", expirado.status() === 404, String(expirado.status()));

  await ctx.close();
}

// ── REVOGAÇÃO ───────────────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  await page.goto(`${BASE}/orcamentos/${idQuote}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  await page.click('button:has-text("Revogar link")');
  await page.waitForTimeout(400);
  await page.click('button:has-text("Sim, revogar")');
  await page.waitForTimeout(1800);
  let body = await page.innerText("body");
  check("revogação confirmada na tela", contem(body, "Link revogado"));
  check("orçamento continua intacto após revogar",
    sql(`select total::text from public.quotes where id='${idQuote}';`) === "482.00");
  check("histórico do link mostra o revogado", contem(body, "revogado"));

  const revogado = await page.request.get(`${BASE}/orcamento-publico/${tokenPublico}`);
  check("link revogado devolve 404", revogado.status() === 404, String(revogado.status()));

  const pdfRevogado = await page.request.get(`${BASE}/api/orcamento-publico/${tokenPublico}/pdf`);
  check("PDF do link revogado devolve 404", pdfRevogado.status() === 404);

  // gera um link novo
  await page.goto(`${BASE}/orcamentos/${idQuote}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  await page.click('button:has-text("Gerar link público")');
  await page.waitForTimeout(1800);
  const novoLink = (await page.locator('[data-testid="share-url"]').first().innerText()).trim();
  check("link novo é diferente do revogado", novoLink !== linkPublico);

  const novo = await page.request.get(novoLink);
  check("link novo funciona", novo.status() === 200, String(novo.status()));

  await ctx.close();
}

// ── VENDEDOR: isolamento ────────────────────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await login(ctx, "vendedor@teste.local");

  const resp = await buscaAutenticado(page, `/api/orcamentos/${idQuote}/pdf`);
  check("vendedor não baixa PDF de orçamento alheio", resp.status() === 404, String(resp.status()));

  await page.goto(`${BASE}/orcamentos/${idQuote}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  const body = await page.innerText("body");
  check("vendedor não vê o painel de link de orçamento alheio",
    !contem(body, "Gerar link público") || !contem(body, numero));

  await ctx.close();
}

// ── Sem rolagem horizontal na página pública ────────────────
{
  for (const width of [360, 768, 1440]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await ctx.newPage();
    const link = sql(`select token from public.quote_share_tokens ts
      join public.quotes q on q.id = ts.quote_id
      where q.id='${idQuote}' and ts.revoked_at is null limit 1;`);
    await page.goto(`${BASE}/orcamento-publico/${link}`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(700);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    check(`página pública sem rolagem horizontal em ${width}px`, over <= 0, `sobra ${over}px`);
    if (width === 1440) {
      await page.screenshot({ path: "docs/screenshots/orcamento-publico-desktop.png", fullPage: true });
    }
    await ctx.close();
  }
}

await browser.close();

console.log("\n=== VALIDAÇÃO DE PDF E COMPARTILHAMENTO ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
