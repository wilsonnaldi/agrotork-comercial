import type { Metadata } from "next";
import Link from "next/link";
import { AlertTriangle, Wallet } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { financialFiltersSchema } from "@/modules/financial/schema";
import { listEntries } from "@/modules/financial/service";
import { DUE_SOON_DAYS, type EntryRow } from "@/modules/financial/types";
import { FINANCIAL_STATUS_LABELS, FINANCIAL_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Financeiro" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function FinancialPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("financial.manage");

  const params = await searchParams;
  const filters = financialFiltersSchema.parse({
    q: pick(params.q),
    kind: pick(params.kind),
    situacao: pick(params.situacao),
    page: pick(params.page),
  });

  const result = await listEntries(filters);
  const recebendo = filters.kind !== "payable";

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.kind !== "receivable") next.set("kind", filters.kind);
    if (filters.situacao !== "open") next.set("situacao", filters.situacao);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/financeiro?${query}` : "/financeiro";
  };

  const isFiltered = Boolean(filters.q || filters.situacao !== "open");

  return (
    <>
      <PageHeader
        title="Financeiro"
        description="O que entra e o que sai. O título nasce quando o pedido é faturado."
      />

      {typeof params.parcelado === "string" && (
        <Alert tone="success" className="mb-4">
          Título parcelado. As parcelas estão na lista, com os vencimentos.
        </Alert>
      )}

      {/* Os três números que se pergunta em voz alta. Somados sobre o
          recorte inteiro, não sobre a página — um total que muda ao
          virar a página não é informação, é armadilha. */}
      <div className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Resumo
          rotulo="Vencido"
          valor={result.summary.overdueCents}
          detalhe={
            result.summary.overdueCount === 0
              ? "nada em atraso"
              : result.summary.overdueCount === 1
                ? "1 título"
                : `${result.summary.overdueCount} títulos`
          }
          alerta={result.summary.overdueCents > 0}
          href="/financeiro?situacao=overdue"
        />
        <Resumo
          rotulo={`Vence em ${DUE_SOON_DAYS} dias`}
          valor={result.summary.dueSoonCents}
          detalhe="a acompanhar"
        />
        <Resumo
          rotulo={recebendo ? "Total a receber" : "Total a pagar"}
          valor={result.summary.openCents}
          detalhe="em aberto"
          className="col-span-2 lg:col-span-1"
        />
      </div>

      <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_auto_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder="Buscar por cliente, fornecedor ou documento…" />
        </div>
        <UrlSelect
          param="kind"
          defaultValue="receivable"
          ariaLabel="A receber ou a pagar"
          options={[
            { value: "receivable", label: "A receber" },
            { value: "payable", label: "A pagar" },
            { value: "all", label: "Tudo" },
          ]}
        />
        <UrlSelect
          param="situacao"
          defaultValue="open"
          ariaLabel="Filtrar por situação"
          options={[
            { value: "open", label: "Em aberto" },
            { value: "overdue", label: "Vencidos" },
            { value: "settled", label: "Quitados" },
            { value: "all", label: "Todos" },
          ]}
        />
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={Wallet}
            title={isFiltered ? "Nada nesta fatia" : "Nenhum título ainda"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "O título a receber nasce quando você fatura um pedido; o a pagar, quando dá entrada numa nota."
            }
          />
        ) : (
          <>
            <table className="hidden w-full text-sm lg:table">
              <thead>
                <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                  <th className="px-5 py-3 font-medium">Vencimento</th>
                  <th className="px-5 py-3 font-medium">{recebendo ? "Cliente" : "Fornecedor"}</th>
                  <th className="px-5 py-3 font-medium">Documento</th>
                  <th className="px-5 py-3 text-right font-medium">Valor</th>
                  <th className="px-5 py-3 text-right font-medium">Falta</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((titulo) => (
                  <tr key={titulo.id} className="hover:bg-sand">
                    <td className="px-5 py-3">
                      <Link href={`/financeiro/${titulo.id}`} className="tnum font-medium hover:text-brand">
                        {formatDate(titulo.due_date)}
                      </Link>
                      <Atraso titulo={titulo} />
                    </td>
                    <td className="px-5 py-3">{titulo.party_name}</td>
                    <td className="px-5 py-3 text-graphite-500">
                      {titulo.description}
                      {titulo.installments > 1 && (
                        <span className="ml-1.5 text-xs text-graphite-300">
                          {titulo.installment}/{titulo.installments}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right tnum">{formatCents(titulo.amount_cents)}</td>
                    <td className="px-5 py-3 text-right tnum font-medium">
                      {formatCents(titulo.open_cents)}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <Badge tone={FINANCIAL_STATUS_TONE[titulo.status]}>
                        {FINANCIAL_STATUS_LABELS[titulo.status]}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((titulo) => (
                <li key={titulo.id}>
                  <Link href={`/financeiro/${titulo.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{titulo.party_name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          {titulo.description}
                          {titulo.installments > 1 && ` · ${titulo.installment}/${titulo.installments}`}
                        </p>
                        <p className="mt-0.5 truncate text-xs tnum text-graphite-300">
                          vence {formatDate(titulo.due_date)}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(titulo.open_cents)}</p>
                        <Badge tone={FINANCIAL_STATUS_TONE[titulo.status]} className="mt-1">
                          {FINANCIAL_STATUS_LABELS[titulo.status]}
                        </Badge>
                      </div>
                    </div>
                  </Link>
                </li>
              ))}
            </ul>

            <Pagination
              page={result.page}
              pageCount={result.pageCount}
              total={result.total}
              buildHref={buildHref}
              itemLabel="títulos"
              itemLabelSingular="título"
            />
          </>
        )}
      </Card>
    </>
  );
}

function Resumo({
  rotulo,
  valor,
  detalhe,
  alerta,
  href,
  className,
}: {
  rotulo: string;
  valor: number;
  detalhe: string;
  alerta?: boolean;
  href?: string;
  className?: string;
}) {
  const conteudo = (
    <Card className={`h-full p-4 ${alerta ? "border-brand/40 bg-brand-soft" : ""} ${className ?? ""}`}>
      <p className="flex items-center gap-1.5 text-xs text-graphite-500">
        {alerta && <AlertTriangle className="size-3.5 shrink-0 text-brand" aria-hidden />}
        {rotulo}
      </p>
      <p className={`mt-1 tnum text-xl font-medium ${alerta ? "text-brand-deep" : ""}`}>
        {formatCents(valor)}
      </p>
      <p className="mt-0.5 text-xs text-graphite-300">{detalhe}</p>
    </Card>
  );

  return href && valor > 0 ? <Link href={href}>{conteudo}</Link> : conteudo;
}

/** Atraso em dias, no lugar onde a pessoa já está olhando: a data. */
function Atraso({ titulo }: { titulo: EntryRow }) {
  if (!titulo.is_overdue) return null;
  return (
    <span className="block text-xs font-medium text-brand-deep">
      {titulo.days_overdue === 1 ? "1 dia de atraso" : `${titulo.days_overdue} dias de atraso`}
    </span>
  );
}
