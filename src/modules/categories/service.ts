import "server-only";

import type { Category } from "@/types/db";
import * as repository from "./repository";
import type { CategoryFilters, CategoryInput } from "./schema";
import type { CategoryPage } from "./repository";

/** Regras de negócio de Categorias. */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

export function listCategories(filters: CategoryFilters): Promise<CategoryPage> {
  return repository.findMany(filters);
}

export function getCategory(id: string): Promise<Category | null> {
  return repository.findById(id);
}

export function countCategoryProducts(id: string): Promise<number> {
  return repository.countProducts(id);
}

async function assertNameIsFree(name: string, exceptId?: string) {
  const existing = await repository.findByName(name, exceptId);
  if (existing) {
    throw new BusinessError(`Já existe uma categoria chamada "${existing.name}".`, "name");
  }
}

export async function createCategory(input: CategoryInput): Promise<string> {
  await assertNameIsFree(input.name);
  // `slug` é preenchido por trigger a partir do nome (migration 1500).
  return repository.insert({
    name: input.name,
    description: input.description ?? null,
    is_active: input.is_active,
  });
}

export async function updateCategory(id: string, input: CategoryInput): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Categoria não encontrada");

  await assertNameIsFree(input.name, id);
  await repository.update(id, {
    name: input.name,
    description: input.description ?? null,
    is_active: input.is_active,
  });
}

/**
 * Desativar não apaga nada: produtos e kits já vinculados continuam
 * como estão. A categoria apenas deixa de ser oferecida em novos cadastros.
 */
export async function setCategoryActive(id: string, isActive: boolean): Promise<void> {
  const current = await repository.findById(id);
  if (!current) throw new BusinessError("Categoria não encontrada");
  await repository.update(id, { is_active: isActive });
}
