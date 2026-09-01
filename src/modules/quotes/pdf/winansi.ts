/**
 * Saneamento de texto para as fontes padrão do PDF.
 *
 * O `render.ts` usa as fontes embutidas do pdfkit (Helvetica) com
 * `WinAnsiEncoding`. Essa escolha está documentada lá: cobre todo o
 * português, não embute arquivo de fonte e não cria dependência de
 * arquivo em runtime na função serverless.
 *
 * O preço dela é que caractere fora do cp1252 não é rejeitado — é
 * desenhado com o glifo errado, em silêncio. Um MINUS SIGN virava aspas,
 * uma seta virava `!’`, um emoji virava `Ø=Þ•`. O texto do orçamento vem
 * do banco (nome de produto, observações, endereço), ou seja: dado de
 * usuário chegando cru numa fonte de 8 bits.
 *
 * Aqui o texto é convertido ANTES de ir para o papel:
 *   1. o que já cabe no cp1252 passa intacto — todo o português, aspas
 *      tipográficas, reticências, grau, mais-menos, micro, vezes, euro;
 *   2. símbolo com equivalente inequívoco vira o equivalente;
 *   3. forma de compatibilidade cai para a forma simples via NFKD;
 *   4. o que sobra (emoji, alfabeto não latino) é removido, porque um
 *      caractere ausente é melhor que um glifo errado.
 *
 * Os literais abaixo usam escapes em vez dos caracteres em si: vários
 * deles são invisíveis e não sobrevivem a copiar e colar.
 */

const EQUIVALENTES: Record<string, string> = {
  "−": "-", // MINUS SIGN
  "‐": "-", // HYPHEN
  "‑": "-", // NON-BREAKING HYPHEN
  "‒": "-", // FIGURE DASH
  "⁃": "-", // HYPHEN BULLET
  "≤": "<=",
  "≥": ">=",
  "≠": "!=",
  "≈": "~",
  "≡": "=",
  "→": "->",
  "←": "<-",
  "↔": "<->",
  "⇒": "=>",
  "\u00a0": " ", // NBSP: cabe no cp1252, mas vira espaço normal
  "\u202f": " ", // NARROW NO-BREAK SPACE
  "\u200b": "", // ZERO WIDTH SPACE
  "\ufeff": "", // BOM / ZERO WIDTH NO-BREAK SPACE
};

/** Faixa 0x80-0x9F do cp1252, que não existe no latin1 puro. */
const CP1252_EXTRA = new Set(
  "€‚ƒ„…†‡ˆ‰Š‹ŒŽ" +
    "‘’“”•–—˜™š›œžŸ",
);

function cabeNoCp1252(caractere: string): boolean {
  if (CP1252_EXTRA.has(caractere)) return true;
  const ponto = caractere.codePointAt(0);
  return ponto !== undefined && ponto <= 0xff;
}

export function paraWinAnsi(texto: string): string {
  let saida = "";

  for (const caractere of texto) {
    const equivalente = EQUIVALENTES[caractere];
    if (equivalente !== undefined) {
      saida += equivalente;
      continue;
    }

    if (cabeNoCp1252(caractere)) {
      saida += caractere;
      continue;
    }

    // NFKD resolve ligaduras e formas de compatibilidade; as marcas
    // combinantes que sobram são descartadas.
    saida += caractere
      .normalize("NFKD")
      .replace(/\p{M}/gu, "")
      .split("")
      .filter((c) => cabeNoCp1252(c))
      .join("");
  }

  return saida;
}

/**
 * Aplica `paraWinAnsi` em toda string de uma estrutura, preservando
 * números, booleanos, nulos e o formato do objeto.
 */
export function sanitizarParaPdf<T>(valor: T): T {
  if (typeof valor === "string") return paraWinAnsi(valor) as T;
  if (Array.isArray(valor)) return valor.map((item) => sanitizarParaPdf(item)) as T;
  if (valor !== null && typeof valor === "object") {
    const saida: Record<string, unknown> = {};
    for (const [chave, item] of Object.entries(valor as Record<string, unknown>)) {
      saida[chave] = sanitizarParaPdf(item);
    }
    return saida as T;
  }
  return valor;
}
