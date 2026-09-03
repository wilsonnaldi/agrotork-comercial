import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { updateSupplierAction } from "@/modules/suppliers/actions";
import { getSupplier } from "@/modules/suppliers/service";
import { SupplierForm } from "../../supplier-form";

export const metadata: Metadata = { title: "Editar fornecedor" };

export default async function EditSupplierPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("suppliers.manage");

  const { id } = await params;
  const supplier = await getSupplier(id);
  if (!supplier) notFound();

  return (
    <>
      <PageHeader title="Editar fornecedor" description={supplier.name} />
      <SupplierForm
        action={updateSupplierAction}
        supplier={supplier}
        submitLabel="Salvar alterações"
        cancelHref={`/configuracoes/fornecedores/${supplier.id}`}
      />
    </>
  );
}
