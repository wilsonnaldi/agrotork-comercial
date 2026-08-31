import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { countUnitProducts, getUnit } from "@/modules/units/service";
import { toggleUnitActiveAction, updateUnitAction } from "@/modules/units/actions";
import { UnitForm } from "../unit-form";

export const metadata: Metadata = { title: "Editar unidade" };

export default async function EditUnitPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("catalog.manage");

  const { id } = await params;
  const unit = await getUnit(id);
  if (!unit) notFound();

  const productCount = await countUnitProducts(unit.id);

  return (
    <>
      <Link
        href="/configuracoes/unidades"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Unidades
      </Link>

      <PageHeader
        title={`${unit.code} · ${unit.name}`}
        description={`${productCount} produto(s) usam esta unidade`}
      />

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <UnitForm
            action={updateUnitAction}
            submitLabel="Salvar alterações"
            unit={{
              id: unit.id,
              code: unit.code,
              name: unit.name,
              allows_fraction: unit.allows_fraction,
              is_active: unit.is_active,
            }}
          />
        </div>

        <aside>
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={unit.is_active ? "success" : "warning"}>
                {unit.is_active ? "Ativa" : "Inativa"}
              </Badge>

              <form action={toggleUnitActiveAction}>
                <input type="hidden" name="id" value={unit.id} />
                <input type="hidden" name="activate" value={String(!unit.is_active)} />
                {unit.is_active ? (
                  <ConfirmButton
                    label="Desativar unidade"
                    confirmLabel="Sim, desativar"
                    question={
                      productCount > 0
                        ? `${productCount} produto(s) usam esta unidade. Eles continuam como estão — ela só deixa de ser oferecida em novos cadastros.`
                        : "A unidade deixa de ser oferecida em novos produtos."
                    }
                  />
                ) : (
                  <Button type="submit" variant="secondary" fullWidth>
                    Reativar unidade
                  </Button>
                )}
              </form>

              <p className="text-xs text-graphite-300">
                Unidades não são excluídas. O banco recusa apagar uma unidade com produto vinculado,
                e a desativação preserva todo o histórico.
              </p>
            </CardBody>
          </Card>
        </aside>
      </div>
    </>
  );
}
