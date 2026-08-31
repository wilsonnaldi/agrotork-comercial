"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Loader2, Search, X } from "lucide-react";

/**
 * Busca que escreve na URL (`?q=`).
 *
 * Manter o termo na URL deixa o resultado compartilhável, sobrevive ao
 * "voltar" do navegador e permite que a listagem continue sendo um
 * Server Component — nada de estado duplicado no cliente.
 */
export function SearchInput({
  placeholder = "Buscar…",
  paramName = "q",
}: {
  placeholder?: string;
  paramName?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  const initial = searchParams.get(paramName) ?? "";
  const [value, setValue] = useState(initial);
  const firstRender = useRef(true);

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }

    const timer = setTimeout(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (value.trim()) params.set(paramName, value.trim());
      else params.delete(paramName);
      params.delete("page"); // busca nova volta para a primeira página

      startTransition(() => router.replace(`${pathname}?${params.toString()}`, { scroll: false }));
    }, 350);

    return () => clearTimeout(timer);
    // `searchParams` muda a cada replace; incluí-lo aqui criaria um laço.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, pathname, paramName]);

  return (
    <div className="relative">
      <Search className="absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-graphite-300" aria-hidden />
      <input
        type="search"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder={placeholder}
        aria-label={placeholder}
        className="h-12 w-full rounded-lg border border-line bg-white pr-10 pl-10 text-graphite placeholder:text-graphite-300 focus:border-brand focus:outline-none"
      />
      {pending ? (
        <Loader2 className="absolute top-1/2 right-3.5 size-4 -translate-y-1/2 animate-spin text-graphite-300" aria-hidden />
      ) : value ? (
        <button
          type="button"
          onClick={() => setValue("")}
          aria-label="Limpar busca"
          className="absolute top-1/2 right-2 flex size-9 -translate-y-1/2 items-center justify-center rounded-md text-graphite-300 hover:text-graphite"
        >
          <X className="size-4" aria-hidden />
        </button>
      ) : null}
    </div>
  );
}
