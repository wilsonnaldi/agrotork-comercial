/**
 * Confere o contrato do Query Service do BRAIN (`src/modules/brain/`).
 *
 *   node supabase/db-tests/check-brain.mjs
 *
 * Por que existe: a camada TypeScript decide DUAS coisas que o banco não
 * decide — o que entra (validação da pergunta) e o que sai (o que a tela vê).
 * O banco já barra quem não pode ler; o que ele não faz é impedir que o
 * aplicativo entregue um UUID, um caminho de Storage ou o sha256 do arquivo
 * junto com a evidência. Quem garante isso é `evidence.ts`, e é isto que
 * este arquivo exercita.
 *
 * Os casos que dependem de banco e de papel — vendedor x admin, degradada,
 * superseded, trilha da consulta — estão em `39_brain_query_service.sql`.
 *
 * Como roda sem test runner: mesmo truque do `check-nfe.mjs`.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "evidence.ts": "src/modules/brain/evidence.ts",
  "schema.ts": "src/modules/brain/schema.ts",
};

const destino = mkdtempSync(join(RAIZ, ".brain-check-"));
// Exceção não tratada no meio da suíte também passa pelo "exit": o
// diretório some mesmo quando o rmSync do fim não chega a rodar.
process.on("exit", () => rmSync(destino, { recursive: true, force: true }));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  // `Json` é só tipo; o strip-types apaga o import, mas o caminho `@/` teria
  // de resolver antes disso. Troca por um tipo local equivalente.
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    .replace(/^import type \{ Json \} from "@\/types\/db";$/m, "type Json = unknown;");
  writeFileSync(join(destino, nome), fonte);
}

const evidence = await import(pathToFileURL(join(destino, "evidence.ts")).href);
const { knowledgeQuerySchema } = await import(pathToFileURL(join(destino, "schema.ts")).href);

let falhas = 0;
const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };
const confere = (titulo, condicao, detalhe = "") =>
  condicao ? ok(`${titulo}${detalhe ? ` — ${detalhe}` : ""}`) : nao(`${titulo}${detalhe ? ` — ${detalhe}` : ""}`);

/** Uma linha crua como `public.brain_search` devolve, com os campos sensíveis. */
const LINHA = {
  chunk_id: 4211,
  score: 0.0327868852459016,
  rank_exact: 1,
  rank_trgm: 3,
  rank_fts: null,
  kind: "table",
  content: "MJ981CAP SOL-CV 02 UG 2,76 40 0,77 77",
  table_data: { rows: [[1, 2]] },
  page_from: 20,
  page_to: 20,
  heading_path: ["PONTAS", "CONE VAZIO"],
  codes: ["MJ981CAP"],
  version_id: "11111111-2222-4333-8444-555555555555",
  version_label: "V41",
  version_status: "active",
  document_id: "66666666-7777-4888-8999-aaaaaaaaaaaa",
  title: "Catálogo Magnojet",
  document_type: "catalog",
  source_key: "magnojet",
  access_level: "public",
  storage_path: "magnojet/magnojet-catalogo/V41/deadbeef.pdf",
  file_sha256: "deadbeef".repeat(8),
};

process.stdout.write("▶ contrato de entrada (Zod)\n");

// T5 · pergunta vazia
confere("T5 pergunta vazia é recusada", !knowledgeQuerySchema.safeParse({ query: "" }).success);
confere("T5 pergunta só de espaço é recusada", !knowledgeQuerySchema.safeParse({ query: "    " }).success);
confere("T5 uma letra é recusada", !knowledgeQuerySchema.safeParse({ query: "a" }).success);

// T6 · pergunta grande demais
const gigante = "a".repeat(1001);
confere("T6 pergunta acima de 1000 caracteres é recusada",
  !knowledgeQuerySchema.safeParse({ query: gigante }).success, "1001 caracteres");
confere("T6 exatamente 1000 caracteres passa",
  knowledgeQuerySchema.safeParse({ query: "a".repeat(1000) }).success);

