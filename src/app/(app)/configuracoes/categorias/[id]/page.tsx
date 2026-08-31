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
import { countCategoryProducts, getCategory } from "@/modules/categories/service";
import { toggleCategoryActiveAction, updateCategoryAction } from "@/modules/categories/actions";
import { CategoryForm } from "../category-form";

export const metadata: Metadata = { title: "Editar categoria" };

export default async function EditCategoryPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("catalog.manage");

  const { id } = await params;
  const category = await getCategory(id);
  if (!category) notFound();

  const productCount = await countCategoryProducts(category.id);

  return (
    <>
      <Link
        href="/configuracoes/categorias"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Categorias
      </Link>

      <PageHeader title={category.name} description={`${productCount} produto(s) nesta categoria`} />

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <CategoryForm
            action={updateCategoryAction}
            submitLabel="Salvar alterações"
            category={{
              id: category.id,
              name: category.name,
              description: category.description,
              is_active: category.is_active,
            }}
          />
        </div>

        <aside>
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={category.is_active ? "success" : "warning"}>
                {category.is_active ? "Ativa" : "Inativa"}
              </Badge>

              <form action={toggleCategoryActiveAction}>
                <input type="hidden" name="id" value={category.id} />
                <input type="hidden" name="activate" value={String(!category.is_active)} />
                {category.is_active ? (
                  <ConfirmButton
                    label="Desativar categoria"
                    confirmLabel="Sim, desativar"
                    question={
                      productCount > 0
                        ? `${productCount} produto(s) estão nesta categoria. Eles continuam onde estão — ela só deixa de ser oferecida em novos cadastros.`
                        : "A categoria deixa de ser oferecida em novos produtos."
                    }
                  />
                ) : (
                  <Button type="submit" variant="secondary" fullWidth>
                    Reativar categoria
                  </Button>
                )}
              </form>

              <p className="text-xs text-graphite-300">
                Categorias não são excluídas. O banco recusa apagar uma categoria com produto
                vinculado, e a desativação preserva todo o histórico.
              </p>
            </CardBody>
          </Card>
        </aside>
      </div>
    </>
  );
}
