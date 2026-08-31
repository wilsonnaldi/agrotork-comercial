import { Slot } from "@/components/ui/slot";
import { cn } from "@/lib/utils/cn";

type Variant = "primary" | "secondary" | "ghost" | "danger" | "whatsapp";
type Size = "sm" | "md" | "lg";

const VARIANTS: Record<Variant, string> = {
  primary: "bg-brand text-white hover:bg-brand-dark active:bg-brand-deep",
  secondary: "bg-white text-graphite border border-line hover:bg-sand",
  ghost: "bg-transparent text-graphite-500 hover:bg-line/60 hover:text-graphite",
  danger: "bg-white text-brand border border-brand/30 hover:bg-brand-soft",
  whatsapp: "bg-whatsapp text-white hover:brightness-95",
};

/* Altura mínima de 44px: alvo de toque confortável no celular. */
const SIZES: Record<Size, string> = {
  sm: "h-10 px-3 text-sm gap-1.5",
  md: "h-11 px-4 text-sm gap-2",
  lg: "h-12 px-5 text-base gap-2",
};

export type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: Size;
  fullWidth?: boolean;
  asChild?: boolean;
};

export function Button({
  className,
  variant = "primary",
  size = "md",
  fullWidth,
  asChild,
  ...props
}: ButtonProps) {
  const Comp = asChild ? Slot : "button";
  return (
    <Comp
      className={cn(
        "inline-flex items-center justify-center rounded-lg font-medium transition-colors",
        "disabled:pointer-events-none disabled:opacity-50",
        VARIANTS[variant],
        SIZES[size],
        fullWidth && "w-full",
        className,
      )}
      {...props}
    />
  );
}
