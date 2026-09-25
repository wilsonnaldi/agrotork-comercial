import "server-only";

import {
  assessEvidence,
  buildCitations,
  extractiveAnswer,
  validateAnswer,
  type BrainCitation,
  type BrainNaturalAnswer,
} from "./answer";
import { MAX_CODIGOS_COMPARADOS, planComparison } from "./comparison";
import { assessExternalProcessing, parsePolicy, type EvidenceRef } from "./external-processing";
import { refusal, toEvidence, type KnowledgeEvidence, type KnowledgeHitRow } from "./evidence";
import { TIMEOUT_PROVIDER_MS } from "./limits";
import { resolveProvider } from "./llm";
import { ProviderError, type BrainLlmProvider } from "./llm/provider";
import { buildUserMessage, renderCalculation, SYSTEM_PROMPT } from "./prompt";
import * as repository from "./repository";
import type { KnowledgeQuery } from "./schema";

/**
 * A cadeia inteira, num lugar só:
 *
 *   busca autorizada → Evidence Gate → gate de processamento externo
 *   → comparação estrutural → provedor disponível? → prompt → provedor
 *   → Answer Validator → resposta com citações
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

/**
 * O aviso da comparação sem um dos lados. Os códigos vêm da PERGUNTA, então
 * repeti-los não revela nada; "não encontrei … nesta consulta" vale igual
 * para documento inexistente e para documento que esta pessoa não pode ver
 * — as duas situações têm de ser indistinguíveis. Nenhuma sugestão de código
 * parecido, pelo mesmo motivo.
 */
function avisoComparacaoIncompleta(faltantes: string[], todosFaltam: boolean): string {
  const lista = faltantes.length === 1
    ? faltantes[0]
    : `${faltantes.slice(0, -1).join(", ")} e ${faltantes[faltantes.length - 1]}`;
  return `Não dá para concluir a comparação: não encontrei documentação para ${lista} nesta consulta. ` +
    (todosFaltam
      ? "Os trechos encontrados estão abaixo, na íntegra."
      : "Os trechos encontrados para os demais códigos estão abaixo, na íntegra.");
}

/**
 * As citações como a TELA as lê. Duas numerações convivem aqui, e trocá-las
 * é o erro: `buildCitations(aceitas)` numera `evidenceIndex` sobre as
 * evidências ACEITAS — é o que o validador (grounding, comparação) espera —,
 * mas o console indexa `resposta.evidence`, que é TUDO o que a busca trouxe,
 * inclusive o que o Evidence Gate descartou. Com um descarte antes de uma
 * aceita, [1] abria o card errado. A tradução acontece só na saída; o
 * validador continua recebendo as citações sobre as aceitas.
 */
function citacoesParaTela(
  citacoes: BrainCitation[],
  aceitas: KnowledgeEvidence[],
  evidencias: KnowledgeEvidence[],
): BrainCitation[] {
  const posicao = new Map(evidencias.map((e, i) => [e, i]));
  return citacoes.map((c) => ({ ...c, evidenceIndex: posicao.get(aceitas[c.evidenceIndex]!) ?? c.evidenceIndex }));
}

/**
 * As três portas por onde a cadeia sai deste arquivo: banco (busca e
 * política) e provedor. Injetáveis só para a máquina de estados ser
 * exercitada sem banco, sem rede e sem chave
 * (`supabase/db-tests/check-brain-synthesis.mjs`). Nada de container: o app
 * chama `answer`, que liga as portas de verdade; o teste chama `answerWith`
 * com falsos.
 */
export type SynthesisDeps = {
  search: (input: KnowledgeQuery) => Promise<KnowledgeHitRow[]>;
  externalProcessing: (documentIds: string[]) => Promise<Map<string, string>>;
  resolveProvider: () => BrainLlmProvider | null;
};

const DEPS: SynthesisDeps = {
  search: repository.search,
  externalProcessing: repository.externalProcessing,
  resolveProvider,
};

export function answer(
  input: KnowledgeQuery,
  opts: { isAdmin: boolean },
): Promise<BrainNaturalAnswer> {
  return answerWith(DEPS, input, opts);
}

