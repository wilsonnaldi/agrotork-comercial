import "server-only";

import { parseNfe, NfeParseError, type NfeDocument, type NfeItem } from "./nfe";
import * as repository from "./repository";
import { BusinessError } from "./service";

/**
 * O casamento entre a nota do fornecedor e o cadastro da AgroTork.
 *
 * O leitor (`nfe.ts`) não conhece o banco; o repositório não conhece a
 * nota. Este arquivo é o único lugar onde os dois se encontram, e onde
 * mora a regra que importa: COMO um item do XML vira um item da entrada.
 *
 * A ORDEM DO CASAMENTO, E POR QUE É ESSA
 *
 *   1. GTIN. O código de barras é do PRODUTO: o mesmo número em qualquer
 *      nota, de qualquer fornecedor. Quando existe, é a resposta certa.
 *   2. De-para. O código do fornecedor, apontado por uma pessoa numa
 *      nota anterior. Não é adivinhação: é memória de uma decisão.
 *   3. Nada. O item fica em aberto e a pessoa escolhe — e a escolha vira
 *      de-para para a próxima nota.
 *
 * O que NÃO existe aqui, de propósito: casamento por semelhança de
 * descrição. "BATERIA 6000" e "Bateria 6.000 mAh" são a mesma coisa para
 * uma pessoa e um chute para um algoritmo — e um chute errado aqui erra
 * o estoque e o custo de uma vez só.
 */

export type MatchOrigin = "gtin" | "memoria" | "nenhum";

export type ImportedLine = NfeItem & {
  /** Produto sugerido, quando houve casamento. */
  product_id: string | null;
  product_code: string | null;
  product_name: string | null;
  origin: MatchOrigin;
};

export type ImportPreview = {
  nfe: NfeDocument;
  supplier: { id: string; name: string } | null;
  /** Quando o fornecedor não existe, o que a nota diz sobre ele. */
  supplierFromNfe: NfeDocument["supplier"];
  lines: ImportedLine[];
  matched: number;
  pending: number;
};

export { NfeParseError };

/**
 * Lê o XML e monta a prévia. NÃO grava nada — nem a nota, nem o
 * fornecedor, nem o de-para. Gravar antes de a pessoa conferir criaria
 * rascunhos órfãos toda vez que alguém abrisse o arquivo errado.
 */
export async function previewNfe(xml: string): Promise<ImportPreview> {
  const nfe = parseNfe(xml);

  const supplier = nfe.supplier.document
    ? await repository.findSupplierByDocument(nfe.supplier.document)
    : null;

  const porGtin = new Map<string, { id: string; code: string; name: string }>();
  const gtins = nfe.items.map((item) => item.gtin).filter((g): g is string => Boolean(g));
  for (const produto of await repository.findProductsByGtin(gtins)) {
    if (produto.gtin) porGtin.set(produto.gtin, produto);
  }

  const porCodigo = new Map<string, { id: string; code: string; name: string }>();
  if (supplier) {
    for (const conhecido of await repository.knownSupplierProducts(supplier.id)) {
      porCodigo.set(conhecido.supplier_code.toUpperCase(), {
        id: conhecido.product_id,
        code: conhecido.product_code,
        name: conhecido.product_name,
      });
    }
  }

  const lines: ImportedLine[] = nfe.items.map((item) => {
    const porBarras = item.gtin ? porGtin.get(item.gtin) : undefined;
    if (porBarras) {
      return { ...item, product_id: porBarras.id, product_code: porBarras.code, product_name: porBarras.name, origin: "gtin" };
    }

    const lembrado = porCodigo.get(item.supplier_code.toUpperCase());
    if (lembrado) {
      return { ...item, product_id: lembrado.id, product_code: lembrado.code, product_name: lembrado.name, origin: "memoria" };
    }

    return { ...item, product_id: null, product_code: null, product_name: null, origin: "nenhum" };
  });

  const matched = lines.filter((l) => l.product_id !== null).length;

  return {
    nfe,
    supplier,
    supplierFromNfe: nfe.supplier,
    lines,
    matched,
    pending: lines.length - matched,
  };
}

/**
 * Confirma a importação: cria (ou reaproveita) o fornecedor, cria a nota
 * em RASCUNHO com os itens, e guarda o de-para de cada linha.
 *
 * Fica em rascunho de propósito. A pessoa acabou de mapear produtos que
 * o sistema não conhecia; obrigar uma conferência antes de o estoque e o
 * custo se mexerem é o mínimo. Dar entrada continua sendo um ato
 * separado, como em qualquer nota digitada à mão.
 */
export async function confirmImport(
  preview: ImportPreview,
  escolhas: Record<string, string>,
  conditionId: string,
  userId: string,
): Promise<string> {
  const nfe = preview.nfe;

  // Um item sem produto não vira linha da nota: o estoque não teria o que
  // movimentar, e o custo não teria onde pousar.
  const linhas = preview.lines
    .map((linha) => ({
      linha,
      product_id: escolhas[linha.supplier_code] || linha.product_id || null,
    }))
    .filter((par): par is { linha: ImportedLine; product_id: string } => par.product_id !== null);

  if (linhas.length === 0) {
    throw new BusinessError(
      "Nenhum item foi ligado a um produto do catálogo. Escolha ao menos um para importar a nota.",
    );
  }

  // O mesmo produto em duas linhas da nota quebraria o índice da entrada.
  // Acontece quando a pessoa aponta dois códigos diferentes para o mesmo
  // produto — e é melhor avisar do que gravar metade.
  const vistos = new Set<string>();
  for (const { product_id } of linhas) {
    if (vistos.has(product_id)) {
      throw new BusinessError(
        "Dois itens da nota apontam para o mesmo produto. Escolha produtos diferentes, ou some as quantidades depois.",
      );
    }
    vistos.add(product_id);
  }

  let supplierId = preview.supplier?.id ?? null;
  if (!supplierId) {
    const emitente = nfe.supplier;
    if (!emitente.legal_name) {
      throw new BusinessError("A nota não traz o nome do fornecedor. Cadastre-o antes de importar.");
    }
    supplierId = await repository.insertSupplierFromNfe(
      {
        name: emitente.legal_name,
        trade_name: emitente.trade_name,
        document: emitente.document,
        state_registration: emitente.state_registration,
        address: emitente.address,
        address_number: emitente.address_number,
        district: emitente.district,
        city: emitente.city,
        state: emitente.state,
        zip_code: emitente.zip_code,
        phone: emitente.phone,
      },
      userId,
    );
  }

  const purchaseId = await repository.insert(
    {
      supplier_id: supplierId,
      condition_id: conditionId,
      invoice_number: nfe.number ?? undefined,
      invoice_series: nfe.series ?? undefined,
      invoice_key: nfe.key ?? undefined,
      issue_date: nfe.issue_date ?? new Date().toISOString().slice(0, 10),
      freight_amount_cents: nfe.totals.freight_cents,
      other_amount_cents: nfe.totals.other_cents,
      discount_amount_cents: nfe.totals.discount_cents,
      notes: undefined,
    },
    userId,
  );

  for (const { linha, product_id } of linhas) {
    await repository.addItem(purchaseId, {
      product_id,
      quantity_milli: linha.quantity_milli,
      unit_cost_cents: linha.unit_cost_cents,
      notes: undefined,
    });

    // A memória: da próxima nota deste fornecedor, este código entra
    // sozinho. É o que faz a importação valer a pena na segunda vez.
    if (linha.supplier_code) {
      await repository.rememberSupplierProduct(
        supplierId,
        linha.supplier_code,
        product_id,
        linha.description,
      );
    }
  }

  return purchaseId;
}
