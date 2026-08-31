import type { QuoteStatus } from "@/types/db";
import type { KitComponentSnapshot } from "../types";

/**
 * O DOCUMENTO COMERCIAL do orçamento.
 *
 * É a única forma dos dados que sai do sistema para o cliente — o PDF e a
 * página pública leem exatamente esta estrutura, e nada além dela. Isso
 * garante três coisas de uma vez:
 *
 *  1. **Nunca há custo aqui.** `unit_cost_snapshot`, `product_costs` e
 *     margem não têm campo neste tipo. Não é uma regra a ser lembrada em
 *     cada tela: não existe onde colocar.
 *  2. **Nunca há observação interna.** `internal_notes` fica fora.
 *  3. **Tudo vem de snapshot.** Os campos abaixo são cópias congeladas
 *     gravadas quando o item entrou no orçamento. Montar o documento não
 *     consulta `products`, `kits` nem `kit_items` — se consultasse, um
 *     orçamento antigo mudaria de conteúdo quando o catálogo mudasse.
 */

export type DocumentCompany = {
  legal_name: string;
  trade_name: string;
  document: string | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  zip_code: string | null;
  website: string | null;
  logo_url: string | null;
};

export type DocumentCustomer = {
  name: string;
  document: string | null;
  city: string | null;
  state: string | null;
  /** Só no PDF: a página pública omite endereço, telefone e e-mail. */
  address: string | null;
  phone: string | null;
  email: string | null;
};

export type DocumentItem = {
  kind: "product" | "kit" | "custom";
  code: string | null;
  name: string;
  description: string | null;
  unit: string | null;
  brand: string | null;
  image_url: string | null;
  components: KitComponentSnapshot[] | null;
  quantity_milli: number;
  unit_price_cents: number;
  discount_percent: number;
  line_total_cents: number;
};

export type QuoteDocument = {
  number: string;
  status: QuoteStatus;
  issue_date: string;
  valid_until: string | null;
  payment_terms: string | null;
  delivery_terms: string | null;
  notes: string | null;
  owner_name: string;
  customer: DocumentCustomer;
  company: DocumentCompany;
  items: DocumentItem[];
  subtotal_cents: number;
  discount_percent: number;
  discount_amount_cents: number;
  shipping_amount_cents: number;
  total_cents: number;
  /** Validade comercial vencida — diferente de token expirado. */
  commercially_expired: boolean;
};

/** Componentes que entram na proposta: obrigatórios + opcionais escolhidos. */
export function includedComponents(item: DocumentItem): KitComponentSnapshot[] {
  return (item.components ?? []).filter((component) => component.selected);
}

/**
 * Opcionais oferecidos e NÃO escolhidos.
 *
 * Aparecem no documento numa seção à parte, rotulada como não incluída —
 * nunca junto dos itens vendidos, e nunca somados ao total. Estão no
 * snapshot desde a Fase 4 justamente para isto: mostrar ao cliente o que
 * ele pode acrescentar.
 */
export function declinedComponents(item: DocumentItem): KitComponentSnapshot[] {
  return (item.components ?? []).filter(
    (component) => !component.selected && component.item_type === "optional",
  );
}
