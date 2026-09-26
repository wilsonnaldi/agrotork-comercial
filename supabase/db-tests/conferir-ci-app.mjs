/**
 * Confere que o CI do BRAIN continua dizendo o que diz.
 *
 *   node supabase/db-tests/conferir-ci-app.mjs
 *
 * 1. Toda suíte check:brain* do package.json tem step em brain-app.yml e
 *    entra no agregador check:brain-all.
 * 2. brain-app.yml não tem `paths`, `continue-on-error` nem `if:` — o
 *    `app-gates` roda sempre e roda tudo (é check obrigatório).
 * 3. brain.yml mantém o desenho de check obrigatório: `scope` decide,
 *    `deploy-reversao` só roda com db=true, `brain-db-gate` sempre reporta.
 * 4. Nos dois: sem `pull_request_target`, `permissions: contents: read`,
 *    nenhum `secrets.`.
 *
 * Por que existe: o CI já ficou velho uma vez — suíte nova no package.json,
 * workflow sem saber dela, verde enganoso. E um `paths:` devolvido ao
 * gatilho recria o check fantasma ("Expected — Waiting for status") sem
 * ninguém notar até o PR travar. Aqui qualquer um dos dois deixa o próprio
 * CI vermelho. Texto puro, sem parser de YAML: as exigências são linhas
 * exatas, e isso regex resolve sem dependência.
 */
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const WORKFLOW = ".github/workflows/brain-app.yml";
const WORKFLOW_DB = ".github/workflows/brain.yml";

// Agregador só de conveniência local; o workflow roda as suítes em steps
// separados de propósito, então exigir o agregador lá seria contraditório.
const IGNORAR = new Set(["check:brain-all"]);

let falhas = 0;
let passou = 0;
const ok = (t) => { passou += 1; process.stdout.write(`  ✓ ${t}\n`); };
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };

for (const w of [WORKFLOW, WORKFLOW_DB]) {
  if (!existsSync(join(RAIZ, w))) nao(`${w} não existe`);
}
if (falhas > 0) {
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

// --- 1b. agregador local: toda suíte entra no check:brain-all -------------
// Comando a comando (split em &&): `npm run check:brain` não é satisfeito
// por `npm run check:brain-answer`.
const agregado = new Set(String(scripts["check:brain-all"] ?? "").split("&&").map((c) => c.trim()));
for (const nome of nomes) {
  if (agregado.has(`npm run ${nome}`)) ok(`${nome} está no check:brain-all`);
  else nao(`${nome} fora do check:brain-all (falta \`npm run ${nome}\`)`);
}

// --- helpers de texto ----------------------------------------------------
// Comentário não conta: a regra vale para o que o Actions executa.
const semComentario = (t) => t.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");
// Bloco que começa na linha `inicio` e vai até a próxima linha (não vazia,
// não comentário) com indentação <= a dele.
function bloco(t, inicio) {
  const linhas = t.split("\n");
  const i = linhas.findIndex((l) => inicio.test(l));
  if (i < 0) return null;
  const ind = linhas[i].match(/^ */)[0].length;
  let f = i + 1;
  while (f < linhas.length && (/^\s*$/.test(linhas[f]) || linhas[f].match(/^ */)[0].length > ind)) f += 1;
  return linhas.slice(i, f).join("\n");
}
const regra = (cond, sim, naoMsg) => (cond ? ok(sim) : nao(naoMsg));

// --- 2. brain-app.yml: roda sempre, roda tudo ----------------------------
const app = semComentario(yml);
regra(!/^\s*paths(-ignore)?:/m.test(app), "brain-app.yml sem `paths` (app-gates reporta em todo PR)",
  "brain-app.yml tem `paths:` — check obrigatório vira status fantasma");
regra(!/^\s*continue-on-error:/m.test(app), "brain-app.yml sem continue-on-error",
  "brain-app.yml tem continue-on-error — step vermelho passaria verde");
regra(!/^\s*(?:-\s+)?if:/m.test(app), "brain-app.yml sem `if:` (nenhum step pulável)",
  "brain-app.yml tem `if:` — gate obrigatório não pode ser pulável");

// --- 3. brain.yml: scope decide, gate sempre reporta ---------------------
const db = semComentario(readFileSync(join(RAIZ, WORKFLOW_DB), "utf8"));
regra(/^  scope:[ \t\r]*$/m.test(db), "brain.yml tem job scope", "brain.yml sem job `scope:`");
const pesado = bloco(db, /^  deploy-reversao:[ \t\r]*$/);
regra(pesado !== null && /^    needs: scope[ \t\r]*$/m.test(pesado) &&
  /^    if: needs\.scope\.outputs\.db == 'true'[ \t\r]*$/m.test(pesado),
  "deploy-reversao depende do scope (needs + if db == 'true')",
  "deploy-reversao sem `needs: scope` e `if: needs.scope.outputs.db == 'true'`");
const gate = bloco(db, /^  brain-db-gate:[ \t\r]*$/);
regra(gate !== null && /^    if: always\(\)[ \t\r]*$/m.test(gate) &&
  /^    needs: \[scope, deploy-reversao\][ \t\r]*$/m.test(gate),
  "brain-db-gate sempre reporta (if: always(), needs scope + deploy-reversao)",
  "brain-db-gate ausente, sem `if: always()` ou sem `needs: [scope, deploy-reversao]`");
const pr = bloco(db, /^  pull_request:/);
regra(pr !== null && !/^\s+(paths|paths-ignore|branches|branches-ignore):/m.test(pr),
  "brain.yml: pull_request sem filtro (gate reporta em todo PR)",
  "brain.yml: pull_request ausente ou com filtro — brain-db-gate vira status fantasma");

// --- 4. os dois: superfície mínima ---------------------------------------
for (const [nomeW, t] of [[WORKFLOW, app], [WORKFLOW_DB, db]]) {
  regra(!/pull_request_target/.test(t), `${nomeW} sem pull_request_target`,
    `${nomeW} usa pull_request_target — código do PR com token de escrita`);
  regra(/^permissions:[ \t\r]*\n  contents: read[ \t\r]*$/m.test(t), `${nomeW} com permissions: contents: read`,
    `${nomeW} sem \`permissions:\` seguido de \`contents: read\``);
  regra(!/secrets\./.test(t), `${nomeW} sem secrets.`, `${nomeW} referencia secrets.`);
}

process.stdout.write(falhas === 0
  ? `✔ CI do BRAIN: ${nomes.length} suíte(s) com step e no agregador, ${passou} conferência(s) ok\n`
  : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
