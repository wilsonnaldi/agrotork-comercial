"use server";

import { can } from "@/config/permissions";
import { getSessionUser } from "@/lib/auth/session";
import { knowledgeQuerySchema } from "./schema";
import * as service from "./service";
import type { KnowledgeAnswer } from "./service";
import type { Json } from "@/types/db";

/**
 * Porta interna do aplicativo para a memória corporativa. Não é chatbot e
 * não é endpoint público: é uma Server Action que exige sessão, valida a
 * entrada e devolve evidência com citação — ou uma recusa nomeada.
 *
 * Por que `getSessionUser` e não `requirePermission`: aquele redireciona, o
 * que é certo para uma PÁGINA e errado aqui. Quem chama é um formulário já
 * aberto, e uma recusa tem de voltar como resposta ("forbidden"), não como
 * navegação. A cerca não fica mais fraca por isso — o banco continua sendo
 * a última barreira: `public.brain_search` devolve vazio sem usuário ativo,
 * e o RLS filtra por nível antes do ranking.
 *
 * A trilha da consulta é do banco: `brain_search` grava em
 * `brain.knowledge_queries` quem perguntou, o quê, com que nível, quantos
 * resultados, quais trechos e a duração. Não se registra nada aqui em cima,
 * para não haver duas contagens da mesma pergunta.
 */

export type KnowledgeActionResult = { answer: KnowledgeAnswer };

export async function askKnowledgeAction(input: unknown): Promise<KnowledgeActionResult> {
  const parsedInput = input as { query?: unknown };
  const perguntaCrua = typeof parsedInput?.query === "string" ? parsedInput.query : "";

  const user = await getSessionUser();
  // Sem sessão, sem perfil ou perfil inativo: `getSessionUser` já devolve null.
  if (!user || !can(user.profile.role, "knowledge.query")) {
    return { answer: service.refusal(perguntaCrua, "forbidden") };
  }

  const parsed = knowledgeQuerySchema.safeParse(input);
  if (!parsed.success) {
    return {
      answer: {
        query: perguntaCrua,
        status: "error",
        evidence: [],
        refusalReason: parsed.error.issues[0]?.message ?? "Consulta inválida.",
      },
    };
  }

  const ehAdmin = user.profile.role === "admin";
  try {
    return { answer: await service.ask(parsed.data, ehAdmin) };
  } catch {
    // Genérica de propósito: mensagem de erro do banco descreve o que existe.
    return { answer: service.refusal(parsed.data.query, "error") };
  }
}

export async function knowledgeProvenanceAction(
  chunkId: number,
): Promise<{ ok: true; provenance: Json | null } | { ok: false; error: string }> {
  const user = await getSessionUser();
  if (!user || !can(user.profile.role, "knowledge.query")) {
    return { ok: false, error: service.SEM_PERMISSAO };
  }
  if (!Number.isInteger(chunkId) || chunkId <= 0) return { ok: false, error: "Trecho inválido." };
  try {
    return { ok: true, provenance: await service.provenance(chunkId) };
  } catch {
    return { ok: false, error: "Não foi possível obter a proveniência agora." };
  }
}
