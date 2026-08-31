"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import type { FormState } from "@/lib/forms/action-state";

/**
 * Encanamento comum dos formulários de cadastro (marcas, categorias, unidades).
 *
 * São duas peças, de propósito:
 *
 *   `useCatalogForm`   — estado da Server Action, valores devolvidos e erros
 *                        por campo. Usado pelo formulário de cada cadastro.
 *   `CatalogFormShell` — a casca visual: `<form>`, alerta de erro, o "ativo"
 *                        e os botões. Recebe os campos já prontos.
 *
 * Por que não uma função filha (`children({ text, error })`): a página é
 * Server Component e o React não deixa passar função para Client Component.
 * Quem monta os campos precisa estar do lado do cliente — daí o formulário
 * de cada cadastro ser um componente próprio.
 */

type Action = (state: FormState, formData: FormData) => Promise<FormState>;

export type CatalogFieldTools = {
  /** Valor a exibir: o que o servidor devolveu, ou o do registro. */
  text: (field: string, fallback?: string | null) => string;
  /** Mensagem de erro do campo, se houver. */
  error: (field: string) => string | undefined;
};

export function useCatalogForm(action: Action) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});

  const tools: CatalogFieldTools = {
    text: (field, fallback) => state.values?.[field] ?? fallback ?? "",
    error: (field) => state.fieldErrors?.[field],
  };

  return { formAction, state, ...tools };
}

export function CatalogFormShell({
  formAction,
  attempt,
  error,
  submitLabel,
  cancelHref,
  id,
  isActive,
  activeLabel,
  children,
}: {
  formAction: (formData: FormData) => void;
  attempt: number | undefined;
  error: string | undefined;
  submitLabel: string;
  cancelHref: string;
  id?: string;
  isActive?: boolean;
  activeLabel: string;
  children: React.ReactNode;
}) {
  return (
    <form
      // Remonta a cada resposta de erro: o React reseta o formulário
      // depois da Server Action. Ver `lib/forms/action-state.ts`.
      key={attempt ?? 0}
      action={formAction}
      className="max-w-xl space-y-5"
      noValidate
    >
      {id && <input type="hidden" name="id" value={id} />}
      {error && <Alert tone="error">{error}</Alert>}

      <Card>
        <CardBody className="space-y-4">
          {children}

          {id !== undefined && (
            <>
              <label className="flex items-center gap-3 border-t border-line pt-4 text-sm">
                <input
                  type="checkbox"
                  name="is_active"
                  value="true"
                  defaultChecked={isActive}
                  className="size-5 rounded border-line accent-brand"
                />
                {activeLabel}
              </label>
              {/* Depois do checkbox: `FormData.get` devolve o primeiro valor,
                  então "true" vence quando marcado e sobra "false" quando não. */}
              <input type="hidden" name="is_active" value="false" />
            </>
          )}
        </CardBody>
      </Card>

      <div className="flex flex-col-reverse gap-3 pb-2 sm:flex-row sm:justify-end">
        <Button asChild variant="secondary" size="lg" className="w-full sm:w-auto">
          <Link href={cancelHref}>Cancelar</Link>
        </Button>
        <SubmitButton label={submitLabel} />
      </div>
    </form>
  );
}

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : label}
    </Button>
  );
}
