import "server-only";

import type { Unit } from "@/types/db";
import * as repository from "./repository";
import type { UnitFilters, UnitInput } from "./schema";
import type { UnitPage } from "./repository";

/** Regras de negócio de Unidades. */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

export function listUnits(filters: UnitFilters): Promise<UnitPage> {
  return repository.findMany(filters);
}

export function getUnit(id: string): Promise<Unit | null> {
  return repository.findById(id);
}

export function countUnitProducts(id: string): Promise<number> {
  return repository.countProducts(id);
}

async function assertCodeIsFree(code: string, exceptId?: string) {
  const existing = await repository.findByCode(code, exceptId);
  if (existing) {
    throw new BusinessError(`O código ${existing.code} já está em uso pela unidade "${existing.name}".`, "code");
  }
}

export async function createUnit(input: UnitInput): Promise<string> {
  await assertCodeIsFree(input.code);
  return repository.insert({
    code: input.code,
    name: input.name,
    allows_fraction: input.allows_fraction,
    is_active: input.is_active,
  });
}

export async function updateUnit(id: string, input: UnitInput): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Unidade não encontrada");

  await assertCodeIsFree(input.code, id);
  await repository.update(id, {
    code: input.code,
    name: input.name,
    allows_fraction: input.allows_fraction,
    is_active: input.is_active,
  });
}

/**
 * Desativar não apaga nada: os produtos já vinculados continuam com a
 * unidade. Ela apenas deixa de ser oferecida em novos cadastros.
 */
export async function setUnitActive(id: string, isActive: boolean): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Unidade não encontrada");
  await repository.update(id, { is_active: isActive });
}
