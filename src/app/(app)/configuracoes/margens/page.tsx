import type { Metadata } from "next";
import { CircleDollarSign, Percent, RefreshCw, Tag } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { PageHeader } from "@/components/ui/page-header";
import { StatCard } from "@/components/ui/stat-card";
import { requirePermission } from "@/lib/auth/session";
import { saveMarginRuleAction } from "@/modules/margins/actions";
import { getOverview } from "@/modules/margins/service";
import { SectorCard } from "./sector-card";

export const metadata: Metadata = { title: "Margens por setor" };

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
const pick = (value: string | string[] | undefined) => (typeof value === "string" ? value : undefined);

export default async function MarginsPage({ searchParams }: { searchParams: SearchParams }) {
  // Esconder o menu não é controle de acesso: a verificação é no servidor,
  // e o RLS de `margin_rules` recusa o vendedor mesmo que ele chegue aqui.
  await requirePermission("catalog.manage");

  const params = await searchParams;
  const overview = await getOverview();
  const aplicado = pick(params.aplicado);
  const semPreco = overview.totalProdutos - overview.comPreco;

  return (
    <>
      <PageHeader
        title="Margens por setor"
        description="A regra sugere o preço; ela não o aplica sozinha. Você confere a lista antes de gravar."
      />

      {pick(params.salvo) && (
        <Alert tone="success" className="mb-4">
          Regra salva. O preço dos produtos só muda quando você aplicar.
        </Alert>
      )}
      {aplicado && (
        <Alert tone="success" className="mb-4">
          {aplicado === "0"
            ? "Nenhum produto precisou mudar de preço."
            : `Preço gravado em ${aplicado} ${aplicado === "1" ? "produto" : "produtos"}.`}
        </Alert>
      )}

      <div className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Setores" value={overview.sectors.length} icon={Tag} hint="Cada um com sua margem" />
        <StatCard
          label="Regras ativas"
          value={overview.regrasAtivas}
          icon={Percent}
          hint={overview.regrasAtivas === 0 ? "Nenhuma sugere preço ainda" : "Sugerindo preço"}
        />
        <StatCard
          label="Com preço definido"
          value={`${overview.comPreco}/${overview.totalProdutos}`}
          icon={CircleDollarSign}
          hint={semPreco > 0 ? `${semPreco} ainda sem preço de venda` : "Catálogo inteiro precificado"}
        />
        <StatCard
          label="Mudariam de preço"
          value={overview.mudariam}
          icon={RefreshCw}
          accent={overview.mudariam > 0}
          hint="Se você aplicar as regras ativas"
        />
      </div>

      {semPreco > 0 && overview.regrasAtivas === 0 && (
        <Alert tone="warning" className="mb-5" title="O catálogo ainda não tem preço de venda">
          Produto sem preço entra inativo e não pode ser usado em orçamento — é assim de propósito, para
          o sistema não vender por R$ 0,00. Defina o percentual de um setor abaixo, marque a regra como
          ativa e confira a lista antes de gravar.
        </Alert>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        {overview.sectors.map((sector) => (
          <SectorCard
            key={sector.categoryId ?? "sem-setor"}
            action={saveMarginRuleAction}
            sector={{
              categoryId: sector.categoryId,
              name: sector.name,
              description: sector.description,
              produtos: sector.produtos,
              semCusto: sector.semCusto,
              custoMin: sector.custoMin,
              custoMax: sector.custoMax,
              custoTotal: sector.custoTotal,
              tabelaTotal: sector.tabelaTotal,
              mudariam: sector.mudariam,
              rule: sector.rule
                ? {
                    mode: sector.rule.mode,
                    percent: sector.rule.percent,
                    cost_basis: sector.rule.cost_basis,
                    rounding: sector.rule.rounding,
                    is_active: sector.rule.is_active,
                  }
                : null,
            }}
          />
        ))}
      </div>
    </>
  );
}
