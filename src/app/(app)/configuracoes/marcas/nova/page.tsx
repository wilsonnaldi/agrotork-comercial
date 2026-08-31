import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { createBrandAction } from "@/modules/brands/actions";
import { BrandForm } from "../brand-form";

export const metadata: Metadata = { title: "Nova marca" };

export default async function NewBrandPage() {
  await requirePermission("catalog.manage");

  return (
    <>
      <PageHeader title="Nova marca" description="Marca comercial que identifica o produto." />
      <BrandForm action={createBrandAction} submitLabel="Cadastrar marca" />
    </>
  );
}
