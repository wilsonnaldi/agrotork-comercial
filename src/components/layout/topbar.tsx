import { Logo } from "./logo";
import { UserMenu } from "./user-menu";
import { ROLE_LABELS } from "@/config/labels";
import type { SessionUser } from "@/lib/auth/session";

export function Topbar({ user }: { user: SessionUser }) {
  return (
    <header className="sticky top-0 z-30 flex h-16 items-center justify-between gap-3 border-b border-line bg-white/90 px-4 backdrop-blur sm:px-6">
      <div className="lg:hidden">
        <Logo />
      </div>

      <div className="hidden min-w-0 lg:block">
        <p className="truncate text-sm text-graphite-500">
          {user.profile.full_name || user.email}
          <span className="mx-2 text-line">·</span>
          <span className="text-graphite-300">{ROLE_LABELS[user.profile.role]}</span>
        </p>
      </div>

      <UserMenu user={user} />
    </header>
  );
}
