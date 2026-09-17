import "server-only";

import { AnthropicProvider } from "./anthropic";
import type { BrainLlmProvider } from "./provider";

export type { BrainLlmProvider, GenerateInput, GenerateOutput } from "./provider";
export { ProviderError } from "./provider";

/**
 * De onde sai o provedor. Três variáveis, todas do SERVIDOR (sem
 * `NEXT_PUBLIC_`, que é o que faria a chave vazar para o navegador):
 *
 *   BRAIN_LLM_PROVIDER   anthropic | none     (padrão: none)
 *   BRAIN_LLM_API_KEY    a chave
 *   BRAIN_LLM_MODEL      o identificador do modelo
 *
 * Sem chave, `resolveProvider()` devolve `null` e a síntese não acontece —
 * o console cai na resposta extractiva, com as evidências inteiras. Isso é o
 * CREDENTIAL GATE: o caminho está pronto e desligado, e desligado ele não
 * mente. Nenhuma credencial é inventada aqui, e nenhuma é escrita em log.
 */
export function resolveProvider(): BrainLlmProvider | null {
  const escolhido = (process.env.BRAIN_LLM_PROVIDER ?? "none").trim().toLowerCase();
  if (escolhido === "none" || escolhido === "") return null;

  if (escolhido === "anthropic") {
    const chave = process.env.BRAIN_LLM_API_KEY?.trim();
    const modelo = process.env.BRAIN_LLM_MODEL?.trim();
    if (!chave || !modelo) return null;   // configuração pela metade é o mesmo que nada
    return new AnthropicProvider(chave, modelo);
  }

  // Provedor desconhecido não vira tentativa às cegas.
  return null;
}

/** Para a tela e para o relatório saberem por que não houve síntese. */
export function providerStatus(): { configured: boolean; provider: string } {
  const escolhido = (process.env.BRAIN_LLM_PROVIDER ?? "none").trim().toLowerCase();
  return { configured: resolveProvider() !== null, provider: escolhido };
}
