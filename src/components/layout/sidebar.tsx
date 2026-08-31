"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV_ITEMS } from "@/config/navigation";
import { can } from "@/config/permissions";
import { Logo } from "./logo";
import { cn } from "@/lib/utils/cn";
import type { UserRole } from "@/types/db";

/** Navegação lateral fixa — só aparece a partir de `lg`. */
export function Sidebar({ role }: { role: UserRole }) {
  const pathname = usePathname();
  const items = NAV_ITEMS.filter((item) => can(role, item.permission));

  return (
    <aside className="hidden w-60 shrink-0 flex-col bg-graphite lg:flex">
      <div className="flex h-16 items-center border-b border-white/10 px-5">
        <Link href="/dashboard" aria-label="Ir para o painel">
          <Logo invert />
        </Link>
      </div>

      <nav className="flex-1 space-y-1 p-3" aria-label="Navegação principal">
        {items.map((item) => {
          const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors",
                active ? "bg-brand text-white" : "text-white/70 hover:bg-white/10 hover:text-white",
              )}
            >
              <item.icon className="size-4 shrink-0" aria-hidden />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <p className="px-5 py-4 text-[11px] text-white/35">Sistema Comercial · v0.1</p>
    </aside>
  );
}
