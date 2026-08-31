/** Validações brasileiras usadas pelos schemas Zod. */
import { onlyDigits } from "./index";

export function isValidCPF(value: string): boolean {
  const cpf = onlyDigits(value);
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;

  const digits = cpf.split("").map(Number) as number[];
  for (const length of [9, 10]) {
    let sum = 0;
    for (let i = 0; i < length; i++) sum += (digits[i] ?? 0) * (length + 1 - i);
    const check = ((sum * 10) % 11) % 10;
    if (check !== digits[length]) return false;
  }
  return true;
}

export function isValidCNPJ(value: string): boolean {
  const cnpj = onlyDigits(value);
  if (cnpj.length !== 14 || /^(\d)\1{13}$/.test(cnpj)) return false;

  const digits = cnpj.split("").map(Number) as number[];
  const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

  for (const length of [12, 13]) {
    const slice = weights.slice(weights.length - length);
    let sum = 0;
    for (let i = 0; i < length; i++) sum += (digits[i] ?? 0) * (slice[i] ?? 0);
    const rest = sum % 11;
    const check = rest < 2 ? 0 : 11 - rest;
    if (check !== digits[length]) return false;
  }
  return true;
}

export function isValidDocument(value: string): boolean {
  const digits = onlyDigits(value);
  if (digits.length === 11) return isValidCPF(digits);
  if (digits.length === 14) return isValidCNPJ(digits);
  return false;
}
