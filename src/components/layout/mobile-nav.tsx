"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Plus } from "lucide-react";
import { NAV_ITEMS } from "@/config/navigation";
import { can } from "@/config/permissions";
import { cn } from "@/lib/utils/cn";
import type { UserRole } from "@/types/db";

/**
 * Barra inferior do celular: as ações mais usadas ao alcance do polegar,
 * com "Novo orçamento" em destaque no centro.
 */
export function MobileNav({ role }: { role: UserRole }) {
  const pathname = usePathname();
  const items = NAV_ITEMS.filter((item) => item.mobile && can(role, item.permission));
  const left = items.slice(0, 2);
  const right = items.slice(2, 4);

  const renderItem = (item: (typeof items)[number]) => {
    const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
    return (
      <Link
        key={item.href}
        href={item.href}
        aria-current={active ? "page" : undefined}
        className={cn(
          "flex min-h-14 flex-1 flex-col items-center justify-center gap-1 text-[11px]",
          active ? "text-brand" : "text-graphite-300",
        )}
      >
        <item.icon className="size-5" aria-hidden />
        {item.shortLabel}
      </Link>
    );
  };

  return (
    <nav
      aria-label="Navegação"
      className="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
    >
      <div className="mx-auto flex max-w-lg items-center">
        {left.map(renderItem)}

        <Link
          href="/orcamentos/novo"
          className="-mt-5 flex size-14 shrink-0 items-center justify-center rounded-full bg-brand text-white shadow-lg shadow-brand/30"
          aria-label="Novo orçamento"
        >
          <Plus className="size-6" aria-hidden />
        </Link>

        {right.map(renderItem)}
      </div>
    </nav>
  );
}
