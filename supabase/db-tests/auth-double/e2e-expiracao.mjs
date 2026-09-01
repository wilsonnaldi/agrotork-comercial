/**
 * Validação de ponta a ponta da EXPIRAÇÃO AUTOMÁTICA — Fase 6.2.
 *
 * O que esta suíte prova, e que os testes de banco não conseguem provar:
 * que o resultado do job aparece na tela do vendedor sem ninguém clicar em
 * nada, e que o navegador NÃO tem caminho para disparar a expiração —
 * nem por RPC do PostgREST, nem alterando o status de orçamento alheio.
 *
 * O job é executado exatamente como o pg_cron o executa: `select
 * public.expire_quotes();` conectado como `postgres`. Nenhuma etapa desta
 * suíte usa a sessão do navegador para expirar coisa alguma — esse é o
 * ponto.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-expiracao.mjs
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") => {
  const linha = `${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`;
  if (!pass) console.log(linha);
  results.push(linha);
};
const norm = (texto) => texto.replace(/ /g, " ").toLowerCase();
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

/** O comando do job, literalmente o que vai no cron.schedule. */
const rodarJob = () => sql("select public.expire_quotes();");
const statusDoBanco = (numero) =>
  sql(`select status::text from public.quotes where number = '${numero}';`);

// ── Cenário ─────────────────────────────────────────────────
// dev-seed.sh deixa: 0001 admin/sent, 0002 admin/draft, 0003 vendedor/draft.
sql(`update public.quotes set status = 'sent', valid_until = current_date - 1 where number = 'ORC-2026-0003';`);
sql(`update public.quotes set status = 'sent', valid_until = current_date      where number = 'ORC-2026-0001';`);
sql(`update public.quotes set valid_until = current_date - 30                  where number = 'ORC-2026-0002';`);

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

/** Situação exibida na linha da listagem, pelo número do orçamento. */
async function situacaoNaLista(page, numero) {
  await page.goto(`${BASE}/orcamentos`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  const linha = page.locator("tr", { hasText: numero }).first();
  if (!(await linha.count())) return "(linha ausente)";
  return norm((await linha.innerText()).replace(/\s+/g, " "));
}

// ── 1. Antes do job: nada mudou sozinho ─────────────────────
{
  const ctx = await browser.newContext();
  const page = await login(ctx, "vendedor@teste.local");
  const linha = await situacaoNaLista(page, "ORC-2026-0003");
  check("antes do job o orcamento vencido ainda aparece como Enviado",
    contem(linha, "enviado") && !contem(linha, "expirado"));
  await ctx.close();
}

// ── 2. O job roda sozinho, como o cron ──────────────────────
const expirados = rodarJob();
check("job expirou exatamente 1 orcamento", expirados === "1", `expire_quotes() = ${expirados}`);
check("o vencido virou expired no banco", statusDoBanco("ORC-2026-0003") === "expired");
check("o que vence hoje continua sent", statusDoBanco("ORC-2026-0001") === "sent");
check("o rascunho vencido continua draft", statusDoBanco("ORC-2026-0002") === "draft");
check("rodar o job de novo nao muda mais nada", rodarJob() === "0");

// ── 3. Depois do job: a tela reflete, sem clique nenhum ─────
{
  const ctx = await browser.newContext();
  const page = await login(ctx, "vendedor@teste.local");

  const linha = await situacaoNaLista(page, "ORC-2026-0003");
  check("vendedor ve o proprio orcamento como Expirado sem ter feito nada",
    contem(linha, "expirado"), linha.slice(0, 80));

  await page.goto(`${BASE}/orcamentos?status=expired`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  const filtrada = norm(await page.locator("main").innerText());
  check("filtro Expirado encontra o orcamento", contem(filtrada, "orc-2026-0003"));

  await page.goto(`${BASE}/orcamentos?status=sent`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(500);
  const enviados = norm(await page.locator("main").innerText());
  check("filtro Enviado nao lista mais o expirado", !contem(enviados, "orc-2026-0003"));

  await ctx.close();
}

// ── 4. O admin continua enxergando tudo, com o status certo ─
{
  const ctx = await browser.newContext();
  const page = await login(ctx, "admin@teste.local");
  const linha = await situacaoNaLista(page, "ORC-2026-0001");
  check("orcamento do admin que vence hoje continua Enviado para o admin",
    contem(linha, "enviado") && !contem(linha, "expirado"), linha.slice(0, 80));
  await ctx.close();
}

// ── 5. O navegador não alcança a expiração ──────────────────
// Esta é a asserção central de segurança da fase: mesmo com uma sessão
// válida de vendedor, `/rest/v1/rpc/expire_quotes` tem de ser recusado.
const env = readFileSync(new URL("../../../.env.local", import.meta.url), "utf8");
const SUPA = env.match(/NEXT_PUBLIC_SUPABASE_URL="?([^"\n]+)"?/)[1];
const ANON = env.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY="?([^"\n]+)"?/)[1];

const sessao = await (await fetch(`${SUPA}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { "Content-Type": "application/json", apikey: ANON },
  body: JSON.stringify({ email: "vendedor@teste.local", password: "teste1234" }),
})).json();
check("sessao de vendedor obtida pela API", Boolean(sessao.access_token));

async function rpc(token, fn) {
  const r = await fetch(`${SUPA}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: ANON, Authorization: `Bearer ${token}` },
    body: "{}",
  });
  return { status: r.status, body: await r.text() };
}

{
  const r = await rpc(sessao.access_token, "expire_quotes");
  check("vendedor autenticado NAO dispara expire_quotes por RPC", r.status !== 200, `HTTP ${r.status}`);
  check("a recusa e de privilegio, nao de argumento", contem(r.body, "permission denied") || contem(r.body, "42501"),
    r.body.slice(0, 120));
}

{
  const r = await rpc(ANON, "expire_quotes");
  check("anonimo NAO dispara expire_quotes por RPC", r.status !== 200, `HTTP ${r.status}`);
}

// O vendedor não pode mexer no status de orçamento de OUTRO dono. É a
// garantia que a expiração automática não pode ser confundida com uma
// brecha: quem muda status alheio continua sendo ninguém.
{
  const r = await fetch(`${SUPA}/rest/v1/quotes?number=eq.ORC-2026-0001`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json", apikey: ANON,
      Authorization: `Bearer ${sessao.access_token}`, Prefer: "return=representation",
    },
    body: JSON.stringify({ status: "expired" }),
  });
  await r.text();
  check("vendedor nao expira o orcamento de outro vendedor",
    statusDoBanco("ORC-2026-0001") === "sent", `HTTP ${r.status}`);
}

await browser.close();

console.log("\n=== VALIDAÇÃO DA EXPIRAÇÃO AUTOMÁTICA ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
