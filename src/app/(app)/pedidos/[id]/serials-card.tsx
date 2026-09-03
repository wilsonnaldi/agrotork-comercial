import Link from "next/link";
import { ScanLine } from "lucide-react";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select } from "@/components/ui/select";
import { getOrderSerialPlan } from "@/modules/stock/service";
import { assignSerialAction, releaseSerialAction } from "@/modules/stock/actions";
import type { OrderItemView } from "@/modules/orders/types";

/**
 * Aparelhos deste pedido.
 *
 * Só aparece quando o pedido vendeu algo com número de série. O
 * faturamento NÃO exige série — é a mesma decisão do estoque: avisar, não
 * travar. Este cartão é o aviso, e fica em aberto até alguém informar.
 */
export async function SerialsCard({
  orderId,
  status,
  items,
  podeGerenciar,
}: {
  orderId: string;
  status: string;
  items: OrderItemView[];
  podeGerenciar: boolean;
}) {
  const linhas = await getOrderSerialPlan(orderId, items);
  if (linhas.length === 0) return null;

  const faturado = status === "invoiced" || status === "delivered";
  const faltando = linhas.reduce(
    (soma, linha) => soma + Math.max(linha.needed - linha.assigned.length, 0),
    0,
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Aparelhos</CardTitle>
        {faltando > 0 ? (
          <Badge tone="warning">
            {faltando === 1 ? "1 sem série" : `${faltando} sem série`}
          </Badge>
        ) : (
          <Badge tone="success">Completo</Badge>
        )}
      </CardHeader>

      <CardBody className="space-y-4 text-sm">
        {!faturado && (
          <p className="text-xs text-graphite-300">
            O aparelho se vincula a partir do faturamento — antes disso ele ainda pode ser trocado
            na separação.
          </p>
        )}

        {linhas.map((linha) => (
          <div key={linha.order_item_id} className="space-y-2">
            <p className="font-medium">
              {linha.name}
              <span className="ml-1.5 text-xs text-graphite-300">
                {linha.assigned.length} de {linha.needed}
              </span>
            </p>

            {linha.assigned.length > 0 && (
              <ul className="space-y-1.5">
                {linha.assigned.map((aparelho) => (
                  <li key={aparelho.id} className="flex items-center justify-between gap-2">
                    <span className="tnum text-sm">{aparelho.serial}</span>
                    {podeGerenciar && (
                      <form action={releaseSerialAction}>
                        <input type="hidden" name="serial_id" value={aparelho.id} />
                        <input type="hidden" name="order_id" value={orderId} />
                        <button
                          type="submit"
                          className="text-xs text-graphite-300 underline hover:text-brand"
                        >
                          desvincular
                        </button>
                      </form>
                    )}
                  </li>
                ))}
              </ul>
            )}

            {podeGerenciar && faturado && linha.assigned.length < linha.needed && (
              linha.available.length > 0 ? (
                <form action={assignSerialAction} className="flex gap-2">
                  <input type="hidden" name="order_item_id" value={linha.order_item_id} />
                  <input type="hidden" name="order_id" value={orderId} />
                  <Select name="serial_id" aria-label={`Aparelho para ${linha.name}`} required>
                    {linha.available.map((aparelho) => (
                      <option key={aparelho.id} value={aparelho.id}>
                        {aparelho.serial}
                      </option>
                    ))}
                  </Select>
                  <Button type="submit" variant="secondary">
                    Vincular
                  </Button>
                </form>
              ) : (
                <p className="text-xs text-graphite-300">
                  Nenhum aparelho disponível no galpão.{" "}
                  <Link href={`/estoque/${linha.product_id}`} className="underline hover:text-brand">
                    Cadastrar série
                  </Link>
                </p>
              )
            )}
          </div>
        ))}

        {!podeGerenciar && (
          <p className="flex items-start gap-2 text-xs text-graphite-300">
            <ScanLine className="mt-0.5 size-3.5 shrink-0" aria-hidden />
            Quem vincula o aparelho ao pedido é a administração.
          </p>
        )}
      </CardBody>
    </Card>
  );
}
