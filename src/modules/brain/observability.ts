import type { EvidenceGateReason, ValidationProblem } from "./answer";
import type { ProviderConfigReason } from "./llm/config";
import type { ProviderErrorKind } from "./llm/provider";

/**
 * O evento de log da síntese — o contrato de observabilidade do Answer v1.
 *
 * PURO (sem `server-only`, sem I/O) para as suítes carregarem sem bundler e
 * conferirem a taxonomia contra a lista daqui, não contra uma cópia.
 *
 * Taxonomia FECHADA: `outcome` e `reason` são uniões de literais, e o que
 * não cabe nelas não é logado. Isso é o que permite contar por outcome em
 * produção sem que um texto livre (motivo da rejeição, mensagem de erro do
 * provedor, trecho da evidência) escorregue para o log e vire, na prática, um
 * canal de conteúdo fora do RLS.
 */

export const GENERATION_OUTCOMES = [
  "answered",
  "no_evidence",
  "external_processing_forbidden",
  "comparison_too_many",
  "comparison_incomplete",
  "no_provider",
  "provider_error",
  "model_refusal",
  "answer_rejected",
  "internal_error",
] as const;

export type GenerationOutcome = (typeof GENERATION_OUTCOMES)[number];

export type { EvidenceGateReason };

/**
 * Por que o outcome aconteceu, quando há mais de um motivo possível. Só
 * existe em `no_evidence` (motivo do Evidence Gate), `no_provider` (qual
 * parte da configuração falta — só o motivo, nunca o valor), `provider_error`
 * (categoria da falha), `answer_rejected` (qual trava reprovou — a recusa do
 * modelo tem outcome próprio) e `internal_error` (qual invariante quebrou).
 */
export type GenerationReason =
  | EvidenceGateReason
  | ProviderConfigReason
  | ProviderErrorKind
  | Exclude<ValidationProblem, "model_refusal">
  | "citation_mapping";

export const GENERATION_REASONS = [
  "none_retrieved", "none_passed_gate", "none_fit_context",
  "provider_missing", "provider_disabled", "provider_unsupported", "model_missing", "key_missing",
  "timeout", "auth", "rate_limit", "network", "invalid_response", "unknown",
  "grounding", "format", "completeness", "association", "comparison", "stance",
  "citation_mapping",
] as const satisfies readonly GenerationReason[];

/**
 * Trava de compilação: se `GenerationReason` ganhar um membro (um kind novo
 * no validador, uma categoria nova no provedor) e a lista acima não, o tipo
 * deste valor vira `false` e o `typecheck` quebra aqui — a lista que os testes
 * usam nunca fica atrás do tipo.
 */
export const GENERATION_REASONS_COMPLETE: [Exclude<GenerationReason, (typeof GENERATION_REASONS)[number]>] extends [never]
  ? true
  : false = true;

/**
 * Forma de código de produto. Achado dos testes de privacidade (OBS4,
 * 26/09): o parser de código da pergunta aceita qualquer token com letra e
 * dígito — uma chave colada na pergunta ("sk-ant-api03-…") virava "código".
 * Código de produto é curto e sem espaço, barra ou ponto — o corpus de hoje
 * não passa de 12 caracteres. Sozinho, porém, é um filtro de FORMA: um CNPJ
 * de 14 dígitos ou um segredo curto digitado na pergunta passariam. Por isso
 * ele é só a segunda trava; a primeira é `comparisonCodesForLog`.
 */
const CODIGO_LOGAVEL = /^[A-Za-z0-9][A-Za-z0-9-]{0,15}$/;

export function codesForLog(codes: readonly string[]): string[] {
  return codes.filter((c) => CODIGO_LOGAVEL.test(c));
}

/** O que a comparação incompleta leva ao log sobre os códigos que faltaram. */
export type IncompleteCodesLog = {
  /** Faltantes que o corpus documenta: estão nos `codes` de uma evidência aceita. */
  codes: string[];
  /** Faltantes com documentação (código no catálogo ou no texto de uma aceita). */
  codesMissingDocumented: number;
  /** Faltantes sem documentação nenhuma — só existem na pergunta. */
  codesMissingUndocumented: number;
};

/**
 * Só vai ao log, POR NOME, o código faltante que o corpus conhece — que está
 * nos `codes` extraídos pela ingestão de alguma evidência aceita, onde preço,
 * telefone e CNPJ não entram (test_w29 do worker). O que só existe na
 * pergunta é texto livre de quem perguntou: pode ser um CNPJ, um número de
 * pedido, um pedaço de chave. Vira contagem. Código achado só no TEXTO da
 * evidência (`documented` sem estar no catálogo) também fica só na contagem:
 * o texto de um orçamento traz o CNPJ do cliente, e o log da Netlify está
 * fora do RLS. A forma (`codesForLog`) segue como segunda trava — o catálogo
 * de uma evidência malformada não passa uma chave ou um UUID adiante.
 */
export function comparisonCodesForLog(
  faltantes: readonly { code: string; documented: boolean }[],
  catalogo: readonly string[],
): IncompleteCodesLog {
  const conhecidos = new Set(catalogo.map((c) => c.toUpperCase()));
  const documentados = faltantes.filter((b) => b.documented);
  return {
    codes: codesForLog(documentados.map((b) => b.code).filter((c) => conhecidos.has(c.toUpperCase()))),
    codesMissingDocumented: documentados.length,
    codesMissingUndocumented: faltantes.length - documentados.length,
  };
}

/**
 * Sem `query`, de propósito (decisão de 26/09). A pergunta já é gravada por
 * `public.brain_search` em `brain.knowledge_queries`, sob RLS e com leitura só
 * de admin — é lá que se investiga uma pergunta individual. O log de função
 * da Netlify fica FORA do RLS, e este evento existe para agregação (contar
 * outcome, medir latência), não para depurar pergunta. Nem hash: pergunta
 * curta ("preço da MJ981CAP") se adivinha por força bruta. Fica o tamanho.
 *
 * Códigos de produto: em `comparison_too_many`, só a CONTAGEM
 * (`codesCount`); em `comparison_incomplete`, só os códigos que o CORPUS
 * documenta (`codes`) e a contagem do resto. Nenhum campo de texto livre: o
 * detalhe da rejeição fica no aviso da tela, não aqui.
 */
export type GenerationEvent = {
  event: "brain.synthesis";
  outcome: GenerationOutcome;
  reason?: GenerationReason;
  comparison: boolean;
  queryLength: number;
  evidencesRetrieved: number;
  evidencesAccepted: number;
  evidencesDropped: number;
  evidencesSent: number;
  provider: string | null;
  model: string | null;
  durationMs: number | null;
  totalMs: number;
  /** Só em `comparison_too_many`: quantos códigos a pergunta pedia. */
  codesCount?: number;
} & Partial<IncompleteCodesLog>;
