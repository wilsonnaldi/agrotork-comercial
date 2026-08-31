import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils/cn";

export function StatCard({
  label,
  value,
  icon: Icon,
  hint,
  accent,
  className,
}: {
  label: string;
  value: string | number;
  icon: LucideIcon;
  hint?: string;
  accent?: boolean;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-card border border-line bg-white p-4",
        accent && "border-brand/20 bg-gradient-to-br from-brand-soft to-white",
        className,
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium tracking-wide text-graphite-500 uppercase">{label}</p>
        <Icon className={cn("size-4 shrink-0", accent ? "text-brand" : "text-graphite-300")} aria-hidden />
      </div>
      {/* data-stat dá um ponto de referência estável para os testes de ponta a ponta. */}
      <p
        data-stat={label}
        className={cn("mt-2 font-display text-2xl tnum sm:text-3xl", accent && "text-brand-deep")}
      >
        {value}
      </p>
      {hint && <p className="mt-1 text-xs text-graphite-300">{hint}</p>}
    </div>
  );
}
