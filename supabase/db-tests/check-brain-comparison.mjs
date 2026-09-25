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
// ISO4 — a entrada mudou em 25/09 (colisão derivado × documental): o
// derivado agora só sai de frase de cálculo, e a antiga ("Variação: …")
// passava pela regra do item sem dono, não pela remoção. Com a MJ985CAP
// escrita no item, ele É julgado: sem a remoção, "40 psi" + "0,76 L/min" na
// linha da MJ985CAP reprovaria — a segunda asserção prova isso.
const ISO4 = "MJ985CAP: variação percentual de 98,7 % a 40 psi e 0,76L/min a mais";
const a4 = EX.checkAssociation(Q_DA, ISO4, EV, DERIV);
confere("ISO4 em frase de cálculo, as grafias com/sem espaço do derivado também saem ('98,7 %', '0,76L/min'): sobra só '40 psi'",
  a4.status === "ok" && a4.checked === 0 &&
  EX.checkAssociation(Q_DA, ISO4, EV, []).status === "failed", JSON.stringify(a4));
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

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Cabeçalho com ponto fixado (HDR / H1–H20, 25/09)\n");
//
// A variante REAL que ficava de fora: "MJ981CAP a 40 psi [1]:" apareceu em
// 2 de 10 saídas do provedor e não era cabeçalho, então a linha de baixo
// voltava a ficar sem dono (checked=0) — o mesmo buraco do PB, por outra
// porta. A gramática cresce o mínimo: depois do código, só "a"/"@" + um
// ponto que a PERGUNTA fixou, escrito igual. Sem conversão, sem prosa.

const PIN40 = C.parseComparison(Q_PB).pinned;
confere("HDR0 o ponto fixado vem da pergunta, não de constante: '40 psi'",
  JSON.stringify(PIN40) === JSON.stringify([{ numero: "40", unidade: "psi" }]));

// A reprodução: sem o pinned (o helper como estava), o cabeçalho real não conta
confere("HDR-GAP1 sem o ponto fixado (o helper como estava em bf1749f), 'MJ981CAP a 40 psi [1]:' não é cabeçalho e a linha de baixo fica sem contexto",
  EX.blockHeaderCode("MJ981CAP a 40 psi [1]:", CONH) === null &&
  EX.blockContexts("MJ981CAP a 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]", CONH)[1].contexto === null);

const hdr = (l) => EX.blockHeaderCode(l, CONH, PIN40);
confere("H1  'MJ981CAP a 40 psi [1]:' → MJ981CAP", hdr("MJ981CAP a 40 psi [1]:") === "MJ981CAP");
confere("H2  'MJ985CAP a 40 psi [1]:' → MJ985CAP", hdr("MJ985CAP a 40 psi [1]:") === "MJ985CAP");
const HP = (a, b, cauda = "") => `MJ981CAP a 40 psi [1]:\n- ${a} [1]\n\nMJ985CAP a 40 psi [1]:\n- ${b} [1]${cauda}`;
const h3 = gates(Q_PB, HP("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min"));
confere("H3  valores certos sob cabeçalhos com ponto fixado → PASSA, e as duas linhas são conferidas", h3.ok && h3.checked === 2, h3.resumo);
const h4 = gates(Q_PB, HP("40 psi -> 1,53 L/min", "40 psi -> 1,53 L/min"));
confere("H4  valor da MJ985CAP sob 'MJ981CAP a 40 psi' → FAIL (association e comparison)",
  !h4.ok && h4.association === "failed" && h4.comparison === "failed", h4.resumo);
const h5 = gates(Q_PB, HP("40 psi -> 1,53 L/min", "40 psi -> 0,77 L/min"));
confere("H5  produtos trocados com cabeçalhos de ponto fixado → FAIL", !h5.ok && h5.association === "failed" && h5.comparison === "failed", h5.resumo);
const h6 = gates(Q_PB, HP("40 psi -> 0,86 L/min", "40 psi -> 1,53 L/min"));
confere("H6  valor de outra linha do mesmo produto → association FAIL", h6.association === "failed" && h6.kind === "association", h6.resumo);
confere("H7  'MJ981CAP a 50 psi:' com a pergunta fixando 40 psi → NÃO é cabeçalho", hdr("MJ981CAP a 50 psi:") === null && hdr("MJ981CAP a 50 psi [1]:") === null);
confere("H8  'Compare MJ981CAP:' → NÃO é cabeçalho", hdr("Compare MJ981CAP:") === null);
confere("H9  'Para MJ981CAP a 40 psi:' → NÃO é cabeçalho", hdr("Para MJ981CAP a 40 psi:") === null && hdr("A MJ981CAP:") === null);
confere("H10 'MJ981CAP tem maior vazão:' → NÃO é cabeçalho", hdr("MJ981CAP tem maior vazão:") === null && hdr("MJ981CAP com vazão maior:") === null);
confere("H11 'MJ981CAP e MJ985CAP a 40 psi:' → NÃO é cabeçalho único", hdr("MJ981CAP e MJ985CAP a 40 psi:") === null && hdr("MJ981CAP e MJ985CAP:") === null);
confere("H12 'MJ999CAP a 40 psi:' → NÃO é cabeçalho conhecido", hdr("MJ999CAP a 40 psi:") === null);
confere("H13 'MJ981CAP @ 40 psi [1]:' → cabeçalho (o conector @ é aceito)", hdr("MJ981CAP @ 40 psi [1]:") === "MJ981CAP");
confere("H14 cabeçalhos simples continuam: 'MJ981CAP [1]:', '**MJ981CAP** [1]:', 'MJ981CAP:'",
  ["MJ981CAP [1]:", "**MJ981CAP** [1]:", "MJ981CAP:", "MJ981CAP"].every((l) => hdr(l) === "MJ981CAP"));
