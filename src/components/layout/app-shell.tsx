import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import { MobileNav } from "./mobile-nav";
import type { SessionUser } from "@/lib/auth/session";

/**
 * Casca da área autenticada.
 * Desktop: sidebar fixa. Celular: topbar + barra inferior.
 */
export function AppShell({ user, children }: { user: SessionUser; children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh">
      <Sidebar role={user.profile.role} />

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar user={user} />
        <main className="pb-mobile-nav flex-1 px-4 py-5 sm:px-6 sm:py-6 lg:pb-8">
          <div className="mx-auto w-full max-w-6xl">{children}</div>
        </main>
      </div>

      <MobileNav role={user.profile.role} />
    </div>
  );
}
