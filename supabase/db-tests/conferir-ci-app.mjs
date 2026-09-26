/**
 * Confere que o CI do BRAIN continua dizendo o que diz.
 *
 *   node supabase/db-tests/conferir-ci-app.mjs
 *
 * 1. Toda suíte check:brain* do package.json tem step em brain-app.yml e
 *    entra no agregador check:brain-all.
 * 2. brain-app.yml não tem `paths`, `continue-on-error` nem `if:` — o
 *    `app-gates` roda sempre e roda tudo (é check obrigatório) —, e tem
 *    `npm run lint`, `typecheck` e `build` como linhas exatas.
 * 3. brain.yml mantém o desenho de check obrigatório: `scope` decide (as
 *    duas saídas, evento desconhecido → pesado, diff com `--no-renames`),
 *    `deploy-reversao` só roda com db=true, `brain-db-gate` sempre reporta e
 *    o veredito dele está fixado linha a linha; sem `continue-on-error` e
 *    só os dois `if:` do desenho.
 * 4. Nos dois: `pull_request:` e `merge_group:` sem filtro, sem
 *    `pull_request_target`, uma única `permissions:` (topo, exatamente
 *    `contents: read`), nenhuma menção a `secrets`, nenhum `${{` dentro de
 *    `run:`.
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

// --- modelo de linhas --------------------------------------------------
// Sem parser de YAML, de propósito: as exigências são linhas exatas. Mas
// duas coisas o texto cru confunde, e as duas já custaram achado (revisão
// adversarial de 26/09):
//  · comentário. `workflow_dispatch: # não é pull_request_target` não pode
//    reprovar (N8), e `uses: …@sha # v5.1.0` não é parte do valor. Fora de
//    bloco `run:`, comentário de linha inteira some e ` #…` no fim é cortado;
//  · bloco `run: |`. Ali dentro é SHELL, e o Actions interpola `${{ }}` antes
//    do shell rodar — inclusive numa linha de comentário do shell. Então o
//    conteúdo do bloco é guardado CRU, sem cortar nada.
// Bloco `run: |`/`>` = as linhas seguintes mais indentadas que a coluna do
// `run` (ou vazias).
function linhas(texto) {
  const brutas = texto.replace(/\r/g, "").split("\n");
  const out = [];
  let colunaRun = -1;
  for (const raw of brutas) {
    const ind = raw.match(/^ */)[0].length;
    if (colunaRun >= 0 && (/^\s*$/.test(raw) || ind > colunaRun)) {
      out.push({ raw, code: raw, ind, run: true });
      continue;
    }
    colunaRun = -1;
    const code = /^\s*#/.test(raw) ? "" : raw.replace(/\s+#.*$/, "").replace(/\s+$/, "");
    out.push({ raw, code, ind, run: false });
    const m = code.match(/^(\s*(?:-\s+)?)run:\s*([|>][-+0-9]*)?\s*$/);
    if (m && m[2]) colunaRun = m[1].length;
  }
  return out;
}
// O que o Actions lê como estrutura: sem comentário, sem o shell dos blocos.
const estrutura = (ls) => ls.filter((l) => !l.run && l.code.trim() !== "").map((l) => l.code).join("\n");
// O que vira shell: o valor de `run:` numa linha só e o conteúdo dos blocos.
const shell = (ls) => ls.flatMap((l) => {
  if (l.run) return [l.raw];
  const m = l.code.match(/^\s*(?:-\s+)?run:\s*(.*)$/);
  return m && !/^[|>]/.test(m[1]) ? [m[1]] : [];
}).join("\n");
// Bloco que começa na linha `inicio` e vai até a próxima linha (não vazia)
// com indentação <= a dele. Sobre a ESTRUTURA (já sem comentários).
function bloco(t, inicio) {
  const ls = t.split("\n");
  const i = ls.findIndex((l) => inicio.test(l));
  if (i < 0) return null;
  const ind = ls[i].match(/^ */)[0].length;
  let f = i + 1;
  while (f < ls.length && (/^\s*$/.test(ls[f]) || ls[f].match(/^ */)[0].length > ind)) f += 1;
  return ls.slice(i, f).join("\n");
}
const regra = (cond, sim, naoMsg) => (cond ? ok(sim) : nao(naoMsg));
const linhaExata = (t, texto) => t.split("\n").some((l) => l.trim() === texto);

const lsApp = linhas(yml);
const lsDb = linhas(readFileSync(join(RAIZ, WORKFLOW_DB), "utf8"));
const app = estrutura(lsApp);
const db = estrutura(lsDb);

