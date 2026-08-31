import type { LucideIcon } from "lucide-react";

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
}: {
  icon: LucideIcon;
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-12 text-center">
      <span className="flex size-12 items-center justify-center rounded-full bg-sand text-graphite-300">
        <Icon className="size-6" aria-hidden />
      </span>
      <p className="font-display text-lg">{title}</p>
      {description && <p className="max-w-sm text-sm text-graphite-500">{description}</p>}
      {action}
    </div>
  );
}
