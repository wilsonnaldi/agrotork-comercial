import type { Metadata } from "next";
import { Tags } from "lucide-react";
import { requirePermission } from "@/lib/auth/session";
import { categoryFiltersSchema } from "@/modules/categories/schema";
import { listCategories } from "@/modules/categories/service";
import { CatalogList } from "../catalog-list";

export const metadata: Metadata = { title: "Categorias" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function CategoriesPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("catalog.manage");

  const params = await searchParams;
  const filters = categoryFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    page: pick(params.page),
  });

  const result = await listCategories(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/configuracoes/categorias?${query}` : "/configuracoes/categorias";
  };

  return (
    <CatalogList
      title="Categorias"
      description="Agrupamento usado para organizar e filtrar o catálogo."
      icon={Tags}
      columnLabel="Categoria"
      rows={result.items.map((category) => ({
        id: category.id,
        primary: category.name,
        secondary: category.description,
        isActive: category.is_active,
        href: `/configuracoes/categorias/${category.id}`,
      }))}
      total={result.total}
      page={result.page}
      pageCount={result.pageCount}
      buildHref={buildHref}
      newHref="/configuracoes/categorias/nova"
      newLabel="Nova categoria"
      searchPlaceholder="Buscar categoria…"
      itemLabel="categorias"
      emptyTitle="Nenhuma categoria cadastrada"
      emptyDescription="Cadastre as categorias que organizam o catálogo."
      isFiltered={Boolean(filters.q || filters.status !== "all")}
      flash={{ criado: pick(params.criado), salvo: pick(params.salvo) }}
    />
  );
}
