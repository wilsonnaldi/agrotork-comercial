import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils/cn";

export function Select({
  className,
  children,
  ...props
}: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <div className="relative">
      <select
        className={cn(
          "h-12 w-full appearance-none rounded-lg border border-line bg-white px-3.5 pr-10 text-graphite",
          "focus:border-brand focus:outline-none disabled:bg-sand disabled:text-graphite-300",
          className,
        )}
        {...props}
      >
        {children}
      </select>
      <ChevronDown
        className="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-graphite-300"
        aria-hidden
      />
    </div>
  );
}
