"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Field, Input } from "@/components/ui/field";
import { MaskedInput } from "@/components/ui/masked-input";
import type { FormState } from "@/lib/forms/action-state";

type Acao = (state: FormState, formData: FormData) => Promise<FormState>;

type Empresa = {
  legal_name: string;
  trade_name: string;
  document: string | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  zip_code: string | null;
  website: string | null;
};

/**
 * Dados que saem no cabeçalho do PDF e na página pública do orçamento.
 * Só a razão social é obrigatória — o resto aparece quando preenchido.
 */
export function CompanyForm({ action, empresa }: { action: Acao; empresa: Empresa }) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const texto = (campo: keyof Empresa) => state.values?.[campo] ?? empresa[campo] ?? "";
  const erro = (campo: string) => state.fieldErrors?.[campo];

  return (
    <form key={state.attempt ?? 0} action={formAction} className="max-w-2xl space-y-5" noValidate>
      {state.error && <Alert tone="error">{state.error}</Alert>}

      <Card>
        <CardBody className="space-y-4">
          <Field label="Razão social" htmlFor="legal_name" required error={erro("legal_name")}>
            <Input id="legal_name" name="legal_name" defaultValue={texto("legal_name")} required />
          </Field>

          <Field
            label="Nome fantasia"
            htmlFor="trade_name"
            error={erro("trade_name")}
            hint="Em branco, o PDF usa a razão social"
          >
            <Input id="trade_name" name="trade_name" defaultValue={texto("trade_name")} />
          </Field>

          <Field label="CNPJ" htmlFor="document" error={erro("document")}>
            <MaskedInput id="document" name="document" mask="cnpj" defaultValue={texto("document")} />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardBody className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Telefone" htmlFor="phone" error={erro("phone")} className="min-w-0">
              <MaskedInput id="phone" name="phone" mask="phone" defaultValue={texto("phone")} />
            </Field>
            <Field label="WhatsApp" htmlFor="whatsapp" error={erro("whatsapp")} className="min-w-0">
              <MaskedInput id="whatsapp" name="whatsapp" mask="phone" defaultValue={texto("whatsapp")} />
            </Field>
          </div>

          <Field label="E-mail" htmlFor="email" error={erro("email")}>
            <Input id="email" name="email" type="email" defaultValue={texto("email")} />
          </Field>

          <Field label="Site" htmlFor="website" error={erro("website")}>
            <Input id="website" name="website" defaultValue={texto("website")} placeholder="agrotork.com.br" />
          </Field>
        </CardBody>
      </Card>

      <Card>
        <CardBody className="space-y-4">
          <Field label="Endereço" htmlFor="address" error={erro("address")}>
            <Input id="address" name="address" defaultValue={texto("address")} placeholder="Av. Tiradentes, 1500" />
          </Field>

          <div className="grid gap-4 sm:grid-cols-[1fr_6rem_8rem]">
            <Field label="Cidade" htmlFor="city" error={erro("city")} className="min-w-0">
              <Input id="city" name="city" defaultValue={texto("city")} />
            </Field>
            <Field label="UF" htmlFor="state" error={erro("state")} className="min-w-0">
              <Input id="state" name="state" maxLength={2} defaultValue={texto("state")} className="uppercase" />
            </Field>
            <Field label="CEP" htmlFor="zip_code" error={erro("zip_code")} className="min-w-0">
              <MaskedInput id="zip_code" name="zip_code" mask="zip" defaultValue={texto("zip_code")} />
            </Field>
          </div>
        </CardBody>
      </Card>

      <div className="flex flex-col-reverse gap-3 pb-2 sm:flex-row sm:justify-end">
        <Button asChild variant="secondary" size="lg" className="w-full sm:w-auto">
          <Link href="/configuracoes">Cancelar</Link>
        </Button>
        <Salvar />
      </div>
    </form>
  );
}

function Salvar() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : "Salvar dados"}
    </Button>
  );
}
