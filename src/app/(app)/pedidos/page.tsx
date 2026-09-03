import type { Metadata } from "next";
import Link from "next/link";
import { ClipboardCheck } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { ORDER_STATUS_LABELS, ORDER_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";
import { orderFiltersSchema } from "@/modules/orders/schema";
import { getOwnerOptions, listOrders } from "@/modules/orders/service";

export const metadata: Metadata = { title: "Pedidos" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

const STATUS_OPTIONS = [
  { value: "all", label: "Todas as situações" },
  { value: "confirmed", label: "Confirmado" },
  { value: "picking", label: "Em separação" },
  { value: "invoiced", label: "Faturado" },
  { value: "delivered", label: "Entregue" },
  { value: "cancelled", label: "Cancelado" },
];

export default async function OrdersPage({ searchParams }: { searchParams: SearchParams }) {
  const user = await requirePermission("orders.read");
  // Quem enxerga orçamento de todos enxerga pedido de todos: é a mesma
  // pessoa e o mesmo alcance. O RLS já decide; isto é só o filtro da tela.
  const canReadAll = can(user.profile.role, "quotes.readAll");

  const params = await searchParams;
  const filters = orderFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    customer: pick(params.customer),
    owner: canReadAll ? pick(params.owner) : undefined,
    sort: pick(params.sort),
    page: pick(params.page),
  });

  const [result, owners] = await Promise.all([
    listOrders(filters),
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
    return query ? `/pedidos?${query}` : "/pedidos";
  };

  const isFiltered = Boolean(filters.q || filters.status !== "all" || filters.customer || filters.owner);

  return (
    <>
      <PageHeader
        title="Pedidos"
        description={canReadAll ? "Todos os negócios fechados da equipe." : "Seus negócios fechados."}
      />

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
            icon={ClipboardCheck}
            title={isFiltered ? "Nenhum pedido encontrado" : "Nenhum pedido ainda"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "O pedido nasce de um orçamento aprovado: abra o orçamento e use “Gerar pedido”."
            }
            action={
              !isFiltered && (
                <Button asChild variant="secondary" className="mt-2">
                  <Link href="/orcamentos?status=approved">Ver orçamentos aprovados</Link>
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
                  <th className="px-5 py-3 font-medium">Previsão</th>
                  <th className="px-5 py-3 text-right font-medium">Itens</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((order) => (
                  <tr key={order.id} className="hover:bg-sand">
                    <td className="px-5 py-3 tnum">
                      <Link href={`/pedidos/${order.id}`} className="font-medium hover:text-brand">
                        {order.number}
                      </Link>
                    </td>
                    <td className="px-5 py-3">
                      {order.customer_name}
                      {order.customer_city && (
                        <span className="block text-xs text-graphite-300">{order.customer_city}</span>
                      )}
                    </td>
                    {canReadAll && (
                      <td className="px-5 py-3 text-graphite-500">
                        {order.owner_name?.trim() || "—"}
                      </td>
                    )}
                    <td className="px-5 py-3 tnum text-graphite-500">{formatDate(order.issue_date)}</td>
                    <td className="px-5 py-3 tnum text-graphite-500">{formatDate(order.delivery_forecast)}</td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">{order.items_count}</td>
                    <td className="px-5 py-3 text-right tnum font-medium">{formatCents(order.total_cents)}</td>
                    <td className="px-5 py-3 text-right">
                      <Badge tone={ORDER_STATUS_TONE[order.status]}>
                        {ORDER_STATUS_LABELS[order.status]}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((order) => (
                <li key={order.id}>
                  <Link href={`/pedidos/${order.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{order.customer_name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          <span className="tnum">{order.number}</span>
                          {` · ${formatDate(order.issue_date)}`}
                          {` · ${order.items_count} item(ns)`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(order.total_cents)}</p>
                        <Badge tone={ORDER_STATUS_TONE[order.status]} className="mt-1">
                          {ORDER_STATUS_LABELS[order.status]}
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
              itemLabel="pedidos"
            />
          </>
        )}
      </Card>
    </>
  );
}
