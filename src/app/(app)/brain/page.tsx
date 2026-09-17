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
 * Nesta versão NÃO há geração de resposta: o que aparece é a evidência
 * recuperada, com fonte, documento, versão e página. Primeiro provar que
 * recuperação, autorização e proveniência funcionam ponta a ponta.
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
