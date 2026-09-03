"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Field } from "@/components/ui/field";
import type { FormState } from "@/lib/forms/action-state";

type Acao = (state: FormState, formData: FormData) => Promise<FormState>;

/**
 * Envio do logotipo para o bucket `public-assets`.
 *
 * Formulário separado do cadastro de propósito: é `multipart`, tem estado
 * próprio e um erro de upload não pode zerar os campos de texto que o
 * usuário acabou de preencher.
 */
export function LogoForm({
  action,
  removeAction,
  logoUrl,
}: {
  action: Acao;
  removeAction: () => Promise<void>;
  logoUrl: string | null;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});

  return (
    <Card>
      <CardBody className="space-y-4">
        {state.error && <Alert tone="error">{state.error}</Alert>}

        {logoUrl ? (
          <div className="flex items-center gap-4">
            <span className="flex h-20 w-32 items-center justify-center overflow-hidden rounded-lg border border-line bg-white p-2">
              {/* `unoptimized`: o arquivo vem do Storage e já foi limitado a
                  5 MB e a imagem pelo bucket. */}
              <Image
                src={logoUrl}
                alt="Logotipo da empresa"
                width={128}
                height={80}
                unoptimized
                className="max-h-16 w-auto object-contain"
              />
            </span>
            <form action={removeAction}>
              <Button type="submit" variant="secondary" size="sm">
                Remover
              </Button>
            </form>
          </div>
        ) : (
          <p className="text-sm text-graphite-500">
            Nenhum logotipo. O cabeçalho do PDF sai só com o nome da empresa.
          </p>
        )}

        <form key={state.attempt ?? 0} action={formAction} className="space-y-3">
          <Field
            label={logoUrl ? "Trocar logotipo" : "Enviar logotipo"}
            htmlFor="logo"
            error={state.fieldErrors?.logo}
            hint="PNG, JPG, WEBP ou SVG, até 5 MB. Fundo transparente fica melhor no PDF."
          >
            <input
              id="logo"
              name="logo"
              type="file"
              accept="image/png,image/jpeg,image/webp,image/svg+xml"
              required
              className="block w-full text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-brand-soft file:px-4 file:py-2.5 file:text-sm file:font-medium file:text-brand"
            />
          </Field>
          <Enviar />
        </form>
      </CardBody>
    </Card>
  );
}

function Enviar() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" variant="secondary" disabled={pending}>
      {pending ? "Enviando…" : "Enviar"}
    </Button>
  );
}
