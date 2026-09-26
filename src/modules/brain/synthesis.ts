import "server-only";

import {
  assessEvidence,
  buildCitations,
  extractiveAnswer,
  mapCitationsToScreen,
  validateAnswer,
  type BrainNaturalAnswer,
} from "./answer";
import { isComparisonQuestion, MAX_CODIGOS_COMPARADOS, planComparison } from "./comparison";
import { assessExternalProcessing, parsePolicy, type EvidenceRef } from "./external-processing";
import { refusal, toEvidence, type KnowledgeEvidence, type KnowledgeHitRow } from "./evidence";
import { TIMEOUT_PROVIDER_MS } from "./limits";
import { resolveProvider } from "./llm";
import { ProviderError, type BrainLlmProvider } from "./llm/provider";
import { codesForLog, type GenerationEvent, type GenerationOutcome, type GenerationReason } from "./observability";
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

/**
 * Diagnóstico da geração: UMA linha por consulta, no log do servidor, nunca
 * no cliente. Log de servidor é suficiente na v1 — a busca já tem trilha em
 * `brain.knowledge_queries`, e uma tabela nova para a geração exigiria
 * migration sem necessidade provada. O prefixo `[brain.synthesis]` fica, para
 * os filtros de log que já existem. O que o evento leva, e por que a pergunta
 * NÃO vai mais, está em `observability.ts`.
 */
function registrar(evento: GenerationEvent) {
  console.info("[brain.synthesis]", JSON.stringify(evento));
}

/** O que muda de um desfecho para outro; o resto o evento calcula sozinho. */
type Desfecho = {
  outcome: GenerationOutcome;
  reason?: GenerationReason;
  codes?: string[];
  evidencesSent?: number;
  provider?: string | null;
  model?: string | null;
  durationMs?: number | null;
};

/**
 * O aviso da comparação sem um dos lados. Os códigos vêm da PERGUNTA, então
 * repeti-los não revela nada; "não encontrei … nesta consulta" vale igual
 * para documento inexistente e para documento que esta pessoa não pode ver
 * — as duas situações têm de ser indistinguíveis. Nenhuma sugestão de código
 * parecido, pelo mesmo motivo.
 */
function lista(codigos: string[]): string {
  return codigos.length === 1
    ? codigos[0]!
    : `${codigos.slice(0, -1).join(", ")} e ${codigos[codigos.length - 1]}`;
}

/**
 * Dois motivos, ditos separados (revisão de 25/09): o código que NENHUMA
 * evidência traz ("não encontrei documentação") e o que está documentado
 * mas sem valor no ponto ou na unidade pedidos ("não encontrei o valor …
 * a 45 psi"). Juntá-los dizia "não encontrei documentação para MJ981CAP"
 * com a tabela da MJ981CAP logo abaixo. O segundo motivo só cita o ponto
 * que a própria pergunta fixou, então também não revela nada.
 */
