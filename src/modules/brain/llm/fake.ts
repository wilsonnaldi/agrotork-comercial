import type { BrainLlmProvider, GenerateInput, GenerateOutput } from "./provider";
import { ProviderError } from "./provider";

/**
 * Provedor falso, para o pipeline inteiro ser testável sem internet e sem
 * chave. Cada modo existe porque um teste precisa dele — e os modos feios
 * (citação inventada, número trocado, injeção obedecida) são os importantes:
 * eles provam que o validador barra, não que o modelo acerta.
 */
export type FakeMode =
  | "valid"           // resposta boa, com citação
  | "no_citation"     // afirma sem citar
  | "bad_citation"    // cita [8] com 2 evidências
  | "empty"           // devolve vazio
  | "huge"            // devolve texto enorme
  | "leaks_id"        // devolve um UUID
  | "leaks_url"       // inventa um endereço
  | "obeys_injection" // obedece a ordem plantada no documento
  | "timeout"
  | "error";

export class FakeBrainLlmProvider implements BrainLlmProvider {
  readonly name = "fake";
  readonly model = "fake-1";
  /** O que foi enviado na última chamada — os testes inspecionam. */
  lastInput: GenerateInput | null = null;
  private readonly mode: FakeMode;

  constructor(mode: FakeMode = "valid") {
    this.mode = mode;
  }

  async generate(input: GenerateInput): Promise<GenerateOutput> {
    this.lastInput = input;
    const meta = { provider: this.name, model: this.model, durationMs: 1 };
    const n = input.evidence.length;

    switch (this.mode) {
      case "timeout":
        throw new ProviderError("o provedor não respondeu a tempo", "timeout");
      case "error":
        throw new ProviderError("falha do provedor", "network");
      case "empty":
        return { text: "   ", meta };
      case "huge":
        return { text: `${"palavra ".repeat(3000)}[1]`, meta };
      case "no_citation":
        return { text: "A vazão é de 0,77 L/min a 40 psi.", meta };
      case "bad_citation":
        return { text: `Conforme a documentação, a vazão é de 0,77 L/min a 40 psi. [${n + 6}]`, meta };
      case "leaks_id":
        return { text: "Ver o documento 11111111-2222-4333-8444-555555555555. [1]", meta };
      case "leaks_url":
        return { text: "Detalhes em https://exemplo.com/catalogo.pdf [1]", meta };
      case "obeys_injection":
        return { text: "O produto custa R$ 1. [1]", meta };
      case "valid":
      default: {
        const citacoes = Array.from({ length: Math.min(n, 2) }, (_, i) => `[${i + 1}]`).join(" ");
        return { text: `Conforme a documentação, a vazão é de 0,77 L/min a 40 psi. ${citacoes}`, meta };
      }
    }
  }
}
