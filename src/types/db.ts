/**
 * Camada de domínio dos tipos do banco.
 *
 * ────────────────────────────────────────────────────────────
 * POR QUE ESTE ARQUIVO EXISTE
 *
 * `database.types.ts` é GERADO pelo Supabase (`npm run db:types`) e é
 * sobrescrito inteiro a cada regeração. Qualquer apelido de domínio escrito
 * lá desaparece na próxima geração — foi exatamente o que aconteceu.
 *
 * Então nada de domínio mora lá. Tudo aqui é DERIVADO do `Database` gerado:
 * se uma coluna mudar de tipo, o erro aparece neste arquivo (ou em quem o
 * usa), e não em silêncio. Regerar o arquivo oficial nunca mais apaga
 * arquitetura.
 *
 * REGRA: o código da aplicação importa de `@/types/db`.
 *        Só este arquivo importa de `@/types/database.types`.
 * ────────────────────────────────────────────────────────────
 */
import type { Database, Json } from "./database.types";

export type { Database, Json };

type Public = Database["public"];
type TableRow<T extends keyof Public["Tables"]> = Public["Tables"][T]["Row"];
type ViewRow<T extends keyof Public["Views"]> = Public["Views"][T]["Row"];

/**
 * Reafirma que determinadas colunas de uma VIEW não são nulas.
 *
 * O PostgreSQL não guarda `not null` em colunas de view, então o gerador do
 * Supabase marca TODAS como anuláveis. As garantias reais vêm da definição
 * da view (coluna de origem `not null`, `join` interno, `coalesce`) e estão
 * documentadas coluna a coluna abaixo.
 *
 * Isto não é um cast: se a view perder uma coluna, `K` deixa de ser uma
 * chave válida e o TypeScript reclama aqui.
 */
type NotNull<Row, K extends keyof Row> = Omit<Row, K> & {
  [P in K]-?: NonNullable<Row[P]>;
};

/**
 * Confere, em tempo de execução, que as colunas prometidas vieram
 * preenchidas — e ENSINA isso ao TypeScript pela assinatura `asserts`.
 *
 * Não é um cast: se a view mudar e passar a devolver nulo onde não devia,
 * o sistema quebra alto, aqui, com o nome da coluna. Um `as` calaria o
 * compilador e deixaria o `undefined` chegar até o PDF do cliente.
 */
export function assertColumns<Row extends object, K extends keyof Row>(
  row: Row,
  keys: readonly K[],
  view: string,
): asserts row is Row & NotNull<Row, K> {
  for (const key of keys) {
    if (row[key] === null || row[key] === undefined) {
      throw new Error(
        `${view}.${String(key)} veio nulo, e a aplicação depende dele. ` +
          "A definição da view mudou?",
      );
    }
  }
}

// ── Enums ───────────────────────────────────────────────────
export type UserRole = Public["Enums"]["user_role"];
export type PersonType = Public["Enums"]["person_type"];
export type ItemKind = Public["Enums"]["item_kind"];
export type ProductSourceType = Public["Enums"]["product_source_type"];

/**
 * Papel do componente dentro do KIT (migration 1600).
 * `required` sempre entra; `optional` fica disponível para o vendedor
 * escolher **no orçamento**. A escolha mora em `quote_items`, nunca em
 * `kit_items` — cadastro e venda são coisas diferentes.
 */
export type KitItemType = Public["Enums"]["kit_item_type"];

/**
 * Situação do orçamento.
 * `rejected` é "o cliente disse não"; `cancelled` é "nós desistimos"
 * (entrou na migration 1700).
 */
export type QuoteStatus = Public["Enums"]["quote_status"];
export type OrderStatus = Public["Enums"]["order_status"];
export type StockReason = Public["Enums"]["stock_reason"];
export type SerialStatus = Public["Enums"]["serial_status"];
export type PurchaseStatus = Public["Enums"]["purchase_status"];
export type FinancialKind = Public["Enums"]["financial_kind"];
export type FinancialStatus = Public["Enums"]["financial_status"];

