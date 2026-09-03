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

  /**
   * Fornecedores. O vendedor LÊ — precisa saber de quem vem a peça que
   * prometeu ao cliente —, mas quem decide de quem a empresa compra é a
   * administração. É o mesmo desenho de marcas e categorias, não o de
   * clientes.
   */
  "suppliers.read": ["admin", "salesperson"],
  "suppliers.manage": ["admin"],
  "kits.read": ["admin", "salesperson"],
  "kits.write": ["admin"],

  /**
   * Pedido de venda. Ler e mover a situação valem para os dois papéis:
   * o vendedor acompanha e fatura o próprio pedido. Quem limita o alcance
   * é o RLS — `orders_select` só devolve os pedidos do dono —, e o que
   * NENHUM papel faz (mudar preço, item ou desconto) é barrado pelo
   * gatilho `trg_orders_freeze`, não por esta matriz.
   */
  "orders.read": ["admin", "salesperson"],
  "orders.write": ["admin", "salesperson"],

  "quotes.readOwn": ["admin", "salesperson"],
  "quotes.readAll": ["admin"],
  "quotes.write": ["admin", "salesperson"],
  "quotes.delete": ["admin"],

  /** Todo mundo abre o relatório; o RLS decide o que cada um soma. */
  "reports.read": ["admin", "salesperson"],
  /** Só o administrador compara vendedores entre si. */
  "reports.readAll": ["admin"],

  "users.manage": ["admin"],
  "settings.manage": ["admin"],
} as const satisfies Record<string, readonly UserRole[]>;

export type Permission = keyof typeof PERMISSIONS;

export function can(role: UserRole | null | undefined, permission: Permission): boolean {
  if (!role) return false;
  return (PERMISSIONS[permission] as readonly UserRole[]).includes(role);
}
