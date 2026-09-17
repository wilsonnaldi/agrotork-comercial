import type { KnowledgeEvidence } from "./evidence";
import { checkGrounding, describeFailure } from "./grounding";
import {
  MAX_CHARS_CONTEXTO,
  MAX_CHARS_POR_EVIDENCIA,
  MAX_CHARS_RESPOSTA,
  MAX_EVIDENCIAS_SINTESE,
} from "./limits";

/**
 * Contrato da resposta natural, o Evidence Gate e o Answer Validator.
 *
 * Tudo aqui é PURO — nada de banco, nada de rede, nada de `server-only`. É a
 * camada que decide se o modelo pode ser chamado e se o que ele devolveu
 * pode ser mostrado, e por isso tem de ser exercitável sozinha
 * (`supabase/db-tests/check-brain-answer.mjs`).
 *
 * A regra que organiza o arquivo inteiro: **o modelo não é fonte de
 * verdade.** Ele recebe trechos já autorizados e os resume. Se a resposta
 * não puder ser amarrada às evidências, ela não é mostrada como confiável.
 */

export type AnswerStatus = "answered" | "no_evidence" | "forbidden" | "error";

export type BrainCitation = {
  /** O número que aparece na resposta: [1], [2]… */
  index: number;
  source: string;
  document: string;
  version: string;
  pageFrom: number;
  pageTo: number;
  /** Posição da evidência no array devolvido — para a tela ligar [1] ao card. */
  evidenceIndex: number;
  label: string;
};

export type BrainNaturalAnswer = {
  query: string;
  status: AnswerStatus;
  /** Texto sintetizado. Ausente em qualquer recusa. */
  answer?: string;
  citations?: BrainCitation[];
  /** A matéria-prima continua disponível, sempre que o usuário pode vê-la. */
  evidence: KnowledgeEvidence[];
  /** Por que não houve síntese, ou o que o usuário precisa saber sobre ela. */
  refusalReason?: string;
  warning?: string;
  /** Como a resposta foi produzida. `extractive` = sem modelo externo. */
  mode?: "synthesized" | "extractive" | "none";
};

// ════════════════════════════════════════════════════════════
// Evidence Gate
// ════════════════════════════════════════════════════════════

export type EvidenceAssessment = {
  sufficient: boolean;
  reason?: string;
  /** As evidências aprovadas, na ordem em que virarão [1], [2]… */
  accepted: KnowledgeEvidence[];
  /** O que foi descartado e por quê — para o relatório e para o log. */
  dropped: { chunkId: number; why: string }[];
};

