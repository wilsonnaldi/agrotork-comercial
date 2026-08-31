"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Field, Input, Textarea } from "@/components/ui/field";
import type { FormState } from "@/lib/forms/action-state";

type Kit = { id: string; code: string; name: string; description: string | null; is_active: boolean };

/**
 * Cabeçalho do kit: código, nome, descrição e situação.
 *
 * A COMPOSIÇÃO não está aqui de propósito. Adicionar e remover componente
 * é operação de servidor, item a item, na tela de edição — assim cada
 * alteração é validada no servidor e nada depende de estado de formulário
 * sobreviver a um erro.
 */
export function KitForm({
  action,
  submitLabel,
  kit,
}: {
  action: (state: FormState, formData: FormData) => Promise<FormState>;
  submitLabel: string;
  kit?: Kit;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});

  const text = (field: string, fallback?: string | null) => state.values?.[field] ?? fallback ?? "";
  const error = (field: string) => state.fieldErrors?.[field];

  return (
    <form
      // Remonta a cada resposta de erro: o React reseta o formulário depois
      // da Server Action. Ver `lib/forms/action-state.ts`.
      key={state.attempt ?? 0}
      action={formAction}
      className="max-w-xl space-y-5"
      noValidate
    >
      {kit && <input type="hidden" name="id" value={kit.id} />}
      {state.error && <Alert tone="error">{state.error}</Alert>}

      <Card>
        <CardBody className="space-y-4">
          <Field
            label="Código"
            htmlFor="code"
            required
            error={error("code")}
            hint="Único entre os kits. Vira maiúsculas."
          >
            <Input
              id="code"
              name="code"
              defaultValue={text("code", kit?.code)}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              className="uppercase"
              placeholder="K-001"
              required
            />
          </Field>

          <Field label="Nome" htmlFor="name" required error={error("name")}>
            <Input
              id="name"
              name="name"
              defaultValue={text("name", kit?.name)}
              autoComplete="off"
              placeholder="Kit pulverização"
              required
            />
          </Field>

          <Field label="Descrição" htmlFor="description" error={error("description")}>
            <Textarea
              id="description"
              name="description"
              defaultValue={text("description", kit?.description)}
              rows={3}
              placeholder="Para que serve, em que máquina se aplica…"
            />
          </Field>

          {kit && (
            <>
              <label className="flex items-center gap-3 border-t border-line pt-4 text-sm">
                <input
                  type="checkbox"
                  name="is_active"
                  value="true"
                  defaultChecked={kit.is_active}
                  className="size-5 rounded border-line accent-brand"
                />
                Kit ativo
              </label>
              {/* Depois do checkbox: `FormData.get` devolve o primeiro valor. */}
              <input type="hidden" name="is_active" value="false" />
            </>
          )}
        </CardBody>
      </Card>

      <div className="flex flex-col-reverse gap-3 pb-2 sm:flex-row sm:justify-end">
        <Button asChild variant="secondary" size="lg" className="w-full sm:w-auto">
          <Link href={kit ? `/kits/${kit.id}` : "/kits"}>Cancelar</Link>
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
