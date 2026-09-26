import type { EvidenceGateReason, ValidationProblem } from "./answer";
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
 * existe em `no_evidence` (motivo do Evidence Gate), `provider_error`
 * (categoria da falha), `answer_rejected` (qual trava reprovou — a recusa do
 * modelo tem outcome próprio) e `internal_error` (qual invariante quebrou).
 */
export type GenerationReason =
  | EvidenceGateReason
  | ProviderErrorKind
  | Exclude<ValidationProblem, "model_refusal">
  | "citation_mapping";

export const GENERATION_REASONS = [
  "none_retrieved", "none_passed_gate", "none_fit_context",
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
 * Sem `query`, de propósito (decisão de 26/09). A pergunta já é gravada por
 * `public.brain_search` em `brain.knowledge_queries`, sob RLS e com leitura só
 * de admin — é lá que se investiga uma pergunta individual. O log de função
 * da Netlify fica FORA do RLS, e este evento existe para agregação (contar
 * outcome, medir latência), não para depurar pergunta. Nem hash: pergunta
 * curta ("preço da MJ981CAP") se adivinha por força bruta. Fica o tamanho.
 *
 * `codes` só em `comparison_too_many`/`comparison_incomplete`, e só códigos
 * tirados da PERGUNTA — os mesmos que o aviso já mostra a quem perguntou.
 * Nenhum campo de texto livre: o detalhe da rejeição fica no aviso da tela,
 * não aqui.
 */
/**
 * Os códigos que o evento pode levar. Achado dos testes de privacidade
 * (OBS4, 26/09): o parser de código da pergunta aceita qualquer token com
 * letra e dígito — uma chave colada na pergunta ("sk-ant-api03-…") virava
 * "código" e, numa comparação incompleta, ia parar em `codes`. O aviso da
 * tela pode repeti-la (é a pergunta da própria pessoa); o log, que fica fora
 * do RLS, não. Código de produto é curto e sem espaço, barra ou ponto — o
 * corpus de hoje não passa de 12 caracteres —, então o log só aceita essa
 * forma. Chave, UUID, caminho e URL ficam de fora pelo tamanho ou pelo
 * caractere. É um filtro de forma, não de conteúdo: um número de 16 dígitos
 * digitado na pergunta ainda passaria.
 */
const CODIGO_LOGAVEL = /^[A-Za-z0-9][A-Za-z0-9-]{0,15}$/;

export function codesForLog(codes: readonly string[]): string[] {
  return codes.filter((c) => CODIGO_LOGAVEL.test(c));
}

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
  codes?: string[];
};
