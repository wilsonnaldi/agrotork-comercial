import type { Metadata } from "next";
import Link from "next/link";
import { Users, Package, Boxes, FileText, Wallet, Plus } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { StatCard } from "@/components/ui/stat-card";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Alert } from "@/components/ui/alert";
import { requireUser } from "@/lib/auth/session";
import { getDashboardSummary } from "@/modules/dashboard/repository";
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { formatCurrency, formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Painel" };

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ erro?: string }>;
}) {
  const { erro } = await searchParams;
  const user = await requireUser();
  const summary = await getDashboardSummary();
  // `full_name` vazio não é nulo, então o `||` caía no e-mail INTEIRO — e
  // `split(" ")` não corta e-mail nenhum. No celular isso virava três
  // linhas de caixa alta ocupando a tela toda. Sem nome cadastrado,
  // usamos só o que vem antes do @.
  const nomeCadastrado = user.profile.full_name?.trim();
  const firstName = nomeCadastrado
    ? nomeCadastrado.split(" ")[0]
    : (user.email.split("@")[0] ?? user.email);

  return (
    <>
      <PageHeader
        title={`Olá, ${firstName}`}
        description="Resumo da operação comercial."
        action={
          <Button asChild size="lg" className="hidden sm:inline-flex">
            <Link href="/orcamentos/novo">
              <Plus className="size-4" aria-hidden />
              Novo orçamento
            </Link>
          </Button>
        }
      />

      {erro === "sem-permissao" && (
        <Alert tone="error" className="mb-5">
          Você não tem permissão para acessar essa área.
        </Alert>
      )}

      <section className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-5">
        <StatCard label="Clientes" value={summary.customers} icon={Users} />
        <StatCard label="Produtos" value={summary.products} icon={Package} />
        <StatCard label="Kits" value={summary.kits} icon={Boxes} />
        <StatCard label="Em aberto" value={summary.openQuotes} icon={FileText} hint="Rascunho + enviados" />
        <StatCard
          label="Valor em aberto"
          value={formatCurrency(summary.openQuotesTotal)}
          icon={Wallet}
          accent
          className="col-span-2 lg:col-span-1"
        />
      </section>

      <Card className="mt-5 sm:mt-6">
        <CardHeader>
          <CardTitle>Orçamentos recentes</CardTitle>
          <Link href="/orcamentos" className="text-sm text-brand hover:underline">
            Ver todos
          </Link>
        </CardHeader>

        {summary.recentQuotes.length === 0 ? (
          <EmptyState
            icon={FileText}
            title="Nenhum orçamento ainda"
            description="Assim que o cadastro de clientes e produtos estiver pronto, os orçamentos aparecem aqui."
          />
        ) : (
          <ul className="divide-y divide-line">
            {summary.recentQuotes.map((quote) => (
              <li key={quote.id}>
                <Link
                  href={`/orcamentos/${quote.id}`}
                  className="flex items-center justify-between gap-3 px-4 py-3.5 hover:bg-sand sm:px-5"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{quote.customer_name}</p>
                    <p className="mt-0.5 text-xs text-graphite-300">
                      <span className="tnum">{quote.number}</span> · {formatDate(quote.issue_date)}
                    </p>
                  </div>
                  <div className="flex shrink-0 items-center gap-3">
                    <span className="tnum text-sm font-medium">{formatCurrency(quote.total)}</span>
                    <Badge tone={QUOTE_STATUS_TONE[quote.status]} className="hidden sm:inline-flex">
                      {QUOTE_STATUS_LABELS[quote.status]}
                    </Badge>
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