function avisoComparacaoIncompleta(
  semDocumentacao: string[],
  semValor: string[],
  pontoPedido: string | null,
  todosFaltam: boolean,
): string {
  const motivos: string[] = [];
  if (semDocumentacao.length > 0) {
    motivos.push(`não encontrei documentação para ${lista(semDocumentacao)} nesta consulta`);
  }
  if (semValor.length > 0) {
    motivos.push(
      `não encontrei, nos trechos encontrados, o valor pedido para ${lista(semValor)}` +
        (pontoPedido ? ` no ponto ${pontoPedido}` : ""),
    );
  }
  return `Não dá para concluir a comparação: ${motivos.join("; ")}. ` +
    (todosFaltam
      ? "Os trechos encontrados estão abaixo, na íntegra."
      : "Os trechos encontrados para os demais códigos estão abaixo, na íntegra.");
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
  // O selo "Comparação" sai só do TEXTO da pergunta, antes de qualquer gate:
  // não lê evidência, política nem provedor, então pode valer igual em todo
  // caminho que devolve resposta sem revelar nada do que existe na memória.
  // Antes ele dependia do plano (declarado depois do gate externo) e sumia
  // no gate externo, sem provedor e no erro do provedor.
  const pedeComparacao = isComparisonQuestion(input.query);
  const inicio = Date.now();

  const rows: KnowledgeHitRow[] = await deps.search(input);
  const evidencias: KnowledgeEvidence[] = rows.map((r) => toEvidence(r, opts.isAdmin));

  // Contagens do Evidence Gate, preenchidas assim que ele roda. Antes dele
  // não há desfecho possível, então nenhum evento sai com elas por preencher.
  let aceitasN = 0;
  let descartadasN = 0;
  const desfecho = (d: Desfecho) =>
    registrar({
      event: "brain.synthesis",
      outcome: d.outcome,
      ...(d.reason ? { reason: d.reason } : {}),
      comparison: pedeComparacao,
      queryLength: input.query.length,
      evidencesRetrieved: rows.length,
      evidencesAccepted: aceitasN,
      evidencesDropped: descartadasN,
      evidencesSent: d.evidencesSent ?? 0,
      provider: d.provider ?? null,
      model: d.model ?? null,
      durationMs: d.durationMs ?? null,
      totalMs: Date.now() - inicio,
      ...(d.codes ? { codes: codesForLog(d.codes) } : {}),
    });

  const base = (extra: Partial<BrainNaturalAnswer>): BrainNaturalAnswer => ({
    query: input.query,
    status: "answered",
    evidence: evidencias,
    comparison: pedeComparacao || undefined,
    ...extra,
  });

  // ── Evidence Gate ─────────────────────────────────────────
  const avaliacao = assessEvidence(input.query, evidencias);
  aceitasN = avaliacao.accepted.length;
  descartadasN = avaliacao.dropped.length;
  if (!avaliacao.sufficient) {
    desfecho({ outcome: "no_evidence", reason: avaliacao.gateReason ?? "none_passed_gate" });
    // Se o retrieval trouxe algo mas o gate recusou tudo, as evidências
    // continuam na tela: o usuário decide se aquilo serve para ele.
    return { ...refusal(input.query, "no_evidence"), evidence: evidencias, mode: "none" };
  }

  const aceitas = avaliacao.accepted;
  const citacoes = buildCitations(aceitas);
  const citacoesMapeadas = mapCitationsToScreen(citacoes, aceitas, evidencias);
  if (citacoesMapeadas === null) {
    // Invariante quebrada: uma aceita que não está entre as evidências da
    // tela. Na cadeia de hoje é inalcançável (as aceitas saem de
    // `evidencias`), e é justamente por isso que não se tenta remendar: sem
    // citação confiável não há citação nenhuma, e nada segue para o gate
    // externo nem para o provedor. O aviso é genérico — sem id, sem pilha.
    desfecho({ outcome: "internal_error", reason: "citation_mapping" });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: [],
      mode: "extractive",
      warning: "Não foi possível montar as citações desta resposta com segurança. Os trechos encontrados estão abaixo, na íntegra.",
    });
  }
  const citacoesDaTela = citacoesMapeadas;

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
    desfecho({ outcome: "external_processing_forbidden" });
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
    // Os códigos vêm da pergunta e já estão no aviso da tela.
    desfecho({ outcome: "comparison_too_many", codes: plano.codes });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      warning: `A pergunta compara ${plano.codes.length} códigos, acima do limite de ${MAX_CODIGOS_COMPARADOS} por consulta. Divida em consultas menores para a resposta continuar conferível.`,
    });
  }
  if (plano.status === "ready" && plano.incomplete) {
    // Sem evidência para um dos códigos não há diferença, vencedor nem
    // percentual — e o modelo só poderia errar isso (SYN16–SYN18 mostravam
    // o provedor chamado à toa). Fim determinístico, com os trechos na tela.
    const faltantes = plano.blocks.filter((b) => b.missing);
    const semDocumentacao = faltantes.filter((b) => !b.documented).map((b) => b.code);
    const semValor = faltantes.filter((b) => b.documented).map((b) => b.code);
    const pontoPedido = plano.spec.pinned.length > 0
      ? plano.spec.pinned.map((p) => `${p.numero} ${p.unidade}`).join(" e ")
      : null;
    desfecho({ outcome: "comparison_incomplete", codes: faltantes.map((b) => b.code) });
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      warning: avisoComparacaoIncompleta(semDocumentacao, semValor, pontoPedido, faltantes.length === plano.blocks.length),
    });
  }

  // ── provedor ──────────────────────────────────────────────
  const provider = deps.resolveProvider();
  if (!provider) {
    desfecho({ outcome: "no_provider" });
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
    // Só a CATEGORIA: a mensagem do erro pode repetir o prompt ou a chave.
    desfecho({
      outcome: "provider_error", reason: tipo, evidencesSent: aceitas.length,
      provider: provider.name, model: provider.model,
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
      desfecho({
        outcome: "model_refusal", evidencesSent: aceitas.length,
        provider: meta.provider, model: meta.model, durationMs: meta.durationMs,
      });
      return { ...refusal(input.query, "no_evidence"), evidence: evidencias, mode: "none" };
    }

    // Só QUAL trava reprovou. O detalhe (`problem`/`details`) cita o texto do
    // modelo e valores do documento — conteúdo, que não vai para o log.
    desfecho({
      outcome: "answer_rejected", reason: validacao.kind, evidencesSent: aceitas.length,
      provider: meta.provider, model: meta.model, durationMs: meta.durationMs,
    });
    // Não se limpa uma alucinação em silêncio: a resposta é descartada
    // inteira e o usuário recebe a matéria-prima, que é verificável. Um
    // número trocado NÃO vira número certo aqui — vira resposta descartada.
    return base({
      answer: extractiveAnswer(aceitas),
      citations: citacoesDaTela,
      mode: "extractive",
      warning: validacao.kind === "comparison"
        ? "A resposta gerada misturou valores entre os produtos comparados e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : validacao.kind === "completeness"
        ? "A resposta gerada não listava todos os valores pedidos e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : validacao.kind === "association"
        ? "A resposta gerada ligava valores de linhas diferentes da tabela e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : validacao.kind === "stance"
        ? "A resposta gerada opinava ou recomendava em vez de documentar e foi descartada. Os trechos encontrados estão abaixo, na íntegra."
        : "A resposta gerada não passou na conferência e foi descartada. Os trechos encontrados estão abaixo.",
    });
  }

  desfecho({
    outcome: "answered", evidencesSent: aceitas.length,
    provider: meta.provider, model: meta.model, durationMs: meta.durationMs,
  });

  return base({
    answer: texto.trim(),
    citations: citacoesDaTela,
    mode: "synthesized",
    warning: avaliacao.dropped.length > 0
      ? `${avaliacao.dropped.length} trecho(s) recuperado(s) ficaram fora da síntese.`
      : undefined,
  });
}
