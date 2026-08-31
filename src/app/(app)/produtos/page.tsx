import type { Metadata } from "next";
import Link from "next/link";
import { Package, Plus } from "lucide-react";
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
import { productFiltersSchema } from "@/modules/products/schema";
import { getCatalogOptions, listProducts } from "@/modules/products/service";
import { formatCents } from "@/lib/format/money";
import { formatNumber } from "@/lib/format";

export const metadata: Metadata = { title: "Produtos" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function ProductsPage({ searchParams }: { searchParams: SearchParams }) {
  const user = await requirePermission("products.read");
  const canViewCost = can(user.profile.role, "products.viewCost");
  const canWrite = can(user.profile.role, "products.write");

  const params = await searchParams;
  const filters = productFiltersSchema.parse({
    q: pick(params.q),
    brand: pick(params.brand),
    category: pick(params.category),
    unit: pick(params.unit),
    status: pick(params.status),
    sort: pick(params.sort),
    page: pick(params.page),
  });

  const [result, options] = await Promise.all([listProducts(filters), getCatalogOptions()]);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.brand) next.set("brand", filters.brand);
    if (filters.category) next.set("category", filters.category);
    if (filters.unit) next.set("unit", filters.unit);
    if (filters.status !== "active") next.set("status", filters.status);
    if (filters.sort !== "name") next.set("sort", filters.sort);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/produtos?${query}` : "/produtos";
  };

  const isFiltered = Boolean(
    filters.q || filters.brand || filters.category || filters.unit || filters.status !== "active",
  );

  return (
    <>
      <PageHeader
        title="Produtos"
        description="Catálogo comercial: preços, marcas e unidades."
        action={
          canWrite && (
            <Button asChild size="lg" className="hidden sm:inline-flex">
              <Link href="/produtos/novo">
                <Plus className="size-4" aria-hidden />
                Novo produto
              </Link>
            </Button>
          )
        }
      />

      <div className="mb-4 space-y-3">
        <SearchInput placeholder="Buscar por código, código do fabricante, nome ou descrição…" />
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          <UrlSelect
            param="brand"
            ariaLabel="Filtrar por marca"
            options={[
              { value: "", label: "Todas as marcas" },
              ...options.brands.map((brand) => ({ value: brand.id, label: brand.name })),
            ]}
          />
          <UrlSelect
            param="category"
            ariaLabel="Filtrar por categoria"
            options={[
              { value: "", label: "Todas as categorias" },
              ...options.categories.map((category) => ({ value: category.id, label: category.name })),
            ]}
          />
          <UrlSelect
            param="unit"
            ariaLabel="Filtrar por unidade"
            options={[
              { value: "", label: "Todas as unidades" },
              ...options.units.map((unit) => ({ value: unit.id, label: unit.code })),
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
          <UrlSelect
            param="sort"
            defaultValue="name"
            ariaLabel="Ordenar"
            options={[
              { value: "name", label: "Ordem: nome" },
              { value: "code", label: "Ordem: código" },
              { value: "price", label: "Ordem: maior preço" },
              { value: "recent", label: "Ordem: mais recentes" },
            ]}
          />
        </div>
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={Package}
            title={isFiltered ? "Nenhum produto encontrado" : "Nenhum produto cadastrado"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Cadastre o primeiro produto para montar kits e orçamentos."
            }
            action={
              !isFiltered &&
              canWrite && (
                <Button asChild className="mt-2">
                  <Link href="/produtos/novo">
                    <Plus className="size-4" aria-hidden />
                    Novo produto
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
                  <th className="px-5 py-3 font-medium">Código</th>
                  <th className="px-5 py-3 font-medium">Produto</th>
                  <th className="px-5 py-3 font-medium">Marca</th>
                  <th className="px-5 py-3 font-medium">Un.</th>
                  {canViewCost && <th className="px-5 py-3 text-right font-medium">Custo</th>}
                  <th className="px-5 py-3 text-right font-medium">Venda</th>
                  {canViewCost && <th className="px-5 py-3 text-right font-medium">Margem</th>}
                  <th className="px-5 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((product) => (
                  <tr key={product.id} className="hover:bg-sand">
                    <td className="px-5 py-3 tnum text-graphite-500">
                      {product.code}
                      {product.manufacturer_code && (
                        <span className="block text-xs text-graphite-300">
                          fab. {product.manufacturer_code}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <Link href={`/produtos/${product.id}`} className="font-medium hover:text-brand">
                        {product.name}
                      </Link>
                      {product.category_name && (
                        <span className="block text-xs text-graphite-300">{product.category_name}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-graphite-500">{product.brand_name ?? "—"}</td>
                    <td className="px-5 py-3 text-graphite-500">{product.unit_code ?? "—"}</td>
                    {canViewCost && (
                      <td className="px-5 py-3 text-right tnum text-graphite-500">
                        {formatCents(product.cost_price_cents)}
                      </td>
                    )}
                    <td className="px-5 py-3 text-right tnum font-medium">
                      {formatCents(product.sale_price_cents)}
                    </td>
                    {canViewCost && (
                      <td className="px-5 py-3 text-right tnum text-graphite-500">
                        {product.margin_percent === null ? "—" : `${formatNumber(product.margin_percent)}%`}
                      </td>
                    )}
                    <td className="px-5 py-3 text-right">
                      {!product.is_active && <Badge tone="warning">Inativo</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((product) => (
                <li key={product.id}>
                  <Link href={`/produtos/${product.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{product.name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          <span className="tnum">{product.code}</span>
                          {product.brand_name && ` · ${product.brand_name}`}
                          {product.unit_code && ` · ${product.unit_code}`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(product.sale_price_cents)}</p>
                        {!product.is_active && (
                          <Badge tone="warning" className="mt-1">
                            Inativo
                          </Badge>
                        )}
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
            />
          </>
        )}
      </Card>

      {canWrite && (
        <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
          <Link href="/produtos/novo">
            <Plus className="size-4" aria-hidden />
            Novo produto
          </Link>
        </Button>
      )}
    </>
  );
}
