"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Lock, Plus, SquareCheck, Trash2 } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import type { FormState } from "@/lib/forms/action-state";
import { formatQuantity } from "@/modules/kits/schema";
import type { ComponentCandidate, KitItemView } from "@/modules/kits/types";
import { formatCents } from "@/lib/format/money";

type Action = (state: FormState, formData: FormData) => Promise<FormState>;

/**
 * Editor da COMPOSIÇÃO do kit.
 *
 * Cada linha é um formulário próprio, com Server Action própria. Não existe
 * um "salvar tudo": adicionar, mudar quantidade, alternar o papel e remover
 * são operações independentes, cada uma validada no servidor. Isso evita o
 * estado gigante de cliente que o formulário de produto já nos ensinou a
 * temer — e faz cada alteração valer sozinha, mesmo que a próxima falhe.
 *
 * IMPORTANTE, e a razão de NÃO haver checkbox aqui:
 * o cadastro apenas DECLARA o que é obrigatório e o que é opcional. Marcar
 * um opcional para incluir numa venda é outra coisa, acontece no orçamento
 * e não toca neste cadastro.
 */

function Pending({ label, pendingLabel }: { label: string; pendingLabel: string }) {
  const { pending } = useFormStatus();
  return <>{pending ? pendingLabel : label}</>;
}

const ROW_BUTTON =
  "inline-flex h-10 items-center justify-center gap-1.5 rounded-lg border border-line px-3 text-xs font-medium text-graphite-500 hover:border-brand/40 hover:text-brand disabled:opacity-50";

export function ComponentRow({
  action,
  kitId,
  item,
}: {
  action: Action;
  kitId: string;
  item: KitItemView;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const alvo = item.item_type === "required" ? "optional" : "required";

  return (
    <li className="px-4 py-3 lg:px-5">
      <form key={state.attempt ?? 0} action={formAction} className="space-y-2">
        <input type="hidden" name="kit_id" value={kitId} />
        <input type="hidden" name="item_id" value={item.id} />

        {state.error && (
          <Alert tone="error" className="mb-2">
            {state.error}
          </Alert>
        )}

        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <div className="min-w-0 flex-1">
            <p className="truncate font-medium">
              {item.product_name}
              {!item.product_is_active && (
                <Badge tone="warning" className="ml-2">
                  Produto inativo
                </Badge>
              )}
            </p>
            <p className="mt-0.5 truncate text-xs text-graphite-300">
              <span className="tnum">{item.product_code}</span>
              {item.brand_name && ` · ${item.brand_name}`}
              {` · ${formatCents(item.sale_price_cents)}`}
              {item.unit_code && ` / ${item.unit_code}`}
            </p>
          </div>

          <label className="flex items-center gap-2 text-xs text-graphite-300">
            <span className="sr-only lg:not-sr-only">Qtd.</span>
            <input
              type="text"
              name="quantity"
              inputMode="decimal"
              defaultValue={formatQuantity(item.quantity_milli)}
              aria-label={`Quantidade de ${item.product_name}`}
              className="h-10 w-20 rounded-lg border border-line px-2 text-right text-sm text-graphite tnum focus:border-brand focus:outline-none"
            />
          </label>

          <button type="submit" name="acao" value="quantidade" className={ROW_BUTTON}>
            <Pending label="Salvar qtd." pendingLabel="…" />
          </button>

          <button type="submit" name="acao" value="alternar" className={ROW_BUTTON}>
            <input type="hidden" name="para" value={alvo} />
            {alvo === "optional" ? (
              <>
                <SquareCheck className="size-3.5" aria-hidden />
                Tornar opcional
              </>
            ) : (
              <>
                <Lock className="size-3.5" aria-hidden />
                Tornar obrigatório
              </>
            )}
          </button>

          <button
            type="submit"
            name="acao"
            value="remover"
            aria-label={`Remover ${item.product_name} do kit`}
            className={`${ROW_BUTTON} hover:border-brand hover:text-brand`}
          >
            <Trash2 className="size-3.5" aria-hidden />
            Remover
          </button>
        </div>
      </form>
    </li>
  );
}

/**
 * Uma linha de resultado da busca vira dois botões: entra como obrigatório
 * ou como opcional. O papel viaja no `value` do próprio botão — um clique,
 * uma decisão, sem estado intermediário.
 */
export function AddComponentForm({
  action,
  kitId,
  candidate,
}: {
  action: Action;
  kitId: string;
  candidate: ComponentCandidate;
}) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const erro = state.error ?? state.fieldErrors?.product_id ?? state.fieldErrors?.quantity;

  return (
    <li className="px-4 py-3 lg:px-5">
      <form key={state.attempt ?? 0} action={formAction} className="space-y-2">
        <input type="hidden" name="kit_id" value={kitId} />
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

          {candidate.already_in_kit ? (
            <Badge tone="neutral">Já está no kit</Badge>
          ) : (
            <>
              <label className="flex items-center gap-2 text-xs text-graphite-300">
                <span className="sr-only lg:not-sr-only">Qtd.</span>
                <input
                  type="text"
                  name="quantity"
                  inputMode="decimal"
                  defaultValue="1"
                  aria-label={`Quantidade de ${candidate.name}`}
                  className="h-10 w-20 rounded-lg border border-line px-2 text-right text-sm text-graphite tnum focus:border-brand focus:outline-none"
                />
              </label>

              <button
                type="submit"
                name="item_type"
                value="required"
                className="inline-flex h-10 items-center gap-1.5 rounded-lg bg-brand px-3 text-xs font-medium text-white hover:bg-brand-deep disabled:opacity-50"
              >
                <Lock className="size-3.5" aria-hidden />
                <Pending label="Obrigatório" pendingLabel="…" />
              </button>

              <button type="submit" name="item_type" value="optional" className={ROW_BUTTON}>
                <Plus className="size-3.5" aria-hidden />
                <Pending label="Opcional" pendingLabel="…" />
              </button>
            </>
          )}
        </div>
      </form>
    </li>
  );
}
