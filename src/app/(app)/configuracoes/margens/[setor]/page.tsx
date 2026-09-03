import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { ConfirmButton } from "@/components/ui/confirm-button";
import { PageHeader } from "@/components/ui/page-header";
import { formatCurrency } from "@/lib/format";
import { requirePermission } from "@/lib/auth/session";
import { applyMarginAction } from "@/modules/margins/actions";
import { getSectorPreview } from "@/modules/margins/service";

export const metadata: Metadata = { title: "Conferir preços" };

type Params = Promise<{ setor: string }>;
type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function MarginPreviewPage({
  params,
  searchParams,
}: {
  params: Params;
  searchParams: SearchParams;
}) {
  await requirePermission("catalog.manage");

  const { setor } = await params;
  const categoryId = setor === "sem-setor" ? null : setor;
  const preview = await getSectorPreview(categoryId);
  if (!preview) notFound();

  const erro = pick((await searchParams).erro);
  const total = preview.changes.reduce((soma, change) => soma + change.preco_sugerido, 0);

  return (
    <>
      <Button asChild variant="ghost" size="sm" className="mb-3 -ml-2">
        <Link href="/configuracoes/margens">
          <ArrowLeft className="size-4" aria-hidden />
          Voltar às margens
        </Link>
      </Button>

      <PageHeader
        title={preview.name}
        description="Confira antes de gravar. Nada foi alterado até aqui."
      />

      {erro && (
        <Alert tone="error" className="mb-4">
          {erro}
        </Alert>
      )}

      {preview.changes.length === 0 ? (
        <Alert tone="info" title="Nada a mudar">
          Ou o setor não tem regra ativa, ou os preços já estão como a regra manda. Se acabou de
          configurar a margem, confirme que marcou a regra como ativa.
        </Alert>
      ) : (
        <>
          <Alert tone="warning" className="mb-4" title={`${preview.changes.length} ${preview.changes.length === 1 ? "produto vai mudar" : "produtos vão mudar"} de preço`}>
            A tabela do setor passa a somar {formatCurrency(total)}. O preço anterior fica registrado na
            trilha de auditoria, com a data e quem aplicou.
          </Alert>

          {/* Rolagem horizontal só na tabela: o corpo da página nunca rola para o lado. */}
          <Card className="mb-5 overflow-x-auto">
            <table className="w-full min-w-[560px] text-sm">
              <thead>
                <tr className="border-b border-line text-left">
                  <th className="px-4 py-3 font-display text-xs tracking-wide text-graphite-300 uppercase">
                    Código
                  </th>
                  <th className="px-4 py-3 font-display text-xs tracking-wide text-graphite-300 uppercase">
                    Produto
                  </th>
                  <th className="px-4 py-3 text-right font-display text-xs tracking-wide text-graphite-300 uppercase">
                    Preço atual
                  </th>
                  <th className="px-4 py-3 text-right font-display text-xs tracking-wide text-graphite-300 uppercase">
                    Preço novo
                  </th>
                </tr>
              </thead>
              <tbody>
                {preview.changes.map((change) => (
                  <tr key={change.product_id} className="border-b border-line last:border-0">
                    <td className="px-4 py-2.5 font-display whitespace-nowrap text-graphite-500">
                      {change.code}
                    </td>
                    <td className="px-4 py-2.5">{change.name}</td>
                    <td className="px-4 py-2.5 text-right tnum text-graphite-300">
                      {change.preco_atual > 0 ? formatCurrency(change.preco_atual) : "sem preço"}
                    </td>
                    <td className="px-4 py-2.5 text-right tnum font-medium text-brand">
                      {formatCurrency(change.preco_sugerido)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>

          <form action={applyMarginAction} className="max-w-md">
            <input type="hidden" name="category_id" value={categoryId ?? ""} />
            <ConfirmButton
              label={`Aplicar aos ${preview.changes.length} produtos`}
              confirmLabel="Confirmar e gravar"
              question={`Gravar o preço de venda de ${preview.changes.length} ${preview.changes.length === 1 ? "produto" : "produtos"} em ${preview.name}?`}
              variant="primary"
            />
          </form>
        </>
      )}
    </>
  );
}
