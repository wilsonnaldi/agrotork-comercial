"use server";

import { requirePermission } from "@/lib/auth/session";
import { knowledgeQuerySchema } from "./schema";
import * as service from "./service";
import type { KnowledgeAnswer } from "./service";
import type { Json } from "@/types/db";

/**
 * Porta interna do aplicativo para a memória corporativa (Fase 2, Lote B).
 * Não é chatbot, não é endpoint público: é uma Server Action que exige
 * sessão, valida a entrada e devolve evidência com citação — ou "não
 * encontrei". A auditoria da consulta fica no banco (`brain_search`
 * registra em brain.knowledge_queries), com o usuário da sessão.
 */

export type KnowledgeActionResult =
  | { ok: true; answer: KnowledgeAnswer }
  | { ok: false; error: string };

export async function askKnowledgeAction(input: unknown): Promise<KnowledgeActionResult> {
  await requirePermission("knowledge.query");
  const parsed = knowledgeQuerySchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Consulta inválida." };
  }
  try {
    return { ok: true, answer: await service.ask(parsed.data) };
  } catch {
    // Mensagem genérica de propósito: erro do banco não descreve o que existe.
    return { ok: false, error: "Não foi possível consultar a memória agora." };
  }
}

export async function knowledgeProvenanceAction(chunkId: number): Promise<{ ok: true; provenance: Json | null } | { ok: false; error: string }> {
  await requirePermission("knowledge.query");
  if (!Number.isInteger(chunkId) || chunkId <= 0) return { ok: false, error: "Trecho inválido." };
  try {
    return { ok: true, provenance: await service.provenance(chunkId) };
  } catch {
    return { ok: false, error: "Não foi possível obter a proveniência agora." };
  }
}