/**
 * Os mesmos valores do enum, em forma de lista, para quem precisa deles em
 * tempo de execução (Zod, `<select>`, testes).
 *
 * As duas travas abaixo impedem que a lista envelheça em silêncio quando o
 * enum mudar no banco: `satisfies` recusa um valor inventado, e
 * `QuoteStatusCoberto` só compila se TODOS os valores do enum estiverem
 * aqui. É uma migration nova que muda o enum — nunca este arquivo sozinho.
 */
export const QUOTE_STATUS_VALUES = [
  "draft",
  "sent",
  "approved",
  "rejected",
  "expired",
  "cancelled",
] as const satisfies readonly QuoteStatus[];

type QuoteStatusCoberto = Exclude<QuoteStatus, (typeof QUOTE_STATUS_VALUES)[number]> extends never
  ? true
  : ["faltou um valor de quote_status em QUOTE_STATUS_VALUES"];
const _quoteStatusCoberto: QuoteStatusCoberto = true;
void _quoteStatusCoberto;

// ── Linhas de tabela ────────────────────────────────────────
export type Profile = TableRow<"profiles">;
export type Unit = TableRow<"units">;
export type Category = TableRow<"categories">;
export type Brand = TableRow<"brands">;
export type Product = TableRow<"products">;
export type ProductCost = TableRow<"product_costs">;
export type MarginRule = TableRow<"margin_rules">;
export type Customer = TableRow<"customers">;
export type Supplier = TableRow<"suppliers">;
export type StockMovement = TableRow<"stock_movements">;
export type ProductSerial = TableRow<"product_serials">;
export type Purchase = TableRow<"purchases">;
export type PurchaseItem = TableRow<"purchase_items">;
export type FinancialEntry = TableRow<"financial_entries">;
export type FinancialPayment = TableRow<"financial_payments">;
export type Kit = TableRow<"kits">;
export type KitItem = TableRow<"kit_items">;
export type Quote = TableRow<"quotes">;
export type QuoteItem = TableRow<"quote_items">;
export type Order = TableRow<"orders">;
export type OrderItem = TableRow<"order_items">;
export type QuoteShareToken = TableRow<"quote_share_tokens">;
export type AppSetting = TableRow<"app_settings">;

// ── Projeções de lista (views) ──────────────────────────────
//
// Cada coluna listada abaixo é `not null` na origem. A justificativa está
// ao lado porque é ela que autoriza a promessa — sem isso, seria otimismo.
// A MESMA lista alimenta o tipo e a conferência em tempo de execução: não
// tem como uma envelhecer sem a outra.

/**
 * `products_list` = `products` (where deleted_at is null) + rótulos de
 * marca/categoria/unidade + custo e margem quando o RLS permitir.
 *
 * Não nulos: vêm de colunas `not null` de `products`.
 * Seguem nulos: `category_id`/`brand_id` (opcionais no cadastro), os
 * rótulos (LEFT JOIN) e `cost_price`/`margin_percent` — nulos para quem não
 * é administrador, decidido pelo RLS e não pela aplicação.
 */
const PRODUCT_LIST_COLUMNS = [
  "id",
  "code",
  "name",
  "unit_id",
  "sale_price",
  "is_active",
  "source_type",
  "technical_data",
  "created_at",
  "updated_at",
] as const satisfies readonly (keyof ViewRow<"products_list">)[];

export type ProductListRow = NotNull<
  ViewRow<"products_list">,
  (typeof PRODUCT_LIST_COLUMNS)[number]
>;

export function toProductListRow(row: ViewRow<"products_list">): ProductListRow {
  assertColumns(row, PRODUCT_LIST_COLUMNS, "products_list");
  return row;
}

/**
 * `quotes_list` = `quotes` (where deleted_at is null) com JOIN INTERNO em
 * `customers` e `profiles` — por isso `customer_name` e `owner_name` nunca
 * são nulos. `items_count` é `count(*)::integer`, que também não é nulo.
 * Seguem nulos: `valid_until` e `customer_city`.
 */
const QUOTE_LIST_COLUMNS = [
  "id",
  "number",
  "status",
  "issue_date",
  "subtotal",
  "total",
  "created_at",
  "updated_at",
  "customer_id",
  "customer_name",
  "owner_id",
  "owner_name",
  "items_count",
] as const satisfies readonly (keyof ViewRow<"quotes_list">)[];

