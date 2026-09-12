import { z } from "zod";

/**
 * Entrada da consulta à memória corporativa. Os limites espelham os da
 * função `brain.search_knowledge`: pergunta até 1000 caracteres (o banco
 * corta o excedente), até 100 resultados, filtros por chave conhecida.
 */
export const knowledgeQuerySchema = z.object({
  query: z.string().trim().min(2, "Escreva ao menos 2 caracteres.").max(1000, "A pergunta tem no máximo 1000 caracteres."),
  limit: z.coerce.number().int().min(1).max(100).default(10),
  includeSuperseded: z.coerce.boolean().default(false),
  filters: z
    .object({
      source_key: z.string().trim().min(1).optional(),
      document_id: z.string().uuid().optional(),
      document_type: z.string().trim().min(1).optional(),
      brand_id: z.string().uuid().optional(),
      category_id: z.string().uuid().optional(),
      version_label: z.string().trim().min(1).optional(),
      version_id: z.string().uuid().optional(),
      kind: z.string().trim().min(1).optional(),
      product_id: z.string().uuid().optional(),
    })
    .strict()
    .default({}),
});

export type KnowledgeQuery = z.infer<typeof knowledgeQuerySchema>;
