import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils/cn";

/** Paginação simples por link — funciona sem JavaScript. */
export function Pagination({
  page,
  pageCount,
  total,
  buildHref,
  itemLabel = "registros",
  itemLabelSingular,
}: {
  page: number;
  pageCount: number;
  total: number;
  buildHref: (page: number) => string;
  itemLabel?: string;
  /** Só quando o singular não for o plural sem o "s" final. */
  itemLabelSingular?: string;
}) {
  // "1 orçamentos" e "1 clientes" apareceram na homologação em celular.
  // Todos os rótulos deste sistema fazem plural com "s"; quando algum não
  // fizer, quem chama informa o singular.
  const rotulo =
    total === 1 ? (itemLabelSingular ?? itemLabel.replace(/s$/, "")) : itemLabel;
  if (pageCount <= 1) {
    return (
      <p className="px-4 py-3 text-xs text-graphite-300 sm:px-5">
        {total} {rotulo}
      </p>
    );
  }

  const linkClass = "flex h-11 min-w-11 items-center justify-center gap-1 rounded-lg border border-line px-3 text-sm";

  return (
    <nav
      className="flex items-center justify-between gap-3 border-t border-line px-4 py-3 sm:px-5"
      aria-label="Paginação"
    >
      <p className="text-xs text-graphite-300">
        Página {page} de {pageCount} · {total} {rotulo}
      </p>

      <div className="flex gap-2">
        <Link
          href={buildHref(page - 1)}
          aria-label="Página anterior"
          aria-disabled={page <= 1}
          className={cn(linkClass, page <= 1 && "pointer-events-none opacity-40")}
        >
          <ChevronLeft className="size-4" aria-hidden />
        </Link>
        <Link
          href={buildHref(page + 1)}
          aria-label="Próxima página"
          aria-disabled={page >= pageCount}
          className={cn(linkClass, page >= pageCount && "pointer-events-none opacity-40")}
        >
          <ChevronRight className="size-4" aria-hidden />
        </Link>
      </div>
    </nav>
  );
}
