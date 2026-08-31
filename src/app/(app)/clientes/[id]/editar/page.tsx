import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { updateCustomerAction } from "@/modules/customers/actions";
import { getCustomer } from "@/modules/customers/service";
import { CustomerForm } from "../../customer-form";

export const metadata: Metadata = { title: "Editar cliente" };

export default async function EditCustomerPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("customers.write");

  const { id } = await params;
  const customer = await getCustomer(id);
  if (!customer) notFound();

  return (
    <>
      <PageHeader title="Editar cliente" description={customer.name} />
      <CustomerForm
        action={updateCustomerAction}
        customer={customer}
        submitLabel="Salvar alterações"
        cancelHref={`/clientes/${customer.id}`}
      />
    </>
  );
}
