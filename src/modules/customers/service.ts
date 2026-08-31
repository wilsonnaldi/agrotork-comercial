import "server-only";

import type { Customer, InsertOf } from "@/types/db";
import type { CustomerInput } from "./schema";
import * as repository from "./repository";
import type { CustomerFilters } from "./schema";
import type { CustomerHistory, CustomerPage } from "./types";

/**
 * Regras de negócio de Clientes.
 * Não conhece React nem Next — só domínio.
 */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

export function listCustomers(filters: CustomerFilters): Promise<CustomerPage> {
  return repository.findMany(filters);
}

export function getCustomer(id: string): Promise<Customer | null> {
  return repository.findById(id);
}

export function getCustomerHistory(id: string): Promise<CustomerHistory> {
  return repository.findHistory(id);
}

/**
 * Monta o registro a partir da entrada já validada.
 * O banco ainda normaliza documento, CEP e UF por trigger — aqui é
 * apenas o formato de persistência.
 */
function toRecord(input: CustomerInput, userId: string, isNew: boolean): InsertOf<"customers"> {
  const record: InsertOf<"customers"> = {
    person_type: input.person_type,
    name: input.name,
    trade_name: input.trade_name ?? null,
    document: input.document ?? null,
    state_registration: input.state_registration ?? null,
    phone: input.phone ?? null,
    whatsapp: input.whatsapp ?? null,
    email: input.email ?? null,
    address: input.address ?? null,
    address_number: input.address_number ?? null,
    address_complement: input.address_complement ?? null,
    district: input.district ?? null,
    city: input.city ?? null,
    state: input.state ?? null,
    zip_code: input.zip_code ?? null,
    notes: input.notes ?? null,
    is_active: input.is_active,
    updated_by: userId,
  };

  if (isNew) record.created_by = userId;
  return record;
}

/** Documento é único entre clientes ativos — evita cadastro em duplicidade. */
async function assertDocumentIsFree(document: string | undefined, exceptId?: string) {
  if (!document) return;

  const existing = await repository.findByDocument(document, exceptId);
  if (existing) {
    throw new BusinessError(`Já existe um cliente com este documento: ${existing.name}`, "document");
  }
}

export async function createCustomer(input: CustomerInput, userId: string): Promise<string> {
  await assertDocumentIsFree(input.document);
  return repository.insert(toRecord(input, userId, true));
}

export async function updateCustomer(id: string, input: CustomerInput, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Cliente não encontrado");

  await assertDocumentIsFree(input.document, id);
  await repository.update(id, toRecord(input, userId, false));
}

/** Desativar mantém o cliente e o histórico; só some das listagens padrão. */
export async function setCustomerActive(id: string, isActive: boolean, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Cliente não encontrado");

  await repository.update(id, { is_active: isActive, updated_by: userId });
}

/**
 * Exclusão lógica. Reservada ao administrador (ver PERMISSIONS).
 * Um cliente com histórico deve ser desativado, não excluído.
 */
export async function deleteCustomer(id: string, userId: string): Promise<void> {
  const history = await repository.findHistory(id);
  if (history.quotes.length > 0) {
    throw new BusinessError(
      "Este cliente tem orçamentos registrados. Desative-o em vez de excluir, para preservar o histórico.",
    );
  }
  await repository.softDelete(id, userId);
}