const ctxH = EX.blockContexts("MJ981CAP a 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP a 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]\n\nA MJ985CAP tem maior vazão [1].", CONH, PIN40).map((l) => l.contexto);
confere("H15 linha em branco encerra o contexto", ctxH[2] === null && ctxH[5] === null, JSON.stringify(ctxH));
confere("H16 novo cabeçalho troca o contexto", ctxH[3] === "MJ985CAP" && ctxH[4] === "MJ985CAP", JSON.stringify(ctxH));
const TRESP = (a, b, c) => `MJ981CAP a 40 psi [1]:\n- 40 psi -> ${a} [1]\n\nMJ982CAP a 40 psi [1]:\n- 40 psi -> ${b} [1]\n\nMJ985CAP a 40 psi [1]:\n- 40 psi -> ${c} [1]`;
const h17 = gates(Q_3, TRESP("0,77 L/min", "0,96 L/min", "1,53 L/min"));
const h17b = gates(Q_3, TRESP("0,77 L/min", "1,53 L/min", "0,96 L/min"));
confere("H17 três produtos com ponto fixado: certo PASSA (3 conferidas), troca 2º↔3º FAIL",
  h17.ok && h17.checked === 3 && !h17b.ok && h17b.association === "failed", `${h17.resumo} | ${h17b.resumo}`);
const h18 = gates(Q_DA, HP("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nDiferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1]\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]"));
confere("H18 derivados depois dos blocos com ponto fixado → PASSA", h18.ok, h18.resumo);
const h19 = gates(Q_QUAL_PB, HP("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nA MJ985CAP tem maior vazão [1]."));
const h19b = gates(Q_QUAL_PB, HP("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nA MJ981CAP tem maior vazão [1]."));
confere("H19 conclusão depois da quebra não herda: certa PASSA, errada FAIL por comparison",
  h19.ok && h19b.kind === "comparison", `${h19.resumo} | ${h19b.resumo}`);

// H20 — ponto fixado diferente, genérico: a pergunta fixa 2,76 bar
const Q_BAR = "Compare a vazão da MJ981CAP e MJ985CAP a 2,76 bar";
const PINBAR = C.parseComparison(Q_BAR).pinned;
confere("H20a a pergunta em bar fixa '2,76 bar'", JSON.stringify(PINBAR) === JSON.stringify([{ numero: "2,76", unidade: "bar" }]));
confere("H20b 'MJ981CAP a 2,76 bar [1]:' é cabeçalho para ESSA pergunta, e 'MJ981CAP a 40 psi:' não é",
  EX.blockHeaderCode("MJ981CAP a 2,76 bar [1]:", CONH, PINBAR) === "MJ981CAP" && EX.blockHeaderCode("MJ981CAP a 40 psi:", CONH, PINBAR) === null);
confere("H20c e vice-versa: com 40 psi fixado, 'MJ981CAP a 2,76 bar:' NÃO é cabeçalho (sem conversão, mesmo sendo a mesma pressão)",
  hdr("MJ981CAP a 2,76 bar:") === null && hdr("MJ981CAP a 276 kPa:") === null);
const h20 = gates(Q_BAR, "MJ981CAP a 2,76 bar [1]:\n- 2,76 bar -> 1,53 L/min [1]\n\nMJ985CAP a 2,76 bar [1]:\n- 2,76 bar -> 0,77 L/min [1]");
confere("H20 troca de produtos sob cabeçalhos 'a 2,76 bar' → FAIL (funciona para qualquer ponto fixado)",
  !h20.ok && h20.association === "failed" && h20.comparison === "failed", h20.resumo);
confere("H20d ponto fixado colado ('MJ981CAP a 40psi:') e com mais de um ponto na pergunta",
  hdr("MJ981CAP a 40psi:") === "MJ981CAP" &&
  EX.blockHeaderCode("MJ981CAP a 40 psi a 2,76 bar:", CONH, [{ numero: "40", unidade: "psi" }, { numero: "2,76", unidade: "bar" }]) === "MJ981CAP" &&
  hdr("MJ981CAP a 40 psi a 2,76 bar:") === null);
confere("H21 depois do ponto fixado, nada mais: 'MJ981CAP a 40 psi e maior vazão:' e 'MJ981CAP a 40 psi 0,77 L/min:' → NÃO",
  hdr("MJ981CAP a 40 psi e maior vazão:") === null && hdr("MJ981CAP a 40 psi 0,77 L/min:") === null && hdr("MJ981CAP 40 psi:") === null);

// O adversarial crítico da rodada
const critH = gates(Q_PB, "MJ981CAP a 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]\n\nMJ985CAP a 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]");
confere("HDR-CRÍTICO produtos trocados sob 'X a 40 psi [1]:' → grounding PASS, association FAIL, comparison FAIL, validateAnswer FAIL",
  critH.grounding && critH.association === "failed" && critH.comparison === "failed" && !critH.ok, critH.resumo);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Colisão derivado × documental (COL0–COL12, 25/09)\n");
