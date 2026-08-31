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

/** Milésimos -> texto pt-BR: 2500 -> "2,5"; 1000 -> "1". */
export function formatQuantity(milli: number): string {
  const whole = Math.floor(milli / QUANTITY_SCALE);
  const fraction = milli % QUANTITY_SCALE;
  if (fraction === 0) return String(whole);
  return `${whole},${String(fraction).padStart(3, "0").replace(/0+$/, "")}`;
}

/** Milésimos -> string decimal para o banco: 2500 -> "2.500". */
export function milliToDecimalString(milli: number): string {
  const whole = Math.floor(milli / QUANTITY_SCALE);
  const fraction = String(milli % QUANTITY_SCALE).padStart(3, "0");
  return `${whole}.${fraction}`;
}

/** `numeric` lido do banco -> milésimos. */
export function dbValueToMilli(value: number | string | null | undefined): number {
  if (value === null || value === undefined) return 0;
  return Math.round(Number(value) * QUANTITY_SCALE);
}
