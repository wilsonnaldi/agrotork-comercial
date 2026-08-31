/**
 * Dinheiro em centavos.
 *
 * Nenhum cálculo monetário do sistema usa ponto flutuante: dentro do
 * TypeScript o valor é um **inteiro de centavos**, e a conversão para o
 * banco é feita como string decimal (`"12345.67"`), que o PostgreSQL
 * recebe direto em `numeric(14,2)`.
 *
 * `0.1 + 0.2 !== 0.3` é o motivo. Em orçamento, isso vira centavo errado
 * no total.
 */

export const MAX_MONEY_CENTS = 99_999_999_999_99; // teto de numeric(14,2)

/**
 * Interpreta o que o usuário digitou em pt-BR e devolve centavos.
 * Aceita "1.234,56", "1234,56", "1234.56", "R$ 1.234,56" e "1234".
 * Devolve `null` quando não é um número válido.
 */
export function parseMoneyToCents(input: string | number | null | undefined): number | null {
  if (input === null || input === undefined) return null;
  if (typeof input === "number") {
    if (!Number.isFinite(input)) return null;
    return Math.round(input * 100);
  }

  const cleaned = input.trim().replace(/[R$\s ]/g, "");
  if (cleaned === "") return null;

  const lastComma = cleaned.lastIndexOf(",");
  const lastDot = cleaned.lastIndexOf(".");

  let normalized: string;
  if (lastComma > lastDot) {
    // pt-BR: ponto é milhar, vírgula é decimal
    normalized = cleaned.replace(/\./g, "").replace(",", ".");
  } else if (lastDot > lastComma) {
    // já veio com ponto decimal
    normalized = cleaned.replace(/,/g, "");
  } else {
    normalized = cleaned;
  }

  if (!/^-?\d+(\.\d+)?$/.test(normalized)) return null;

  const [wholePart = "0", fractionPart = ""] = normalized.split(".");
  const negative = wholePart.startsWith("-");
  const digits = wholePart.replace("-", "");
  const cents = `${fractionPart}00`.slice(0, 2);

  const value = Number(digits) * 100 + Number(cents);
  if (!Number.isSafeInteger(value)) return null;
  return negative ? -value : value;
}

/** Centavos -> string decimal para o banco: 123456 -> "1234.56". */
export function centsToDecimalString(cents: number): string {
  const negative = cents < 0;
  const absolute = Math.abs(Math.round(cents));
  const whole = Math.floor(absolute / 100);
  const rest = String(absolute % 100).padStart(2, "0");
  return `${negative ? "-" : ""}${whole}.${rest}`;
}

/**
 * Valor vindo do banco -> centavos.
 * O PostgREST pode devolver `numeric` como string ou como número;
 * a conversão passa por string para não depender disso.
 */
export function dbValueToCents(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  return parseMoneyToCents(typeof value === "number" ? value.toFixed(2) : value);
}

/** Centavos -> "R$ 1.234,56". */
export function formatCents(cents: number | null | undefined): string {
  if (cents === null || cents === undefined) return "—";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(cents / 100);
}

/** Centavos -> "1.234,56" (sem símbolo), para preencher campo de formulário. */
export function centsToInputValue(cents: number | null | undefined): string {
  if (cents === null || cents === undefined) return "";
  return new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(
    cents / 100,
  );
}

/**
 * Margem sobre o custo, em pontos percentuais com 2 casas.
 * Devolve `null` quando não há custo — margem sobre zero não existe.
 */
export function marginPercent(costCents: number | null, saleCents: number | null): number | null {
  if (costCents === null || saleCents === null || costCents <= 0) return null;
  return Math.round(((saleCents - costCents) / costCents) * 10000) / 100;
}

/** Preço de venda que produz a margem informada sobre o custo. */
export function saleFromMargin(costCents: number, margin: number): number {
  return Math.round(costCents * (1 + margin / 100));
}
