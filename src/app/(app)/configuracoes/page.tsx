import type { Metadata } from "next";
import Link from "next/link";
import { Boxes, Building2, ChevronRight, Ruler, Tags, Users } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { requirePermission } from "@/lib/auth/session";

export const metadata: Metadata = { title: "Configurações" };

const CADASTROS = [
  {
    href: "/configuracoes/marcas",
    icon: Building2,
    title: "Marcas",
    description: "Marca comercial que identifica o produto (ARAG, DJI, KUHN…).",
  },
  {
    href: "/configuracoes/categorias",
    icon: Tags,
    title: "Categorias",
    description: "Agrupamento de produtos: implementos, peças, pulverização…",
  },
  {
    href: "/configuracoes/unidades",
    icon: Ruler,
    title: "Unidades de medida",
    description: "UN, KG, L, M, JG, HR… usadas em produtos e orçamentos.",
  },
];

const EMPRESA = [
  {
    href: "/configuracoes/empresa",
    icon: Boxes,
    title: "Dados da empresa",
    description: "Cabeçalho do PDF e da página pública, mais o logotipo.",
  },
  {
    href: "/configuracoes/usuarios",
    icon: Users,
    title: "Usuários",
    description: "Papel de cada pessoa e quem continua com acesso.",
  },
];

export default async function SettingsPage() {
  // Esconder o menu não é controle de acesso: a verificação é no servidor.
  await requirePermission("settings.manage");

  return (
    <>
      <PageHeader title="Configurações" description="Cadastros que alimentam produtos, kits e orçamentos." />

      <h2 className="mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">Cadastros</h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {CADASTROS.map((item) => (
          <Link key={item.href} href={item.href}>
            <Card className="flex h-full items-start gap-3 p-4 transition-colors hover:border-brand/40 hover:bg-sand">
              <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-soft text-brand">
                <item.icon className="size-5" aria-hidden />
              </span>
              <div className="min-w-0 flex-1">
                <p className="font-medium">{item.title}</p>
                <p className="mt-0.5 text-xs text-graphite-500">{item.description}</p>
              </div>
              <ChevronRight className="mt-2 size-4 shrink-0 text-graphite-300" aria-hidden />
            </Card>
          </Link>
        ))}
      </div>

      <h2 className="mt-8 mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">
        Empresa e acesso
      </h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {EMPRESA.map((item) => (
          <Link key={item.href} href={item.href}>
            <Card className="flex h-full items-start gap-3 p-4 transition-colors hover:border-brand/40 hover:bg-sand">
              <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-soft text-brand">
                <item.icon className="size-5" aria-hidden />
              </span>
              <div className="min-w-0 flex-1">
                <p className="font-medium">{item.title}</p>
                <p className="mt-0.5 text-xs text-graphite-500">{item.description}</p>
              </div>
              <ChevronRight className="mt-2 size-4 shrink-0 text-graphite-300" aria-hidden />
            </Card>
          </Link>
        ))}
      </div>

    </>
  );
}
