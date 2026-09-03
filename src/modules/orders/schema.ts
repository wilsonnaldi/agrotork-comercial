import { z } from "zod";

/**
 * Validação do que chega da URL e dos formulários de Pedidos.
 *
 * É uma superfície pequena de propósito: o pedido não tem formulário de
 * montagem. O que o navegador manda é intenção de leitura (filtros) ou de
 * movimento (situação, converter) — nunca preço, quantidade ou total.
 */

export const orderStatusSchema = z.enum([
  "confirmed",
  "picking",
  "invoiced",
  "delivered",
  "cancelled",
]);

export const orderFiltersSchema = z.object({
  q: z.string().trim().max(120).optional(),
  status: z
    .enum(["all", "confirmed", "picking", "invoiced", "delivered", "cancelled"])
    .default("all"),
  customer: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  owner: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  sort: z.enum(["recent", "number", "total", "customer"]).default("recent"),
  page: z.coerce.number().int().min(1).default(1),
});

export type OrderFilters = z.infer<typeof orderFiltersSchema>;
