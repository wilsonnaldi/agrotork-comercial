/**
 * Validação de ponta a ponta da TRILHA DE AUDITORIA — Fase 6.3.
 *
 * O que esta suíte prova, e que os testes de banco não conseguem provar:
 * que uma ação feita na TELA, passando pelo Server Action e pelo PostgREST
 * com uma sessão de verdade, chega ao log com o ator certo; e que a tabela
 * `audit_log`, apesar de exposta em /rest/v1/ como qualquer outra, não
 * entrega nada ao vendedor nem ao anônimo, e não aceita escrita de
 * ninguém.
 *
 * Pré-requisitos (mesma sequência dos outros e2e):
 *   bash supabase/db-tests/dev-seed.sh
 *   node supabase/db-tests/auth-double/server.mjs
 *   npm run build && npx next start -p 3402
 *
 * Depois:  BASE_URL=http://localhost:3402 node supabase/db-tests/auth-double/e2e-auditoria.mjs
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

function sql(query) {
  return execFileSync(
    "psql",
    ["-h", process.env.PGHOST ?? "/tmp/pgrun", "-p", process.env.PGPORT ?? "5433",
     "-U", process.env.PGUSER ?? "postgres", "-d", process.env.PGDATABASE ?? "agrotork_dev",
     "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1", "-c", query],
    { stdio: "pipe" },
  ).toString().trim();
}

const env = readFileSync(new URL("../../../.env.local", import.meta.url), "utf8");
const SUPA = env.match(/NEXT_PUBLIC_SUPABASE_URL="?([^"\n]+)"?/)[1];
const ANON = env.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY="?([^"\n]+)"?/)[1];

async function sessao(email) {
  const r = await fetch(`${SUPA}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: ANON },
    body: JSON.stringify({ email, password: "teste1234" }),
  });
  return (await r.json()).access_token;
}

function cabecalho(token) {
  return { "Content-Type": "application/json", apikey: ANON, Authorization: `Bearer ${token}` };
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

// ── 1. Uma ação na TELA vira um evento com o ator certo ─────
const NOME = "Cliente Auditado E2E";
{
  const ctx = await browser.newContext();
  const page = await login(ctx, "vendedor@teste.local");
  await page.goto(`${BASE}/clientes/novo`, { waitUntil: "domcontentloaded" });
  await page.fill("#name", NOME);
  await page.fill("#phone", "4332220000");
  await page.click('button[type="submit"]');
  await page.waitForTimeout(1500);
  await ctx.close();
}

{
  const linha = sql(
    `select action || '|' || actor_kind || '|' || coalesce(actor_email,'?') || '|'
         || coalesce(actor_role::text,'?') || '|' || actor_db_role || '|' || coalesce(entity_label,'?')
       from public.audit_log
      where entity_type = 'customer' and entity_label = '${NOME}';`,
  );
  check(
    "cadastro feito na tela virou um evento com o vendedor como ator",
    linha === `customer.created|user|vendedor@teste.local|salesperson|authenticated|${NOME}`,
    linha || "(nenhuma linha)",
  );

  const quantas = sql(
    `select count(*) from public.audit_log where entity_type='customer' and entity_label='${NOME}';`,
  );
  check("gerou exatamente uma linha, não duas", quantas === "1", `${quantas} linha(s)`);
}

// ── 2. Mudança de status pela API da aplicação ──────────────
// É o caminho que `changeStatusAction` → `repository.updateStatus` usa:
// PATCH em /rest/v1/quotes com a sessão do usuário.
const tokenAdmin = await sessao("admin@teste.local");
const tokenVend = await sessao("vendedor@teste.local");
check("sessões obtidas", Boolean(tokenAdmin && tokenVend));

const numeroOrc = sql(
  `select number from public.quotes where owner_id='aaaaaaaa-0000-4000-8000-000000000001' and status='sent' limit 1;`,
);
const idOrc = sql(`select id from public.quotes where number='${numeroOrc}';`);

{
  const r = await fetch(`${SUPA}/rest/v1/quotes?id=eq.${idOrc}`, {
    method: "PATCH",
    headers: { ...cabecalho(tokenAdmin), Prefer: "return=representation" },
    body: JSON.stringify({ status: "approved" }),
  });
  await r.text();

  const linha = sql(
    `select action || '|' || coalesce(actor_email,'?') || '|' || (old_data->>'status')
         || '->' || (new_data->>'status')
       from public.audit_log
      where entity_type='quote' and entity_id='${idOrc}' and action='quote.approved';`,
  );
  check(
    "aprovação pela API registrou quote.approved com de → para",
    linha === `quote.approved|admin@teste.local|sent->approved`,
    linha || "(nenhuma linha)",
  );
}

// ── 3. O log NÃO é legível pelo vendedor via PostgREST ──────
async function lerLog(token) {
  const r = await fetch(`${SUPA}/rest/v1/audit_log?select=id&limit=5`, { headers: cabecalho(token) });
  const corpo = await r.text();
  let linhas = -1;
  try { const j = JSON.parse(corpo); linhas = Array.isArray(j) ? j.length : -1; } catch { /* erro */ }
  return { status: r.status, linhas, corpo };
}

