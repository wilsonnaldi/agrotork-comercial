import type { Metadata } from "next";
import Link from "next/link";
import { Boxes, Lock, Plus, SquareCheck } from "lucide-react";
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
import { formatCents } from "@/lib/format/money";
import { kitFiltersSchema } from "@/modules/kits/schema";
import { kitIsUsable, listKits } from "@/modules/kits/service";

export const metadata: Metadata = { title: "Kits" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function KitsPage({ searchParams }: { searchParams: SearchParams }) {
  const user = await requirePermission("kits.read");
  const canWrite = can(user.profile.role, "kits.write");

  const params = await searchParams;
  const filters = kitFiltersSchema.parse({
    q: pick(params.q),
    // O vendedor vê a vitrine: só kits ativos. Não é controle de acesso —
    // o RLS deixa ele LER um kit desativado de propósito, porque vai
    // precisar disso para abrir um orçamento antigo. Aqui é a lista de
    // opções, e opção desativada não é opção.
    status: canWrite ? pick(params.status) : "active",
    page: pick(params.page),
  });

  const result = await listKits(filters);

  const buildHref = (page: number) => {
    const next = new URLSearchParams();
    if (filters.q) next.set("q", filters.q);
    if (filters.status !== "all") next.set("status", filters.status);
    if (page > 1) next.set("page", String(page));
    const query = next.toString();
    return query ? `/kits?${query}` : "/kits";
  };

  const isFiltered = Boolean(filters.q || filters.status !== "all");

  return (
    <>
      <PageHeader
        title="Kits"
        description="Composições comerciais de produtos, com itens obrigatórios e opcionais."
        action={
          canWrite && (
            <Button asChild size="lg" className="hidden sm:inline-flex">
              <Link href="/kits/novo">
                <Plus className="size-4" aria-hidden />
                Novo kit
              </Link>
            </Button>
          )
        }
      />

      {pick(params.salvo) && (
        <Alert tone="success" className="mb-4">
          Alterações salvas.
        </Alert>
      )}

      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-[1fr_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder="Buscar por código, nome ou descrição…" />
        </div>
        {canWrite && (
          <UrlSelect
            param="status"
            defaultValue="all"
            ariaLabel="Filtrar por situação"
            options={[
              { value: "all", label: "Todos" },
              { value: "active", label: "Ativos" },
              { value: "inactive", label: "Inativos" },
            ]}
          />
        )}
      </div>

      <Card className="overflow-hidden">
        {result.items.length === 0 ? (
          <EmptyState
            icon={Boxes}
            title={isFiltered ? "Nenhum kit encontrado" : "Nenhum kit cadastrado"}
            description={
              isFiltered
                ? "Tente outro termo de busca ou limpe os filtros."
                : "Monte o primeiro kit com produtos já cadastrados."
            }
            action={
              !isFiltered &&
              canWrite && (
                <Button asChild className="mt-2">
                  <Link href="/kits/novo">
                    <Plus className="size-4" aria-hidden />
                    Novo kit
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
                  <th className="px-5 py-3 font-medium">Kit</th>
                  <th className="px-5 py-3 text-right font-medium">Itens</th>
                  <th className="px-5 py-3 text-right font-medium">Obrigatórios</th>
                  <th className="px-5 py-3 text-right font-medium">Opcionais</th>
                  <th className="px-5 py-3 text-right font-medium">Preço-base</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                  <th className="px-5 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {result.items.map((kit) => (
                  <tr key={kit.id} className="hover:bg-sand">
                    <td className="px-5 py-3 tnum text-graphite-500">{kit.code}</td>
                    <td className="px-5 py-3">
                      <Link href={`/kits/${kit.id}`} className="font-medium hover:text-brand">
                        {kit.name}
                      </Link>
                      {kit.description && (
                        <span className="block truncate text-xs text-graphite-300">{kit.description}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">{kit.items_count}</td>
                    <td className="px-5 py-3 text-right tnum">
                      <span className="inline-flex items-center gap-1">
                        <Lock className="size-3 text-graphite-300" aria-hidden />
                        {kit.required_count}
                      </span>
                    </td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">
                      <span className="inline-flex items-center gap-1">
                        <SquareCheck className="size-3 text-graphite-300" aria-hidden />
                        {kit.optional_count}
                      </span>
                    </td>
                    <td className="px-5 py-3 text-right tnum font-medium">
                      {formatCents(kit.components_total_cents)}
                    </td>
                    <td className="px-5 py-3 text-right">
                      {kit.is_active ? (
                        <Badge tone="success">Ativo</Badge>
                      ) : (
                        <Badge tone="warning">Inativo</Badge>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right">
                      {!kitIsUsable(kit) && kit.is_active && <Badge tone="warning">Incompleto</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {result.items.map((kit) => (
                <li key={kit.id}>
                  <Link href={`/kits/${kit.id}`} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{kit.name}</p>
                        <p className="mt-0.5 truncate text-xs text-graphite-300">
                          <span className="tnum">{kit.code}</span>
                          {` · ${kit.required_count} obrigatório(s)`}
                          {kit.optional_count > 0 && ` · ${kit.optional_count} opcional(is)`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="tnum text-sm font-medium">{formatCents(kit.components_total_cents)}</p>
                        {!kit.is_active && (
                          <Badge tone="warning" className="mt-1">
                            Inativo
                          </Badge>
                        )}
                        {kit.is_active && !kitIsUsable(kit) && (
                          <Badge tone="warning" className="mt-1">
                            Incompleto
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
              itemLabel="kits"
            />
          </>
        )}
      </Card>

      {canWrite && (
        <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
          <Link href="/kits/novo">
            <Plus className="size-4" aria-hidden />
            Novo kit
          </Link>
        </Button>
      )}
    </>
  );
}
