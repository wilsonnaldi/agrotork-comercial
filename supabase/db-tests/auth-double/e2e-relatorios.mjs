/**
 * Validação de ponta a ponta dos RELATÓRIOS — Fase 6.
 *
 * Além de conferir a tela, este arquivo semeia orçamentos com situações
 * conhecidas e confere a ARITMÉTICA: total, aprovado, ticket médio e taxa
 * de conversão. Relatório que mostra número errado é pior que relatório
 * nenhum, porque ninguém desconfia.
 *
 * Pré-requisitos: dev-seed, duplê e a aplicação servindo (ver os outros e2e).
 */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";

const BASE = process.env.BASE_URL ?? "http://localhost:3402";
const results = [];
const check = (name, pass, detail = "") =>
  results.push(`${pass ? "OK  " : "FALHA"} ${name}${detail ? " — " + detail : ""}`);
const norm = (t) => t.replace(/ /g, " ");

function sql(query) {
  return execFileSync(
    "psql",
    ["-h", process.env.PGHOST ?? "/tmp/pgrun", "-p", process.env.PGPORT ?? "5433",
     "-U", process.env.PGUSER ?? "postgres", "-d", process.env.PGDATABASE ?? "agrotork_dev",
     "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1", "-c", query],
    { stdio: "pipe" },
  ).toString().trim();
}

// ── Massa determinística ────────────────────────────────────
// Seis orçamentos do ADMIN, emitidos hoje, de R$ 1.000,00 cada:
//   2 aprovados · 1 recusado · 1 expirado · 1 enviado · 1 rascunho
// Decididos = 4 (aprovado, recusado, expirado). Conversão = 2/4 = 50,0%.
// E um do VENDEDOR, aprovado, para provar o isolamento por RLS.
sql(`
  delete from public.quote_items where quote_id in (select id from public.quotes);
  delete from public.quotes;
  insert into public.customers (name) select 'Cliente Relatorio'
   where not exists (select 1 from public.customers where name='Cliente Relatorio');
`);
sql(`
  do $$
  declare c uuid; q uuid; s text;
          admin uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
          vend  uuid := 'bbbbbbbb-0000-4000-8000-000000000002';
  begin
    select id into c from public.customers where name='Cliente Relatorio';
    foreach s in array array['approved','approved','rejected','expired','sent','draft'] loop
      insert into public.quotes (customer_id, owner_id, status, issue_date)
      values (c, admin, s::public.quote_status, current_date) returning id into q;
      insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
      values (q, 'custom', 'Item', 1, 1000);
    end loop;
    insert into public.quotes (customer_id, owner_id, status, issue_date)
    values (c, vend, 'approved', current_date) returning id into q;
    insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
    values (q, 'custom', 'Item do vendedor', 1, 500);
  end $$;
`);

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

// ── 1. Administrador: vê tudo e as contas fecham ────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "admin@teste.local");

  const menu = await page.textContent("nav");
  check("Relatórios aparece no menu do admin", menu.includes("Relatórios"));

  await page.goto(`${BASE}/relatorios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  const texto = norm(await page.textContent("main"));

  check("conta os 7 orçamentos do período", texto.includes("7"), "");
  check("valor emitido soma R$ 6.500,00", texto.includes("6.500,00"));
  check("valor aprovado soma R$ 2.500,00", texto.includes("2.500,00"));
  check("taxa de conversão é 60%", texto.includes("60%"), "2 admin + 1 vendedor aprovados de 5 decididos");
  check("mostra o ticket médio", texto.includes("Ticket médio"));
  check("quebra por situação", texto.includes("Aprovado") && texto.includes("Recusado") && texto.includes("Expirado"));
  check("admin vê a quebra por vendedor", texto.includes("Por vendedor"));
  check("explica como a conversão é calculada", texto.includes("aprovados ÷ decididos"));

  // Período sem nada emitido.
  await page.goto(`${BASE}/relatorios?periodo=mes_anterior`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  const vazio = norm(await page.textContent("main"));
  check("período sem orçamento mostra estado vazio", vazio.includes("Nenhum orçamento no período"));

  await ctx.close();
}

// ── 2. Vendedor: só os próprios números ─────────────────────
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await login(ctx, "vendedor@teste.local");

  await page.goto(`${BASE}/relatorios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  const texto = norm(await page.textContent("main"));

  check("vendedor abre o relatório", page.url().includes("/relatorios"));
  check("vendedor soma só R$ 500,00", texto.includes("500,00") && !texto.includes("6.500,00"),
        "o RLS entrega só os orçamentos dele");
  check("vendedor NÃO vê a quebra por vendedor", !texto.includes("Por vendedor"));
  check("vendedor não vê o valor dos outros", !texto.includes("2.500,00"));

  await ctx.close();
}

// ── 3. Responsividade ───────────────────────────────────────
for (const largura of [360, 768, 1440]) {
  const ctx = await browser.newContext({ viewport: { width: largura, height: 900 } });
  const page = await login(ctx, "admin@teste.local");
  await page.goto(`${BASE}/relatorios`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(600);
  const sobra = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check(`relatórios sem rolagem horizontal em ${largura}px`, sobra <= 0, `sobra ${sobra}px`);
  await ctx.close();
}

await browser.close();

for (const linha of results) console.log(linha);
const falhas = results.filter((r) => r.startsWith("FALHA")).length;
console.log(`\n${results.length - falhas}/${results.length} verificações OK`);
process.exit(falhas === 0 ? 0 : 1);
