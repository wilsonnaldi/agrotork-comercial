import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { requirePermission } from "@/lib/auth/session";
import { getConditionOptions, getProductOptions } from "@/modules/purchases/service";
import { ImportForm } from "./import-form";

export const metadata: Metadata = { title: "Importar NF-e" };

export default async function ImportPage() {
  await requirePermission("purchases.manage");

  const [conditions, products] = await Promise.all([
    getConditionOptions(),
    getProductOptions(),
  ]);

  return (
    <>
      <Link
        href="/compras"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Entradas
      </Link>

      <PageHeader
        title="Importar NF-e"
        description="O XML da nota vira a entrada pronta. O que o sistema não reconhecer, você aponta uma vez — e ele lembra."
        action={
          <Button asChild variant="secondary">
            <Link href="/compras/nova">Digitar à mão</Link>
          </Button>
        }
      />

      <ImportForm conditions={conditions} products={products} />
    </>
  );
}
