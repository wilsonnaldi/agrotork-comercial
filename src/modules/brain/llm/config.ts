/**
 * O CONTRATO de configuração do provedor de síntese, como função pura.
 *
 * Sem `server-only` e sem tocar `process.env` aqui dentro, de propósito: quem
 * chama passa o ambiente. Assim a mesma regra vale no servidor
 * (`resolveProvider`), no preflight manual (`npm run brain:preflight`) e nos
 * testes, que passam um ambiente inventado — e nenhum dos três precisa de uma
 * chave de verdade para provar que a regra funciona.
 *
 * O resultado NUNCA carrega a chave, nem o valor cru do provedor: alguém pode
 * ter colado a chave na variável errada, e o motivo de uma configuração
 * recusada acaba em tela, em log e em relatório. Só vão os NOMES das
 * variáveis e um motivo de uma lista fechada.
 */

export const PROVIDER_ENV = {
  provider: "BRAIN_LLM_PROVIDER",
  apiKey: "BRAIN_LLM_API_KEY",
  model: "BRAIN_LLM_MODEL",
} as const;

export const SUPPORTED_PROVIDERS = ["anthropic"] as const;
export type SupportedProvider = (typeof SUPPORTED_PROVIDERS)[number];

/** Valores que DESLIGAM a síntese de propósito — o rollback documentado. */
export const DISABLED_VALUES = ["none", "off", "disabled"] as const;

export type ProviderConfigReason =
  | "provider_missing"
  | "provider_disabled"
  | "provider_unsupported"
  | "model_missing"
  | "key_missing";

export const PROVIDER_CONFIG_REASONS = [
  "provider_missing",
  "provider_disabled",
  "provider_unsupported",
  "model_missing",
  "key_missing",
] as const satisfies readonly ProviderConfigReason[];

export type ProviderConfig =
  | { configured: true; provider: SupportedProvider; model: string }
  | { configured: false; reason: ProviderConfigReason };

const limpo = (v: string | undefined): string => (typeof v === "string" ? v.trim() : "");

/**
 * Lê as três variáveis e diz se a síntese pode ser ligada.
 *
 * Ordem das conferências: provedor → modelo → chave. A chave vem por último
 * para uma configuração ainda sem chave (o Preview, por exemplo) já validar
 * o resto: o preflight aponta `key_missing` só quando provedor e modelo estão
 * certos. Configuração pela metade é o mesmo que nada — nunca uma tentativa
 * às cegas.
 */
export function readProviderConfig(env: Record<string, string | undefined>): ProviderConfig {
  const provedor = limpo(env[PROVIDER_ENV.provider]).toLowerCase();
  if (provedor === "") return { configured: false, reason: "provider_missing" };
  if ((DISABLED_VALUES as readonly string[]).includes(provedor)) {
    return { configured: false, reason: "provider_disabled" };
  }
  // O valor recusado não volta no resultado: pode ser a chave colada no lugar
  // errado.
  if (!(SUPPORTED_PROVIDERS as readonly string[]).includes(provedor)) {
    return { configured: false, reason: "provider_unsupported" };
  }

  const modelo = limpo(env[PROVIDER_ENV.model]);
  if (modelo === "") return { configured: false, reason: "model_missing" };

  // A chave é só conferida (existe e não é espaço); o valor não sai daqui.
  if (limpo(env[PROVIDER_ENV.apiKey]) === "") return { configured: false, reason: "key_missing" };

  return { configured: true, provider: provedor as SupportedProvider, model: modelo };
}

/**
 * A frase de cada motivo, para o preflight e para quem opera o deploy. Só
 * nomes de variável e valores ACEITOS — nunca o valor que foi recusado.
 * (O aviso da tela de consulta continua genérico: quem pergunta não precisa
 * saber qual variável falta, e não deve.)
 */
export function providerConfigMessage(reason: ProviderConfigReason): string {
  switch (reason) {
    case "provider_missing":
      return `${PROVIDER_ENV.provider} ausente ou vazia: a síntese fica desligada e o BRAIN responde de forma extractiva.`;
    case "provider_disabled":
      return `${PROVIDER_ENV.provider} desliga a síntese de propósito (${DISABLED_VALUES.join("/")}): resposta extractiva.`;
    case "provider_unsupported":
      return `${PROVIDER_ENV.provider} com valor não suportado. Aceitos: ${SUPPORTED_PROVIDERS.join(", ")}.`;
    case "model_missing":
      return `${PROVIDER_ENV.model} ausente ou vazia: informe o identificador do modelo.`;
    case "key_missing":
      return `${PROVIDER_ENV.apiKey} ausente ou vazia: cadastre a chave no painel, só no escopo de servidor.`;
  }
}
