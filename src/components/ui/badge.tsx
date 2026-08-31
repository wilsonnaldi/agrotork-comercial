import { cn } from "@/lib/utils/cn";

type Tone = "neutral" | "info" | "success" | "danger" | "warning";

const TONES: Record<Tone, string> = {
  neutral: "bg-line text-graphite-500",
  info: "bg-blue-50 text-blue-700",
  success: "bg-emerald-50 text-emerald-700",
  danger: "bg-brand-soft text-brand-deep",
  warning: "bg-amber-50 text-amber-700",
};

export function Badge({
  tone = "neutral",
  className,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium whitespace-nowrap",
        TONES[tone],
        className,
      )}
      {...props}
    />
  );
}
