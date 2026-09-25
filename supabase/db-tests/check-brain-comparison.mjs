/**
 * Confere a COMPARAÇÃO entre códigos (Comparison v1).
 *
 *   node --experimental-strip-types supabase/db-tests/check-brain-comparison.mjs
 *
 * Três coisas se provam aqui, e as três são de segurança:
 *
 *  1. o valor de um produto nunca vira valor do outro (cross-product leak);
 *  2. a diferença é CALCULADA por código, a partir de valores validados, e
 *     é o único número que a resposta pode escrever sem estar no documento;
 *  3. faltando evidência para um dos produtos não há diferença, não há
 *     vencedor e a falta é dita com todas as letras.
 *
 * O fixture são as linhas reais da p. 20 do Catálogo Magnojet V41 e do
 * orçamento interno ARAG, copiadas de produção.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "evidence.ts": "src/modules/brain/evidence.ts",
  "limits.ts": "src/modules/brain/limits.ts",
  "grounding.ts": "src/modules/brain/grounding.ts",
  "exhaustiveness.ts": "src/modules/brain/exhaustiveness.ts",
  "comparison.ts": "src/modules/brain/comparison.ts",
  "answer.ts": "src/modules/brain/answer.ts",
  "prompt.ts": "src/modules/brain/prompt.ts",
  "external-processing.ts": "src/modules/brain/external-processing.ts",
  "provider.ts": "src/modules/brain/llm/provider.ts",
  "fake.ts": "src/modules/brain/llm/fake.ts",
};

const destino = mkdtempSync(join(RAIZ, ".comparison-check-"));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    .replace(/^import type \{ Json \} from "@\/types\/db";$/m, "type Json = unknown;")
    .replace(/from "\.\.\/evidence"/g, 'from "./evidence.ts"')
    .replace(/from "\.\/evidence"/g, 'from "./evidence.ts"')
    .replace(/from "\.\/limits"/g, 'from "./limits.ts"')
    .replace(/from "\.\/provider"/g, 'from "./provider.ts"')
    .replace(/from "\.\/grounding"/g, 'from "./grounding.ts"')
    .replace(/from "\.\/exhaustiveness"/g, 'from "./exhaustiveness.ts"')
    .replace(/from "\.\/comparison"/g, 'from "./comparison.ts"');
  writeFileSync(join(destino, nome), fonte);
}
const imp = (n) => import(pathToFileURL(join(destino, n)).href);
const A = await imp("answer.ts");
const C = await imp("comparison.ts");
const P = await imp("prompt.ts");
const X = await imp("external-processing.ts");

let falhas = 0;
const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };
const confere = (t, c, d = "") => (c ? ok(`${t}${d ? ` — ${d}` : ""}`) : nao(`${t}${d ? ` — ${d}` : ""}`));

// ── fixture real ────────────────────────────────────────────
const LINHA = (codigo, cv, bar, psi, kpa, lmin, lha) =>
  `${codigo} MUG-CV ${cv} MALHA 50 UG ${bar} bar ${psi} psi ${kpa} kPa ${lmin} L/min ${lha}`;
const P20 = [
  "LITROS POR HECTARE (ESPAÇAMENTO 50CM)",
  "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min 4 km/h 5 km/h 6 km/h 7 km/h 8 km/h 9 km/h 10 km/h 12 km/h 14 km/h 16 km/h 18 km/h 20 km/h 25 km/h",
  LINHA("MJ981CAP", "02", "2,07", "30", "207", "0,66", "199 L/ha 159 L/ha 133 L/ha"),
  LINHA("MJ981CAP", "02", "2,76", "40", "276", "0,77", "230 L/ha 184 L/ha 153 L/ha"),
  LINHA("MJ981CAP", "02", "3,45", "50", "345", "0,86", "257 L/ha 206 L/ha 172 L/ha"),
  LINHA("MJ982CAP", "025", "2,76", "40", "276", "0,96", "288 L/ha 230 L/ha 192 L/ha"),
  LINHA("MJ985CAP", "04", "2,07", "30", "207", "1,33", "399 L/ha 319 L/ha 266 L/ha"),
  LINHA("MJ985CAP", "04", "2,76", "40", "276", "1,53", "460 L/ha 368 L/ha 307 L/ha"),
  LINHA("MJ985CAP", "04", "3,45", "50", "345", "1,72", "515 L/ha 412 L/ha 343 L/ha"),
].join("\n");

const ev = (over = {}) => ({
  chunkId: 72, kind: "table", content: P20, tableData: null, page: { from: 20, to: 20 },
  headingPath: ["MAGNO ULTRA GROSSA"], codes: ["MJ981CAP", "MJ982CAP", "MJ985CAP"], source: "Magnojet",
  document: { title: "Catálogo Magnojet", type: "catalog" },
  version: { label: "V41", status: "active" }, accessLevel: "public",
  citation: "Magnojet — Catálogo Magnojet V41 · p. 20",
  ...over,
});
const MAG = ev();
const ARAG = ev({
  chunkId: 90, kind: "price_table", accessLevel: "commercial",
  content: "SISTEMA PARA BICOS HIDRAULICOS\n1 SENSOR PRESSAO 466113200 12V 0,5AH 4-20MAH 0-20 BAR 1098 1098",
  codes: ["466113200"], source: "AGROTORK — documentos internos",
  document: { title: "Orçamento interno — sistemas ARAG para bicos", type: "quote" },
  version: { label: "2024-10", status: "active" }, page: { from: 1, to: 1 },
  citation: "AGROTORK — documentos internos — Orçamento interno — sistemas ARAG para bicos 2024-10 · p. 1",
});

const EV = [MAG];
const CIT = A.buildCitations(EV);
const vq = (q, t, evs = EV) => A.validateAnswer(t, A.buildCitations(evs), evs, q);

const Q_40PSI = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi";
const CERTA = [
  "Comparação a 40 psi [1]:",
  "- MJ981CAP: 0,77 L/min [1]",
  "- MJ985CAP: 1,53 L/min [1]",
  "- Diferença: 0,76 L/min [1]",
].join("\n");

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Intenção de comparação\n");

const PEDE = [
  "Compare MJ981CAP e MJ985CAP",
  "Qual a diferença entre MJ981CAP e MJ985CAP?",
  "Compare a vazão da MJ981CAP com a MJ985CAP a 40 psi",
  "Qual tem maior vazão a 40 psi: MJ981CAP ou MJ985CAP?",
  "Compare MJ981CAP, MJ985CAP e MJ982CAP",
  "Mostre lado a lado MJ981CAP e MJ985CAP",
  "Qual a diferença de vazão entre MJ981CAP e MJ985CAP em 2,76 bar?",
  "MJ981CAP versus MJ985CAP",
  "Quanto a MJ985CAP entrega a mais que a MJ981CAP a 40 psi?",
];
confere("I1  as nove formas de pedir comparação são reconhecidas",
  PEDE.every((q) => C.detectComparisonIntent(q)),
  PEDE.filter((q) => !C.detectComparisonIntent(q)).join(" | ") || "9/9");

const NAO_PEDE = [
  "Qual a vazão da MJ981CAP a 40 psi?",
  "A MJ981CAP substitui a MJ985CAP?",
  "Quais as vazões da MJ981CAP em bar possíveis?",
  "Tenho MJ981CAP e MJ985CAP em estoque?",
];
confere("I2  dois códigos NÃO bastam: sem gatilho explícito, não é comparação",
  NAO_PEDE.every((q) => !C.detectComparisonIntent(q)),
  NAO_PEDE.filter((q) => C.detectComparisonIntent(q)).join(" | ") || "4/4");

confere("I3  um código só não abre comparação",
  C.planComparison("Compare a MJ981CAP", EV).status === "not_applicable");

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Plano: evidência por produto (C1, C5, C6, C13)\n");

const plano = C.planComparison(Q_40PSI, EV);
confere("C1  plano pronto, um bloco por código, na ordem da pergunta",
  plano.status === "ready" && plano.blocks.map((b) => b.code).join(",") === "MJ981CAP,MJ985CAP");
confere("C1b cada bloco tem SÓ o valor da linha do seu código",
  plano.blocks[0].values.map((v) => v.numero).join() === "0,77" &&
  plano.blocks[1].values.map((v) => v.numero).join() === "1,53",
  `${plano.blocks[0].values.map((v) => v.numero)} vs ${plano.blocks[1].values.map((v) => v.numero)}`);
confere("C1c a diferença é calculada em código: 1,53 − 0,77 = 0,76 L/min",
  plano.derived.length === 1 && plano.derived[0].texto === "0,76 L/min", JSON.stringify(plano.derived));
confere("C1d e a resposta certa passa no validador", vq(Q_40PSI, CERTA).ok === true, vq(Q_40PSI, CERTA).problem ?? "ok");

const tres = C.planComparison("Compare MJ981CAP, MJ982CAP e MJ985CAP a 40 psi", EV);
confere("C5  três códigos válidos: três blocos e as três diferenças de vazão (o ponto fixado não gera diferença)",
  tres.status === "ready" && tres.blocks.length === 3 &&
  tres.derived.length === 3 && tres.derived.every((d) => d.unidade === "L/min"),
  tres.status === "ready" ? tres.derived.map((d) => `${d.de}/${d.para}=${d.texto}`).join(" · ") : tres.status);

confere("C6  código repetido é deduplicado",
  C.parseComparison("Compare MJ981CAP com MJ981CAP e MJ985CAP").codes.join(",") === "MJ981CAP,MJ985CAP");

const seis = C.planComparison(
  "Compare MJ980CAP, MJ981CAP, MJ982CAP, MJ983CAP, MJ984CAP e MJ985CAP a 40 psi", EV);
confere(`C13 acima de ${C.MAX_CODIGOS_COMPARADOS} códigos o plano recusa, com o número e o limite`,
  seis.status === "too_many" && seis.codes.length === 6 && seis.limite === 5);
const Q_SEIS = "Compare MJ980CAP, MJ981CAP, MJ982CAP, MJ983CAP, MJ984CAP e MJ985CAP a 40 psi";
confere("C13b e não falha em silêncio: a resposta que tentar é reprovada",
  vq(Q_SEIS, CERTA).ok === false, vq(Q_SEIS, CERTA).problem);
confere("C13c a checagem nomeia o limite",
  C.checkComparison(Q_SEIS, CERTA, EV, CIT).failures[0].includes("acima do limite de 5"));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Vazamento entre produtos (C2, C14)\n");

const TROCADA = [
  "Comparação a 40 psi [1]:",
  "- MJ981CAP: 1,53 L/min [1]",
  "- MJ985CAP: 0,77 L/min [1]",
].join("\n");
const t2 = vq(Q_40PSI, TROCADA);
confere("C2  valores trocados entre os dois códigos → REPROVADO", t2.ok === false, t2.problem);
confere("C2b e o motivo nomeia o produto e o valor",
  (t2.details ?? []).some((d) => d.includes("MJ981CAP") && d.includes("1,53")),
  (t2.details ?? [])[0] ?? "");

const SO_UM_TROCADO = [
  "Comparação a 40 psi [1]:",
  "- MJ981CAP: 0,77 L/min [1]",
  "- MJ985CAP: 0,96 L/min [1]",
].join("\n");
confere("C14 valor que existe na tabela, mas é da MJ982CAP, atribuído à MJ985CAP → REPROVADO",
  vq(Q_40PSI, SO_UM_TROCADO).ok === false, vq(Q_40PSI, SO_UM_TROCADO).problem);
confere("C14b os dois números existem no documento — o grounding sozinho deixaria passar",
  P.renderEvidence(EV).includes("0,96 L/min") && P.renderEvidence(EV).includes("0,77 L/min"));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Valor inexistente e produto inexistente (C3, C4, C15)\n");

confere("C3  valor que não está em lugar nenhum → grounding",
  vq(Q_40PSI, "- MJ981CAP: 0,79 L/min [1]\n- MJ985CAP: 1,53 L/min [1]").kind === "grounding");

const Q_999 = "Compare a vazão da MJ981CAP e MJ999CAP a 40 psi";
const plano999 = C.planComparison(Q_999, EV);
confere("C4  produto sem evidência: bloco marcado como ausente e comparação incompleta",
  plano999.status === "ready" && plano999.incomplete === true &&
  plano999.blocks.find((b) => b.code === "MJ999CAP").missing === true);
confere("C4b sem os dois lados, NENHUMA diferença é calculada", plano999.derived.length === 0);
const INCOMPLETA_OK = [
  "MJ981CAP: 0,77 L/min a 40 psi [1].",
  "",
  "Não encontrei documentação suficiente para a MJ999CAP nesse mesmo critério, então não dá para concluir a comparação. [1]",
].join("\n");
confere("C4c a resposta que declara a falta passa", vq(Q_999, INCOMPLETA_OK).ok === true, vq(Q_999, INCOMPLETA_OK).problem ?? "ok");
confere("C15 anunciar diferença numa comparação incompleta → REPROVADO",
  vq(Q_999, "- MJ981CAP: 0,77 L/min [1]\n- MJ999CAP: sem dados [1]\n- Diferença: 0,77 L/min [1]").kind === "comparison");
confere("C15b inventar valor para o produto ausente → REPROVADO",
  vq(Q_999, "- MJ981CAP: 0,77 L/min [1]\n- MJ999CAP: 1,53 L/min [1]").ok === false);
confere("C15c omitir um dos produtos comparados → REPROVADO",
  vq(Q_40PSI, "A MJ981CAP entrega 0,77 L/min a 40 psi. [1]").kind === "comparison");

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Cálculo determinístico (C8, C9, C10, C11)\n");

confere("C8  mesma unidade: a subtração acontece",
  C.difference({ numero: "1,53", unidade: "L/min" }, { numero: "0,77", unidade: "L/min" }).texto === "0,76");
confere("C8b e a vírgula decimal é preservada, sem lixo de ponto flutuante",
  C.difference({ numero: "0,1", unidade: "L/min" }, { numero: "0,3", unidade: "L/min" }).texto === "0,2");
confere("C9  unidades diferentes: NÃO calcula (e não converte)",
  C.difference({ numero: "40", unidade: "psi" }, { numero: "1,53", unidade: "L/min" }) === null);
const Q_PCT = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi: quanto por cento a mais?";
const planoPct = C.planComparison(Q_PCT, EV);
confere("C10 percentual pedido → calculado em código (0,77 → 1,53 = 98,7%)",
  planoPct.derived.some((d) => d.tipo === "percentual" && d.texto === "98,7%"),
  planoPct.derived.map((d) => d.texto).join(" · "));
confere("C11 percentual NÃO pedido → nenhum percentual no plano",
  plano.derived.every((d) => d.tipo !== "percentual"));
confere("C11b e escrever percentual sem pedido → grounding reprova",
  vq(Q_40PSI, `${CERTA}\n- A MJ985CAP entrega 98,7% a mais [1]`).ok === false);
confere("C11c diferença errada (0,86) → grounding reprova, mesmo com o número existindo na tabela",
  vq(Q_40PSI, CERTA.replace("Diferença: 0,76 L/min", "Diferença: 0,86 L/min")).ok === false);
// C11d mudou de forma nesta rodada: `derivedLiterals` não devolve mais
// strings soltas, e sim o literal COM as evidências que o sustentam. A
// asserção antiga (`.join(" · ")`) provava a lista; esta prova a condição,
// que é o que passou a importar.
confere("C11d o que escapa do documento é só o cálculo do sistema e os códigos da pergunta",
  C.derivedLiterals(plano).map((d) => d.texto).join(" · ") === "0,76 L/min · MJ981CAP · MJ985CAP" &&
  C.derivedLiterals({ status: "not_applicable", reason: "x" }).length === 0,
  C.derivedLiterals(plano).map((d) => d.texto).join(" · "));
confere("C11d2 e o derivado carrega a evidência de origem; o código da pergunta não exige nenhuma",
  C.derivedLiterals(plano).find((d) => d.texto === "0,76 L/min").requires.join() === "0" &&
  C.derivedLiterals(plano).find((d) => d.texto === "MJ999CAP") === undefined &&
  C.derivedLiterals(plano).find((d) => d.texto === "MJ981CAP").requires.length === 0,
  JSON.stringify(C.derivedLiterals(plano)));
confere("C11e o código liberado NÃO libera valor: número ao lado do produto sem linha continua reprovado",
  vq(Q_999, "- MJ981CAP: 0,77 L/min [1]\n- MJ999CAP: 0,86 L/min [1]").kind === "comparison");

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Intenção indevida e prompt (C12)\n");

confere("C12 dois códigos sem gatilho: a checagem de comparação não se aplica",
  C.checkComparison("Tenho MJ981CAP e MJ985CAP em estoque?", "A MJ981CAP entrega 0,77 L/min. [1]", EV, CIT).status === "not_applicable");
confere("C12b e a resposta pontual de sempre continua passando",
  A.validateAnswer("A vazão da MJ981CAP a 40 psi é 0,77 L/min. [1]", CIT, EV, "Qual a vazão da MJ981CAP a 40 psi?").ok === true);
confere("C12c o prompt manda um bloco por código e proíbe recomendar o melhor",
  /responda em BLOCOS/.test(P.SYSTEM_PROMPT) && /Não recomende qual é melhor/.test(P.SYSTEM_PROMPT));
confere("C12d o prompt manda usar os CÁLCULOS VERIFICADOS e não calcular sozinho",
  /CÁLCULOS VERIFICADOS/.test(P.SYSTEM_PROMPT) && /Não calcule por conta própria/.test(P.SYSTEM_PROMPT));
const MSG = P.buildUserMessage(Q_40PSI, EV, ["Diferença entre MJ981CAP e MJ985CAP: 0,76 L/min"]);
confere("C12e o bloco de cálculos chega ao provedor, separado das evidências",
  MSG.includes("=== CÁLCULOS VERIFICADOS") && MSG.includes("0,76 L/min") &&
  MSG.indexOf("=== FIM DAS EVIDÊNCIAS ===") < MSG.indexOf("=== CÁLCULOS VERIFICADOS"));
confere("C12f sem cálculo, a mensagem é a de sempre — nenhuma seção nova",
  !P.buildUserMessage("Qual a vazão da MJ981CAP a 40 psi?", EV).includes("CÁLCULOS"));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Processamento externo na comparação (C7)\n");

const refs = [
  { chunkId: 72, documentId: "doc-mag", documentTitle: "Catálogo Magnojet" },
  { chunkId: 90, documentId: "doc-arag", documentTitle: "Orçamento interno ARAG" },
];
const misto = X.assessExternalProcessing(refs, new Map([["doc-mag", "allowed"], ["doc-arag", "forbidden"]]));
confere("C7  comparação que mistura Magnojet (allowed) e ARAG (forbidden) NÃO sai daqui",
  misto.allowed === false && misto.sendableChunkIds.length === 0);
confere("C7b nem a parte permitida vai sozinha — resposta parcial enganaria",
  misto.blocked.length === 1 && misto.reason.includes("Orçamento interno ARAG"));
const planoMisto = C.planComparison("Compare MJ981CAP e 466113200", [MAG, ARAG]);
confere("C7c e o plano da comparação entre documentos diferentes não mistura linha",
  planoMisto.status === "ready" &&
  planoMisto.blocks.every((b) => b.values.every((v) => v.linha.includes(b.code))));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Identidade da linha\n");

confere("L1  linha que cita DOIS códigos comparados não identifica ninguém",
  C.linesForCode("MJ981CAP", ["MJ981CAP", "MJ985CAP"],
    [ev({ content: "MJ981CAP e MJ985CAP compartilham o corpo 2,76 bar 40 psi 0,77 L/min" })]).length === 0);
confere("L2  e a linha própria continua valendo",
  C.linesForCode("MJ981CAP", ["MJ981CAP", "MJ985CAP"], EV).length === 3);
confere("L3  o pino da pergunta ('a 40 psi') corta para uma linha por produto",
  plano.blocks.every((b) => new Set(b.values.map((v) => v.linha)).size === 1));

// ════════════════════════════════════════════════════════════
// HARDENING 18/09 — a prova tem de ser A prova
//
// Tudo abaixo nasceu de uma auditoria que não achou número errado: achou
// prova certa no lugar errado. São três buracos, e os três têm a mesma
// forma — duas verificações verdadeiras, cada uma olhando para um lado,
// e nenhuma delas provando o que a frase afirma.
// ════════════════════════════════════════════════════════════

// Uma segunda evidência que repete os MESMOS números para OUTROS produtos.
// É o fixture adversarial desta rodada: com ele, todo número da resposta
// existe em duas evidências, e citar a errada deixa de ser inofensivo.
const P21 = [
  "LITROS POR HECTARE (ESPAÇAMENTO 50CM)",
  "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min 4 km/h 5 km/h 6 km/h",
  LINHA("MJ811CAP", "01", "2,76", "40", "276", "0,77", "230 L/ha 184 L/ha 153 L/ha"),
  LINHA("MJ815CAP", "03", "2,76", "40", "276", "1,53", "460 L/ha 368 L/ha 307 L/ha"),
].join("\n");
const GEMEA = ev({
  chunkId: 73, content: P21, codes: ["MJ811CAP", "MJ815CAP"], page: { from: 21, to: 21 },
  citation: "Magnojet — Catálogo Magnojet V41 · p. 21",
});
const EV2 = [MAG, GEMEA];

// E um par de evidências que separa os dois produtos em DOCUMENTOS
// diferentes: aqui a diferença nasce de duas fontes, e uma citação só
// deixa metade da conta sem mostrar.
const SO_981 = ["LITROS POR HECTARE", "CÓDIGO BAR PSI kPa L/min",
  LINHA("MJ981CAP", "02", "2,76", "40", "276", "0,77", "230 L/ha")].join("\n");
const SO_985 = ["LITROS POR HECTARE", "CÓDIGO BAR PSI kPa L/min",
  LINHA("MJ985CAP", "04", "2,76", "40", "276", "1,53", "460 L/ha")].join("\n");
const DOC_A = ev({ chunkId: 80, content: SO_981, codes: ["MJ981CAP"] });
const DOC_B = ev({
  chunkId: 81, content: SO_985, codes: ["MJ985CAP"], page: { from: 21, to: 21 },
  document: { title: "Tabela complementar Magnojet", type: "catalog" },
  citation: "Magnojet — Tabela complementar Magnojet V41 · p. 21",
});
const EVD = [DOC_A, DOC_B];

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Proveniência do valor derivado (P1–P4)\n");

const planoD = C.planComparison(Q_40PSI, EVD);
confere("P0  o derivado guarda de onde veio cada parcela: código, número, unidade e evidência",
  planoD.derived.length === 1 &&
  planoD.derived[0].sources.length === 2 &&
  planoD.derived[0].sources[0].code === "MJ981CAP" && planoD.derived[0].sources[0].numero === "0,77" &&
  planoD.derived[0].sources[0].evidenceIndex === 0 &&
  planoD.derived[0].sources[1].code === "MJ985CAP" && planoD.derived[0].sources[1].numero === "1,53" &&
  planoD.derived[0].sources[1].evidenceIndex === 1,
  JSON.stringify(planoD.derived[0]?.sources));
confere("P0b e o literal liberado exige as DUAS evidências de origem",
  C.derivedLiterals(planoD).find((d) => d.texto === "0,76 L/min").requires.join(",") === "0,1");

confere("P1  derivado correto, com a citação da origem → PASSA",
  vq(Q_40PSI, CERTA).ok === true, vq(Q_40PSI, CERTA).problem ?? "ok");

const P2_ERRADA = [
  "MJ981CAP: 0,77 L/min [1]",
  "MJ985CAP: 1,53 L/min [1]",
  "Diferença: 0,76 L/min [2]",
].join("\n");
const r2 = vq(Q_40PSI, P2_ERRADA, EV2);
confere("P2  derivado correto, citação errada → REPROVADO", r2.ok === false && r2.kind === "comparison", r2.problem);
confere("P2b e o motivo diz de onde a conta saiu e o que o item citou",
  (r2.details ?? [])[0].includes("MJ981CAP 0,77 L/min") && (r2.details ?? [])[0].includes("cita [2]"),
  (r2.details ?? [])[0]);

const P3_METADE = [
  "MJ981CAP: 0,77 L/min [1]",
  "MJ985CAP: 1,53 L/min [2]",
  "Diferença: 0,76 L/min [1]",
].join("\n");
const r3 = vq(Q_40PSI, P3_METADE, EVD);
confere("P3  derivado de DOIS documentos com só um citado → REPROVADO",
  r3.ok === false && r3.kind === "comparison", r3.problem);

const P4_INTEIRA = [
  "MJ981CAP: 0,77 L/min [1]",
  "MJ985CAP: 1,53 L/min [2]",
  "Diferença: 0,76 L/min [1][2]",
].join("\n");
confere("P4  o mesmo caso, citando as duas → PASSA",
  vq(Q_40PSI, P4_INTEIRA, EVD).ok === true, vq(Q_40PSI, P4_INTEIRA, EVD).problem ?? "ok");

const P4b = ["MJ981CAP: 0,77 L/min [1]", "MJ985CAP: 1,53 L/min [2]", "", "Diferença: 0,76 L/min [1]"].join("\n");
confere("P4b em parágrafo próprio e sem as duas citações, o GROUNDING já barra antes",
  vq(Q_40PSI, P4b, EVD).kind === "grounding", vq(Q_40PSI, P4b, EVD).problem);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Tripla produto + valor + citação (P5, P6, P14, P15)\n");

confere("P5b o fixture é honesto: 0,77 e 1,53 existem NAS DUAS evidências",
  P21.includes("0,77 L/min") && P21.includes("1,53 L/min") &&
  P20.includes("0,77 L/min") && P20.includes("1,53 L/min"));

const P5_CRUZADA = [
  "MJ981CAP: 0,77 L/min [2]",
  "MJ985CAP: 1,53 L/min [1]",
].join("\n");
const r5 = vq(Q_40PSI, P5_CRUZADA, EV2);
confere("P5  valor certo do produto certo, mas citando a evidência que NÃO o sustenta → REPROVADO",
  r5.ok === false && r5.kind === "comparison", r5.problem);
confere("P5c o grounding sozinho deixaria passar: 0,77 L/min está mesmo em [2]",
  A.validateAnswer(P5_CRUZADA, A.buildCitations(EV2), EV2).ok === true,
  "sem a pergunta, não há comparação a conferir");

const P6_CERTA = [
  "MJ981CAP: 0,77 L/min [1]",
  "MJ985CAP: 1,53 L/min [1]",
].join("\n");
confere("P6  o mesmo valor com a citação certa → PASSA",
  vq(Q_40PSI, P6_CERTA, EV2).ok === true, vq(Q_40PSI, P6_CERTA, EV2).problem ?? "ok");

const P14_CRUZADA = [
  "MJ981CAP: 0,77 L/min [1]",
  "MJ985CAP: 1,53 L/min [2]",
].join("\n");
confere("P14 a prova cruzada do outro lado (1,53 é da MJ815CAP em [2]) → REPROVADO",
  vq(Q_40PSI, P14_CRUZADA, EV2).kind === "comparison", vq(Q_40PSI, P14_CRUZADA, EV2).problem);

confere("P15 produto, valor e citação todos certos → PASSA",
  vq(Q_40PSI, `${P6_CERTA}\nDiferença: 0,76 L/min [1]`, EV2).ok === true,
  vq(Q_40PSI, `${P6_CERTA}\nDiferença: 0,76 L/min [1]`, EV2).problem ?? "ok");

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Maior, menor e igual (P7–P13)\n");

const Q_MAIOR = "Qual tem maior vazão a 40 psi: MJ981CAP ou MJ985CAP?";
const Q_MENOR = "Qual tem menor vazão a 40 psi: MJ981CAP ou MJ985CAP?";

confere("P7a a intenção relacional é lida da pergunta, e só quando ela pergunta QUAL",
  C.parseRelationalIntent(Q_MAIOR) === "greater" &&
  C.parseRelationalIntent(Q_MENOR) === "lower" &&
  C.parseRelationalIntent(Q_40PSI) === null &&
  C.parseRelationalIntent("Quanto a MJ985CAP entrega a mais que a MJ981CAP a 40 psi?") === null,
  "quanto pede tamanho, não vencedor");

const relacao = C.relate(C.planComparison(Q_MAIOR, EV));
confere("P7b a relação sai dos valores validados, em código: 1,53 > 0,77",
  relacao.status === "ready" && relacao.unidade === "L/min" &&
  relacao.maiores.join() === "MJ985CAP" && relacao.menores.join() === "MJ981CAP" &&
  relacao.todosIguais === false,
  JSON.stringify(relacao));

const VALORES = "MJ981CAP: 0,77 L/min [1]\nMJ985CAP: 1,53 L/min [1]";
confere("P7  pergunta pede o maior, resposta aponta a MJ985CAP → PASSA",
  vq(Q_MAIOR, `A MJ985CAP tem maior vazão a 40 psi [1].\n${VALORES}`).ok === true,
  vq(Q_MAIOR, `A MJ985CAP tem maior vazão a 40 psi [1].\n${VALORES}`).problem ?? "ok");

const r8 = vq(Q_MAIOR, `A MJ981CAP tem maior vazão a 40 psi [1].\n${VALORES}`);
confere("P8  mesmos números, resposta aponta a MJ981CAP → REPROVADO", r8.kind === "comparison", r8.problem);

const r9 = vq(Q_MENOR, `A MJ985CAP tem menor vazão a 40 psi [1].\n${VALORES}`);
confere("P9  pergunta pede o menor, resposta aponta o maior → REPROVADO", r9.kind === "comparison", r9.problem);
confere("P9b e apontar o menor de verdade passa",
  vq(Q_MENOR, `A MJ981CAP tem menor vazão a 40 psi [1].\n${VALORES}`).ok === true);
confere("P9c a forma 'A tem maior X que B' também é lida",
  vq(Q_MAIOR, `A MJ985CAP tem maior vazão que a MJ981CAP [1].\n${VALORES}`).ok === true &&
  vq(Q_MAIOR, `A MJ981CAP tem maior vazão que a MJ985CAP [1].\n${VALORES}`).kind === "comparison");
confere("P9d perguntou qual é o maior e a resposta não conclui → REPROVADO",
  vq(Q_MAIOR, VALORES).kind === "comparison", vq(Q_MAIOR, VALORES).problem);

// valores iguais
const EMPATE = [
  "LITROS POR HECTARE (ESPAÇAMENTO 50CM)",
  "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min 4 km/h",
  LINHA("MJ981CAP", "02", "2,76", "40", "276", "1,53", "460 L/ha"),
  LINHA("MJ985CAP", "04", "2,76", "40", "276", "1,53", "460 L/ha"),
].join("\n");
const EVE = [ev({ content: EMPATE, codes: ["MJ981CAP", "MJ985CAP"] })];
const planoE = C.planComparison(Q_MAIOR, EVE);
const relE = C.relate(planoE);
confere("P10a empate: nenhuma diferença é calculada e a relação diz iguais",
  planoE.derived.length === 0 && relE.status === "ready" && relE.todosIguais === true &&
  relE.maiores.length === 0 && relE.menores.length === 0,
  JSON.stringify(relE));
const IGUAIS = "MJ981CAP: 1,53 L/min [1]\nMJ985CAP: 1,53 L/min [1]";
confere("P10 valores iguais e a resposta diz que são iguais → PASSA",
  vq(Q_MAIOR, `${IGUAIS}\nAs duas vazões são iguais a 40 psi [1]`, EVE).ok === true,
  vq(Q_MAIOR, `${IGUAIS}\nAs duas vazões são iguais a 40 psi [1]`, EVE).problem ?? "ok");
const r11 = vq(Q_MAIOR, `${IGUAIS}\nA MJ985CAP tem maior vazão [1]`, EVE);
confere("P11 valores iguais e a resposta declara um como maior → REPROVADO",
  r11.kind === "comparison", r11.problem);

confere("P12 pergunta que NÃO pede maior/menor não exige conclusão relacional → PASSA",
  vq(Q_40PSI, CERTA).ok === true && C.parseRelationalIntent(Q_40PSI) === null);

const Q_MAIOR_999 = "Qual tem maior vazão a 40 psi: MJ981CAP ou MJ999CAP?";
const r13 = vq(Q_MAIOR_999, "MJ981CAP: 0,77 L/min [1]\nNão encontrei documentação para a MJ999CAP [1]\nA MJ981CAP tem maior vazão [1]");
confere("P13 comparação incompleta e a resposta declara um maior → REPROVADO",
  r13.kind === "comparison", r13.problem);
confere("P13b e a resposta honesta, que declara a falta e não conclui, passa",
  vq(Q_MAIOR_999, "MJ981CAP: 0,77 L/min [1]\nNão encontrei documentação suficiente para a MJ999CAP nesse critério [1]").ok === true);
confere("P13c dois valores por produto (pergunta sem ponto fixado) não ordena nada",
  C.relate(C.planComparison("Qual tem maior vazão: MJ981CAP ou MJ985CAP?", EV)).status === "not_applicable",
  C.relate(C.planComparison("Qual tem maior vazão: MJ981CAP ou MJ985CAP?", EV)).reason);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Citação por parágrafo na comparação (T1–T8, 25/09)\n");
//
// O teste H ("quanto por cento a mais?") caía 3/3 com provedor real, e a
// causa provada no log do servidor não era o percentual: era parágrafo
// factual SEM citação — a linha de abertura ("A 40 psi (2,76 bar / 276
// kPa):") ou a conclusão ("A MJ985CAP tem maior vazão a 40 psi. A diferença
// é…"). O grounding estava certo em descartar. O que faltava era (a) o
// prompt dizer, no lugar certo, que diferença, percentual e conclusão também
// citam, e (b) a linha do bloco CÁLCULOS VERIFICADOS trazer a referência que
// o modelo precisa escrever. Estes casos provam que o pipeline de resposta
// inteiro — não só o plano — aceita a forma que o prompt pede e continua
// recusando o que ele proíbe. O validador não mudou.

const Q_H = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi. Quanto por cento a MJ985CAP entrega a mais?";
const BLOCOS = [
  "MJ981CAP [1]:",
  "- 40 psi -> 0,77 L/min [1]",
  "",
  "MJ985CAP [1]:",
  "- 40 psi -> 1,53 L/min [1]",
].join("\n");
const planoH = C.planComparison(Q_H, EV);
const CALC_H = planoH.derived.map((d) => P.renderCalculation(d, CIT));

confere("T0  a linha do bloco de cálculos leva a referência da evidência de origem",
  CALC_H.join(" | ") === "Diferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1] | Variação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]",
  CALC_H.join(" | "));
confere("T0b e a referência é o número da CITAÇÃO, não o índice da evidência (evidência 1 → [2])",
  P.renderCalculation(planoH.derived[0], [{ index: 2, evidenceIndex: 0 }]).endsWith("0,76 L/min [2]"));
confere("T0c parcelas em evidências diferentes → as duas referências na linha",
  P.renderCalculation(
    { ...planoH.derived[0], sources: [{ code: "MJ981CAP", numero: "0,77", unidade: "L/min", evidenceIndex: 0 }, { code: "MJ985CAP", numero: "1,53", unidade: "L/min", evidenceIndex: 1 }] },
    [{ index: 1, evidenceIndex: 0 }, { index: 2, evidenceIndex: 1 }],
  ).endsWith("0,76 L/min [1][2]"));
const MSG_H = P.buildUserMessage(Q_H, EV, CALC_H);
confere("T0d a mensagem manda copiar as linhas com a referência, e as linhas vão com ela",
  /Copie cada linha abaixo como está, com a referência indicada/.test(MSG_H) && MSG_H.includes("98,7% [1]"));

// T1 — a forma que o prompt pede (regra 11g), com os valores reais: PASSA
const T1 = `${BLOCOS}\n\n${CALC_H.join("\n")}`;
const r_t1 = vq(Q_H, T1);
confere("T1  blocos + linhas de cálculo copiadas com [1] → PASSA (98,7% aceito no pipeline inteiro)",
  r_t1.ok === true, r_t1.problem ?? "ok");
confere("T1b e a conclusão com a sua referência no mesmo parágrafo também passa",
  vq(Q_H, `${T1}\nA MJ985CAP tem maior vazão [1]`).ok === true);

// T2 — a conclusão SEM [1], como o modelo escreveu nos RUNs 2 e 3 de 25/09: grounding
const r_t2 = vq(Q_H, `${BLOCOS}\n\nA MJ985CAP tem maior vazão a 40 psi. A diferença entre MJ981CAP e MJ985CAP é de 0,76 L/min (98,7%).`);
confere("T2  parágrafo de conclusão sem citação → grounding reprova (parágrafo 3 afirma sem citar)",
  r_t2.kind === "grounding" && /parágrafo 3 afirma sem citar/.test(r_t2.problem), r_t2.problem);
const r_t2b = vq(Q_H, `A 40 psi (2,76 bar / 276 kPa):\n\nMJ981CAP: 0,77 L/min [1]\n\nMJ985CAP: 1,53 L/min [1]`);
confere("T2b linha de abertura sem citação, como no RUN 1 de 25/09 → grounding reprova (parágrafo 1)",
  r_t2b.kind === "grounding" && /parágrafo 1 afirma sem citar/.test(r_t2b.problem), r_t2b.problem);

// T3 — percentual certo, sem citação: FAIL
const r_t3 = vq(Q_H, `${BLOCOS}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7%`);
confere("T3  percentual correto sem citação → grounding reprova",
  r_t3.kind === "grounding" && /afirma sem citar/.test(r_t3.problem), r_t3.problem);
confere("T3b e \"conforme cálculos verificados\" não substitui a referência",
  vq(Q_H, `${BLOCOS}\n\nA MJ985CAP entrega 98,7% a mais (conforme cálculos verificados).`).kind === "grounding");

// T4 — percentual certo, com a citação certa: PASS
const r_t4 = vq(Q_H, `${BLOCOS}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]`);
confere("T4  percentual correto com citação correta → PASSA", r_t4.ok === true, r_t4.problem ?? "ok");
confere("T4b e o percentual só vale escrito como o sistema calculou: 98,70% e 98.7% continuam reprovados",
  vq(Q_H, `${BLOCOS}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98,70% [1]`).kind === "grounding" &&
  vq(Q_H, `${BLOCOS}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98.7% [1]`).kind === "grounding");

// T5 — parcelas em documentos diferentes: o parágrafo derivado cita as DUAS
// Reaproveita DOC_A/DOC_B (P1b): MJ981CAP só em [1], MJ985CAP só em [2].
const plano2 = C.planComparison(Q_H, EVD);
const CALC_2 = plano2.derived.map((d) => P.renderCalculation(d, A.buildCitations(EVD)));
confere("T5a com as parcelas em [1] e [2], as linhas de cálculo pedem as duas referências",
  CALC_2.every((l) => l.endsWith("[1][2]")), CALC_2.join(" | "));
const BLOCOS2 = "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [2]:\n- 40 psi -> 1,53 L/min [2]";
confere("T5  derivado citando as duas evidências de origem → PASSA",
  vq(Q_H, `${BLOCOS2}\n\n${CALC_2.join("\n")}`, EVD).ok === true,
  vq(Q_H, `${BLOCOS2}\n\n${CALC_2.join("\n")}`, EVD).problem ?? "ok");
const r_t5b = vq(Q_H, `${BLOCOS2}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]`, EVD);
confere("T5b derivado citando só uma das duas → REPROVADO (a conta não é conferível por [1] sozinho)",
  r_t5b.ok === false, r_t5b.problem);

// T6 — citação errada: a evidência citada não sustenta o que o parágrafo diz
const r_t6 = vq(Q_H, `MJ981CAP [2]:\n- 40 psi -> 0,77 L/min [2]\n\nMJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\n${CALC_2.join("\n")}`, EVD);
confere("T6  citação trocada (valor da MJ981CAP atribuído à evidência da MJ985CAP) → REPROVADO",
  r_t6.ok === false, r_t6.problem);
confere("T6b citação para evidência inexistente → format",
  vq(Q_H, `${BLOCOS}\n\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [3]`).kind === "format");

// T7 / T8 — conclusão maior/menor com e sem citação, na pergunta relacional
const Q_QUAL = "Qual tem maior vazão a 40 psi: MJ981CAP ou MJ985CAP?";
const CALC_Q = C.planComparison(Q_QUAL, EV).derived.map((d) => P.renderCalculation(d, CIT));
const r_t7 = vq(Q_QUAL, `${BLOCOS}\n\n${CALC_Q.join("\n")}\nA MJ985CAP tem maior vazão [1]`);
confere("T7  conclusão maior/menor com citação correta → PASSA", r_t7.ok === true, r_t7.problem ?? "ok");
const r_t8 = vq(Q_QUAL, `${BLOCOS}\n\n${CALC_Q.join("\n")}\n\nA MJ985CAP tem maior vazão.`);
confere("T8  conclusão maior/menor sem citação → grounding reprova", r_t8.kind === "grounding", r_t8.problem);

// O contrato do prompt, no lugar onde o modelo lê sobre comparação
const secaoComp = P.SYSTEM_PROMPT.slice(P.SYSTEM_PROMPT.indexOf("COMPARAÇÃO ENTRE CÓDIGOS"), P.SYSTEM_PROMPT.indexOf("VALOR PEDIDO QUE NÃO ESTÁ NA TABELA"));
confere("T9  o prompt exige, NA SEÇÃO de comparação, referência para diferença, percentual e conclusão",
  /11f\./.test(secaoComp) && /variação percentual e a conclusão/.test(secaoComp) && /ÚLTIMO parágrafo/.test(secaoComp) &&
  /linha de abertura/.test(secaoComp) && /conforme cálculos verificados/.test(secaoComp));
confere("T9b e traz exemplo positivo com cada linha citando, inclusive a diferença e a conclusão",
  /CÓDIGO-A \[1\]:/.test(secaoComp) && /Diferença entre CÓDIGO-A e CÓDIGO-B: 0,20 L\/min \[1\]/.test(secaoComp) &&
  /Variação percentual entre CÓDIGO-A e CÓDIGO-B: 200,0% \[1\]/.test(secaoComp) && /A CÓDIGO-B tem maior vazão \[1\]/.test(secaoComp));
confere("T9c a regra de forma não limita a comparação a dois parágrafos sem citar o terceiro",
  /um bloco por código e mais um parágrafo para diferença e conclusão/.test(P.SYSTEM_PROMPT) && /o último inclusive/.test(P.SYSTEM_PROMPT));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Associação + valores derivados (DA1–DA14, 25/09)\n");
//
// O segundo defeito que o teste H expôs. Com provedor real, "A diferença
// entre as duas é de 0,76 L/min, e a MJ985CAP entrega 98,7% a mais que a
// MJ981CAP a 40 psi [1]" passava no grounding (números certos, citação
// certa) e caía em `association`: o gate exigia UMA linha da tabela com os
// dois códigos, "40 psi", "0,76 L/min" e "98,7" — e essa linha não existe
// nem deveria, porque 0,76 e 98,7 são calculados sobre DUAS linhas. Havia um
// segundo tropeço na mesma frase, em `checkComparison` 1b: "40 psi" numa
// frase de diferença era lido como diferença anunciada, e não confere com
// 0,76 L/min. Os dois estão cobertos aqui. O que NÃO muda: par documental
// trocado de linha, valor de outro produto, derivado inventado e conclusão
// mentirosa continuam reprovando — e os testes adversariais provam isso.

const EX = await imp("exhaustiveness.ts");
const Q_DA = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi. Quanto por cento a MJ985CAP entrega a mais?";
const BLOCOS_DA = "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\n";
const planoDA = C.planComparison(Q_DA, EV);
const DERIV = planoDA.derived;

// A reprodução, gate a gate, ANTES de qualquer conserto: é o que prova a causa.
const ASSOC0 = `${BLOCOS_DA}A diferença entre MJ981CAP e MJ985CAP a 40 psi é de 0,76 L/min e a MJ985CAP entrega 98,7% a mais [1].`;
const G = await imp("grounding.ts");
confere("ASSOC-0 grounding PASSA na frase real (números certos, [1] certo)",
  G.checkGrounding(ASSOC0, CIT, EV, C.derivedLiterals(planoDA)).ok === true);
const a0 = EX.checkAssociation(Q_DA, ASSOC0, EV);
confere("ASSOC-0 e a associação SEM os derivados reprova: exige linha com os dois códigos e os valores calculados",
  a0.status === "failed" && /nenhuma linha traz MJ981CAP, MJ985CAP com esses valores/.test(a0.failures[0]), a0.failures?.[0]);
const a0d = EX.checkAssociation(Q_DA, ASSOC0, EV, DERIV);
confere("ASSOC-0 com os derivados do MESMO plano, a frase vira '40 psi' sozinha e não é julgada; só as duas linhas dos blocos são",
  a0d.status === "ok" && a0d.checked === 2, JSON.stringify(a0d));

// DA1 — o caso real, ponta a ponta
const da1 = vq(Q_DA, `${BLOCOS_DA}A diferença entre MJ981CAP e MJ985CAP a 40 psi é 0,76 L/min e 98,7% [1].`);
confere("DA1 caso real: blocos + frase com ponto fixado, diferença e percentual → PASSA", da1.ok === true, da1.problem ?? "ok");
const da1b = vq(Q_DA, `${BLOCOS_DA}A diferença entre as duas é de 0,76 L/min, e a MJ985CAP entrega 98,7% a mais que a MJ981CAP a 40 psi [1].`);
confere("DA1b a saída bruta do provider de 25/09 (RUN 2) → PASSA", da1b.ok === true, da1b.problem ?? "ok");

// DA2 — derivados corretos com citação correta, cada um na sua linha
confere("DA2 0,76 L/min [1] e 98,7% [1] em linhas próprias → PASSA",
  vq(Q_DA, `${BLOCOS_DA}Diferença: 0,76 L/min [1]\nVariação percentual: 98,7% [1]`).ok === true);

// DA3 / DA4 — derivado inventado: o grounding barra antes
const da3 = vq(Q_DA, `${BLOCOS_DA}A diferença a 40 psi é de 0,75 L/min e 98,7% [1].`);
confere("DA3 diferença inventada (0,75 L/min) → FAIL, e é o grounding que barra", da3.kind === "grounding", da3.problem);
const da4 = vq(Q_DA, `${BLOCOS_DA}A diferença a 40 psi é de 0,76 L/min e 97,8% [1].`);
confere("DA4 percentual inventado (97,8%) → FAIL, grounding", da4.kind === "grounding", da4.problem);

// DA5 — derivado certo, parcela documental errada
const da5 = vq(Q_DA, `MJ981CAP: 40 psi -> 0,86 L/min [1]\nMJ985CAP: 40 psi -> 1,53 L/min [1]\nA diferença a 40 psi é de 0,76 L/min e 98,7% [1].`);
confere("DA5 0,86 L/min posto a 40 psi (é a linha de 50 psi) → FAIL association, mesmo com o derivado certo ao lado",
  da5.kind === "association", `${da5.kind}: ${da5.problem}`);

// DA6 — valores trocados entre produtos; a diferença absoluta continua 0,76
const da6 = vq(Q_DA, `MJ981CAP: 40 psi -> 1,53 L/min [1]\nMJ985CAP: 40 psi -> 0,77 L/min [1]\nDiferença: 0,76 L/min [1]`);
confere("DA6 valores trocados entre produtos, diferença 0,76 correta → FAIL (o derivado não esconde o produto errado)",
  da6.ok === false && (da6.kind === "association" || da6.kind === "comparison"), `${da6.kind}: ${da6.problem}`);
const da6b = vq(Q_DA, `${BLOCOS_DA}A MJ981CAP entrega 1,53 L/min e a MJ985CAP entrega 0,77 L/min; diferença 0,76 L/min [1].`);
confere("DA6b a troca em prosa, na mesma frase → FAIL", da6b.ok === false, `${da6b.kind}: ${da6b.problem}`);

// DA7 — associação clássica de linha continua ativa dentro da comparação
const da7 = vq(Q_DA, `MJ981CAP: 2,07 bar -> 0,77 L/min [1]\nMJ985CAP: 40 psi -> 1,53 L/min [1]\nDiferença: 0,76 L/min [1]`);
confere("DA7 pressão de uma linha com a vazão de outra (2,07 bar -> 0,77) → FAIL association",
  da7.kind === "association", da7.problem);

// GAP1–GAP3 nasceram (25/09, commit 761bcf3) registrando um buraco: no
// formato em BLOCOS — o código numa linha ("MJ981CAP [1]:") e o valor na de
// baixo ("- 40 psi -> 0,86 L/min [1]") — a linha do valor não carregava
// código, a associação caía nos códigos da pergunta (linha com os dois →
// nenhuma) e desistia, e a comparação (bloco 1) só julgava item com um
// código. Valor errado, produto trocado e linha trocada passavam — no
// formato que a regra 11g manda escrever. Fechado com o contexto de bloco
// (`blockContexts`, exhaustiveness.ts): o cabeçalho empresta o código às
// linhas de baixo, nos dois gates. As três asserções agora PROVAM a
// correção; a seção PB abaixo cobre o resto.
const BLOCO = (a, b) => `MJ981CAP [1]:\n- ${a} [1]\n\nMJ985CAP [1]:\n- ${b} [1]\n\nDiferença: 0,76 L/min [1]`;
const gap1 = vq(Q_DA, BLOCO("40 psi -> 0,86 L/min", "40 psi -> 1,53 L/min"));
confere("GAP1 (bloco) 0,86 L/min a 40 psi na MJ981CAP → FAIL association (é a linha de 50 psi)",
  gap1.kind === "association", `${gap1.kind}: ${gap1.problem}`);
const gap2 = vq(Q_DA, BLOCO("40 psi -> 1,53 L/min", "40 psi -> 0,77 L/min"));
confere("GAP2 (bloco) produtos trocados → FAIL",
  gap2.ok === false && (gap2.kind === "association" || gap2.kind === "comparison"), `${gap2.kind}: ${gap2.problem}`);
const gap3 = vq(Q_DA, BLOCO("2,07 bar -> 0,77 L/min", "40 psi -> 1,53 L/min"));
confere("GAP3 (bloco) 2,07 bar -> 0,77 L/min → FAIL association",
  gap3.kind === "association", `${gap3.kind}: ${gap3.problem}`);

// DA8 / DA9 — sem derivados, nada muda (a suíte de listagem em check-brain-answer prova o resto)
const Q_LISTA = "Quais as vazões da MJ981CAP?";
const LISTA_TROCADA = "Vazões da MJ981CAP [1]:\n- 2,07 bar -> 0,77 L/min [1]\n- 2,76 bar -> 0,66 L/min [1]\n- 3,45 bar -> 0,86 L/min [1]";
confere("DA8 listagem não comparativa com pares trocados → FAIL association, como antes",
  vq(Q_LISTA, LISTA_TROCADA).kind === "association");
confere("DA9 checkAssociation sem o quarto argumento é o de sempre (assinatura compatível)",
  EX.checkAssociation(Q_LISTA, LISTA_TROCADA, EV).status === "failed" &&
  EX.checkAssociation(Q_LISTA, LISTA_TROCADA, EV, []).status === "failed" &&
  EX.checkAssociation(Q_LISTA, LISTA_TROCADA.replace("0,77 L/min", "0,66 L/min").replace("2,76 bar -> 0,66", "2,76 bar -> 0,77"), EV).status === "ok");

// DA10 — comparação incompleta: nenhum derivado existe, nada é liberado
confere("DA10 MJ981CAP + MJ999CAP: plano incompleto, zero derivados, e a diferença anunciada reprova",
  C.planComparison(Q_999, EV).incomplete === true && C.planComparison(Q_999, EV).derived.length === 0 &&
  vq(Q_999, "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nNão encontrei documentação suficiente para MJ999CAP [1]\n\nDiferença: 0,76 L/min [1]").ok === false);

// DA11 — parcelas em evidências diferentes
const planoAB = C.planComparison(Q_DA, EVD);
const derivAB = planoAB.derived;
confere("DA11a com as parcelas em [1] e [2], cada derivado exige as duas",
  derivAB.length === 2 && derivAB.every((d) => new Set(d.sources.map((s) => s.evidenceIndex)).size === 2));
const da11 = vq(Q_DA, "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [2]:\n- 40 psi -> 1,53 L/min [2]\n\nA diferença entre MJ981CAP e MJ985CAP a 40 psi é de 0,76 L/min e 98,7% [1][2].", EVD);
confere("DA11 frase real citando [1][2] → PASSA (sem falso positivo de associação)", da11.ok === true, da11.problem ?? "ok");
const da11b = vq(Q_DA, "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [2]:\n- 40 psi -> 1,53 L/min [2]\n\nA diferença entre MJ981CAP e MJ985CAP a 40 psi é de 0,76 L/min e 98,7% [1].", EVD);
confere("DA11b citando só [1] → FAIL, e é o grounding que barra ANTES da associação", da11b.kind === "grounding", da11b.problem);

// DA12 / DA13 — conclusão relacional
confere("DA12 'A MJ985CAP tem maior vazão a 40 psi [1].' depois dos blocos certos → PASSA",
  vq(Q_DA, `${BLOCOS_DA}A MJ985CAP tem maior vazão a 40 psi [1].`).ok === true);
const da13 = vq(Q_DA, `${BLOCOS_DA}A MJ981CAP tem maior vazão a 40 psi [1].`);
confere("DA13 'A MJ981CAP tem maior vazão' → FAIL por comparison", da13.kind === "comparison", da13.problem);

// DA14 — o essencial contra bypass: derivado legítimo NA MESMA frase de um documental errado
const da14 = vq(Q_DA, `${BLOCOS_DA}A MJ985CAP entrega 98,7% a mais que a MJ981CAP a 40 psi, com 0,86 L/min [1].`);
confere("DA14 98,7% legítimo + 0,86 L/min (linha de 50 psi) na mesma frase → FAIL",
  da14.ok === false && (da14.kind === "association" || da14.kind === "comparison"), `${da14.kind}: ${da14.problem}`);
const da14b = vq(Q_DA, `${BLOCOS_DA}A MJ985CAP entrega 98,7% a mais a 40 psi, com 1,72 L/min [1].`);
confere("DA14b 98,7% legítimo + 1,72 L/min (MJ985CAP a 50 psi) posto a 40 psi → FAIL association",
  da14b.kind === "association", da14b.problem);

// Isolamento: o que sai e o que fica
const a1 = EX.checkAssociation(Q_DA, "A MJ985CAP entrega 98,7% a mais a 40 psi, com 1,72 L/min", EV, DERIV);
confere("ISO1 só o literal derivado sai; 40 psi + 1,72 L/min continuam conferidos e reprovam",
  a1.status === "failed" && a1.checked === 1 && /40 psi com 1,72 L\/min/.test(a1.failures[0]), a1.failures?.[0]);
const a2 = EX.checkAssociation(Q_DA, "MJ985CAP: 40 psi -> 1,53 L/min, 0,76 L/min a mais", EV, DERIV);
confere("ISO2 par documental certo + derivado no mesmo item → conferido (1) e ok",
  a2.status === "ok" && a2.checked === 1, JSON.stringify(a2));
const a3 = EX.checkAssociation(Q_DA, "MJ985CAP: 40 psi -> 10,76 L/min", EV, DERIV);
confere("ISO3 '10,76 L/min' não perde o '0,76 L/min' de dentro: continua reprovado",
  a3.status === "failed", JSON.stringify(a3));
const a4 = EX.checkAssociation(Q_DA, "Variação: 98,7 % a 40 psi e 0,76L/min", EV, DERIV);
confere("ISO4 as grafias com/sem espaço do derivado também saem ('98,7 %', '0,76L/min')",
  a4.status === "ok" && a4.checked === 0, JSON.stringify(a4));
confere("ISO5 a mensagem de falha mostra o item como foi escrito, não o texto sem derivados",
  /98,7%/.test(a1.failures[0]));

// O ponto fixado no checkComparison 1b
confere("CMP1 '40 psi' (ponto da pergunta) numa frase de diferença não é diferença anunciada",
  C.checkComparison(Q_DA, `${BLOCOS_DA}A diferença a 40 psi é de 0,76 L/min [1]`, EV, CIT).status === "ok");
const cmp2 = C.checkComparison(Q_DA, `${BLOCOS_DA}A diferença a 30 psi é de 0,76 L/min [1]`, EV, CIT);
confere("CMP2 '30 psi' (não é o ponto da pergunta) numa frase de diferença → continua reprovado",
  cmp2.status === "failed" && /30 psi/.test(cmp2.failures[0]), cmp2.failures?.[0]);
const cmp3 = C.checkComparison(Q_DA, `${BLOCOS_DA}A diferença a 40 psi é de 0,86 L/min [1]`, EV, CIT);
confere("CMP3 e a diferença errada ao lado do ponto fixado → continua reprovada",
  cmp3.status === "failed" && /0,86 L\/min/.test(cmp3.failures[0]), cmp3.failures?.[0]);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Product binding no formato em blocos (PB1–PB15, 25/09)\n");
//
// Cada cenário é registrado gate a gate — grounding, associação, comparação
// e validateAnswer — porque "validateAnswer = false" não diz QUEM barrou, e
// é isso que prova que o vínculo produto → valor está sendo fiscalizado no
// formato oficial, e não só que alguma coisa reprovou.

const Q_PB = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi.";
const gates = (q, t, evs = EV) => {
  const cit = A.buildCitations(evs);
  const plano = C.planComparison(q, evs);
  const g = G.checkGrounding(t, cit, evs, C.derivedLiterals(plano));
  const a = EX.checkAssociation(q, t, evs, plano.status === "ready" ? plano.derived : []);
  const c = C.checkComparison(q, t, evs, cit);
  const v = A.validateAnswer(t, cit, evs, q);
  return {
    grounding: g.ok, association: a.status, checked: a.checked, comparison: c.status,
    ok: v.ok, kind: v.ok ? "ok" : v.kind,
    resumo: `grounding=${g.ok ? "PASS" : "FAIL"} association=${a.status}(${a.checked}) comparison=${c.status} validateAnswer=${v.ok ? "PASS" : `FAIL ${v.kind}`}`,
  };
};
const BL = (a, b, cauda = "") => `MJ981CAP [1]:\n- ${a} [1]\n\nMJ985CAP [1]:\n- ${b} [1]${cauda}`;

// O contexto em si
const CONH = new Set(["MJ981CAP", "MJ982CAP", "MJ985CAP"]);
confere("PB0  cabeçalho: 'MJ981CAP:', 'MJ981CAP [1]:', '**MJ981CAP** [1][2]:' e 'MJ981CAP' sozinho estabelecem contexto",
  ["MJ981CAP:", "MJ981CAP [1]:", "**MJ981CAP** [1][2]:", "MJ981CAP", "- mj981cap [1]:"].every((l) => EX.blockHeaderCode(l, CONH) === "MJ981CAP"));
confere("PB0b prosa e pseudo-cabeçalhos NÃO estabelecem contexto",
  ["A MJ981CAP tem maior vazão", "MJ981CAP e MJ985CAP:", "Compare MJ981CAP:", "Para MJ981CAP a 40 psi:", "MJ981CAP a 40 psi [1]:", "MJ999CAP:", "40 psi -> 0,77 L/min", ""].every((l) => EX.blockHeaderCode(l, CONH) === null));
const ctx = EX.blockContexts("MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 50 psi -> 0,86 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nA MJ985CAP tem maior vazão [1].", CONH).map((l) => l.contexto);
confere("PB0c herança: linhas do bloco herdam, novo cabeçalho substitui, linha em branco encerra, conclusão fica sem contexto",
  JSON.stringify(ctx) === JSON.stringify(["MJ981CAP", "MJ981CAP", "MJ981CAP", null, "MJ985CAP", "MJ985CAP", null, null]), JSON.stringify(ctx));

const pb1 = gates(Q_PB, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min"));
confere("PB1  bloco correto → PASSA, e as duas linhas de valor são conferidas (checked=2)",
  pb1.ok && pb1.association === "ok" && pb1.checked === 2 && pb1.comparison === "ok", pb1.resumo);

const pb2 = gates(Q_PB, BL("40 psi -> 1,53 L/min", "40 psi -> 0,77 L/min"));
confere("PB2  valores trocados entre produtos → grounding PASSA, association E comparison reprovam",
  pb2.grounding && pb2.association === "failed" && pb2.comparison === "failed" && !pb2.ok, pb2.resumo);

const pb3 = gates(Q_PB, BL("40 psi -> 0,86 L/min", "40 psi -> 1,53 L/min"));
confere("PB3  valor de outra linha do mesmo produto (0,86 é a MJ981CAP a 50 psi) → association reprova (comparison não: o valor É da MJ981CAP)",
  pb3.grounding && pb3.association === "failed" && pb3.comparison === "ok" && pb3.kind === "association", pb3.resumo);

const pb4 = gates(Q_PB, "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 0,77 L/min [1]");
confere("PB4  novo cabeçalho troca o contexto: 0,77 debaixo de MJ985CAP é julgado como MJ985CAP e reprova",
  !pb4.ok && pb4.association === "failed" && pb4.comparison === "failed" && /MJ985CAP/.test(A.validateAnswer("MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 0,77 L/min [1]", CIT, EV, Q_PB).problem), pb4.resumo);

const Q_QUAL_PB = "Qual tem maior vazão a 40 psi: MJ981CAP ou MJ985CAP?";
const pb5a = gates(Q_QUAL_PB, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nA MJ985CAP tem maior vazão [1]."));
confere("PB5a conclusão relacional certa depois dos blocos → PASSA (não herda o bloco anterior)", pb5a.ok, pb5a.resumo);
const pb5b = gates(Q_QUAL_PB, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nA MJ981CAP tem maior vazão [1]."));
confere("PB5b conclusão relacional errada → comparison reprova", pb5b.comparison === "failed" && pb5b.kind === "comparison", pb5b.resumo);

const pb6 = gates(Q_PB, "MJ981CAP e MJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]");
confere("PB6  'MJ981CAP e MJ985CAP:' não é cabeçalho: a linha de baixo segue a regra conservadora antiga (sem dono, não julgada)",
  EX.blockHeaderCode("MJ981CAP e MJ985CAP [1]:", CONH) === null && pb6.checked === 0, pb6.resumo);

const pb7 = EX.blockContexts("A MJ981CAP tem maior vazão [1].\n- 40 psi -> 1,53 L/min [1]", CONH);
confere("PB7  prosa com código não vira cabeçalho: a linha seguinte não herda MJ981CAP",
  pb7[0].cabecalho === false && pb7[1].contexto === null);

confere("PB8  'MJ981CAP [1]:' → contexto MJ981CAP", EX.blockContexts("MJ981CAP [1]:\n- x 1", CONH)[1].contexto === "MJ981CAP");
confere("PB9  'MJ981CAP [1][2]:' → contexto MJ981CAP", EX.blockContexts("MJ981CAP [1][2]:\n- x 1", CONH)[1].contexto === "MJ981CAP");

// PB10 — listagem não comparativa: idêntico ao histórico
const Q_L = "Quais as vazões da MJ981CAP?";
const LISTA_L = "Vazões da MJ981CAP [1]:\n- 2,07 bar -> 0,66 L/min [1]\n- 2,76 bar -> 0,77 L/min [1]\n- 3,45 bar -> 0,86 L/min [1]";
confere("PB10 listagem não comparativa: certa PASSA, trocada reprova por association, como antes",
  vq(Q_L, LISTA_L).ok === true && vq(Q_L, LISTA_L.replace("0,66", "X").replace("0,77", "0,66").replace("X", "0,77")).kind === "association" &&
  EX.blockHeaderCode("Vazões da MJ981CAP [1]:", CONH) === null);

// PB11 — três códigos, cada bloco com o seu contexto
const Q_3 = "Compare a vazão da MJ981CAP, MJ982CAP e MJ985CAP a 40 psi";
const TRES = (a, b, c) => `MJ981CAP [1]:\n- 40 psi -> ${a} [1]\n\nMJ982CAP [1]:\n- 40 psi -> ${b} [1]\n\nMJ985CAP [1]:\n- 40 psi -> ${c} [1]`;
const pb11 = gates(Q_3, TRES("0,77 L/min", "0,96 L/min", "1,53 L/min"));
confere("PB11 três blocos certos → PASSA, três linhas conferidas", pb11.ok && pb11.checked === 3, pb11.resumo);
const pb11b = gates(Q_3, TRES("0,77 L/min", "1,53 L/min", "0,96 L/min"));
confere("PB11b troca entre o 2º e o 3º bloco → reprova (sem bleed do 1º)", !pb11b.ok && pb11b.association === "failed", pb11b.resumo);
const pb11c = gates(Q_3, TRES("0,96 L/min", "0,96 L/min", "1,53 L/min"));
confere("PB11c valor do 2º posto no 1º → reprova", !pb11c.ok, pb11c.resumo);

// PB12 / PB13 — derivados
const pb12 = gates(Q_DA, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nDiferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1]\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]"));
confere("PB12 blocos certos + 0,76 L/min + 98,7% → PASSA", pb12.ok, pb12.resumo);
const pb12b = gates(Q_DA, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nA diferença entre MJ981CAP e MJ985CAP a 40 psi é de 0,76 L/min e 98,7% [1]."));
confere("PB12b a frase real do provider (DA1) continua passando com o contexto de bloco", pb12b.ok, pb12b.resumo);
const pb13 = gates(Q_DA, BL("40 psi -> 0,86 L/min", "40 psi -> 1,53 L/min", "\n\nDiferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1]\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]"));
confere("PB13 derivado correto não esconde o bloco errado → reprova", !pb13.ok && pb13.association === "failed", pb13.resumo);

// PB14 — cabeçalho sem linha numérica: nada a associar, nada a reprovar
const pb14 = gates(Q_PB, "MJ981CAP [1]:\nSem valor a 40 psi nesta tabela [1]\n\nMJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]");
confere("PB14 cabeçalho sem linha numérica não inventa falha de associação", pb14.association === "ok" && pb14.checked === 1, pb14.resumo);

// PB15 — linha órfã, fora de bloco: regra conservadora de antes
const pb15 = gates(Q_PB, "MJ981CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n\n- 40 psi -> 1,53 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 1,53 L/min [1]");
confere("PB15 linha órfã (sem cabeçalho) não ganha produto: segue não julgada, como antes (checked=2, só as dos blocos)",
  pb15.checked === 2 && pb15.ok, pb15.resumo);

// O teste crítico da rodada, em separado
const critico = gates(Q_PB, "MJ981CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nMJ985CAP [1]:\n- 40 psi -> 0,77 L/min [1]");
confere("PB-CRÍTICO 1,53 debaixo de MJ981CAP e 0,77 debaixo de MJ985CAP → REPROVADO nos dois gates", !critico.ok && critico.association === "failed" && critico.comparison === "failed", critico.resumo);

// Comportamento antigo sem cabeçalho nenhum permanece
confere("PB16 sem cabeçalho, inline com código: idêntico ao histórico (P1..P15 acima já passaram)",
  gates(Q_PB, "MJ981CAP: 40 psi -> 1,53 L/min [1]\nMJ985CAP: 40 psi -> 0,77 L/min [1]").association === "failed");

rmSync(destino, { recursive: true, force: true });
process.stdout.write(falhas === 0 ? "✔ comparação entre códigos\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