//
// Achado de auditoria: `checkAssociation` tirava o literal derivado de TODO
// item antes de conferir a linha. O literal é texto, não carimbo de origem —
// se a diferença calculada (0,76 L/min, A−B a 40 psi) coincide com um valor
// documental do próprio produto noutra linha (A a 50 psi = 0,76 L/min), a
// linha ERRADA "- 40 psi -> 0,76 L/min" debaixo de A perdia o 0,76, sobrava
// "40 psi" sozinho e o par não era conferido. O grounding passa (0,76 L/min
// existe no documento e é derivado liberado) e a comparação passa (o valor é
// de A, em ALGUMA linha — o bloco 1 não olha a linha). Reproduzido em HEAD
// 152708b, com o fixture sintético abaixo, nos dois formatos e nas duas
// perguntas (com e sem percentual): grounding=PASS association=ok(1)
// comparison=ok validateAnswer=PASS — bypass.
//
// O conserto: o derivado só sai de item que ANUNCIA cálculo
// (`isDerivedStatement`: diferença, variação percentual, percentual, por
// cento, a mais, a menos). Linha de tabela é conferida inteira.
//
// Fixture SINTÉTICO de propósito: os números do Magnojet não colidem, e a
// prova não pode depender de um catálogo que muda.
const COL_TAB = [
  "LITROS POR HECTARE (ESPAÇAMENTO 50CM)",
  "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min 4 km/h 5 km/h 6 km/h",
  LINHA("MJ701CAP", "02", "2,76", "40", "276", "0,77", "230 L/ha"),
  LINHA("MJ701CAP", "02", "3,45", "50", "345", "0,76", "228 L/ha"),
  LINHA("MJ702CAP", "04", "2,76", "40", "276", "1,53", "460 L/ha"),
].join("\n");
const COL_EV = (content = COL_TAB) => [ev({
  chunkId: 500, content, codes: ["MJ701CAP", "MJ702CAP"], headingPath: ["TABELA SINTÉTICA"],
  source: "Sintético", document: { title: "Tabela sintética", type: "catalog" },
  version: { label: "T1", status: "active" }, page: { from: 1, to: 1 },
  citation: "Sintético — Tabela sintética T1 · p. 1",
})];
const EVCOL = COL_EV();
const Q_COL = "Compare a vazão da MJ701CAP e MJ702CAP a 40 psi.";
const Q_COLP = "Compare a vazão da MJ701CAP e MJ702CAP a 40 psi. Quanto por cento a MJ702CAP entrega a mais?";
const planoCol = C.planComparison(Q_COL, EVCOL);
const planoColP = C.planComparison(Q_COLP, EVCOL);
const BLC = (a, b, cauda = "") => `MJ701CAP [1]:\n- ${a} [1]\n\nMJ702CAP [1]:\n- ${b} [1]${cauda}`;
const BLC_OK = BLC("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min");

// O percentual esperado sai das parcelas do PLANO, não de constante.
const [colA, colB] = planoColP.blocks.map((b) => Number(b.values[0].numero.replace(",", ".")));
const PCT_COL = `${(((colB - colA) / colA) * 100).toFixed(1).replace(".", ",")}%`;

confere("COL0 fixture: plano A@40=0,77, B@40=1,53, diferença 0,76 L/min — e A tem 0,76 L/min DE VERDADE na linha de 50 psi",
  planoCol.status === "ready" &&
  planoCol.blocks.map((b) => `${b.code}=${b.values.map((v) => v.numero).join("/")}`).join(",") === "MJ701CAP=0,77,MJ702CAP=1,53" &&
  planoCol.derived.length === 1 && planoCol.derived[0].texto === "0,76 L/min" &&
  COL_TAB.split("\n").some((l) => l.includes("MJ701CAP") && l.includes("50 psi") && l.includes("0,76 L/min")),
  planoCol.derived.map((d) => `${d.tipo}:${d.texto}`).join(" · "));
confere("COL0b com percentual: o plano calcula 0,76 L/min e o percentual que as parcelas dão",
  planoColP.derived.map((d) => d.texto).join(" · ") === `0,76 L/min · ${PCT_COL}` && PCT_COL === "98,7%",
  planoColP.derived.map((d) => d.texto).join(" · "));

// COL1 — a linha errada, sozinha, direto no gate
const col1 = EX.checkAssociation(Q_COL, "MJ701CAP: 40 psi -> 0,76 L/min", EVCOL, planoCol.derived);
const col1g = gates(Q_COL, "MJ701CAP: 40 psi -> 0,76 L/min [1]\nMJ702CAP: 40 psi -> 1,53 L/min [1]", EVCOL);
confere("COL1 'MJ701CAP: 40 psi -> 0,76 L/min' com o derivado 0,76 no plano → association FAIL (0,76 é de 50 psi)",
  col1.status === "failed" && /40 psi com 0,76 L\/min/.test(col1.failures[0]) &&
  col1g.grounding && col1g.association === "failed" && col1g.comparison === "ok" && col1g.kind === "association",
  col1g.resumo);

// COL2 / COL3 — as duas formas da auditoria, nas duas perguntas
const COL_BLOCO = BLC("40 psi -> 0,76 L/min", "40 psi -> 1,53 L/min", "\n\nDiferença entre MJ701CAP e MJ702CAP: 0,76 L/min [1]");
const COL_INLINE = "MJ701CAP: 40 psi -> 0,76 L/min [1]\nMJ702CAP: 40 psi -> 1,53 L/min [1]\nDiferença: 0,76 L/min [1]";
const col2 = gates(Q_COL, COL_BLOCO, EVCOL);
const col2p = gates(Q_COLP, COL_BLOCO, EVCOL);
confere("COL2 bloco: 40 psi -> 0,76 L/min sob MJ701CAP → association FAIL (em HEAD: tudo PASS)",
  col2.grounding && col2.association === "failed" && col2.comparison === "ok" && col2.kind === "association" &&
  col2p.association === "failed" && col2p.kind === "association",
  `${col2.resumo} | pct: ${col2p.resumo}`);
