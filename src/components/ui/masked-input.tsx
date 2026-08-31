"use client";

import { useState } from "react";
import { Input } from "@/components/ui/field";
import { formatDocument, formatPhone, formatZipCode, onlyDigits } from "@/lib/format";

type Mask = "document" | "cpf" | "cnpj" | "phone" | "zip";

const FORMATTERS: Record<Mask, (value: string) => string> = {
  document: formatDocument,
  cpf: formatDocument,
  cnpj: formatDocument,
  phone: formatPhone,
  zip: formatZipCode,
};

const MAX_DIGITS: Record<Mask, number> = {
  document: 14,
  cpf: 11,
  cnpj: 14,
  phone: 11,
  zip: 8,
};

/**
 * Campo com máscara brasileira.
 *
 * Mostra formatado e envia **somente dígitos** — o banco guarda sem máscara,
 * então busca e comparação funcionam sem gambiarra. O valor visível fica num
 * input auxiliar; o `name` real viaja em um campo oculto.
 */
export function MaskedInput({
  mask,
  name,
  defaultValue,
  ...props
}: Omit<React.InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "defaultValue"> & {
  mask: Mask;
  name: string;
  defaultValue?: string | null;
}) {
  const [digits, setDigits] = useState(() => onlyDigits(defaultValue ?? ""));

  const display = (() => {
    const formatted = FORMATTERS[mask](digits);
    // Enquanto o usuário digita, um valor incompleto não casa com o padrão:
    // nesse caso mostramos os dígitos crus em vez de apagar o que ele escreveu.
    return formatted || digits;
  })();

  return (
    <>
      <Input
        {...props}
        inputMode="numeric"
        autoComplete="off"
        value={display}
        onChange={(event) => setDigits(onlyDigits(event.target.value).slice(0, MAX_DIGITS[mask]))}
      />
      <input type="hidden" name={name} value={digits} />
    </>
  );
}
