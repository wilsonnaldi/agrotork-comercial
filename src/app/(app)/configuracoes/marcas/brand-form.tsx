"use client";

import { Field, Input, Textarea } from "@/components/ui/field";
import type { FormState } from "@/lib/forms/action-state";
import { CatalogFormShell, useCatalogForm } from "../catalog-form";

type Brand = { id: string; name: string; description: string | null; is_active: boolean };

/**
 * Formulário de MARCA — serve tanto para cadastrar quanto para editar.
 * O que muda é a ação e o registro recebido; os campos são os mesmos.
 */
export function BrandForm({
  action,
  submitLabel,
  brand,
}: {
  action: (state: FormState, formData: FormData) => Promise<FormState>;
  submitLabel: string;
  brand?: Brand;
}) {
  const { formAction, state, text, error } = useCatalogForm(action);

  return (
    <CatalogFormShell
      formAction={formAction}
      attempt={state.attempt}
      error={state.error}
      submitLabel={submitLabel}
      cancelHref="/configuracoes/marcas"
      id={brand?.id}
      isActive={brand?.is_active}
      activeLabel="Marca ativa"
    >
      <Field label="Nome" htmlFor="name" required error={error("name")} hint="Único entre as marcas">
        <Input
          id="name"
          name="name"
          defaultValue={text("name", brand?.name)}
          autoComplete="off"
          placeholder="ARAG"
          required
        />
      </Field>

      <Field label="Descrição" htmlFor="description" error={error("description")}>
        <Textarea
          id="description"
          name="description"
          defaultValue={text("description", brand?.description)}
          rows={3}
          placeholder="Linha de produtos, origem, observações…"
        />
      </Field>
    </CatalogFormShell>
  );
}
