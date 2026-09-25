/**
 * Confere a MÁQUINA DE ESTADOS da síntese (`synthesis.ts`), de ponta a ponta.
 *
 *   node --experimental-strip-types supabase/db-tests/check-brain-synthesis.mjs
 *
 * Por que existe: as outras suítes provam cada peça sozinha — Evidence Gate,
 * gate externo, validador, comparação. Nenhuma provava a ORDEM em que
 * `answerWith` as encadeia, nem quem é chamado em cada caminho. E é a ordem
 * que decide se um documento proibido sai daqui, se o provedor é chamado à
 * toa, e o que a tela recebe quando algo recusa.
 *
 * Sem banco, sem rede, sem chave: busca, política e provedor são falsos, e
 * cada um conta as próprias chamadas. O provedor falso guarda a entrada
 * exata, para provar que só a evidência aceita sai — e sem id, caminho ou
 * hash. O `console.info` é capturado para conferir a linha
 * `[brain.synthesis]` de cada caminho.
 *
 * SYN16–SYN18 reproduzem uma lacuna conhecida (comparação incompleta ainda
 * chama o provedor). Afirmam o comportamento de HOJE, com o rótulo "GAP",
 * para o commit que a fechar ter de virar a asserção de propósito.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "evidence.ts": "src/modules/brain/evidence.ts",
  "limits.ts": "src/modules/brain/limits.ts",
  "answer.ts": "src/modules/brain/answer.ts",
  "prompt.ts": "src/modules/brain/prompt.ts",
  "external-processing.ts": "src/modules/brain/external-processing.ts",
  "grounding.ts": "src/modules/brain/grounding.ts",
  "exhaustiveness.ts": "src/modules/brain/exhaustiveness.ts",
  "comparison.ts": "src/modules/brain/comparison.ts",
  "provider.ts": "src/modules/brain/llm/provider.ts",
  "synthesis.ts": "src/modules/brain/synthesis.ts",
};

const destino = mkdtempSync(join(RAIZ, ".synthesis-check-"));
let falhas = 0;
try {
  for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
    const fonte = readFileSync(join(RAIZ, caminho), "utf8")
      // Sem bundler aqui, `server-only` só quebraria o import; a garantia
      // continua valendo no build de verdade, que roda no CI.
      .replace(/^import "server-only";\n\n?/m, "")
      .replace(/^import type \{ Json \} from "@\/types\/db";$/m, "type Json = unknown;")
      .replace(/from "\.\.\/evidence"/g, 'from "./evidence.ts"')
      .replace(/from "\.\/evidence"/g, 'from "./evidence.ts"')
      .replace(/from "\.\/limits"/g, 'from "./limits.ts"')
      .replace(/from "\.\/provider"/g, 'from "./provider.ts"')
      .replace(/from "\.\/llm\/provider"/g, 'from "./provider.ts"')
      .replace(/from "\.\/grounding"/g, 'from "./grounding.ts"')
      .replace(/from "\.\/exhaustiveness"/g, 'from "./exhaustiveness.ts"')
      .replace(/from "\.\/comparison"/g, 'from "./comparison.ts"')
      .replace(/from "\.\/answer"/g, 'from "./answer.ts"')
      .replace(/from "\.\/prompt"/g, 'from "./prompt.ts"')
      .replace(/from "\.\/external-processing"/g, 'from "./external-processing.ts"')
      // As portas reais (Supabase e SDK) viram stubs que EXPLODEM: se
      // `answerWith` usar qualquer coisa fora de `deps`, o teste cai aqui.
      .replace(/from "\.\/llm"/g, 'from "./llm-stub.ts"')
      .replace(/from "\.\/repository"/g, 'from "./repository-stub.ts"');
    writeFileSync(join(destino, nome), fonte);
  }
  writeFileSync(join(destino, "llm-stub.ts"),
    'export function resolveProvider(): never { throw new Error("resolveProvider real chamado"); }\n');
  writeFileSync(join(destino, "repository-stub.ts"), [
    'export async function search(): Promise<never> { throw new Error("search real chamado"); }',
    'export async function externalProcessing(): Promise<never> { throw new Error("externalProcessing real chamado"); }',
    "",
  ].join("\n"));

  const imp = (n) => import(pathToFileURL(join(destino, n)).href);
  const S = await imp("synthesis.ts");
  const A = await imp("answer.ts");
  const C = await imp("comparison.ts");
  const P = await imp("prompt.ts");
  const L = await imp("limits.ts");
  const E = await imp("evidence.ts");
  const { ProviderError } = await imp("provider.ts");

  await suite({ S, A, C, P, L, E, ProviderError });
} catch (erro) {
  falhas += 1;
  process.stdout.write(`  ✗ erro inesperado: ${erro?.stack ?? erro}\n`);
} finally {
  rmSync(destino, { recursive: true, force: true });
}
process.stdout.write(falhas === 0 ? "✔ máquina de estados da síntese\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);

async function suite({ S, A, C, P, L, E, ProviderError }) {
  const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
  const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };
  const confere = (t, c, d = "") => (c ? ok(`${t}${d ? ` — ${d}` : ""}`) : nao(`${t}${d ? ` — ${d}` : ""}`));

  // ── fixture real ────────────────────────────────────────────
  // Linhas do trecho 72 (Catálogo Magnojet V41, p. 20), as mesmas de
  // check-brain-answer.mjs (L1–L12), mais as três linhas da MJ985CAP de
  // check-brain-comparison.mjs — a comparação precisa do outro lado.
  const LINHAS_P20 = [
    "LITROS POR HECTARE (ESPAÇAMENTO 50CM)",
    "CÓDIGO PONTAS GOTAS BAR PSI kPa L/min 4 km/h 5 km/h 6 km/h 7 km/h 8 km/h 9 km/h 10 km/h 12 km/h 14 km/h 16 km/h 18 km/h 20 km/h 25 km/h",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 2,07 bar 30 psi 207 kPa 0,5 L/min 149 L/ha 120 L/ha 100 L/ha 85 L/ha 75 L/ha 66 L/ha 60 L/ha 50 L/ha 43 L/ha 37 L/ha 33 L/ha 30 L/ha 24 L/ha",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 2,76 bar 40 psi 276 kPa 0,58 L/min 173 L/ha 138 L/ha 115 L/ha 99 L/ha 86 L/ha 77 L/ha 69 L/ha 58 L/ha 49 L/ha 43 L/ha 38 L/ha 35 L/ha 28 L/ha",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 3,45 bar 50 psi 345 kPa 0,64 L/min 193 L/ha 154 L/ha 129 L/ha 110 L/ha 96 L/ha 86 L/ha 77 L/ha 64 L/ha 55 L/ha 48 L/ha 43 L/ha 39 L/ha 31 L/ha",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 4,14 bar 60 psi 414 kPa 0,7 L/min 211 L/ha 169 L/ha 141 L/ha 121 L/ha 106 L/ha 94 L/ha 85 L/ha 70 L/ha 60 L/ha 53 L/ha 47 L/ha 42 L/ha 34 L/ha",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 4,83 bar 70 psi 483 kPa 0,76 L/min 228 L/ha 183 L/ha 152 L/ha 130 L/ha 114 L/ha 101 L/ha 91 L/ha 76 L/ha 65 L/ha 57 L/ha 51 L/ha 46 L/ha 37 L/ha",
    "MJ980CAP MUG-CV 015 MALHA 50 UG 5,52 bar 80 psi 552 kPa 0,81 L/min 244 L/ha 195 L/ha 163 L/ha 139 L/ha 122 L/ha 108 L/ha 98 L/ha 81 L/ha 70 L/ha 61 L/ha 54 L/ha 49 L/ha 39 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 2,07 bar 30 psi 207 kPa 0,66 L/min 199 L/ha 159 L/ha 133 L/ha 114 L/ha 100 L/ha 89 L/ha 80 L/ha 66 L/ha 57 L/ha 50 L/ha 44 L/ha 40 L/ha 32 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 2,76 bar 40 psi 276 kPa 0,77 L/min 230 L/ha 184 L/ha 153 L/ha 131 L/ha 115 L/ha 102 L/ha 92 L/ha 77 L/ha 66 L/ha 58 L/ha 51 L/ha 46 L/ha 37 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 3,45 bar 50 psi 345 kPa 0,86 L/min 257 L/ha 206 L/ha 172 L/ha 147 L/ha 129 L/ha 114 L/ha 103 L/ha 86 L/ha 74 L/ha 64 L/ha 57 L/ha 51 L/ha 41 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 4,14 bar 60 psi 414 kPa 0,94 L/min 282 L/ha 225 L/ha 188 L/ha 161 L/ha 141 L/ha 125 L/ha 113 L/ha 94 L/ha 81 L/ha 70 L/ha 63 L/ha 56 L/ha 45 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 4,83 bar 70 psi 483 kPa 1,01 L/min 304 L/ha 244 L/ha 203 L/ha 174 L/ha 152 L/ha 135 L/ha 122 L/ha 101 L/ha 87 L/ha 76 L/ha 68 L/ha 61 L/ha 49 L/ha",
    "MJ981CAP MUG-CV 02 MALHA 50 UG 5,52 bar 80 psi 552 kPa 1,08 L/min 325 L/ha 260 L/ha 217 L/ha 186 L/ha 163 L/ha 145 L/ha 130 L/ha 108 L/ha 93 L/ha 81 L/ha 72 L/ha 65 L/ha 52 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 2,07 bar 30 psi 207 kPa 0,83 L/min 249 L/ha 199 L/ha 166 L/ha 142 L/ha 125 L/ha 111 L/ha 100 L/ha 83 L/ha 71 L/ha 62 L/ha 55 L/ha 50 L/ha 40 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 2,76 bar 40 psi 276 kPa 0,96 L/min 288 L/ha 230 L/ha 192 L/ha 164 L/ha 144 L/ha 128 L/ha 115 L/ha 96 L/ha 82 L/ha 72 L/ha 64 L/ha 58 L/ha 46 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 3,45 bar 50 psi 345 kPa 1,07 L/min 322 L/ha 257 L/ha 214 L/ha 184 L/ha 161 L/ha 143 L/ha 129 L/ha 107 L/ha 92 L/ha 80 L/ha 71 L/ha 64 L/ha 51 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 4,14 bar 60 psi 414 kPa 1,17 L/min 352 L/ha 282 L/ha 235 L/ha 201 L/ha 176 L/ha 157 L/ha 141 L/ha 117 L/ha 101 L/ha 88 L/ha 78 L/ha 70 L/ha 56 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 4,83 bar 70 psi 483 kPa 1,27 L/min 381 L/ha 304 L/ha 254 L/ha 217 L/ha 190 L/ha 169 L/ha 152 L/ha 127 L/ha 109 L/ha 95 L/ha 85 L/ha 76 L/ha 61 L/ha",
    "MJ982CAP MUG-CV 025 MALHA 50 UG 5,52 bar 80 psi 552 kPa 1,36 L/min 407 L/ha 325 L/ha 271 L/ha 232 L/ha 203 L/ha 181 L/ha 163 L/ha 136 L/ha 116 L/ha 102 L/ha 90 L/ha 81 L/ha 65 L/ha",
    "MJ985CAP MUG-CV 04 MALHA 50 UG 2,07 bar 30 psi 207 kPa 1,33 L/min 399 L/ha 319 L/ha 266 L/ha",
    "MJ985CAP MUG-CV 04 MALHA 50 UG 2,76 bar 40 psi 276 kPa 1,53 L/min 460 L/ha 368 L/ha 307 L/ha",
    "MJ985CAP MUG-CV 04 MALHA 50 UG 3,45 bar 50 psi 345 kPa 1,72 L/min 515 L/ha 412 L/ha 343 L/ha",
  ];
  const P20 = LINHAS_P20.join("\n");
  const ARAG_CONTEUDO = "SISTEMA PARA BICOS HIDRAULICOS\n1 SENSOR PRESSAO 466113200 12V 0,5AH 4-20MAH 0-20 BAR 1098 1098";

  // Os campos que NUNCA podem sair: estão na linha crua de propósito, para
  // o teste provar que não chegam nem à mensagem do provedor nem ao log.
  const DOC_MAG = "3f2b9c1e-8a4d-4e6f-9b1a-7c5d2e8f0a11";
  const VER_MAG = "9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a";
  const DOC_ARAG = "b1c2d3e4-f5a6-4b7c-8d9e-0f1a2b3c4d5e";
  const VER_ARAG = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";
  const SHA_MAG = "4e1f9a7c2b3d5e6f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7";
  const SHA_ARAG = "c0ffee00deadbeef0123456789abcdef0123456789abcdef0123456789abcdef";
  const PATH_MAG = `magnojet/catalogo-magnojet/v41/${SHA_MAG.slice(0, 16)}.pdf`;
  const PATH_ARAG = `agrotork_interno/orcamento-arag/2024-10/${SHA_ARAG.slice(0, 16)}.pdf`;
  const SEGREDOS = [DOC_MAG, VER_MAG, DOC_ARAG, VER_ARAG, SHA_MAG, SHA_ARAG, PATH_MAG, PATH_ARAG];
  const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

  const linha = (over = {}) => ({
    chunk_id: 72, score: 0.91, rank_exact: 1, rank_trgm: null, rank_fts: 3,
    kind: "table", content: P20, table_data: null, page_from: 20, page_to: 20,
    heading_path: ["MAGNO ULTRA GROSSA", "CONE VAZIO"],
    codes: ["MJ980CAP", "MJ981CAP", "MJ982CAP", "MJ985CAP", "MUG-CV015", "MUG-CV02"],
    version_id: VER_MAG, version_label: "V41", version_status: "active",
    document_id: DOC_MAG, title: "Catálogo Magnojet", document_type: "catalog",
    source_key: "magnojet", access_level: "public", storage_path: PATH_MAG, file_sha256: SHA_MAG,
    ...over,
  });
  const MAG = linha();
  const ARAG = linha({
    chunk_id: 90, kind: "price_table", content: ARAG_CONTEUDO, page_from: 1, page_to: 1,
    heading_path: [], codes: ["466113200"], version_id: VER_ARAG, version_label: "2024-10",
    document_id: DOC_ARAG, title: "Orçamento interno — sistemas ARAG para bicos", document_type: "quote",
    source_key: "agrotork_interno", access_level: "commercial", storage_path: PATH_ARAG, file_sha256: SHA_ARAG,
  });
  // Uma evidência que passa em tudo MENOS no teto por evidência.
  const GRANDE_CONTEUDO = "MJ981CAP " + "x".repeat(L.MAX_CHARS_POR_EVIDENCIA);
  const GRANDE = linha({ chunk_id: 99, content: GRANDE_CONTEUDO, codes: ["MJ981CAP"] });

  // ── dublês ──────────────────────────────────────────────────
  /** Uma "chave" inventada: nunca pode aparecer em log nem em aviso. */
  const CHAVE_FALSA = "sk-ant-api03-CHAVE-DE-TESTE-QUE-NAO-EXISTE-0000000000";
  /** Corpo de erro como um provedor real devolve: repete chave e prompt. */
  const corpoDeErro = (tipo) =>
    `${tipo} 401 {"error":{"message":"invalid x-api-key ${CHAVE_FALSA}","echo":"${LINHAS_P20[9]}"}}`;

  /**
   * Provedor falso. `roteiro`: texto, função (input → texto) ou erro a lançar.
   * Guarda cada entrada, inteira — é por ela que se prova o que saiu.
   */
  function provedor(roteiro) {
    const p = {
      name: "fake", model: "fake-1", apiKey: CHAVE_FALSA, chamadas: [],
      async generate(input) {
        p.chamadas.push(input);
        if (roteiro instanceof Error) throw roteiro;
        const text = typeof roteiro === "function" ? roteiro(input) : roteiro;
        return { text, meta: { provider: "fake", model: "fake-1", durationMs: 7 } };
      },
    };
    return p;
  }

  const TODAS = [];   // todas as rodadas, para as conferências de log no fim

  /**
   * Uma consulta pela máquina de estados, com busca, política e provedor
   * falsos. `politicas`: { documentId: policy } — ausente = sem linha.
   */
  async function rodar({ pergunta, linhas = [MAG], politicas = { [DOC_MAG]: "allowed" }, prov = null, isAdmin = false, rotulo }) {
    const conta = { search: 0, externo: [], resolve: 0 };
    const deps = {
      search: async () => { conta.search += 1; return linhas; },
      externalProcessing: async (ids) => {
        conta.externo.push(ids);
        return new Map(Object.entries(politicas).filter(([id]) => ids.includes(id)));
      },
      resolveProvider: () => { conta.resolve += 1; return prov; },
    };
    const capturado = [];
    const original = console.info;
    console.info = (...args) => capturado.push(args);
    let r;
    try {
      r = await S.answerWith(deps, { query: pergunta, limit: 10, includeSuperseded: false, filters: {} }, { isAdmin });
    } finally {
      console.info = original;
    }
    const brutos = capturado.filter((a) => a[0] === "[brain.synthesis]").map((a) => a.slice(1).join(" "));
    const outros = capturado.filter((a) => a[0] !== "[brain.synthesis]");
    const rodada = {
      rotulo, pergunta, r, conta, prov, brutos, outros,
      log: brutos.length === 1 ? JSON.parse(brutos[0]) : null,
      chamadas: prov ? prov.chamadas.length : 0,
      entrada: prov?.chamadas[0] ?? null,
    };
    TODAS.push(rodada);
    return rodada;
  }

  const Q = "Qual a vazão da MJ981CAP a 40 psi?";
  const OK_PONTUAL = "A MJ981CAP entrega 0,77 L/min a 40 psi. [1]";
  const AVISO_GENERICO = "A resposta gerada não passou na conferência e foi descartada. Os trechos encontrados estão abaixo.";
  const AVISO_PROVEDOR = "Não consegui redigir a resposta agora. Os trechos encontrados estão abaixo.";
  const AVISO_SEM_PROVEDOR = "A síntese automática não está configurada neste ambiente. Os trechos encontrados estão abaixo.";
  const extractivaDe = (...rows) => A.extractiveAnswer(rows.map((x) => E.toEvidence(x, false)));

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Caminho feliz e retrieval vazio (SYN1–SYN3)\n");

  const s1 = await rodar({ rotulo: "SYN1", pergunta: Q, prov: provedor(OK_PONTUAL) });
  confere("SYN1  evidência liberada + texto citado válido → synthesized, provider chamado 1×",
    s1.r.status === "answered" && s1.r.mode === "synthesized" && s1.chamadas === 1 &&
    s1.r.answer === OK_PONTUAL && s1.r.comparison === undefined && s1.r.warning === undefined,
    `status=${s1.r.status} mode=${s1.r.mode} calls=${s1.chamadas}`);
  confere("SYN1b busca 1×, política 1× com o documento da evidência, resolveProvider 1×",
    s1.conta.search === 1 && s1.conta.externo.length === 1 &&
    s1.conta.externo[0].join() === DOC_MAG && s1.conta.resolve === 1);
  confere("SYN1c uma citação, a da evidência aceita, e a evidência segue na resposta",
    s1.r.citations?.length === 1 && s1.r.citations[0].label === "Magnojet — Catálogo Magnojet V41 · p. 20" &&
    s1.r.evidence.length === 1);

  const s2 = await rodar({ rotulo: "SYN2", pergunta: Q, linhas: [], prov: provedor(OK_PONTUAL) });
  confere("SYN2  busca devolve [] → no_evidence, mode none, provider 0, política 0",
    s2.r.status === "no_evidence" && s2.r.mode === "none" && s2.chamadas === 0 &&
    s2.conta.externo.length === 0 && s2.conta.resolve === 0 && s2.r.evidence.length === 0,
    `status=${s2.r.status} calls=${s2.chamadas} externo=${s2.conta.externo.length}`);
  confere("SYN2b recusa padrão, sem resposta e sem citação",
    s2.r.refusalReason === E.SEM_EVIDENCIA && s2.r.answer === undefined && s2.r.citations === undefined);

  const s3 = await rodar({ rotulo: "SYN3", pergunta: Q, linhas: [GRANDE], prov: provedor(OK_PONTUAL) });
  confere("SYN3  retrieval traz evidência, Evidence Gate recusa tudo (acima do teto) → no_evidence, provider 0",
    s3.r.status === "no_evidence" && s3.r.mode === "none" && s3.chamadas === 0 && s3.conta.externo.length === 0,
    s3.log?.outcome);
  confere("SYN3b a evidência recusada continua na resposta, para a pessoa julgar",
    s3.r.evidence.length === 1 && s3.r.evidence[0].chunkId === 99 &&
    s3.r.evidence[0].content.length === GRANDE_CONTEUDO.length);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Processamento externo (SYN4, SYN5)\n");

  const s4 = await rodar({ rotulo: "SYN4", pergunta: Q, politicas: { [DOC_MAG]: "forbidden" }, prov: provedor(OK_PONTUAL) });
  confere("SYN4  política forbidden → extractive, provider 0, resolveProvider nem é consultado",
    s4.r.status === "answered" && s4.r.mode === "extractive" && s4.chamadas === 0 && s4.conta.resolve === 0,
    `mode=${s4.r.mode} calls=${s4.chamadas} resolve=${s4.conta.resolve}`);
  confere("SYN4b a resposta é a extractiva padrão e o aviso é o do gate externo",
    s4.r.answer === extractivaDe(MAG) &&
    s4.r.warning === 'O documento "Catálogo Magnojet" não pode ser processado por um serviço externo. A consulta continua disponível, com os trechos na íntegra.',
    s4.r.warning);
  const s4c = await rodar({ rotulo: "SYN4c", pergunta: Q, politicas: {}, prov: provedor(OK_PONTUAL) });
  confere("SYN4c política AUSENTE é proibição → mesmo caminho, provider 0",
    s4c.r.mode === "extractive" && s4c.chamadas === 0 && s4c.log?.outcome === "external_processing_forbidden");

  const Q_MISTO = "Qual a vazão da MJ981CAP e o sensor 466113200?";
  const s5 = await rodar({
    rotulo: "SYN5", pergunta: Q_MISTO, linhas: [MAG, ARAG],
    politicas: { [DOC_MAG]: "allowed", [DOC_ARAG]: "forbidden" }, prov: provedor(OK_PONTUAL),
  });
  confere("SYN5  allowed + forbidden → o conjunto inteiro fica, provider 0",
    s5.r.mode === "extractive" && s5.chamadas === 0 && s5.r.citations?.length === 2 &&
    s5.conta.externo[0].join() === `${DOC_MAG},${DOC_ARAG}`,
    `mode=${s5.r.mode} calls=${s5.chamadas}`);
  confere("SYN5b o aviso nomeia só o documento proibido",
    s5.r.warning.includes("Orçamento interno — sistemas ARAG para bicos") && !s5.r.warning.includes("Catálogo Magnojet"),
    s5.r.warning);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Provedor ausente ou com falha (SYN6–SYN9)\n");

  const s6 = await rodar({ rotulo: "SYN6", pergunta: Q, prov: null });
  confere("SYN6  resolveProvider → null → extractive, aviso de síntese não configurada",
    s6.r.mode === "extractive" && s6.conta.resolve === 1 && s6.r.warning === AVISO_SEM_PROVEDOR &&
    s6.r.answer === extractivaDe(MAG) && s6.log?.outcome === "no_provider",
    s6.r.warning);

  const s7 = await rodar({ rotulo: "SYN7", pergunta: Q, prov: provedor(new ProviderError(corpoDeErro("auth"), "auth")) });
  confere("SYN7  ProviderError auth → extractive, aviso genérico, provider chamado 1×",
    s7.r.mode === "extractive" && s7.chamadas === 1 && s7.r.warning === AVISO_PROVEDOR &&
    s7.log?.outcome === "provider_error: auth", s7.log?.outcome);
  const vazouErro = (x) => [CHAVE_FALSA, "invalid x-api-key", LINHAS_P20[9]].some((s) => x.includes(s));
  confere("SYN7b nem o aviso, nem a resposta, nem o log carregam o corpo do erro ou a chave",
    !vazouErro(s7.r.warning) && !vazouErro(s7.r.answer) && !vazouErro(s7.brutos.join("\n")) &&
    !vazouErro(JSON.stringify({ ...s7.r, evidence: undefined })));

  const s8 = await rodar({ rotulo: "SYN8", pergunta: Q, prov: provedor(new ProviderError(corpoDeErro("network"), "network")) });
  confere("SYN8  erro de rede → extractive, outcome provider_error: network",
    s8.r.mode === "extractive" && s8.chamadas === 1 && s8.r.warning === AVISO_PROVEDOR &&
    s8.log?.outcome === "provider_error: network");
  const s9 = await rodar({ rotulo: "SYN9", pergunta: Q, prov: provedor(new ProviderError(corpoDeErro("timeout"), "timeout")) });
  confere("SYN9  timeout → extractive, outcome provider_error: timeout",
    s9.r.mode === "extractive" && s9.chamadas === 1 && s9.log?.outcome === "provider_error: timeout");
  confere("SYN9b e o provedor recebe o teto de espera de limits.ts",
    s9.entrada?.timeoutMs === L.TIMEOUT_PROVIDER_MS, String(s9.entrada?.timeoutMs));
  const s9c = await rodar({ rotulo: "SYN9c", pergunta: Q, prov: provedor(new Error(corpoDeErro("bruto"))) });
  confere("SYN9c erro que não é ProviderError → provider_error: unknown, sem o corpo",
    s9c.r.mode === "extractive" && s9c.log?.outcome === "provider_error: unknown" && !vazouErro(s9c.brutos.join("\n")));

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Answer Validator dentro da cadeia (SYN10–SYN14)\n");

  const s10 = await rodar({ rotulo: "SYN10", pergunta: Q, prov: provedor(A.FRASE_DE_RECUSA) });
  confere("SYN10 recusa literal do modelo → no_evidence, mode none, provider 1×",
    s10.r.status === "no_evidence" && s10.r.mode === "none" && s10.chamadas === 1 &&
    s10.r.answer === undefined && s10.r.citations === undefined && s10.log?.outcome === "model_refusal");
  confere("SYN10b as evidências continuam na resposta", s10.r.evidence.length === 1 && s10.r.evidence[0].chunkId === 72);

  const TEXTO_RUIM = "A MJ981CAP entrega 0,99 L/min a 40 psi. [1]";
  const s11 = await rodar({ rotulo: "SYN11", pergunta: Q, prov: provedor(TEXTO_RUIM) });
  confere("SYN11 número fora da evidência → extractive, 'não passou na conferência'",
    s11.r.mode === "extractive" && s11.chamadas === 1 && s11.r.warning === AVISO_GENERICO &&
    s11.log?.outcome.startsWith("answer_rejected (grounding):"), s11.log?.outcome);
  confere("SYN11b o texto reprovado NÃO aparece na resposta",
    !s11.r.answer.includes("0,99") && !JSON.stringify(s11.r).includes(TEXTO_RUIM) && s11.r.answer === extractivaDe(MAG));

  const Q_LISTA = "Quais as vazões da MJ981CAP em bar possíveis?";
  const PONTOS = [["2,07", "0,66"], ["2,76", "0,77"], ["3,45", "0,86"], ["4,14", "0,94"], ["4,83", "1,01"], ["5,52", "1,08"]];
  const lista = (pontos) => ["Valores da MJ981CAP [1]:", ...pontos.map(([b, v]) => `- ${b} bar -> ${v} L/min [1]`)].join("\n");
  const s12 = await rodar({ rotulo: "SYN12", pergunta: Q_LISTA, prov: provedor(lista(PONTOS.filter(([b]) => b !== "4,83"))) });
  confere("SYN12 listagem com valor omitido → extractive, 'não listava todos os valores'",
    s12.r.mode === "extractive" && s12.chamadas === 1 && /não listava todos os valores/.test(s12.r.warning ?? "") &&
    s12.log?.outcome.startsWith("answer_rejected (completeness):"), s12.log?.outcome);

  const INVERTIDA = lista(PONTOS.map(([b], i) => [b, PONTOS[PONTOS.length - 1 - i][1]]));
  const s13 = await rodar({ rotulo: "SYN13", pergunta: Q_LISTA, prov: provedor(INVERTIDA) });
  confere("SYN13 pares de linhas diferentes → extractive, 'ligava valores de linhas diferentes'",
    s13.r.mode === "extractive" && s13.chamadas === 1 && /ligava valores de linhas diferentes/.test(s13.r.warning ?? "") &&
    s13.log?.outcome.startsWith("answer_rejected (association):"), s13.log?.outcome);

  const Q_40PSI = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi";
  const TROCADA = "Comparação a 40 psi [1]:\n- MJ981CAP: 1,53 L/min [1]\n- MJ985CAP: 0,77 L/min [1]";
  const s14 = await rodar({ rotulo: "SYN14", pergunta: Q_40PSI, prov: provedor(TROCADA) });
  confere("SYN14 valores trocados entre produtos → extractive, 'misturou valores entre os produtos'",
    s14.r.mode === "extractive" && s14.chamadas === 1 && /misturou valores entre os produtos/.test(s14.r.warning ?? "") &&
    s14.r.comparison === true && s14.log?.outcome.startsWith("answer_rejected (comparison):"), s14.log?.outcome);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Comparação: teto e incompleta (SYN15–SYN19)\n");

  const Q_SEIS = "Compare MJ980CAP, MJ981CAP, MJ982CAP, MJ983CAP, MJ984CAP e MJ985CAP a 40 psi";
  const s15 = await rodar({ rotulo: "SYN15", pergunta: Q_SEIS, prov: provedor(OK_PONTUAL) });
  confere("SYN15 seis códigos com provedor disponível → provider 0, extractive, comparison true",
    s15.chamadas === 0 && s15.r.mode === "extractive" && s15.r.comparison === true &&
    s15.log?.outcome === "comparison_too_many: 6" &&
    s15.r.warning === `A pergunta compara 6 códigos, acima do limite de ${C.MAX_CODIGOS_COMPARADOS} por consulta. Divida em consultas menores para a resposta continuar conferível.`,
    s15.log?.outcome);

  const Q_999 = "Compare a vazão da MJ981CAP e MJ999CAP a 40 psi.";
  const plano999 = C.planComparison(Q_999, [E.toEvidence(MAG, false)]);
  confere("SYN16 plano da comparação incompleta: ready, incomplete=true, derived=[]",
    plano999.status === "ready" && plano999.incomplete === true && plano999.derived.length === 0 &&
    plano999.blocks.find((b) => b.code === "MJ999CAP")?.missing === true);
  const SEM_CITACAO = "Não encontrei documentação suficiente para MJ999CAP.";
  const s16a = await rodar({ rotulo: "SYN16a", pergunta: Q_999, prov: provedor(SEM_CITACAO) });
  confere("SYN16a hoje chama o provider — GAP, fecha no próximo commit",
    s16a.chamadas === 1, `calls=${s16a.chamadas}`);
  confere("SYN16b e a mensagem vai sem CÁLCULOS VERIFICADOS (não há derivado)",
    !s16a.entrada?.userMessage.includes("CÁLCULOS VERIFICADOS"));
  confere("SYN16c GAP (reprodução): falta declarada SEM citação → extractive, format, aviso genérico, comparison true",
    s16a.r.status === "answered" && s16a.r.mode === "extractive" && s16a.r.warning === AVISO_GENERICO &&
    s16a.r.comparison === true && s16a.log?.outcome.startsWith("answer_rejected (format):"),
    `status=${s16a.r.status} mode=${s16a.r.mode} comparison=${s16a.r.comparison} outcome=${s16a.log?.outcome}`);
  const INCOMPLETA_OK = [
    "MJ981CAP: 0,77 L/min a 40 psi [1].",
    "",
    "Não encontrei documentação suficiente para a MJ999CAP nesse mesmo critério, então não dá para concluir a comparação. [1]",
  ].join("\n");
  const s16d = await rodar({ rotulo: "SYN16d", pergunta: Q_999, prov: provedor(INCOMPLETA_OK) });
  confere("SYN16d GAP (reprodução): falta declarada COM citação → synthesized, comparison true, provider 1×",
    s16d.chamadas === 1 && s16d.r.status === "answered" && s16d.r.mode === "synthesized" &&
    s16d.r.comparison === true && s16d.r.warning === undefined && s16d.log?.outcome === "answered",
    `status=${s16d.r.status} mode=${s16d.r.mode} warning=${s16d.r.warning ?? "—"}`);

  const s17 = await rodar({ rotulo: "SYN17", pergunta: Q_999, prov: null });
  confere("SYN17 GAP (reprodução): incompleta + provedor ausente → no_provider vence, extractive, SEM selo de comparação",
    s17.r.mode === "extractive" && s17.r.warning === AVISO_SEM_PROVEDOR && s17.r.comparison === undefined &&
    s17.log?.outcome === "no_provider",
    `mode=${s17.r.mode} comparison=${s17.r.comparison} outcome=${s17.log?.outcome}`);

  const s18 = await rodar({ rotulo: "SYN18", pergunta: Q_999,
    prov: provedor("- MJ981CAP: 0,77 L/min [1]\n- MJ999CAP: sem dados [1]\n- Diferença: 0,77 L/min [1]") });
  confere("SYN18 GAP (reprodução): incompleta + provedor disponível → chamado 1×; diferença inventada reprova em comparison",
    s18.chamadas === 1 && s18.r.mode === "extractive" && s18.r.comparison === true &&
    /misturou valores entre os produtos/.test(s18.r.warning ?? "") &&
    s18.log?.outcome.startsWith("answer_rejected (comparison):"),
    `calls=${s18.chamadas} outcome=${s18.log?.outcome}`);

  const Q_999_ARAG = "Compare a vazão da MJ981CAP e MJ999CAP a 40 psi com o sensor 466113200.";
  const s19 = await rodar({
    rotulo: "SYN19", pergunta: Q_999_ARAG, linhas: [MAG, ARAG],
    politicas: { [DOC_MAG]: "allowed", [DOC_ARAG]: "forbidden" }, prov: provedor(INCOMPLETA_OK),
  });
  const planoS19 = C.planComparison(Q_999_ARAG, [MAG, ARAG].map((x) => E.toEvidence(x, false)));
  confere("SYN19 forbidden + incompleta: o plano SERIA incompleto, mas o gate externo vence — provider 0",
    planoS19.status === "ready" && planoS19.incomplete === true &&
    s19.chamadas === 0 && s19.conta.resolve === 0 && s19.log?.outcome === "external_processing_forbidden");
  confere("SYN19b o aviso é o do processamento externo, e não fala da comparação",
    s19.r.warning.startsWith('O documento "Orçamento interno — sistemas ARAG para bicos" não pode ser processado') &&
    !s19.r.warning.includes("MJ999CAP") && s19.r.comparison === undefined, s19.r.warning);
  const tituloArag = "Orçamento interno — sistemas ARAG para bicos";
  const ocorrencias = (t, s) => t.split(s).length - 1;
  confere("SYN19c a resposta é EXATAMENTE a extractiva padrão: o título proibido só aparece na linha de citação dela",
    s19.r.answer === extractivaDe(MAG, ARAG) && ocorrencias(s19.r.answer, tituloArag) === 1 &&
    s19.r.answer.includes(`[2] AGROTORK — documentos internos — ${tituloArag} 2024-10 · p. 1`));
  confere("SYN19d nem conteúdo, nem id, nem caminho do documento proibido na resposta ou no aviso",
    !s19.r.answer.includes("1098") && !s19.r.warning.includes("1098") && !s19.r.answer.includes("SENSOR PRESSAO") &&
    !UUID.test(JSON.stringify(s19.r)) && SEGREDOS.every((x) => !JSON.stringify(s19.r).includes(x)));

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Comparação válida (SYN20)\n");

  const Q_H = "Compare a vazão da MJ981CAP e MJ985CAP a 40 psi. Quanto por cento a MJ985CAP entrega a mais?";
  const CALC_H = [
    "Diferença entre MJ981CAP e MJ985CAP: 0,76 L/min [1]",
    "Variação percentual entre MJ981CAP e MJ985CAP: 98,7% [1]",
  ];
  const BLOCOS = ["MJ981CAP [1]:", "- 40 psi -> 0,77 L/min [1]", "", "MJ985CAP [1]:", "- 40 psi -> 1,53 L/min [1]"].join("\n");
  const s20 = await rodar({ rotulo: "SYN20", pergunta: Q_H, prov: provedor(`${BLOCOS}\n\n${CALC_H.join("\n")}\nA MJ985CAP tem maior vazão [1]`) });
  confere("SYN20 comparação H com as linhas de cálculo copiadas → synthesized, comparison true",
    s20.chamadas === 1 && s20.r.mode === "synthesized" && s20.r.comparison === true && s20.log?.outcome === "answered",
    s20.log?.outcome);
  confere("SYN20b a mensagem ao provedor traz o bloco CÁLCULOS VERIFICADOS com [1] em cada linha",
    s20.entrada?.userMessage.includes("=== CÁLCULOS VERIFICADOS") && CALC_H.every((l) => s20.entrada.userMessage.includes(l)));

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Evidência descartada e limites (SYN21–SYN23)\n");

  const s21 = await rodar({ rotulo: "SYN21", pergunta: Q, linhas: [MAG, GRANDE], prov: provedor(OK_PONTUAL) });
  confere("SYN21 uma aceita + uma grande demais → synthesized com aviso de trecho fora",
    s21.r.mode === "synthesized" && s21.chamadas === 1 &&
    s21.r.warning === "1 trecho(s) recuperado(s) ficaram fora da síntese.", s21.r.warning);
  confere("SYN21b a descartada segue na tela, mas não entra nas citações",
    s21.r.evidence.length === 2 && s21.r.citations.length === 1);

  const s22 = await rodar({ rotulo: "SYN22", pergunta: Q, linhas: [GRANDE], prov: provedor(OK_PONTUAL) });
  confere(`SYN22 única evidência acima de ${L.MAX_CHARS_POR_EVIDENCIA} caracteres → provider 0`,
    s22.chamadas === 0 && s22.r.status === "no_evidence" &&
    s22.log?.outcome === "no_evidence: nenhuma das evidências recuperadas passou no gate", s22.log?.outcome);

  // O orçamento total, com os limites de hoje, não consegue barrar a
  // primeira evidência: ela cabe por definição (teto por evidência + 200 ≤
  // contexto). O caminho "nenhuma coube no contexto" é inalcançável — quem
  // barra tudo por tamanho é o teto por evidência (SYN22).
  const custoMax = L.MAX_CHARS_POR_EVIDENCIA + 200;
  confere("SYN23 o orçamento sozinho não barra tudo: a maior evidência aceitável cabe no contexto",
    custoMax <= L.MAX_CHARS_CONTEXTO && L.MAX_EVIDENCIAS_SINTESE * custoMax <= L.MAX_CHARS_CONTEXTO,
    `${L.MAX_EVIDENCIAS_SINTESE} × ${custoMax} ≤ ${L.MAX_CHARS_CONTEXTO}`);
  const noTeto = (i) => linha({ chunk_id: 200 + i, content: `MJ981CAP bloco ${i} ` + "y".repeat(L.MAX_CHARS_POR_EVIDENCIA - 17), codes: ["MJ981CAP"] });
  const quatroNoTeto = [1, 2, 3, 4].map(noTeto);
  const s23 = await rodar({ rotulo: "SYN23b", pergunta: "MJ981CAP", linhas: quatroNoTeto, prov: provedor(A.FRASE_DE_RECUSA) });
  confere(`SYN23b quatro evidências no teto (${L.MAX_CHARS_POR_EVIDENCIA}): vão ${L.MAX_EVIDENCIAS_SINTESE}, a quarta cai pela regra das ${L.MAX_EVIDENCIAS_SINTESE}`,
    quatroNoTeto.every((x) => x.content.length === L.MAX_CHARS_POR_EVIDENCIA) &&
    s23.chamadas === 1 && s23.entrada.evidence.map((e) => e.chunkId).join() === "201,202,203" &&
    !s23.entrada.userMessage.includes("MJ981CAP bloco 4"));
  const s23c = await rodar({ rotulo: "SYN23c", pergunta: "MJ981CAP",
    linhas: [1, 2, 3].map((i) => linha({ chunk_id: 300 + i, content: `MJ981CAP ${i} ` + "z".repeat(L.MAX_CHARS_POR_EVIDENCIA), codes: ["MJ981CAP"] })),
    prov: provedor(OK_PONTUAL) });
  confere("SYN23c três evidências, todas 1 caractere acima do teto → nada cabe, provider 0",
    s23c.chamadas === 0 && s23c.r.status === "no_evidence" && s23c.r.evidence.length === 3);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ O que o provedor recebe (SYN24–SYN26)\n");

  const s24 = await rodar({ rotulo: "SYN24", pergunta: Q_MISTO, linhas: [MAG, ARAG],
    politicas: { [DOC_MAG]: "allowed", [DOC_ARAG]: "allowed" }, prov: provedor("A MJ981CAP entrega 0,77 L/min a 40 psi [1]. O sensor 466113200 aparece no orçamento [2].") });
  const cit24 = s24.r.citations ?? [];
  confere("SYN24 citação n ↔ evidência aceita n-1: index = evidenceIndex + 1, rótulo = citação da evidência",
    s24.r.mode === "synthesized" && cit24.length === 2 &&
    cit24.every((c, i) => c.index === i + 1 && c.evidenceIndex === i && c.label === s24.entrada.evidence[i].citation),
    cit24.map((c) => `[${c.index}]→${c.evidenceIndex}`).join(" "));
  confere("SYN24b com nada descartado, evidenceIndex aponta o card certo em `evidence`",
    cit24.every((c) => s24.r.evidence[c.evidenceIndex]?.citation === c.label));
  // Descarte ANTES de uma aceita desloca a numeração: as citações são
  // montadas sobre `aceitas`, mas a tela indexa `evidence` (tudo o que veio
  // da busca). Reprodução do comportamento de hoje.
  const s24c = await rodar({ rotulo: "SYN24c", pergunta: Q, linhas: [GRANDE, MAG], prov: provedor(OK_PONTUAL) });
  const c24c = s24c.r.citations?.[0];
  confere("SYN24c GAP (reprodução): descartada antes da aceita → [1] aponta evidence[0], que é a DESCARTADA",
    s24c.r.mode === "synthesized" && c24c?.evidenceIndex === 0 && s24c.r.evidence[0].chunkId === 99 &&
    c24c.label === "Magnojet — Catálogo Magnojet V41 · p. 20",
    `citação [1] "${c24c?.label}" → evidence[${c24c?.evidenceIndex}].chunkId=${s24c.r.evidence[c24c?.evidenceIndex]?.chunkId}`);

  const s25 = await rodar({ rotulo: "SYN25", pergunta: Q, linhas: [MAG, GRANDE], prov: provedor(OK_PONTUAL), isAdmin: true });
  const msg25 = s25.entrada?.userMessage ?? "";
  confere("SYN25 o provedor recebe SÓ a evidência aceita (a descartada não vai, nem inteira nem em pedaço)",
    s25.entrada?.evidence.map((e) => e.chunkId).join() === "72" && !msg25.includes("x".repeat(100)) &&
    msg25.includes(P.renderEvidence(s25.entrada.evidence)));
  confere("SYN25b mesmo para admin: a mensagem não traz UUID, caminho de Storage nem sha256",
    !UUID.test(msg25) && SEGREDOS.every((x) => !msg25.includes(x)) && !/\b[0-9a-f]{64}\b/i.test(msg25));
  confere("SYN25c o system prompt é o de prompt.ts, sem nada da consulta dentro",
    s25.entrada?.systemPrompt === P.SYSTEM_PROMPT);
  confere("SYN25d a mensagem é exatamente buildUserMessage(pergunta, aceitas) — nada a mais",
    msg25 === P.buildUserMessage(Q, s25.entrada.evidence));

  const chamadasPorConsulta = TODAS.map((t) => t.chamadas);
  confere("SYN26 provedor chamado no máximo 1× por consulta (sucesso SYN1 e rejeição SYN11 inclusive)",
    s1.chamadas === 1 && s11.chamadas === 1 && chamadasPorConsulta.every((n) => n <= 1),
    `${TODAS.length} consultas, máximo ${Math.max(...chamadasPorConsulta)}`);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Código desconhecido e saída proibida do modelo (SYN27–SYN30)\n");

  const s27 = await rodar({ rotulo: "SYN27", pergunta: "Qual a vazão da MJ777CAP?", linhas: [], prov: provedor(OK_PONTUAL) });
  confere("SYN27 código único desconhecido, busca [] → no_evidence, provider 0",
    s27.r.status === "no_evidence" && s27.chamadas === 0 && s27.conta.externo.length === 0 && s27.r.mode === "none");

  const s28 = await rodar({ rotulo: "SYN28", pergunta: Q, prov: provedor("A MJ981CAP entrega 0,77 L/min a 40 psi. [3]") });
  confere("SYN28 citação [3] com uma evidência → extractive (format)",
    s28.r.mode === "extractive" && s28.r.warning === AVISO_GENERICO && s28.log?.outcome.startsWith("answer_rejected (format):"),
    s28.log?.outcome);
  const s29 = await rodar({ rotulo: "SYN29", pergunta: Q, prov: provedor(`Ver o documento ${DOC_MAG}. [1]`) });
  confere("SYN29 resposta com UUID → extractive, e o UUID não chega à tela",
    s29.r.mode === "extractive" && s29.log?.outcome.startsWith("answer_rejected (format):") &&
    !JSON.stringify(s29.r).includes(DOC_MAG), s29.log?.outcome);
  const s30 = await rodar({ rotulo: "SYN30", pergunta: Q, prov: provedor("Detalhes em https://exemplo.com/catalogo.pdf [1]") });
  confere("SYN30 resposta com URL → extractive, e a URL não chega à tela",
    s30.r.mode === "extractive" && s30.log?.outcome.startsWith("answer_rejected (format):") &&
    !JSON.stringify(s30.r).includes("exemplo.com"), s30.log?.outcome);

  // ════════════════════════════════════════════════════════════
  process.stdout.write("▶ Log [brain.synthesis]\n");

  const semLinhaUnica = TODAS.filter((t) => t.brutos.length !== 1 || typeof t.log?.outcome !== "string");
  confere("LOG1 todo caminho grava exatamente UMA linha [brain.synthesis] com `outcome`",
    semLinhaUnica.length === 0, `${TODAS.length} consultas${semLinhaUnica.length ? `; falhou: ${semLinhaUnica.map((t) => t.rotulo).join(",")}` : ""}`);
  confere("LOG2 e nenhuma outra linha de console.info",
    TODAS.every((t) => t.outros.length === 0));

  const metaCoerente = (t) => {
    const g = t.log;
    if (t.chamadas === 0) return g.provider === null && g.model === null && g.durationMs === null;
    const devolveu = !(t.prov.chamadas.length && t.log.outcome.startsWith("provider_error"));
    return g.provider === "fake" && g.model === "fake-1" && (devolveu ? g.durationMs === 7 : g.durationMs === null);
  };
  const incoerentes = TODAS.filter((t) => !metaCoerente(t));
  confere("LOG3 provider/model só quando o provedor foi chamado; durationMs só quando ele devolveu",
    incoerentes.length === 0, incoerentes.map((t) => `${t.rotulo}:${JSON.stringify(t.log)}`).join(" ") || `${TODAS.length}/${TODAS.length}`);

  const contagensCertas = TODAS.every((t) =>
    t.log.evidencesRetrieved === t.r.evidence.length &&
    t.log.evidencesSent === (t.chamadas === 1 ? t.entrada.evidence.length : 0));
  confere("LOG4 evidencesRetrieved = o que a busca devolveu; evidencesSent = o que o provedor recebeu (0 sem chamada)",
    contagensCertas);

  const PROIBIDO_NO_LOG = [
    ["conteúdo de evidência", (s) => LINHAS_P20.slice(2).some((l) => s.includes(l)) || s.includes(ARAG_CONTEUDO) || s.includes("SENSOR PRESSAO") || s.includes("x".repeat(50))],
    ["system prompt", (s) => s.includes(P.SYSTEM_PROMPT.slice(0, 60)) || s.includes("REGRAS ABSOLUTAS")],
    ["userMessage", (s) => s.includes("=== EVIDÊNCIAS RECUPERADAS") || s.includes("=== PERGUNTA DO USUÁRIO")],
    ["chave falsa", (s) => s.includes(CHAVE_FALSA)],
    ["corpo do erro", (s) => s.includes("invalid x-api-key")],
    ["id/caminho/hash", (s) => SEGREDOS.some((x) => s.includes(x)) || UUID.test(s)],
  ];
  for (const [nome, vaza] of PROIBIDO_NO_LOG) {
    const culpados = TODAS.filter((t) => vaza(t.brutos.join("\n")));
    confere(`LOG5 o log nunca contém ${nome}`, culpados.length === 0, culpados.map((t) => t.rotulo).join(",") || `${TODAS.length} linhas`);
  }

  // Achado, não regra: o motivo da rejeição vai ao log com um PREFIXO da
  // linha da evidência (cortado em "…") e o item da resposta reprovado.
  // Nunca a linha inteira — LOG5 prova isso —, mas também não é zero.
  confere("LOG6 ACHADO (reprodução): rejeição por completeness/association leva ao log prefixo truncado da linha, nunca a linha inteira",
    s12.brutos[0].includes("MJ981CAP MUG-CV 02 MALHA 50 UG 4,83 bar …") && !s12.brutos[0].includes(LINHAS_P20[12]) &&
    s13.brutos[0].includes("- 2,07 bar -> 1,08 L/min") && !s13.brutos[0].includes(LINHAS_P20[8]));

  const prefixo = (o) => {
    const m = o.match(/^answer_rejected \((\w+)\):/);
    if (m) return `answer_rejected (${m[1]}):`;
    if (o.startsWith("no_evidence:")) return "no_evidence:";
    if (o.startsWith("comparison_too_many:")) return "comparison_too_many:";
    if (o.startsWith("provider_error:")) return "provider_error:";
    return o;
  };
  const observados = [...new Set(TODAS.map((t) => prefixo(t.log.outcome)))].sort();
  const ESPERADOS = [
    "answered", "no_evidence:", "external_processing_forbidden", "no_provider", "comparison_too_many:",
    "provider_error:", "model_refusal",
    "answer_rejected (grounding):", "answer_rejected (completeness):", "answer_rejected (association):",
    "answer_rejected (comparison):", "answer_rejected (format):",
  ].sort();
  confere("LOG7 taxonomia de outcome: todos os prefixos conhecidos foram exercitados, nenhum desconhecido",
    JSON.stringify(observados) === JSON.stringify(ESPERADOS), observados.join(" · "));
}
