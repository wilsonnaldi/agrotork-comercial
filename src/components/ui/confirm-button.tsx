"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";
import { AlertTriangle } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";

function Submitting({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return <>{pending ? "Aguarde…" : label}</>;
}

/**
 * Botão de ação destrutiva em dois passos.
 *
 * Um `confirm()` do navegador trava a página e some no celular; aqui a
 * confirmação aparece no próprio fluxo, e o usuário pode desistir.
 */
export function ConfirmButton({
  label,
  confirmLabel,
  question,
  variant = "danger",
  ...props
}: Omit<ButtonProps, "children" | "onClick"> & {
  label: string;
  confirmLabel: string;
  question: string;
}) {
  const [armed, setArmed] = useState(false);

  if (!armed) {
    return (
      <Button type="button" variant={variant} fullWidth onClick={() => setArmed(true)} {...props}>
        {label}
      </Button>
    );
  }

  return (
    <div className="space-y-3 rounded-lg border border-brand/30 bg-brand-soft p-3">
      <p className="flex items-start gap-2 text-sm text-brand-deep">
        <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
        {question}
      </p>
      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="submit" variant="primary" fullWidth {...props}>
          <Submitting label={confirmLabel} />
        </Button>
        <Button type="button" variant="secondary" fullWidth onClick={() => setArmed(false)}>
          Cancelar
        </Button>
      </div>
    </div>
  );
}
