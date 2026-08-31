"use client";

import { Field, Input } from "@/components/ui/field";
import type { FormState } from "@/lib/forms/action-state";
import { CatalogFormShell, useCatalogForm } from "../catalog-form";

type Unit = {
  id: string;
  code: string;
  name: string;
  allows_fraction: boolean;
  is_active: boolean;
};

/** Formulário de UNIDADE DE MEDIDA — cadastro e edição. */
export function UnitForm({
  action,
  submitLabel,
  unit,
}: {
  action: (state: FormState, formData: FormData) => Promise<FormState>;
  submitLabel: string;
  unit?: Unit;
}) {
  const { formAction, state, text, error } = useCatalogForm(action);

  return (
    <CatalogFormShell
      formAction={formAction}
      attempt={state.attempt}
      error={state.error}
      submitLabel={submitLabel}
      cancelHref="/configuracoes/unidades"
      id={unit?.id}
      isActive={unit?.is_active}
      activeLabel="Unidade ativa"
    >
      <Field label="Código" htmlFor="code" required error={error("code")} hint="Único, sem espaços">
        <Input
          id="code"
          name="code"
          defaultValue={text("code", unit?.code)}
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          className="uppercase"
          placeholder="UN"
          required
        />
      </Field>

      <Field label="Nome" htmlFor="name" required error={error("name")}>
        <Input
          id="name"
          name="name"
          defaultValue={text("name", unit?.name)}
          autoComplete="off"
          placeholder="Unidade"
          required
        />
      </Field>

      <label className="flex items-start gap-3 text-sm">
        <input
          type="checkbox"
          name="allows_fraction"
          value="true"
          defaultChecked={unit?.allows_fraction ?? false}
          className="mt-0.5 size-5 rounded border-line accent-brand"
        />
        <span>
          Aceita quantidade fracionada
          <span className="block text-xs text-graphite-300">
            Marque para peso, volume e comprimento (2,5 kg). Deixe desmarcado para unidade e peça.
          </span>
        </span>
      </label>
    </CatalogFormShell>
  );
}
