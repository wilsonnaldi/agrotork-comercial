"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { confirmImport, NfeParseError, previewNfe, type ImportPreview } from "./import-service";
import { BusinessError } from "./service";

/**
 * Fronteira da importação de NF-e.
 *
 * A prévia viaja de volta para a tela dentro do estado do formulário, e
 * volta do navegador na confirmação. Nada é gravado entre os dois passos:
 * abrir o arquivo errado não deixa rascunho órfão no banco.
 *
 * O XML tem limite de tamanho porque é arquivo de terceiro chegando pela
 * internet: uma nota real tem dezenas de KB, e recusar 2 MB é mais
 * honesto do que tentar processar o que não é nota.
 */

const LIMITE_BYTES = 2 * 1024 * 1024;

export type ImportState = {
  error?: string;
  preview?: ImportPreview;
  attempt?: number;
};

export async function previewNfeAction(
  prev: ImportState,
  formData: FormData,
): Promise<ImportState> {
  await requirePermission("purchases.manage");

  const arquivo = formData.get("xml");
  const tentativa = (prev.attempt ?? 0) + 1;

  if (!(arquivo instanceof File) || arquivo.size === 0) {
    return { error: "Escolha o arquivo XML da nota.", attempt: tentativa };
  }
  if (arquivo.size > LIMITE_BYTES) {
    return { error: "O arquivo é grande demais para ser uma NF-e.", attempt: tentativa };
  }

  let preview: ImportPreview;
  try {
    preview = await previewNfe(await arquivo.text());
  } catch (error) {
    if (error instanceof NfeParseError) {
      return { error: error.message, attempt: tentativa };
    }
    return { error: "Não foi possível ler esta nota.", attempt: tentativa };
  }

  return { preview, attempt: tentativa };
}

export async function confirmImportAction(
  prev: ImportState,
  formData: FormData,
): Promise<ImportState> {
  const user = await requirePermission("purchases.manage");
  const tentativa = (prev.attempt ?? 0) + 1;

  const bruto = formData.get("preview");
  if (typeof bruto !== "string" || bruto === "") {
    return { error: "A conferência expirou. Envie o arquivo de novo.", attempt: tentativa };
  }

  let preview: ImportPreview;
  try {
    preview = JSON.parse(bruto) as ImportPreview;
  } catch {
    return { error: "A conferência expirou. Envie o arquivo de novo.", attempt: tentativa };
  }

  const conditionId = formData.get("condition_id");
  if (typeof conditionId !== "string" || !conditionId) {
    return { preview, error: "Escolha a condição de pagamento.", attempt: tentativa };
  }

  // Uma escolha por linha, indexada pelo código do fornecedor — que é o
  // que identifica a linha dentro da nota.
  const escolhas: Record<string, string> = {};
  for (const [chave, valor] of formData.entries()) {
    if (chave.startsWith("produto:") && typeof valor === "string" && valor) {
      escolhas[chave.slice("produto:".length)] = valor;
    }
  }

  let purchaseId: string;
  try {
    purchaseId = await confirmImport(preview, escolhas, conditionId, user.id);
  } catch (error) {
    // A prévia volta no estado, e não `prev`: quem errou acabou de
    // apontar doze produtos à mão, e perder isso por uma condição de
    // pagamento em branco seria cruel.
    if (error instanceof BusinessError) {
      return { preview, error: error.message, attempt: tentativa };
    }
    const mensagem = error instanceof Error ? error.message : "";
    if (mensagem.includes("idx_purchases_invoice")) {
      return {
        preview,
        error: "Esta nota deste fornecedor já foi lançada. Procure por ela na listagem de entradas.",
        attempt: tentativa,
      };
    }
    return { preview, error: "Não foi possível importar a nota.", attempt: tentativa };
  }

  revalidatePath("/compras");
  redirect(`/compras/${purchaseId}?importada=1`);
}
