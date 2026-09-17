import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/types/db";
import type { KnowledgeHitRow } from "./evidence";
import type { KnowledgeQuery } from "./schema";

/**
 * Acesso à memória corporativa. ÚNICO lugar do módulo que fala com o
 * Supabase, e só por duas portas: `public.brain_search` e
 * `public.brain_provenance`. O schema `brain` não é exposto ao PostgREST —
 * tudo passa pelo RLS com a sessão do usuário; o worker de ingestão vive
 * fora do aplicativo (brain/worker).
 */

export type { KnowledgeHitRow };

export async function search(input: KnowledgeQuery): Promise<KnowledgeHitRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("brain_search", {
    p_query: input.query,
    p_filters: input.filters as Json,
    p_limit: input.limit,
    p_include_superseded: input.includeSuperseded,
  });
  if (error) throw new Error(error.message);
  return (data ?? []) as KnowledgeHitRow[];
}

/**
 * Política de processamento externo de cada documento
 * (`public.brain_external_processing`, migration 20260917054004).
 *
 * Devolve um MAPA, e o que não estiver nele é proibido — quem decide isso é
 * `assessExternalProcessing`. Por isso o erro aqui não sobe: banco fora do ar,
 * RLS escondendo o documento ou migration ainda não aplicada dão todos o
 * mesmo resultado prático, que é o seguro. Um `catch` que devolve mapa vazio
 * seria perigoso se ausência significasse permissão; como significa
 * proibição, ele é a própria cerca.
 */
export async function externalProcessing(documentIds: string[]): Promise<Map<string, string>> {
  const unicos = [...new Set(documentIds)].filter(Boolean);
  if (unicos.length === 0) return new Map();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("brain_external_processing", { p_document_ids: unicos });
  if (error) return new Map();
  const linhas = (data ?? []) as { document_id: string; policy: string }[];
  return new Map(linhas.map((l) => [l.document_id, l.policy]));
}

export async function provenance(chunkId: number): Promise<Json | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("brain_provenance", { p_chunk_id: chunkId });
  if (error) throw new Error(error.message);
  return (data as Json | null) ?? null;
}
