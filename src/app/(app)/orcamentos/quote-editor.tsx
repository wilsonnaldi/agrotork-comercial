"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { Boxes, Lock, Package, Plus, Trash2 } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { MoneyInput } from "@/components/ui/money-input";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import type { FormState } from "@/lib/forms/action-state";
import type {
  KitComponentSnapshot,
  ProductCandidate,
  QuoteItemView,
} from "@/modules/quotes/types";

type Action = (state: FormState, formData: FormData) => Promise<FormState>;

/**
 * Edição do orçamento, linha a linha.
 *
 * Cada linha é um formulário com Server Action própria — mesma escolha do
 * editor de kits, pelo mesmo motivo: nenhuma alteração depende de um
 * estado grande de cliente sobreviver ao retorno da action, e cada uma
 * vale sozinha.
 *
 * Nada aqui calcula o total. Os números que aparecem vêm do banco, que os
 * recalcula por trigger a cada mudança. A tela só mostra.
 */

function Pending({ label, pendingLabel = "…" }: { label: string; pendingLabel?: string }) {
  const { pending } = useFormStatus();
  return <>{pending ? pendingLabel : label}</>;
}

const ROW_BUTTON =
  "inline-flex h-10 items-center justify-center gap-1.5 rounded-lg border border-line px-3 text-xs font-medium text-graphite-500 hover:border-brand/40 hover:text-brand disabled:opacity-50";

const NUM_INPUT =
  "h-10 w-20 rounded-lg border border-line px-2 text-right text-sm text-graphite tnum focus:border-brand focus:outline-none";

