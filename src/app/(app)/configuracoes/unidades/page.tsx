import type { Metadata } from "next";
import { Ruler } from "lucide-react";
import { requirePermission } from "@/lib/auth/session";
import { unitFiltersSchema } from "@/modules/units/schema";
import { listUnits } from "@/modules/units/service";
import { CatalogList } from "../catalog-list";

export const metadata: Metadata = { title: "Unidades de medida" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function UnitsPage({ searchParams }: { searchParams: SearchParams }) {
  await requirePermission("catalog.manage");

  const params = await searchParams;
  const filters = unitFiltersSchema.parse({
    q: pick(params.q),
    status: pick(params.status),
    page: pick(params.page),
  });

  const result = await listUnits(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/configuracoes/unidades?${query}` : "/configuracoes/unidades";
  };

  return (
    <CatalogList
      title="Unidades de medida"
      description="Como o produto é vendido: unidade, peso, volume, comprimento, hora…"
      icon={Ruler}
      columnLabel="Código"
      rows={result.items.map((unit) => ({
        id: unit.id,
        primary: unit.code,
        secondary: unit.name,
        hint: unit.name,
        isActive: unit.is_active,
        href: `/configuracoes/unidades/${unit.id}`,
      }))}
      total={result.total}
      page={result.page}
      pageCount={result.pageCount}
      buildHref={buildHref}
      newHref="/configuracoes/unidades/nova"
      newLabel="Nova unidade"
      searchPlaceholder="Buscar por código ou nome…"
      itemLabel="unidades"
      emptyTitle="Nenhuma unidade cadastrada"
      emptyDescription="Sem unidade não é possível cadastrar produto."
      isFiltered={Boolean(filters.q || filters.status !== "all")}
      flash={{ criado: pick(params.criado), salvo: pick(params.salvo) }}
    />
  );
}
