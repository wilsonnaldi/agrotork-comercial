import { Children, cloneElement, isValidElement, type ReactElement } from "react";
import { cn } from "@/lib/utils/cn";

/**
 * Versão mínima do padrão "asChild": repassa as props para o filho
 * em vez de renderizar um elemento próprio. Evita <button><a>.
 */
export function Slot({ children, className, ...props }: React.HTMLAttributes<HTMLElement>) {
  const child = Children.only(children) as ReactElement<Record<string, unknown>>;
  if (!isValidElement(child)) return null;

  return cloneElement(child, {
    ...props,
    ...child.props,
    className: cn(className, child.props.className as string | undefined),
  });
}
