import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Lock, Search, SquareCheck } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { SearchInput } from "@/components/ui/search-input";
import { requirePermission } from "@/lib/auth/session";
import { componentSearchSchema } from "@/modules/kits/schema";
import {
  countKitQuoteUsage,
  getComposition,
  getKit,
  searchComponents,
} from "@/modules/kits/service";
import { addComponentAction, componentRowAction, updateKitAction } from "@/modules/kits/actions";
import { KitForm } from "../../kit-form";
import { AddComponentForm, ComponentRow } from "../../composition-editor";

export const metadata: Metadata = { title: "Editar kit" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function EditKitPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  await requirePermission("kits.write");

  const { id } = await params;
  const kit = await getKit(id);
  if (!kit) notFound();

  const query = await searchParams;
  const busca = componentSearchSchema.parse({ q: pick(query.q) });

  const [composition, quoteUsage, candidates] = await Promise.all([
    getComposition(kit.id),
    countKitQuoteUsage(kit.id),
    busca.q ? searchComponents(kit.id, busca) : Promise.resolve([]),
  ]);

  return (
    <>
      <Link
        href={`/kits/${kit.id}`}
        className="mb-3 inline-flex items-center gap-1.5 text-sm text-graphite-500 hover:text-brand"
      >
        <ArrowLeft className="size-4" aria-hidden />
        {kit.name}
      </Link>

      <PageHeader title="Editar kit" description={`${kit.code} · ${kit.items_count} componente(s)`} />

      {typeof query.criado === "string" && (
        <Alert tone="success" className="mb-4 max-w-3xl">
          Kit criado. Agora monte a composição: use a busca abaixo para adicionar produtos.
        </Alert>
      )}

      {quoteUsage > 0 && (
        <Alert tone="warning" className="mb-4 max-w-3xl">
          <strong>Este kit já aparece em {quoteUsage} item(ns) de orçamento.</strong> Editar a
          composição aqui <em>não</em> altera esses orçamentos: cada um guarda a composição e os
          preços congelados na data em que foi emitido.
        </Alert>
      )}

      <div className="grid gap-5 lg:grid-cols-3">
        <div className="min-w-0 lg:col-span-2">
          <div className="space-y-5">
            {/* ── Cabeçalho ───────────────────────────────── */}
            <KitForm action={updateKitAction} submitLabel="Salvar alterações" kit={{
              id: kit.id,
              code: kit.code,
              name: kit.name,
              description: kit.description,
              is_active: kit.is_active,
            }} />

            {/* ── Obrigatórios ────────────────────────────── */}
            <Card className="overflow-hidden">
              <CardHeader className="flex items-center justify-between gap-3">
                <CardTitle>
                  <span className="inline-flex items-center gap-2">
                    <Lock className="size-4 text-brand" aria-hidden />
                    Itens obrigatórios
                  </span>
                </CardTitle>
                <span className="text-xs text-graphite-300">{kit.required_count} item(ns)</span>
              </CardHeader>
              {composition.required.length === 0 ? (
                <p className="px-4 py-4 text-sm text-graphite-300 lg:px-5">
                  Nenhum item obrigatório ainda. Um kit sem obrigatórios não é oferecido em orçamento.
                </p>
              ) : (
                <ul className="divide-y divide-line">
                  {composition.required.map((item) => (
                    <ComponentRow key={item.id} action={componentRowAction} kitId={kit.id} item={item} />
                  ))}
                </ul>
              )}
            </Card>

            {/* ── Opcionais ───────────────────────────────── */}
            <Card className="overflow-hidden">
              <CardHeader className="flex items-center justify-between gap-3">
                <CardTitle>
                  <span className="inline-flex items-center gap-2">
                    <SquareCheck className="size-4 text-graphite-500" aria-hidden />
                    Itens opcionais
                  </span>
                </CardTitle>
                <span className="text-xs text-graphite-300">{kit.optional_count} item(ns)</span>
              </CardHeader>
              {composition.optional.length === 0 ? (
                <p className="px-4 py-4 text-sm text-graphite-300 lg:px-5">
                  Nenhum item opcional. O vendedor levará apenas os obrigatórios.
                </p>
              ) : (
                <ul className="divide-y divide-line">
                  {composition.optional.map((item) => (
                    <ComponentRow key={item.id} action={componentRowAction} kitId={kit.id} item={item} />
                  ))}
                </ul>
              )}
            </Card>

            {/* ── Adicionar componente ────────────────────── */}
            <Card className="overflow-hidden">
              <CardHeader>
                <CardTitle>Adicionar componente</CardTitle>
              </CardHeader>
              <CardBody className="space-y-3">
                <SearchInput placeholder="Buscar por código, código do fabricante, nome, marca ou categoria…" />
                <p className="text-xs text-graphite-300">
                  Só produtos <strong>ativos</strong> entram em associação nova. Cada produto entra uma
                  vez por kit — como obrigatório <em>ou</em> como opcional.
                </p>
              </CardBody>

              {busca.q && candidates.length === 0 && (
                <p className="px-4 pb-4 text-sm text-graphite-300 lg:px-5">
                  Nenhum produto ativo encontrado para “{busca.q}”.
                </p>
              )}

              {candidates.length > 0 && (
                <ul className="divide-y divide-line border-t border-line">
                  {candidates.map((candidate) => (
                    <AddComponentForm
                      key={candidate.id}
                      action={addComponentAction}
                      kitId={kit.id}
                      candidate={candidate}
                    />
                  ))}
                </ul>
              )}

              {!busca.q && (
                <p className="flex items-center gap-2 px-4 pb-4 text-sm text-graphite-300 lg:px-5">
                  <Search className="size-4" aria-hidden />
                  Digite acima para encontrar o produto.
                </p>
              )}
            </Card>
          </div>
        </div>

        <aside className="min-w-0 space-y-5">
          <Card>
            <CardHeader>
              <CardTitle>Obrigatório × opcional</CardTitle>
            </CardHeader>
            <CardBody className="space-y-3 text-sm text-graphite-500">
              <p className="flex items-start gap-2">
                <Lock className="mt-0.5 size-4 shrink-0 text-brand" aria-hidden />
                <span>
                  <strong className="text-graphite">Obrigatório</strong> — sempre entra quando o kit
                  for usado. O vendedor não tira.
                </span>
              </p>
              <p className="flex items-start gap-2">
                <SquareCheck className="mt-0.5 size-4 shrink-0 text-graphite-500" aria-hidden />
                <span>
                  <strong className="text-graphite">Opcional</strong> — fica <em>disponível</em> para
                  o vendedor escolher quando montar o orçamento.
                </span>
              </p>
              <p className="border-t border-line pt-3 text-xs">
                Esta tela define <strong>o que existe</strong>. A escolha do que entra em cada venda é
                feita no orçamento, sem alterar este cadastro — por isso não há caixa de seleção aqui.
              </p>
            </CardBody>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Histórico</CardTitle>
            </CardHeader>
            <CardBody className="space-y-2 text-xs text-graphite-300">
              <p>
                Remover um componente muda só o cadastro. Orçamentos já emitidos guardam a composição
                congelada e não são reescritos.
              </p>
              <p>
                Produto que for desativado depois continua no kit, com o vínculo preservado — mas não
                pode ser adicionado a um kit novo.
              </p>
            </CardBody>
          </Card>

          <Button asChild variant="secondary" fullWidth>
            <Link href={`/kits/${kit.id}`}>Ver ficha do kit</Link>
          </Button>
        </aside>
      </div>
    </>
  );
}
