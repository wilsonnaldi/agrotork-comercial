import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { requirePermission } from "@/lib/auth/session";
import { createKitAction } from "@/modules/kits/actions";
import { KitForm } from "../kit-form";

export const metadata: Metadata = { title: "Novo kit" };

export default async function NewKitPage() {
  await requirePermission("kits.write");

  return (
    <>
      <Link
        href="/kits"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Kits
      </Link>

      <PageHeader title="Novo kit" description="Primeiro o cabeçalho; a composição vem em seguida." />

      <Alert tone="info" className="mb-5 max-w-xl">
        Depois de salvar, você cai direto na montagem do kit, onde escolhe os produtos
        <strong> obrigatórios</strong> e os <strong>opcionais</strong>.
      </Alert>

      <KitForm action={createKitAction} submitLabel="Criar e montar" />
    </>
  );
}
