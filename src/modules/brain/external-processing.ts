/**
 * O gate de processamento externo — a fronteira entre "posso LER isto" e
 * "isto pode SAIR daqui". São perguntas diferentes com respostas
 * independentes, e é fácil confundi-las quando se está com pressa de mostrar
 * uma resposta bonita.
 *
 * O orçamento interno ARAG, em produção, é o exemplo vivo: um administrador
 * pode consultá-lo (RLS diz sim) e ele NÃO pode ser enviado a um provedor de
 * LLM (`external_processing_for` diz `forbidden`). As duas coisas ao mesmo
 * tempo, e nenhuma delas cede para a outra.
 *
 * A regra da casa, vinda de `brain.external_processing_for`:
 *
 *   allowed  <  approved_provider_only  <  forbidden
 *
 * Nesta versão, **só `allowed` sai**. `approved_provider_only` exige um
 * provedor formalmente aprovado, e a AGROTORK não aprovou nenhum ainda —
 * tratar como permissão seria inventar uma aprovação que não existe.
 */

export type ExternalPolicy = "allowed" | "approved_provider_only" | "forbidden";

/** Ausência é proibição. Se a política não veio, não sai. */
export function parsePolicy(valor: string | null | undefined): ExternalPolicy {
  return valor === "allowed" || valor === "approved_provider_only" ? valor : "forbidden";
}

export function mayLeave(policy: ExternalPolicy): boolean {
  return policy === "allowed";
}

/**
 * O mínimo que o gate precisa saber de cada evidência. Montado no servidor a
 * partir da linha crua da busca — o `documentId` NÃO mora em
 * `KnowledgeEvidence`, justamente para não haver um id circulando até a tela
 * só porque o gate precisava dele.
 */
export type EvidenceRef = {
  chunkId: number;
  documentId: string;
  documentTitle: string;
};

export type ExternalDecision = {
  /** Pode chamar o provedor externo com ESTAS evidências. */
  allowed: boolean;
  /** Os trechos liberados a sair. Vazio quando `allowed` é falso. */
  sendableChunkIds: number[];
  /** Os que ficam, e por quê — para a tela dizer a verdade. */
  blocked: { chunkId: number; document: string; policy: ExternalPolicy }[];
  reason?: string;
};

/**
 * Decide o que pode ser enviado.
 *
 * Desenho conservador e deliberado: **basta uma evidência proibida para a
 * síntese externa inteira não acontecer.** Não se manda "só a parte
 * liberada": a pergunta e a resposta seriam moldadas pelo que ficou de fora,
 * e o recorte silencioso é justamente o tipo de vazamento que ninguém audita
 * depois. Ou vai o conjunto, ou não vai nada.
 *
 * `policyByDocumentId` vem de `public.brain_external_processing`. Documento
 * ausente do mapa — porque o RLS não o devolveu, porque a migration ainda não
 * foi aplicada, porque a chamada falhou — cai em `forbidden`. O gate falha
 * fechado em todos esses casos, e é por isso que ele é seguro antes mesmo de
 * a migration existir no banco.
 */
export function assessExternalProcessing(
  refs: EvidenceRef[],
  policyByDocumentId: Map<string, ExternalPolicy>,
): ExternalDecision {
  const blocked: ExternalDecision["blocked"] = [];

  for (const r of refs) {
    const policy = parsePolicy(policyByDocumentId.get(r.documentId));
    if (!mayLeave(policy)) {
      blocked.push({ chunkId: r.chunkId, document: r.documentTitle, policy });
    }
  }

  if (blocked.length > 0) {
    const documentos = [...new Set(blocked.map((b) => b.document))];
    return {
      allowed: false,
      sendableChunkIds: [],
      blocked,
      reason:
        `${documentos.length === 1 ? "O documento" : "Os documentos"} ` +
        `${documentos.map((d) => `"${d}"`).join(", ")} ` +
        `${documentos.length === 1 ? "não pode" : "não podem"} ser processado${documentos.length === 1 ? "" : "s"} por um serviço externo.`,
    };
  }

  return { allowed: true, sendableChunkIds: refs.map((r) => r.chunkId), blocked: [] };
}
