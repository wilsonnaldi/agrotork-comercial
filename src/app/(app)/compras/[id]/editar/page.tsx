import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { updatePurchaseAction } from "@/modules/purchases/actions";
import {
  getConditionOptions,
  getPurchaseWithItems,
  getSupplierOptions,
} from "@/modules/purchases/service";
import { isEditable } from "@/modules/purchases/types";
import { PurchaseForm } from "../../purchase-form";

export const metadata: Metadata = { title: "Editar entrada" };

export default async function EditPurchasePage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("purchases.manage");

  const { id } = await params;
  const purchase = await getPurchaseWithItems(id);
  if (!purchase) notFound();

  // A rota é bloqueada no servidor, e não só escondida na ficha: quem
  // digita o endereço direto recebe a mesma recusa.
  if (!isEditable(purchase.status)) {
    redirect(`/compras/${id}?erro=${encodeURIComponent("Só rascunho se edita. Esta nota já foi recebida.")}`);
  }

  const [suppliers, conditions] = await Promise.all([getSupplierOptions(), getConditionOptions()]);

  return (
    <>
      <PageHeader title={`Editar ${purchase.number}`} description={purchase.supplier_name} />
      <PurchaseForm
        action={updatePurchaseAction}
        purchase={purchase}
        suppliers={suppliers}
        conditions={conditions}
        submitLabel="Salvar alterações"
        cancelHref={`/compras/${purchase.id}`}
      />
    </>
  );
}
