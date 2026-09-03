import type { Metadata } from "next";
import Link from "next/link";
import { PackagePlus, Plus } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { purchaseFiltersSchema } from "@/modules/purchases/schema";
import { listPurchases } from "@/modules/purchases/service";
import { PURCHASE_STATUS_LABELS, PURCHASE_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Entradas" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function PurchasesPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("purchases.manage");

  const params = await searchParams;
  const filters = purchaseFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    supplier: pick(params.supplier),
    page: pick(params.page),
  });

  const result = await listPurchases(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/compras?${query}` : "/compras";
  };

  const isFiltered = Boolean(filters.q || filters.status !== "all");

  return (
    <>
      <PageHeader
        title="Entradas"
        description="A nota que chegou do fornecedor. É ela que atualiza o estoque e o custo."
        action={
          <Button asChild size="lg" className="hidden sm:inline-flex">
            <Link href="/compras/nova">
              <Plus className="size-4" aria-hidden />
              Nova entrada
            </Link>
          </Button>
        }
      />

      <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_auto]">
        <SearchInput placeholder="Buscar por número, nota ou fornecedor…" />
        <UrlSelect
          param="status"
          defaultValue="all"
          ariaLabel="Filtrar por situação"
          options={[
            { value: "all", label: "Todas as situações" },
            { value: "draft", label: "Rascunhos" },
            { value: "received", label: "Recebidas" },
            { value: "cancelled", label: "Canceladas" },
          ]}
        />
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={PackagePlus}
            title={isFiltered ? "Nenhuma entrada encontrada" : "Nenhuma entrada lançada"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Lance a nota que chegou: o estoque entra e o custo do produto se atualiza sozinho."
            }
            action={
              !isFiltered && (
                <Button asChild className="mt-2">
                  <Link href="/compras/nova">
                    <Plus className="size-4" aria-hidden />
                    Nova entrada
                  </Link>
                </Button>
              )
            }
          />
        ) : (
          <>
            <table className="hidden w-full text-sm lg:table">
              <thead>
                <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                  <th className="px-5 py-3 font-medium">Número</th>
                  <th className="px-5 py-3 font-medium">Fornecedor</th>
                  <th className="px-5 py-3 font-medium">Nota</th>
                  <th className="px-5 py-3 font-medium">Emissão</th>
                  <th className="px-5 py-3 text-right font-medium">Itens</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((nota) => (
                  <tr key={nota.id} className="hover:bg-sand">
                    <td className="px-5 py-3 tnum">
                      <Link href={`/compras/${nota.id}`} className="font-medium hover:text-brand">
                        {nota.number}
                      </Link>
                    </td>
                    <td className="px-5 py-3">
                      {nota.supplier_name}
                      {nota.supplier_city && (
                        <span className="block text-xs text-graphite-300">{nota.supplier_city}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">{nota.invoice_number || "—"}</td>
                    <td className="px-5 py-3 tnum text-graphite-500">{formatDate(nota.issue_date)}</td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">{nota.items_count}</td>
                    <td className="px-5 py-3 text-right tnum font-medium">
                      {formatCents(nota.total_cents)}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <Badge tone={PURCHASE_STATUS_TONE[nota.status]}>
                        {PURCHASE_STATUS_LABELS[nota.status]}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((nota) => (
                <li key={nota.id}>
                  <Link href={`/compras/${nota.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{nota.supplier_name}</p>
                        <p className="mt-0.5 truncate text-xs font-medium tnum text-graphite-300">
                          {nota.number}
                          {nota.invoice_number ? ` · NF ${nota.invoice_number}` : ""}
                        </p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          {formatDate(nota.issue_date)}
                          {` · ${nota.items_count} ${nota.items_count === 1 ? "item" : "itens"}`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(nota.total_cents)}</p>
                        <Badge tone={PURCHASE_STATUS_TONE[nota.status]} className="mt-1">
                          {PURCHASE_STATUS_LABELS[nota.status]}
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
              itemLabel="entradas"
              itemLabelSingular="entrada"
            />
          </>
        )}
      </Card>

      <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
        <Link href="/compras/nova">
          <Plus className="size-4" aria-hidden />
          Nova entrada
        </Link>
      </Button>
    </>
  );
}
