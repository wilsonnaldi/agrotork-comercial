"use client";

import { Input } from "@/components/ui/field";
import { centsToInputValue } from "@/lib/format/money";

/**
 * Campo monetário em reais.
 *
 * O usuário digita só números e o valor se monta da direita para a
 * esquerda (12345 vira "123,45") — é o comportamento que se espera no
 * celular e evita erro de vírgula. O componente é controlado em
 * **centavos**; o campo oculto envia o texto formatado, que o schema
 * reinterpreta no servidor.
 */
export function MoneyInput({
  name,
  valueCents,
  onChangeCents,
  ...props
}: Omit<React.InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "name"> & {
  name: string;
  valueCents: number | null;
  onChangeCents: (cents: number | null) => void;
}) {
  const display = valueCents === null ? "" : centsToInputValue(valueCents);

  return (
    <>
      <div className="relative">
        <span className="pointer-events-none absolute top-1/2 left-3.5 -translate-y-1/2 text-sm text-graphite-300">
          R$
        </span>
        <Input
          {...props}
          className="pl-10 text-right tnum"
          inputMode="numeric"
          autoComplete="off"
          value={display}
          placeholder="0,00"
          onChange={(event) => {
            const digits = event.target.value.replace(/\D/g, "").slice(0, 13);
            onChangeCents(digits === "" ? null : Number(digits));
          }}
        />
      </div>
      <input type="hidden" name={name} value={display} />
    </>
  );
}
