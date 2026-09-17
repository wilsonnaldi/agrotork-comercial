import type { Json } from "@/types/db";

/**
 * A parte PURA do módulo: tipos, rótulos, citação, sanitização e recusa.
 *
 * Mora fora de `service.ts` porque `service.ts` é `server-only` e fala com o
 * repositório — não dá para exercitar sem banco nem sem runtime de servidor.
 * O que decide o que o usuário enxerga (e o que ele não enxerga) é justamente
 * isto aqui, então tem de ser testável sozinho: `supabase/db-tests/check-brain.mjs`.
 */

export const SEM_EVIDENCIA =
  "Não encontrei documentação suficiente para responder com segurança.";
export const SEM_PERMISSAO = "Seu perfil não tem acesso à memória corporativa.";
export const ERRO_CONSULTA = "Não foi possível consultar a memória agora.";

/** `answered` só existe com pelo menos uma evidência. Os outros três são recusa. */
export type KnowledgeStatus = "answered" | "no_evidence" | "forbidden" | "error";

/** A linha crua que `public.brain_search` devolve. */
export type KnowledgeHitRow = {
  chunk_id: number;
  score: number;
  rank_exact: number | null;
  rank_trgm: number | null;
  rank_fts: number | null;
  kind: string;
  content: string;
  table_data: Json | null;
  page_from: number;
  page_to: number;
  heading_path: string[];
  codes: string[];
  version_id: string;
  version_label: string;
  version_status: string;
  document_id: string;
  title: string;
  document_type: string;
  source_key: string;
  access_level: string;
  storage_path: string;
  file_sha256: string;
};

/**
 * O que a tela recebe. Sem UUID, sem caminho de Storage, sem sha256: o
 * usuário identifica o documento pelo nome, pela versão e pela página — que é
 * o que ele abriria para conferir. `debug` só é preenchido para admin.
 */
export type KnowledgeEvidence = {
  chunkId: number;
  kind: string;
  content: string;
  tableData: Json | null;
  page: { from: number; to: number };
  headingPath: string[];
  codes: string[];
  source: string;
  document: { title: string; type: string };
  version: { label: string; status: string };
  accessLevel: string;
  citation: string;
  debug?: {
    chunkId: number;
    score: number;
    rankExact: number | null;
    rankTrgm: number | null;
    rankFts: number | null;
    versionId: string;
    documentId: string;
    sourceKey: string;
  };
};

export type KnowledgeAnswer = {
  query: string;
  status: KnowledgeStatus;
  evidence: KnowledgeEvidence[];
  refusalReason?: string;
};

/**
 * Nome de exibição da fonte. A chave técnica (`agrotork_interno`) não é para
 * o usuário; sem tradução, mostra a chave — que é melhor do que nada, e ainda
 * assim nunca é um id.
 */
const NOME_DA_FONTE: Record<string, string> = {
  magnojet: "Magnojet",
  agrotork_interno: "AGROTORK — documentos internos",
  allcomp: "ALLCOMP",
  jr_solucoes: "JR Soluções",
};

export function sourceLabel(key: string): string {
  return NOME_DA_FONTE[key] ?? key;
}

export function citation(row: KnowledgeHitRow): string {
  const pages =
    row.page_from === row.page_to ? `p. ${row.page_from}` : `p. ${row.page_from}–${row.page_to}`;
  return `${sourceLabel(row.source_key)} — ${row.title} ${row.version_label} · ${pages}`;
}

export function toEvidence(row: KnowledgeHitRow, comDebug: boolean): KnowledgeEvidence {
  const evidencia: KnowledgeEvidence = {
    chunkId: row.chunk_id,
    kind: row.kind,
    content: row.content,
    tableData: row.table_data,
    page: { from: row.page_from, to: row.page_to },
    headingPath: row.heading_path ?? [],
    codes: row.codes ?? [],
    source: sourceLabel(row.source_key),
    document: { title: row.title, type: row.document_type },
    version: { label: row.version_label, status: row.version_status },
    accessLevel: row.access_level,
    citation: citation(row),
  };
  if (comDebug) {
    evidencia.debug = {
      chunkId: row.chunk_id,
      score: Number(row.score),
      rankExact: row.rank_exact,
      rankTrgm: row.rank_trgm,
      rankFts: row.rank_fts,
      versionId: row.version_id,
      documentId: row.document_id,
      sourceKey: row.source_key,
    };
  }
  return evidencia;
}

export function refusal(
  query: string,
  status: Exclude<KnowledgeStatus, "answered">,
  motivo?: string,
): KnowledgeAnswer {
  const padrao =
    status === "forbidden" ? SEM_PERMISSAO : status === "error" ? ERRO_CONSULTA : SEM_EVIDENCIA;
  return { query, status, evidence: [], refusalReason: motivo ?? padrao };
}
