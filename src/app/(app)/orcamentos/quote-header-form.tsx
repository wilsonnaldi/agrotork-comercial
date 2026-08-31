"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import type { FormState } from "@/lib/forms/action-state";

type Quote = {
  id: string;
  customer_id: string;
  issue_date: string;
  valid_until: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  notes: string | null;
  internal_notes: string | null;
};

/**
 * Cabeçalho do orçamento: cliente, datas e condições comerciais.
 *
 * Os ITENS não estão aqui. Montar a proposta é operação de servidor, item
 * a item, na tela de edição — cada alteração validada e totalizada pelo
 * banco, sem um estado grande de cliente para se perder.
 */
export function QuoteHeaderForm({
  action,
  submitLabel,
  customers,
  quote,
  cancelHref,
  compact,
}: {
  action: (state: FormState, formData: FormData) => Promise<FormState>;
  submitLabel: string;
  customers: { id: string; name: string; city: string | null }[];
  quote?: Quote;
  cancelHref: string;
  /** Na tela de edição o formulário é só mais um bloco, sem card próprio. */
  compact?: boolean;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});

  const text = (field: string, fallback?: string | null) => state.values?.[field] ?? fallback ?? "";
  const error = (field: string) => state.fieldErrors?.[field];
  const salvo = state.values?.salvo === "1";

  const campos = (
    <>
      <Field label="Cliente" htmlFor="customer_id" required error={error("customer_id")}>
        <Select id="customer_id" name="customer_id" defaultValue={text("customer_id", quote?.customer_id)} required>
          <option value="">Selecione o cliente</option>
          {customers.map((customer) => (
            <option key={customer.id} value={customer.id}>
              {customer.name}
              {customer.city ? ` — ${customer.city}` : ""}
            </option>
          ))}
        </Select>
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Emissão" htmlFor="issue_date" error={error("issue_date")}>
          <Input
            id="issue_date"
            name="issue_date"
            type="date"
            defaultValue={text("issue_date", quote?.issue_date)}
          />
        </Field>

        <Field label="Válido até" htmlFor="valid_until" error={error("valid_until")}>
          <Input
            id="valid_until"
            name="valid_until"
            type="date"
            defaultValue={text("valid_until", quote?.valid_until)}
          />
        </Field>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Condição de pagamento" htmlFor="payment_terms" error={error("payment_terms")}>
          <Input
            id="payment_terms"
            name="payment_terms"
            defaultValue={text("payment_terms", quote?.payment_terms)}
            autoComplete="off"
            placeholder="30/60/90 dias"
          />
        </Field>

        <Field label="Prazo de entrega" htmlFor="delivery_terms" error={error("delivery_terms")}>
          <Input
            id="delivery_terms"
            name="delivery_terms"
            defaultValue={text("delivery_terms", quote?.delivery_terms)}
            autoComplete="off"
            placeholder="15 dias após a confirmação"
          />
        </Field>
      </div>

      <Field label="Observações" htmlFor="notes" error={error("notes")} hint="Sai no orçamento do cliente">
        <Textarea id="notes" name="notes" defaultValue={text("notes", quote?.notes)} rows={3} />
      </Field>

      <Field
        label="Observações internas"
        htmlFor="internal_notes"
        error={error("internal_notes")}
        hint="Nunca sai no documento do cliente"
      >
        <Textarea
          id="internal_notes"
          name="internal_notes"
          defaultValue={text("internal_notes", quote?.internal_notes)}
          rows={2}
        />
      </Field>
    </>
  );

  return (
    <form
      // Remonta a cada resposta: o React reseta o formulário depois da
      // Server Action. Ver `lib/forms/action-state.ts`.
      key={state.attempt ?? 0}
      action={formAction}
      className={compact ? "space-y-4" : "max-w-2xl space-y-5"}
      noValidate
    >
      {quote && <input type="hidden" name="id" value={quote.id} />}
      {state.error && <Alert tone="error">{state.error}</Alert>}
      {salvo && <Alert tone="success">Cabeçalho salvo.</Alert>}

      {compact ? (
        <div className="space-y-4">{campos}</div>
      ) : (
        <Card>
          <CardBody className="space-y-4">{campos}</CardBody>
        </Card>
      )}

      <div className="flex flex-col-reverse gap-3 pb-2 sm:flex-row sm:justify-end">
        {!compact && (
          <Button asChild variant="secondary" size="lg" className="w-full sm:w-auto">
            <Link href={cancelHref}>Cancelar</Link>
          </Button>
        )}
        <SubmitButton label={submitLabel} compact={compact} />
      </div>
    </form>
  );
}

function SubmitButton({ label, compact }: { label: string; compact?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <Button
      type="submit"
      size={compact ? "md" : "lg"}
      disabled={pending}
      variant={compact ? "secondary" : "primary"}
      className="w-full sm:w-auto"
    >
      {pending ? "Salvando…" : label}
    </Button>
  );
}
