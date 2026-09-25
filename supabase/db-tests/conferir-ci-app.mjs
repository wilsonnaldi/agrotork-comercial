/**
 * Confere que toda suíte check:brain* do package.json tem step no CI da app.
 *
 *   node supabase/db-tests/conferir-ci-app.mjs
 *
 * Por que existe: o CI já ficou velho uma vez — suíte nova no package.json,
 * workflow sem saber dela, verde enganoso. Agora um check:brain-foo novo
 * que não aterrisse em brain-app.yml deixa o próprio CI vermelho.
 * Texto puro, sem parser de YAML: a exigência é uma linha `run: npm run
 * <nome>` exata, e isso regex resolve sem dependência.
 */
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const WORKFLOW = ".github/workflows/brain-app.yml";

// Agregador só de conveniência local; o workflow roda as suítes em steps
// separados de propósito, então exigir o agregador lá seria contraditório.
const IGNORAR = new Set(["check:brain-all"]);

let falhas = 0;
const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };

if (!existsSync(join(RAIZ, WORKFLOW))) {
  nao(`${WORKFLOW} não existe`);
  process.stdout.write(`✗ ${falhas} falha(s)\n`);
  process.exit(1);
}
const scripts = JSON.parse(readFileSync(join(RAIZ, "package.json"), "utf8")).scripts ?? {};
const yml = readFileSync(join(RAIZ, WORKFLOW), "utf8");
const nomes = Object.keys(scripts).filter((n) => n.startsWith("check:brain") && !IGNORAR.has(n));

for (const nome of nomes) {
  const esc = nome.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // Linha inteira: `check:brain` não é satisfeito por `check:brain-answer`,
  // e um `|| true` no fim também não passa.
  const linha = new RegExp(`^\\s*(?:-\\s+)?run:\\s+npm run ${esc}[ \\t\\r]*$`, "m");
  if (linha.test(yml)) ok(`${nome} tem step`);
  else nao(`${nome} sem step \`run: npm run ${nome}\` em ${WORKFLOW}`);
}

process.stdout.write(falhas === 0 ? `✔ CI da app cobre ${nomes.length} suíte(s)\n` : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
