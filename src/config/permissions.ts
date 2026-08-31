import type { UserRole } from "@/types/db";

/**
 * Matriz de permissões — ÚNICO lugar onde "quem pode o quê" é declarado.
 * Adicionar um papel novo (manager, financial, viewer) é acrescentar uma
 * linha aqui e um valor no enum `user_role` do banco.
 *
 * Isto é conveniência de interface. A segurança real está nas policies de RLS.
 */
export const PERMISSIONS = {
  "customers.read": ["admin", "salesperson"],
  "customers.write": ["admin", "salesperson"],
  "customers.delete": ["admin"],

  "products.read": ["admin", "salesperson"],
  "products.write": ["admin"],
  "products.viewCost": ["admin"],

  "catalog.manage": ["admin"], // categorias, marcas, unidades
  "kits.read": ["admin", "salesperson"],
  "kits.write": ["admin"],

  "quotes.readOwn": ["admin", "salesperson"],
  "quotes.readAll": ["admin"],
  "quotes.write": ["admin", "salesperson"],
  "quotes.delete": ["admin"],

  "users.manage": ["admin"],
  "settings.manage": ["admin"],
} as const satisfies Record<string, readonly UserRole[]>;

export type Permission = keyof typeof PERMISSIONS;

export function can(role: UserRole | null | undefined, permission: Permission): boolean {
  if (!role) return false;
  return (PERMISSIONS[permission] as readonly UserRole[]).includes(role);
}
