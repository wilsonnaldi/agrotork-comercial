import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Boxes, Download, Link2, Lock, Package, Pencil } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate, formatDocument } from "@/lib/format";
import { getQuoteWithItems, quoteIsEditable } from "@/modules/quotes/service";
import { STATUS_TRANSITIONS } from "@/modules/quotes/types";
import { changeStatusAction, deleteDraftAction } from "@/modules/quotes/actions";
import { createOrderFromQuoteAction } from "@/modules/orders/actions";
import { orderForQuote } from "@/modules/orders/service";
import { listLinks } from "@/modules/quotes/share/service";
import {
  createShareLinkAction,
  currentBaseUrl,
  revokeShareLinkAction,
} from "@/modules/quotes/share/actions";
import { ShareActions } from "../share-panel";
import type { KitComponentSnapshot, QuoteItemView } from "@/modules/quotes/types";

export const metadata: Metadata = { title: "Orçamento" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

/** Composição congelada do kit, como saiu no dia. */
function Components({ item }: { item: QuoteItemView }) {
  if (!item.components) return null;
  const incluidos = item.components.filter((component) => component.selected);
  const fora = item.components.filter((component) => !component.selected);

  const linha = (component: KitComponentSnapshot, incluso: boolean) => (
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
        {formatQuantity(Math.round((component.quantity_milli * item.quantity_milli) / 1000))}{" "}
        {component.unit ?? ""}
      </span>
    </li>
  );

  return (
    <div className="mt-2 ml-7 border-l border-line pl-3 text-xs">
      <ul>{incluidos.map((component) => linha(component, true))}</ul>
      {fora.length > 0 && (
        <>
          <p className="mt-1.5 text-graphite-300">Opcionais não incluídos:</p>
          <ul>{fora.map((component) => linha(component, false))}</ul>
        </>
      )}
    </div>
  );
}

export default async function QuotePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("quotes.readOwn");

  const { id } = await params;
  const quote = await getQuoteWithItems(id);
  if (!quote) notFound();

  const query = await searchParams;
  const links = await listLinks(quote.id, await currentBaseUrl());
  const linkAtivo = links.find((link) => link.is_active) ?? null;
  const isOwner = quote.owner_id === user.id;
  const isAdmin = user.profile.role === "admin";
  const podeMudarStatus = isAdmin || isOwner;

  // O pedido vivo deste orçamento decide duas coisas: o que o cartão
  // PEDIDO mostra (botão de gerar, ou link para o que já existe) e se
  // este orçamento ainda é um documento de trabalho.
  const pedido = await orderForQuote(quote.id);

  // Orçamento que virou pedido é HISTÓRICO, não rascunho: alterá-lo
  // faria o pedido apontar para uma origem que não diz mais o que foi
  // vendido. O banco recusa desde a migration 20260903080000; aqui a
  // tela para de oferecer o caminho, para o botão não existir só para
  // devolver erro.
  const editable = quoteIsEditable(quote, user.profile.role, user.id) && !pedido;

  const proximos =
    podeMudarStatus && !pedido
      ? STATUS_TRANSITIONS[quote.status].filter(
          (status) => isAdmin || quote.status !== "approved" || status === quote.status,
        )
      : [];

  const erro = typeof query.erro === "string" ? query.erro : null;

  return (
    <>
      <Link
        href="/orcamentos"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Orçamentos
      </Link>

      <PageHeader
        title={quote.number}
        description={`${quote.customer_name} · emitido em ${formatDate(quote.issue_date)}`}
        action={
          <div className="hidden gap-2 sm:flex">
            <Button asChild variant="secondary" size="lg">
              {/* Route Handler, não Server Action: o retorno é um arquivo. */}
              <a href={`/api/orcamentos/${quote.id}/pdf`}>
                <Download className="size-4" aria-hidden />
                Baixar PDF
              </a>
            </Button>
            {editable && (
              <Button asChild size="lg">
                <Link href={`/orcamentos/${quote.id}/editar`}>
                  <Pencil className="size-4" aria-hidden />
                  Editar
                </Link>
              </Button>
            )}
          </div>
        }
      />

      {erro && (
        <Alert tone="error" className="mb-4">
          {erro}
        </Alert>
      )}
      {typeof query.status === "string" && (
        <Alert tone="success" className="mb-4">
          Situação atualizada para <strong>{QUOTE_STATUS_LABELS[quote.status]}</strong>.
        </Alert>
      )}
      {typeof query.salvo === "string" && (
        <Alert tone="success" className="mb-4">
          Alterações salvas.
        </Alert>
      )}
      {typeof query.link === "string" && (
        <Alert tone="success" className="mb-4">
          Link público gerado. Qualquer pessoa com o endereço vê a proposta — sem custo, sem
          observações internas.
        </Alert>
      )}
      {typeof query.revogado === "string" && (
        <Alert tone="success" className="mb-4">
          Link revogado. O endereço antigo deixou de funcionar imediatamente.
        </Alert>
      )}
      {typeof query.bloqueado === "string" && (
        <Alert tone="warning" className="mb-4">
          {/* Três motivos diferentes, três saídas diferentes. Dizer
              "um administrador precisa reabri-lo" para um orçamento que
              virou pedido mandaria a pessoa pedir algo que ninguém pode
              fazer. */}
          {query.bloqueado === "pedido"
            ? `Este orçamento virou o pedido ${pedido?.number ?? ""} e não pode mais ser editado. Para mudar o que foi vendido, use Renegociar na ficha do pedido.`
            : quote.status === "approved"
              ? "Orçamento aprovado não pode ser editado. Um administrador precisa reabri-lo."
              : "Orçamento cancelado não pode ser editado. Reabra-o para voltar a mexer."}
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="min-w-0 space-y-5 lg:col-span-2">
          <Card className="overflow-hidden">
            <CardHeader className="flex items-center justify-between gap-3">
              <CardTitle>Itens</CardTitle>
              <span className="text-xs text-graphite-300">{quote.items.length} linha(s)</span>
            </CardHeader>

            {quote.items.length === 0 ? (
              <p className="px-4 py-4 text-sm text-graphite-300 lg:px-5">
                Este orçamento ainda não tem itens.
              </p>
            ) : (
              <ul className="divide-y divide-line">
                {quote.items.map((item) => (
                  <li key={item.id} className="px-4 py-3 lg:px-5">
                    <div className="flex items-start gap-3">
                      <span className="mt-0.5 shrink-0" aria-hidden>
                        {item.kind === "kit" ? (
                          <Boxes className="size-4 text-brand" />
                        ) : (
                          <Package className="size-4 text-graphite-300" />
                        )}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="font-medium">{item.name_snapshot}</p>
                        <p className="mt-0.5 text-xs text-graphite-300">
                          {item.code_snapshot && <span className="tnum">{item.code_snapshot}</span>}
                          {item.brand_snapshot && ` · ${item.brand_snapshot}`}
                          {` · ${formatQuantity(item.quantity_milli)} ${item.unit_snapshot ?? ""} × ${formatCents(item.unit_price_cents)}`}
                          {item.discount_percent > 0 &&
                            ` · desconto ${String(item.discount_percent).replace(".", ",")}%`}
                        </p>
                      </div>
                      <span className="shrink-0 text-right tnum text-sm font-medium">
                        {formatCents(item.line_total_cents)}
                      </span>
                    </div>
                    <Components item={item} />
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {(quote.payment_terms || quote.delivery_terms || quote.notes) && (
            <Card>
              <CardHeader>
                <CardTitle>Condições comerciais</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3 text-sm">
                {quote.payment_terms && (
                  <p>
                    <span className="text-graphite-500">Pagamento: </span>
                    {quote.payment_terms}
                  </p>
                )}
                {quote.delivery_terms && (
                  <p>
                    <span className="text-graphite-500">Entrega: </span>
                    {quote.delivery_terms}
                  </p>
                )}
                {quote.notes && <p className="whitespace-pre-line text-graphite-500">{quote.notes}</p>}
              </CardBody>
            </Card>
          )}

          {quote.internal_notes && (isAdmin || isOwner) && (
            <Card>
              <CardHeader>
                <CardTitle>Observações internas</CardTitle>
              </CardHeader>
              <CardBody>
                <p className="whitespace-pre-line text-sm text-graphite-500">{quote.internal_notes}</p>
                <p className="mt-2 text-xs text-graphite-300">Não sai no documento do cliente.</p>
              </CardBody>
            </Card>
          )}

          <Alert tone="info">
            Este orçamento guarda <strong>cópias congeladas</strong> de tudo o que foi vendido — código,
            nome, unidade, preço e a composição de cada kit. Mudanças posteriores no catálogo não o
            alteram.
          </Alert>
        </div>

        <aside className="min-w-0 space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Totais</CardTitle>
            </CardHeader>
            <CardBody className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-graphite-500">Subtotal</span>
                <span className="tnum font-medium">{formatCents(quote.subtotal_cents)}</span>
              </div>
              {quote.discount_percent > 0 && (
                <div className="flex justify-between text-graphite-500">
                  <span>Desconto {String(quote.discount_percent).replace(".", ",")}%</span>
                  <span className="tnum">
                    −{formatCents(Math.round((quote.subtotal_cents * quote.discount_percent) / 100))}
                  </span>
                </div>
              )}
              {quote.discount_amount_cents > 0 && (
                <div className="flex justify-between text-graphite-500">
                  <span>Desconto em valor</span>
                  <span className="tnum">−{formatCents(quote.discount_amount_cents)}</span>
                </div>
              )}
              {quote.shipping_amount_cents > 0 && (
                <div className="flex justify-between text-graphite-500">
                  <span>Frete</span>
                  <span className="tnum">+{formatCents(quote.shipping_amount_cents)}</span>
                </div>
              )}
              <div className="flex justify-between border-t border-line pt-2 text-base font-medium">
                <span>Total</span>
                <span className="tnum">{formatCents(quote.total_cents)}</span>
              </div>
            </CardBody>
          </Card>

          {(quote.status === "approved" || pedido) && (
            <Card>
              <CardHeader>
                <CardTitle>Pedido</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3 text-sm">
                {pedido ? (
                  <>
                    <p>
                      <span className="text-graphite-500">Este orçamento virou o pedido </span>
                      <Link href={`/pedidos/${pedido.id}`} className="tnum font-medium hover:text-brand">
                        {pedido.number}
                      </Link>
                    </p>
                    <Button asChild variant="secondary" fullWidth>
                      <Link href={`/pedidos/${pedido.id}`}>Abrir pedido</Link>
                    </Button>
                  </>
                ) : (
                  <>
                    <p className="text-graphite-500">
                      Gerar o pedido copia os itens e <strong>congela</strong> preço e composição. Para
                      mudar o que foi vendido depois, o caminho é renegociar.
                    </p>
                    <form action={createOrderFromQuoteAction}>
                      <input type="hidden" name="quote_id" value={quote.id} />
                      <Button type="submit" fullWidth>
                        Gerar pedido
                      </Button>
                    </form>
                  </>
                )}
              </CardBody>
            </Card>
          )}

          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={QUOTE_STATUS_TONE[quote.status]}>{QUOTE_STATUS_LABELS[quote.status]}</Badge>

              <dl className="space-y-1 text-sm">
                <div className="flex justify-between">
                  <dt className="text-graphite-500">Vendedor</dt>
                  <dd>{quote.owner_name}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-graphite-500">Validade</dt>
                  <dd className="tnum">{formatDate(quote.valid_until)}</dd>
                </div>
                {quote.customer_document && (
                  <div className="flex justify-between">
                    <dt className="text-graphite-500">Documento</dt>
                    <dd className="tnum">{formatDocument(quote.customer_document)}</dd>
                  </div>
                )}
              </dl>

              {proximos.length > 0 && (
                <div className="space-y-2 border-t border-line pt-3">
                  {proximos.map((status) => (
                    <form key={status} action={changeStatusAction}>
                      <input type="hidden" name="id" value={quote.id} />
                      <input type="hidden" name="status" value={status} />
                      <Button
                        type="submit"
                        variant={status === "approved" ? "primary" : "secondary"}
                        fullWidth
                      >
                        Marcar como {QUOTE_STATUS_LABELS[status]}
                      </Button>
                    </form>
                  ))}
                </div>
              )}

              {pedido && (
                <p className="border-t border-line pt-3 text-xs text-graphite-300">
                  Este orçamento virou o pedido {pedido.number} e não muda mais. Para alterar o
                  que foi vendido, use <strong>Renegociar</strong> na ficha do pedido.
                </p>
              )}

              {quote.status === "draft" && podeMudarStatus && (
                <form action={deleteDraftAction} className="border-t border-line pt-3">
                  <input type="hidden" name="id" value={quote.id} />
                  <ConfirmButton
                    label="Descartar rascunho"
                    confirmLabel="Sim, descartar"
                    question="O rascunho sai da lista. O número já usado não volta a ser emitido."
                  />
                </form>
              )}
            </CardBody>
          </Card>

          {/* ── Compartilhamento ───────────────────────── */}
          <Card>
            <CardHeader>
              <CardTitle>
                <span className="inline-flex items-center gap-2">
                  <Link2 className="size-4 text-brand" aria-hidden />
                  Link público
                </span>
              </CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              {linkAtivo ? (
                <>
                  <ShareActions link={linkAtivo} quoteNumber={quote.number} />
                  <form action={revokeShareLinkAction} className="border-t border-line pt-3">
                    <input type="hidden" name="quote_id" value={quote.id} />
                    <input type="hidden" name="token_id" value={linkAtivo.id} />
                    <ConfirmButton
                      label="Revogar link"
                      confirmLabel="Sim, revogar"
                      question="O endereço atual deixa de abrir na hora. O orçamento continua intacto e um link novo pode ser gerado."
                    />
                  </form>
                </>
              ) : (
                <>
                  <p className="text-sm text-graphite-500">
                    Gere um endereço para o cliente ver a proposta sem precisar de login.
                  </p>
                  {quote.status === "draft" && (
                    <p className="text-xs text-graphite-300">
                      Este orçamento é um rascunho: ao gerar o link ele passa a <strong>enviado</strong>.
                    </p>
                  )}
                  <form action={createShareLinkAction}>
                    <input type="hidden" name="quote_id" value={quote.id} />
                    <Button type="submit" fullWidth>
                      <Link2 className="size-4" aria-hidden />
                      Gerar link público
                    </Button>
                  </form>
                </>
              )}

              {links.length > 0 && (
                <div className="border-t border-line pt-3">
                  <p className="mb-1.5 text-xs font-medium tracking-wide text-graphite-500 uppercase">
                    Histórico
                  </p>
                  <ul className="space-y-1 text-xs text-graphite-300">
                    {links.map((link) => (
                      <li key={link.id} className="flex justify-between gap-2">
                        <span className="tnum">{formatDate(link.created_at)}</span>
                        <span>
                          {link.revoked_at
                            ? "revogado"
                            : link.is_expired
                              ? "expirado"
                              : `ativo · ${link.view_count} acesso(s)`}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <p className="border-t border-line pt-3 text-xs text-graphite-300">
                O link mostra a mesma proposta do PDF — <strong>sem custo, sem margem e sem
                observações internas</strong>. Revogar não apaga nada do orçamento.
              </p>
            </CardBody>
          </Card>

          <div className="flex flex-col gap-2">
            <Button asChild variant="secondary" fullWidth>
              <a href={`/api/orcamentos/${quote.id}/pdf`}>
                <Download className="size-4" aria-hidden />
                Baixar PDF
              </a>
            </Button>
            {editable && (
              <Button asChild variant="secondary" fullWidth>
                <Link href={`/orcamentos/${quote.id}/editar`}>Editar itens</Link>
              </Button>
            )}
          </div>
        </aside>
      </div>
    </>
  );
}