// --- 2. brain-app.yml: roda sempre, roda tudo ----------------------------
regra(!/^\s*paths(-ignore)?:/m.test(app), "brain-app.yml sem `paths` (app-gates reporta em todo PR)",
  "brain-app.yml tem `paths:` — check obrigatório vira status fantasma");
regra(!/continue-on-error/.test(app), "brain-app.yml sem continue-on-error",
  "brain-app.yml tem continue-on-error — step vermelho passaria verde");
regra(!/^\s*(?:-\s+)?if:/m.test(app), "brain-app.yml sem `if:` (nenhum step pulável)",
  "brain-app.yml tem `if:` — gate obrigatório não pode ser pulável");
// Os três gates caros, como as suítes: linha inteira, sem `|| true`.
for (const cmd of ["npm run lint", "npm run typecheck", "npm run build"]) {
  const esc = cmd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  regra(new RegExp(`^\\s*(?:-\\s+)?run:\\s+${esc}$`, "m").test(app), `brain-app.yml tem o step \`run: ${cmd}\``,
    `brain-app.yml sem a linha exata \`run: ${cmd}\` (ausente, ou com algo depois, como \`|| true\`)`);
}

// --- 3. brain.yml: scope decide, gate sempre reporta ---------------------
regra(/^  scope:$/m.test(db), "brain.yml tem job scope", "brain.yml sem job `scope:`");
const pesado = bloco(db, /^  deploy-reversao:$/);
regra(pesado !== null && /^    needs: scope$/m.test(pesado) &&
  /^    if: needs\.scope\.outputs\.db == 'true'$/m.test(pesado),
  "deploy-reversao depende do scope (needs + if db == 'true')",
  "deploy-reversao sem `needs: scope` e `if: needs.scope.outputs.db == 'true'`");
const gate = bloco(db, /^  brain-db-gate:$/);
regra(gate !== null && /^    if: always\(\)$/m.test(gate) &&
  /^    needs: \[scope, deploy-reversao\]$/m.test(gate),
  "brain-db-gate sempre reporta (if: always(), needs scope + deploy-reversao)",
  "brain-db-gate ausente, sem `if: always()` ou sem `needs: [scope, deploy-reversao]`");
regra(!/continue-on-error/.test(db), "brain.yml sem continue-on-error",
  "brain.yml tem continue-on-error — ensaio vermelho passaria verde");
// Só dois `if:` no arquivo inteiro, e exatamente estes. Um `if:` a mais num
// step do ensaio (ou do gate) pularia o que o gate acha que rodou.
const IFS_PERMITIDOS = new Set(["if: needs.scope.outputs.db == 'true'", "if: always()"]);
const ifs = db.split("\n").filter((l) => /^\s*(?:-\s+)?if:/.test(l)).map((l) => l.trim().replace(/^-\s+/, ""));
regra(ifs.length === 2 && ifs.every((l) => IFS_PERMITIDOS.has(l)) && new Set(ifs).size === 2,
  "brain.yml: só os dois `if:` do desenho (ensaio com db == 'true', gate com always())",
  `brain.yml: \`if:\` fora do desenho: ${ifs.join(" | ") || "nenhum"}`);
// O veredito do gate, fixado linha a linha: trocar `skipped` por `success`,
// pôr `|| true` ou apontar HEAVY para uma constante aprovaria sem ensaio.
const shDb = shell(lsDb);
const VEREDITO = [
  '[ "$SCOPE" = success ] || { echo "::error::scope nao concluiu ($SCOPE)"; exit 1; }',
  'case "$DB" in',
  'true)  [ "$HEAVY" = success ] || { echo "::error::deploy-reversao: $HEAVY"; exit 1; } ;;',
  'false) [ "$HEAVY" = skipped ] || { echo "::error::esperava skipped, veio $HEAVY"; exit 1; } ;;',
  '*)     echo "::error::saida db invalida"; exit 1 ;;',
];
const faltaVeredito = VEREDITO.filter((v) => !linhaExata(gate ?? "", v) && !linhaExata(shDb, v));
const envGate = ["SCOPE: ${{ needs.scope.result }}", "DB: ${{ needs.scope.outputs.db }}", "HEAVY: ${{ needs.deploy-reversao.result }}"];
regra(gate !== null && faltaVeredito.length === 0 && envGate.every((e) => linhaExata(gate, e)),
  "brain-db-gate: veredito e env (SCOPE/DB/HEAVY) com o texto fixado",
  `brain-db-gate: veredito ou env alterado (${[...faltaVeredito, ...envGate.filter((e) => !linhaExata(gate ?? "", e))].join(" | ")})`);
