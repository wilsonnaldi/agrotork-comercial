import type { Metadata } from "next";
import Link from "next/link";
import { FileText, Plus } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";
import { quoteFiltersSchema } from "@/modules/quotes/schema";
import { getOwnerOptions, listQuotes } from "@/modules/quotes/service";

export const metadata: Metadata = { title: "Orçamentos" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

const STATUS_OPTIONS = [
  { value: "all", label: "Todas as situações" },
  { value: "draft", label: "Rascunho" },
  { value: "sent", label: "Enviado" },
  { value: "approved", label: "Aprovado" },
  { value: "rejected", label: "Recusado" },
  { value: "expired", label: "Expirado" },
  { value: "cancelled", label: "Cancelado" },
];

export default async function QuotesPage({ searchParams }: { searchParams: SearchParams }) {
  const user = await requirePermission("quotes.readOwn");
  const canReadAll = can(user.profile.role, "quotes.readAll");

  const params = await searchParams;
  const filters = quoteFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    customer: pick(params.customer),
    // O filtro por vendedor é do administrador. Para o vendedor o RLS já
    // devolve só os dele — não é a tela que decide isso.
    owner: canReadAll ? pick(params.owner) : undefined,
    sort: pick(params.sort),
    page: pick(params.page),
  });

  const [result, owners] = await Promise.all([
    listQuotes(filters),
    canReadAll ? getOwnerOptions() : Promise.resolve([]),
  ]);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (filters.customer) next.set("customer", filters.customer);
    if (filters.owner) next.set("owner", filters.owner);
    if (filters.sort !== "recent") next.set("sort", filters.sort);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/orcamentos?${query}` : "/orcamentos";
  };

  const isFiltered = Boolean(filters.q || filters.status !== "all" || filters.customer || filters.owner);

  return (
    <>
      <PageHeader
        title="Orçamentos"
        description={canReadAll ? "Todas as propostas da equipe." : "Suas propostas comerciais."}
        action={
          <Button asChild size="lg" className="hidden sm:inline-flex">
            <Link href="/orcamentos/novo">
              <Plus className="size-4" aria-hidden />
              Novo orçamento
            </Link>
          </Button>
        }
      />

      {typeof params.descartado === "string" && (
        <Alert tone="success" className="mb-4">
          Rascunho descartado.
        </Alert>
      )}

      <div className="mb-4 space-y-3">
        <SearchInput placeholder="Buscar por número ou cliente…" />
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
          <UrlSelect param="status" defaultValue="all" ariaLabel="Filtrar por situação" options={STATUS_OPTIONS} />
          {canReadAll && (
            <UrlSelect
              param="owner"
              ariaLabel="Filtrar por vendedor"
              options={[
                { value: "", label: "Todos os vendedores" },
                ...owners.map((owner) => ({ value: owner.id, label: owner.name })),
              ]}
            />
          )}
          <UrlSelect
            param="sort"
            defaultValue="recent"
            ariaLabel="Ordenar"
            options={[
              { value: "recent", label: "Ordem: mais recentes" },
              { value: "number", label: "Ordem: número" },
              { value: "total", label: "Ordem: maior valor" },
              { value: "customer", label: "Ordem: cliente" },
            ]}
          />
        </div>
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={FileText}
            title={isFiltered ? "Nenhum orçamento encontrado" : "Nenhum orçamento ainda"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Crie a primeira proposta: escolha o cliente, adicione produtos e kits."
            }
            action={
              !isFiltered && (
                <Button asChild className="mt-2">
                  <Link href="/orcamentos/novo">
                    <Plus className="size-4" aria-hidden />
                    Novo orçamento
                  </Link>
                </Button>
              )
            }
          />
        ) : (
          <>
            {/* Desktop: tabela. Celular: a mesma informação em lista. */}
            <table className="hidden w-full text-sm lg:table">
              <thead>
                <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                  <th className="px-5 py-3 font-medium">Número</th>
                  <th className="px-5 py-3 font-medium">Cliente</th>
                  {canReadAll && <th className="px-5 py-3 font-medium">Vendedor</th>}
                  <th className="px-5 py-3 font-medium">Emissão</th>
                  <th className="px-5 py-3 font-medium">Validade</th>
                  <th className="px-5 py-3 text-right font-medium">Itens</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((quote) => (
                  <tr key={quote.id} className="hover:bg-sand">
                    <td className="px-5 py-3 tnum">
                      <Link href={`/orcamentos/${quote.id}`} className="font-medium hover:text-brand">
                        {quote.number}
                      </Link>
                    </td>
                    <td className="px-5 py-3">
                      {quote.customer_name}
                      {quote.customer_city && (
                        <span className="block text-xs text-graphite-300">{quote.customer_city}</span>
                      )}
                    </td>
                    {canReadAll && <td className="px-5 py-3 text-graphite-500">{quote.owner_name}</td>}
                    <td className="px-5 py-3 tnum text-graphite-500">{formatDate(quote.issue_date)}</td>
                    <td className="px-5 py-3 tnum text-graphite-500">{formatDate(quote.valid_until)}</td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">{quote.items_count}</td>
                    <td className="px-5 py-3 text-right tnum font-medium">{formatCents(quote.total_cents)}</td>
                    <td className="px-5 py-3 text-right">
                      <Badge tone={QUOTE_STATUS_TONE[quote.status]}>
                        {QUOTE_STATUS_LABELS[quote.status]}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((quote) => (
                <li key={quote.id}>
                  <Link href={`/orcamentos/${quote.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{quote.customer_name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          <span className="tnum">{quote.number}</span>
                          {` · ${formatDate(quote.issue_date)}`}
                          {` · ${quote.items_count} item(ns)`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(quote.total_cents)}</p>
                        <Badge tone={QUOTE_STATUS_TONE[quote.status]} className="mt-1">
                          {QUOTE_STATUS_LABELS[quote.status]}
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
              itemLabel="orçamentos"
            />
          </>
        )}
      </Card>

      <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
        <Link href="/orcamentos/novo">
          <Plus className="size-4" aria-hidden />
          Novo orçamento
        </Link>
      </Button>
    </>
  );
}
