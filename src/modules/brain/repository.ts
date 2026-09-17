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

export async function provenance(chunkId: number): Promise<Json | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("brain_provenance", { p_chunk_id: chunkId });
  if (error) throw new Error(error.message);
  return (data as Json | null) ?? null;
}
