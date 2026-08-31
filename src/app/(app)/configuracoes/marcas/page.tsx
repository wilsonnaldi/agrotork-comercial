import type { Metadata } from "next";
import { Building2 } from "lucide-react";
import { requirePermission } from "@/lib/auth/session";
import { brandFiltersSchema } from "@/modules/brands/schema";
import { listBrands } from "@/modules/brands/service";
import { CatalogList } from "../catalog-list";

export const metadata: Metadata = { title: "Marcas" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function BrandsPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("catalog.manage");

  const params = await searchParams;
  const filters = brandFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    page: pick(params.page),
  });

  const result = await listBrands(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/configuracoes/marcas?${query}` : "/configuracoes/marcas";
  };

  return (
    <CatalogList
      title="Marcas"
      description="Marca comercial que identifica o produto. Não é fornecedor nem distribuidor."
      icon={Building2}
      columnLabel="Marca"
      rows={result.items.map((brand) => ({
        id: brand.id,
        primary: brand.name,
        secondary: brand.description,
        isActive: brand.is_active,
        href: `/configuracoes/marcas/${brand.id}`,
      }))}
      total={result.total}
      page={result.page}
      pageCount={result.pageCount}
      buildHref={buildHref}
      newHref="/configuracoes/marcas/nova"
      newLabel="Nova marca"
      searchPlaceholder="Buscar marca…"
      itemLabel="marcas"
      emptyTitle="Nenhuma marca cadastrada"
      emptyDescription="Cadastre as marcas que a AGROTORK comercializa."
      isFiltered={Boolean(filters.q || filters.status !== "all")}
      flash={{ criado: pick(params.criado), salvo: pick(params.salvo) }}
    />
  );
}
