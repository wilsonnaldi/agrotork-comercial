import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ArrowLeft, Boxes, Package, Search } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SearchInput } from "@/components/ui/search-input";
import { requirePermission } from "@/lib/auth/session";
import { formatCents } from "@/lib/format/money";
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { catalogSearchSchema } from "@/modules/quotes/schema";
import {
  getCustomerOptions,
  getKitConfiguration,
  getQuoteWithItems,
  quoteIsEditable,
  searchProducts,
  searchUsableKits,
} from "@/modules/quotes/service";
import {
  addKitAction,
  addProductAction,
  itemRowAction,
  updateCommercialAction,
  updateKitOptionalsAction,
  updateQuoteHeaderAction,
} from "@/modules/quotes/actions";
import { QuoteHeaderForm } from "../../quote-header-form";
import {
  AddProductRow,
  CommercialForm,
  ItemRow,
  KitComposition,
  KitOptionalsForm,
} from "../../quote-editor";

export const metadata: Metadata = { title: "Editar orçamento" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function EditQuotePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("quotes.write");

  const { id } = await params;
  const quote = await getQuoteWithItems(id);
  if (!quote) notFound();

  const editable = quoteIsEditable(quote, user.profile.role, user.id);
  // Orçamento travado não tem tela de edição: a ficha já mostra tudo.
  if (!editable) redirect(`/orcamentos/${quote.id}?bloqueado=1`);

  const query = await searchParams;
  const busca = catalogSearchSchema.parse({ q: pick(query.q), aba: pick(query.aba) });

  // Painel de opcionais: `kit` para adicionar um kit novo, `item` para
  // mexer nos opcionais de um kit que já está no orçamento.
  const kitParaAdicionar = pick(query.kit);
  const itemParaAjustar = pick(query.item);

  const [customers, produtos, kitsDisponiveis, configuracao] = await Promise.all([
    getCustomerOptions(),
    busca.aba === "produtos" && busca.q && !kitParaAdicionar && !itemParaAjustar
      ? searchProducts(busca)
      : Promise.resolve([]),
    busca.aba === "kits" && !kitParaAdicionar && !itemParaAjustar
      ? searchUsableKits(busca)
      : Promise.resolve([]),
    kitParaAdicionar ? getKitConfiguration(kitParaAdicionar) : Promise.resolve(null),
  ]);

  const itemAjustado = itemParaAjustar
    ? (quote.items.find((item) => item.id === itemParaAjustar) ?? null)
    : null;

  const abaHref = (aba: "produtos" | "kits") => {
    const next = new URLSearchParams();
    next.set("aba", aba);
    if (busca.q) next.set("q", busca.q);
    return `/orcamentos/${quote.id}/editar?${next.toString()}`;
  };

  const voltarParaBusca = `/orcamentos/${quote.id}/editar?aba=kits${busca.q ? `&q=${encodeURIComponent(busca.q)}` : ""}`;

  return (
    <>
      <Link
        href={`/orcamentos/${quote.id}`}
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        {quote.number}
      </Link>

      <PageHeader
        title="Montar orçamento"
        description={`${quote.number} · ${quote.customer_name}`}
        action={
          <Badge tone={QUOTE_STATUS_TONE[quote.status]}>{QUOTE_STATUS_LABELS[quote.status]}</Badge>
        }
      />

      {typeof query.criado === "string" && (
        <Alert tone="success" className="mb-4 max-w-4xl">
          Orçamento <strong>{quote.number}</strong> criado. Agora adicione produtos e kits.
        </Alert>
      )}
      {typeof query.kit_adicionado === "string" && (
        <Alert tone="success" className="mb-4 max-w-4xl">
          Kit adicionado com os opcionais escolhidos.
        </Alert>
      )}
      {typeof query.opcionais === "string" && (
        <Alert tone="success" className="mb-4 max-w-4xl">
          Opcionais atualizados. O preço do kit foi recalculado no servidor.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="min-w-0 space-y-5 lg:col-span-2">
          {/* ── Itens ─────────────────────────────────────── */}
          <Card className="overflow-hidden">
            <CardHeader className="flex items-center justify-between gap-3">
              <CardTitle>Itens</CardTitle>
              <span className="text-xs text-graphite-300">{quote.items.length} linha(s)</span>
            </CardHeader>

            {quote.items.length === 0 ? (
              <p className="px-4 py-4 text-sm text-graphite-300 lg:px-5">
                Nenhum item ainda. Use a busca abaixo para adicionar produtos e kits.
              </p>
            ) : (
              <ul className="divide-y divide-line">
                {quote.items.map((item) => (
                  <ItemRow key={item.id} action={itemRowAction} quoteId={quote.id} item={item} editable>
                    {item.kind === "kit" && item.components && (
                      <>
                        <KitComposition
                          components={item.components}
                          kitQuantityMilli={item.quantity_milli}
                        />
                        {item.components.some((component) => component.item_type === "optional") && (
                          <Link
                            href={`/orcamentos/${quote.id}/editar?item=${item.id}`}
                            className="mt-1.5 ml-7 inline-block text-xs text-brand hover:underline"
                          >
                            Ajustar opcionais deste kit
                          </Link>
                        )}
                      </>
                    )}
                  </ItemRow>
                ))}
              </ul>
            )}
          </Card>

          {/* ── Painel de opcionais ───────────────────────── */}
          {configuracao && (
            <Card>
              <CardHeader>
                <CardTitle>
                  {configuracao.kit.code} · {configuracao.kit.name}
                </CardTitle>
              </CardHeader>
              <CardBody className="space-y-4">
                <Alert tone="info">
                  Marcar aqui significa <strong>incluir este componente nesta venda</strong>. Não altera o
                  cadastro do kit.
                </Alert>
                <KitOptionalsForm
                  action={addKitAction}
                  quoteId={quote.id}
                  kitId={configuracao.kit.id}
                  required={configuracao.required}
                  optional={configuracao.optional}
                  quantityMilli={1000}
                  submitLabel="Adicionar kit ao orçamento"
                />
                <Button asChild variant="secondary" fullWidth>
                  <Link href={voltarParaBusca}>Voltar para a busca</Link>
                </Button>
              </CardBody>
            </Card>
          )}

          {itemAjustado?.components && (
            <Card>
              <CardHeader>
                <CardTitle>Opcionais de {itemAjustado.name_snapshot}</CardTitle>
              </CardHeader>
              <CardBody className="space-y-4">
                <Alert tone="info">
                  Os componentes e os preços são os <strong>congelados</strong> quando o kit entrou. Mudar
                  de ideia sobre um opcional não repreça a proposta.
                </Alert>
                <KitOptionalsForm
                  action={updateKitOptionalsAction}
                  quoteId={quote.id}
                  itemId={itemAjustado.id}
                  required={itemAjustado.components.filter((c) => c.item_type === "required")}
                  optional={itemAjustado.components.filter((c) => c.item_type === "optional")}
                  quantityMilli={itemAjustado.quantity_milli}
                  submitLabel="Salvar opcionais"
                />
                <Button asChild variant="secondary" fullWidth>
                  <Link href={`/orcamentos/${quote.id}/editar`}>Cancelar</Link>
                </Button>
              </CardBody>
            </Card>
          )}

          {/* ── Adicionar item ────────────────────────────── */}
          {!configuracao && !itemAjustado && (
            <Card className="overflow-hidden">
              <CardHeader>
                <CardTitle>Adicionar ao orçamento</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3">
                <div className="flex gap-2">
                  <Button asChild variant={busca.aba === "produtos" ? "primary" : "secondary"}>
                    <Link href={abaHref("produtos")}>
                      <Package className="size-4" aria-hidden />
                      Produtos
                    </Link>
                  </Button>
                  <Button asChild variant={busca.aba === "kits" ? "primary" : "secondary"}>
                    <Link href={abaHref("kits")}>
                      <Boxes className="size-4" aria-hidden />
                      Kits
                    </Link>
                  </Button>
                </div>

                <SearchInput
                  placeholder={
                    busca.aba === "produtos"
                      ? "Buscar produto por código, nome ou descrição…"
                      : "Buscar kit por código ou nome…"
                  }
                />

                {busca.aba === "produtos" ? (
                  <p className="text-xs text-graphite-300">
                    Só produtos <strong>ativos</strong> entram em orçamento novo.
                  </p>
                ) : (
                  <p className="text-xs text-graphite-300">
                    Só kits <strong>utilizáveis</strong>: ativos e com ao menos um item obrigatório.
                  </p>
                )}
              </CardBody>

              {busca.aba === "produtos" && (
                <>
                  {busca.q && produtos.length === 0 && (
                    <p className="px-4 pb-4 text-sm text-graphite-300 lg:px-5">
                      Nenhum produto ativo encontrado para “{busca.q}”.
                    </p>
                  )}
                  {produtos.length > 0 && (
                    <ul className="divide-y divide-line border-t border-line">
                      {produtos.map((candidate) => (
                        <AddProductRow
                          key={candidate.id}
                          action={addProductAction}
                          quoteId={quote.id}
                          candidate={candidate}
                        />
                      ))}
                    </ul>
                  )}
                </>
              )}

              {busca.aba === "kits" && (
                <>
                  {kitsDisponiveis.length === 0 ? (
                    <p className="px-4 pb-4 text-sm text-graphite-300 lg:px-5">
                      {busca.q
                        ? `Nenhum kit utilizável encontrado para “${busca.q}”.`
                        : "Nenhum kit utilizável cadastrado."}
                    </p>
                  ) : (
                    <ul className="divide-y divide-line border-t border-line">
                      {kitsDisponiveis.map((kit) => (
                        <li key={kit.id} className="px-4 py-3 lg:px-5">
                          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                            <div className="min-w-0 flex-1">
                              <p className="truncate font-medium">{kit.name}</p>
                              <p className="mt-0.5 truncate text-xs text-graphite-300">
                                <span className="tnum">{kit.code}</span>
                                {` · ${kit.required_count} obrigatório(s)`}
                                {kit.optional_count > 0 && ` · ${kit.optional_count} opcional(is)`}
                                {` · base ${formatCents(kit.base_price_cents)}`}
                              </p>
                            </div>
                            <Button asChild>
                              <Link href={`/orcamentos/${quote.id}/editar?kit=${kit.id}`}>
                                {kit.optional_count > 0 ? "Escolher opcionais" : "Adicionar"}
                              </Link>
                            </Button>
                          </div>
                        </li>
                      ))}
                    </ul>
                  )}
                </>
              )}

              {busca.aba === "produtos" && !busca.q && (
                <p className="flex items-center gap-2 px-4 pb-4 text-sm text-graphite-300 lg:px-5">
                  <Search className="size-4" aria-hidden />
                  Digite acima para encontrar o produto.
                </p>
              )}
            </Card>
          )}

          {/* ── Cabeçalho ─────────────────────────────────── */}
          <Card>
            <CardHeader>
              <CardTitle>Cliente e condições</CardTitle>
            </CardHeader>
            <CardBody>
              <QuoteHeaderForm
                action={updateQuoteHeaderAction}
                submitLabel="Salvar cabeçalho"
                customers={customers}
                cancelHref={`/orcamentos/${quote.id}`}
                compact
                quote={{
                  id: quote.id,
                  customer_id: quote.customer_id,
                  issue_date: quote.issue_date,
                  valid_until: quote.valid_until,
                  payment_terms: quote.payment_terms,
                  delivery_terms: quote.delivery_terms,
                  notes: quote.notes,
                  internal_notes: quote.internal_notes,
                }}
              />
            </CardBody>
          </Card>
        </div>

        {/* ── Totais e desconto ───────────────────────────── */}
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
              <p className="text-xs text-graphite-300">
                Subtotal e total são calculados pelo banco a cada alteração. A tela apenas mostra o
                resultado — nenhum total vem do navegador.
              </p>
            </CardBody>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Desconto e frete</CardTitle>
            </CardHeader>
            <CardBody>
              <CommercialForm
                action={updateCommercialAction}
                quoteId={quote.id}
                discountPercent={quote.discount_percent}
                discountAmountCents={quote.discount_amount_cents}
                shippingAmountCents={quote.shipping_amount_cents}
              />
            </CardBody>
          </Card>

          <Button asChild variant="secondary" fullWidth>
            <Link href={`/orcamentos/${quote.id}`}>Ver orçamento</Link>
          </Button>
        </aside>
      </div>
    </>
  );
}
