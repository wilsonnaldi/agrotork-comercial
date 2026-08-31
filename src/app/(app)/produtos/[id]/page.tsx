import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Boxes, FileStack, History, Pencil, Truck, Warehouse } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert } from "@/components/ui/alert";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { requirePermission } from "@/lib/auth/session";
import { can } from "@/config/permissions";
import { countKitUsage, getProduct } from "@/modules/products/service";
import { toggleProductActiveAction } from "@/modules/products/actions";
import { formatCents } from "@/lib/format/money";
import { formatDate, formatNumber } from "@/lib/format";
import { PRODUCT_SOURCE_LABELS } from "@/config/labels";

export const metadata: Metadata = { title: "Ficha do produto" };

export default async function ProductDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ criado?: string; salvo?: string }>;
}) {
  const user = await requirePermission("products.read");
  const canViewCost = can(user.profile.role, "products.viewCost");
  const canWrite = can(user.profile.role, "products.write");

  const [{ id }, flags] = await Promise.all([params, searchParams]);
  const product = await getProduct(id);
  if (!product) notFound();

  const kitUsage = canWrite ? await countKitUsage(product.id) : 0;

  // `technical_data` vem do catálogo do fabricante e varia por marca.
  const technicalEntries =
    product.technical_data && typeof product.technical_data === "object" && !Array.isArray(product.technical_data)
      ? Object.entries(product.technical_data as Record<string, unknown>)
      : [];

  return (
    <>
      <Link
        href="/produtos"
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        Produtos
      </Link>

      <PageHeader
        title={product.name}
        description={`${product.code}${product.brand_name ? ` · ${product.brand_name}` : ""}`}
        action={
          canWrite && (
            <Button asChild size="lg" variant="secondary">
              <Link href={`/produtos/${product.id}/editar`}>
                <Pencil className="size-4" aria-hidden />
                Editar produto
              </Link>
            </Button>
          )
        }
      />

      {flags.criado && <Alert tone="success" className="mb-4">Produto cadastrado.</Alert>}
      {flags.salvo && <Alert tone="success" className="mb-4">Alterações salvas.</Alert>}
      {!product.is_active && (
        <Alert tone="info" className="mb-4">
          Produto inativo: não aparece nas seleções comerciais, mas continua no histórico e nos kits
          onde já foi usado.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="space-y-5 lg:col-span-2">
          {/* ── Preços ────────────────────────────────────── */}
          <Card>
            <CardHeader>
              <CardTitle>Preços</CardTitle>
              <span className="text-xs text-graphite-300">Valores em reais</span>
            </CardHeader>
            <CardBody>
              <dl className={`grid gap-4 ${canViewCost ? "sm:grid-cols-3" : "sm:grid-cols-1"}`}>
                {canViewCost && (
                  <div>
                    <dt className="text-xs text-graphite-300">Preço de custo</dt>
                    <dd className="mt-1 font-display text-xl tnum">{formatCents(product.cost_price_cents)}</dd>
                  </div>
                )}
                <div>
                  <dt className="text-xs text-graphite-300">Preço de venda</dt>
                  <dd className="mt-1 font-display text-2xl tnum text-brand-deep">
                    {formatCents(product.sale_price_cents)}
                  </dd>
                </div>
                {canViewCost && (
                  <div>
                    <dt className="text-xs text-graphite-300">Margem</dt>
                    <dd className="mt-1 font-display text-xl tnum">
                      {product.margin_percent === null ? "—" : `${formatNumber(product.margin_percent)}%`}
                    </dd>
                  </div>
                )}
              </dl>
            </CardBody>
          </Card>

          {/* ── Dados ─────────────────────────────────────── */}
          <Card>
            <CardHeader>
              <CardTitle>Dados</CardTitle>
            </CardHeader>
            <CardBody className="grid gap-4 sm:grid-cols-2">
              <Row label="Código" value={<span className="tnum">{product.code}</span>} />
              <Row
                label="Código do fabricante"
                value={
                  product.manufacturer_code ? (
                    <span className="tnum">{product.manufacturer_code}</span>
                  ) : (
                    "—"
                  )
                }
              />
              <Row label="Unidade" value={product.unit_code ? `${product.unit_code} · ${product.unit_name}` : "—"} />
              <Row label="Marca" value={product.brand_name ?? "—"} />
              <Row label="Categoria" value={product.category_name ?? "—"} />

              {product.description && (
                <div className="sm:col-span-2">
                  <p className="text-xs text-graphite-300">Descrição</p>
                  <p className="mt-1 text-sm whitespace-pre-wrap">{product.description}</p>
                </div>
              )}

              {product.notes && (
                <div className="sm:col-span-2">
                  <p className="text-xs text-graphite-300">Observações internas</p>
                  <p className="mt-1 text-sm whitespace-pre-wrap">{product.notes}</p>
                </div>
              )}

              {product.image_url && (
                <div className="sm:col-span-2">
                  <p className="mb-2 text-xs text-graphite-300">Imagem</p>
                  {/* Endereço externo arbitrário: `next/image` entra quando as fotos
                      passarem a viver no Storage do Supabase. */}
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={product.image_url}
                    alt={product.name}
                    className="h-48 w-48 rounded-lg border border-line bg-sand object-contain"
                  />
                </div>
              )}
            </CardBody>
          </Card>

          {/* ── Procedência ───────────────────────────────── */}
          {(product.source_type !== "manual" || technicalEntries.length > 0) && (
            <Card>
              <CardHeader>
                <CardTitle>Procedência</CardTitle>
                <Badge tone={product.source_type === "test_data" ? "warning" : "info"}>
                  {PRODUCT_SOURCE_LABELS[product.source_type]}
                </Badge>
              </CardHeader>
              <CardBody className="grid gap-4 sm:grid-cols-2">
                {product.source_brand && <Row label="Fabricante de origem" value={product.source_brand} />}
                {product.source_catalog && <Row label="Catálogo" value={product.source_catalog} />}
                {product.source_version && <Row label="Versão do catálogo" value={product.source_version} />}
                {product.source_reference && <Row label="Referência" value={product.source_reference} />}
                {product.source_imported_at && (
                  <Row label="Importado em" value={formatDate(product.source_imported_at)} />
                )}

                {technicalEntries.length > 0 && (
                  <div className="sm:col-span-2">
                    <p className="mb-2 text-xs text-graphite-300">Dados técnicos do catálogo</p>
                    <dl className="grid gap-2 sm:grid-cols-2">
                      {technicalEntries.map(([key, value]) => (
                        <div key={key} className="flex gap-2 text-sm">
                          <dt className="text-graphite-300">{key}:</dt>
                          <dd>{String(value)}</dd>
                        </div>
                      ))}
                    </dl>
                  </div>
                )}

                {product.source_type === "test_data" && (
                  <p className="text-xs text-graphite-300 sm:col-span-2">
                    Este produto veio de massa de teste e será removido quando o catálogo oficial
                    entrar. Não é catálogo AGROTORK.
                  </p>
                )}
              </CardBody>
            </Card>
          )}

          {/* ── Áreas preparadas, ainda sem módulo ────────── */}
          <Card>
            <CardHeader>
              <CardTitle>Ainda por vir</CardTitle>
            </CardHeader>
            <CardBody>
              <ul className="grid gap-3 text-sm text-graphite-300 sm:grid-cols-2">
                <Upcoming icon={Boxes} label="Kits que usam este produto" phase="Fase 3" />
                <Upcoming icon={FileStack} label="Importação de catálogo do fabricante" phase="Backlog" />
                <Upcoming icon={History} label="Histórico de preços" phase="Fase 6" />
                <Upcoming icon={Truck} label="Fornecedores" phase="Backlog" />
                <Upcoming icon={Warehouse} label="Estoque e movimentações" phase="Backlog" />
              </ul>
              <p className="mt-4 text-xs text-graphite-300">
                O modelo de dados já comporta essas áreas; elas entram nos módulos correspondentes.
              </p>
            </CardBody>
          </Card>
        </div>

        {/* ── Situação ────────────────────────────────────── */}
        <aside className="space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Situação</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3">
              <Badge tone={product.is_active ? "success" : "warning"}>
                {product.is_active ? "Ativo" : "Inativo"}
              </Badge>

              {canWrite ? (
                <form action={toggleProductActiveAction}>
                  <input type="hidden" name="id" value={product.id} />
                  <input type="hidden" name="activate" value={String(!product.is_active)} />
                  {product.is_active ? (
                    <ConfirmButton
                      label="Desativar produto"
                      confirmLabel="Sim, desativar"
                      question={
                        kitUsage > 0
                          ? `Este produto faz parte de ${kitUsage} kit(s). Desativar não o remove de lá, mas ele deixa de aparecer em novas seleções.`
                          : "O produto deixa de aparecer nas seleções comerciais. Nada do histórico é perdido."
                      }
                    />
                  ) : (
                    <Button type="submit" variant="secondary" fullWidth>
                      Reativar produto
                    </Button>
                  )}
                </form>
              ) : (
                <p className="text-xs text-graphite-300">
                  Somente o administrador altera produtos e preços.
                </p>
              )}

              <p className="text-xs text-graphite-300">
                Produtos não são excluídos: a desativação preserva orçamentos e kits que já os
                utilizam.
              </p>
            </CardBody>
          </Card>
        </aside>
      </div>
    </>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs text-graphite-300">{label}</p>
      <div className="mt-0.5 text-sm">{value}</div>
    </div>
  );
}

function Upcoming({
  icon: Icon,
  label,
  phase,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  phase: string;
}) {
  return (
    <li className="flex items-center gap-2">
      <Icon className="size-4 shrink-0" aria-hidden />
      <span>{label}</span>
      <span className="ml-auto text-xs">{phase}</span>
    </li>
  );
}