export type QuoteListRow = NotNull<ViewRow<"quotes_list">, (typeof QUOTE_LIST_COLUMNS)[number]>;

export function toQuoteListRow(row: ViewRow<"quotes_list">): QuoteListRow {
  assertColumns(row, QUOTE_LIST_COLUMNS, "quotes_list");
  return row;
}

/**
 * `orders_list` = `orders` (where deleted_at is null) + cliente, vendedor,
 * número do orçamento de origem e contagem de itens.
 *
 * Seguem nulos: `delivery_forecast`, `customer_city`, e o par
 * `quote_id`/`quote_number` — o pedido nasce de um orçamento, mas o
 * orçamento pode ter sido apagado depois (`on delete set null`), e o
 * pedido não desaparece junto.
 */
const ORDER_LIST_COLUMNS = [
  "id",
  "number",
  "status",
  "issue_date",
  "subtotal",
  "total",
  "created_at",
  "updated_at",
  "customer_id",
  "customer_name",
  "owner_id",
  "owner_name",
  "items_count",
] as const satisfies readonly (keyof ViewRow<"orders_list">)[];

export type OrderListRow = NotNull<ViewRow<"orders_list">, (typeof ORDER_LIST_COLUMNS)[number]>;

export function toOrderListRow(row: ViewRow<"orders_list">): OrderListRow {
  assertColumns(row, ORDER_LIST_COLUMNS, "orders_list");
  return row;
}

/**
 * `financial_position` = `financial_entries` + a soma das baixas.
 *
 * `paid_amount`, `open_amount`, `is_overdue` e `days_overdue` passam por
 * `coalesce`/`case` na view — nenhum é nulo, nem para título sem
 * nenhuma baixa. `party_name` é `coalesce(cliente, fornecedor)`, e a
 * constraint da tabela garante que exatamente um dos dois existe.
 *
 * Seguem nulos: `order_number` e `purchase_number` (o documento de
 * origem pode ter sido apagado, ou o título pode ter nascido à mão).
 */
const FINANCIAL_POSITION_COLUMNS = [
  "id",
  "kind",
  "status",
  "description",
  "due_date",
  "amount",
  "installment",
  "installments",
  "created_at",
  "party_name",
  "paid_amount",
  "open_amount",
  "is_overdue",
  "days_overdue",
] as const satisfies readonly (keyof ViewRow<"financial_position">)[];

export type FinancialPositionRow = NotNull<
  ViewRow<"financial_position">,
  (typeof FINANCIAL_POSITION_COLUMNS)[number]
>;

export function toFinancialPositionRow(
  row: ViewRow<"financial_position">,
): FinancialPositionRow {
  assertColumns(row, FINANCIAL_POSITION_COLUMNS, "financial_position");
  return row;
}

/**
 * `purchases_list` = `purchases` (where deleted_at is null) com JOIN
 * INTERNO em `suppliers` e `price_conditions` — por isso `supplier_name`
 * e `condition_name` nunca são nulos. `items_count` é
 * `count(*)::integer`, que também não é nulo.
 *
 * Seguem nulos: `received_date` (a nota ainda é rascunho),
 * `invoice_number` (entrada sem nota — brinde, garantia) e
 * `supplier_city`.
 */
const PURCHASE_LIST_COLUMNS = [
  "id",
  "number",
  "status",
  "issue_date",
  "items_total",
  "total",
  "created_at",
  "updated_at",
  "supplier_id",
  "supplier_name",
  "condition_name",
  "items_count",
] as const satisfies readonly (keyof ViewRow<"purchases_list">)[];

export type PurchaseListRow = NotNull<
  ViewRow<"purchases_list">,
  (typeof PURCHASE_LIST_COLUMNS)[number]
>;

export function toPurchaseListRow(row: ViewRow<"purchases_list">): PurchaseListRow {
  assertColumns(row, PURCHASE_LIST_COLUMNS, "purchases_list");
  return row;
}