/** Acentos fora, minúsculas, pontuação vira espaço. */
export function normalize(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * Palavras curtas e conectivos não dizem nada sobre o assunto. A lista é
 * pequena de propósito: o objetivo não é entender a pergunta, é só não
 * deixar "de" e "qual" contarem como relação.
 */
const VAZIAS = new Set([
  "qual", "quais", "quanto", "quanta", "quantos", "quantas", "como", "onde", "quando", "porque",
  "que", "para", "por", "com", "sem", "dos", "das", "nos", "nas", "uma", "uns", "umas",
  "the", "and", "tem", "sao", "esta", "este", "essa", "esse", "isso", "aqui", "sobre",
  "preco", "valor", "documento", "documentos", "pode", "posso", "voce", "seu", "sua", "minha", "meu",
]);

export function significantTokens(texto: string): string[] {
  return normalize(texto)
    .split(" ")
    .filter((t) => t.length >= 3 && !VAZIAS.has(t));
}

/**
 * Relação mínima entre pergunta e evidência. É LEXICAL e é grosseira de
 * propósito — não é um classificador, é uma cerca contra o caso patológico
 * em que o retrieval devolveu algo sem nada em comum com a pergunta.
 *
 * O prefixo de 5 caracteres faz as vezes de radical ("pontas" ≈ "ponta"),
 * que é o suficiente para não brigar com o stemming do FTS português. Um
 * código presente em `codes` vale por si: é o sinal mais forte que existe.
 */
export function relacionada(pergunta: string, evidencia: KnowledgeEvidence): boolean {
  const alvo = new Set(
    [...significantTokens(evidencia.content), ...significantTokens(evidencia.headingPath.join(" "))].map((t) =>
      t.slice(0, 5),
    ),
  );
  for (const codigo of evidencia.codes) alvo.add(normalize(codigo).slice(0, 5));
  return significantTokens(pergunta).some((t) => alvo.has(t.slice(0, 5)));
}

/**
 * Decide se vale chamar o modelo. Conservador por desenho: na dúvida,
 * fail-closed. Cada motivo de descarte é nomeado — "não deu certo" não
 * ajuda ninguém a consertar o corpus depois.
 */
export function assessEvidence(
  pergunta: string,
  evidencias: KnowledgeEvidence[],
): EvidenceAssessment {
  const dropped: { chunkId: number; why: string }[] = [];
  const aprovadas: KnowledgeEvidence[] = [];

  for (const e of evidencias) {
    if (!e.content || e.content.trim().length === 0) {
      dropped.push({ chunkId: e.chunkId, why: "trecho sem conteúdo" });
      continue;
    }
    if (e.version.status !== "active") {
      // O retrieval já filtra vigência; isto é a segunda tranca, para o caso
      // de alguém pedir superseded e a síntese não perceber.
      dropped.push({ chunkId: e.chunkId, why: `versão ${e.version.status}, não vigente` });
      continue;
    }
    if (!e.citation || e.citation.trim().length === 0) {
      dropped.push({ chunkId: e.chunkId, why: "sem proveniência para citar" });
      continue;
    }
    if (!relacionada(pergunta, e)) {
      dropped.push({ chunkId: e.chunkId, why: "nada em comum com a pergunta" });
      continue;
    }
    aprovadas.push(e);
  }

  if (aprovadas.length === 0) {
    return {
      sufficient: false,
      reason:
        evidencias.length === 0
          ? "nenhuma evidência recuperada"
          : "nenhuma das evidências recuperadas passou no gate",
      accepted: [],
      dropped,
    };
  }

  // Corta no teto de evidências e no teto de contexto, nessa ordem. Cortar
  // uma evidência inteira é honesto; cortar um trecho ao meio, não.
  const escolhidas: KnowledgeEvidence[] = [];
  let orcamento = MAX_CHARS_CONTEXTO;
  for (const e of aprovadas.slice(0, MAX_EVIDENCIAS_SINTESE)) {
    const custo = Math.min(e.content.length, MAX_CHARS_POR_EVIDENCIA) + 200; // 200 ≈ cabeçalho
    if (custo > orcamento && escolhidas.length > 0) {
      dropped.push({ chunkId: e.chunkId, why: "não coube no orçamento de contexto" });
      continue;
    }
    orcamento -= custo;
    escolhidas.push(e);
  }
  for (const e of aprovadas.slice(MAX_EVIDENCIAS_SINTESE)) {
    dropped.push({ chunkId: e.chunkId, why: `além das ${MAX_EVIDENCIAS_SINTESE} evidências da síntese` });
  }

  return { sufficient: true, accepted: escolhidas, dropped };
}

// ════════════════════════════════════════════════════════════
// Citações
// ════════════════════════════════════════════════════════════

export function buildCitations(evidencias: KnowledgeEvidence[]): BrainCitation[] {
  return evidencias.map((e, i) => ({
    index: i + 1,
    source: e.source,
    document: e.document.title,
    version: e.version.label,
    pageFrom: e.page.from,
    pageTo: e.page.to,
    evidenceIndex: i,
    label: e.citation,
  }));
}

/** Os números entre colchetes que o texto realmente usa. */
export function referencesUsed(texto: string): number[] {
  const achados = new Set<number>();
  for (const m of texto.matchAll(/\[(\d{1,3})\]/g)) achados.add(Number(m[1]));
  return [...achados].sort((a, b) => a - b);
}

// ════════════════════════════════════════════════════════════
// Answer Validator
// ════════════════════════════════════════════════════════════

/**
 * `kind` separa três coisas que a orquestração trata de formas diferentes:
 *  · `model_refusal` — o modelo disse que não dá para concluir. Não é erro:
 *    vira `no_evidence`, que é a resposta honesta;
 *  · `grounding` — número, unidade ou código sem lastro na evidência citada;
 *  · `format` — vazio, enorme, citação inexistente, campo proibido.
 */
export type ValidationProblem = "model_refusal" | "grounding" | "format";

export type ValidationResult =
  | { ok: true }
  | { ok: false; kind: ValidationProblem; problem: string; details?: string[] };

/** A frase exata que o prompt manda usar quando as evidências não bastam. */
export const FRASE_DE_RECUSA = "A documentação disponível não permite concluir isso.";

/**
 * O modelo se recusou a concluir. Comparação frouxa de propósito — pontuação
 * e caixa variam, e uma recusa quase-igual continua sendo uma recusa.
 */
export function modelRefused(texto: string): boolean {
  const limpa = (t: string) =>
    t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim();
  const alvo = limpa(FRASE_DE_RECUSA);
  const corpo = limpa(texto);
  return corpo.length > 0 && corpo.length <= alvo.length + 40 && corpo.includes(alvo);
}

/** Campos que nunca podem aparecer no texto devolvido pelo modelo. */
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const SHA256 = /\b[0-9a-f]{64}\b/i;
const CAMINHO_STORAGE = /\b[\w-]+\/[\w.-]+\/[\w.-]+\/[0-9a-f]{8,}\.\w{2,5}\b/i;
const URL = /\bhttps?:\/\/\S+/i;

/**
 * O que se confere DEPOIS da geração. Falhou, a resposta não é mostrada —
 * não se "limpa" uma alucinação crítica em silêncio, porque limpar esconde
 * que o modelo errou e a próxima vez ninguém fica sabendo.
 *
 * Precisa das EVIDÊNCIAS, não só das citações: desde 17/09 a conferência não
 * para em "existe um [1]" — ela exige que os números, as unidades e os
 * códigos escritos em cada parágrafo estejam nas evidências citadas NAQUELE
 * parágrafo. Sem as evidências à mão, isso seria impossível, e uma resposta
 * como "0,99 L/min [1]" passaria com a evidência dizendo 0,77.
 */
export function validateAnswer(
  texto: string,
  citacoes: BrainCitation[],
  evidencias: KnowledgeEvidence[],
): ValidationResult {
  const limpo = (texto ?? "").trim();

  if (limpo.length === 0) return { ok: false, kind: "format", problem: "o modelo devolveu texto vazio" };
  if (limpo.length > MAX_CHARS_RESPOSTA) {
    return {
      ok: false, kind: "format",
      problem: `resposta com ${limpo.length} caracteres, acima do teto de ${MAX_CHARS_RESPOSTA}`,
    };
  }

  // A recusa do modelo é resposta legítima, e não passa pelo resto: ela não
  // tem citação porque não afirma nada.
  if (modelRefused(limpo)) {
    return { ok: false, kind: "model_refusal", problem: "o modelo não encontrou base nas evidências" };
  }

  const usadas = referencesUsed(limpo);
  const validas = new Set(citacoes.map((c) => c.index));

  if (usadas.length === 0) {
    return { ok: false, kind: "format", problem: "resposta afirmativa sem nenhuma citação" };
  }
  const inexistentes = usadas.filter((n) => !validas.has(n));
  if (inexistentes.length > 0) {
    return {
      ok: false, kind: "format",
      problem: `citação para evidência inexistente: ${inexistentes.map((n) => `[${n}]`).join(", ")} (há ${citacoes.length})`,
    };
  }

  if (UUID.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém identificador interno" };
  if (SHA256.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém hash de arquivo" };
  if (CAMINHO_STORAGE.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém caminho de arquivo" };
  if (URL.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém endereço de internet" };

  // A trava determinística: cada parágrafo cita, e o que ele afirma em
  // número, unidade e código está nas evidências que ele citou.
  const lastro = checkGrounding(limpo, citacoes, evidencias);
  if (!lastro.ok) {
    const detalhes = lastro.failures.map(describeFailure);
    return {
      ok: false, kind: "grounding",
      problem: detalhes[0] ?? "afirmação sem lastro na evidência citada",
      details: detalhes,
    };
  }

  return { ok: true };
}

/**
 * Resposta extractiva: usada quando a síntese externa está proibida pela
 * política de processamento externo, ou quando não há provedor. Não é um
 * resumo — é a citação da primeira evidência, montada aqui, sem modelo
 * nenhum. Honesta sobre o que é.
 */
export function extractiveAnswer(evidencias: KnowledgeEvidence[]): string {
  const n = evidencias.length;
  const cabeca = n === 1
    ? "Encontrei 1 trecho na documentação, mas não posso resumi-lo automaticamente:"
    : `Encontrei ${n} trechos na documentação, mas não posso resumi-los automaticamente:`;
  const corpo = evidencias
    .map((e, i) => `[${i + 1}] ${e.citation}`)
    .join("\n");
  return `${cabeca}\n\n${corpo}\n\nOs trechos estão abaixo, na íntegra.`;
}
