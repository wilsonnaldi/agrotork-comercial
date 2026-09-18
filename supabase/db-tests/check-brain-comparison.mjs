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

rmSync(destino, { recursive: true, force: true });
process.stdout.write(falhas === 0 ? "✔ comparação entre códigos\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
