import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Plus, Truck } from "lucide-react";
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
import { supplierFiltersSchema } from "@/modules/suppliers/schema";
import { listSuppliers } from "@/modules/suppliers/service";
import { formatDocument, formatPhone } from "@/lib/format";
import { BRAZIL_STATES } from "@/config/locale";

export const metadata: Metadata = { title: "Fornecedores" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function SuppliersPage({ searchParams }: { searchParams: SearchParams }) {
  // Ler é dos dois papéis; cadastrar não. Quem entra pelo endereço direto
  // sem ser administrador vê a lista, e nenhum botão de escrita.
  const user = await requirePermission("suppliers.read");
  const podeGerenciar = can(user.profile.role, "suppliers.manage");

  const params = await searchParams;
  const filters = supplierFiltersSchema.parse({
    q: pick(params.q),
    state: pick(params.state),
    status: pick(params.status),
    page: pick(params.page),
  });

  const result = await listSuppliers(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.state) next.set("state", filters.state);
    if (filters.status !== "active") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/configuracoes/fornecedores?${query}` : "/configuracoes/fornecedores";
  };

  const isFiltered = Boolean(filters.q || filters.state || filters.status !== "active");

  return (
    <>
      <PageHeader
        title="Fornecedores"
        description="De quem a AgroTork compra. Não confundir com marca do produto."
        action={
          <div className="flex gap-2">
            <Button asChild variant="secondary">
              <Link href="/configuracoes">
                <ArrowLeft className="size-4" aria-hidden />
                Voltar
              </Link>
            </Button>
            {podeGerenciar && (
              <Button asChild size="lg" className="hidden sm:inline-flex">
                <Link href="/configuracoes/fornecedores/novo">
                  <Plus className="size-4" aria-hidden />
                  Novo fornecedor
                </Link>
              </Button>
            )}
          </div>
        }
      />

      {typeof params.excluido === "string" && (
        <Alert tone="success" className="mb-4">
          Fornecedor excluído. O cadastro sai da listagem, mas o histórico continua no banco.
        </Alert>
      )}

      <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_auto_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder="Buscar por nome, CNPJ, cidade ou contato…" />
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
            icon={Truck}
            title={isFiltered ? "Nenhum fornecedor encontrado" : "Nenhum fornecedor cadastrado"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Cadastre de quem a empresa compra: DJI, distribuidores, oficinas."
            }
            action={
              !isFiltered &&
              podeGerenciar && (
                <Button asChild className="mt-2">
                  <Link href="/configuracoes/fornecedores/novo">
                    <Plus className="size-4" aria-hidden />
                    Novo fornecedor
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
                {result.items.map((supplier) => (
                  <tr key={supplier.id} className="hover:bg-sand">
                    <td className="px-5 py-3">
                      <Link
                        href={`/configuracoes/fornecedores/${supplier.id}`}
                        className="font-medium hover:text-brand"
                      >
                        {supplier.name}
                      </Link>
                      {supplier.trade_name && (
                        <span className="block text-xs text-graphite-300">{supplier.trade_name}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {formatDocument(supplier.document) || "—"}
                    </td>
                    <td className="px-5 py-3 text-graphite-500">
                      {supplier.city ? `${supplier.city}${supplier.state ? `/${supplier.state}` : ""}` : "—"}
                    </td>
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {formatPhone(supplier.phone) || "—"}
                    </td>
                    <td className="px-5 py-3 text-right">
                      {!supplier.is_active && <Badge tone="warning">Inativo</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((supplier) => (
                <li key={supplier.id}>
                  <Link
                    href={`/configuracoes/fornecedores/${supplier.id}`}
                    className="block px-4 py-3.5 hover:bg-sand"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{supplier.name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          {formatDocument(supplier.document) || "sem documento"}
                          {supplier.city && ` · ${supplier.city}${supplier.state ? `/${supplier.state}` : ""}`}
                        </p>
                      </div>
                      {!supplier.is_active && <Badge tone="warning">Inativo</Badge>}
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
              itemLabel="fornecedores"
              itemLabelSingular="fornecedor"
            />
          </>
        )}
      </Card>

      {podeGerenciar && (
        <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
          <Link href="/configuracoes/fornecedores/novo">
            <Plus className="size-4" aria-hidden />
            Novo fornecedor
          </Link>
        </Button>
      )}
    </>
  );
}
