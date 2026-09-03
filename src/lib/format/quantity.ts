/**
 * Quantidade em milésimos.
 *
 * Mesma decisão do dinheiro em centavos, pelo mesmo motivo: `numeric(14,3)`
 * no banco, inteiro no TypeScript, string decimal na fronteira. Ponto
 * flutuante não entra em nada que multiplique preço.
 *
 * Vive em `lib/` porque Kits e Orçamentos precisam das mesmas funções —
 * e um módulo não importa o outro.
 */

export const QUANTITY_SCALE = 1000;
export const MAX_QUANTITY_MILLI = 99_999_999 * QUANTITY_SCALE;

/** Interpreta "2", "2,5" ou "2.5" e devolve milésimos. `null` se inválido. */
export function parseQuantityToMilli(input: string | null | undefined): number | null {
  if (input === null || input === undefined) return null;
  const cleaned = input.trim().replace(/\s/g, "").replace(",", ".");
  if (cleaned === "" || !/^\d+(\.\d{1,3})?$/.test(cleaned)) return null;

  const [whole = "0", fraction = ""] = cleaned.split(".");
  const milli = Number(whole) * QUANTITY_SCALE + Number(`${fraction}000`.slice(0, 3));
  return Number.isSafeInteger(milli) ? milli : null;
}

/**
 * Aceita sinal, ao contrário de `parseQuantityToMilli`.
 *
 * Existe por causa do estoque: ajuste de contagem vai para os dois lados,
 * e saldo negativo é informação legítima (a lista do que falta acertar).
 * Em orçamento e kit a quantidade continua sendo positiva por definição,
 * e por isso a função de lá segue recusando o sinal.
 */
export function parseSignedQuantityToMilli(input: string | null | undefined): number | null {
  if (input === null || input === undefined) return null;
  const cleaned = input.trim().replace(/\s/g, "").replace(",", ".");
  const negativo = cleaned.startsWith("-");
  const semSinal = cleaned.replace(/^[+-]/, "");
  const milli = parseQuantityToMilli(semSinal);
  if (milli === null) return null;
  return negativo ? -milli : milli;
}

/**
 * Milésimos -> texto pt-BR: 2500 -> "2,5"; 1000 -> "1"; -2500 -> "-2,5".
 *
 * O sinal sai antes e a parte fracionária é calculada sobre o valor
 * absoluto: com `Math.floor` direto, −2500 virava "−3,500".
 */
export function formatQuantity(milli: number): string {
  const sinal = milli < 0 ? "-" : "";
  const absoluto = Math.abs(milli);
  const whole = Math.floor(absoluto / QUANTITY_SCALE);
  const fraction = absoluto % QUANTITY_SCALE;
  if (fraction === 0) return `${sinal}${whole}`;
  return `${sinal}${whole},${String(fraction).padStart(3, "0").replace(/0+$/, "")}`;
}

/** Milésimos -> string decimal para o banco: 2500 -> "2.500"; -2500 -> "-2.500". */
export function milliToDecimalString(milli: number): string {
  const sinal = milli < 0 ? "-" : "";
  const absoluto = Math.abs(milli);
  const whole = Math.floor(absoluto / QUANTITY_SCALE);
  const fraction = String(absoluto % QUANTITY_SCALE).padStart(3, "0");
  return `${sinal}${whole}.${fraction}`;
}

/** `numeric` lido do banco -> milésimos. */
export function dbValueToMilli(value: number | string | null | undefined): number {
  if (value === null || value === undefined) return 0;
  return Math.round(Number(value) * QUANTITY_SCALE);
}
