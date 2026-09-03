import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { Alert } from "@/components/ui/alert";
import { requirePermission } from "@/lib/auth/session";
import { getCompany } from "@/modules/settings/service";
import { removeLogoAction, saveCompanyAction, uploadLogoAction } from "@/modules/settings/actions";
import { CompanyForm } from "./company-form";
import { LogoForm } from "./logo-form";

export const metadata: Metadata = { title: "Dados da empresa" };

export default async function CompanyPage({
  searchParams,
}: {
  searchParams: Promise<{ salvo?: string; logo?: string }>;
}) {
  // Esconder o menu não é controle de acesso: quem decide é o servidor,
  // e o RLS recusa a escrita mesmo que alguém chame a action direto.
  await requirePermission("settings.manage");

  const [empresa, params] = await Promise.all([getCompany(), searchParams]);

  return (
    <>
      <PageHeader
        title="Dados da empresa"
        description="Sai no cabeçalho do PDF e na página pública do orçamento."
      />

      {params.salvo && <Alert tone="success">Dados da empresa salvos.</Alert>}
      {params.logo === "1" && <Alert tone="success">Logotipo atualizado.</Alert>}
      {params.logo === "0" && <Alert tone="success">Logotipo removido do cabeçalho.</Alert>}

      <div className="mt-4 space-y-6">
        <section className="max-w-2xl">
          <h2 className="mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">Logotipo</h2>
          <LogoForm action={uploadLogoAction} removeAction={removeLogoAction} logoUrl={empresa.logo_url} />
        </section>

        <section>
          <h2 className="mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">Identificação</h2>
          <CompanyForm action={saveCompanyAction} empresa={empresa} />
        </section>
      </div>
    </>
  );
}
