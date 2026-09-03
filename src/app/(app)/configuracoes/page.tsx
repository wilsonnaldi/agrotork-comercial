import type { Metadata } from "next";
import Link from "next/link";
import { Boxes, Building2, ChevronRight, Percent, Ruler, Tags, Users } from "lucide-react";
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
  {
    href: "/configuracoes/margens",
    icon: Percent,
    title: "Margens por setor",
    description: "O percentual de lucro de cada setor, e o preço que ele sugere.",
  },
];

const PENDENTES = [
  { icon: Users, title: "Usuários", description: "Convite, papel e ativação", phase: "Fase 1" },
  { icon: Boxes, title: "Dados da empresa", description: "O que sai no cabeçalho do PDF", phase: "Fase 1" },
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
        Ainda por vir
      </h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {PENDENTES.map((item) => (
          <Card key={item.title} className="flex h-full items-start gap-3 p-4 opacity-60">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-sand text-graphite-300">
              <item.icon className="size-5" aria-hidden />
            </span>
            <div className="min-w-0 flex-1">
              <p className="font-medium">{item.title}</p>
              <p className="mt-0.5 text-xs text-graphite-500">{item.description}</p>
            </div>
            <span className="mt-1 text-xs text-graphite-300">{item.phase}</span>
          </Card>
        ))}
      </div>
    </>
  );
}
