import "server-only";

import type { InsertOf, Supplier } from "@/types/db";
import * as repository from "./repository";
import type { SupplierFilters, SupplierInput } from "./schema";
import type { SupplierPage } from "./types";

/**
 * Regras de negócio de Fornecedores.
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

export function listSuppliers(filters: SupplierFilters): Promise<SupplierPage> {
  return repository.findMany(filters);
}

export function getSupplier(id: string): Promise<Supplier | null> {
  return repository.findById(id);
}

/**
 * Monta o registro a partir da entrada já validada.
 * O banco ainda normaliza documento, CEP e UF por trigger — aqui é
 * apenas o formato de persistência.
 */
function toRecord(input: SupplierInput, userId: string, isNew: boolean): InsertOf<"suppliers"> {
  const record: InsertOf<"suppliers"> = {
    person_type: input.person_type,
    name: input.name,
    trade_name: input.trade_name ?? null,
    document: input.document ?? null,
    state_registration: input.state_registration ?? null,
    phone: input.phone ?? null,
    whatsapp: input.whatsapp ?? null,
    email: input.email ?? null,
    website: input.website ?? null,
    address: input.address ?? null,
    address_number: input.address_number ?? null,
    address_complement: input.address_complement ?? null,
    district: input.district ?? null,
    city: input.city ?? null,
    state: input.state ?? null,
    zip_code: input.zip_code ?? null,
    contact_name: input.contact_name ?? null,
    payment_terms: input.payment_terms ?? null,
    notes: input.notes ?? null,
    is_active: input.is_active,
    updated_by: userId,
  };

  if (isNew) record.created_by = userId;
  return record;
}

/** Documento é único entre fornecedores vivos — evita cadastro em duplicidade. */
async function assertDocumentIsFree(document: string | undefined, exceptId?: string) {
  if (!document) return;

  const existing = await repository.findByDocument(document, exceptId);
  if (existing) {
    throw new BusinessError(`Já existe um fornecedor com este documento: ${existing.name}`, "document");
  }
}

/**
 * O índice único do banco é a autoridade; a checagem acima é só para dar
 * uma mensagem melhor. Se duas telas gravarem ao mesmo tempo, quem chega
 * depois leva a violação do índice — e ela também precisa sair em
 * português, não como texto do PostgreSQL.
 */
function traduzir(error: unknown): never {
  const mensagem = error instanceof Error ? error.message : "";
  if (mensagem.includes("idx_suppliers_document") || mensagem.includes("duplicate key")) {
    throw new BusinessError("Já existe um fornecedor com este documento.", "document");
  }
  if (mensagem.includes("row-level security") || mensagem.includes("Sem permissão")) {
    throw new BusinessError("Somente administrador pode alterar fornecedor.");
  }
  throw error;
}

export async function createSupplier(input: SupplierInput, userId: string): Promise<string> {
  await assertDocumentIsFree(input.document);
  try {
    return await repository.insert(toRecord(input, userId, true));
  } catch (error) {
    traduzir(error);
  }
}

export async function updateSupplier(id: string, input: SupplierInput, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Fornecedor não encontrado");

  await assertDocumentIsFree(input.document, id);
  try {
    await repository.update(id, toRecord(input, userId, false));
  } catch (error) {
    traduzir(error);
  }
}

/** Desativar mantém o cadastro e o histórico; só some das listagens padrão. */
export async function setSupplierActive(id: string, isActive: boolean, userId: string): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Fornecedor não encontrado");

  try {
    await repository.update(id, { is_active: isActive, updated_by: userId });
  } catch (error) {
    traduzir(error);
  }
}

/**
 * Exclusão lógica. Reservada ao administrador — a função do banco confere
 * o papel por conta própria, então esta camada só traduz a recusa.
 */
export async function deleteSupplier(id: string): Promise<void> {
  try {
    await repository.softDelete(id);
  } catch (error) {
    const mensagem = error instanceof Error ? error.message : "";
    if (mensagem.includes("Somente administrador")) {
      throw new BusinessError("Somente administrador pode excluir fornecedor.");
    }
    if (mensagem.includes("não encontrado")) {
      throw new BusinessError("Fornecedor não encontrado.");
    }
    throw error;
  }
}
