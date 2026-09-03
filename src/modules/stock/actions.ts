"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/session";
import { movementFormData, movementSchema, serialSchema } from "./schema";
import * as service from "./service";
import { BusinessError } from "./service";

/**
 * Fronteira entre a interface e o domínio.
 *
 * Todas estas ações são de `stock.manage` — do administrador. Ler estoque
 * é de todo mundo, e leitura não passa por action nenhuma.
 */

function voltar(productId: string, mensagem?: string): never {
  const destino = mensagem
    ? `/estoque/${productId}?erro=${encodeURIComponent(mensagem)}`
    : `/estoque/${productId}?lancado=1`;
  redirect(destino);
}

export async function registerMovementAction(formData: FormData): Promise<void> {
  await requirePermission("stock.manage");

  const parsed = movementSchema.safeParse(movementFormData(formData));
  if (!parsed.success) {
    const produto = (formData.get("product_id") as string | null) ?? "";
    voltar(produto, parsed.error.issues[0]?.message ?? "Não foi possível lançar.");
  }

  try {
    await service.registerMovement(parsed.data);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível lançar o movimento.";
    voltar(parsed.data.product_id, mensagem);
  }

  revalidatePath("/estoque");
  revalidatePath(`/estoque/${parsed.data.product_id}`);
  voltar(parsed.data.product_id);
}

export async function createSerialAction(formData: FormData): Promise<void> {
  const user = await requirePermission("stock.manage");

  const parsed = serialSchema.safeParse({
    product_id: (formData.get("product_id") as string | null) ?? "",
    serial: (formData.get("serial") as string | null) ?? "",
    notes: (formData.get("notes") as string | null) ?? "",
  });

  if (!parsed.success) {
    const produto = (formData.get("product_id") as string | null) ?? "";
    voltar(produto, parsed.error.issues[0]?.message ?? "Número de série inválido.");
  }

  try {
    await service.createSerial(parsed.data, user.id);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível cadastrar o aparelho.";
    voltar(parsed.data.product_id, mensagem);
  }

  revalidatePath(`/estoque/${parsed.data.product_id}`);
  redirect(`/estoque/${parsed.data.product_id}?serie=1`);
}

/**
 * Vincular e desvincular acontecem na ficha do PEDIDO, não na do produto:
 * é lá que a pessoa está quando separa o aparelho para entregar.
 */
export async function assignSerialAction(formData: FormData): Promise<void> {
  await requirePermission("stock.manage");

  const serialId = formData.get("serial_id");
  const orderItemId = formData.get("order_item_id");
  const orderId = formData.get("order_id");
  if (typeof serialId !== "string" || typeof orderItemId !== "string" || typeof orderId !== "string") {
    return;
  }

  try {
    await service.assignSerial(serialId, orderItemId);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível vincular o aparelho.";
    redirect(`/pedidos/${orderId}?erro=${encodeURIComponent(mensagem)}`);
  }

  revalidatePath(`/pedidos/${orderId}`);
  redirect(`/pedidos/${orderId}?serie=1`);
}

export async function releaseSerialAction(formData: FormData): Promise<void> {
  await requirePermission("stock.manage");

  const serialId = formData.get("serial_id");
  const orderId = formData.get("order_id");
  if (typeof serialId !== "string" || typeof orderId !== "string") return;

  try {
    await service.releaseSerial(serialId);
  } catch (error) {
    const mensagem =
      error instanceof BusinessError ? error.message : "Não foi possível desvincular o aparelho.";
    redirect(`/pedidos/${orderId}?erro=${encodeURIComponent(mensagem)}`);
  }

  revalidatePath(`/pedidos/${orderId}`);
  redirect(`/pedidos/${orderId}?serie=0`);
}
