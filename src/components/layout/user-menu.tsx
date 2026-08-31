"use client";

import { useState, useRef, useEffect } from "react";
import { LogOut, User } from "lucide-react";
import { signOut } from "@/modules/auth/actions";
import { ROLE_LABELS } from "@/config/labels";
import { initialsOf } from "@/lib/format";
import type { SessionUser } from "@/lib/auth/session";

export function UserMenu({ user }: { user: SessionUser }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClickOutside(event: MouseEvent) {
      if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, []);

  const name = user.profile.full_name || user.email;

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-haspopup="menu"
        aria-expanded={open}
        className="flex size-11 items-center justify-center rounded-full bg-graphite text-sm font-medium text-white"
      >
        {initialsOf(name)}
        <span className="sr-only">Abrir menu do usuário</span>
      </button>

      {open && (
        <div
          role="menu"
          className="absolute right-0 z-50 mt-2 w-60 overflow-hidden rounded-card border border-line bg-white shadow-lg"
        >
          <div className="border-b border-line px-4 py-3">
            <p className="truncate text-sm font-medium">{name}</p>
            <p className="truncate text-xs text-graphite-300">{user.email}</p>
            <p className="mt-1 text-xs text-brand">{ROLE_LABELS[user.profile.role]}</p>
          </div>

          <a
            href="/configuracoes/perfil"
            className="flex items-center gap-2 px-4 py-3 text-sm text-graphite hover:bg-sand"
            role="menuitem"
          >
            <User className="size-4" aria-hidden />
            Meu perfil
          </a>

          <form action={signOut}>
            <button
              type="submit"
              className="flex w-full items-center gap-2 px-4 py-3 text-left text-sm text-brand hover:bg-brand-soft"
              role="menuitem"
            >
              <LogOut className="size-4" aria-hidden />
              Sair
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
