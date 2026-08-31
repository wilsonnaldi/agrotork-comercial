import Link from "next/link";
import { ArrowLeft, Plus, type LucideIcon } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { SearchInput } from "@/components/ui/search-input";
import { UrlSelect } from "@/components/ui/url-select";
import { Pagination } from "@/components/ui/pagination";

export type CatalogRow = {
  id: string;
  /** Identificador visível: código, para unidades; nome, nos demais. */
  primary: string;
  secondary?: string | null;
  hint?: string | null;
  isActive: boolean;
  href: string;
};

/**
 * Listagem comum dos cadastros de apoio.
 *
 * Desktop: tabela simples. Celular: a mesma informação em lista tocável.
 * As três telas (marcas, categorias, unidades) mostram exatamente os
 * mesmos elementos, então dividem esta apresentação.
 */
export function CatalogList({
  title,
  description,
  icon,
  columnLabel,
  rows,
  total,
  page,
  pageCount,
  buildHref,
  newHref,
  newLabel,
  searchPlaceholder,
  itemLabel,
  emptyTitle,
  emptyDescription,
  isFiltered,
  flash,
}: {
  title: string;
  description: string;
  icon: LucideIcon;
  columnLabel: string;
  rows: CatalogRow[];
  total: number;
  page: number;
  pageCount: number;
  buildHref: (page: number) => string;
  newHref: string;
  newLabel: string;
  searchPlaceholder: string;
  itemLabel: string;
  emptyTitle: string;
  emptyDescription: string;
  isFiltered: boolean;
  flash?: { criado?: string; salvo?: string };
}) {
  return (
    <>
      <Link
        href="/configuracoes"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Configurações
      </Link>

      <PageHeader
        title={title}
        description={description}
        action={
          <Button asChild size="lg" className="hidden sm:inline-flex">
            <Link href={newHref}>
              <Plus className="size-4" aria-hidden />
              {newLabel}
            </Link>
          </Button>
        }
      />

      {flash?.criado && <Alert tone="success" className="mb-4">Cadastro criado.</Alert>}
      {flash?.salvo && <Alert tone="success" className="mb-4">Alterações salvas.</Alert>}

      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-[1fr_auto]">
        <div className="col-span-2 sm:col-span-1">
          <SearchInput placeholder={searchPlaceholder} />
        </div>
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
      </div>

      <Card className="overflow-hidden">
        {rows.length === 0 ? (
          <EmptyState
            icon={icon}
            title={isFiltered ? "Nenhum registro encontrado" : emptyTitle}
            description={isFiltered ? "Tente outro termo ou limpe os filtros." : emptyDescription}
            action={
              !isFiltered && (
                <Button asChild className="mt-2">
                  <Link href={newHref}>
                    <Plus className="size-4" aria-hidden />
                    {newLabel}
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
                  <th className="px-5 py-3 font-medium">{columnLabel}</th>
                  <th className="px-5 py-3 font-medium">Descrição</th>
                  <th className="px-5 py-3 text-right font-medium">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.map((row) => (
                  <tr key={row.id} className="hover:bg-sand">
                    <td className="px-5 py-3">
                      <Link href={row.href} className="font-medium hover:text-brand">
                        {row.primary}
                      </Link>
                      {row.hint && <span className="block text-xs text-graphite-300">{row.hint}</span>}
                    </td>
                    <td className="px-5 py-3 text-graphite-500">{row.secondary || "—"}</td>
                    <td className="px-5 py-3 text-right">
                      {row.isActive ? (
                        <Badge tone="success">Ativo</Badge>
                      ) : (
                        <Badge tone="warning">Inativo</Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {rows.map((row) => (
                <li key={row.id}>
                  <Link href={row.href} className="block px-4 py-3.5 hover:bg-sand">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{row.primary}</p>
                        {(row.hint || row.secondary) && (
                          <p className="mt-0.5 truncate text-xs text-graphite-300">
                            {row.hint ?? row.secondary}
                          </p>
                        )}
                      </div>
                      {!row.isActive && <Badge tone="warning">Inativo</Badge>}
                    </div>
                  </Link>
                </li>
              ))}
            </ul>

            <Pagination
              page={page}
              pageCount={pageCount}
              total={total}
              buildHref={buildHref}
              itemLabel={itemLabel}
            />
          </>
        )}
      </Card>

      <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
        <Link href={newHref}>
          <Plus className="size-4" aria-hidden />
          {newLabel}
        </Link>
      </Button>
    </>
  );
}
