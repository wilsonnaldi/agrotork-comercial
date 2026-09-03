"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { Alert } from "@/components/ui/alert";
import type { PurchaseFormState } from "@/modules/purchases/actions";
import type { PurchaseView } from "@/modules/purchases/types";

type Action = (state: PurchaseFormState, formData: FormData) => Promise<PurchaseFormState>;

/** Centavos -> "1234,56" para o campo de texto. */
function paraCampo(cents: number): string {
  return cents === 0 ? "" : (cents / 100).toFixed(2).replace(".", ",");
}

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : label}
    </Button>
  );
}

export function PurchaseForm({
  action,
  purchase,
  suppliers,
  conditions,
  submitLabel,
  cancelHref,
}: {
  action: Action;
  purchase?: PurchaseView | null;
  suppliers: { id: string; name: string }[];
  conditions: { id: string; name: string; is_default: boolean }[];
  submitLabel: string;
  cancelHref: string;
}) {
  const [state, formAction] = useActionState<PurchaseFormState, FormData>(action, {});
  const kept = state.values;
  const error = (field: string) => state.fieldErrors?.[field];
  const hoje = new Date().toISOString().slice(0, 10);
  const condicaoPadrao = conditions.find((c) => c.is_default)?.id ?? conditions[0]?.id ?? "";

  return (
    <form key={state.attempt ?? 0} action={formAction} className="max-w-3xl space-y-5" noValidate>
      {purchase && <input type="hidden" name="id" value={purchase.id} />}
      {state.error && <Alert tone="error">{state.error}</Alert>}

      <Card>
        <CardHeader>
          <CardTitle>De quem, e sob qual condição</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-2">
          <Field label="Fornecedor" htmlFor="supplier_id" required error={error("supplier_id")}>
            <Select
              id="supplier_id"
              name="supplier_id"
              defaultValue={kept?.supplier_id ?? purchase?.supplier_id ?? ""}
              required
            >
              <option value="">Escolha…</option>
              {suppliers.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </Field>

          {/* A condição decide em QUAL custo do produto esta nota mexe:
              à vista e faturado têm preços diferentes, e misturá-los
              estragaria os dois. */}
          <Field
            label="Condição de pagamento"
            htmlFor="condition_id"
            required
            error={error("condition_id")}
            hint="Define qual custo do produto será atualizado"
          >
            <Select
              id="condition_id"
              name="condition_id"
              defaultValue={kept?.condition_id ?? purchase?.condition_id ?? condicaoPadrao}
              required
            >
              {conditions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Documento do fornecedor</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-6">
          <Field label="Número da nota" htmlFor="invoice_number" error={error("invoice_number")} className="sm:col-span-2">
            <Input
              id="invoice_number"
              name="invoice_number"
              inputMode="numeric"
              autoComplete="off"
              defaultValue={kept?.invoice_number ?? purchase?.invoice_number ?? ""}
              placeholder="55501"
            />
          </Field>

          <Field label="Série" htmlFor="invoice_series" className="sm:col-span-1">
            <Input
              id="invoice_series"
              name="invoice_series"
              autoComplete="off"
              defaultValue={kept?.invoice_series ?? purchase?.invoice_series ?? ""}
              placeholder="1"
            />
          </Field>

          <Field label="Emissão" htmlFor="issue_date" required error={error("issue_date")} className="sm:col-span-3">
            <Input
              id="issue_date"
              name="issue_date"
              type="date"
              defaultValue={kept?.issue_date ?? purchase?.issue_date ?? hoje}
              required
            />
          </Field>

          <Field
            label="Chave da NF-e"
            htmlFor="invoice_key"
            error={error("invoice_key")}
            hint="44 dígitos. Opcional hoje — é o que vai permitir importar o XML depois."
            className="sm:col-span-6"
          >
            <Input
              id="invoice_key"
              name="invoice_key"
              inputMode="numeric"
              autoComplete="off"
              defaultValue={kept?.invoice_key ?? purchase?.invoice_key ?? ""}
            />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Valores da nota</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-3">
          <Field
            label="Frete"
            htmlFor="freight_amount"
            error={error("freight_amount_cents")}
            hint="Rateado entre os itens pelo valor de cada um"
          >
            <Input
              id="freight_amount"
              name="freight_amount"
              inputMode="decimal"
              autoComplete="off"
              defaultValue={kept?.freight_amount ?? (purchase ? paraCampo(purchase.freight_amount_cents) : "")}
              placeholder="0,00"
            />
          </Field>

          <Field label="Outras despesas" htmlFor="other_amount" error={error("other_amount_cents")}>
            <Input
              id="other_amount"
              name="other_amount"
              inputMode="decimal"
              autoComplete="off"
              defaultValue={kept?.other_amount ?? (purchase ? paraCampo(purchase.other_amount_cents) : "")}
              placeholder="0,00"
            />
          </Field>

          <Field label="Desconto" htmlFor="discount_amount" error={error("discount_amount_cents")}>
            <Input
              id="discount_amount"
              name="discount_amount"
              inputMode="decimal"
              autoComplete="off"
              defaultValue={kept?.discount_amount ?? (purchase ? paraCampo(purchase.discount_amount_cents) : "")}
              placeholder="0,00"
            />
          </Field>

          <Field label="Observações" htmlFor="notes" className="sm:col-span-3">
            <Textarea id="notes" name="notes" rows={3} defaultValue={kept?.notes ?? purchase?.notes ?? ""} />
          </Field>
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
