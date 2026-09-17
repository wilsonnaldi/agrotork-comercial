import type { KnowledgeEvidence } from "../evidence";

/**
 * A interface do provedor de síntese. O BRAIN não conhece SDK nenhum: ele
 * conhece isto. Trocar de fornecedor é escrever outro adapter, não mexer no
 * serviço — e os testes rodam com um provedor falso, sem internet.
 */

export type GenerateInput = {
  question: string;
  evidence: KnowledgeEvidence[];
  systemPrompt: string;
  userMessage: string;
  timeoutMs: number;
};

export type GenerateOutput = {
  text: string;
  /** Para o log de diagnóstico. Nunca inclui chave nem prompt integral. */
  meta: { provider: string; model: string; durationMs: number };
};

export interface BrainLlmProvider {
  readonly name: string;
  readonly model: string;
  generate(input: GenerateInput): Promise<GenerateOutput>;
}

export type ProviderErrorKind =
  | "timeout" | "auth" | "rate_limit" | "network" | "invalid_response" | "unknown";

/**
 * Falha do provedor. Nunca carrega corpo de resposta nem cabeçalho — só a
 * categoria, porque o corpo do erro costuma repetir o prompt, e o prompt tem
 * o conteúdo dos documentos.
 *
 * Campos atribuídos no corpo do construtor, e não como parâmetro-propriedade,
 * porque os testes rodam com o `--experimental-strip-types` do Node, que
 * remove tipos sem transpilar e não entende aquela forma.
 */
export class ProviderError extends Error {
  readonly kind: ProviderErrorKind;

  constructor(message: string, kind: ProviderErrorKind) {
    super(message);
    this.name = "ProviderError";
    this.kind = kind;
  }
}
