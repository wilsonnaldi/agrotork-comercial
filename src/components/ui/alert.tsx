import { AlertTriangle, CheckCircle2, Info } from "lucide-react";
import { cn } from "@/lib/utils/cn";

/**
 * `warning` entrou na Fase 3: "kit inativo" e "kit incompleto" são avisos —
 * não são erro (nada quebrou) nem informação neutra. Usa o mesmo âmbar do
 * `Badge tone="warning"`, para o usuário reconhecer o mesmo significado nos
 * dois lugares.
 */
type Tone = "info" | "success" | "warning" | "error";

const CONFIG = {
  info: { icon: Info, className: "bg-blue-50 text-blue-800 border-blue-200" },
  success: { icon: CheckCircle2, className: "bg-emerald-50 text-emerald-800 border-emerald-200" },
  warning: { icon: AlertTriangle, className: "bg-amber-50 text-amber-900 border-amber-200" },
  error: { icon: AlertTriangle, className: "bg-brand-soft text-brand-deep border-brand/20" },
} as const;

export function Alert({
  tone = "info",
  title,
  children,
  className,
}: {
  tone?: Tone;
  title?: string;
  children?: React.ReactNode;
  className?: string;
}) {
  const { icon: Icon, className: toneClass } = CONFIG[tone];
  return (
    <div className={cn("flex gap-3 rounded-lg border px-4 py-3 text-sm", toneClass, className)} role="alert">
      <Icon className="mt-0.5 size-4 shrink-0" aria-hidden />
      <div className="space-y-1">
        {title && <p className="font-medium">{title}</p>}
        {children && <div className="leading-relaxed">{children}</div>}
      </div>
    </div>
  );
}
