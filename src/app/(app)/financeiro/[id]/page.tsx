import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, CalendarClock, Receipt } from "lucide-react";
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
import { getEntry, getPayments } from "@/modules/financial/service";
import {
  cancelEntryAction,
  registerPaymentAction,
  splitEntryAction,
} from "@/modules/financial/actions";
import {
  FINANCIAL_KIND_LABELS,
  FINANCIAL_STATUS_LABELS,
  FINANCIAL_STATUS_TONE,
} from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Título" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function EntryPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  await requirePermission("financial.manage");

  const [{ id }, query] = await Promise.all([params, searchParams]);
  const titulo = await getEntry(id);
  if (!titulo) notFound();

  const baixas = await getPayments(id);
  const recebendo = titulo.kind === "receivable";
  const emAberto = titulo.status === "open" || titulo.status === "partial";
  const podeParcelar = titulo.status === "open" && baixas.length === 0 && titulo.installments === 1;
  const hoje = new Date().toISOString().slice(0, 10);

  return (
    <>
      <Link
        href="/financeiro"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Financeiro
      </Link>

      <PageHeader
        title={titulo.party_name}
        description={`${FINANCIAL_KIND_LABELS[titulo.kind]} · ${titulo.description}${
          titulo.installments > 1 ? ` · parcela ${titulo.installment} de ${titulo.installments}` : ""
        }`}
      />

      {typeof query.baixa === "string" && (
        <Alert tone="success" className="mb-4">Baixa registrada.</Alert>
      )}
      {typeof query.cancelado === "string" && (
        <Alert tone="success" className="mb-4">Título cancelado.</Alert>
      )}
      {typeof query.erro === "string" && (
        <Alert tone="warning" className="mb-4">{query.erro}</Alert>
      )}
      {titulo.is_overdue && (
        <Alert tone="warning" className="mb-4">
          Vencido há {titulo.days_overdue === 1 ? "1 dia" : `${titulo.days_overdue} dias`}.
          Faltam {formatCents(titulo.open_cents)}.
        </Alert>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          {/* ── O livro das baixas ──────────────────────────── */}
          <Card className="overflow-hidden">
            <CardHeader>
              <CardTitle>Baixas</CardTitle>
              <span className="text-xs text-graphite-300">
                {baixas.length === 1 ? "1 lançamento" : `${baixas.length} lançamentos`}
              </span>
            </CardHeader>

            {baixas.length === 0 ? (
              <EmptyState
                icon={Receipt}
                title="Nada recebido ainda"
                description={
                  recebendo
                    ? "Quando o cliente pagar, registre aqui — parcial ou total."
                    : "Quando a AgroTork pagar o fornecedor, registre aqui."
                }
              />
            ) : (
              <ul className="divide-y divide-line">
                {baixas.map((baixa) => {
                  const estorno = baixa.amount_cents < 0;
                  return (
                    <li key={baixa.id} className="flex items-start justify-between gap-3 px-4 py-3 sm:px-5">
                      <div className="min-w-0">
                        <p className="text-sm font-medium">
                          {estorno ? "Estorno" : recebendo ? "Recebimento" : "Pagamento"}
                          {baixa.method && (
                            <span className="ml-1.5 font-normal text-graphite-500">
                              · {baixa.method}
                            </span>
                          )}
                        </p>
                        <p className="mt-0.5 text-xs text-graphite-300">
                          {formatDate(baixa.paid_on)}
                          {baixa.author_name?.trim() ? ` · ${baixa.author_name.trim()}` : ""}
                        </p>
                        {baixa.notes && (
                          <p className="mt-1 text-xs text-graphite-500">{baixa.notes}</p>
                        )}
                      </div>
                      <span
                        className={
                          estorno
                            ? "shrink-0 tnum text-sm font-medium text-brand-deep"
                            : "shrink-0 tnum text-sm font-medium text-emerald-700"
                        }
                      >
                        {estorno ? "" : "+"}
                        {formatCents(baixa.amount_cents)}
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}

            {emAberto && (
              <CardBody className="border-t border-line">
                <form action={registerPaymentAction} className="grid gap-3 sm:grid-cols-4">
                  <input type="hidden" name="entry_id" value={titulo.id} />

                  <Field
                    label="Valor"
                    htmlFor="amount"
                    hint={`Falta ${formatCents(titulo.open_cents)}. Negativo estorna.`}
                    className="sm:col-span-2"
                  >
                    <Input
                      id="amount"
                      name="amount"
                      inputMode="decimal"
                      autoComplete="off"
                      placeholder={(titulo.open_cents / 100).toFixed(2).replace(".", ",")}
                      required
                    />
                  </Field>

                  <Field label="Data" htmlFor="paid_on">
                    <Input id="paid_on" name="paid_on" type="date" defaultValue={hoje} required />
                  </Field>

                  <Field label="Forma" htmlFor="method">
                    <Select id="method" name="method" defaultValue="PIX">
                      <option value="PIX">PIX</option>
                      <option value="Boleto">Boleto</option>
                      <option value="Transferência">Transferência</option>
                      <option value="Dinheiro">Dinheiro</option>
                      <option value="Cartão">Cartão</option>
                      <option value="Cheque">Cheque</option>
                      <option value="">Outra</option>
                    </Select>
                  </Field>

                  <div className="sm:col-span-4">
                    <Button type="submit" fullWidth>
                      Registrar {recebendo ? "recebimento" : "pagamento"}
                    </Button>
                  </div>
                </form>
              </CardBody>
            )}
          </Card>

          {/* ── Parcelar ────────────────────────────────────── */}
          {podeParcelar && (
            <Card>
              <CardHeader>
                <CardTitle>Parcelar</CardTitle>
                <CalendarClock className="size-4 text-graphite-300" aria-hidden />
              </CardHeader>
              <CardBody className="space-y-3">
                <p className="text-sm text-graphite-500">
                  Troca este título por várias parcelas com vencimentos próprios. A soma fecha
                  exatamente com {formatCents(titulo.amount_cents)} — a sobra dos centavos vai
                  para a primeira.
                </p>

                <form action={splitEntryAction} className="grid gap-3 sm:grid-cols-4">
                  <input type="hidden" name="entry_id" value={titulo.id} />

                  <Field label="Parcelas" htmlFor="installments">
                    <Input
                      id="installments"
                      name="installments"
                      type="number"
                      min={2}
                      max={60}
                      defaultValue={3}
                      required
                    />
                  </Field>

                  <Field label="Primeiro vencimento" htmlFor="first_due" className="sm:col-span-2">
                    <Input
                      id="first_due"
                      name="first_due"
                      type="date"
                      defaultValue={titulo.due_date}
                      required
                    />
                  </Field>

                  <Field label="A cada (dias)" htmlFor="interval_days">
                    <Input
                      id="interval_days"
                      name="interval_days"
                      type="number"
                      min={1}
                      max={365}
                      defaultValue={30}
                      required
                    />
                  </Field>

                  <div className="sm:col-span-4">
                    <Button type="submit" variant="secondary" fullWidth>
                      Parcelar
                    </Button>
                  </div>
                </form>
              </CardBody>
            </Card>
          )}
        </div>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Título</CardTitle>
              <Badge tone={FINANCIAL_STATUS_TONE[titulo.status]}>
                {FINANCIAL_STATUS_LABELS[titulo.status]}
              </Badge>
            </CardHeader>
            <CardBody className="space-y-3">
              <div>
                <p className="text-xs text-graphite-300">
                  {emAberto ? (recebendo ? "Falta receber" : "Falta pagar") : "Valor do título"}
                </p>
                <p
                  className={
                    titulo.is_overdue
                      ? "tnum text-3xl font-medium text-brand-deep"
                      : "tnum text-3xl font-medium"
                  }
                >
                  {formatCents(emAberto ? titulo.open_cents : titulo.amount_cents)}
                </p>
              </div>

              <dl className="space-y-1.5 border-t border-line pt-3 text-sm">
                <Linha rotulo="Valor" valor={formatCents(titulo.amount_cents)} />
                {titulo.paid_cents !== 0 && (
                  <Linha rotulo="Já baixado" valor={formatCents(titulo.paid_cents)} />
                )}
                <Linha rotulo="Vencimento" valor={formatDate(titulo.due_date)} />
                {titulo.installments > 1 && (
                  <Linha
                    rotulo="Parcela"
                    valor={`${titulo.installment} de ${titulo.installments}`}
                  />
                )}
              </dl>

              {(titulo.order_id || titulo.purchase_id) && (
                <div className="border-t border-line pt-3 text-sm">
                  <p className="text-xs text-graphite-300">Origem</p>
                  {titulo.order_id && titulo.order_number && (
                    <Link
                      href={`/pedidos/${titulo.order_id}`}
                      className="tnum font-medium hover:text-brand"
                    >
                      {titulo.order_number}
                    </Link>
                  )}
                  {titulo.purchase_id && titulo.purchase_number && (
                    <Link
                      href={`/compras/${titulo.purchase_id}`}
                      className="tnum font-medium hover:text-brand"
                    >
                      {titulo.purchase_number}
                    </Link>
                  )}
                </div>
              )}

              {titulo.status === "open" && baixas.length === 0 && (
                <form action={cancelEntryAction} className="border-t border-line pt-3">
                  <input type="hidden" name="entry_id" value={titulo.id} />
                  <ConfirmButton
                    label="Cancelar título"
                    confirmLabel="Sim, cancelar"
                    question="O título deixa de contar no que há a receber. O pedido de origem não é alterado."
                  />
                </form>
              )}

              {titulo.status === "settled" && (
                <p className="border-t border-line pt-3 text-xs text-graphite-300">
                  Quitado. Para desfazer, lance um estorno — o valor negativo reabre o título e
                  deixa os dois lançamentos à vista.
                </p>
              )}
            </CardBody>
          </Card>
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
