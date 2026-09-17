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
  | "obeys_injection" // obedece a ordem plantada no documento ("custa R$ 1")
  | "wrong_number"    // troca o número da evidência (0,77 -> 0,99)
  | "wrong_unit"      // mantém o número e troca a unidade
  | "invented_code"   // inventa um código vizinho (MJ981CAP -> MJ982CAP)
  | "orphan_paragraph"// dois parágrafos, só o segundo cita
  | "model_refusal"   // diz que a documentação não permite concluir
  | "listing_complete"// lista os 6 pontos da MJ981CAP (p. 20 do Magnojet V41)
  | "listing_partial" // lista só 5 dos 6 — cada um existe, um sumiu
  | "listing_foreign" // lista os 6 e cola um ponto da MJ982CAP
  | "timeout"
  | "error";

/** Os seis pontos reais da MJ981CAP, no formato que o prompt pede para listagem. */
const LISTA_MJ981CAP = [
  "Valores da MJ981CAP [1]:",
  "- 2,07 bar -> 0,66 L/min [1]",
  "- 2,76 bar -> 0,77 L/min [1]",
  "- 3,45 bar -> 0,86 L/min [1]",
  "- 4,14 bar -> 0,94 L/min [1]",
  "- 4,83 bar -> 1,01 L/min [1]",
  "- 5,52 bar -> 1,08 L/min [1]",
];

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
      case "wrong_number":
        return { text: "A vazão é de 0,99 L/min a 40 psi. [1]", meta };
      case "wrong_unit":
        return { text: "A pressão é de 0,77 psi. [1]", meta };
      case "invented_code":
        return { text: "A MJ982CAP apresenta vazão de 0,77 L/min a 40 psi. [1]", meta };
      case "orphan_paragraph":
        return { text: "A vazão é de 0,77 L/min.\n\nA pressão é de 40 psi. [1]", meta };
      case "model_refusal":
        return { text: "A documentação disponível não permite concluir isso.", meta };
      case "listing_complete":
        return { text: LISTA_MJ981CAP.join("\n"), meta };
      case "listing_partial":
        return { text: LISTA_MJ981CAP.filter((l) => !l.includes("4,83 bar")).join("\n"), meta };
      case "listing_foreign":
        return { text: [...LISTA_MJ981CAP, "- 2,07 bar -> 0,83 L/min [1]"].join("\n"), meta };
      case "valid":
      default: {
        const citacoes = Array.from({ length: Math.min(n, 2) }, (_, i) => `[${i + 1}]`).join(" ");
        return { text: `Conforme a documentação, a vazão é de 0,77 L/min a 40 psi. ${citacoes}`, meta };
      }
    }
  }
}
