import type { ZodIssue } from "zod";

/**
 * Estado de retorno das Server Actions de formulário.
 *
 * É encanamento de formulário, não regra de negócio — por isso vive em
 * `lib/` e é usado por todos os módulos, sem que um módulo precise
 * importar o outro.
 */
export type FormState = {
  /** Erro geral, quando não é de um campo específico. */
  error?: string;
  /** Erros por campo, na mesma chave que o `name` do input. */
  fieldErrors?: Record<string, string>;
  /** O que o usuário digitou, devolvido para o formulário não zerar. */
  values?: Record<string, string>;
  /**
   * Contador de tentativas.
   *
   * O React **reseta o formulário** quando uma Server Action termina, e não
   * ressincroniza os campos controlados — selects e campos com máscara
   * perdiam a escolha depois de um erro de validação. O formulário usa este
   * número como `key` para remontar a partir de `values`.
   */
  attempt?: number;
};

/** Resposta de erro, sempre incrementando o contador de tentativas. */
export function fail(prev: FormState, patch: Omit<FormState, "attempt">): FormState {
  return { ...patch, attempt: (prev.attempt ?? 0) + 1 };
}

/**
 * Primeiro erro de cada campo.
 * `stripSuffix` existe porque alguns schemas nomeiam o campo de forma
 * diferente do input (`sale_price_cents` no schema, `sale_price` no form).
 */
export function collectFieldErrors(
  issues: readonly Pick<ZodIssue, "path" | "message">[],
  stripSuffix?: RegExp,
): Record<string, string> {
  const fieldErrors: Record<string, string> = {};
  for (const issue of issues) {
    const key = issue.path[0];
    if (typeof key !== "string") continue;
    const field = stripSuffix ? key.replace(stripSuffix, "") : key;
    if (!fieldErrors[field]) fieldErrors[field] = issue.message;
  }
  return fieldErrors;
}

/** Devolve o que foi enviado, para repopular o formulário. */
export function rawValues(formData: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === "string") values[key] = value;
  }
  return values;
}

/** Reconhece violação de índice único vinda do Postgres. */
export function isUniqueViolation(error: unknown, ...indexNames: string[]): boolean {
  const message = error instanceof Error ? error.message : String(error ?? "");
  if (/duplicate key|unique constraint/i.test(message)) return true;
  return indexNames.some((name) => message.includes(name));
}
