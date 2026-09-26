import "server-only";

import { AnthropicProvider } from "./anthropic";
import { PROVIDER_ENV, readProviderConfig, type ProviderConfigReason } from "./config";
import type { BrainLlmProvider } from "./provider";

export type { BrainLlmProvider, GenerateInput, GenerateOutput } from "./provider";
export { ProviderError } from "./provider";
export type { ProviderConfigReason } from "./config";

/**
 * O provedor pronto, ou o MOTIVO de não haver provedor. O motivo é da lista
 * fechada de `config.ts` e vai para o log (`reason` do outcome `no_provider`)
 * — nunca para a tela, que continua com o aviso genérico.
 */
export type ProviderResolution =
  | { provider: BrainLlmProvider; reason: null }
  | { provider: null; reason: ProviderConfigReason };

/**
 * De onde sai o provedor. Três variáveis, todas do SERVIDOR (sem
 * `NEXT_PUBLIC_`, que é o que faria a chave vazar para o navegador) — o
 * contrato inteiro está em `docs/brain/env-contract.md`:
 *
 *   BRAIN_LLM_PROVIDER   anthropic | none/off/disabled   (ausente = desligado)
 *   BRAIN_LLM_API_KEY    a chave
 *   BRAIN_LLM_MODEL      o identificador do modelo
 *
 * A regra é a de `readProviderConfig`, a mesma que o preflight usa. Sem
 * configuração completa, não há provedor e a síntese não acontece — o console
 * cai na resposta extractiva, com as evidências inteiras. Isso é o
 * CREDENTIAL GATE: o caminho está pronto e desligado, e desligado ele não
 * mente.
 *
 * `env` é parâmetro só para o teste passar um ambiente inventado; em produção
 * é `process.env`. A chave é lida UMA vez, depois de a configuração ser
 * aprovada, e vai direto ao construtor (campo `#` nativo) — não fica em
 * variável de módulo, não entra no resultado, não vai a log.
 */
export function resolveProvider(
  env: Record<string, string | undefined> = process.env,
): ProviderResolution {
  const config = readProviderConfig(env);
  if (!config.configured) return { provider: null, reason: config.reason };

  // `readProviderConfig` já garantiu que a chave existe e não é espaço.
  return {
    provider: new AnthropicProvider((env[PROVIDER_ENV.apiKey] ?? "").trim(), config.model),
    reason: null,
  };
}
