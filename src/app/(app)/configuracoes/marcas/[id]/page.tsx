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
import { countBrandProducts, getBrand } from "@/modules/brands/service";
import { toggleBrandActiveAction, updateBrandAction } from "@/modules/brands/actions";
import { BrandForm } from "../brand-form";

export const metadata: Metadata = { title: "Editar marca" };

export default async function EditBrandPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("catalog.manage");

  const { id } = await params;
  const brand = await getBrand(id);
  if (!brand) notFound();

  const productCount = await countBrandProducts(brand.id);

  return (
    <>
      <Link
        href="/configuracoes/marcas"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Marcas
      </Link>

      <PageHeader title={brand.name} description={`${productCount} produto(s) usam esta marca`} />

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <BrandForm
            action={updateBrandAction}
            submitLabel="Salvar alterações"
            brand={{
              id: brand.id,
              name: brand.name,
              description: brand.description,
              is_active: brand.is_active,
            }}
          />
        </div>

        <aside>
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={brand.is_active ? "success" : "warning"}>
                {brand.is_active ? "Ativa" : "Inativa"}
              </Badge>

              <form action={toggleBrandActiveAction}>
                <input type="hidden" name="id" value={brand.id} />
                <input type="hidden" name="activate" value={String(!brand.is_active)} />
                {brand.is_active ? (
                  <ConfirmButton
                    label="Desativar marca"
                    confirmLabel="Sim, desativar"
                    question={
                      productCount > 0
                        ? `${productCount} produto(s) usam esta marca. Eles continuam vinculados e nada é perdido — a marca só deixa de ser oferecida em novos cadastros.`
                        : "A marca deixa de ser oferecida em novos produtos."
                    }
                  />
                ) : (
                  <Button type="submit" variant="secondary" fullWidth>
                    Reativar marca
                  </Button>
                )}
              </form>

              <p className="text-xs text-graphite-300">
                Marcas não são excluídas. O banco recusa apagar uma marca com produto vinculado, e a
                desativação preserva todo o histórico.
              </p>
            </CardBody>
          </Card>
        </aside>
      </div>
    </>
  );
}
