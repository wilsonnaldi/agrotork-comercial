import type { Metadata } from "next";
import Link from "next/link";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { requirePermission } from "@/lib/auth/session";
import { createPurchaseAction } from "@/modules/purchases/actions";
import { getConditionOptions, getSupplierOptions } from "@/modules/purchases/service";
import { PurchaseForm } from "../purchase-form";

export const metadata: Metadata = { title: "Nova entrada" };

export default async function NewPurchasePage() {
  await requirePermission("purchases.manage");

  const [suppliers, conditions] = await Promise.all([getSupplierOptions(), getConditionOptions()]);

  // Sem fornecedor não há de quem comprar. Mandar a pessoa cadastrar é
  // melhor do que oferecer um seletor vazio.
  if (suppliers.length === 0) {
    return (
      <>
        <PageHeader title="Nova entrada" description="Antes, é preciso ter de quem comprar." />
        <Alert tone="info">
          Nenhum fornecedor cadastrado ainda.{" "}
          <Link href="/configuracoes/fornecedores/novo" className="font-medium underline">
            Cadastrar fornecedor
          </Link>
        </Alert>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Nova entrada"
        description="A nota nasce como rascunho. Nada entra no estoque até você confirmar o recebimento."
      />
      <PurchaseForm
        action={createPurchaseAction}
        suppliers={suppliers}
        conditions={conditions}
        submitLabel="Criar rascunho"
        cancelHref="/compras"
      />
    </>
  );
}
