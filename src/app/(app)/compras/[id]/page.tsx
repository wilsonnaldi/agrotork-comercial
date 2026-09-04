import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ArrowUpRight, Pencil, Trash2, TrendingDown, TrendingUp } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { EmptyState } from "@/components/ui/empty-state";
import { Field, Input } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { requirePermission } from "@/lib/auth/session";
import { getProductOptions, getPurchaseWithItems } from "@/modules/purchases/service";
import {
  addItemAction,
  cancelPurchaseAction,
  receivePurchaseAction,
  removeItemAction,
} from "@/modules/purchases/actions";
import { isEditable } from "@/modules/purchases/types";
import { PURCHASE_STATUS_LABELS, PURCHASE_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Entrada" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

/** Décimos de centavo -> "R$ 1.166,6700". Quatro casas, porque é o que o rateio gera. */
function formatLanded(decimillis: number | null): string {
  if (decimillis === null) return "—";
  return `R$ ${(decimillis / 10000).toLocaleString("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  })}`;
}

export default async function PurchasePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  await requirePermission("purchases.manage");

  const [{ id }, query] = await Promise.all([params, searchParams]);
  const nota = await getPurchaseWithItems(id);
  if (!nota) notFound();

  const rascunho = isEditable(nota.status);
  const produtos = rascunho ? await getProductOptions() : [];
  const rateio =
    nota.freight_amount_cents + nota.other_amount_cents - nota.discount_amount_cents;

  return (
    <>
      <Link
        href="/compras"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Entradas
      </Link>

      <PageHeader
        title={nota.number}
        description={`${nota.supplier_name}${nota.invoice_number ? ` · NF ${nota.invoice_number}` : ""}`}
        action={
          rascunho && (
            <Button asChild variant="secondary">
              <Link href={`/compras/${nota.id}/editar`}>
                <Pencil className="size-4" aria-hidden />
                Editar
              </Link>
            </Button>
          )
        }
      />

      {typeof query.importada === "string" && (
        <Alert tone="success" className="mb-4">
          Nota importada do XML. Confira os itens e confirme o recebimento para o estoque e o
          custo se mexerem.
        </Alert>
      )}
      {typeof query.criada === "string" && (
        <Alert tone="success" className="mb-4">
          Rascunho criado. Adicione os itens e depois confirme o recebimento.
        </Alert>
      )}
      {typeof query.salva === "string" && <Alert tone="success" className="mb-4">Alterações salvas.</Alert>}
      {typeof query.item === "string" && <Alert tone="success" className="mb-4">Item adicionado.</Alert>}
      {typeof query.removido === "string" && <Alert tone="success" className="mb-4">Item removido.</Alert>}
      {typeof query.recebida === "string" && (
        <Alert tone="success" className="mb-4">
          Entrada confirmada: o estoque subiu e o custo dos produtos foi atualizado.
        </Alert>
      )}
      {typeof query.cancelada === "string" && (
        <Alert tone="success" className="mb-4">Nota cancelada.</Alert>
      )}
      {typeof query.erro === "string" && (
        <Alert tone="warning" className="mb-4">{query.erro}</Alert>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card className="overflow-hidden">
            <CardHeader>
              <CardTitle>Itens</CardTitle>
              {!rascunho && (
                <span className="text-xs text-graphite-300">
                  Congelado — a nota já virou estoque
                </span>
              )}
            </CardHeader>

            {nota.items.length === 0 ? (
              <EmptyState
                icon={Trash2}
                title="Nenhum item ainda"
                description="Adicione os produtos da nota, com a quantidade e o custo que o fornecedor cobrou."
              />
            ) : (
              <>
                <table className="hidden w-full text-sm lg:table">
                  <thead>
                    <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                      <th className="px-5 py-3 font-medium">Produto</th>
                      <th className="px-5 py-3 text-right font-medium">Qtd.</th>
                      <th className="px-5 py-3 text-right font-medium">Custo</th>
                      <th className="px-5 py-3 text-right font-medium">Total</th>
                      {!rascunho && <th className="px-5 py-3 text-right font-medium">Com frete</th>}
                      {rascunho && <th className="px-5 py-3"></th>}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-line">
                    {nota.items.map((item) => (
                      <tr key={item.id}>
                        <td className="px-5 py-3">
                          <Link
                            href={`/estoque/${item.product_id}`}
                            className="font-medium hover:text-brand"
                          >
                            {item.product_name}
                          </Link>
                          <span className="block text-xs tnum text-graphite-300">
                            {item.product_code}
                          </span>
                        </td>
                        <td className="px-5 py-3 text-right tnum">
                          {formatQuantity(item.quantity_milli)}
                          {item.unit_code && <span className="text-graphite-300"> {item.unit_code}</span>}
                        </td>
                        <td className="px-5 py-3 text-right tnum">{formatCents(item.unit_cost_cents)}</td>
                        <td className="px-5 py-3 text-right tnum font-medium">
                          {formatCents(item.line_total_cents)}
                        </td>
                        {!rascunho && (
                          <td className="px-5 py-3 text-right">
                            <span className="tnum font-medium">
                              {formatLanded(item.landed_cost_decimillis)}
                            </span>
                            <Variacao item={item} />
                          </td>
                        )}
                        {rascunho && (
                          <td className="px-5 py-3 text-right">
                            <form action={removeItemAction}>
                              <input type="hidden" name="purchase_id" value={nota.id} />
                              <input type="hidden" name="item_id" value={item.id} />
                              <button
                                type="submit"
                                className="text-graphite-300 hover:text-brand"
                                aria-label={`Remover ${item.product_name}`}
                              >
                                <Trash2 className="size-4" aria-hidden />
                              </button>
                            </form>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>

                <ul className="divide-y divide-line lg:hidden">
                  {nota.items.map((item) => (
                    <li key={item.id} className="px-4 py-3.5">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate font-medium">{item.product_name}</p>
                          <p className="mt-0.5 truncate text-xs text-graphite-300">
                            {formatQuantity(item.quantity_milli)}
                            {item.unit_code ? ` ${item.unit_code}` : ""}
                            {` × ${formatCents(item.unit_cost_cents)}`}
                          </p>
                          {!rascunho && (
                            <p className="mt-0.5 text-xs text-graphite-500">
                              com frete: {formatLanded(item.landed_cost_decimillis)}
                            </p>
                          )}
                        </div>
                        <div className="shrink-0 text-right">
                          <p className="tnum text-sm font-medium">{formatCents(item.line_total_cents)}</p>
                          {rascunho && (
                            <form action={removeItemAction} className="mt-1">
                              <input type="hidden" name="purchase_id" value={nota.id} />
                              <input type="hidden" name="item_id" value={item.id} />
                              <button type="submit" className="text-xs text-graphite-300 underline">
                                remover
                              </button>
                            </form>
                          )}
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              </>
            )}

            {rascunho && produtos.length > 0 && (
              <CardBody className="border-t border-line">
                <form action={addItemAction} className="grid gap-3 sm:grid-cols-[1fr_auto_auto_auto]">
                  <input type="hidden" name="purchase_id" value={nota.id} />

                  <Field label="Produto" htmlFor="product_id">
                    <Select id="product_id" name="product_id" required>
                      <option value="">Escolha…</option>
                      {produtos.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.code} · {p.name}
                        </option>
                      ))}
                    </Select>
                  </Field>

                  <Field label="Quantidade" htmlFor="quantity">
                    <Input id="quantity" name="quantity" inputMode="decimal" placeholder="1" required />
                  </Field>

                  <Field label="Custo unitário" htmlFor="unit_cost">
                    <Input id="unit_cost" name="unit_cost" inputMode="decimal" placeholder="0,00" required />
                  </Field>

                  <div className="flex items-end">
                    <Button type="submit" variant="secondary" fullWidth>
                      Adicionar
                    </Button>
                  </div>
                </form>
              </CardBody>
            )}
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
              <Badge tone={PURCHASE_STATUS_TONE[nota.status]}>
                {PURCHASE_STATUS_LABELS[nota.status]}
              </Badge>
            </CardHeader>
            <CardBody className="space-y-3">
              <dl className="space-y-1.5 text-sm">
                <Linha rotulo="Fornecedor" valor={nota.supplier_name} />
                <Linha rotulo="Condição" valor={nota.condition_name} />
                <Linha rotulo="Emissão" valor={formatDate(nota.issue_date)} />
                {nota.received_date && (
                  <Linha rotulo="Recebida em" valor={formatDate(nota.received_date)} />
                )}
              </dl>

              <dl className="space-y-1.5 border-t border-line pt-3 text-sm">
                <Linha rotulo="Itens" valor={formatCents(nota.items_total_cents)} />
                {nota.freight_amount_cents > 0 && (
                  <Linha rotulo="Frete" valor={formatCents(nota.freight_amount_cents)} />
                )}
                {nota.other_amount_cents > 0 && (
                  <Linha rotulo="Outras despesas" valor={formatCents(nota.other_amount_cents)} />
                )}
                {nota.discount_amount_cents > 0 && (
                  <Linha rotulo="Desconto" valor={`− ${formatCents(nota.discount_amount_cents)}`} />
                )}
                <div className="flex justify-between gap-4 border-t border-line pt-1.5 text-base font-medium">
                  <dt>Total</dt>
                  <dd className="tnum">{formatCents(nota.total_cents)}</dd>
                </div>
              </dl>

              {rascunho && (
                <div className="space-y-2 border-t border-line pt-3">
                  {rateio !== 0 && nota.items.length > 0 && (
                    <p className="text-xs text-graphite-500">
                      {formatCents(rateio)} de frete e despesas serão rateados entre os itens
                      pelo valor de cada um.
                    </p>
                  )}

                  <form action={receivePurchaseAction}>
                    <input type="hidden" name="id" value={nota.id} />
                    <ConfirmButton
                      label="Dar entrada no estoque"
                      confirmLabel="Sim, dar entrada"
                      question="O estoque sobe e o custo dos produtos passa a ser o desta nota. Depois disso a nota não muda mais."
                      variant="primary"
                    />
                  </form>

                  <form action={cancelPurchaseAction}>
                    <input type="hidden" name="id" value={nota.id} />
                    <ConfirmButton
                      label="Cancelar nota"
                      confirmLabel="Sim, cancelar"
                      question="A nota fica registrada como cancelada. Nada entra no estoque."
                    />
                  </form>
                </div>
              )}

              {nota.status === "received" && (
                <div className="space-y-2 border-t border-line pt-3">
                  <p className="text-xs text-graphite-300">
                    Esta nota já virou estoque e virou custo. Para corrigir, lance um ajuste ou uma
                    devolução ao fornecedor na tela de estoque.
                  </p>
                  <Button asChild variant="secondary" fullWidth>
                    <Link href="/estoque">
                      <ArrowUpRight className="size-4" aria-hidden />
                      Ir para o estoque
                    </Link>
                  </Button>
                </div>
              )}
            </CardBody>
          </Card>

          {nota.notes && (
            <Card>
              <CardHeader>
                <CardTitle>Observações</CardTitle>
              </CardHeader>
              <CardBody>
                <p className="text-sm whitespace-pre-wrap">{nota.notes}</p>
              </CardBody>
            </Card>
          )}
        </div>
      </div>
    </>
  );
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-graphite-500">{rotulo}</dt>
      <dd className="tnum">{valor}</dd>
    </div>
  );
}

/**
 * Quanto o custo do produto mudou com esta nota.
 *
 * É a metade "e avisa" da decisão: a entrada atualiza o custo sozinha, e
 * quem olha a nota vê exatamente o que ela mexeu. Produto que nunca teve
 * custo não mostra variação — não há de quê comparar.
 */
function Variacao({
  item,
}: {
  item: { landed_cost_decimillis: number | null; previous_cost_cents: number | null };
}) {
  if (item.landed_cost_decimillis === null || item.previous_cost_cents === null) return null;

  const novo = Math.round(item.landed_cost_decimillis / 100);
  const antes = item.previous_cost_cents;
  if (antes === 0 || novo === antes) return null;

  const variacao = ((novo - antes) / antes) * 100;
  const subiu = novo > antes;

  return (
    <span
      className={
        subiu
          ? "mt-0.5 flex items-center justify-end gap-1 text-xs text-brand-deep"
          : "mt-0.5 flex items-center justify-end gap-1 text-xs text-emerald-700"
      }
    >
      {subiu ? (
        <TrendingUp className="size-3" aria-hidden />
      ) : (
        <TrendingDown className="size-3" aria-hidden />
      )}
      {subiu ? "+" : ""}
      {variacao.toFixed(1).replace(".", ",")}% · antes {formatCents(antes)}
    </span>
  );
}
