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
import type { SupplierFormState } from "@/modules/suppliers/actions";
import type { PersonType, Supplier } from "@/types/db";

/**
 * Gêmeo do formulário de cliente, de propósito: quem já sabe cadastrar
 * cliente não precisa aprender outra tela. As duas diferenças estão no
 * bloco "Relação comercial" — quem nos atende lá, e o prazo que ELE dá.
 */

type Action = (state: SupplierFormState, formData: FormData) => Promise<SupplierFormState>;

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : label}
    </Button>
  );
}

export function SupplierForm({
  action,
  supplier,
  submitLabel,
  cancelHref,
}: {
  action: Action;
  supplier?: Supplier | null;
  submitLabel: string;
  cancelHref: string;
}) {
  const [state, formAction] = useActionState<SupplierFormState, FormData>(action, {});
  const kept = state.values;
  const value = (field: keyof Supplier) =>
    kept?.[field as string] ?? ((supplier?.[field] as string | null) ?? "") ?? "";

  const [personType, setPersonType] = useState<PersonType>(
    () => (value("person_type") as PersonType) || supplier?.person_type || "company",
  );
  const [uf, setUf] = useState(() => value("state") || supplier?.state || DEFAULT_STATE);

  const isCompany = personType === "company";
  const error = (field: string) => state.fieldErrors?.[field];

  return (
    <form key={state.attempt ?? 0} action={formAction} className="max-w-3xl space-y-5" noValidate>
      {supplier && <input type="hidden" name="id" value={supplier.id} />}
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
              placeholder={isCompany ? "DJI do Brasil Ltda" : "José da Oficina"}
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

          <Field label="E-mail" htmlFor="email" error={error("email")}>
            <Input
              id="email"
              name="email"
              type="email"
              inputMode="email"
              autoCapitalize="none"
              autoComplete="off"
              defaultValue={value("email")}
              placeholder="vendas@fornecedor.com.br"
            />
          </Field>

          <Field label="Site" htmlFor="website" error={error("website")} hint="Onde ficam catálogo e tabela">
            <Input
              id="website"
              name="website"
              inputMode="url"
              autoCapitalize="none"
              autoComplete="off"
              defaultValue={value("website")}
              placeholder="www.fornecedor.com.br"
            />
          </Field>
        </CardBody>
      </Card>

      {/* ── Relação comercial ───────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Relação comercial</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-2">
          <Field label="Quem nos atende" htmlFor="contact_name" hint="Nome do representante ou vendedor">
            <Input
              id="contact_name"
              name="contact_name"
              defaultValue={value("contact_name")}
              autoComplete="off"
              autoCapitalize="words"
            />
          </Field>

          <Field
            label="Condição de pagamento"
            htmlFor="payment_terms"
            hint="O prazo que ele dá para nós"
          >
            <Input
              id="payment_terms"
              name="payment_terms"
              defaultValue={value("payment_terms")}
              autoComplete="off"
              placeholder="28/56/84 dias"
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
            <Select id="state" name="state" value={uf} onChange={(event) => setUf(event.target.value)}>
              <option value="">—</option>
              {BRAZIL_STATES.map((estado) => (
                <option key={estado.code} value={estado.code}>
                  {estado.code} · {estado.name}
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
          <Field label="Anotações internas" htmlFor="notes" hint="Só a equipe vê">
            <Textarea id="notes" name="notes" defaultValue={value("notes")} rows={4} />
          </Field>

          {supplier && (
            <label className="flex items-center gap-3 text-sm">
              <input
                type="checkbox"
                name="is_active"
                value="true"
                defaultChecked={supplier.is_active}
                className="size-5 rounded border-line accent-brand"
              />
              Fornecedor ativo
            </label>
          )}
          {supplier && <input type="hidden" name="is_active" value="false" />}
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
