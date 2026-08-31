import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { createCustomerAction } from "@/modules/customers/actions";
import { CustomerForm } from "../customer-form";

export const metadata: Metadata = { title: "Novo cliente" };

export default async function NewCustomerPage() {
  await requirePermission("customers.write");

  return (
    <>
      <PageHeader title="Novo cliente" description="Só o nome é obrigatório — o resto pode vir depois." />
      <CustomerForm action={createCustomerAction} submitLabel="Cadastrar cliente" cancelHref="/clientes" />
    </>
  );
}
