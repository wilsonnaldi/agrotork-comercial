import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Download, Lock } from "lucide-react";

import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate } from "@/lib/format";
import { getSharedDocument } from "@/modules/quotes/share/service";
import {
  declinedComponents,
  includedComponents,
  type DocumentItem,
  type QuoteDocument,
} from "@/modules/quotes/share/document";

/**
 * Página pública do orçamento — sem login, só com o token.
 *
 * O que aparece aqui é exatamente o que `get_shared_quote` devolve: sem
 * custo, sem margem, sem observação interna, sem id de nada, e sem
 * telefone ou e-mail do cliente. O token pode ser repassado adiante, e a
 * página foi desenhada com isso em mente.
 */

export const metadata: Metadata = {
  title: "Orçamento",
  // Proposta comercial não entra em buscador.
  robots: { index: false, follow: false },
};

const percent = (value: number) => `${String(value).replace(".", ",")}%`;

function ItemLine({ item }: { item: DocumentItem }) {
  const incluidos = includedComponents(item);
  const recusados = declinedComponents(item);

  return (
    <li className="border-b border-line px-4 py-4 last:border-0 sm:px-6">
      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-1">
        <div className="min-w-0 flex-1">
          <p className="font-medium">{item.name}</p>
          <p className="mt-0.5 text-xs text-graphite-300">
            {item.code && <span className="tnum">{item.code}</span>}
            {item.brand && ` · ${item.brand}`}
            {item.description && ` · ${item.description}`}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p className="tnum text-sm">
            {formatQuantity(item.quantity_milli)} {item.unit ?? ""} × {formatCents(item.unit_price_cents)}
            {item.discount_percent > 0 && ` − ${percent(item.discount_percent)}`}
          </p>
          <p className="tnum font-medium">{formatCents(item.line_total_cents)}</p>
        </div>
      </div>

      {incluidos.length > 0 && (
        <div className="mt-2.5 ml-1 border-l-2 border-brand/30 pl-3">
          <p className="text-xs font-medium tracking-wide text-graphite-500 uppercase">Inclui</p>
          <ul className="mt-1 space-y-0.5 text-xs text-graphite-500">
            {incluidos.map((componente) => (
              <li key={`${componente.code}-${componente.item_type}`} className="flex gap-2">
                <span className="min-w-0 flex-1">{componente.name}</span>
                <span className="shrink-0 tnum text-graphite-300">
                  {formatQuantity(
                    Math.round((componente.quantity_milli * item.quantity_milli) / 1000),
                  )}{" "}
                  {componente.unit ?? ""}
                </span>
              </li>
            ))}
          </ul>

          {recusados.length > 0 && (
            <>
              <p className="mt-2 text-xs font-medium tracking-wide text-graphite-300 uppercase">
                Opcionais não incluídos nesta proposta
              </p>
              <ul className="mt-1 space-y-0.5 text-xs text-graphite-300 italic">
                {recusados.map((componente) => (
                  <li key={`${componente.code}-opt`}>{componente.name}</li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}
    </li>
  );
}

export default async function PublicQuotePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const document: QuoteDocument | null = await getSharedDocument(token);

  // Token inexistente, revogado, expirado, de orçamento excluído ou de
  // orçamento que não circula — tudo responde 404 igual, sem dizer qual
  // dos casos é.
  if (!document) notFound();

  const { company, customer } = document;
  const descontoPercentual =
    document.discount_percent > 0
      ? Math.round((document.subtotal_cents * document.discount_percent) / 100)
      : 0;

  return (
    <main className="min-h-dvh bg-sand py-6 sm:py-10">
      <div className="mx-auto w-full max-w-3xl px-4 sm:px-6">
        {/* ── Cabeçalho da empresa ─────────────────────────── */}
        <header className="rounded-card border border-line bg-white p-5 sm:p-7">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="min-w-0">
              <p className="font-display text-2xl tracking-tight text-brand">
                {company.trade_name.toUpperCase()}
              </p>
              <div className="mt-1 space-y-0.5 text-xs text-graphite-500">
                {company.document && <p>CNPJ {company.document}</p>}
                {(company.address || company.city) && (
                  <p>
                    {[company.address, company.city && `${company.city}${company.state ? `/${company.state}` : ""}`]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                )}
                {(company.phone || company.email) && (
                  <p>{[company.phone, company.email].filter(Boolean).join(" · ")}</p>
                )}
              </div>
            </div>

            <div className="rounded-lg bg-sand px-4 py-3 text-right">
              <p className="text-xs tracking-wide text-graphite-500 uppercase">Orçamento</p>
              <p className="font-display text-xl tnum">{document.number}</p>
              <p className="mt-1 text-xs text-graphite-500">
                Emissão {formatDate(document.issue_date)}
              </p>
              {document.valid_until && (
                <p className="text-xs text-graphite-500">
                  Validade {formatDate(document.valid_until)}
                </p>
              )}
            </div>
          </div>
        </header>

        {document.commercially_expired && (
          <div
            role="alert"
            className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
          >
            <strong>Proposta com validade encerrada.</strong> Os valores abaixo são os que foram
            propostos e podem não estar mais disponíveis. Fale com {document.owner_name} para uma
            proposta atualizada.
          </div>
        )}

        {/* ── Cliente ──────────────────────────────────────── */}
        <section className="mt-4 rounded-card border border-line bg-white p-5 sm:p-7">
          <p className="text-xs font-medium tracking-wide text-graphite-500 uppercase">Cliente</p>
          <p className="mt-1 text-lg font-medium">{customer.name}</p>
          <p className="mt-0.5 text-sm text-graphite-500">
            {[customer.document, [customer.city, customer.state].filter(Boolean).join("/")]
              .filter(Boolean)
              .join(" · ")}
          </p>
          <p className="mt-2 text-xs text-graphite-300">
            Proposta elaborada por {document.owner_name}
          </p>
        </section>

        {/* ── Itens ────────────────────────────────────────── */}
        <section className="mt-4 overflow-hidden rounded-card border border-line bg-white">
          <div className="border-b border-line px-4 py-3 sm:px-6">
            <p className="text-xs font-medium tracking-wide text-graphite-500 uppercase">
              Itens da proposta
            </p>
          </div>
          {document.items.length === 0 ? (
            <p className="px-4 py-5 text-sm text-graphite-300 sm:px-6">
              Esta proposta ainda não possui itens.
            </p>
          ) : (
            <ul>
              {document.items.map((item, index) => (
                <ItemLine key={`${item.code ?? "item"}-${index}`} item={item} />
              ))}
            </ul>
          )}
        </section>

        {/* ── Totais ───────────────────────────────────────── */}
        <section className="mt-4 rounded-card border border-line bg-white p-5 sm:p-7">
          <dl className="ml-auto max-w-xs space-y-1.5 text-sm">
            <div className="flex justify-between">
              <dt className="text-graphite-500">Subtotal</dt>
              <dd className="tnum">{formatCents(document.subtotal_cents)}</dd>
            </div>
            {descontoPercentual > 0 && (
              <div className="flex justify-between text-graphite-500">
                <dt>Desconto {percent(document.discount_percent)}</dt>
                <dd className="tnum">− {formatCents(descontoPercentual)}</dd>
              </div>
            )}
            {document.discount_amount_cents > 0 && (
              <div className="flex justify-between text-graphite-500">
                <dt>Desconto</dt>
                <dd className="tnum">− {formatCents(document.discount_amount_cents)}</dd>
              </div>
            )}
            {document.shipping_amount_cents > 0 && (
              <div className="flex justify-between text-graphite-500">
                <dt>Frete</dt>
                <dd className="tnum">+ {formatCents(document.shipping_amount_cents)}</dd>
              </div>
            )}
            <div className="flex justify-between border-t border-line pt-2 text-lg font-medium">
              <dt>Total</dt>
              <dd className="tnum text-brand">{formatCents(document.total_cents)}</dd>
            </div>
          </dl>
        </section>

        {/* ── Condições comerciais ─────────────────────────── */}
        {(document.payment_terms || document.delivery_terms || document.notes) && (
          <section className="mt-4 rounded-card border border-line bg-white p-5 text-sm sm:p-7">
            <p className="text-xs font-medium tracking-wide text-graphite-500 uppercase">
              Condições comerciais
            </p>
            <dl className="mt-2 space-y-1">
              {document.payment_terms && (
                <div className="flex gap-2">
                  <dt className="text-graphite-500">Pagamento:</dt>
                  <dd>{document.payment_terms}</dd>
                </div>
              )}
              {document.delivery_terms && (
                <div className="flex gap-2">
                  <dt className="text-graphite-500">Entrega:</dt>
                  <dd>{document.delivery_terms}</dd>
                </div>
              )}
            </dl>
            {document.notes && (
              <p className="mt-3 whitespace-pre-line text-graphite-500">{document.notes}</p>
            )}
          </section>
        )}

        {/* ── Ações ────────────────────────────────────────── */}
        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:justify-end">
          <a
            href={`/api/orcamento-publico/${token}/pdf`}
            className="inline-flex h-12 items-center justify-center gap-2 rounded-lg bg-brand px-5 text-sm font-medium text-white hover:bg-brand-deep"
          >
            <Download className="size-4" aria-hidden />
            Baixar PDF
          </a>
        </div>

        <footer className="mt-6 pb-4 text-center text-xs text-graphite-300">
          <p className="flex items-center justify-center gap-1.5">
            <Lock className="size-3" aria-hidden />
            Documento gerado por {company.trade_name}
            {company.website && ` · ${company.website.replace(/^https?:\/\//, "")}`}
          </p>
          {document.valid_until && (
            <p className="mt-1">
              {document.commercially_expired
                ? `Validade encerrada em ${formatDate(document.valid_until)}.`
                : `Proposta válida até ${formatDate(document.valid_until)}.`}
            </p>
          )}
        </footer>
      </div>
    </main>
  );
}
