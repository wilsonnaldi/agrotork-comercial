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
  | "model_invalid"
  | "key_missing"
  | "key_invalid";

export const PROVIDER_CONFIG_REASONS = [
  "provider_missing",
  "provider_disabled",
  "provider_unsupported",
  "model_missing",
  "model_invalid",
  "key_missing",
  "key_invalid",
] as const satisfies readonly ProviderConfigReason[];

export type ProviderConfig =
  | { configured: true; provider: SupportedProvider; model: string }
  | { configured: false; reason: ProviderConfigReason };

const limpo = (v: string | undefined): string => (typeof v === "string" ? v.trim() : "");

/**
 * Forma de identificador de modelo ("claude-sonnet-4.5", "claude-x@2026",
 * "anthropic.claude-v2:1"). Achado da revisão adversarial (S1, 26/09): o
 * modelo era aceito como veio e LOGADO em todo evento `[brain.synthesis]` —
 * a chave colada em `BRAIN_LLM_MODEL` virava `"model":"sk-ant-…"` no log da
 * Netlify, e o preflight ainda dizia PRONTO. Agora o modelo tem de ter cara
 * de identificador, e o prefixo de chave (`sk-`) é recusado mesmo cabendo
 * na forma. O valor recusado não volta no resultado.
 */
const MODELO_VALIDO = /^[a-z0-9][a-z0-9._:@-]{0,99}$/i;
const PREFIXO_DE_CHAVE = /^sk-/i;

/**
 * A chave vai crua para o cabeçalho `x-api-key`. Com espaço interno,
 * quebra de linha, caractere de controle ou não-ASCII (ZWSP colado junto,
 * "ç", "€"), o undici recusa o cabeçalho, e isso aparecia como erro de REDE
 * em toda consulta (S2, 26/09) — o operador procuraria o problema no lugar
 * errado. Só ASCII visível (0x21–0x7E) passa; o resto é `key_invalid`, dito
 * na configuração, antes de qualquer chamada.
 */
const CHAVE_VALIDA = /^[\x21-\x7E]+$/;

/**
 * Lê as três variáveis e diz se a síntese pode ser ligada.
 *
 * Ordem das conferências: provedor → modelo (ausente → inválido) → chave
 * (ausente → inválida). A chave vem por último para uma configuração ainda
 * sem chave (o Preview, por exemplo) já validar o resto: o preflight aponta
 * `key_missing` só quando provedor e modelo estão certos. Configuração pela
 * metade é o mesmo que nada — nunca uma tentativa às cegas.
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
  // O modelo vai ao log; o que não tem forma de identificador não vai, nem
  // volta aqui (pode ser a chave colada na variável errada).
  if (!MODELO_VALIDO.test(modelo) || PREFIXO_DE_CHAVE.test(modelo)) {
    return { configured: false, reason: "model_invalid" };
  }

  // A chave é só conferida (existe, não é espaço, é ASCII visível); o valor
  // não sai daqui.
  const chave = limpo(env[PROVIDER_ENV.apiKey]);
  if (chave === "") return { configured: false, reason: "key_missing" };
  if (!CHAVE_VALIDA.test(chave)) return { configured: false, reason: "key_invalid" };

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
    case "model_invalid":
      return `${PROVIDER_ENV.model} fora do formato de identificador de modelo (letras, dígitos e . _ : @ -, até 100 caracteres, sem o prefixo de chave sk-): confira se não é a chave colada no lugar errado.`;
    case "key_missing":
      return `${PROVIDER_ENV.apiKey} ausente ou vazia: cadastre a chave no painel, só no escopo de servidor.`;
    case "key_invalid":
      return `${PROVIDER_ENV.apiKey} com espaço interno, quebra de linha ou caractere fora do ASCII visível: cole a chave de novo, sem nada em volta.`;
  }
}