export async function answerWith(
  deps: SynthesisDeps,
  input: KnowledgeQuery,
  opts: { isAdmin: boolean },
): Promise<BrainNaturalAnswer> {
  const rows: KnowledgeHitRow[] = await deps.search(input);
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
  const citacoesDaTela = citacoesParaTela(citacoes, aceitas, evidencias);

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
  const politicas = await deps.externalProcessing(refs.map((r) => r.documentId));
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
      citations: citacoesDaTela,
      mode: "extractive",
      warning: `${externo.reason} A consulta continua disponível, com os trechos na íntegra.`,
    });
  }

  // ── comparação estrutural: antes de saber se há provedor ──
  // O plano sai das MESMAS evidências que iriam ao provedor, com a mesma
  // função que o validador usa depois. Se os dois discordassem, a resposta
  // seria descartada — eles não discordam porque é o mesmo código.
  //
  // Vem ANTES da disponibilidade do provedor porque o que ele decide não
  // depende de modelo nenhum: comparação grande demais ou sem um dos lados
  // não tem resposta conferível, com ou sem chave. Assim o resultado é o
  // mesmo em qualquer ambiente, e o provedor não é chamado para escrever
  // algo que o sistema já sabe que não pode concluir.
  const plano = planComparison(input.query, aceitas);
  if (plano.status === "too_many") {
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null,
      outcome: `comparison_too_many: ${plano.codes.length}`,
    });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      comparison: true,
      warning: `A pergunta compara ${plano.codes.length} códigos, acima do limite de ${MAX_CODIGOS_COMPARADOS} por consulta. Divida em consultas menores para a resposta continuar conferível.`,
    });
  }
  if (plano.status === "ready" && plano.incomplete) {
    // Sem evidência para um dos códigos não há diferença, vencedor nem
    // percentual — e o modelo só poderia errar isso (SYN16–SYN18 mostravam
    // o provedor chamado à toa). Fim determinístico, com os trechos na tela.
    const faltantes = plano.blocks.filter((b) => b.missing).map((b) => b.code);
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null,
      outcome: `comparison_incomplete: ${faltantes.join(",")}`,
    });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      comparison: true,
      warning: avisoComparacaoIncompleta(faltantes, faltantes.length === plano.blocks.length),
    });
  }

  // ── provedor ──────────────────────────────────────────────
  const provider = deps.resolveProvider();
  if (!provider) {
    registrar({
      query: input.query, evidencesRetrieved: rows.length, evidencesSent: 0,
      provider: null, model: null, durationMs: null, outcome: "no_provider",
    });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      warning: "A síntese automática não está configurada neste ambiente. Os trechos encontrados estão abaixo.",
    });
  }

  // Cada linha leva a referência que o modelo deve escrever ao lado do
  // número: o derivado só é aceito no parágrafo que cita as evidências de
  // origem, e o modelo não tem como adivinhar quais são.
  const calculos = plano.status === "ready"
    ? plano.derived.map((d) => renderCalculation(d, citacoes))
    : [];

  let texto: string;
  let meta: { provider: string; model: string; durationMs: number };
  try {
    const saida = await provider.generate({
      question: input.query,
      evidence: aceitas,
      systemPrompt: SYSTEM_PROMPT,
      userMessage: buildUserMessage(input.query, aceitas, calculos),
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
      citations: citacoesDaTela,
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
      citations: citacoesDaTela,
      mode: "extractive",
      comparison: plano.status === "ready" || undefined,
      warning: validacao.kind === "comparison"
        ? "A resposta gerada misturou valores entre os produtos comparados e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : validacao.kind === "completeness"
        ? "A resposta gerada não listava todos os valores pedidos e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : validacao.kind === "association"
        ? "A resposta gerada ligava valores de linhas diferentes da tabela e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : "A resposta gerada não passou na conferência e foi descartada. Os trechos encontrados estão abaixo.",
    });
  }

  registrar({
    query: input.query, evidencesRetrieved: rows.length, evidencesSent: aceitas.length,
    provider: meta.provider, model: meta.model, durationMs: meta.durationMs, outcome: "answered",
  });

  return base({
    answer: texto.trim(),
    citations: citacoesDaTela,
    mode: "synthesized",
    comparison: plano.status === "ready" || undefined,
    warning: avaliacao.dropped.length > 0
      ? `${avaliacao.dropped.length} trecho(s) recuperado(s) ficaram fora da síntese.`
      : undefined,
  });
}
