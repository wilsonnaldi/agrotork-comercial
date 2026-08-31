"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTransition } from "react";
import { Select } from "@/components/ui/select";

/**
 * Select que grava a escolha na URL, para a listagem continuar sendo
 * renderizada no servidor. Reseta a paginação a cada mudança.
 */
export function UrlSelect({
  param,
  defaultValue,
  ariaLabel,
  options,
}: {
  param: string;
  defaultValue?: string;
  ariaLabel: string;
  options: { value: string; label: string }[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  return (
    <Select
      aria-label={ariaLabel}
      disabled={pending}
      defaultValue={searchParams.get(param) ?? defaultValue ?? ""}
      onChange={(event) => {
        const params = new URLSearchParams(searchParams.toString());
        if (event.target.value) params.set(param, event.target.value);
        else params.delete(param);
        params.delete("page");
        startTransition(() => router.replace(`${pathname}?${params.toString()}`, { scroll: false }));
      }}
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </Select>
  );
}
