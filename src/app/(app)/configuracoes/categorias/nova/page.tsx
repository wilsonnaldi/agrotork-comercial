import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { requirePermission } from "@/lib/auth/session";
import { createCategoryAction } from "@/modules/categories/actions";
import { CategoryForm } from "../category-form";

export const metadata: Metadata = { title: "Nova categoria" };

export default async function NewCategoryPage() {
  await requirePermission("catalog.manage");

  return (
    <>
      <PageHeader title="Nova categoria" description="Agrupamento usado para organizar o catálogo." />
      <CategoryForm action={createCategoryAction} submitLabel="Cadastrar categoria" />
    </>
  );
}
