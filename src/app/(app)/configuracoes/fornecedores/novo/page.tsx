import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { createSupplierAction } from "@/modules/suppliers/actions";
import { SupplierForm } from "../supplier-form";

export const metadata: Metadata = { title: "Novo fornecedor" };

export default async function NewSupplierPage() {
  await requirePermission("suppliers.manage");

  return (
    <>
      <PageHeader
        title="Novo fornecedor"
        description="Só o nome é obrigatório — o resto pode vir depois."
      />
      <SupplierForm
        action={createSupplierAction}
        submitLabel="Cadastrar fornecedor"
        cancelHref="/configuracoes/fornecedores"
      />
    </>
  );
}