{
  const vend = await lerLog(tokenVend);
  check("vendedor lê ZERO linhas do log pela API", vend.linhas === 0,
    `HTTP ${vend.status}, ${vend.linhas} linha(s)`);

  const adm = await lerLog(tokenAdmin);
  check("administrador lê o log pela API", adm.linhas > 0,
    `HTTP ${adm.status}, ${adm.linhas} linha(s)`);

  const anon = await lerLog(ANON);
  check("anônimo não lê o log pela API", anon.linhas === 0 || anon.status >= 400,
    `HTTP ${anon.status}, ${anon.linhas} linha(s)`);
}

// ── 4. Ninguém escreve no log pela API ──────────────────────
{
  const forjado = {
    actor_kind: "user", actor_db_role: "authenticated",
    action: "quote.approved", operation: "INSERT",
    entity_type: "quote", entity_id: "forjado",
  };

  for (const [quem, token] of [["vendedor", tokenVend], ["administrador", tokenAdmin]]) {
    const r = await fetch(`${SUPA}/rest/v1/audit_log`, {
      method: "POST", headers: cabecalho(token), body: JSON.stringify(forjado),
    });
    await r.text();
    check(`${quem} NÃO insere linha no log pela API`, r.status >= 400, `HTTP ${r.status}`);
  }

  const idAlvo = sql("select min(id) from public.audit_log;");
  for (const [quem, token] of [["vendedor", tokenVend], ["administrador", tokenAdmin]]) {
    const r = await fetch(`${SUPA}/rest/v1/audit_log?id=eq.${idAlvo}`, {
      method: "PATCH", headers: cabecalho(token), body: JSON.stringify({ action: "quote.rejected" }),
    });
    await r.text();
    const intacto = sql(`select action from public.audit_log where id = ${idAlvo};`) !== "quote.rejected";
    check(`${quem} NÃO altera linha do log pela API`, intacto, `HTTP ${r.status}`);
  }

  const antes = sql("select count(*) from public.audit_log;");
  const r = await fetch(`${SUPA}/rest/v1/audit_log?id=eq.${idAlvo}`, {
    method: "DELETE", headers: cabecalho(tokenAdmin),
  });
  await r.text();
  const depois = sql("select count(*) from public.audit_log;");
  check("administrador NÃO apaga linha do log pela API", antes === depois,
    `HTTP ${r.status}, ${antes} → ${depois}`);
}

// ── 5. Segredo nenhum no log ────────────────────────────────
// Gera um link de verdade primeiro: sem token no banco, a asserção de
// redação passaria por vacuidade.
{
  const r = await fetch(`${SUPA}/rest/v1/quote_share_tokens`, {
    method: "POST",
    headers: { ...cabecalho(tokenAdmin), Prefer: "return=representation" },
    body: JSON.stringify({ quote_id: idOrc }),
  });
  await r.text();
  const criados = sql(
    `select count(*) from public.audit_log where action='quote.link_created' and parent_id='${idOrc}';`,
  );
  check("gerar link de compartilhamento virou quote.link_created", criados === "1",
    `HTTP ${r.status}, ${criados} evento(s)`);
}

{
  const vazou = sql(
    `select count(*) from public.audit_log a
      where exists (select 1 from public.quote_share_tokens t
                     where coalesce(a.old_data::text,'') || coalesce(a.new_data::text,'')
                           like '%' || t.token || '%');`,
  );
  check("nenhum token de compartilhamento aparece no log", vazou === "0", `${vazou} vazamento(s)`);

  const redigidos = sql(
    `select count(*) from public.audit_log
      where entity_type='quote_share_token' and new_data->>'token' <> '[REDIGIDO]';`,
  );
  check("todo evento de link grava o token como [REDIGIDO]", redigidos === "0",
    `${redigidos} sem redação`);

  const senhas = sql(
    `select count(*) from public.audit_log
      where coalesce(old_data::text,'') || coalesce(new_data::text,'')
            ~* '(password|encrypted_password|access_token|refresh_token|service_role|secret)';`,
  );
  check("nenhum campo de autenticação chegou ao log", senhas === "0", `${senhas} ocorrência(s)`);
}

// ── 6. Regressão: a aplicação continua funcionando ──────────
{
  const ctx = await browser.newContext();
  const page = await login(ctx, "vendedor@teste.local");
  await page.goto(`${BASE}/clientes`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(400);
  const texto = await page.locator("main").innerText();
  check("a lista de clientes continua abrindo com o cliente novo", texto.includes(NOME));
  await ctx.close();
}

await browser.close();

console.log("\n=== VALIDAÇÃO DA TRILHA DE AUDITORIA ===");
for (const r of results) console.log(r);
const failed = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - failed}/${results.length} verificações OK`);
process.exit(failed ? 1 : 0);
