import { Construction } from "lucide-react";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";

/**
 * Marcador de módulo ainda não implementado.
 * Existe para que a navegação já funcione — ver ROADMAP.md.
 */
export function ComingSoon({
  title,
  description,
  phase,
}: {
  title: string;
  description: string;
  phase: string;
}) {
  return (
    <>
      <PageHeader title={title} description={description} />
      <Card>
        <EmptyState
          icon={Construction}
          title={`${phase} do roadmap`}
          description="Este módulo ainda não foi implementado. A estrutura, o banco e as permissões já estão prontos para recebê-lo."
        />
      </Card>
    </>
  );
}
