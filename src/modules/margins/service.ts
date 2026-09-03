import "server-only";

import type { MarginRule } from "@/types/db";
import * as repository from "./repository";
import type { MarginChange, ProductCostRow } from "./repository";
import type { MarginRuleInput } from "./schema";

/** Regras de negócio da margem por setor. */

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

/** Um setor na tela: a categoria, sua regra e o que ela faria. */
export type Sector = {
  /** Nulo é o setor "sem categoria", atendido pela regra padrão. */
  categoryId: string | null;
  name: string;
  description: string | null;
  produtos: number;
  semCusto: number;
  custoMin: number | null;
  custoMax: number | null;
  custoTotal: number;
  /** Soma do que o catálogo valeria com a regra aplicada. */
  tabelaTotal: number;
  rule: MarginRule | null;
  /** Quantos produtos mudariam de preço se a regra fosse aplicada agora. */
  mudariam: number;
};

export type MarginOverview = {
  sectors: Sector[];
  totalProdutos: number;
  comPreco: number;
  mudariam: number;
  regrasAtivas: number;
};

function agrupar(produtos: ProductCostRow[], categoryId: string | null): ProductCostRow[] {
  return produtos.filter((p) => (p.category_id ?? null) === categoryId);
}

/**
 * Monta a tela inteira com três consultas e UM ensaio.
 *
 * O ensaio (`dryRun`) é a única fonte do preço sugerido: a aplicação não
 * recalcula margem em lugar nenhum, para não existir uma segunda conta
 * que possa divergir da do banco.
 */
export async function getOverview(): Promise<MarginOverview> {
  const [categories, rules, produtos, mudancas] = await Promise.all([
    repository.listCategories(),
    repository.listRules(),
    repository.listProductCosts(),
    repository.runMarginRules({ todas: true, dryRun: true }),
  ]);

  const sugerido = new Map(mudancas.map((m) => [m.product_id, m.preco_sugerido]));
  const ruleByCategory = new Map<string | null, MarginRule>(
    rules.map((rule) => [rule.category_id, rule]),
  );

  const montar = (categoryId: string | null, name: string, description: string | null): Sector => {
    const doSetor = agrupar(produtos, categoryId);
    const custos = doSetor.map((p) => p.custo).filter((c): c is number => c !== null);
    return {
      categoryId,
      name,
      description,
      produtos: doSetor.length,
      semCusto: doSetor.length - custos.length,
      custoMin: custos.length > 0 ? Math.min(...custos) : null,
      custoMax: custos.length > 0 ? Math.max(...custos) : null,
      custoTotal: custos.reduce((soma, c) => soma + c, 0),
      tabelaTotal: doSetor.reduce((soma, p) => soma + (sugerido.get(p.id) ?? p.sale_price), 0),
      rule: ruleByCategory.get(categoryId) ?? null,
      mudariam: doSetor.filter((p) => sugerido.has(p.id)).length,
    };
  };

  const sectors = categories.map((c) => montar(c.id, c.name, c.description));

  // O setor "sem categoria" só aparece quando existe produto nessa situação
  // ou quando alguém já configurou a regra padrão — senão é ruído na tela.
  const semSetor = agrupar(produtos, null);
  if (semSetor.length > 0 || ruleByCategory.has(null)) {
    sectors.push(
      montar(null, "Sem setor", "Produtos ainda não classificados. Atendidos pela regra padrão."),
    );
  }

  return {
    sectors: sectors.sort((a, b) => b.produtos - a.produtos || a.name.localeCompare(b.name, "pt-BR")),
    totalProdutos: produtos.length,
    comPreco: produtos.filter((p) => p.sale_price > 0).length,
    mudariam: mudancas.length,
    regrasAtivas: rules.filter((r) => r.is_active).length,
  };
}

/** Cria ou atualiza a regra do setor. Uma regra por setor, sempre. */
export async function saveRule(input: MarginRuleInput, userId: string): Promise<void> {
  const existing = await repository.findRule(input.category_id);

  // `percent` é `numeric` no banco: vai como string decimal para não
  // passar por ponto flutuante — mesma regra do custo e do preço.
  const payload = {
    mode: input.mode,
    percent: input.percent.toFixed(2),
    cost_basis: input.cost_basis,
    rounding: input.rounding,
    is_active: input.is_active,
    updated_by: userId,
  };

  if (existing) {
    await repository.updateRule(existing.id, payload);
    return;
  }
  await repository.insertRule({ ...payload, category_id: input.category_id });
}

/** Nome do setor e o que mudaria nele. Não escreve nada. */
export async function getSectorPreview(categoryId: string | null): Promise<{
  name: string;
  description: string | null;
  changes: MarginChange[];
} | null> {
  if (categoryId !== null) {
    const categories = await repository.listCategories();
    const category = categories.find((c) => c.id === categoryId);
    if (!category) return null;
    return {
      name: category.name,
      description: category.description,
      changes: await repository.runMarginRules({ categoryId, dryRun: true }),
    };
  }
  return {
    name: "Sem setor",
    description: "Produtos ainda não classificados. Atendidos pela regra padrão.",
    changes: await repository.runMarginRules({ categoryId: null, dryRun: true }),
  };
}

/** O que mudaria no setor. Não escreve nada. */
export function previewSector(categoryId: string | null): Promise<MarginChange[]> {
  return repository.runMarginRules({ categoryId, dryRun: true });
}

/**
 * Grava os preços do setor.
 *
 * Devolve o que foi efetivamente aplicado, para a tela poder dizer
 * quantos produtos mudaram em vez de só "pronto".
 */
export async function applySector(categoryId: string | null): Promise<MarginChange[]> {
  const previa = await repository.runMarginRules({ categoryId, dryRun: true });
  if (previa.length === 0) {
    throw new BusinessError("Nenhum produto mudaria de preço com a regra atual.");
  }
  return repository.runMarginRules({ categoryId, dryRun: false });
}
