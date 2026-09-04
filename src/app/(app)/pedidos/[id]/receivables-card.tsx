import Link from "next/link";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { getEntriesByOrder } from "@/modules/financial/service";
import { FINANCIAL_STATUS_LABELS, FINANCIAL_STATUS_TONE } from "@/config/labels";
import { formatCents } from "@/lib/format/money";
import { formatDate } from "@/lib/format";

/**
 * O dinheiro deste pedido, na ficha do próprio pedido.
 *
 * Só aparece para quem tem financeiro — o vendedor abre o mesmo pedido e
 * não vê este cartão, do mesmo jeito que não vê o caixa da empresa. E só
 * existe depois do faturamento, porque é aí que o título nasce.
 */
export async function ReceivablesCard({ orderId }: { orderId: string }) {
  const titulos = await getEntriesByOrder(orderId);
  if (titulos.length === 0) return null;

  const falta = titulos.reduce((soma, t) => soma + t.open_cents, 0);
  const atrasados = titulos.filter((t) => t.is_overdue).length;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Recebimento</CardTitle>
        {falta === 0 ? (
          <Badge tone="success">Recebido</Badge>
        ) : (
          <Badge tone={atrasados > 0 ? "danger" : "info"}>
            {formatCents(falta)} a receber
          </Badge>
        )}
      </CardHeader>
      <CardBody className="space-y-2 text-sm">
        {titulos.map((titulo) => (
          <Link
            key={titulo.id}
            href={`/financeiro/${titulo.id}`}
            className="flex items-center justify-between gap-3 hover:text-brand"
          >
            <span className="min-w-0">
              <span className="tnum">{formatDate(titulo.due_date)}</span>
              {titulo.installments > 1 && (
                <span className="ml-1.5 text-xs text-graphite-300">
                  {titulo.installment}/{titulo.installments}
                </span>
              )}
              {titulo.is_overdue && (
                <span className="ml-1.5 text-xs font-medium text-brand-deep">
                  {titulo.days_overdue}d de atraso
                </span>
              )}
            </span>
            <span className="flex shrink-0 items-center gap-2">
              <span className="tnum">{formatCents(titulo.amount_cents)}</span>
              <Badge tone={FINANCIAL_STATUS_TONE[titulo.status]}>
                {FINANCIAL_STATUS_LABELS[titulo.status]}
              </Badge>
            </span>
          </Link>
        ))}
      </CardBody>
    </Card>
  );
}