/** Linha do orçamento: quantidade, desconto e remoção. */
export function ItemRow({
  action,
  quoteId,
  item,
  editable,
  children,
}: {
  action: Action;
  quoteId: string;
  item: QuoteItemView;
  editable: boolean;
  children?: React.ReactNode;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  // A regra de unidade devolve o erro no campo `quantity`; sem isto a
  // recusa acontecia no servidor e não aparecia para o usuário.
  const erro = state.error ?? state.fieldErrors?.quantity ?? state.fieldErrors?.discount_percent;

  return (
    <li className="px-4 py-3 lg:px-5">
      <form key={state.attempt ?? 0} action={formAction} className="space-y-2">
        <input type="hidden" name="quote_id" value={quoteId} />
        <input type="hidden" name="item_id" value={item.id} />

        {erro && (
          <Alert tone="error" className="mb-2">
            {erro}
          </Alert>
        )}

        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <span className="shrink-0" aria-hidden>
            {item.kind === "kit" ? (
              <Boxes className="size-4 text-brand" />
            ) : (
              <Package className="size-4 text-graphite-300" />
            )}
          </span>

          <div className="min-w-0 flex-1">
            <p className="truncate font-medium">{item.name_snapshot}</p>
            <p className="mt-0.5 truncate text-xs text-graphite-300">
              {item.code_snapshot && <span className="tnum">{item.code_snapshot}</span>}
              {item.brand_snapshot && ` · ${item.brand_snapshot}`}
              {` · ${formatCents(item.unit_price_cents)}`}
              {item.unit_snapshot && ` / ${item.unit_snapshot}`}
              {item.kind === "kit" && " · preço do kit congelado"}
            </p>
          </div>

          {editable ? (
            <>
              <label className="flex items-center gap-1.5 text-xs text-graphite-300">
                <span className="sr-only lg:not-sr-only">Qtd.</span>
                <input
                  type="text"
                  name="quantity"
                  inputMode="decimal"
                  defaultValue={formatQuantity(item.quantity_milli)}
                  aria-label={`Quantidade de ${item.name_snapshot}`}
                  className={NUM_INPUT}
                />
              </label>

              <label className="flex items-center gap-1.5 text-xs text-graphite-300">
                <span className="sr-only lg:not-sr-only">Desc.%</span>
                <input
                  type="text"
                  name="discount_percent"
                  inputMode="decimal"
                  defaultValue={String(item.discount_percent).replace(".", ",")}
                  aria-label={`Desconto de ${item.name_snapshot}`}
                  className={`${NUM_INPUT} w-16`}
                />
              </label>

              <button type="submit" name="acao" value="atualizar" className={ROW_BUTTON}>
                <Pending label="Salvar" />
              </button>

              <button
                type="submit"
                name="acao"
                value="remover"
                aria-label={`Remover ${item.name_snapshot} do orçamento`}
                className={`${ROW_BUTTON} hover:border-brand hover:text-brand`}
              >
                <Trash2 className="size-3.5" aria-hidden />
                Remover
              </button>
            </>
          ) : (
            <span className="text-xs text-graphite-300">
              {formatQuantity(item.quantity_milli)} × {formatCents(item.unit_price_cents)}
            </span>
          )}

          <span className="w-24 shrink-0 text-right tnum text-sm font-medium">
            {formatCents(item.line_total_cents)}
          </span>
        </div>
      </form>

      {children}
    </li>
  );
}

/** Composição congelada de um kit dentro do orçamento. */
export function KitComposition({
  components,
  kitQuantityMilli,
}: {
  components: KitComponentSnapshot[];
  kitQuantityMilli: number;
}) {
  const escolhidos = components.filter((component) => component.selected);
  const recusados = components.filter((component) => !component.selected);

  const linha = (component: KitComponentSnapshot, incluso: boolean) => {
    const efetiva = Math.round((component.quantity_milli * kitQuantityMilli) / 1000);
    return (
      <li
        key={`${component.product_id ?? component.code}-${component.item_type}`}
        className="flex items-center gap-2 py-0.5"
      >
        <span aria-hidden className="shrink-0">
          {component.item_type === "required" ? (
            <Lock className="size-3 text-brand" />
          ) : incluso ? (
            <span className="text-brand">☑</span>
          ) : (
            <span className="text-graphite-300">☐</span>
          )}
        </span>
        <span className={incluso ? "min-w-0 truncate" : "min-w-0 truncate text-graphite-300 line-through"}>
          {component.name}
        </span>
        <span className="ml-auto shrink-0 tnum text-graphite-300">
          {formatQuantity(efetiva)} {component.unit ?? ""}
          {incluso && ` · ${formatCents(Math.round((component.quantity_milli * component.unit_price_cents) / 1000))}`}
        </span>
      </li>
    );
  };

  return (
    <div className="mt-2 ml-7 border-l border-line pl-3 text-xs">
      <ul>{escolhidos.map((component) => linha(component, true))}</ul>
      {recusados.length > 0 && (
        <>
          <p className="mt-1.5 text-graphite-300">Opcionais não incluídos:</p>
          <ul>{recusados.map((component) => linha(component, false))}</ul>
        </>
      )}
    </div>
  );
}

/** Uma linha da busca de produtos vira um formulário de adição. */
export function AddProductRow({
  action,
  quoteId,
  candidate,
}: {
  action: Action;
  quoteId: string;
  candidate: ProductCandidate;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const erro = state.error ?? state.fieldErrors?.product_id ?? state.fieldErrors?.quantity;

  return (
    <li className="px-4 py-3 lg:px-5">
      <form key={state.attempt ?? 0} action={formAction} className="space-y-2">
        <input type="hidden" name="quote_id" value={quoteId} />
        <input type="hidden" name="product_id" value={candidate.id} />

        {erro && (
          <Alert tone="error" className="mb-2">
            {erro}
          </Alert>
        )}

        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <div className="min-w-0 flex-1">
            <p className="truncate font-medium">{candidate.name}</p>
            <p className="mt-0.5 truncate text-xs text-graphite-300">
              <span className="tnum">{candidate.code}</span>
              {candidate.manufacturer_code && ` · fab. ${candidate.manufacturer_code}`}
              {candidate.brand_name && ` · ${candidate.brand_name}`}
              {` · ${formatCents(candidate.sale_price_cents)}`}
              {candidate.unit_code && ` / ${candidate.unit_code}`}
            </p>
          </div>

          <label className="flex items-center gap-1.5 text-xs text-graphite-300">
            <span className="sr-only lg:not-sr-only">Qtd.</span>
            <input
              type="text"
              name="quantity"
              inputMode="decimal"
              defaultValue="1"
              aria-label={`Quantidade de ${candidate.name}`}
              className={NUM_INPUT}
            />
          </label>

          <button
            type="submit"
            className="inline-flex h-10 items-center gap-1.5 rounded-lg bg-brand px-3 text-xs font-medium text-white hover:bg-brand-deep disabled:opacity-50"
          >
            <Plus className="size-3.5" aria-hidden />
            <Pending label="Adicionar" />
          </button>
        </div>
      </form>
    </li>
  );
}

/**
 * Escolha dos opcionais antes de o kit entrar no orçamento.
 *
 * AQUI a caixa de seleção significa "incluir este componente NESTA venda"
 * — é o gesto oposto ao do cadastro de Kits, onde não existe caixa
 * nenhuma. Obrigatórios aparecem marcados e desabilitados: não são uma
 * escolha, e a lista deles nem sequer é enviada ao servidor.
 */
export function KitOptionalsForm({
  action,
  quoteId,
  kitId,
  itemId,
  required,
  optional,
  quantityMilli,
  submitLabel,
}: {
  action: Action;
  quoteId: string;
  kitId?: string;
  itemId?: string;
  required: KitComponentSnapshot[];
  optional: KitComponentSnapshot[];
  quantityMilli: number;
  submitLabel: string;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const [selecionados, setSelecionados] = useState<string[]>(
    optional.filter((component) => component.selected).map((component) => component.product_id ?? ""),
  );
  const [quantidade, setQuantidade] = useState(formatQuantity(quantityMilli));

  const porUnidade = (component: KitComponentSnapshot) =>
    Math.round((component.quantity_milli * component.unit_price_cents) / 1000);

  const base = required.reduce((total, component) => total + porUnidade(component), 0);
  const extras = optional
    .filter((component) => selecionados.includes(component.product_id ?? ""))
    .reduce((total, component) => total + porUnidade(component), 0);

  const unidades = Number((quantidade || "0").replace(",", ".")) || 0;

  const erro = state.error ?? state.fieldErrors?.kit_id ?? state.fieldErrors?.quantity;

  return (
    <form action={formAction} className="space-y-4">
      <input type="hidden" name="quote_id" value={quoteId} />
      {kitId && <input type="hidden" name="kit_id" value={kitId} />}
      {itemId && <input type="hidden" name="item_id" value={itemId} />}

      {erro && <Alert tone="error">{erro}</Alert>}

      <div>
        <p className="mb-2 flex items-center gap-2 text-sm font-medium">
          <Lock className="size-4 text-brand" aria-hidden />
          Obrigatórios — sempre entram
        </p>
        <ul className="space-y-1.5 text-sm">
          {required.map((component) => (
            <li key={component.product_id ?? component.code} className="flex items-center gap-2.5">
              <input
                type="checkbox"
                checked
                disabled
                aria-label={`${component.name} (obrigatório)`}
                className="size-4 rounded border-line accent-brand"
              />
              <span className="min-w-0 flex-1 truncate">{component.name}</span>
              <span className="shrink-0 tnum text-xs text-graphite-300">
                {formatQuantity(component.quantity_milli)} {component.unit ?? ""} ·{" "}
                {formatCents(porUnidade(component))}
              </span>
            </li>
          ))}
        </ul>
      </div>

      {optional.length > 0 && (
        <div className="border-t border-line pt-4">
          <p className="mb-2 text-sm font-medium">Opcionais — escolha o que entra nesta venda</p>
          <ul className="space-y-1.5 text-sm">
            {optional.map((component) => {
              const id = component.product_id ?? "";
              const marcado = selecionados.includes(id);
              return (
                <li key={id || component.code}>
                  <label className="flex cursor-pointer items-center gap-2.5">
                    <input
                      type="checkbox"
                      name="opcional"
                      value={id}
                      checked={marcado}
                      onChange={(event) =>
                        setSelecionados((atual) =>
                          event.target.checked ? [...atual, id] : atual.filter((item) => item !== id),
                        )
                      }
                      className="size-4 rounded border-line accent-brand"
                    />
                    <span className="min-w-0 flex-1 truncate">{component.name}</span>
                    <span className="shrink-0 tnum text-xs text-graphite-300">
                      + {formatCents(porUnidade(component))}
                    </span>
                  </label>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      <div className="grid gap-3 border-t border-line pt-4 sm:grid-cols-[auto_1fr]">
        <Field label="Quantidade de kits" htmlFor="quantidade-kit">
          <input
            id="quantidade-kit"
            type="text"
            name="quantity"
            inputMode="numeric"
            value={quantidade}
            onChange={(event) => setQuantidade(event.target.value)}
            className="h-12 w-28 rounded-lg border border-line px-3 text-right text-graphite tnum focus:border-brand focus:outline-none"
          />
        </Field>

        <div className="self-end rounded-lg bg-sand p-3 text-sm">
          <div className="flex justify-between text-graphite-500">
            <span>Base (obrigatórios)</span>
            <span className="tnum">{formatCents(base)}</span>
          </div>
          <div className="flex justify-between text-graphite-500">
            <span>Opcionais escolhidos</span>
            <span className="tnum">{formatCents(extras)}</span>
          </div>
          <div className="mt-1 flex justify-between border-t border-line pt-1 font-medium">
            <span>Por kit</span>
            <span className="tnum">{formatCents(base + extras)}</span>
          </div>
          {unidades > 1 && (
            <div className="flex justify-between text-graphite-500">
              <span>× {quantidade} kits</span>
              <span className="tnum">{formatCents(Math.round((base + extras) * unidades))}</span>
            </div>
          )}
          <p className="mt-1 text-xs text-graphite-300">
            Prévia. O valor gravado é recalculado no servidor.
          </p>
        </div>
      </div>

      <SubmitBlock label={submitLabel} />
    </form>
  );
}

function SubmitBlock({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" fullWidth disabled={pending}>
      {pending ? "Salvando…" : label}
    </Button>
  );
}

/** Desconto e frete do orçamento inteiro. */
export function CommercialForm({
  action,
  quoteId,
  discountPercent,
  discountAmountCents,
  shippingAmountCents,
}: {
  action: Action;
  quoteId: string;
  discountPercent: number;
  discountAmountCents: number;
  shippingAmountCents: number;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const [desconto, setDesconto] = useState<number | null>(discountAmountCents || null);
  const [frete, setFrete] = useState<number | null>(shippingAmountCents || null);

  return (
    <form key={state.attempt ?? 0} action={formAction} className="space-y-3">
      <input type="hidden" name="id" value={quoteId} />

      {state.error && <Alert tone="error">{state.error}</Alert>}
      {state.fieldErrors?.discount_percent && (
        <Alert tone="error">{state.fieldErrors.discount_percent}</Alert>
      )}
      {state.values?.salvo === "1" && <Alert tone="success">Valores aplicados.</Alert>}

      <Field label="Desconto (%)" htmlFor="discount_percent">
        <input
          id="discount_percent"
          type="text"
          name="discount_percent"
          inputMode="decimal"
          defaultValue={String(discountPercent).replace(".", ",")}
          className="h-12 w-full rounded-lg border border-line px-3.5 text-right text-graphite tnum focus:border-brand focus:outline-none"
        />
      </Field>

      <Field label="Desconto (R$)" htmlFor="discount_amount">
        <MoneyInput
          id="discount_amount"
          name="discount_amount"
          valueCents={desconto}
          onChangeCents={setDesconto}
        />
      </Field>

      <Field label="Frete (R$)" htmlFor="shipping_amount">
        <MoneyInput id="shipping_amount" name="shipping_amount" valueCents={frete} onChangeCents={setFrete} />
      </Field>

      <SubmitBlock label="Aplicar" />
    </form>
  );
}
