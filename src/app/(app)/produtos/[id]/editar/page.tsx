import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { updateProductAction } from "@/modules/products/actions";
import { getCatalogOptions, getProduct } from "@/modules/products/service";
import { ProductForm } from "../../product-form";

export const metadata: Metadata = { title: "Editar produto" };

export default async function EditProductPage({ params }: { params: Promise<{ id: string }> }) {
  const user = await requirePermission("products.write");

  const { id } = await params;
  const [product, options] = await Promise.all([getProduct(id), getCatalogOptions()]);
  if (!product) notFound();

  return (
    <>
      <PageHeader title="Editar produto" description={`${product.code} · ${product.name}`} />
      <ProductForm
        action={updateProductAction}
        product={product}
        options={options}
        canViewCost={can(user.profile.role, "products.viewCost")}
        submitLabel="Salvar alterações"
        cancelHref={`/produtos/${product.id}`}
      />
    </>
  );
}
