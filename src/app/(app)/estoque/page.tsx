import type { Metadata } from "next";
import Link from "next/link";
import { AlertTriangle, Warehouse } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { stockFiltersSchema } from "@/modules/stock/schema";
import { listStock } from "@/modules/stock/service";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Estoque" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

/** `numeric(14,3)` chega como número; a tela fala em milésimos. */
const toMilli = (quantity: number) => Math.round(quantity * 1000);

export default async function StockPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("stock.read");

  const params = await searchParams;
  const filters = stockFiltersSchema.parse({
    q: pick(params.q),
    category: pick(params.category),
    situacao: pick(params.situacao),
    sort: pick(params.sort),
    page: pick(params.page),
  });

  const result = await listStock(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.situacao !== "all") next.set("situacao", filters.situacao);
    if (filters.sort !== "name") next.set("sort", filters.sort);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/estoque?${query}` : "/estoque";
  };

  const isFiltered = Boolean(filters.q || filters.situacao !== "all");

  return (
    <>
      <PageHeader
        title="Estoque"
        description="O saldo é a soma dos lançamentos — nunca um número digitado."
      />

      {/* O negativo é o recado principal desta tela: é a lista do que
          precisa ser acertado. Aparece mesmo quando a pessoa está
          olhando outra fatia. */}
      {result.negativeCount > 0 && filters.situacao !== "negative" && (
        <Alert tone="warning" className="mb-4">
          <span className="flex flex-wrap items-center gap-x-1.5">
            <AlertTriangle className="size-4 shrink-0" aria-hidden />
            {result.negativeCount === 1
              ? "1 produto está com saldo negativo."
              : `${result.negativeCount} produtos estão com saldo negativo.`}
            <Link href="/estoque?situacao=negative" className="font-medium underline">
              Ver a lista
            </Link>
          </span>
        </Alert>
      )}

      <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_auto_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder="Buscar por nome ou código…" />
        </div>
        <UrlSelect
          param="situacao"
          defaultValue="all"
          ariaLabel="Filtrar por saldo"
          options={[
            { value: "all", label: "Todos os saldos" },
            { value: "negative", label: "Negativos" },
            { value: "zero", label: "Zerados" },
            { value: "positive", label: "Com saldo" },
          ]}
        />
        <UrlSelect
          param="sort"
          defaultValue="name"
          ariaLabel="Ordenar"
          options={[
            { value: "name", label: "Ordem: nome" },
            { value: "quantity", label: "Ordem: menor saldo" },
            { value: "recent", label: "Ordem: movimentado" },
          ]}
        />
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={Warehouse}
            title={isFiltered ? "Nenhum produto nesta fatia" : "Nenhum produto no catálogo"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Cadastre produtos para começar a controlar o estoque."
            }
          />
        ) : (
          <>
            <table className="hidden w-full text-sm lg:table">
              <thead>
                <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                  <th className="px-5 py-3 font-medium">Produto</th>
                  <th className="px-5 py-3 font-medium">Código</th>
                  <th className="px-5 py-3 font-medium">Último movimento</th>
                  <th className="px-5 py-3 text-right font-medium">Saldo</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((row) => (
                  <tr key={row.product_id} className="hover:bg-sand">
                    <td className="px-5 py-3">
                      <Link href={`/estoque/${row.product_id}`} className="font-medium hover:text-brand">
                        {row.name}
                      </Link>
                      {row.tracks_serial && (
                        <span className="ml-2 text-xs text-graphite-300">com número de série</span>
                      )}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">{row.code}</td>
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {formatDate(row.last_movement_at) || "—"}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <Saldo quantity={row.quantity} unit={row.unit_code} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((row) => (
                <li key={row.product_id}>
                  <Link href={`/estoque/${row.product_id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{row.name}</p>
                        <p className="mt-0.5 truncate text-xs tnum text-graphite-300">{row.code}</p>
                      </div>
                      <div className="shrink-0 text-right">
                        <Saldo quantity={row.quantity} unit={row.unit_code} />
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
              itemLabel="produtos"
              itemLabelSingular="produto"
            />
          </>
        )}
      </Card>
    </>
  );
}

/**
 * Saldo negativo tem que doer de olhar: é dívida de contagem, não um
 * número qualquer. Zero fica cinza — não é problema, é "ninguém contou".
 */
function Saldo({ quantity, unit }: { quantity: number; unit: string | null }) {
  const milli = toMilli(quantity);
  if (milli < 0) {
    return (
      <Badge tone="danger">
        {formatQuantity(milli)}
        {unit ? ` ${unit}` : ""}
      </Badge>
    );
  }
  return (
    <span className={milli === 0 ? "tnum text-graphite-300" : "tnum font-medium"}>
      {formatQuantity(milli)}
      {unit ? <span className="text-graphite-300"> {unit}</span> : null}
    </span>
  );
}