/**
 * `product_stock` = `products` (where deleted_at is null) + a SOMA do
 * livro `stock_movements`.
 *
 * `quantity` passa por `coalesce(..., 0)`: produto sem nenhum movimento
 * aparece com zero, e não some da lista — sumir esconderia justamente o
 * que ninguém contou ainda.
 *
 * Segue nulo `last_movement_at` (não há movimento), e seguem nulos
 * `category_id` e `brand_id`, que são opcionais no produto.
 */
const PRODUCT_STOCK_COLUMNS = [
  "product_id",
  "code",
  "name",
  "unit_id",
  "is_active",
  "tracks_serial",
  "quantity",
] as const satisfies readonly (keyof ViewRow<"product_stock">)[];

export type ProductStockRow = NotNull<
  ViewRow<"product_stock">,
  (typeof PRODUCT_STOCK_COLUMNS)[number]
>;

export function toProductStockRow(row: ViewRow<"product_stock">): ProductStockRow {
  assertColumns(row, PRODUCT_STOCK_COLUMNS, "product_stock");
  return row;
}

/**
 * `kits_with_price` = `kits` (where deleted_at is null) + contagens e somas
 * dos componentes. Todos os agregados passam por `coalesce(..., 0)` e
 * `suggested_price` por `round(coalesce(...))` — nenhum é nulo, nem para
 * kit sem item.
 *
 * `components_total` soma apenas os OBRIGATÓRIOS: é o preço-base do kit.
 * `optional_total` é informativo — só entra no total se o vendedor escolher.
 */
const KIT_LIST_COLUMNS = [
  "id",
  "code",
  "name",
  "discount_percent",
  "is_active",
  "created_at",
  "updated_at",
  "items_count",
  "required_count",
  "optional_count",
  "components_total",
  "optional_total",
  "suggested_price",
] as const satisfies readonly (keyof ViewRow<"kits_with_price">)[];

export type KitListRow = NotNull<ViewRow<"kits_with_price">, (typeof KIT_LIST_COLUMNS)[number]>;

export function toKitListRow(row: ViewRow<"kits_with_price">): KitListRow {
  assertColumns(row, KIT_LIST_COLUMNS, "kits_with_price");
  return row;
}

// ── Escrita de colunas `numeric` ────────────────────────────
//
// `numeric` do PostgreSQL não tem equivalente exato em JavaScript, e
// `0.1 + 0.2 !== 0.3` vira centavo errado no total de um orçamento. Por
// isso o dinheiro anda em inteiro (centavos, ou milésimos na quantidade) e
// é gravado como STRING DECIMAL — "1234.56" —, que o PostgREST repassa ao
// Postgres sem passar por ponto flutuante.
//
// O gerador do Supabase não distingue `integer` de `numeric`: os dois viram
// `number`. A lista abaixo é escrita à mão de propósito, e é conferida pelo
// TypeScript: cada coluna precisa existir na tabela e ser numérica, senão
// `NumericColumns` não compila. `sort_order`, `view_count` e afins
// continuam exigindo `number`, como devem.

type NumericColumnsByTable = {
  products: "sale_price";
  product_costs: "cost_price";
  /** Percentual da regra de margem (migration 20260903020000). */
  margin_rules: "percent";
  kits: "discount_percent";
  kit_items: "quantity";
  quotes: "discount_percent" | "discount_amount" | "shipping_amount" | "subtotal" | "total";
  quote_items:
    | "quantity"
    | "unit_price"
    | "unit_cost_snapshot"
    | "discount_percent"
    | "line_total";
  /** Pedido de venda (migration 20260903060000). Mesmo dinheiro, mesma regra. */
  orders: "discount_percent" | "discount_amount" | "shipping_amount" | "subtotal" | "total";
  order_items: "quantity" | "unit_price" | "discount_percent" | "line_total";
};

/** Trava: só é aceita como coluna decimal o que for `number` na tabela. */
type NumericColumns<T extends keyof Public["Tables"]> = T extends keyof NumericColumnsByTable
  ? Extract<NumericColumnsByTable[T], NumericKeys<TableRow<T>>>
  : never;

