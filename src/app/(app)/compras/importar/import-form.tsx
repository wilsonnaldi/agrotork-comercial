"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Building2, CheckCircle2, CircleHelp, ScanBarcode } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, Input } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { confirmImportAction, previewNfeAction, type ImportState } from "@/modules/purchases/import-actions";
import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDocument } from "@/lib/format";

function Enviando({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} fullWidth>
      {pending ? "Lendo a nota…" : label}
    </Button>
  );
}

function Confirmando({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" disabled={pending} className="w-full sm:w-auto">
      {pending ? "Importando…" : label}
    </Button>
  );
}

/**
 * Dois passos numa tela só: mandar o arquivo, conferir o que o sistema
 * entendeu. Nada é gravado no primeiro passo — abrir o XML errado não
 * deixa rascunho nenhum no banco.
 */
export function ImportForm({
  conditions,
  products,
}: {
  conditions: { id: string; name: string; is_default: boolean }[];
  products: { id: string; code: string; name: string }[];
}) {
  const [state, enviarAction] = useActionState<ImportState, FormData>(previewNfeAction, {});
  const [confirmState, confirmarAction] = useActionState<ImportState, FormData>(
    confirmImportAction,
    {},
  );

  const preview = state.preview;
  const condicaoPadrao = conditions.find((c) => c.is_default)?.id ?? conditions[0]?.id ?? "";

  if (!preview) {
    return (
      <form action={enviarAction} className="max-w-xl space-y-4">
        {state.error && <Alert tone="warning">{state.error}</Alert>}

        <Card>
          <CardHeader>
            <CardTitle>O arquivo da nota</CardTitle>
          </CardHeader>
          <CardBody className="space-y-4">
            <Field
              label="XML da NF-e"
              htmlFor="xml"
              hint="O arquivo que o fornecedor manda por e-mail, ou o que se baixa no portal"
            >
              <Input id="xml" name="xml" type="file" accept=".xml,text/xml,application/xml" required />
            </Field>

            <Enviando label="Ler a nota" />

            <p className="text-xs text-graphite-300">
              Nada é gravado agora. Você confere o que o sistema entendeu antes de qualquer coisa
              entrar no cadastro.
            </p>
          </CardBody>
        </Card>
      </form>
    );
  }

  const { nfe, supplier, supplierFromNfe, lines, matched, pending } = preview;

  return (
    <form action={confirmarAction} className="space-y-4">
      <input type="hidden" name="preview" value={JSON.stringify(preview)} />

      {confirmState.error && <Alert tone="warning">{confirmState.error}</Alert>}

      {/* ── O emitente ──────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Fornecedor</CardTitle>
          {supplier ? (
            <Badge tone="success">Já cadastrado</Badge>
          ) : (
            <Badge tone="warning">Será cadastrado</Badge>
          )}
        </CardHeader>
        <CardBody className="space-y-2 text-sm">
          <p className="flex items-start gap-2 font-medium">
            <Building2 className="mt-0.5 size-4 shrink-0 text-graphite-300" aria-hidden />
            {supplier?.name ?? supplierFromNfe.legal_name ?? "—"}
          </p>
          <p className="text-xs tnum text-graphite-500">
            {formatDocument(supplierFromNfe.document) || "sem CNPJ na nota"}
            {supplierFromNfe.city && ` · ${supplierFromNfe.city}/${supplierFromNfe.state ?? ""}`}
          </p>
          {!supplier && (
            <p className="text-xs text-graphite-500">
              Este CNPJ ainda não está no cadastro. Ao importar, ele entra com os dados da própria
              nota — nome, endereço e telefone.
            </p>
          )}
        </CardBody>
      </Card>

      {/* ── A nota ──────────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>
            Nota {nfe.number ?? "—"}
            {nfe.series ? ` · série ${nfe.series}` : ""}
          </CardTitle>
          <span className="tnum text-sm text-graphite-500">
            {formatCents(nfe.totals.invoice_cents)}
          </span>
        </CardHeader>
        <CardBody className="grid gap-3 sm:grid-cols-2">
          <dl className="space-y-1.5 text-sm">
            <Linha rotulo="Emissão" valor={nfe.issue_date ?? "—"} />
            <Linha rotulo="Produtos" valor={formatCents(nfe.totals.products_cents)} />
            {nfe.totals.freight_cents > 0 && (
              <Linha rotulo="Frete" valor={formatCents(nfe.totals.freight_cents)} />
            )}
            {nfe.totals.discount_cents > 0 && (
              <Linha rotulo="Desconto" valor={`− ${formatCents(nfe.totals.discount_cents)}`} />
            )}
          </dl>

          <Field
            label="Condição de pagamento"
            htmlFor="condition_id"
            hint="Define qual custo do produto será atualizado, e o vencimento da conta a pagar"
          >
            <Select id="condition_id" name="condition_id" defaultValue={condicaoPadrao} required>
              {conditions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        </CardBody>
      </Card>

      {/* ── Os itens ────────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Itens da nota</CardTitle>
          <span className="text-xs text-graphite-300">
            {matched} de {lines.length} reconhecidos
          </span>
        </CardHeader>

        {pending > 0 && (
          <CardBody className="border-b border-line">
            <Alert tone="info">
              {pending === 1
                ? "1 item ainda não tem produto. Escolha qual é — o sistema guarda a resposta e da próxima nota deste fornecedor ele entra sozinho."
                : `${pending} itens ainda não têm produto. Escolha quais são — o sistema guarda as respostas e da próxima nota deste fornecedor eles entram sozinhos.`}
            </Alert>
          </CardBody>
        )}

        {/* A chave é o ÍNDICE porque a NF-e pode trazer o mesmo `cProd`
            duas vezes (lotes diferentes na mesma nota). Usar o código
            daria chave repetida, e o React embaralharia as linhas. */}
        <ul className="divide-y divide-line">
          {lines.map((linha, indice) => (
            <li key={`${indice}-${linha.supplier_code}`} className="px-4 py-4 sm:px-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="font-medium">{linha.description}</p>
                  <p className="mt-0.5 text-xs tnum text-graphite-300">
                    {linha.supplier_code && `cód. ${linha.supplier_code} · `}
                    {formatQuantity(linha.quantity_milli)}
                    {linha.unit ? ` ${linha.unit}` : ""}
                    {` × ${formatCents(linha.unit_cost_cents)}`}
                  </p>
                </div>
                <p className="shrink-0 tnum text-sm font-medium">
                  {formatCents(linha.line_total_cents)}
                </p>
              </div>

              <div className="mt-2.5">
                {linha.product_id ? (
                  <p className="flex items-center gap-1.5 text-sm text-emerald-700">
                    {linha.origin === "gtin" ? (
                      <ScanBarcode className="size-4 shrink-0" aria-hidden />
                    ) : (
                      <CheckCircle2 className="size-4 shrink-0" aria-hidden />
                    )}
                    <span className="min-w-0 truncate">
                      {linha.product_code} · {linha.product_name}
                    </span>
                    <span className="shrink-0 text-xs text-graphite-300">
                      {linha.origin === "gtin" ? "pelo código de barras" : "já conhecido"}
                    </span>
                  </p>
                ) : (
                  <div className="space-y-1.5">
                    <p className="flex items-center gap-1.5 text-xs text-graphite-500">
                      <CircleHelp className="size-3.5 shrink-0" aria-hidden />
                      Qual produto do catálogo é este?
                    </p>
                    <Select
                      name={`produto:${linha.supplier_code}`}
                      aria-label={`Produto para ${linha.description}`}
                    >
                      <option value="">Não importar este item</option>
                      {products.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.code} · {p.name}
                        </option>
                      ))}
                    </Select>
                  </div>
                )}
              </div>
            </li>
          ))}
        </ul>
      </Card>

      <div className="flex flex-col-reverse gap-3 pb-2 sm:flex-row sm:justify-end">
        <Button asChild variant="secondary" size="lg" className="w-full sm:w-auto">
          <Link href="/compras">Cancelar</Link>
        </Button>
        <Confirmando label="Importar como rascunho" />
      </div>

      <p className="text-xs text-graphite-300">
        A nota entra como <strong>rascunho</strong>. O estoque e o custo só se mexem quando você
        confirmar o recebimento — como em qualquer entrada digitada à mão.
      </p>
    </form>
  );
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-graphite-500">{rotulo}</dt>
      <dd className="tnum">{valor}</dd>
    </div>
  );
}
