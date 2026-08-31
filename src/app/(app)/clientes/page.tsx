import type { Metadata } from "next";
import Link from "next/link";
import { Plus, Users, MessageCircle } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";
import { requirePermission } from "@/lib/auth/session";
import { customerFiltersSchema } from "@/modules/customers/schema";
import { listCustomers } from "@/modules/customers/service";
import { formatDocument, formatPhone } from "@/lib/format";
import { BRAZIL_STATES } from "@/config/locale";

export const metadata: Metadata = { title: "Clientes" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function CustomersPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("customers.read");

  const params = await searchParams;
  const filters = customerFiltersSchema.parse({
    q: typeof params.q === "string" ? params.q : undefined,
    state: typeof params.state === "string" ? params.state : undefined,
    status: typeof params.status === "string" ? params.status : undefined,
    page: typeof params.page === "string" ? params.page : undefined,
  });

  const result = await listCustomers(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.state) next.set("state", filters.state);
    if (filters.status !== "active") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/clientes?${query}` : "/clientes";
  };

  const isFiltered = Boolean(filters.q || filters.state || filters.status !== "active");

  return (
    <>
      <PageHeader
        title="Clientes"
        description="Cadastro e histórico comercial."
        action={
          <Button asChild size="lg" className="hidden sm:inline-flex">
            <Link href="/clientes/novo">
              <Plus className="size-4" aria-hidden />
              Novo cliente
            </Link>
          </Button>
        }
      />

      {/* Busca em destaque: é a primeira coisa que se faz nesta tela. */}
      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-[1fr_auto_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder="Buscar por nome, documento ou cidade…" />
        </div>
        <UrlSelect
          param="state"
          ariaLabel="Filtrar por estado"
          options={[
            { value: "", label: "Todos os estados" },
            ...BRAZIL_STATES.map((uf) => ({ value: uf.code, label: uf.code })),
          ]}
        />
        <UrlSelect
          param="status"
          defaultValue="active"
          ariaLabel="Filtrar por situação"
          options={[
            { value: "active", label: "Ativos" },
            { value: "inactive", label: "Inativos" },
            { value: "all", label: "Todos" },
          ]}
        />
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={Users}
            title={isFiltered ? "Nenhum cliente encontrado" : "Nenhum cliente cadastrado"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Cadastre o primeiro cliente para começar a emitir orçamentos."
            }
            action={
              !isFiltered && (
                <Button asChild className="mt-2">
                  <Link href="/clientes/novo">
                    <Plus className="size-4" aria-hidden />
                    Novo cliente
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
                  <th className="px-5 py-3 font-medium">Nome</th>
                  <th className="px-5 py-3 font-medium">Documento</th>
                  <th className="px-5 py-3 font-medium">Cidade</th>
                  <th className="px-5 py-3 font-medium">Telefone</th>
                  <th className="px-5 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((customer) => (
                  <tr key={customer.id} className="hover:bg-sand">
                    <td className="px-5 py-3">
                      <Link href={`/clientes/${customer.id}`} className="font-medium hover:text-brand">
                        {customer.name}
                      </Link>
                      {customer.trade_name && (
                        <span className="block text-xs text-graphite-300">{customer.trade_name}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {formatDocument(customer.document) || "—"}
                    </td>
                    <td className="px-5 py-3 text-graphite-500">
                      {customer.city ? `${customer.city}${customer.state ? `/${customer.state}` : ""}` : "—"}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {formatPhone(customer.phone ?? customer.whatsapp) || "—"}
                    </td>
                    <td className="px-5 py-3 text-right">
                      {!customer.is_active && <Badge tone="warning">Inativo</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((customer) => (
                <li key={customer.id}>
                  <Link href={`/clientes/${customer.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{customer.name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          {formatDocument(customer.document) || "sem documento"}
                          {customer.city && ` · ${customer.city}${customer.state ? `/${customer.state}` : ""}`}
                        </p>
                      </div>
                      {!customer.is_active && <Badge tone="warning">Inativo</Badge>}
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
              itemLabel="clientes"
            />
          </>
        )}
      </Card>

      {/* Atalho de polegar: no celular o botão principal fica ao alcance. */}
      <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
        <Link href="/clientes/novo">
          <Plus className="size-4" aria-hidden />
          Novo cliente
        </Link>
      </Button>

      <p className="mt-4 flex items-center gap-2 text-xs text-graphite-300 sm:hidden">
        <MessageCircle className="size-3.5" aria-hidden />
        Toque em um cliente para ver a ficha e o histórico.
      </p>
    </>
  );
}
