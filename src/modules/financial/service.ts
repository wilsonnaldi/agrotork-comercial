import "server-only";

import * as repository from "./repository";
import type { FinancialFilters, PaymentInput, SplitInput } from "./schema";
import type { EntryPage, EntryRow, PaymentRow } from "./types";

/**
 * Regras de negócio do Financeiro.
 *
 * A camada é fina porque as regras que importam moram no banco: o status
 * derivado da soma das baixas, a recusa de baixa maior que o saldo, o
 * "com baixa não se cancela", a imutabilidade do livro. Aqui só traduz.
 */

export class BusinessError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BusinessError";
  }
}

function traduzir(error: unknown): never {
  const mensagem = error instanceof Error ? error.message : "";

  if (mensagem.includes("Somente administrador")) {
    throw new BusinessError("Somente administrador mexe no financeiro.");
  }
  if (mensagem.includes("passa do que falta")) {
    throw new BusinessError(
      "A baixa é maior do que o que falta receber neste título. Confira o valor.",
    );
  }
  if (mensagem.includes("estorno passa do que já foi baixado")) {
    throw new BusinessError("O estorno é maior do que o que já foi baixado.");
  }
  if (mensagem.includes("Título cancelado")) {
    throw new BusinessError("Título cancelado não recebe baixa.");
  }
  if (mensagem.includes("com baixa não se cancela") || mensagem.includes("Estorne a baixa")) {
    throw new BusinessError("Título com baixa não se cancela. Estorne a baixa primeiro.");
  }
  if (mensagem.includes("Só título aberto")) {
    throw new BusinessError("Só título aberto e sem baixa se parcela.");
  }
  if (mensagem.includes("já é uma parcela")) {
    throw new BusinessError("Este título já é uma parcela e não se parcela de novo.");
  }
  if (mensagem.includes("parcelamento vai de")) {
    throw new BusinessError("O parcelamento vai de 2 a 60 vezes.");
  }
  if (mensagem.includes("não se altera nem se apaga")) {
    throw new BusinessError("Baixa não se altera nem se apaga. Para corrigir, lance um estorno.");
  }
  if (mensagem.includes("não encontrado")) {
    throw new BusinessError("Título não encontrado.");
  }
  if (mensagem.includes("row-level security")) {
    throw new BusinessError("Sem permissão para esta operação.");
  }
  throw error;
}

export function listEntries(filters: FinancialFilters): Promise<EntryPage> {
  return repository.findMany(filters);
}

export function getEntry(id: string): Promise<EntryRow | null> {
  return repository.findById(id);
}

export function getPayments(entryId: string): Promise<PaymentRow[]> {
  return repository.findPayments(entryId);
}

export function getEntriesByOrder(orderId: string): Promise<EntryRow[]> {
  return repository.findByOrder(orderId);
}

export async function registerPayment(input: PaymentInput): Promise<void> {
  try {
    await repository.registerPayment(input);
  } catch (error) {
    traduzir(error);
  }
}

export async function splitEntry(input: SplitInput): Promise<number> {
  try {
    return await repository.split(input);
  } catch (error) {
    traduzir(error);
  }
}

export async function cancelEntry(id: string, notes?: string): Promise<void> {
  try {
    await repository.cancel(id, notes);
  } catch (error) {
    traduzir(error);
  }
}
