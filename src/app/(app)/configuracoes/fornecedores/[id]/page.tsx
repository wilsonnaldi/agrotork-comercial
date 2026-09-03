import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  ArrowLeft,
  Globe,
  Handshake,
  Mail,
  MapPin,
  MessageCircle,
  Pencil,
  Phone,
  StickyNote,
  Wallet,
} from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { getSupplier } from "@/modules/suppliers/service";
import { deleteSupplierAction, toggleSupplierActiveAction } from "@/modules/suppliers/actions";
import { PERSON_TYPE_LABELS } from "@/config/labels";
import { formatDocument, formatPhone, formatZipCode, onlyDigits } from "@/lib/format";

export const metadata: Metadata = { title: "Ficha do fornecedor" };

type SearchParams = Promise<{ criado?: string; salvo?: string; erro?: string }>;

/** Um site digitado como "www.dji.com" ainda precisa de esquema para virar link. */
function toHref(website: string) {
  return /^https?:\/\//i.test(website) ? website : `https://${website}`;
}

export default async function SupplierDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("suppliers.read");
  const podeGerenciar = can(user.profile.role, "suppliers.manage");

  const [{ id }, flags] = await Promise.all([params, searchParams]);
  const supplier = await getSupplier(id);
  if (!supplier) notFound();

  const addressLine = [
    supplier.address,
    supplier.address_number,
    supplier.address_complement,
    supplier.district,
  ]
    .filter(Boolean)
    .join(", ");

  const cityLine = [supplier.city, supplier.state].filter(Boolean).join("/");
  const hasAddress = Boolean(addressLine || cityLine || supplier.zip_code);
  const whatsappDigits = onlyDigits(supplier.whatsapp);
  const vazio =
    !supplier.phone &&
    !whatsappDigits &&
    !supplier.email &&
    !supplier.website &&
    !hasAddress &&
    !supplier.notes &&
    !supplier.contact_name &&
    !supplier.payment_terms;

  return (
    <>
      <Link
        href="/configuracoes/fornecedores"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Fornecedores
      </Link>

      <PageHeader
        title={supplier.name}
        description={supplier.trade_name ?? PERSON_TYPE_LABELS[supplier.person_type]}
        action={
          podeGerenciar && (
            <Button asChild size="lg" variant="secondary">
              <Link href={`/configuracoes/fornecedores/${supplier.id}/editar`}>
                <Pencil className="size-4" aria-hidden />
                Editar
              </Link>
            </Button>
          )
        }
      />

      {flags.criado && <Alert tone="success" className="mb-4">Fornecedor cadastrado.</Alert>}
      {flags.salvo && <Alert tone="success" className="mb-4">Alterações salvas.</Alert>}
      {flags.erro && <Alert tone="warning" className="mb-4">{flags.erro}</Alert>}
      {!supplier.is_active && (
        <Alert tone="info" className="mb-4">
          Este fornecedor está inativo e não aparece nas listagens padrão.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="space-y-5 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Dados</CardTitle>
              {supplier.document && (
                <span className="tnum text-sm text-graphite-500">{formatDocument(supplier.document)}</span>
              )}
            </CardHeader>
            <CardBody className="space-y-4">
              {supplier.state_registration && (
                <Row label="Inscrição estadual" value={supplier.state_registration} />
              )}

              {supplier.contact_name && (
                <Row icon={Handshake} label="Quem nos atende" value={supplier.contact_name} />
              )}

              {supplier.payment_terms && (
                <Row icon={Wallet} label="Condição de pagamento" value={supplier.payment_terms} />
              )}

              {supplier.phone && (
                <Row
                  icon={Phone}
                  label="Telefone"
                  value={
                    <a href={`tel:+55${onlyDigits(supplier.phone)}`} className="hover:text-brand">
                      {formatPhone(supplier.phone)}
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
                      {formatPhone(supplier.whatsapp)}
                    </a>
                  }
                />
              )}

              {supplier.email && (
                <Row
                  icon={Mail}
                  label="E-mail"
                  value={
                    <a href={`mailto:${supplier.email}`} className="break-all hover:text-brand">
                      {supplier.email}
                    </a>
                  }
                />
              )}

              {supplier.website && (
                <Row
                  icon={Globe}
                  label="Site"
                  value={
                    <a
                      href={toHref(supplier.website)}
                      target="_blank"
                      rel="noreferrer"
                      className="break-all hover:text-brand"
                    >
                      {supplier.website}
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
                      {supplier.zip_code && (
                        <span className="block tnum text-graphite-300">
                          CEP {formatZipCode(supplier.zip_code)}
                        </span>
                      )}
                    </span>
                  }
                />
              )}

              {supplier.notes && (
                <Row
                  icon={StickyNote}
                  label="Observações"
                  value={<span className="whitespace-pre-wrap">{supplier.notes}</span>}
                />
              )}

              {vazio && (
                <p className="text-sm text-graphite-300">
                  {podeGerenciar ? (
                    <>
                      Só o nome foi preenchido. Use <strong>Editar</strong> para completar a ficha.
                    </>
                  ) : (
                    "Só o nome foi preenchido."
                  )}
                </p>
              )}
            </CardBody>
          </Card>
        </div>

        <aside className="space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={supplier.is_active ? "success" : "warning"}>
                {supplier.is_active ? "Ativo" : "Inativo"}
              </Badge>

              {podeGerenciar ? (
                <>
                  <form action={toggleSupplierActiveAction}>
                    <input type="hidden" name="id" value={supplier.id} />
                    <input type="hidden" name="activate" value={String(!supplier.is_active)} />
                    <Button type="submit" variant={supplier.is_active ? "danger" : "secondary"} fullWidth>
                      {supplier.is_active ? "Desativar fornecedor" : "Reativar fornecedor"}
                    </Button>
                  </form>

                  <p className="text-xs text-graphite-300">
                    Desativar preserva o cadastro. O fornecedor some das listagens padrão, mas a
                    entrada de mercadoria antiga continua apontando para ele.
                  </p>

                  <form action={deleteSupplierAction} className="border-t border-line pt-3">
                    <input type="hidden" name="id" value={supplier.id} />
                    <ConfirmButton
                      label="Excluir fornecedor"
                      confirmLabel="Sim, excluir"
                      question="O cadastro sai da listagem para sempre. Se ele já entregou mercadoria, prefira desativar."
                    />
                  </form>
                </>
              ) : (
                <p className="text-xs text-graphite-300">
                  Quem cadastra e altera fornecedor é a administração. Você pode consultar.
                </p>
              )}
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