type NumericKeys<Row> = {
  [K in keyof Row]-?: number extends NonNullable<Row[K]> ? K : never;
}[keyof Row];

/** Aceita string decimal onde a coluna é `numeric`; o resto fica intacto. */
type AcceptsDecimalString<Payload, Decimal extends PropertyKey> = {
  [K in keyof Payload]: K extends Decimal ? Payload[K] | string : Payload[K];
};

/**
 * Colunas `not null` SEM default no banco, preenchidas por trigger BEFORE
 * INSERT. O Postgres não tem como anunciá-las, então o gerador as marca
 * como obrigatórias no `Insert` — e a aplicação nunca deve mandá-las.
 *
 * Ficam de fora do payload de propósito: escrever um número de orçamento
 * pela aplicação seria furar a sequência oficial (`next_quote_number`).
 */
type TriggerOwned = {
  /** `trg_brands_slug` -> `set_catalog_slug()` (migration 1500). */
  brands: "slug";
  /** `trg_categories_slug` -> `set_catalog_slug()` (migration 1500). */
  categories: "slug";
  /** `trg_quotes_assign_number` -> `assign_quote_number()` (migration 0600). */
  quotes: "number" | "sequence_year" | "sequence_number";
};

/** Torna opcional no `Insert` o que o trigger preenche. */
type TriggerOptional<T, Payload> = T extends keyof TriggerOwned
  ? Omit<Payload, TriggerOwned[T]> & {
      [P in TriggerOwned[T] & keyof Payload]?: Payload[P];
    }
  : Payload;

/**
 * Colunas `not null` que um trigger BEFORE INSERT preenche QUANDO chegam
 * nulas. Diferente de `TriggerOwned`: aqui a aplicação PODE informar o
 * valor — e o importador de catálogo informa, porque precisa distinguir
 * AVISTA de FATURADO. O gerador do Supabase não tem como saber disso e
 * marca a coluna como obrigatória; a lista abaixo a torna opcional.
 */
type TriggerDefaulted = {
  /**
   * `trg_product_costs_default_condition` -> `set_default_price_condition()`
   * (migration 20260902120000). Nulo vira a condição padrão (AVISTA).
   */
  product_costs: "condition_id";
};

/** Trava: só entra aqui coluna que exista no `Insert` da tabela. */
type TriggerDefaultOptional<T, Payload> = T extends keyof TriggerDefaulted
  ? Omit<Payload, TriggerDefaulted[T]> & {
      [P in TriggerDefaulted[T] & keyof Payload]?: Payload[P];
    }
  : Payload;

type WidenTable<T extends keyof Public["Tables"]> = Omit<
  Public["Tables"][T],
  "Insert" | "Update"
> & {
  Insert: TriggerDefaultOptional<
    T,
    TriggerOptional<T, AcceptsDecimalString<Public["Tables"][T]["Insert"], NumericColumns<T>>>
  >;
  Update: AcceptsDecimalString<Public["Tables"][T]["Update"], NumericColumns<T>>;
};

// ── Escrita de argumentos `numeric` em RPC ──────────────────
//
// Mesma razão das colunas: o gerador transforma `numeric` em `number`, e a
// aplicação manda string decimal para não passar por ponto flutuante. A
// lista é conferida pelo TypeScript — o argumento precisa existir na função
// e ser numérico, senão `NumericArgs` não compila.

type NumericArgsByFunction = {
  /** migration 20260902120000 — grava o custo vigente do produto. */
  set_product_cost: "p_cost_price";
  /** migration 20260903020000 — arredondamento comercial do preço. */
  round_commercial: "p_value";
};

type NumericArgKeys<Args> = {
  [K in keyof Args]-?: number extends NonNullable<Args[K]> ? K : never;
}[keyof Args];

type NumericArgs<F extends keyof Public["Functions"]> = F extends keyof NumericArgsByFunction
  ? Extract<NumericArgsByFunction[F], NumericArgKeys<Public["Functions"][F]["Args"]>>
  : never;

type WidenFunction<F extends keyof Public["Functions"]> = Omit<
  Public["Functions"][F],
  "Args"
