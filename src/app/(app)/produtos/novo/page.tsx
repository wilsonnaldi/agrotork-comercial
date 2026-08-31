import type { Metadata } from "next";
import Link from "next/link";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { createProductAction } from "@/modules/products/actions";
import { getCatalogOptions } from "@/modules/products/service";
import { ProductForm } from "../product-form";

export const metadata: Metadata = { title: "Novo produto" };

export default async function NewProductPage() {
  const user = await requirePermission("products.write");
  const options = await getCatalogOptions();

  // Sem unidade cadastrada não há como salvar: a unidade é obrigatória.
  if (options.units.length === 0) {
    return (
      <>
        <PageHeader title="Novo produto" />
        <Alert tone="error" title="Nenhuma unidade de medida cadastrada">
          O produto precisa de uma unidade (UN, KG, L…). Cadastre as unidades em{" "}
          <Link href="/configuracoes" className="underline">
            Configurações
          </Link>{" "}
          antes de continuar.
        </Alert>
      </>
    );
  }

  return (
    <>
      <PageHeader title="Novo produto" description="Código, nome, unidade e preço de venda bastam para começar." />
      <ProductForm
        action={createProductAction}
        options={options}
        canViewCost={can(user.profile.role, "products.viewCost")}
        submitLabel="Cadastrar produto"
        cancelHref="/produtos"
      />
    </>
  );
}
