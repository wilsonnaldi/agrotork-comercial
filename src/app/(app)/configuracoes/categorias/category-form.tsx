"use client";

import { Field, Input, Textarea } from "@/components/ui/field";
import type { FormState } from "@/lib/forms/action-state";
import { CatalogFormShell, useCatalogForm } from "../catalog-form";

type Category = { id: string; name: string; description: string | null; is_active: boolean };

/** Formulário de CATEGORIA — cadastro e edição. */
export function CategoryForm({
  action,
  submitLabel,
  category,
}: {
  action: (state: FormState, formData: FormData) => Promise<FormState>;
  submitLabel: string;
  category?: Category;
}) {
  const { formAction, state, text, error } = useCatalogForm(action);

  return (
    <CatalogFormShell
      formAction={formAction}
      attempt={state.attempt}
      error={state.error}
      submitLabel={submitLabel}
      cancelHref="/configuracoes/categorias"
      id={category?.id}
      isActive={category?.is_active}
      activeLabel="Categoria ativa"
    >
      <Field
        label="Nome"
        htmlFor="name"
        required
        error={error("name")}
        hint="Único entre as categorias"
      >
        <Input
          id="name"
          name="name"
          defaultValue={text("name", category?.name)}
          autoComplete="off"
          placeholder="Pulverização"
          required
        />
      </Field>

      <Field label="Descrição" htmlFor="description" error={error("description")}>
        <Textarea
          id="description"
          name="description"
          defaultValue={text("description", category?.description)}
          rows={3}
          placeholder="O que entra nesta categoria…"
        />
      </Field>
    </CatalogFormShell>
  );
}
