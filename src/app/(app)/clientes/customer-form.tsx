"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { MaskedInput } from "@/components/ui/masked-input";
import { Alert } from "@/components/ui/alert";
import { BRAZIL_STATES, DEFAULT_STATE } from "@/config/locale";
import type { CustomerFormState } from "@/modules/customers/actions";
import type { Customer, PersonType } from "@/types/db";

type Action = (state: CustomerFormState, formData: FormData) => Promise<CustomerFormState>;

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : label}
    </Button>
  );
}

export function CustomerForm({
  action,
  customer,
  submitLabel,
  cancelHref,
}: {
  action: Action;
  customer?: Customer | null;
  submitLabel: string;
  cancelHref: string;
}) {
  const [state, formAction] = useActionState<CustomerFormState, FormData>(action, {});
  // Depois de um erro, o servidor devolve o que foi digitado. Isso entra já
  // na inicialização porque, sem JavaScript, o POST é nativo e o componente
  // REMONTA com a resposta do servidor.
  const kept = state.values;
  const value = (field: keyof Customer) =>
    kept?.[field as string] ?? ((customer?.[field] as string | null) ?? "") ?? "";

  const [personType, setPersonType] = useState<PersonType>(
    () => (value("person_type") as PersonType) || customer?.person_type || "company",
  );
  // Controlado pelo mesmo motivo: com `defaultValue`, a UF escolhida se perdia.
  const [uf, setUf] = useState(() => value("state") || customer?.state || DEFAULT_STATE);

  const isCompany = personType === "company";
  const error = (field: string) => state.fieldErrors?.[field];

  return (
    <form
      // Ver `modules/customers/actions.ts`: remonta com o que o servidor
      // devolveu, porque o React reseta o formulário após a ação.
      key={state.attempt ?? 0}
      action={formAction}
      className="max-w-3xl space-y-5"
      noValidate
    >
      {customer && <input type="hidden" name="id" value={customer.id} />}
      {state.error && <Alert tone="error">{state.error}</Alert>}

      {/* ── Identificação ───────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Identificação</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-2">
          <Field label="Tipo de pessoa" htmlFor="person_type" className="sm:col-span-2">
            <Select
              id="person_type"
              name="person_type"
              value={personType}
              onChange={(event) => setPersonType(event.target.value as PersonType)}
            >
              <option value="company">Pessoa jurídica (CNPJ)</option>
              <option value="individual">Pessoa física (CPF)</option>
            </Select>
          </Field>

          <Field
            label={isCompany ? "Razão social" : "Nome completo"}
            htmlFor="name"
            required
            error={error("name")}
            className="sm:col-span-2"
          >
            <Input
              id="name"
              name="name"
              defaultValue={value("name")}
              autoComplete="off"
              autoCapitalize="words"
              placeholder={isCompany ? "AGROTORK Comércio de Máquinas Ltda" : "João da Silva"}
              required
            />
          </Field>

          {isCompany && (
            <Field label="Nome fantasia" htmlFor="trade_name" error={error("trade_name")}>
              <Input id="trade_name" name="trade_name" defaultValue={value("trade_name")} autoComplete="off" />
            </Field>
          )}

          <Field
            label={isCompany ? "CNPJ" : "CPF"}
            htmlFor="document"
            error={error("document")}
            hint="Opcional, mas evita cadastro duplicado"
          >
            <MaskedInput
              id="document"
              name="document"
              mask={isCompany ? "cnpj" : "cpf"}
              defaultValue={value("document")}
              placeholder={isCompany ? "00.000.000/0000-00" : "000.000.000-00"}
            />
          </Field>

          {isCompany && (
            <Field label="Inscrição estadual" htmlFor="state_registration" error={error("state_registration")}>
              <Input
                id="state_registration"
                name="state_registration"
                defaultValue={value("state_registration")}
                autoComplete="off"
              />
            </Field>
          )}
        </CardBody>
      </Card>

      {/* ── Contato ─────────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Contato</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-2">
          <Field label="Telefone" htmlFor="phone" error={error("phone")}>
            <MaskedInput id="phone" name="phone" mask="phone" defaultValue={value("phone")} placeholder="(43) 3333-4444" />
          </Field>

          <Field label="WhatsApp" htmlFor="whatsapp" error={error("whatsapp")}>
            <MaskedInput
              id="whatsapp"
              name="whatsapp"
              mask="phone"
              defaultValue={value("whatsapp")}
              placeholder="(43) 99999-8888"
            />
          </Field>

          <Field label="E-mail" htmlFor="email" error={error("email")} className="sm:col-span-2">
            <Input
              id="email"
              name="email"
              type="email"
              inputMode="email"
              autoCapitalize="none"
              autoComplete="off"
              defaultValue={value("email")}
              placeholder="contato@cliente.com.br"
            />
          </Field>
        </CardBody>
      </Card>

      {/* ── Endereço ────────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Endereço</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-6">
          <Field label="CEP" htmlFor="zip_code" error={error("zip_code")} className="sm:col-span-2">
            <MaskedInput id="zip_code" name="zip_code" mask="zip" defaultValue={value("zip_code")} placeholder="86000-000" />
          </Field>

          <Field label="Logradouro" htmlFor="address" error={error("address")} className="sm:col-span-4">
            <Input id="address" name="address" defaultValue={value("address")} autoComplete="off" />
          </Field>

          <Field label="Número" htmlFor="address_number" className="sm:col-span-2">
            <Input id="address_number" name="address_number" defaultValue={value("address_number")} autoComplete="off" />
          </Field>

          <Field label="Complemento" htmlFor="address_complement" className="sm:col-span-4">
            <Input
              id="address_complement"
              name="address_complement"
              defaultValue={value("address_complement")}
              autoComplete="off"
            />
          </Field>

          <Field label="Bairro" htmlFor="district" className="sm:col-span-2">
            <Input id="district" name="district" defaultValue={value("district")} autoComplete="off" />
          </Field>

          <Field label="Cidade" htmlFor="city" className="sm:col-span-2">
            <Input id="city" name="city" defaultValue={value("city")} autoComplete="off" />
          </Field>

          <Field label="UF" htmlFor="state" error={error("state")} className="sm:col-span-2">
            <Select
              id="state"
              name="state"
              value={uf}
              onChange={(event) => setUf(event.target.value)}
            >
              <option value="">—</option>
              {BRAZIL_STATES.map((uf) => (
                <option key={uf.code} value={uf.code}>
                  {uf.code} · {uf.name}
                </option>
              ))}
            </Select>
          </Field>
        </CardBody>
      </Card>

      {/* ── Observações ─────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Observações</CardTitle>
        </CardHeader>
        <CardBody className="space-y-4">
          <Field label="Anotações internas" htmlFor="notes" hint="Não aparece para o cliente">
            <Textarea id="notes" name="notes" defaultValue={value("notes")} rows={4} />
          </Field>

          {customer && (
            <label className="flex items-center gap-3 text-sm">
              <input
                type="checkbox"
                name="is_active"
                value="true"
                defaultChecked={customer.is_active}
                className="size-5 rounded border-line accent-brand"
              />
              Cliente ativo
            </label>
          )}
          {customer && <input type="hidden" name="is_active" value="false" />}
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