const col3 = gates(Q_COL, COL_INLINE, EVCOL);
const col3p = gates(Q_COLP, COL_INLINE, EVCOL);
confere("COL3 inline: 'MJ701CAP: 40 psi -> 0,76 L/min' → association FAIL (em HEAD: tudo PASS)",
  col3.grounding && col3.association === "failed" && col3.comparison === "ok" && col3.kind === "association" &&
  col3p.association === "failed" && col3p.kind === "association",
  `${col3.resumo} | pct: ${col3p.resumo}`);

// COL4–COL6 — a frase de cálculo continua liberada
const col4 = gates(Q_COL, `${BLC_OK}\n\nDiferença entre MJ701CAP e MJ702CAP: 0,76 L/min [1]`, EVCOL);
confere("COL4 blocos certos + 'Diferença entre MJ701CAP e MJ702CAP: 0,76 L/min [1]' → PASSA", col4.ok, col4.resumo);
const col5 = gates(Q_COLP, `${BLC_OK}\n\nVariação percentual entre MJ701CAP e MJ702CAP: ${PCT_COL} [1]`, EVCOL);
confere(`COL5 blocos certos + 'Variação percentual entre MJ701CAP e MJ702CAP: ${PCT_COL} [1]' → PASSA`, col5.ok, col5.resumo);
const col6 = gates(Q_COLP, `${BLC_OK}\n\nA diferença entre MJ701CAP e MJ702CAP a 40 psi é de 0,76 L/min e a MJ702CAP entrega ${PCT_COL} a mais [1].`, EVCOL);
confere("COL6 frase natural (diferença a 40 psi + percentual 'a mais') → PASSA — e só passa porque o derivado sai dela",
  col6.ok && col6.checked === 2 &&
  EX.checkAssociation(Q_COLP, `A diferença entre MJ701CAP e MJ702CAP a 40 psi é de 0,76 L/min e a MJ702CAP entrega ${PCT_COL} a mais`, EVCOL, []).status === "failed",
  col6.resumo);

