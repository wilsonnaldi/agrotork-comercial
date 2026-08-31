import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { requirePermission } from "@/lib/auth/session";
import { getCustomerOptions } from "@/modules/quotes/service";
import { createQuoteAction } from "@/modules/quotes/actions";
import { QuoteHeaderForm } from "../quote-header-form";

export const metadata: Metadata = { title: "Novo orçamento" };

export default async function NewQuotePage() {
  await requirePermission("quotes.write");

  const customers = await getCustomerOptions();

  return (
    <>
      <Link
        href="/orcamentos"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Orçamentos
      </Link>

      <PageHeader title="Novo orçamento" description="Primeiro o cliente; os itens vêm em seguida." />

      {customers.length === 0 ? (
        <Alert tone="warning" className="max-w-2xl">
          <strong>Nenhum cliente ativo.</strong> Um orçamento precisa de cliente — cadastre um antes de
          continuar.
          <Button asChild variant="secondary" className="mt-3">
            <Link href="/clientes/novo">Cadastrar cliente</Link>
          </Button>
        </Alert>
      ) : (
        <>
          <Alert tone="info" className="mb-5 max-w-2xl">
            O número do orçamento é gerado pelo sistema ao salvar. Depois disso você cai direto na
            montagem, onde adiciona produtos e kits.
          </Alert>

          <QuoteHeaderForm
            action={createQuoteAction}
            submitLabel="Criar e montar"
            customers={customers}
            cancelHref="/orcamentos"
          />
        </>
      )}
    </>
  );
}
