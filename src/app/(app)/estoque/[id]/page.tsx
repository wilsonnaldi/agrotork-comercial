import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Package, ScanLine } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { EmptyState } from "@/components/ui/empty-state";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { getMovements, getProductStock, getSerials } from "@/modules/stock/service";
import { createSerialAction, registerMovementAction } from "@/modules/stock/actions";
import { MANUAL_REASONS } from "@/modules/stock/types";
import { SERIAL_STATUS_LABELS, SERIAL_STATUS_TONE, STOCK_REASON_LABELS } from "@/config/labels";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "Estoque do produto" };

type SearchParams = Promise<{ lancado?: string; serie?: string; erro?: string }>;

const toMilli = (quantity: number) => Math.round(quantity * 1000);

export default async function ProductStockPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("stock.read");
  const podeLancar = can(user.profile.role, "stock.manage");

  const [{ id }, flags] = await Promise.all([params, searchParams]);
  const stock = await getProductStock(id);
  if (!stock) notFound();

  const [movements, serials] = await Promise.all([
    getMovements(id),
    stock.tracks_serial ? getSerials(id) : Promise.resolve([]),
  ]);

  const saldo = toMilli(stock.quantity);
  const disponiveis = serials.filter((s) => s.status === "in_stock").length;

  return (
    <>
      <Link
        href="/estoque"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Estoque
      </Link>

      <PageHeader
        title={stock.name}
        description={stock.code}
        action={
          <Button asChild variant="secondary">
            <Link href={`/produtos/${stock.product_id}`}>
              <Package className="size-4" aria-hidden />
              Ver produto
            </Link>
          </Button>
        }
      />

      {flags.lancado && <Alert tone="success" className="mb-4">Movimento lançado.</Alert>}
      {flags.serie && <Alert tone="success" className="mb-4">Aparelho cadastrado.</Alert>}
      {flags.erro && <Alert tone="warning" className="mb-4">{flags.erro}</Alert>}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          {/* ── O livro ─────────────────────────────────────── */}
          <Card className="overflow-hidden">
            <CardHeader>
              <CardTitle>Lançamentos</CardTitle>
              <span className="text-xs text-graphite-300">
                {movements.length === 1 ? "1 lançamento" : `${movements.length} lançamentos`}
              </span>
            </CardHeader>

            {movements.length === 0 ? (
              <EmptyState
                icon={Package}
                title="Nenhum lançamento ainda"
                description={
                  podeLancar
                    ? "Comece pela contagem inicial: o saldo que já está no galpão hoje."
                    : "Este produto ainda não teve entrada nem saída registrada."
                }
              />
            ) : (
              <ul className="divide-y divide-line">
                {movements.map((m) => {
                  const milli = toMilli(m.quantity);
                  return (
                    <li key={m.id} className="flex items-start justify-between gap-3 px-4 py-3 sm:px-5">
                      <div className="min-w-0">
                        <p className="text-sm font-medium">{STOCK_REASON_LABELS[m.reason]}</p>
                        <p className="mt-0.5 text-xs text-graphite-300">
                          {formatDateTime(m.created_at)}
                          {m.author_name?.trim() ? ` · ${m.author_name.trim()}` : ""}
                          {m.order_number && m.order_id ? " · " : ""}
                          {m.order_number && m.order_id && (
                            <Link href={`/pedidos/${m.order_id}`} className="hover:text-brand">
                              {m.order_number}
                            </Link>
                          )}
                        </p>
                        {m.notes && <p className="mt-1 text-xs text-graphite-500">{m.notes}</p>}
                      </div>
                      {/* O sinal aparece aqui, e o motivo ao lado: juntos
                          eles dizem "saiu 3 por venda" sem ambiguidade. */}
                      <span
                        className={
                          milli < 0
                            ? "shrink-0 tnum text-sm font-medium text-brand-deep"
                            : "shrink-0 tnum text-sm font-medium text-emerald-700"
                        }
                      >
                        {milli > 0 ? "+" : ""}
                        {formatQuantity(milli)}
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>

          {/* ── Aparelhos ───────────────────────────────────── */}
          {stock.tracks_serial && (
            <Card className="overflow-hidden">
              <CardHeader>
                <CardTitle>Aparelhos</CardTitle>
                <span className="text-xs text-graphite-300">
                  {disponiveis} de {serials.length} no galpão
                </span>
              </CardHeader>

              {serials.length === 0 ? (
                <EmptyState
                  icon={ScanLine}
                  title="Nenhum aparelho cadastrado"
                  description="Cadastre a série de cada aparelho para responder depois onde ele foi parar."
                />
              ) : (
                <ul className="divide-y divide-line">
                  {serials.map((s) => (
                    <li key={s.id} className="flex items-center justify-between gap-3 px-4 py-3 sm:px-5">
                      <div className="min-w-0">
                        <p className="truncate tnum text-sm font-medium">{s.serial}</p>
                        {s.order_number && s.order_id && (
                          <Link
                            href={`/pedidos/${s.order_id}`}
                            className="text-xs text-graphite-300 hover:text-brand"
                          >
                            {s.order_number}
                          </Link>
                        )}
                      </div>
                      <Badge tone={SERIAL_STATUS_TONE[s.status]}>
                        {SERIAL_STATUS_LABELS[s.status]}
                      </Badge>
                    </li>
                  ))}
                </ul>
              )}

              {podeLancar && (
                <CardBody className="border-t border-line">
                  <form action={createSerialAction} className="space-y-3">
                    <input type="hidden" name="product_id" value={stock.product_id} />
                    <Field label="Número de série" htmlFor="serial">
                      <Input
                        id="serial"
                        name="serial"
                        autoComplete="off"
                        autoCapitalize="characters"
                        placeholder="1ABC-7742"
                        required
                      />
                    </Field>
                    <Button type="submit" variant="secondary" fullWidth>
                      Cadastrar aparelho
                    </Button>
                  </form>
                </CardBody>
              )}
            </Card>
          )}
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Saldo</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <p
                className={
                  saldo < 0
                    ? "tnum text-3xl font-medium text-brand-deep"
                    : saldo === 0
                      ? "tnum text-3xl font-medium text-graphite-300"
                      : "tnum text-3xl font-medium"
                }
              >
                {formatQuantity(saldo)}
                {stock.unit_code && (
                  <span className="ml-1.5 text-base text-graphite-300">{stock.unit_code}</span>
                )}
              </p>

              {saldo < 0 && (
                <p className="text-xs text-graphite-500">
                  Saldo negativo quer dizer que saiu mais do que o sistema sabia que tinha — quase
                  sempre porque a entrada não foi lançada. Acerte com um <strong>ajuste de
                  contagem</strong>.
                </p>
              )}
              {saldo === 0 && movements.length === 0 && (
                <p className="text-xs text-graphite-500">
                  Zero aqui não quer dizer que acabou: quer dizer que ninguém contou ainda.
                </p>
              )}
            </CardBody>
          </Card>

          {podeLancar && (
            <Card>
              <CardHeader>
                <CardTitle>Lançar movimento</CardTitle>
              </CardHeader>
              <CardBody>
                <form action={registerMovementAction} className="space-y-3">
                  <input type="hidden" name="product_id" value={stock.product_id} />

                  <Field label="Motivo" htmlFor="reason">
                    <Select id="reason" name="reason" defaultValue="purchase">
                      {MANUAL_REASONS.map((reason) => (
                        <option key={reason} value={reason}>
                          {STOCK_REASON_LABELS[reason]}
                        </option>
                      ))}
                    </Select>
                  </Field>

                  <Field
                    label="Quantidade"
                    htmlFor="quantity"
                    hint="No ajuste de contagem, use o sinal: −2 tira, 2 acrescenta."
                  >
                    <Input
                      id="quantity"
                      name="quantity"
                      inputMode="text"
                      autoComplete="off"
                      placeholder="1"
                      required
                    />
                  </Field>

                  <Field label="Observação" htmlFor="notes" hint="Número da nota, quem contou…">
                    <Textarea id="notes" name="notes" rows={2} />
                  </Field>

                  <Button type="submit" fullWidth>
                    Lançar
                  </Button>

                  <p className="text-xs text-graphite-300">
                    Saída por venda não entra aqui: ela acontece sozinha quando o pedido é
                    faturado.
                  </p>
                </form>
              </CardBody>
            </Card>
          )}
        </div>
      </div>
    </>
  );
}