// COL7 — 0,76 onde ele É documental. A pergunta fixa 40 psi, então a linha
// de 50 psi vai como linha EXTRA no bloco da MJ701CAP, ao lado da de 40 psi
// (uma pergunta sem ponto fixado daria duas vazões para a MJ701CAP e
// nenhuma diferença — não haveria colisão para provar).
const col7 = gates(Q_COL, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 50 psi -> 0,76 L/min [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nDiferença entre MJ701CAP e MJ702CAP: 0,76 L/min [1]`, EVCOL);
confere("COL7 MJ701CAP '- 50 psi -> 0,76 L/min' (linha verdadeira) + diferença 0,76 → PASSA, e a linha de 50 psi é conferida (checked=3)",
  col7.ok && col7.checked === 3, col7.resumo);

// COL8 — 0,76 na pressão errada, noutra grafia de pressão
const col8 = gates(Q_COL, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 2,76 bar -> 0,76 L/min [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nDiferença entre MJ701CAP e MJ702CAP: 0,76 L/min [1]`, EVCOL);
confere("COL8 MJ701CAP '2,76 bar -> 0,76 L/min' (0,76 é de 3,45 bar) → association FAIL",
  col8.grounding && col8.association === "failed" && col8.kind === "association", col8.resumo);

// COL9 — frase de cálculo certa + par documental errado na MESMA frase
const col9 = gates(Q_COLP, `${BLC_OK}\n\nA diferença entre MJ701CAP e MJ702CAP é de 0,76 L/min, e a MJ701CAP entrega 0,77 L/min a 50 psi [1].`, EVCOL);
confere("COL9 'diferença … 0,76 L/min, e a MJ701CAP entrega 0,77 L/min a 50 psi' → FAIL (só o derivado sai; o par errado fica)",
  col9.grounding && !col9.ok && col9.association === "failed", col9.resumo);
// COL9b — a colisão DENTRO da frase de cálculo. Era o limite que sobrou do
// primeiro conserto: `semDerivados` tirava o literal em todas as ocorrências,
// e a segunda cópia do 0,76 — afirmação documental na pressão errada — saía
// junto. Agora cada literal sai UMA vez por item; a segunda fica e é
// conferida contra a linha da MJ701CAP a 40 psi, que traz 0,77.
const col9b = gates(Q_COLP, `${BLC_OK}\n\nA diferença é de 0,76 L/min e a MJ701CAP entrega 0,76 L/min a 40 psi [1].`, EVCOL);
confere("COL9b colisão DENTRO da frase de cálculo: o derivado sai uma vez, a 2ª cópia (0,76 a 40 psi na MJ701CAP) fica → association FAIL",
  col9b.grounding && col9b.association === "failed" && col9b.kind === "association", col9b.resumo);
// COL9c — o preço aceito da regra "uma vez só": frase honesta que repete a
// diferença E carrega outro número documental. A 2ª cópia do 0,76 fica ao
// lado de "40 psi", sem código no item e fora de bloco; com os códigos da
// pergunta como sujeito, nenhuma linha traz os dois, e o item não é julgado
// (regra conservadora de sempre para item sem dono). Resultado consciente:
// passa, e passa por ESSA regra — não porque o 0,76 repetido sumiu.
const COL9C = "A diferença a 40 psi é de 0,76 L/min, isto é, 0,76 L/min a mais [1].";
const col9c = gates(Q_COLP, `${BLC_OK}\n\n${COL9C}`, EVCOL);
const col9cDentro = gates(Q_COLP, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- A diferença a 40 psi é de 0,76 L/min, isto é, 0,76 L/min a mais [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]`, EVCOL);
confere("COL9c trade-off: diferença repetida + '40 psi' em parágrafo próprio → PASSA (item sem código nem bloco não é julgado, checked=2); dentro do bloco da MJ701CAP → FAIL fechado",
  col9c.ok && col9c.checked === 2 && col9cDentro.association === "failed" && col9cDentro.kind === "association",
  `${col9c.resumo} | no bloco: ${col9cDentro.resumo}`);

// COL10 — o literal sozinho, sem palavra de cálculo: nenhum bypass
// automático. Ele não é tirado (isDerivedStatement = false) e é julgado como
// qualquer item; como UM número sozinho não afirma relação, a associação não
// tem o que conferir e ele passa — pela regra de sempre, não pela exceção
// do derivado. O mesmo literal ao lado de uma pressão, dentro de bloco, é
// conferido e reprova.
const col10 = gates(Q_COL, `${BLC_OK}\n\n0,76 L/min [1]`, EVCOL);
const col10b = gates(Q_COL, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 0,76 L/min a 40 psi [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]`, EVCOL);
confere("COL10 '0,76 L/min [1]' solto: não é frase de cálculo, não é tirado; um número só não é relação → PASSA sem ser conferido (checked=2)",
  !EX.isDerivedStatement("0,76 L/min") && col10.ok && col10.checked === 2, col10.resumo);
confere("COL10b '- 0,76 L/min a 40 psi' dentro do bloco da MJ701CAP, sem palavra de cálculo → association FAIL",
  col10b.association === "failed" && col10b.kind === "association", col10b.resumo);

// COL11 — colisão de PERCENTUAL. "%" não é unidade de linha na associação
// (UNIDADES_DE_LINHA), mas o NÚMERO 98,7 entra na lista de números do item e
// tem de estar na mesma linha. Aqui 98,7% é valor documental da MJ701CAP a
// 50 psi (coluna sintética) e é também o percentual calculado.
const COL_TAB_PCT = [
  "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min L/ha EFIC.",
  LINHA("MJ701CAP", "02", "2,76", "40", "276", "0,77", "230 L/ha 97,1%"),
  LINHA("MJ701CAP", "02", "3,45", "50", "345", "0,86", "257 L/ha 98,7%"),
  LINHA("MJ702CAP", "04", "2,76", "40", "276", "1,53", "460 L/ha 99,0%"),
].join("\n");
const EVPCT = COL_EV(COL_TAB_PCT);
const planoPctCol = C.planComparison(Q_COLP, EVPCT);
confere("COL11a fixture: o percentual calculado (98,7%) é também valor documental da MJ701CAP a 50 psi",
  planoPctCol.derived.some((d) => d.tipo === "percentual" && d.texto === PCT_COL) &&
  COL_TAB_PCT.split("\n").some((l) => l.includes("MJ701CAP") && l.includes("50 psi") && l.includes(PCT_COL)),
  planoPctCol.derived.map((d) => d.texto).join(" · "));
const col11 = gates(Q_COLP, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min, ${PCT_COL} [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nVariação percentual entre MJ701CAP e MJ702CAP: ${PCT_COL} [1]`, EVPCT);
confere("COL11 '40 psi -> 0,77 L/min, 98,7%' (98,7% é da linha de 50 psi) → association FAIL: o percentual documental não some por colisão",
  col11.grounding && col11.association === "failed" && col11.kind === "association", col11.resumo);
const col11b = gates(Q_COLP, `MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 50 psi -> 0,86 L/min, ${PCT_COL} [1]\n\nMJ702CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nVariação percentual entre MJ701CAP e MJ702CAP: ${PCT_COL} [1]`, EVPCT);
confere("COL11b o mesmo 98,7% na linha certa (50 psi) + a variação percentual → PASSA",
  col11b.ok && col11b.checked === 3, col11b.resumo);

// COL12 — sem derivado, nada muda: listagem, par trocado reprova; a palavra
// de cálculo sozinha não tira nada (não há o que tirar)
const Q_COL_LISTA = "Quais as vazões da MJ701CAP?";
const col12 = gates(Q_COL_LISTA, "Vazões da MJ701CAP [1]:\n- 40 psi -> 0,76 L/min [1]\n- 50 psi -> 0,77 L/min [1]", EVCOL);
const col12b = gates(Q_COL_LISTA, "Vazões da MJ701CAP [1]:\n- 40 psi -> 0,77 L/min [1]\n- 50 psi -> 0,76 L/min [1]", EVCOL);
confere("COL12 listagem sem derivados: pares trocados → association FAIL; certos → PASSA",
  C.planComparison(Q_COL_LISTA, EVCOL).status === "not_applicable" &&
  col12.association === "failed" && col12.kind === "association" && col12b.ok,
  `${col12.resumo} | ${col12b.resumo}`);
confere("COL12b sem derivados, nem frase com 'diferença' perde número",
  EX.checkAssociation(Q_COL_LISTA, "Diferença: MJ701CAP 40 psi -> 0,76 L/min", EVCOL, []).status === "failed");

// isDerivedStatement — a fronteira, isolada
const DERIV_SIM = ["Diferença: 0,76 L/min", "Variação percentual entre X e Y: 98,7%", "A MJ985CAP entrega 98,7% a mais",
  "98,7 por cento", "A DIFERENCA é 0,76 L/min", "entrega 0,76 L/min a menos", "As diferenças são 0,76 L/min e 98,7%"];
const DERIV_NAO = ["- 40 psi -> 0,76 L/min", "MJ981CAP: 40 psi -> 0,76 L/min", "MJ981CAP a 40 psi", "0,76 L/min",
  "A MJ985CAP tem maior vazão", "mais de 0,76 L/min a 40 psi", "40 psi -> 0,76 L/min (máximo)"];
confere("COL-D1 isDerivedStatement reconhece as frases de cálculo (sem acento e sem caixa)",
  DERIV_SIM.every((t) => EX.isDerivedStatement(t)), DERIV_SIM.filter((t) => !EX.isDerivedStatement(t)).join(" | ") || `${DERIV_SIM.length}/${DERIV_SIM.length}`);
confere("COL-D2 e NÃO reconhece linha de tabela, cabeçalho nem valor solto",
  DERIV_NAO.every((t) => !EX.isDerivedStatement(t)), DERIV_NAO.filter((t) => EX.isDerivedStatement(t)).join(" | ") || `${DERIV_NAO.length}/${DERIV_NAO.length}`);

// As formas reais do provedor seguem passando (DA1/DA1b/PB12/PB12b/H18 acima
// já rodaram com o conserto); aqui, as mesmas, lado a lado, no fixture sintético.
const colReal = gates(Q_COLP, `${BLC_OK}\n\nA diferença entre as duas é de 0,76 L/min, e a MJ702CAP entrega ${PCT_COL} a mais que a MJ701CAP a 40 psi [1].`, EVCOL);
confere("COL-R forma bruta do provedor (RUN 2 de 25/09) no fixture com colisão → PASSA",
  colReal.ok && da1.ok && da1b.ok && pb12.ok && pb12b.ok && h18.ok, colReal.resumo);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Matriz adversarial (ADV, 25/09)\n");
//
// Trinta classes de falha, cada uma apontada para ONDE já está provada. Só
// ganha asserção nova a classe que faltava ou estava coberta pela metade
// (formato não exercitado ponta a ponta). Nada aqui é fuzz: cada caso é uma
// forma que um provedor pode escrever.
//
//   classe                                         onde está provada
//   ─────────────────────────────────────────────  ─────────────────────────────────────────────
//   ADV1  número inexistente                       answer N2, R2, I1 · comparison C3
//   ADV2  unidade errada                           answer N6, R6, I2
//   ADV3  vírgula/ponto trocado                    answer N3, R3, L8b, L8d · comparison T4b
//   ADV4  código de outro produto                  answer N8, R5, I3, G8b (código fora da evidência)
//                                                  + NOVO ADV4 (código que EXISTE na evidência, valor alheio)
//                                                  + NOVO ADV4-LIMIT (fato verdadeiro do produto errado)
//   ADV5  valor existente, produto errado          answer P6c, L7c · comparison C2, C14, PB2
//   ADV6  pressão de uma linha + vazão de outra    answer P2c, P3, P6b · comparison DA7, GAP3
//   ADV7  derived collision                        comparison COL1, COL2, COL3
//   ADV8  collision dentro de frase de cálculo     comparison COL9b
//   ADV9  header simples                           comparison PB2, PB4, PB-CRÍTICO
//                                                  + NOVO ADV9b (**negrito** ponta a ponta; PB0 só lia o cabeçalho)
//   ADV10 header pinned                            comparison H4, H5, HDR-CRÍTICO
//                                                  + NOVO ADV10b ('@ 40 psi' ponta a ponta; H13 só lia o cabeçalho)
//   ADV11 header com prosa inválida                comparison H7–H12, PB0b, PB6, PB7 (a prosa NÃO vira cabeçalho)
//                                                  + NOVO ADV11-GAP (a consequência: troca de produto passa)
//   ADV12 context bleed entre 3 produtos           comparison PB11b, PB11c, H17
//   ADV13 citação inexistente                      answer D4, E3 · comparison T6b · synthesis SYN28
//   ADV14 parágrafo factual sem citação            answer N11, I4 · comparison T2, T2b, T3
//   ADV15 duas evidências, citação cruzada         answer N13 · comparison P5, P14, T6
//   ADV16 UUID                                     answer D6, E6 · synthesis SYN29
//   ADV17 SHA                                      answer D7
//   ADV18 storage path                             answer D8
//   ADV19 URL                                      answer D9, E7 · synthesis SYN30
//   ADV20 resposta > limite                        answer D5, E5
//   ADV21 modelo vazio                             answer D2, E4
//   ADV22 comparação incompleta                    comparison C4c, C15, C15b, P13, DA10 · synthesis SYN16a–SYN18
//   ADV23 comparação > limite de códigos           comparison C13, C13b · synthesis SYN15, SYN15b
//   ADV24 lista incompleta                         answer L6b, L12b, P5 · synthesis SYN12
//   ADV25 lista com linha de outro código          answer L7c, L12c
//   ADV26 dois pontos de tabela no mesmo item      answer P8c (lista) + NOVO ADV26b (bloco de comparação)
//   ADV27 percentual não pedido                    comparison C11, C11b
//   ADV28 percentual errado                        comparison DA4, T4b
//   ADV29 maior/menor invertido                    comparison P8, P9, DA13, PB5b, H19
//   ADV30 empate apontando vencedor                comparison P11
//
// Formatos: inline (PB16, COL3), bloco (PB*), [1] (todos), '->' (todos),
// 'a 40 psi' (H3–H5), texto natural (DA6b, COL9), lista (answer L*) já
// estavam ponta a ponta. Novos aqui: **negrito**, '@ 40 psi', [1][2] no
// cabeçalho, espaços extras e CRLF.

// ADV4 — o código escrito EXISTE na evidência (MJ982CAP está na p. 20), então
// o grounding aceita; o valor é da MJ981CAP. Quem barra é a associação.
const Q_PONTUAL = "Qual a vazão da MJ981CAP a 40 psi?";
const adv4 = gates(Q_PONTUAL, "A MJ982CAP entrega 0,77 L/min a 40 psi [1].");
confere("ADV4  código de outro produto que EXISTE na evidência, com o valor da MJ981CAP → grounding PASS, association FAIL",
  adv4.grounding && adv4.association === "failed" && adv4.kind === "association", adv4.resumo);
// ADV4-LIMIT — registro, não conserto. Perguntou pela MJ981CAP e a resposta
// fala só da MJ982CAP, com o valor CERTO dela. Nada do que está escrito é
// falso nem sem lastro — é resposta fora do assunto. Os gates provam
// verdade e vínculo, não pertinência; exigir que a resposta cite o código da
// pergunta é outra regra, e fica como fronteira conhecida.
const adv4l = gates(Q_PONTUAL, "A MJ982CAP entrega 0,96 L/min a 40 psi [1].");
confere("ADV4-LIMIT fato verdadeiro de OUTRO produto na pergunta pontual → PASSA (fronteira registrada: pertinência não é conferida)",
  adv4l.ok && adv4l.association === "ok" && adv4l.checked === 1, adv4l.resumo);

// ADV9b / ADV10b — os dois cabeçalhos que só tinham prova unitária
const adv9 = gates(Q_PB, "**MJ981CAP** [1]:\n- 40 psi -> 1,53 L/min [1]\n\n**MJ985CAP** [1]:\n- 40 psi -> 0,77 L/min [1]");
const adv9ok = gates(Q_PB, "**MJ981CAP** [1]:\n- 40 psi -> 0,77 L/min [1]\n\n**MJ985CAP** [1]:\n- 40 psi -> 1,53 L/min [1]");
confere("ADV9b cabeçalho **negrito**: troca → association e comparison FAIL; certo → PASSA (2 conferidas)",
  !adv9.ok && adv9.association === "failed" && adv9.comparison === "failed" && adv9ok.ok && adv9ok.checked === 2,
  `${adv9.resumo} | certo: ${adv9ok.resumo}`);
const adv10 = gates(Q_PB, "MJ981CAP @ 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]\n\nMJ985CAP @ 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]");
const adv10ok = gates(Q_PB, "MJ981CAP @ 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]\n\nMJ985CAP @ 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]");
confere("ADV10b cabeçalho 'X @ 40 psi [1]:': troca → association e comparison FAIL; certo → PASSA (2 conferidas)",
  !adv10.ok && adv10.association === "failed" && adv10.comparison === "failed" && adv10ok.ok && adv10ok.checked === 2,
  `${adv10.resumo} | certo: ${adv10ok.resumo}`);

// ADV11-GAP — MEDIDO em 25/09, não suposto. A gramática fechada do cabeçalho
// (H7–H12) está certa em não dar contexto à prosa; a consequência é que as
// linhas de valor debaixo de "Para MJ981CAP a 40 psi [1]:" ficam SEM DONO
// (checked=0), e a comparação só julga item com um código — que aqui é o
// próprio cabeçalho, com "40 psi", valor que a MJ981CAP de fato tem. A troca
// passa em todos os gates. É o buraco do GAP1–GAP3 por outra porta.
// Não foi fechado nesta rodada porque fechar é decidir gramática (alargar o
// cabeçalho, ou reprovar valor órfão numa comparação — o que muda o PB15);
// fica registrado para a auditoria. Quando for fechado, estas asserções
// INVERTEM, como aconteceu com o GAP1–GAP3.
const adv11a = gates(Q_PB, "Para MJ981CAP a 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]\n\nPara MJ985CAP a 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]");
const adv11b = gates(Q_PB, "Sobre a MJ981CAP [1]:\n- 40 psi -> 1,53 L/min [1]\n\nSobre a MJ985CAP [1]:\n- 40 psi -> 0,77 L/min [1]");
confere("ADV11-GAP troca de produtos sob cabeçalho em PROSA ('Para X a 40 psi:', 'Sobre a X:') → PASSA em todos os gates, nenhuma linha de valor conferida (buraco registrado)",
  adv11a.grounding && adv11a.association === "ok" && adv11a.checked === 0 && adv11a.comparison === "ok" && adv11a.ok &&
  adv11b.ok && adv11b.checked === 0,
  `${adv11a.resumo} | ${adv11b.resumo}`);

// ADV26b — dois pontos da tabela no mesmo item, agora dentro do bloco de
// comparação (P8c provava na lista). Os dois pares existem na linha da
// MJ981CAP, cada um na sua; juntos no item, não há uma linha que prove.
const adv26 = gates(Q_PB, BL("40 psi -> 0,77 L/min e 50 psi -> 0,86 L/min", "40 psi -> 1,53 L/min"));
const adv26x = gates(Q_PB, BL("40 psi -> 0,86 L/min e 50 psi -> 0,77 L/min", "40 psi -> 1,53 L/min"));
confere("ADV26b dois pontos no mesmo item do bloco (certos ou cruzados) → association FAIL: não dá para provar a relação",
  adv26.grounding && adv26.association === "failed" && adv26.kind === "association" && adv26x.kind === "association",
  `${adv26.resumo} | cruzado: ${adv26x.resumo}`);

// Referência dupla no cabeçalho, ponta a ponta (PB9 só lia o cabeçalho).
// EVD: MJ981CAP só em [1], MJ985CAP só em [2]; citar as duas satisfaz o
// grounding, e o vínculo produto → valor continua sendo conferido.
const advRef = gates(Q_PB, "MJ981CAP [1][2]:\n- 40 psi -> 1,53 L/min [1][2]\n\nMJ985CAP [1][2]:\n- 40 psi -> 0,77 L/min [1][2]", EVD);
const advRefOk = gates(Q_PB, "MJ981CAP [1][2]:\n- 40 psi -> 0,77 L/min [1][2]\n\nMJ985CAP [1][2]:\n- 40 psi -> 1,53 L/min [1][2]", EVD);
confere("ADV-REF cabeçalho '[1][2]' com duas evidências: troca → grounding PASS, association e comparison FAIL; certo → PASSA",
  advRef.grounding && advRef.association === "failed" && advRef.comparison === "failed" && advRefOk.ok,
  `${advRef.resumo} | certo: ${advRefOk.resumo}`);

// Espaços extras em tudo: cabeçalho, marcador, número, unidade, seta.
const advSp = gates(Q_PB, "MJ981CAP   [1] :\n-    40  psi   ->   1,53  L/min   [1]\n\n  MJ985CAP  [1]:\n-  40 psi  ->  0,77 L/min [1]");
const advSpOk = gates(Q_PB, "MJ981CAP   [1] :\n-    40  psi   ->   0,77  L/min   [1]\n\n  MJ985CAP  [1]:\n-  40 psi  ->  1,53 L/min [1]");
confere("ADV-SP espaços extras: o cabeçalho continua cabeçalho — troca FAIL (association e comparison), certo PASSA",
  !advSp.ok && advSp.association === "failed" && advSp.comparison === "failed" && advSpOk.ok && advSpOk.checked === 2,
  `${advSp.resumo} | certo: ${advSpOk.resumo}`);

// CRLF — um provedor (ou um proxy) pode devolver "\r\n". Se alguma quebra
// lesse "\r" como conteúdo, o cabeçalho "MJ981CAP [1]:\r" deixaria de ser
// cabeçalho e a linha em branco "\r" deixaria de encerrar o bloco — o mesmo
// buraco do PB, só que invisível na tela. A prova é de EQUIVALÊNCIA: gate a
// gate, o resultado em CRLF é idêntico ao em LF, e o esperado é o de sempre.
const crlf = (t) => t.replace(/\n/g, "\r\n");
const lfCrlf = (q, t, evs = EV) => {
  const lf = gates(q, t, evs);
  const cr = gates(q, crlf(t), evs);
  return { lf, cr, igual: lf.resumo === cr.resumo };
};
const bindOk = lfCrlf(Q_PB, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min"));
const bindSwap = lfCrlf(Q_PB, BL("40 psi -> 1,53 L/min", "40 psi -> 0,77 L/min"));
confere("ADV-CRLF1 product binding em bloco: CRLF ≡ LF gate a gate — certo PASSA (2 conferidas), troca FAIL em association e comparison",
  bindOk.igual && bindSwap.igual && bindOk.cr.ok && bindOk.cr.checked === 2 &&
  !bindSwap.cr.ok && bindSwap.cr.association === "failed" && bindSwap.cr.comparison === "failed",
  `CRLF certo: ${bindOk.cr.resumo} | CRLF troca: ${bindSwap.cr.resumo}`);
const derivOk = lfCrlf(Q_DA, BL("40 psi -> 0,77 L/min", "40 psi -> 1,53 L/min", "\n\nDiferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1]\nVariação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]"));
const derivCol = lfCrlf(Q_COL, COL_BLOCO, EVCOL);
const derivCol9b = lfCrlf(Q_COLP, `${BLC_OK}\n\nA diferença é de 0,76 L/min e a MJ701CAP entrega 0,76 L/min a 40 psi [1].`, EVCOL);
confere("ADV-CRLF2 derivado: CRLF ≡ LF — legítimo PASSA; colisão derivado × documental (COL2) e colisão na frase de cálculo (COL9b) FAIL association",
  derivOk.igual && derivCol.igual && derivCol9b.igual &&
  derivOk.cr.ok && derivCol.cr.kind === "association" && derivCol9b.cr.kind === "association",
  `CRLF legítimo: ${derivOk.cr.resumo} | CRLF COL2: ${derivCol.cr.resumo} | CRLF COL9b: ${derivCol9b.cr.resumo}`);
const crlfResto = [
  ["pinned", lfCrlf(Q_PB, "MJ981CAP a 40 psi [1]:\n- 40 psi -> 1,53 L/min [1]\n\nMJ985CAP a 40 psi [1]:\n- 40 psi -> 0,77 L/min [1]"), (g) => g.kind === "association"],
  ["3 produtos", lfCrlf(Q_3, TRES("0,77 L/min", "1,53 L/min", "0,96 L/min")), (g) => g.association === "failed"],
  ["parágrafo sem citação", lfCrlf(Q_H, `${BLOCOS}\n\nA MJ985CAP tem maior vazão a 40 psi. A diferença é de 0,76 L/min (98,7%).`), (g) => g.kind === "grounding"],
];
confere("ADV-CRLF3 CRLF ≡ LF também no cabeçalho com ponto fixado, no bleed entre 3 produtos e no parágrafo sem citação (a quebra dupla '\\r\\n\\r\\n' separa parágrafo)",
  crlfResto.every(([, r, esperado]) => r.igual && esperado(r.cr)),
  crlfResto.map(([n, r]) => `${n}: ${r.cr.resumo}`).join(" | "));

rmSync(destino, { recursive: true, force: true });
process.stdout.write(falhas === 0 ? "✔ comparação entre códigos\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
