import "server-only";

import {
  assessEvidence,
  buildCitations,
  extractiveAnswer,
  validateAnswer,
  type BrainNaturalAnswer,
} from "./answer";
import { assessExternalProcessing, parsePolicy, type EvidenceRef } from "./external-processing";
import { refusal, toEvidence, type KnowledgeEvidence, type KnowledgeHitRow } from "./evidence";
import { TIMEOUT_PROVIDER_MS } from "./limits";
import { resolveProvider } from "./llm";
import { ProviderError } from "./llm/provider";
import { buildUserMessage, SYSTEM_PROMPT } from "./prompt";
import * as repository from "./repository";
import type { KnowledgeQuery } from "./schema";

/**
 * A cadeia inteira, num lugar só:
 *
 *   busca autorizada → Evidence Gate → gate de processamento externo
 *   → prompt → provedor → Answer Validator → resposta com citações
 *
 * Três coisas que este arquivo NÃO faz, e é o mais importante dele:
 *
 *  · não consulta o banco em nome do modelo. O provedor recebe um texto já
 *    montado, com trechos que aquele usuário já podia ler;
 *  · não deixa a síntese substituir a evidência. O que o retrieval achou vai
 *    para a tela de qualquer jeito, síntese ou não;
 *  · não transforma falha em resposta. Provedor fora do ar, citação
 *    inventada, política proibindo — tudo vira recusa ou resposta
 *    extractiva, nunca um parágrafo sem lastro.
 */

/** Diagnóstico da geração. Vai para o log do servidor, nunca para o cliente. */
type GenerationLog = {
  query: string;
  evidencesRetrieved: number;
  evidencesSent: number;
  provider: string | null;
  model: string | null;
  durationMs: number | null;
  outcome: string;
};

function registrar(log: GenerationLog) {
  // Log de servidor é suficiente na v1: a busca já tem trilha em
  // `brain.knowledge_queries`, e uma tabela nova para a geração exigiria
  // migration sem necessidade provada. A pergunta entra porque ela já está
  // na trilha do banco; o conteúdo das evidências e o prompt, não.
  console.info("[brain.synthesis]", JSON.stringify(log));
}

export async function answer(
  input: KnowledgeQuery,
  opts: { isAdmin: boolean },
): Promise<BrainNaturalAnswer> {
  const rows: KnowledgeHitRow[] = await repository.search(input);
  const evidencias: KnowledgeEvidence[] = rows.map((r) => toEvidence(r, opts.isAdmin));

  const base = (extra: Partial<BrainNaturalAnswer>): BrainNaturalAnswer => ({
    query: input.query,
    status: "answered",
    evidence: evidencias,
    ...extra,
  });

  // ── Evidence Gate ─────────────────────────────────────────
  const avaliacao = assessEvidence(input.query, evidencias);
  if (!avaliacao.sufficient) {
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null,
      outcome: `no_evidence: ${avaliacao.reason}`,
    });
    // Se o retrieval trouxe algo mas o gate recusou tudo, as evidências
    // continuam na tela: o usuário decide se aquilo serve para ele.
    return { ...refusal(input.query, "no_evidence"), evidence: evidencias, mode: "none" };
  }

  const aceitas = avaliacao.accepted;
  const citacoes = buildCitations(aceitas);

  // ── gate de processamento externo ─────────────────────────
  // ANTES do provedor, sempre. Autorizar leitura não autoriza saída.
  const refs: EvidenceRef[] = aceitas.map((e) => {
    const linha = rows.find((r) => r.chunk_id === e.chunkId);
    return {
      chunkId: e.chunkId,
      documentId: linha?.document_id ?? "",
      documentTitle: e.document.title,
    };
  });
  const politicas = await repository.externalProcessing(refs.map((r) => r.documentId));
  const externo = assessExternalProcessing(
    refs,
    new Map([...politicas].map(([id, p]) => [id, parsePolicy(p)])),
  );

  if (!externo.allowed) {
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null,
      outcome: "external_processing_forbidden",
    });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoes,
      mode: "extractive",
      warning: `${externo.reason} A consulta continua disponível, com os trechos na íntegra.`,
    });
  }

  // ── provedor ──────────────────────────────────────────────
  const provider = resolveProvider();
  if (!provider) {
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null, outcome: "no_provider",
    });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoes,
      mode: "extractive",
      warning: "A síntese automática não está configurada neste ambiente. Os trechos encontrados estão abaixo.",
    });
  }

  let texto: string;
  let meta: { provider: string; model: string; durationMs: number };
  try {
    const saida = await provider.generate({
      question: input.query,
      evidence: aceitas,
      systemPrompt: SYSTEM_PROMPT,
      userMessage: buildUserMessage(input.query, aceitas),
      timeoutMs: TIMEOUT_PROVIDER_MS,
    });
    texto = saida.text;
    meta = saida.meta;
  } catch (erro) {
    const tipo = erro instanceof ProviderError ? erro.kind : "unknown";
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: aceitas.length,
      provider: provider.name, model: provider.model, durationMs: null,
      outcome: `provider_error: ${tipo}`,
    });
    // Falha do provedor não apaga o que o BRAIN achou.
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoes,
      mode: "extractive",
      warning: "Não consegui redigir a resposta agora. Os trechos encontrados estão abaixo.",
    });
  }

  // ── Answer Validator ──────────────────────────────────────
  const validacao = validateAnswer(texto, citacoes, aceitas, input.query);
  if (!validacao.ok) {
    // O modelo dizer "a documentação não permite concluir" não é falha dele
    // nem nossa: é a resposta certa. Vira `no_evidence`, com as evidências
    // na tela para a pessoa julgar.
    if (validacao.kind === "model_refusal") {
      registrar({
        query: input.query, evidencesRetrieved: rows.length, evidencesSent: aceitas.length,
        provider: meta.provider, model: meta.model, durationMs: meta.durationMs,
        outcome: "model_refusal",
      });
      return { ...refusal(input.query, "no_evidence"), evidence: evidencias, mode: "none" };
    }

    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: aceitas.length,
      provider: meta.provider, model: meta.model, durationMs: meta.durationMs,
      outcome: `answer_rejected (${validacao.kind}): ${validacao.details?.join(" | ") ?? validacao.problem}`,
    });
    // Não se limpa uma alucinação em silêncio: a resposta é descartada
    // inteira e o usuário recebe a matéria-prima, que é verificável. Um
    // número trocado NÃO vira número certo aqui — vira resposta descartada.
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoes,
      mode: "extractive",
      warning: validacao.kind === "completeness"
        ? "A resposta gerada não listava todos os valores pedidos e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : "A resposta gerada não passou na conferência e foi descartada. Os trechos encontrados estão abaixo.",
    });
  }

  registrar({
    query: input.query, evidencesRetrieved: rows.length, evidencesSent: aceitas.length,
    provider: meta.provider, model: meta.model, durationMs: meta.durationMs, outcome: "answered",
  });

  return base({
    answer: texto.trim(),
    citations: citacoes,
    mode: "synthesized",
    warning: avaliacao.dropped.length > 0
      ? `${avaliacao.dropped.length} trecho(s) recuperado(s) ficaram fora da síntese.`
      : undefined,
  });
}
