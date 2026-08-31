import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { requirePermission } from "@/lib/auth/session";
import { createUnitAction } from "@/modules/units/actions";
import { UnitForm } from "../unit-form";

export const metadata: Metadata = { title: "Nova unidade" };

export default async function NewUnitPage() {
  await requirePermission("catalog.manage");

  return (
    <>
      <PageHeader title="Nova unidade" description="O código é a identidade da unidade e é único." />

      <Alert tone="info" className="mb-5 max-w-xl">
        Cada código é uma unidade distinta. <strong>L</strong> e <strong>LT</strong> não são tratados
        como equivalentes — se um dia forem, isso será uma decisão explícita, não uma suposição do
        sistema.
      </Alert>

      <UnitForm action={createUnitAction} submitLabel="Cadastrar unidade" />
    </>
  );
}
