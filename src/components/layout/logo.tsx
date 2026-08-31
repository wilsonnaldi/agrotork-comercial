import Image from "next/image";
import { COMPANY } from "@/config/company";
import { cn } from "@/lib/utils/cn";

/**
 * Logotipo da AGROTORK.
 * `invert` usa a versão para fundo escuro (letreiro branco + TORK vermelho).
 */
export function Logo({ className, invert }: { className?: string; invert?: boolean }) {
  return (
    <span className={cn("inline-flex items-center", className)}>
      <Image
        src={invert ? COMPANY.logoLight : COMPANY.logo}
        alt={COMPANY.name}
        width={1777}
        height={344}
        priority
        className="h-7 w-auto object-contain sm:h-8"
      />
    </span>
  );
}
