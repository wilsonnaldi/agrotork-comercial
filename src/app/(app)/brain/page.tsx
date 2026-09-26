import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { BrainConsole } from "./brain-console";

export const metadata: Metadata = { title: "AGROTORK BRAIN" };

/**
 * Console de consulta à memória corporativa. A página exige a permissão
 * (e redireciona quem não a tem); a Server Action confere de novo e o banco
 * confere pela terceira vez — a tela é conforto, o RLS é a cerca.
 *
 * Desde a Answer v1 há resposta redigida por um provedor externo — mas só
 * sobre evidência já recuperada e autorizada, conferida pelo Answer Validator
 * e sempre com os trechos originais visíveis (fonte, documento, versão e
 * página). Sem provedor configurado, ou quando algum gate recusa, a resposta
 * é extractiva: montada localmente, sem modelo. Ver `synthesis.ts`.
 */
export default async function BrainPage() {
  const user = await requirePermission("knowledge.query");
  return (
    <>
      <PageHeader
        title="AGROTORK BRAIN"
        description="Consulte a memória técnica e comercial da AGROTORK."
      />
      <BrainConsole isAdmin={user.profile.role === "admin"} />
    </>
  );
}
