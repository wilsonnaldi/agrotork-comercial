import type { Metadata } from "next";
import { BadgeCheck, FileText, Percent, Receipt } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody } from "@/components/ui/card";
import { StatCard } from "@/components/ui/stat-card";
import { Badge } from "@/components/ui/badge";
import { UrlSelect } from "@/components/ui/url-select";
import { EmptyState } from "@/components/ui/empty-state";
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONE } from "@/config/labels";
import { can } from "@/config/permissions";
import { requirePermission } from "@/lib/auth/session";
import { formatCents } from "@/lib/format/money";
import { PERIODO_LABELS, PERIODOS, reportFiltersSchema } from "@/modules/reports/schema";
import { getRelatorio, listOwners } from "@/modules/reports/service";

export const metadata: Metadata = { title: "Relatórios" };

const dataBr = (iso: string) => iso.split("-").reverse().join("/");
const porcento = (valor: number | null) => (valor === null ? "—" : `${valor.toString().replace(".", ",")}%`);

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const user = await requirePermission("reports.read");
  const params = await searchParams;

  const filtros = reportFiltersSchema.parse({
    periodo: params.periodo,
    de: params.de,
    ate: params.ate,
    vendedor: params.vendedor,
  });

  const vejoTodos = can(user.profile.role, "reports.readAll");
  const [relatorio, vendedores] = await Promise.all([
    getRelatorio(filtros),
    vejoTodos ? listOwners() : Promise.resolve([]),
  ]);

  return (
    <>
      <PageHeader
        title="Relatórios"
        description={
          vejoTodos
            ? "Orçamentos emitidos no período, por situação e por vendedor."
            : "Seus orçamentos emitidos no período."
        }
      />

      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="min-w-0 sm:w-56">
          <UrlSelect
            param="periodo"
            defaultValue={filtros.periodo}
            ariaLabel="Período"
            options={PERIODOS.filter((p) => p !== "personalizado").map((p) => ({
              value: p,
              label: PERIODO_LABELS[p],
            }))}
          />
        </div>
        {vejoTodos && vendedores.length > 1 && (
          <div className="min-w-0 sm:w-64">
            <UrlSelect
              param="vendedor"
              ariaLabel="Vendedor"
              options={[
                { value: "", label: "Todos os vendedores" },
                ...vendedores.map((v) => ({ value: v.id, label: v.full_name || "(sem nome)" })),
              ]}
            />
          </div>
        )}
        <p className="text-sm text-graphite-500">
          {dataBr(relatorio.de)} a {dataBr(relatorio.ate)}
        </p>
      </div>

      {relatorio.quantidade === 0 ? (
        <EmptyState
          icon={FileText}
          title="Nenhum orçamento no período"
          description="Escolha outro período ou emita o primeiro orçamento."
        />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard label="Orçamentos" value={relatorio.quantidade} icon={FileText} />
            <StatCard label="Valor emitido" value={formatCents(relatorio.total_cents)} icon={Receipt} />
            <StatCard
              label="Aprovado"
              value={formatCents(relatorio.aprovados_cents)}
              icon={BadgeCheck}
              hint={`${relatorio.aprovados} de ${relatorio.quantidade}`}
              accent
            />
            <StatCard
              label="Taxa de conversão"
              value={porcento(relatorio.conversao)}
              icon={Percent}
              hint={
                relatorio.conversao === null
                  ? "Nenhum orçamento decidido ainda"
                  : `${relatorio.decididos} decidido(s): aprovado, recusado ou expirado`
              }
            />
          </div>

          {relatorio.ticket_medio_cents !== null && (
            <p className="mt-3 text-sm text-graphite-500">
              Ticket médio do orçamento aprovado:{" "}
              <strong className="text-graphite">{formatCents(relatorio.ticket_medio_cents)}</strong>
            </p>
          )}

          <h2 className="mt-8 mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">
            Por situação
          </h2>
          <Card>
            <CardBody className="divide-y divide-line p-0">
              {relatorio.por_situacao.map((linha) => (
                <div key={linha.status} className="flex items-center justify-between gap-3 px-4 py-3">
                  <Badge tone={QUOTE_STATUS_TONE[linha.status]}>{QUOTE_STATUS_LABELS[linha.status]}</Badge>
                  <div className="flex items-baseline gap-4 text-right">
                    <span className="text-sm text-graphite-500">{linha.quantidade}</span>
                    <span className="min-w-28 font-medium tabular-nums">
                      {formatCents(linha.total_cents)}
                    </span>
                  </div>
                </div>
              ))}
            </CardBody>
          </Card>

          {vejoTodos && relatorio.por_vendedor.length > 0 && (
            <>
              <h2 className="mt-8 mb-3 font-display text-sm tracking-wide text-graphite-500 uppercase">
                Por vendedor
              </h2>
              <Card>
                <CardBody className="divide-y divide-line p-0">
                  {relatorio.por_vendedor.map((linha) => (
                    <div key={linha.owner_id} className="px-4 py-3">
                      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                        <p className="min-w-0 font-medium">{linha.owner_name}</p>
                        <p className="font-medium tabular-nums">{formatCents(linha.total_cents)}</p>
                      </div>
                      <p className="mt-1 text-xs text-graphite-500">
                        {linha.quantidade} orçamento(s) · {linha.aprovados} aprovado(s) ·{" "}
                        {formatCents(linha.aprovados_cents)} · conversão {porcento(linha.conversao)}
                      </p>
                    </div>
                  ))}
                </CardBody>
              </Card>
            </>
          )}

          <p className="mt-6 text-xs text-graphite-500">
            O período considera a <strong>data de emissão</strong> do orçamento. A conversão é
            aprovados ÷ decididos — rascunho e enviado ainda estão em aberto e não contam como perda;
            cancelado é desistência nossa e fica de fora.
          </p>
        </>
      )}
    </>
  );
}
