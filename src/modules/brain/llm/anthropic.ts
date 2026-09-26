import "server-only";

import type { BrainLlmProvider, GenerateInput, GenerateOutput } from "./provider";
import { ProviderError } from "./provider";

/**
 * Adapter da API de Mensagens da Anthropic. Sem SDK: uma chamada `fetch`,
 * porque é tudo o que a síntese precisa e uma dependência a menos é uma
 * superfície a menos.
 *
 * `server-only`: a chave nunca chega ao navegador. Ela é lida de
 * `BRAIN_LLM_API_KEY` no servidor, não é escrita em log nenhum e não aparece
 * em mensagem de erro — `ProviderError` carrega só a categoria da falha.
 * Ela viaja apenas no cabeçalho `x-api-key`, nunca no corpo.
 *
 * SEM PARÂMETRO DE AMOSTRAGEM. O corpo leva só `model`, `max_tokens`,
 * `system` e `messages`. Havia aqui um `temperature: 0`, com a justificativa
 * de que "síntese documental não é lugar de variedade" — a intenção estava
 * certa, o meio estava errado: no Claude Sonnet 5, `temperature`, `top_p` e
 * `top_k` em valor não-padrão são recusados com HTTP 400. Ou seja, aquele
 * zero não deixava a resposta mais estável; deixava a chamada impossível, e
 * a síntese cairia sempre no extractivo com um erro que parecia de rede.
 *
 * O que garante que a resposta não invente não é a temperatura: é o
 * `grounding.ts`, que confere cada número e cada código contra as evidências
 * citadas, e o `validateAnswer`, que barra o parágrafo sem lastro. Esses
 * conferem o texto DEPOIS de pronto, e por isso valem mais do que qualquer
 * ajuste de amostragem.
 */

const ENDPOINT = "https://api.anthropic.com/v1/messages";
const VERSAO_API = "2023-06-01";

export class AnthropicProvider implements BrainLlmProvider {
  readonly name = "anthropic";
  readonly model: string;
  // Campo privado NATIVO (`#`), não `private` do TypeScript: o `private` some
  // na compilação e a chave continuaria enumerável — `JSON.stringify(provider)`
  // ou um `console.log(provider)` a imprimiriam. O `#` não aparece em nenhum
  // dos dois.
  readonly #apiKey: string;
  private readonly maxTokens: number;

  constructor(apiKey: string, model: string, maxTokens = 1024) {
    this.#apiKey = apiKey;
    this.model = model;
    this.maxTokens = maxTokens;
  }

  async generate(input: GenerateInput): Promise<GenerateOutput> {
    const t0 = Date.now();
    const controle = new AbortController();
    const relogio = setTimeout(() => controle.abort(), input.timeoutMs);

    // O relógio só é desarmado no `finally`, DEPOIS de o corpo ser lido. Antes
    // ele era limpo assim que chegavam os cabeçalhos, e um provedor que
    // mandasse o cabeçalho e travasse no corpo deixava `resposta.json()`
    // pendurado sem teto nenhum. O mesmo AbortController cobre as duas fases.
    try {
      let resposta: Response;
      try {
        resposta = await fetch(ENDPOINT, {
          method: "POST",
          signal: controle.signal,
          headers: {
            "content-type": "application/json",
            "x-api-key": this.#apiKey,
            "anthropic-version": VERSAO_API,
          },
          body: JSON.stringify({
            // SÓ O NECESSÁRIO. Nada de `temperature`, `top_p`, `top_k`,
            // `thinking` ou `budget_tokens` — ver o bloco de comentário acima.
            model: this.model,
            max_tokens: this.maxTokens,
            system: input.systemPrompt,
            messages: [{ role: "user", content: input.userMessage }],
          }),
        });
      } catch (erro) {
        if (controle.signal.aborted || (erro instanceof Error && erro.name === "AbortError")) {
          throw new ProviderError("o provedor não respondeu a tempo", "timeout");
        }
        throw new ProviderError("não foi possível falar com o provedor", "network");
      }

      if (!resposta.ok) {
        // O corpo do erro pode repetir o prompt — e o prompt tem o conteúdo dos
        // documentos. Fica de fora: só a categoria sobe.
        const kind =
          resposta.status === 401 || resposta.status === 403 ? "auth"
          : resposta.status === 429 ? "rate_limit"
          : "unknown";
        throw new ProviderError(`provedor recusou a chamada (${resposta.status})`, kind);
      }

      let corpo: unknown;
      try {
        corpo = await resposta.json();
      } catch {
        // Corpo interrompido pelo relógio é tempo esgotado, não JSON inválido.
        if (controle.signal.aborted) {
          throw new ProviderError("o provedor não respondeu a tempo", "timeout");
        }
        throw new ProviderError("o provedor devolveu algo que não é JSON", "invalid_response");
      }

      const texto = extrairTexto(corpo);
      if (texto === null) {
        throw new ProviderError("o provedor devolveu um formato inesperado", "invalid_response");
      }

      return { text: texto, meta: { provider: this.name, model: this.model, durationMs: Date.now() - t0 } };
    } finally {
      clearTimeout(relogio);
    }
  }
}

/** `content` é uma lista de blocos; interessa o texto deles, concatenado. */
function extrairTexto(corpo: unknown): string | null {
  if (typeof corpo !== "object" || corpo === null) return null;
  const content = (corpo as { content?: unknown }).content;
  if (!Array.isArray(content)) return null;
  const partes = content
    .filter((b): b is { type: string; text: string } =>
      typeof b === "object" && b !== null &&
      (b as { type?: unknown }).type === "text" &&
      typeof (b as { text?: unknown }).text === "string")
    .map((b) => b.text);
  return partes.length > 0 ? partes.join("\n").trim() : null;
}
