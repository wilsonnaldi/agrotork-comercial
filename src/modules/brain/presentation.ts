import { pareceCodigo } from "./grounding";

/**
 * Apresentação do console do BRAIN. PURO: sem React, sem banco, sem rede —
 * dá para exercitar sozinho (`supabase/db-tests/check-brain-ui.mjs`).
 *
 * A regra que organiza o arquivo: **isto é renderização, não transformação.**
 * O texto que chega aqui já passou pelo grounding, pela exaustão e pela
 * associação. Nada aqui pode apagar lastro: nenhum marcador [n] some,
 * nenhum número muda, nenhuma linha é resumida. O que este arquivo faz é
 * dizer ONDE cada pedaço entra na tela.
 *
 * A única troca de caractere permitida é a seta ASCII "->" pela seta "→"
 * (`formatarSetas`), e ela só acontece entre espaços, longe de número e de
 * unidade. É estética de leitura; o conteúdo conferido continua o mesmo.
 */

export type BlocoDeResposta =
  /** Linha de abertura de uma lista: "Vazões da MJ981CAP por pressão em bar [1]:" */
  | { tipo: "lead"; texto: string }
  /** Item de lista, sem o marcador ("- ", "• ", "1. ") que veio do modelo. */
  | { tipo: "item"; texto: string }
  | { tipo: "paragrafo"; texto: string };

const MARCADOR_DE_ITEM = /^\s*(?:[-–—*•]|\d{1,2}[.)])\s+/;

/**
 * Quebra a resposta em blocos para a tela. Conservador: linha que não é
 * item de lista continua parágrafo, e o texto de cada bloco é o original,
 * com os marcadores [n] onde o modelo os escreveu.
 */
export function parseAnswer(texto: string): BlocoDeResposta[] {
  const blocos: BlocoDeResposta[] = [];
  const linhas = texto.split(/\r?\n/);

  linhas.forEach((bruta, i) => {
    const linha = bruta.trim();
    if (linha.length === 0) return;

    if (MARCADOR_DE_ITEM.test(linha)) {
      blocos.push({ tipo: "item", texto: linha.replace(MARCADOR_DE_ITEM, "") });
      return;
    }

    // Abertura de lista: termina em ":" e a próxima linha com conteúdo é item.
    const proxima = linhas.slice(i + 1).find((l) => l.trim().length > 0);
    if (linha.endsWith(":") && proxima !== undefined && MARCADOR_DE_ITEM.test(proxima.trim())) {
      blocos.push({ tipo: "lead", texto: linha });
      return;
    }

    blocos.push({ tipo: "paragrafo", texto: linha });
  });

  return blocos;
}

/**
 * "2,07 bar -> 0,66 L/min" vira "2,07 bar → 0,66 L/min". Só a seta entre
 * espaços: "-4" continua "-4", e nada colado em número é tocado.
 */
export function formatarSetas(texto: string): string {
  return texto.replace(/ -+> /g, " → ");
}

/** Só os dígitos de um texto — o teste usa para provar que nada mudou. */
export function digitosDe(texto: string): string {
  return texto.replace(/\D+/g, "");
}

/** Quantos marcadores [n] o texto tem — nenhum pode sumir na renderização. */
export function marcadoresDe(texto: string): string[] {
  return [...texto.matchAll(/\[\d{1,3}\]/g)].map((m) => m[0]);
}

/**
 * O código que a pessoa perguntou, para a tela de "sem evidência" mostrar o
 * que foi procurado. Mesmo perfil de código do grounding — não é um parser
 * novo, é o mesmo critério.
 */
export function codigoConsultado(pergunta: string): string | null {
  const achados = [...pergunta.matchAll(/[A-Za-z0-9][A-Za-z0-9-]*/g)]
    .map((m) => m[0])
    .filter(pareceCodigo);
  return achados[0] ?? null;
}

export function rotuloDeFontes(quantidade: number): string {
  return quantidade === 1 ? "Fonte utilizada" : "Fontes utilizadas";
}

export function rotuloDeTrechos(quantidade: number): string {
  return quantidade === 1 ? "1 trecho" : `${quantidade} trechos`;
}

/** Nível de acesso da evidência. Rótulo e cor; a REGRA está na RLS. */
export const NIVEL_DE_ACESSO: Record<
  string,
  { texto: string; tom: "neutral" | "info" | "warning" | "danger" }
> = {
  public: { texto: "Público", tom: "neutral" },
  internal: { texto: "Interno", tom: "info" },
  commercial: { texto: "Comercial", tom: "warning" },
  admin: { texto: "Admin", tom: "danger" },
};

export const TIPO_DE_TRECHO: Record<string, string> = {
  text: "Texto",
  heading: "Título",
  list: "Lista",
  table: "Tabela",
  price_table: "Tabela de preços",
  spec: "Especificação",
  caption: "Legenda",
  manual: "Manual",
  catalog: "Catálogo",
};

/** Tabela ganha rolagem horizontal própria; texto quebra linha normalmente. */
export function ehTabular(kind: string): boolean {
  return kind === "table" || kind === "price_table";
}

/**
 * O estado da resposta, em palavra de gente. `no_evidence`, `extractive` e
 * `grounding` são vocabulário de dentro do sistema e não vão para a tela —
 * seguem no log e no card de admin.
 */
export type EstadoDaResposta = "synthesized" | "extractive" | "no_evidence" | "forbidden" | "error";

export const ROTULO_DO_ESTADO: Record<EstadoDaResposta, string> = {
  synthesized: "Resposta do BRAIN",
  extractive: "Sem síntese automática",
  no_evidence: "Sem documentação suficiente",
  forbidden: "Sem acesso à memória",
  error: "Não foi possível consultar",
};

export function estadoDaResposta(
  status: "answered" | "no_evidence" | "forbidden" | "error",
  mode: "synthesized" | "extractive" | "none" | undefined,
): EstadoDaResposta {
  if (status !== "answered") return status;
  return mode === "extractive" ? "extractive" : "synthesized";
}