// limite e filtros
const padrao = knowledgeQuerySchema.parse({ query: "vazão da MJ981CAP" });
confere("limite padrão é 10", padrao.limit === 10, `limit=${padrao.limit}`);
confere("limite acima de 100 é recusado", !knowledgeQuerySchema.safeParse({ query: "x y", limit: 500 }).success);
confere("filtro desconhecido é recusado (strict)",
  !knowledgeQuerySchema.safeParse({ query: "x y", filters: { inventado: "1" } }).success);
confere("pergunta é aparada nas pontas",
  knowledgeQuerySchema.parse({ query: "  MJ981CAP  " }).query === "MJ981CAP");

process.stdout.write("▶ o que a tela recebe (sanitização)\n");

const vendedor = evidence.toEvidence(LINHA, false);
const admin = evidence.toEvidence(LINHA, true);
const serializado = JSON.stringify(vendedor);

// T-SAN · nada de id, caminho de arquivo ou hash para quem não é admin
confere("nenhum UUID chega ao usuário comum",
  !/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(serializado));
confere("caminho de Storage não vaza", !serializado.includes("storage") && !serializado.includes(".pdf"));
confere("sha256 do arquivo não vaza", !serializado.includes(LINHA.file_sha256));
confere("sem bloco de debug para quem não é admin", vendedor.debug === undefined);

// T-DBG · admin recebe o painel, e só ele
confere("admin recebe rank_exact/trgm/fts", admin.debug?.rankExact === 1 && admin.debug?.rankTrgm === 3 && admin.debug?.rankFts === null);
confere("admin recebe o chunk id e o score", admin.debug?.chunkId === 4211 && Math.abs(admin.debug.score - 0.0327868852459016) < 1e-12);

// o essencial continua chegando
confere("fonte com nome de gente", vendedor.source === "Magnojet");
confere("documento, versão e página", vendedor.document.title === "Catálogo Magnojet" && vendedor.version.label === "V41" && vendedor.page.from === 20);
confere("proveniência pronta para citar", vendedor.citation === "Magnojet — Catálogo Magnojet V41 · p. 20", vendedor.citation);
confere("código da peça preservado", vendedor.codes.join() === "MJ981CAP");
confere("nível de acesso visível", vendedor.accessLevel === "public");

const duasPaginas = evidence.toEvidence({ ...LINHA, page_from: 20, page_to: 21 }, false);
confere("trecho que cruza página cita o intervalo", duasPaginas.citation.endsWith("p. 20–21"), duasPaginas.citation);

const fonteNova = evidence.toEvidence({ ...LINHA, source_key: "fonte_que_ainda_nao_tem_rotulo" }, false);
confere("fonte sem rótulo mostra a chave, nunca um id", fonteNova.source === "fonte_que_ainda_nao_tem_rotulo");

process.stdout.write("▶ recusas\n");

const semEvidencia = evidence.refusal("qual o manual da semeadora Kuhn?", "no_evidence");
confere("no_evidence não traz evidência nenhuma", semEvidencia.evidence.length === 0 && semEvidencia.status === "no_evidence");
confere("no_evidence diz que não sabe, sem completar",
  semEvidencia.refusalReason === evidence.SEM_EVIDENCIA, semEvidencia.refusalReason);
confere("a pergunta volta junto da recusa", semEvidencia.query === "qual o manual da semeadora Kuhn?");

const proibido = evidence.refusal("orçamento interno", "forbidden");
confere("forbidden não revela se o documento existe",
  proibido.evidence.length === 0 && proibido.refusalReason === evidence.SEM_PERMISSAO);

// T16 · erro de banco não vaza stack nem SQL
const erro = evidence.refusal("MJ981CAP", "error");
const textoDoErro = JSON.stringify(erro);
confere("T16 mensagem de erro é genérica", erro.refusalReason === evidence.ERRO_CONSULTA, erro.refusalReason);
confere("T16 erro não carrega SQL, schema nem stack",
  !/select |from brain\.|relation |at Object|\.ts:\d+/i.test(textoDoErro));

const erroDeEntrada = evidence.refusal("x", "error", "Escreva ao menos 2 caracteres.");
confere("erro de validação pode ter mensagem própria", erroDeEntrada.refusalReason === "Escreva ao menos 2 caracteres.");

rmSync(destino, { recursive: true, force: true });

process.stdout.write(falhas === 0 ? "✔ contrato do Query Service\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
