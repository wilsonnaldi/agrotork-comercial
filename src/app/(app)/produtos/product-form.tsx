"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { MoneyInput } from "@/components/ui/money-input";
import { Alert } from "@/components/ui/alert";
import { formatCents, marginPercent, parseMoneyToCents, saleFromMargin } from "@/lib/format/money";
import type { ProductFormState } from "@/modules/products/actions";
import type { CatalogOptions, ProductView } from "@/modules/products/types";

type Action = (state: ProductFormState, formData: FormData) => Promise<ProductFormState>;

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Salvando…" : label}
    </Button>
  );
}

export function ProductForm({
  action,
  product,
  options,
  canViewCost,
  submitLabel,
  cancelHref,
}: {
  action: Action;
  product?: ProductView | null;
  options: CatalogOptions;
  canViewCost: boolean;
  submitLabel: string;
  cancelHref: string;
}) {
  const [state, formAction] = useActionState<ProductFormState, FormData>(action, {});

  // `state.values` é o que o servidor devolveu depois de um erro.
  // Ele precisa entrar já na inicialização: sem JavaScript o formulário
  // é enviado por POST nativo, a página volta renderizada do servidor e
  // este componente REMONTA — se o estado partisse só de `product`, o
  // usuário perderia tudo o que tinha escolhido.
  const kept = state.values;
  const text = (field: string, fallback?: string | null) => kept?.[field] ?? fallback ?? "";

  // Selects controlados: com `defaultValue` a escolha também se perdia
  // no caminho com JavaScript.
  const [brandId, setBrandId] = useState(() => text("brand_id", product?.brand_id));
  const [categoryId, setCategoryId] = useState(() => text("category_id", product?.category_id));
  const [unitId, setUnitId] = useState(() => text("unit_id", product?.unit_id));

  const [costCents, setCostCents] = useState<number | null>(
    () => parseMoneyToCents(kept?.cost_price ?? "") ?? product?.cost_price_cents ?? null,
  );
  const [saleCents, setSaleCents] = useState<number | null>(
    () => parseMoneyToCents(kept?.sale_price ?? "") ?? product?.sale_price_cents ?? null,
  );
  const [imageUrl, setImageUrl] = useState(() => text("image_url", product?.image_url));

  const margin = marginPercent(costCents, saleCents);
  const belowCost = costCents !== null && saleCents !== null && costCents > 0 && saleCents < costCents;
  const error = (field: string) => state.fieldErrors?.[field];

  return (
    <form
      // Remonta o formulário a cada resposta de erro: o React reseta os
      // campos depois da Server Action e não ressincroniza os controlados.
      key={state.attempt ?? 0}
      action={formAction}
      className="max-w-3xl space-y-5"
      noValidate
    >
      {product && <input type="hidden" name="id" value={product.id} />}
      {state.error && <Alert tone="error">{state.error}</Alert>}

      {/* ── Identificação ───────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Identificação</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-3">
          <Field
            label="Código"
            htmlFor="code"
            required
            error={error("code")}
            hint="Único no catálogo"
          >
            <Input
              id="code"
              name="code"
              defaultValue={text("code", product?.code)}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              placeholder="BIC-110-02"
              className="uppercase"
              required
            />
          </Field>

          <Field label="Nome" htmlFor="name" required error={error("name")} className="sm:col-span-2">
            <Input
              id="name"
              name="name"
              defaultValue={text("name", product?.name)}
              autoComplete="off"
              placeholder="Bico de pulverização AD 110-02"
              required
            />
          </Field>

          <Field label="Descrição" htmlFor="description" className="sm:col-span-3">
            <Textarea
              id="description"
              name="description"
              defaultValue={text("description", product?.description)}
              rows={3}
              placeholder="Detalhes técnicos, aplicação, compatibilidade…"
            />
          </Field>
        </CardBody>
      </Card>

      {/* ── Classificação ───────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Classificação</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-2">
          <Field label="Marca" htmlFor="brand_id" error={error("brand_id")}>
            <Select
              id="brand_id"
              name="brand_id"
              value={brandId}
              onChange={(event) => setBrandId(event.target.value)}
            >
              <option value="">— sem marca —</option>
              {options.brands.map((brand) => (
                <option key={brand.id} value={brand.id}>
                  {brand.name}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="Categoria" htmlFor="category_id" error={error("category_id")}>
            <Select
              id="category_id"
              name="category_id"
              value={categoryId}
              onChange={(event) => setCategoryId(event.target.value)}
            >
              <option value="">— sem categoria —</option>
              {options.categories.map((category) => (
                <option key={category.id} value={category.id}>
                  {category.name}
                </option>
              ))}
            </Select>
          </Field>

          <Field
            label="Código do fabricante"
            htmlFor="manufacturer_code"
            error={error("manufacturer_code")}
            hint="Código original de fábrica, quando houver"
          >
            <Input
              id="manufacturer_code"
              name="manufacturer_code"
              defaultValue={text("manufacturer_code", product?.manufacturer_code)}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              placeholder="AGR-9001"
              className="uppercase"
            />
          </Field>

          <Field label="Unidade" htmlFor="unit_id" required error={error("unit_id")}>
            <Select
              id="unit_id"
              name="unit_id"
              value={unitId}
              onChange={(event) => setUnitId(event.target.value)}
              required
            >
              <option value="">— selecione —</option>
              {options.units.map((unit) => (
                <option key={unit.id} value={unit.id}>
                  {unit.code} · {unit.name}
                </option>
              ))}
            </Select>
          </Field>
        </CardBody>
      </Card>

      {/* ── Preços ──────────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Preços</CardTitle>
        </CardHeader>
        <CardBody className="grid gap-4 sm:grid-cols-3">
          {canViewCost ? (
            <Field label="Preço de custo" htmlFor="cost_price" error={error("cost_price")}>
              <MoneyInput
                id="cost_price"
                name="cost_price"
                valueCents={costCents}
                onChangeCents={setCostCents}
              />
            </Field>
          ) : (
            <input type="hidden" name="cost_price" value="" />
          )}

          <Field label="Preço de venda" htmlFor="sale_price" required error={error("sale_price")}>
            <MoneyInput
              id="sale_price"
              name="sale_price"
              valueCents={saleCents}
              onChangeCents={setSaleCents}
              required
            />
          </Field>

          {canViewCost && (
            <Field
              label="Margem"
              htmlFor="margin"
              hint="Atalho: digite a margem para calcular a venda"
            >
              <div className="relative">
                <Input
                  id="margin"
                  inputMode="decimal"
                  autoComplete="off"
                  className="pr-8 text-right tnum"
                  value={margin === null ? "" : String(margin).replace(".", ",")}
                  placeholder="—"
                  disabled={!costCents}
                  onChange={(event) => {
                    const raw = event.target.value.replace(",", ".").replace(/[^\d.-]/g, "");
                    const value = Number(raw);
                    if (costCents && raw !== "" && Number.isFinite(value)) {
                      setSaleCents(saleFromMargin(costCents, value));
                    }
                  }}
                />
                <span className="pointer-events-none absolute top-1/2 right-3.5 -translate-y-1/2 text-sm text-graphite-300">
                  %
                </span>
              </div>
            </Field>
          )}

          {canViewCost && (
            <p className="text-xs text-graphite-300 sm:col-span-3">
              A margem não é armazenada: ela é sempre recalculada a partir do custo e do preço de
              venda, para que os três nunca fiquem em desacordo.
            </p>
          )}

          {belowCost && (
            <Alert tone="info" className="sm:col-span-3">
              O preço de venda ({formatCents(saleCents)}) está abaixo do custo ({formatCents(costCents)}).
              Se for promoção, pode salvar normalmente.
            </Alert>
          )}
        </CardBody>
      </Card>

      {/* ── Imagem e observações ────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Imagem e observações</CardTitle>
        </CardHeader>
        <CardBody className="space-y-4">
          <Field
            label="Endereço da imagem"
            htmlFor="image_url"
            error={error("image_url")}
            hint="O envio direto de fotos entra junto com o Storage do Supabase"
          >
            <Input
              id="image_url"
              name="image_url"
              type="url"
              inputMode="url"
              autoCapitalize="none"
              autoComplete="off"
              value={imageUrl}
              onChange={(event) => setImageUrl(event.target.value)}
              placeholder="https://…"
            />
          </Field>

          {/^https?:\/\/\S+$/i.test(imageUrl) && (
            // A imagem vem de endereço arbitrário; `next/image` entra quando
            // as fotos passarem a viver no Storage do Supabase.
            <div className="h-40 w-40 overflow-hidden rounded-lg border border-line bg-sand">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={imageUrl} alt="Pré-visualização" className="h-full w-full object-contain" />
            </div>
          )}

          <Field label="Observações internas" htmlFor="notes" hint="Não aparece para o cliente">
            <Textarea id="notes" name="notes" defaultValue={text("notes", product?.notes)} rows={3} />
          </Field>

          {product && (
            <>
              <label className="flex items-center gap-3 text-sm">
                <input
                  type="checkbox"
                  name="is_active"
                  value="true"
                  defaultChecked={product.is_active}
                  className="size-5 rounded border-line accent-brand"
                />
                Produto ativo
              </label>
              <input type="hidden" name="is_active" value="false" />
            </>
          )}
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