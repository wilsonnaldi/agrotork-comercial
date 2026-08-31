import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Lock, Pencil, SquareCheck } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/modules/kits/schema";
import {
  countKitQuoteUsage,
  getComposition,
  getKit,
  kitIsUsable,
} from "@/modules/kits/service";
import { toggleKitActiveAction } from "@/modules/kits/actions";
import type { KitItemView } from "@/modules/kits/types";

export const metadata: Metadata = { title: "Kit" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function CompositionTable({ items, empty }: { items: KitItemView[]; empty: string }) {
  if (items.length === 0) {
    return <p className="px-5 py-4 text-sm text-graphite-300">{empty}</p>;
  }

  return (
    <>
      <table className="hidden w-full text-sm lg:table">
        <thead>
          <tr className="border-b border-line text-left text-xs tracking-wide text-graphite-300 uppercase">
            <th className="px-5 py-3 font-medium">Produto</th>
            <th className="px-5 py-3 font-medium">Código</th>
            <th className="px-5 py-3 font-medium">Marca</th>
            <th className="px-5 py-3 text-right font-medium">Qtd.</th>
            <th className="px-5 py-3 text-right font-medium">Preço unit.</th>
            <th className="px-5 py-3 text-right font-medium">Subtotal</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {items.map((item) => (
            <tr key={item.id}>
              <td className="px-5 py-3">
                <Link href={`/produtos/${item.product_id}`} className="font-medium hover:text-brand">
                  {item.product_name}
                </Link>
                {!item.product_is_active && (
                  <Badge tone="warning" className="ml-2">
                    Produto inativo
                  </Badge>
                )}
              </td>
              <td className="px-5 py-3 tnum text-graphite-500">
                {item.product_code}
                {item.manufacturer_code && (
                  <span className="block text-xs text-graphite-300">fab. {item.manufacturer_code}</span>
                )}
              </td>
              <td className="px-5 py-3 text-graphite-500">{item.brand_name ?? "—"}</td>
              <td className="px-5 py-3 text-right tnum">
                {formatQuantity(item.quantity_milli)} {item.unit_code ?? ""}
              </td>
              {/* Preço de VENDA. O custo não passa por aqui para ninguém: o
                  módulo de kits nunca lê `product_costs`. */}
              <td className="px-5 py-3 text-right tnum text-graphite-500">
                {formatCents(item.sale_price_cents)}
              </td>
              <td className="px-5 py-3 text-right tnum font-medium">
                {formatCents(item.line_total_cents)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <ul className="divide-y divide-line lg:hidden">
        {items.map((item) => (
          <li key={item.id} className="px-4 py-3.5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <Link href={`/produtos/${item.product_id}`} className="block truncate font-medium">
                  {item.product_name}
                </Link>
                <p className="mt-0.5 truncate text-xs text-graphite-300">
                  <span className="tnum">{item.product_code}</span>
                  {item.brand_name && ` · ${item.brand_name}`}
                </p>
              </div>
              <div className="shrink-0 text-right">
                <p className="tnum text-xs text-graphite-300">
                  {formatQuantity(item.quantity_milli)} {item.unit_code ?? ""} ×{" "}
                  {formatCents(item.sale_price_cents)}
                </p>
                <p className="tnum text-sm font-medium">{formatCents(item.line_total_cents)}</p>
              </div>
            </div>
          </li>
        ))}
      </ul>
    </>
  );
}

export default async function KitPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const user = await requirePermission("kits.read");
  const canWrite = can(user.profile.role, "kits.write");

  const { id } = await params;
  const kit = await getKit(id);
  if (!kit) notFound();

  const [composition, quoteUsage, query] = await Promise.all([
    getComposition(kit.id),
    canWrite ? countKitQuoteUsage(kit.id) : Promise.resolve(0),
    searchParams,
  ]);

  const usable = kitIsUsable(kit);

  return (
    <>
      <Link
        href="/kits"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Kits
      </Link>

      <PageHeader
        title={kit.name}
        description={`${kit.code} · ${kit.items_count} componente(s)`}
        action={
          canWrite && (
            <Button asChild size="lg" className="hidden sm:inline-flex">
              <Link href={`/kits/${kit.id}/editar`}>
                <Pencil className="size-4" aria-hidden />
                Editar kit
              </Link>
            </Button>
          )
        }
      />

      {typeof query.salvo === "string" && (
        <Alert tone="success" className="mb-4">
          Alterações salvas.
        </Alert>
      )}

      {!kit.is_active && (
        <Alert tone="warning" className="mb-4">
          <strong>Kit inativo.</strong> Não é oferecido em novos orçamentos, mas continua no histórico
          com a composição inteira preservada.
        </Alert>
      )}

      {kit.is_active && !usable && (
        <Alert tone="warning" className="mb-4">
          <strong>Kit incompleto.</strong> Sem nenhum item obrigatório, ele não tem o que entregar —
          não será oferecido em orçamento enquanto estiver assim.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="min-w-0 space-y-5 lg:col-span-2">
          {kit.description && (
            <Card>
              <CardBody>
                <p className="text-sm text-graphite-500">{kit.description}</p>
              </CardBody>
            </Card>
          )}

          <Card className="overflow-hidden">
            <CardHeader className="flex items-center justify-between gap-3">
              <CardTitle>
                <span className="inline-flex items-center gap-2">
                  <Lock className="size-4 text-brand" aria-hidden />
                  Obrigatórios
                </span>
              </CardTitle>
              <span className="text-xs text-graphite-300">
                {kit.required_count} item(ns) · sempre entram no kit
              </span>
            </CardHeader>
            <CompositionTable
              items={composition.required}
              empty="Nenhum item obrigatório. Um kit sem obrigatórios não é oferecido em orçamento."
            />
          </Card>

          <Card className="overflow-hidden">
            <CardHeader className="flex items-center justify-between gap-3">
              <CardTitle>
                <span className="inline-flex items-center gap-2">
                  <SquareCheck className="size-4 text-graphite-500" aria-hidden />
                  Opcionais
                </span>
              </CardTitle>
              <span className="text-xs text-graphite-300">
                {kit.optional_count} item(ns) · o vendedor escolhe no orçamento
              </span>
            </CardHeader>
            <CompositionTable
              items={composition.optional}
              empty="Este kit não oferece itens opcionais."
            />
          </Card>

          <Alert tone="info">
            <strong>Opcional do kit</strong> é o que o vendedor <em>pode</em> incluir. O que ele
            <strong> de fato incluir</strong> fica gravado no orçamento, com preço congelado naquela
            data — e não altera este cadastro.
          </Alert>
        </div>

        <aside className="min-w-0 space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Resumo</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-graphite-500">Situação</span>
                <Badge tone={kit.is_active ? "success" : "warning"}>
                  {kit.is_active ? "Ativo" : "Inativo"}
                </Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-graphite-500">Componentes</span>
                <span className="tnum font-medium">{kit.items_count}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-graphite-500">Obrigatórios</span>
                <span className="tnum font-medium">{kit.required_count}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-graphite-500">Opcionais</span>
                <span className="tnum font-medium">{kit.optional_count}</span>
              </div>
              <div className="flex items-center justify-between border-t border-line pt-3">
                <span className="text-graphite-500">Preço-base</span>
                <span className="tnum font-medium">{formatCents(kit.components_total_cents)}</span>
              </div>
              {kit.optional_count > 0 && (
                <div className="flex items-center justify-between">
                  <span className="text-graphite-500">Opcionais somam</span>
                  <span className="tnum text-graphite-500">
                    {formatCents(kit.optional_total_cents)}
                  </span>
                </div>
              )}
              <p className="text-xs text-graphite-300">
                O preço-base soma apenas os itens obrigatórios, a partir do preço de venda de cada
                produto. Nada é armazenado: mudou o preço do produto, muda aqui.
              </p>
            </CardBody>
          </Card>

          {canWrite && (
            <Card>
              <CardHeader>
                <CardTitle>Administração</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3">
                <Button asChild variant="secondary" fullWidth>
                  <Link href={`/kits/${kit.id}/editar`}>Editar kit e composição</Link>
                </Button>

                <form action={toggleKitActiveAction}>
                  <input type="hidden" name="id" value={kit.id} />
                  <input type="hidden" name="activate" value={String(!kit.is_active)} />
                  {kit.is_active ? (
                    <ConfirmButton
                      label="Desativar kit"
                      confirmLabel="Sim, desativar"
                      question={
                        quoteUsage > 0
                          ? `Este kit já aparece em ${quoteUsage} item(ns) de orçamento. Esses orçamentos não mudam — o kit só deixa de ser oferecido em novos.`
                          : "O kit deixa de ser oferecido em novos orçamentos. A composição é preservada."
                      }
                    />
                  ) : (
                    <Button type="submit" variant="secondary" fullWidth>
                      Reativar kit
                    </Button>
                  )}
                </form>

                <p className="text-xs text-graphite-300">
                  Kits não são excluídos. O banco recusa apagar um kit citado em orçamento, e a
                  desativação preserva a composição e todo o histórico.
                </p>
              </CardBody>
            </Card>
          )}
        </aside>
      </div>

      {canWrite && (
        <Button asChild size="lg" fullWidth className="mt-4 sm:hidden">
          <Link href={`/kits/${kit.id}/editar`}>
            <Pencil className="size-4" aria-hidden />
            Editar kit
          </Link>
        </Button>
      )}
    </>
  );
}
