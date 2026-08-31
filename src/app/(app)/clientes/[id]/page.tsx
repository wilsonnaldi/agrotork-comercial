import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  ArrowLeft,
  FileText,
  Mail,
  MapPin,
  MessageCircle,
  Pencil,
  Phone,
  StickyNote,
} from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { requirePermission } from "@/lib/auth/session";
import { getCustomer, getCustomerHistory } from "@/modules/customers/service";
import { toggleCustomerActiveAction } from "@/modules/customers/actions";
import { PERSON_TYPE_LABELS, QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { formatCurrency, formatDate, formatDocument, formatPhone, formatZipCode, onlyDigits } from "@/lib/format";

export const metadata: Metadata = { title: "Ficha do cliente" };

export default async function CustomerDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ criado?: string; salvo?: string }>;
}) {
  await requirePermission("customers.read");

  const [{ id }, flags] = await Promise.all([params, searchParams]);
  const customer = await getCustomer(id);
  if (!customer) notFound();

  const history = await getCustomerHistory(id);

  const addressLine = [
    customer.address,
    customer.address_number,
    customer.address_complement,
    customer.district,
  ]
    .filter(Boolean)
    .join(", ");

  const cityLine = [customer.city, customer.state].filter(Boolean).join("/");
  const hasAddress = Boolean(addressLine || cityLine || customer.zip_code);
  const whatsappDigits = onlyDigits(customer.whatsapp);

  return (
    <>
      <Link
        href="/clientes"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Clientes
      </Link>

      <PageHeader
        title={customer.name}
        description={customer.trade_name ?? PERSON_TYPE_LABELS[customer.person_type]}
        action={
          <Button asChild size="lg" variant="secondary">
            <Link href={`/clientes/${customer.id}/editar`}>
              <Pencil className="size-4" aria-hidden />
              Editar
            </Link>
          </Button>
        }
      />

      {flags.criado && <Alert tone="success" className="mb-4">Cliente cadastrado.</Alert>}
      {flags.salvo && <Alert tone="success" className="mb-4">Alterações salvas.</Alert>}
      {!customer.is_active && (
        <Alert tone="info" className="mb-4">
          Este cliente está inativo e não aparece nas listagens padrão.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        {/* ── Dados ───────────────────────────────────────── */}
        <div className="space-y-5 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Dados</CardTitle>
              {customer.document && (
                <span className="tnum text-sm text-graphite-500">{formatDocument(customer.document)}</span>
              )}
            </CardHeader>
            <CardBody className="space-y-4">
              {customer.state_registration && (
                <Row label="Inscrição estadual" value={customer.state_registration} />
              )}

              {customer.phone && (
                <Row
                  icon={Phone}
                  label="Telefone"
                  value={
                    <a href={`tel:+55${onlyDigits(customer.phone)}`} className="hover:text-brand">
                      {formatPhone(customer.phone)}
                    </a>
                  }
                />
              )}

              {whatsappDigits && (
                <Row
                  icon={MessageCircle}
                  label="WhatsApp"
                  value={
                    <a
                      href={`https://wa.me/55${whatsappDigits}`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-whatsapp hover:underline"
                    >
                      {formatPhone(customer.whatsapp)}
                    </a>
                  }
                />
              )}

              {customer.email && (
                <Row
                  icon={Mail}
                  label="E-mail"
                  value={
                    <a href={`mailto:${customer.email}`} className="break-all hover:text-brand">
                      {customer.email}
                    </a>
                  }
                />
              )}

              {hasAddress && (
                <Row
                  icon={MapPin}
                  label="Endereço"
                  value={
                    <span>
                      {addressLine && <span className="block">{addressLine}</span>}
                      {cityLine && <span className="block">{cityLine}</span>}
                      {customer.zip_code && (
                        <span className="block tnum text-graphite-300">
                          CEP {formatZipCode(customer.zip_code)}
                        </span>
                      )}
                    </span>
                  }
                />
              )}

              {customer.notes && (
                <Row icon={StickyNote} label="Observações" value={<span className="whitespace-pre-wrap">{customer.notes}</span>} />
              )}

              {!customer.phone && !whatsappDigits && !customer.email && !hasAddress && !customer.notes && (
                <p className="text-sm text-graphite-300">
                  Só o nome foi preenchido. Use <strong>Editar</strong> para completar a ficha.
                </p>
              )}
            </CardBody>
          </Card>

          {/* ── Histórico ─────────────────────────────────── */}
          <Card>
            <CardHeader>
              <CardTitle>Histórico comercial</CardTitle>
              {history.quotes.length > 0 && (
                <span className="tnum text-sm text-graphite-500">
                  {formatCurrency(history.quotesTotal)}
                </span>
              )}
            </CardHeader>

            {history.quotes.length === 0 ? (
              <EmptyState
                icon={FileText}
                title="Nenhum orçamento ainda"
                description="Orçamentos, pedidos e contatos deste cliente vão aparecer aqui."
              />
            ) : (
              <ul className="divide-y divide-line">
                {history.quotes.map((quote) => (
                  <li key={quote.id}>
                    <Link
                      href={`/orcamentos/${quote.id}`}
                      className="flex items-center justify-between gap-3 px-4 py-3.5 hover:bg-sand sm:px-5"
                    >
                      <div className="min-w-0">
                        <p className="tnum text-sm font-medium">{quote.number}</p>
                        <p className="mt-0.5 text-xs text-graphite-300">{formatDate(quote.issue_date)}</p>
                      </div>
                      <div className="flex shrink-0 items-center gap-3">
                        <span className="tnum text-sm font-medium">{formatCurrency(quote.total)}</span>
                        <Badge tone={QUOTE_STATUS_TONE[quote.status]}>
                          {QUOTE_STATUS_LABELS[quote.status]}
                        </Badge>
                      </div>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        {/* ── Ações ───────────────────────────────────────── */}
        <aside className="space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={customer.is_active ? "success" : "warning"}>
                {customer.is_active ? "Ativo" : "Inativo"}
              </Badge>

              <form action={toggleCustomerActiveAction}>
                <input type="hidden" name="id" value={customer.id} />
                <input type="hidden" name="activate" value={String(!customer.is_active)} />
                <Button type="submit" variant={customer.is_active ? "danger" : "secondary"} fullWidth>
                  {customer.is_active ? "Desativar cliente" : "Reativar cliente"}
                </Button>
              </form>

              <p className="text-xs text-graphite-300">
                Desativar preserva todo o histórico. O cliente some das listagens padrão, mas os
                orçamentos antigos continuam intactos.
              </p>
            </CardBody>
          </Card>
        </aside>
      </div>
    </>
  );
}

function Row({
  icon: Icon,
  label,
  value,
}: {
  icon?: React.ComponentType<{ className?: string }>;
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="flex items-start gap-3">
      {Icon ? (
        <Icon className="mt-0.5 size-4 shrink-0 text-graphite-300" aria-hidden />
      ) : (
        <span className="mt-0.5 size-4 shrink-0" />
      )}
      <div className="min-w-0">
        <p className="text-xs text-graphite-300">{label}</p>
        <div className="text-sm">{value}</div>
      </div>
    </div>
  );
}
