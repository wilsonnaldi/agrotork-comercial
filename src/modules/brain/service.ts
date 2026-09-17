import "server-only";

import type { Json } from "@/types/db";
import * as repository from "./repository";
import { refusal, toEvidence } from "./evidence";
import type { KnowledgeAnswer } from "./evidence";
import type { KnowledgeQuery } from "./schema";

/**
 * Regra da consulta: o que volta para a tela é EVIDÊNCIA com citação, ou a
 * recusa. Nunca uma resposta inventada. Este módulo não escreve prosa —
 * entrega trecho, página e proveniência para quem for compor a resposta
 * (hoje a pessoa; mais tarde, um assistente com as mesmas cercas).
 *
 * O fail-closed de verdade está no banco: `brain.search_knowledge` filtra
 * acesso, vigência e tabela degradada ANTES do ranking, e `public.brain_search`
 * devolve vazio quando não há usuário ativo. Aqui não se reabre nada — só se
 * traduz "zero linhas" numa recusa que a tela sabe mostrar.
 */

export * from "./evidence";

/**
 * `comDebug` vem do papel de quem perguntou, nunca da requisição: pedir
 * debug não é um jeito de virar administrador.
 */
export async function ask(input: KnowledgeQuery, comDebug = false): Promise<KnowledgeAnswer> {
  const rows = await repository.search(input);
  if (rows.length === 0) return refusal(input.query, "no_evidence");
  return {
    query: input.query,
    status: "answered",
    evidence: rows.map((r) => toEvidence(r, comDebug)),
  };
}

export async function provenance(chunkId: number): Promise<Json | null> {
  return repository.provenance(chunkId);
}