> & {
  Args: AcceptsDecimalString<Public["Functions"][F]["Args"], NumericArgs<F>>;
};

/**
 * O `Database` que a aplicação usa: a tipagem oficial do Supabase, com a
 * única diferença de que as colunas `numeric` também aceitam string decimal
 * na escrita. A LEITURA continua exatamente como o Supabase gerou.
 *
 * É isto que evita `as any` espalhado pelos repositories.
 */
export type AppDatabase = Omit<Database, "public"> & {
  public: Omit<Public, "Tables" | "Functions"> & {
    Tables: { [T in keyof Public["Tables"]]: WidenTable<T> };
    Functions: { [F in keyof Public["Functions"]]: WidenFunction<F> };
  };
};

// ── Payloads de escrita ─────────────────────────────────────
//
// Antes, vários repositories recebiam `Partial<Brand>`, `Partial<Unit>`,
// `Partial<Customer>`. Isso é mais frouxo que o banco: aceita um insert de
// marca sem nome e só descobre o problema em produção. Os tipos abaixo são
// os do próprio Supabase — o obrigatório continua obrigatório.

type WritableTables = AppDatabase["public"]["Tables"];

type OmitTriggerOwned<T extends keyof WritableTables, Payload> = T extends keyof TriggerOwned
  ? Omit<Payload, TriggerOwned[T]>
  : Payload;


/** Payload de `insert` da tabela, sem as colunas que o trigger preenche. */
export type InsertOf<T extends keyof WritableTables> = OmitTriggerOwned<
  T,
  WritableTables[T]["Insert"]
>;

/** Payload de `update` da tabela, sem as colunas que o trigger preenche. */
export type UpdateOf<T extends keyof WritableTables> = OmitTriggerOwned<
  T,
  WritableTables[T]["Update"]
>;

// ── Travas de integridade da camada ─────────────────────────
//
// Esta camada só funciona inteira. Se `AppDatabase` deixar de ser usada nos
// clientes Supabase, ou se um merge parcial trouxer os apelidos sem a
// ampliação, o sintoma são dezenas de erros espalhados por repositories e
// páginas — sem nenhum que diga o que realmente quebrou.
//
// As travas abaixo transformam isso em UM erro, aqui, com nome. Elas não
// custam nada em tempo de execução: são só verificações de tipo.

type Trava<Condicao extends boolean, Mensagem extends string> = Condicao extends true
  ? true
  : Mensagem;

/** Coluna `numeric` precisa aceitar a string decimal que o repository envia. */
type EscritaNumericaAmpliada = Trava<
  string extends NonNullable<InsertOf<"products">["sale_price"]> ? true : false,
  "AppDatabase não está ampliando as colunas numeric: o cliente Supabase foi tipado com `Database` em vez de `AppDatabase` (ver src/lib/supabase/*.ts)."
>;

/** O número do orçamento é do trigger; o payload da aplicação não o tem. */
type NumeroDoOrcamentoEhDoTrigger = Trava<
  "number" extends keyof InsertOf<"quotes"> ? false : true,
  "InsertOf<'quotes'> ainda expõe `number`: TriggerOwned não está sendo aplicado."
>;

/** E o cliente Supabase precisa aceitar o insert sem essas três colunas. */
type ClienteAceitaOrcamentoSemNumero = Trava<
  InsertOf<"quotes"> extends AppDatabase["public"]["Tables"]["quotes"]["Insert"] ? true : false,
  "O insert de orçamento sem `number`/`sequence_*` não é aceito pelo cliente: TriggerOptional não está sendo aplicado em AppDatabase."
>;

/** As projeções de lista precisam continuar não-nulas onde a view garante. */
type ProjecaoDeListaNaoNula = Trava<
  null extends QuoteListRow["status"] ? false : true,
  "QuoteListRow.status voltou a ser anulável: a projeção de view não está sendo aplicada."
>;

const _travas: [
  EscritaNumericaAmpliada,
  NumeroDoOrcamentoEhDoTrigger,
  ClienteAceitaOrcamentoSemNumero,
  ProjecaoDeListaNaoNula,
] = [true, true, true, true];
void _travas;