// O scope: as duas saídas existem, o `*)` do evento cai no pesado, e o
// diff lista o nome ANTIGO de arquivo movido (--no-renames).
const SCOPE_FIXO = [
  'heavy() { echo "db=true" >> "$GITHUB_OUTPUT"; echo "scope: $1 -> roda tudo"; exit 0; }',
  '*)            heavy "evento $EVENT" ;;',
  'git diff --no-renames --name-only -z "$mb" HEAD > "$RUNNER_TEMP/changed"',
  'echo "db=true" >> "$GITHUB_OUTPUT"; echo "scope: mudanca relevante -> roda"',
  'echo "db=false" >> "$GITHUB_OUTPUT"; echo "scope: nada relevante -> pula"',
];
const faltaScope = SCOPE_FIXO.filter((v) => !linhaExata(shDb, v));
regra(faltaScope.length === 0 && linhaExata(db, "db: ${{ steps.diff.outputs.db }}"),
  "scope: db=true e db=false, evento desconhecido → pesado, diff com --no-renames, output ligado ao step",
  `scope alterado: ${faltaScope.join(" | ") || "output `db: ${{ steps.diff.outputs.db }}` ausente"}`);

// --- 4. os dois: gatilho, permissões, superfície mínima ------------------
for (const [nomeW, t, ls] of [[WORKFLOW, app, lsApp], [WORKFLOW_DB, db, lsDb]]) {
  regra(!/pull_request_target/.test(t), `${nomeW} sem pull_request_target`,
    `${nomeW} usa pull_request_target — código do PR com token de escrita`);
  // `pull_request:` sozinho na linha, sem filho: qualquer filtro (paths,
  // branches, types) ou forma de fluxo (`{paths: …}`) faz o check
  // obrigatório deixar de reportar em algum PR.
  const tl = t.split("\n");
  const iPr = tl.findIndex((l) => l === "  pull_request:");
  const semFilho = (i) => i >= 0 && (i + 1 >= tl.length || tl[i + 1].match(/^ */)[0].length <= tl[i].match(/^ */)[0].length);
  regra(semFilho(iPr) && tl.filter((l) => /^\s*pull_request\b/.test(l)).length === 1,
    `${nomeW}: \`pull_request:\` presente e sem filtro (reporta em todo PR)`,
    `${nomeW}: \`pull_request:\` ausente, com filho (paths/branches/types) ou em forma de fluxo — check obrigatório vira status fantasma`);
  const iMq = tl.findIndex((l) => l === "  merge_group:");
  regra(semFilho(iMq), `${nomeW}: \`merge_group:\` presente e sem filtro`,
    `${nomeW}: sem \`merge_group:\` (com merge queue, o check nunca reportaria na fila)`);
  // Uma única `permissions:`, no topo, com exatamente `contents: read`.
  // Nenhuma no nível do job: ali ela SUBSTITUI a do topo.
  const perms = tl.filter((l) => /^\s*permissions\s*:/.test(l));
  const blocoPerm = bloco(t, /^permissions:$/);
  regra(perms.length === 1 && blocoPerm !== null && blocoPerm === "permissions:\n  contents: read",
    `${nomeW}: só \`permissions: contents: read\` no topo, nenhuma no job`,
    `${nomeW}: \`permissions:\` diferente de exatamente \`contents: read\` no topo, ou redefinida num job`);
  // Qualquer menção a `secrets` (secrets.X, secrets['X'], toJSON(secrets)),
  // na estrutura ou no shell.
  regra(!/\bsecrets\b/.test(`${t}\n${shell(ls)}`), `${nomeW} sem secrets`,
    `${nomeW} referencia \`secrets\` — o CI roda sem credencial, de propósito`);
  // `${{ }}` dentro do shell vira código antes de rodar: contexto só por env.
  regra(!shell(ls).includes("${{"), `${nomeW}: nenhum \`\${{\` dentro de \`run:\` (contexto só por env)`,
    `${nomeW}: \`\${{\` dentro de um \`run:\` — o valor do evento seria executado pelo shell`);
}

process.stdout.write(falhas === 0
  ? `✔ CI do BRAIN: ${nomes.length} suíte(s) com step e no agregador, ${passou} conferência(s) ok\n`
  : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
