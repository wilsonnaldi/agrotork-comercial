import "server-only";

import type { Json } from "@/types/db";
import * as repository from "./repository";
import type { KnowledgeHitRow } from "./repository";
import type { KnowledgeQuery } from "./schema";

/**
 * Regra da consulta: o que volta para a tela é EVIDÊNCIA com citação, ou
 * a resposta "não encontrei evidência suficiente". Nunca uma resposta
 * inventada. Este módulo não escreve prosa: entrega trechos, página e
 * proveniência para quem for compor a resposta (pessoa ou, mais tarde,
 * um assistente com as mesmas cercas).
 */

export const SEM_EVIDENCIA = "Não encontrei documentação suficiente para afirmar isso.";

export type KnowledgeEvidence = {
  chunkId: number;
  score: number;
  kind: string;
  content: string;
  tableData: Json | null;
  page: { from: number; to: number };
  headingPath: string[];
  codes: string[];
  version: { id: string; label: string; status: string };
  document: { id: string; title: string; type: string; sourceKey: string; accessLevel: string };
  citation: string;
};

export type KnowledgeAnswer =
  | { found: true; evidence: KnowledgeEvidence[] }
  | { found: false; message: string };

function citation(row: KnowledgeHitRow): string {
  const pages = row.page_from === row.page_to ? `p. ${row.page_from}` : `p. ${row.page_from}–${row.page_to}`;
  return `${row.title} ${row.version_label}, ${pages}`;
}

export function toEvidence(row: KnowledgeHitRow): KnowledgeEvidence {
  return {
    chunkId: row.chunk_id,
    score: Number(row.score),
    kind: row.kind,
    content: row.content,
    tableData: row.table_data,
    page: { from: row.page_from, to: row.page_to },
    headingPath: row.heading_path ?? [],
    codes: row.codes ?? [],
    version: { id: row.version_id, label: row.version_label, status: row.version_status },
    document: {
      id: row.document_id, title: row.title, type: row.document_type,
      sourceKey: row.source_key, accessLevel: row.access_level,
    },
    citation: citation(row),
  };
}

export async function ask(input: KnowledgeQuery): Promise<KnowledgeAnswer> {
  const rows = await repository.search(input);
  if (rows.length === 0) return { found: false, message: SEM_EVIDENCIA };
  return { found: true, evidence: rows.map(toEvidence) };
}

export async function provenance(chunkId: number): Promise<Json | null> {
  return repository.provenance(chunkId);
}
