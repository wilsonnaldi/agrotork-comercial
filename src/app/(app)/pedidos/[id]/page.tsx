import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, FileText, Lock } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { ORDER_STATUS_LABELS, ORDER_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate } from "@/lib/format";
import { getOrderWithItems } from "@/modules/orders/service";
import { STATUS_TRANSITIONS } from "@/modules/orders/types";
import { changeStatusAction, renegotiateAction } from "@/modules/orders/actions";
import { SerialsCard } from "./serials-card";

export const metadata: Metadata = { title: "Pedido" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function OrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("orders.read");
  const { id } = await params;
  const query = await searchParams;

  const order = await getOrderWithItems(id);
  if (!order) notFound();

  const podeMover = can(user.profile.role, "orders.write");
  const proximos = STATUS_TRANSITIONS[order.status];
  const encerrado = order.status === "delivered" || order.status === "cancelled";

  return (
    <>
      <PageHeader
        title={order.number}
        description={`${order.customer_name}${order.customer_city ? ` · ${order.customer_city}` : ""}`}
        action={
          <Button asChild variant="secondary">
            <Link href="/pedidos">
              <ArrowLeft className="size-4" aria-hidden />
              Voltar
            </Link>
          </Button>
        }
      />

      {typeof query.criado === "string" && (
        <Alert tone="success" className="mb-4">
          Pedido gerado a partir do orçamento. O conteúdo está congelado a partir de agora.
        </Alert>
      )}
      {typeof query.situacao === "string" && (
        <Alert tone="success" className="mb-4">
          Situação atualizada.
        </Alert>
      )}
      {typeof query.erro === "string" && (
        <Alert tone="warning" className="mb-4">
          {query.erro}
        </Alert>
      )}
      {query.serie === "1" && (
        <Alert tone="success" className="mb-4">
          Aparelho vinculado ao pedido.
        </Alert>
      )}
      {query.serie === "0" && (
        <Alert tone="success" className="mb-4">
          Aparelho desvinculado e de volta ao galpão.
        </Alert>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Itens</CardTitle>
              <span className="inline-flex items-center gap-1.5 text-xs text-graphite-300">
                <Lock className="size-3.5" aria-hidden />
                Congelado
              </span>
            </CardHeader>

            <table className="hidden w-full text-sm lg:table">
              <thead>
                <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
                  <th className="px-5 py-3 font-medium">Item</th>
                  <th className="px-5 py-3 text-right font-medium">Qtd.</th>
                  <th className="px-5 py-3 text-right font-medium">Unitário</th>
                  <th className="px-5 py-3 text-right font-medium">Desc.</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {order.items.map((item) => (
                  <tr key={item.id}>
                    <td className="px-5 py-3">
                      <p className="font-medium">{item.name_snapshot}</p>
                      <p className="mt-0.5 text-xs text-graphite-300">
                        {[item.code_snapshot, item.brand_snapshot].filter(Boolean).join(" · ") || "—"}
                      </p>
                    </td>
                    <td className="px-5 py-3 text-right tnum">
                      {formatQuantity(item.quantity_milli)}
                      {item.unit_snapshot && (
                        <span className="text-graphite-300"> {item.unit_snapshot}</span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right tnum">{formatCents(item.unit_price_cents)}</td>
                    <td className="px-5 py-3 text-right tnum text-graphite-500">
                      {item.discount_percent > 0 ? `${item.discount_percent}%` : "—"}
                    </td>
                    <td className="px-5 py-3 text-right tnum font-medium">
                      {formatCents(item.line_total_cents)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="divide-y divide-line lg:hidden">
              {order.items.map((item) => (
                <li key={item.id} className="px-4 py-3.5">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-medium">{item.name_snapshot}</p>
                      <p className="mt-0.5 truncate text-xs text-graphite-300">
                        {formatQuantity(item.quantity_milli)}
                        {item.unit_snapshot ? ` ${item.unit_snapshot}` : ""}
                        {` × ${formatCents(item.unit_price_cents)}`}
                        {item.discount_percent > 0 ? ` − ${item.discount_percent}%` : ""}
                      </p>
                    </div>
                    <p className="shrink-0 tnum text-sm font-medium">
                      {formatCents(item.line_total_cents)}
                    </p>
                  </div>
                </li>
              ))}
            </ul>

            <CardBody className="border-t border-line">
              <dl className="ml-auto max-w-xs space-y-1.5 text-sm">
                <div className="flex justify-between gap-6">
                  <dt className="text-graphite-500">Subtotal</dt>
                  <dd className="tnum">{formatCents(order.subtotal_cents)}</dd>
                </div>
                {order.discount_percent > 0 && (
                  <div className="flex justify-between gap-6">
                    <dt className="text-graphite-500">Desconto</dt>
                    <dd className="tnum">{order.discount_percent}%</dd>
                  </div>
                )}
                {order.discount_amount_cents > 0 && (
                  <div className="flex justify-between gap-6">
                    <dt className="text-graphite-500">Desconto em valor</dt>
                    <dd className="tnum">− {formatCents(order.discount_amount_cents)}</dd>
                  </div>
                )}
                {order.shipping_amount_cents > 0 && (
                  <div className="flex justify-between gap-6">
                    <dt className="text-graphite-500">Frete</dt>
                    <dd className="tnum">{formatCents(order.shipping_amount_cents)}</dd>
                  </div>
                )}
                <div className="flex justify-between gap-6 border-t border-line pt-1.5 text-base font-medium">
                  <dt>Total</dt>
                  <dd className="tnum">{formatCents(order.total_cents)}</dd>
                </div>
              </dl>
            </CardBody>
          </Card>

          {(order.notes || order.payment_terms || order.delivery_terms) && (
            <Card>
              <CardHeader>
                <CardTitle>Condições</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3 text-sm">
                {order.payment_terms && (
                  <p>
                    <span className="text-graphite-500">Pagamento: </span>
                    {order.payment_terms}
                  </p>
                )}
                {order.delivery_terms && (
                  <p>
                    <span className="text-graphite-500">Entrega: </span>
                    {order.delivery_terms}
                  </p>
                )}
                {order.notes && <p className="whitespace-pre-wrap">{order.notes}</p>}
              </CardBody>
            </Card>
          )}
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
              <Badge tone={ORDER_STATUS_TONE[order.status]}>{ORDER_STATUS_LABELS[order.status]}</Badge>
            </CardHeader>
            <CardBody className="space-y-3">
              <dl className="space-y-1.5 text-sm">
                <div className="flex justify-between gap-4">
                  <dt className="text-graphite-500">Emissão</dt>
                  <dd className="tnum">{formatDate(order.issue_date)}</dd>
                </div>
                <div className="flex justify-between gap-4">
                  <dt className="text-graphite-500">Previsão de entrega</dt>
                  <dd className="tnum">{formatDate(order.delivery_forecast) || "—"}</dd>
                </div>
                <div className="flex justify-between gap-4">
                  <dt className="text-graphite-500">Vendedor</dt>
                  {/* `full_name` vazio não é nulo: sem o trim a linha sairia
                      em branco, como saiu na homologação. */}
                  <dd>{order.owner_name?.trim() || "—"}</dd>
                </div>
              </dl>

              {proximos.length > 0 && podeMover && (
                <div className="space-y-2 border-t border-line pt-3">
                  {/* Só o primeiro passo do caminho normal é primário. Dois
                      botões vermelhos lado a lado não dizem qual é o próximo
                      passo — e "Faturado" é o mais consequente dos dois. */}
                  {proximos.map((status, indice) => (
                    <form key={status} action={changeStatusAction}>
                      <input type="hidden" name="id" value={order.id} />
                      <input type="hidden" name="status" value={status} />
                      <Button
                        type="submit"
                        variant={indice === 0 && status !== "cancelled" ? "primary" : "secondary"}
                        fullWidth
                      >
                        Marcar como {ORDER_STATUS_LABELS[status]}
                      </Button>
                    </form>
                  ))}
                </div>
              )}

              {encerrado && (
                <p className="border-t border-line pt-3 text-xs text-graphite-300">
                  Este pedido está encerrado e não muda mais de situação.
                </p>
              )}
            </CardBody>
          </Card>

          <SerialsCard
            orderId={order.id}
            status={order.status}
            items={order.items}
            podeGerenciar={can(user.profile.role, "stock.manage")}
          />

          <Card>
            <CardHeader>
              <CardTitle>Origem</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3 text-sm">
              {order.quote_number && order.quote_id ? (
                <p>
                  <span className="text-graphite-500">Orçamento </span>
                  <Link href={`/orcamentos/${order.quote_id}`} className="tnum font-medium hover:text-brand">
                    {order.quote_number}
                  </Link>
                </p>
              ) : (
                <p className="text-graphite-300">
                  O orçamento de origem não está mais disponível. O pedido continua válido.
                </p>
              )}

              {order.supersedes_order_id && (
                <p>
                  <span className="text-graphite-500">Substitui o pedido </span>
                  <Link
                    href={`/pedidos/${order.supersedes_order_id}`}
                    className="font-medium hover:text-brand"
                  >
                    anterior
                  </Link>
                </p>
              )}

              {podeMover && (
                <form action={renegotiateAction} className="border-t border-line pt-3">
                  <input type="hidden" name="id" value={order.id} />
                  <ConfirmButton
                    label="Renegociar"
                    confirmLabel="Sim, gerar orçamento"
                    question="Cria um orçamento novo em rascunho com os mesmos itens. Este pedido não é alterado nem cancelado."
                  />
                </form>
              )}
            </CardBody>
          </Card>

          <Button asChild variant="secondary" fullWidth>
            <Link href="/orcamentos?status=approved">
              <FileText className="size-4" aria-hidden />
              Orçamentos aprovados
            </Link>
          </Button>
        </div>
      </div>
    </>
  );
}
