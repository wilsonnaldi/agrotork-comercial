import "server-only";

import type { Brand } from "@/types/db";
import * as repository from "./repository";
import type { BrandFilters, BrandInput } from "./schema";
import type { BrandPage } from "./repository";

/** Regras de negócio de Marcas. */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

export function listBrands(filters: BrandFilters): Promise<BrandPage> {
  return repository.findMany(filters);
}

export function getBrand(id: string): Promise<Brand | null> {
  return repository.findById(id);
}

export function countBrandProducts(id: string): Promise<number> {
  return repository.countProducts(id);
}

async function assertNameIsFree(name: string, exceptId?: string) {
  const existing = await repository.findByName(name, exceptId);
  if (existing) {
    throw new BusinessError(`Já existe uma marca chamada "${existing.name}".`, "name");
  }
}

export async function createBrand(input: BrandInput): Promise<string> {
  await assertNameIsFree(input.name);
  // `slug` é preenchido por trigger a partir do nome (migration 1500).
  return repository.insert({
    name: input.name,
    description: input.description ?? null,
    is_active: input.is_active,
  });
}

export async function updateBrand(id: string, input: BrandInput): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Marca não encontrada");

  await assertNameIsFree(input.name, id);
  await repository.update(id, {
    name: input.name,
    description: input.description ?? null,
    is_active: input.is_active,
  });
}

/**
 * Desativar não apaga nada: os produtos já vinculados continuam como
 * estão. A marca apenas deixa de ser oferecida para novos produtos.
 */
export async function setBrandActive(id: string, isActive: boolean): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Marca não encontrada");
  await repository.update(id, { is_active: isActive });
}
