# BANCO DE DADOS — Sistema Comercial AGROTORK

Banco: **PostgreSQL 15+** (Supabase)
Fonte da verdade do schema: `supabase/migrations/` (SQL versionado)
Versão deste documento: 1.0 — 29/08/2026

---

## 1. Convenções

| Regra | Valor |
| --- | --- |
| Nomes | `snake_case`, tabelas no plural, em inglês |
| Chave primária | `id uuid primary key default gen_random_uuid()` |
| Datas | `timestamptz` (sempre com fuso), `default now()` |
| Auditoria | `created_at`, `updated_at` (trigger), `created_by`, `updated_by` |
| Exclusão | **Soft delete** via `deleted_at timestamptz` nos cadastros |
| Dinheiro | `numeric(14,2)` — nunca `float`/`real` |
| Percentual | `numeric(7,4)` (ex.: `12.5000` = 12,5 %) |
| Booleano de estado | `is_active boolean not null default true` |
| Segurança | **RLS habilitado em todas as tabelas**, sem exceção |

---

## 2. Diagrama de relacionamentos

```
                       auth.users (Supabase)
                             │ 1:1
                             ▼
                        profiles ──────────────┐
                             │                 │
              created_by     │                 │ owner_id
        ┌────────────────────┼─────────────┐   │
        ▼                    ▼             ▼   ▼
   categories            customers        quotes ────────┐
        │                    ▲               │           │
        │ 1:N                └───────────────┘ N:1       │ 1:N
        ▼                                                ▼
    products ◀── N:1 ── brands                     quote_items
        ▲   ▲                                            │
        │   └── N:1 ── units                             │ product_id / kit_id
        │                                                │ (referência histórica)
        │ 1:N                                            │
        ▼                                                │
    kit_items ──── N:1 ────▶ kits ◀─────────────────────┘
                                 │
                                 └── N:1 ── categories

    quotes 1:N quote_share_tokens        (links públicos com validade)
```

---

## 3. Tipos enumerados

```sql
create type user_role   as enum ('admin', 'salesperson');
create type quote_status as enum ('draft', 'sent', 'approved', 'rejected', 'expired', 'cancelled');
-- 'cancelled' entrou na migration 1700: 'rejected' é o cliente dizendo não;
-- 'cancelled' é desistência nossa. Relatórios diferentes.
create type person_type  as enum ('individual', 'company');   -- CPF / CNPJ
create type item_kind    as enum ('product', 'kit', 'custom');

-- Procedência do cadastro do produto (migration 1300)
create type product_source_type as enum (
  'manual', 'manufacturer_catalog', 'price_list', 'test_data'
);
```

Novos papéis entram com `alter type user_role add value 'manager';` — sem
migração de dados.

**Rótulos em português** ficam na aplicação (`src/config/labels.ts`), não no
banco. O banco guarda o valor canônico.

---

## 4. Tabelas

### 4.1 `profiles` — usuários do sistema
Espelha `auth.users`, guarda o que é do negócio.

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | = `auth.users.id` (FK, `on delete cascade`) |
| `full_name` | `text` not null | |
| `email` | `text` not null unique | |
| `phone` | `text` | |
| `role` | `user_role` not null default `'salesperson'` | |
| `is_active` | `boolean` not null default `true` | desativar sem excluir |
| `created_at` / `updated_at` | `timestamptz` | |

Criado automaticamente por trigger `on auth.users insert`.
Índices: `idx_profiles_role`.

---

### 4.2 `customers` — clientes

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `person_type` | `person_type` not null default `'company'` | |
| `name` | `text` not null | Nome / Razão Social |
| `trade_name` | `text` | Nome fantasia |
| `document` | `text` | CPF ou CNPJ, **só dígitos** |
| `state_registration` | `text` | Inscrição estadual |
| `phone` | `text` | |
| `whatsapp` | `text` | |
| `email` | `text` | |
| `address` / `address_number` / `address_complement` | `text` | |
| `district` | `text` | Bairro |
| `city` | `text` | |
| `state` | `char(2)` | UF |
| `zip_code` | `text` | CEP, só dígitos |
| `notes` | `text` | Observações |
| `is_active` | `boolean` default `true` | |
| `created_by` / `updated_by` | `uuid` → `profiles` | |
| `created_at` / `updated_at` / `deleted_at` | `timestamptz` | |

Índices: `unique (document) where document is not null and deleted_at is null`;
busca por nome com `pg_trgm` (`idx_customers_name_trgm`); `idx_customers_city`.

> **Histórico do cliente:** não existe tabela separada. O histórico é montado por
> consulta sobre `quotes` (e, no futuro, `orders`, `interactions`, `invoices`),
> todas com FK para `customers.id`. Nada precisa ser reestruturado depois.

---

### 4.3 `units` — unidades de medida (configurável)

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `code` | `text` not null unique | `UN`, `KG`, `L`, `M`, `JG`, `HR`, `SERV` |
| `name` | `text` not null | "Unidade", "Quilograma"… |
| `allows_fraction` | `boolean` default `false` | KG e L aceitam 0,5 |
| `is_active` | `boolean` default `true` | |
| `sort_order` | `integer` default `0` | |

Índices: `unique (upper(code))`; `idx_units_active_code (is_active, sort_order, code)`.

Populada por *seed*, **não fixa no código**. O admin cadastra novas em
**Configurações → Unidades de medida**.

> O **código** é a identidade da unidade. `L` e `LT` são unidades **diferentes**
> enquanto ninguém decidir que são equivalentes — o sistema não presume nada a
> respeito. Por isso o *nome* não é único: "Litro" pode existir em mais de um
> código.

`units` não tem exclusão lógica: unidade não se apaga, se desativa. E o banco
recusa apagar fisicamente uma unidade com produto vinculado (`on delete restrict`).

---

### 4.4 `categories` — categorias de produto

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `name` | `text` not null | |
| `slug` | `text` unique | |
| `parent_id` | `uuid` → `categories` | permite subcategoria no futuro |
| `description` | `text` | |
| `is_active` | `boolean` default `true` | |
| `sort_order` | `integer` | |

Índices: `unique (lower(name)) where deleted_at is null` — "Peças" e "PEÇAS" são
a mesma categoria; `idx_categories_active_name`.
O `slug` é preenchido pelo trigger `set_catalog_slug()` (migration 1500), a
partir do nome; nenhum insert precisa calculá-lo.

Seed: Implementos, Peças, Pulverização, Tecnologia, Agricultura de Precisão,
Serviços, Acessórios. **Editáveis** em **Configurações → Categorias.**

---

### 4.5 `brands` — marcas

> **Marca é a marca comercial que identifica o produto.** Não é fornecedor,
> não é distribuidor, não é fabricante. Esses são conceitos distintos e, quando
> forem necessários, entram como cadastros próprios — nada no modelo atual
> impede isso.

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `name` | `text` not null | único por `lower(name)` (migration 1500) |
| `description` | `text` | migration 1500 |
| `slug` | `text` unique | preenchido pelo trigger `set_catalog_slug()` |
| `logo_url` | `text` | Supabase Storage — envio ainda não implementado |
| `website` | `text` | |
| `is_active` | `boolean` default `true` | |

Índices: `unique (lower(name)) where deleted_at is null`; `idx_brands_active_name`.

Seed: AGROTORK, DJI, KUHN, BALDAN, ARAG, MAGNOJET, TRIMBLE, AGRES.
**Lista não definitiva** — admin cadastra, edita e desativa em
**Configurações → Marcas**.

#### Desativar um cadastro de apoio

Vale igualmente para marcas, categorias e unidades:

- o produto já vinculado **continua vinculado**; nada é apagado nem alterado;
- o registro deixa de ser oferecido em cadastros novos — recusa feita **no
  serviço, no servidor** (`products/service.ts`), não apenas escondendo a opção
  na tela;
- trocar a referência de um produto para um registro inativo é recusado; manter
  a que ele já tinha, não — desativar não invalida o que existe;
- exclusão física é recusada pelo banco enquanto houver produto vinculado
  (`on delete restrict`);
- o vendedor **lê** um cadastro desativado (precisa dele para abrir a ficha de um
  produto antigo); só o admin escreve, e é o RLS que garante isso.

---

### 4.6 `products` — produtos

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `code` | `text` not null unique | código interno |
| `name` | `text` not null | |
| `description` | `text` | |
| `category_id` | `uuid` → `categories` | `on delete restrict` |
| `brand_id` | `uuid` → `brands` | `on delete restrict` |
| `unit_id` | `uuid` → `units` not null | `on delete restrict` |
| `manufacturer_code` | `text` | **código original de fábrica** — chave de correspondência com catálogos e tabelas de preço |
| `sale_price` | `numeric(14,2)` not null default `0` | preço de venda |
| `source_type` | `product_source_type` not null default `'manual'` | `manual` · `manufacturer_catalog` · `price_list` · `test_data` |
| `source_brand` | `text` | fabricante de origem (ex.: `AGRES`) |
| `source_catalog` | `text` | catálogo de origem (ex.: `AGRIS 2026`) |
| `source_version` | `text` | versão/edição do catálogo |
| `source_reference` | `text` | página, linha ou arquivo de origem |
| `source_imported_at` | `timestamptz` | quando foi importado |
| `technical_data` | `jsonb` not null default `{}` | características do catálogo. **Nunca contém preço** |
| `image_url` | `text` | Storage, bucket `product-images` |
| `notes` | `text` | |
| `is_active` | `boolean` default `true` | |
| `created_by` / `updated_by` / timestamps / `deleted_at` | | |

> **O custo NÃO fica aqui.** Ver `product_costs` (§4.7) — foi separado na
> migration `1200` para que o RLS possa escondê-lo do vendedor. A margem
> deixou de ser coluna gerada e passou a ser derivada na view `products_list`.

Índices: `unique(code) where deleted_at is null`,
`unique (brand_id, upper(manufacturer_code)) where manufacturer_code is not null`,
`idx_products_category`, `idx_products_brand`, `idx_products_active`,
`idx_products_name_trgm`, `idx_products_code_trgm`, `idx_products_active_name`.

Restrição: `check (manufacturer_code is null or brand_id is not null)` — código
de fabricante sem fabricante não identifica nada.

> **Código do fabricante é único por MARCA, não globalmente.** Dois fabricantes
> podem usar a mesma numeração; o mesmo fabricante, não. É essa unicidade que
> permite à futura importação de catálogos e de tabelas de preço casar linhas
> com segurança.

> **Massa de teste.** Produtos com `source_type = 'test_data'` vêm das planilhas
> internas (AGROTORK 23 e afins) e **não são catálogo oficial**. Saem com
> `select public.purge_test_products();` — os kits de teste saem junto e os
> itens de orçamento preservam o snapshot congelado.

---

### 4.7 `product_costs` — custo do produto *(somente administrador)*

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `product_id` | `uuid` PK | FK → `products`, `on delete cascade` |
| `cost_price` | `numeric(14,2)` not null default `0` | `check (>= 0)` |
| `updated_by` | `uuid` → `profiles` | |
| `created_at` / `updated_at` | `timestamptz` | |

**Por que uma tabela separada.** O PostgreSQL não filtra *coluna* por papel de
aplicação: enquanto o custo era coluna de `products`, qualquer usuário
autenticado que chamasse a API direto conseguia lê-lo — esconder na interface
não era proteção. Com o custo em tabela própria, a policy de RLS resolve:
`product_costs` só aceita `is_admin()`.

A margem acompanha o custo (é informação derivada dele) e por isso também
deixou de existir em `products`. As duas aparecem na view `products_list`,
que faz `left join` em `product_costs` — para o vendedor o join simplesmente
não encontra a linha, e as colunas chegam **nulas**. Nenhum `if` de aplicação
envolvido.

Coberto por `supabase/db-tests/05_custo_produto.sql`.

### View `products_list`

Produto + rótulos de marca, categoria e unidade + custo e margem quando
permitido. É o que a listagem e a ficha consultam. `security_invoker = true`,
então o RLS vale para quem consulta.

---

### 4.7 `kits` — kits comerciais

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `code` | `text` not null unique | |
| `name` | `text` not null | |
| `description` | `text` | |
| `category_id` | `uuid` → `categories` | |
| `image_url` | `text` | |
| `discount_percent` | `numeric(7,4)` default `0` | desconto padrão do kit |
| `is_active` | `boolean` default `true` | |
| timestamps / auditoria | | |

`unique (upper(code)) where deleted_at is null`.

O preço **não é armazenado**: é derivado de `kit_items` pela view
`kits_with_price`. Desde a migration 1600 a view separa o que é base do que é
opção:

| Coluna da view | Significado |
| --- | --- |
| `items_count` | todos os componentes |
| `required_count` / `optional_count` | quantos de cada papel |
| `components_total` | **soma apenas dos obrigatórios** — o preço-base do kit |
| `optional_total` | soma dos opcionais; informativo, não entra na base |
| `suggested_price` | `components_total` menos `discount_percent` |

Derivar em vez de armazenar evita preço de kit desatualizado quando um
componente muda de preço. **Não existe preço comercial próprio do kit**: se um
dia for preciso um valor fechado, independente da soma dos componentes, será
coluna nova e decisão explícita. No orçamento o usuário poderá sobrescrever o
valor final — e essa sobrescrita fica congelada em `quote_items`.

A view nunca toca `product_costs`: custo não passa pelo módulo de kits para
usuário nenhum.

**Kit vazio é permitido.** O cadastro é em dois passos — o kit precisa existir
para receber componentes. Um kit com `required_count = 0` é *incompleto*:
aparece marcado na interface e não será oferecido em orçamento (Fase 4).

---

### 4.8 `kit_items` — componentes do kit

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `kit_id` | `uuid` → `kits` not null | `on delete cascade` |
| `product_id` | `uuid` → `products` not null | `on delete restrict` |
| `quantity` | `numeric(14,3)` not null default `1` | `check (quantity > 0)` |
| `item_type` | `kit_item_type` not null default `'required'` | migration 1600 |
| `sort_order` | `integer` default `0` | |
| `notes` | `text` | |

`unique (kit_id, product_id)`. Índices `idx_kit_items_kit` e
`idx_kit_items_kit_type (kit_id, item_type, sort_order)`.

#### `item_type` — obrigatório × opcional

| Valor | Significado |
| --- | --- |
| `required` | sempre entra quando o kit for usado; o vendedor não tira |
| `optional` | fica **disponível** para o vendedor escolher no orçamento |

> **A distinção que importa.** `item_type = 'optional'` é **cadastro**: diz o
> que *pode* ser escolhido. O que o vendedor *escolheu* numa venda vai para
> `quote_items` — outra tabela, outro momento, outro dono. Marcar um item como
> opcional não o coloca em orçamento nenhum, e escolher opcionais num orçamento
> não altera este cadastro.

**Um produto entra uma vez por kit.** O `unique (kit_id, product_id)` de 0500
vale como regra de negócio: o mesmo produto não pode ser obrigatório *e*
opcional no mesmo kit. Conferido contra as 14 páginas de kit do catálogo
Tecomec 2026 — nenhum kit real repete produto entre os dois grupos, então a
restrição não precisou de exceção.

**Fração respeita a unidade.** `quantity` é `numeric(14,3)`, mas o serviço
recusa fração quando a unidade do produto não aceita (UN, PC, JG) — é a regra
dos cadastros de apoio da Fase 1 valendo aqui.

**Produto desativado.** O banco mantém o vínculo: um kit que já usava o produto
continua íntegro. O que a aplicação recusa é *associação nova* com produto
inativo — regra em `kits/service.ts`, verificada no servidor, com teste que
força o campo no HTML para provar que a proteção não está na tela.

---

### 4.9 `quotes` — orçamentos *(módulo principal)*

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `number` | `text` not null unique | `ORC-2026-0001`, gerado no banco |
| `sequence_year` / `sequence_number` | `integer` | base da numeração |
| `customer_id` | `uuid` → `customers` not null | `on delete restrict` |
| `owner_id` | `uuid` → `profiles` not null | vendedor responsável |
| `status` | `quote_status` not null default `'draft'` | `draft` · `sent` · `approved` · `rejected` · `expired` · `cancelled` |
| `issue_date` | `date` not null default `current_date` | |
| `valid_until` | `date` | validade da proposta |
| `delivery_terms` | `text` | prazo de entrega (migration 1700) |
| `payment_terms` | `text` | condição de pagamento |
| `discount_percent` | `numeric(7,4)` default `0` | desconto geral (%) |
| `discount_amount` | `numeric(14,2)` default `0` | desconto geral (R$) |
| `shipping_amount` | `numeric(14,2)` default `0` | frete (preparado) |
| `subtotal` | `numeric(14,2)` not null default `0` | soma dos itens |
| `total` | `numeric(14,2)` not null default `0` | valor final |
| `notes` | `text` | observações do orçamento |
| `internal_notes` | `text` | nunca sai no PDF |
| `sent_at` / `approved_at` / `rejected_at` | `timestamptz` | |
| timestamps / auditoria | | |

`subtotal` e `total` são **recalculados por trigger** a cada alteração de item
ou de desconto — o total nunca depende do front-end.

Índices: `idx_quotes_customer`, `idx_quotes_owner`, `idx_quotes_status`,
`idx_quotes_issue_date desc`, `unique(number)`.

**Numeração:** tabela `quote_sequences (year int pk, last_number int)` +
função `next_quote_number()` com `update ... returning` dentro da transação —
concorrência resolvida pelo próprio Postgres.

**Expiração:** orçamentos com `valid_until < current_date` e status `sent` são
marcados `expired` pela função `expire_quotes()`. A comparação é `<`: no
próprio dia da validade o orçamento ainda vale. `valid_until` nulo nunca
expira. A função ignora descartados (`deleted_at`) e não toca em `draft`,
`approved`, `rejected`, `cancelled` nem no que já está `expired` — rodar duas
vezes seguidas devolve 0 e não altera nada.

Quem a chama é o job `expirar-orcamentos` do **pg_cron** (`5 3 * * *`,
03h05 UTC = 00h05 em Brasília), agendado pela migration
`20260901052525_expire_quotes_schedule.sql` — que também cria o índice
parcial `idx_quotes_expiration (valid_until) where deleted_at is null and
status = 'sent'`. O agendamento só acontece se a extensão já estiver
instalada; enquanto o `pg_cron` não for habilitado no painel, a migration
passa como no-op e a expiração continua dependendo de ação manual. Ver
SETUP.md §9.

---

### 4.10 `quote_items` — itens do orçamento *(preços congelados)*

Esta é a tabela que garante a regra: **um orçamento antigo nunca muda.**

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `quote_id` | `uuid` → `quotes` not null | `on delete cascade` |
| `kind` | `item_kind` not null | `product` \| `kit` \| `custom` |
| `product_id` | `uuid` → `products` | **referência histórica**, `on delete set null` |
| `kit_id` | `uuid` → `kits` | idem |
| `code_snapshot` | `text` | cópia do código |
| `name_snapshot` | `text` not null | cópia do nome |
| `description_snapshot` | `text` | |
| `unit_snapshot` | `text` | cópia do código da unidade |
| `brand_snapshot` | `text` | |
| `image_url_snapshot` | `text` | para o PDF com fotos (futuro) |
| `quantity` | `numeric(14,3)` not null default `1` | `check (> 0)` |
| `unit_price` | `numeric(14,2)` not null | preço praticado |
| `unit_cost_snapshot` | `numeric(14,2)` | **sempre nulo hoje** — ver abaixo |
| `discount_percent` | `numeric(7,4)` default `0` | desconto do item |
| `line_total` | `numeric(14,2)` **gerada** | `qty × price × (1 − desc/100)` |
| `components_snapshot` | `jsonb` | composição do kit no momento |
| `sort_order` | `integer` | |
| `notes` | `text` | |

```sql
line_total numeric(14,2) generated always as (
  round(quantity * unit_price * (1 - coalesce(discount_percent,0)/100), 2)
) stored
```

`check` de referência, na forma que a migration 1400 deixou — impede
referência cruzada e permite que a referência fique nula quando o cadastro de
origem é excluído:

```sql
check ( (kind='product' and kit_id is null)
     or (kind='kit'     and product_id is null)
     or (kind='custom'  and product_id is null and kit_id is null) )
```

Índices: `idx_quote_items_quote (quote_id, sort_order)`, `idx_quote_items_product`,
`idx_quote_items_kit`.

#### `components_snapshot` — a composição do kit congelada

Guarda **todos** os componentes, inclusive os opcionais que o vendedor recusou:

```json
[
  {"product_id":"…","code":"P-001","name":"Bico AD 110-02","unit":"UN",
   "brand":"ARAG","quantity_milli":1000,"unit_price_cents":15000,
   "item_type":"required","selected":true},
  {"product_id":"…","code":"P-002","name":"Mangueira 3/4\"","unit":"M",
   "brand":"MAGNOJET","quantity_milli":1000,"unit_price_cents":3200,
   "item_type":"optional","selected":false}
]
```

- `item_type` é o papel **no cadastro do kit naquele dia**; se o cadastro mudar
  depois, o orçamento continua mostrando o papel de então.
- `selected` é a escolha do vendedor **nesta venda**. Obrigatório é sempre
  `true`.
- `quantity_milli` é a quantidade **por unidade do kit**; a efetiva é ela vezes
  `quote_items.quantity`.
- `unit_price` da linha do kit = soma dos componentes com `selected = true`.

#### Por que `unit_cost_snapshot` continua nulo

Preencher o custo do item exporia o custo ao vendedor: `quote_items` é legível
por quem é dono do orçamento, e o PostgreSQL não filtra COLUNA por papel de
aplicação — foi exatamente o motivo de o custo ter ido para `product_costs` na
migration 1200. Capturar custo histórico para relatório de margem exigirá o
mesmo tratamento (tabela própria com RLS de administrador) e é decisão da fase
de relatórios.

#### Totais: quem calcula é o banco

`line_total` é coluna gerada; `recalculate_quote_totals()` roda por trigger a
cada mudança de item e a cada mudança de desconto ou frete do orçamento:

```
total = greatest( subtotal
                  − round(subtotal × discount_percent/100, 2)
                  − discount_amount
                  + shipping_amount , 0 )
```

O piso em zero mais os `check` da migration 1700 (`subtotal >= 0`,
`total >= 0`) garantem que nenhum caminho produza valor negativo. A aplicação
nunca envia subtotal nem total.

---

### 4.11 `quote_share_tokens` — compartilhamento público

| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `quote_id` | `uuid` → `quotes` not null | `on delete cascade` |
| `token` | `text` not null unique | `encode(gen_random_bytes(24),'hex')` — 48 hex, gerado pelo banco |
| `expires_at` | `timestamptz` | validade TÉCNICA do link |
| `revoked_at` | `timestamptz` | revogação; a linha nunca é apagada |
| `view_count` | `integer` default `0` | único efeito colateral do acesso público |
| `created_by` / `created_at` | | |

Índices: `unique (token)`, `idx_share_tokens_quote`, `idx_share_tokens_live`.

#### Leitura pública: `get_shared_quote(token)` (migration 1900)

O papel `anon` **não tem policy** em `quotes` nem em `quote_items`, e isso não
mudou na Fase 5. Quem lê pelo link é uma função `security definer` que recebe o
token e devolve `jsonb` com os campos comerciais:

| Devolve | Não devolve |
| --- | --- |
| número, situação, datas, condições, observações | `internal_notes` |
| itens com snapshot e `components_snapshot` | `unit_cost_snapshot`, custo, margem |
| totais gravados (como **texto**, para não passar por float) | `owner_id`, `customer_id`, qualquer id |
| nome do cliente, CNPJ/CPF, cidade/UF | telefone e e-mail do cliente |
| nome do vendedor e dados da empresa | |

Devolve `null` — que a aplicação transforma em 404 — para token inexistente,
revogado, expirado, de orçamento descartado ou de orçamento cuja situação não
circula (`quote_is_shareable`: `sent`, `approved`, `expired`). Todos os casos
respondem igual, para não confirmar a existência de nada.

A **escrita** (gerar e revogar) continua na tabela, sob a policy `share_tokens_all`
de 0800: administrador ou dono do orçamento. Revogar é
`update ... set revoked_at = now()`, e funciona como update comum porque
nenhuma policy filtra `revoked_at` — ao contrário do `deleted_at` de `quotes`,
que precisou da migration 1800.

> **Validade do token ≠ validade da proposta.** O token expirado não abre. A
> proposta com `valid_until` vencido **abre com aviso** — o cliente que clica
> num link antigo precisa ver o que foi proposto. O token nasce com a validade
> comercial do orçamento; sem ela, 30 dias.

---

### 4.12 `app_settings` — parâmetros da empresa

Chave/valor (`jsonb`) para dados da empresa, texto padrão de condição de
pagamento, validade padrão, termos comerciais e dados bancários (usados no PDF).
Somente `admin` lê e escreve.

---

### 4.13 `audit_log` — trilha de auditoria *(somente administrador)*

Registro **somente-anexação** de quem fez o quê, quando, em qual registro e com
qual mudança de estado. Não é histórico comercial: é evidência.

| Grupo | Colunas |
| --- | --- |
| Quando | `id bigint identity`, `occurred_at` |
| Quem | `actor_kind` (`user`/`system`/`anonymous`/`unknown`), `actor_user_id`, `actor_email`, `actor_name`, `actor_role`, `actor_db_role` |
| O quê | `action` (`quote.approved`, `user.role_changed`…), `operation` |
| Onde | `entity_type`, `entity_id` (**texto**), `entity_label`, `parent_type`, `parent_id` |
| Mudança | `changed_fields`, `old_data`, `new_data` |
| Extra | `metadata` (`txid` e tabela de origem) |

**Sem chave estrangeira nenhuma**, de propósito: uma FK faria apagar um
orçamento apagar (ou travar) a prova de que ele existiu, e apagar um usuário
levaria o rastro dele junto. Por isso o ator vai denormalizado — nome, e-mail e
papel **congelados no instante do fato**. `entity_id` é `text` porque
`app_settings` tem chave primária textual.

**Captura por trigger**, nunca pela aplicação: a expiração vem do pg_cron (sem
sessão), a troca de papel vem do SQL Editor (sem tela), e o PostgREST não
permite à aplicação anexar contexto a uma escrita. Uma única função,
`audit_capture()`, atende as 13 tabelas auditadas — `profiles`, `customers`,
`products`, `product_costs`, `kits`, `kit_items`, `quotes`, `quote_items`,
`quote_share_tokens`, `app_settings`, `units`, `categories`, `brands`. Fora:
`quote_sequences` (contador interno) e `auth.*` (onde moram senha, tokens e
sessões).

O que **não** vira evento: colunas derivadas (`subtotal`, `total`, `line_total`)
— sem isso, cada item adicionado geraria um `quote.updated` fantasma —,
`updated_at`/`updated_by`, e `view_count` do link público. Quando o diff fica
vazio, nenhuma linha é gravada. O `token` de `quote_share_tokens` é gravado como
`[REDIGIDO]` **na escrita**, não na leitura.

**Acesso:** `revoke all` de `public`, `anon`, `authenticated` e `service_role`;
só `select` volta, e a única policy exige `is_admin()`. Nem administrador
escreve: não existe policy de INSERT/UPDATE/DELETE. Três triggers
(`before update`, `before delete`, `before truncate`) recusam alteração
inclusive para o **dono da tabela**, que o `revoke` não alcança.

> **Pendência conhecida (LGPD):** o log sobrevive à exclusão do cliente. Nome,
> CPF/CNPJ, telefone e endereço permanecem em `old_data` depois de o cliente ser
> apagado. É a tensão clássica entre trilha de auditoria e direito de
> eliminação. Se um dia existir rotina de esquecimento, ela terá de percorrer o
> log também.

Índices: `(entity_type, entity_id, occurred_at desc)`, `(actor_user_id,
occurred_at desc)` parcial, `(occurred_at desc)`. Sem retenção automática —
expurgo é mecanismo que apaga prova e fica como decisão explícita, a revisar
por volta de 100 mil linhas.

---

## 5. Row Level Security — resumo das políticas

| Tabela | admin | salesperson |
| --- | --- | --- |
| `profiles` | tudo | lê todos (nome do vendedor), edita só o próprio |
| `customers` | tudo | lê todos, cria e edita |
| `categories`, `brands`, `units` | tudo | somente leitura (ativos) |
| `products`, `kits`, `kit_items` | tudo | somente leitura (ativos) |
| `product_costs` | tudo | **sem acesso**: custo e margem chegam nulos |
| `quotes` | tudo | lê/edita apenas `owner_id = auth.uid()`; cria como dono; não edita `approved` |
| `quote_items` | tudo | apenas de orçamentos próprios **e não aprovados** |
| `quote_share_tokens` | tudo | apenas de orçamentos próprios |
| `app_settings` | tudo | lê apenas a chave `company` |
| `audit_log` | **somente leitura** | **sem acesso** — nem dos próprios orçamentos |
| `quote_sequences` | — | sem policy: ninguém acessa direto |

Funções auxiliares (`security definer`, `search_path` fixo):

```sql
create function public.auth_role() returns user_role ...
create function public.is_admin() returns boolean ...
create function public.is_active_user() returns boolean ...
create function public.owns_quote(uuid) returns boolean ...
create function public.quote_is_editable(uuid) returns boolean ...
```

### Trava do orçamento aprovado

Orçamento com status `approved` só é editado por `admin`. Isso vale para a
tabela `quotes` **e para `quote_items`** — a checagem em `quotes` sozinha não
bastava: o vendedor conseguia alterar o preço de um item ou apagá-lo, e o
trigger recalculava o total de uma proposta já aceita. Corrigido em
`20260829001100_rls_hardening.sql` via `quote_is_editable()`, com regressão em
`supabase/db-tests/04_travas_de_orcamento.sql`.

### Usuário desativado

`profiles_update_self` exige `is_active_user()` na leitura e na escrita, e
impede troca de `role`. Um usuário desativado não se reativa nem se promove,
mesmo com token válido em mãos.

---

## 6. Storage (Supabase)

| Bucket | Público | Conteúdo |
| --- | --- | --- |
| `product-images` | sim (leitura) | fotos de produto |
| `kit-images` | sim (leitura) | fotos de kit |
| `brand-logos` | sim (leitura) | logotipos |
| `company-assets` | sim (leitura) | logo AGROTORK para o PDF |

Escrita apenas por usuário autenticado; `admin` para produtos, kits e marcas.

---

## 7. Migrations

```
supabase/migrations/
├─ 20260829000100_extensions.sql       # pgcrypto, pg_trgm, unaccent
├─ 20260829000200_enums_helpers.sql    # enums, set_updated_at(), helpers
├─ 20260829000300_profiles.sql         # profiles + trigger de auth.users
├─ 20260829000400_catalog.sql          # units, categories, brands, products
├─ 20260829000500_kits.sql             # kits, kit_items, view de preço
├─ 20260829000600_quotes.sql           # sequences, quotes, quote_items, triggers
├─ 20260829000700_sharing_settings.sql # tokens públicos, app_settings
├─ 20260829000800_rls.sql              # todas as policies
├─ 20260829000900_seed.sql             # unidades, categorias e marcas iniciais
├─ 20260829001000_grants.sql           # privilégios explícitos + revoke das funções administrativas
├─ 20260829001100_rls_hardening.sql    # trava dos itens do orçamento aprovado, perfil, índices de FK
├─ 20260829001200_product_costs.sql    # custo isolado com RLS de admin, view products_list, índices
├─ 20260829001300_product_origin.sql   # código do fabricante, procedência, dados técnicos, purge da massa de teste
├─ 20260829001400_quote_item_reference.sql # corrige o check que impedia excluir produto usado em orçamento
├─ 20260829001500_catalog_registers.sql # brands.description, slug por trigger, nome único, índices de listagem
├─ 20260829001600_kit_item_type.sql   # item obrigatório/opcional do kit, preço-base na view, FK de kit no orçamento
├─ 20260829001700_quotes_workflow.sql # status `cancelled`, prazo de entrega, totais não negativos, trava de cancelado
├─ 20260829001800_discard_draft.sql   # discard_quote_draft(): exclusão lógica de rascunho via security definer
├─ 20260829001900_quote_sharing.sql   # get_shared_quote(): leitura pública por token, sem policy para anon
├─ 20260829002000_storage.sql         # buckets public-assets e private-docs, com policies próprias
│
│  ── Fase 6 e endurecimento ──────────────────────────────────────────
├─ 20260831002100_signup_role_hardening.sql  # papel de admin não se concede no cadastro
├─ 20260901052518_revoke_trigger_function_execute.sql # revoga EXECUTE direto das funções de trigger
├─ 20260901052525_expire_quotes_schedule.sql # Fase 6.2: índice da varredura e job `expirar-orcamentos` no pg_cron
├─ 20260901055000_reconciliar_comentarios_expiracao.sql # só COMMENT: reconciliação documental da 6.2
├─ 20260901060000_audit_log.sql       # Fase 6.3: audit_log append-only, audit_capture() e triggers em 13 tabelas
├─ 20260901190230_harden_function_search_path_and_rls_policies.sql # search_path vazio nos helpers de autorização; initPlan nas policies
├─ 20260901190334_harden_remaining_function_search_paths.sql # search_path vazio nas demais funções de trigger/helper
├─ 20260901191225_harden_quote_sequence_access.sql # quote_sequences fora do alcance de anon e authenticated
├─ 20260901193812_revoke_anon_public_table_access.sql # revoga todo privilégio de tabela do anon no schema public
├─ 20260901193926_harden_remaining_security_definer_search_path.sql # search_path vazio nas security definer restantes
├─ 20260901194546_move_extensions_out_of_public.sql # pg_trgm e unaccent saem do schema public
├─ 20260901195103_revoke_anon_trigger_function_execute.sql # revoga EXECUTE do anon nas funções de trigger
├─ 20260901201459_enforce_quote_status_and_active_rls.sql # máquina de estados do orçamento no banco; RLS exige usuário ativo
├─ 20260901211122_protect_quote_totals_from_direct_updates.sql # PATCH direto em subtotal/total dispara recálculo
├─ 20260901211340_enforce_active_user_on_quote_items.sql # owns_quote() e quote_is_editable() exigem usuário ativo
└─ 20260901214750_consolidate_permissive_rls_policies.sql # policies por comando, sem sobreposição admin ALL + leitura
```

**36 migrations**, todas aplicadas no projeto remoto. A conferência é por
checksum: a lista `version||'_'||name` de `supabase_migrations.schema_migrations`
e a lista de arquivos deste diretório produzem o mesmo md5. Um banco montado do
zero com estas 36 migrations reproduz o catálogo de produção — mesmas 47
policies, 25 funções, 36 triggers e 15 tabelas.

> `supabase db pull` deposita aqui um `<timestamp>_remote_schema.sql`. Isso **não
> é uma migration**: é um dump do schema remoto, e versioná-lo reabre a
> divergência entre o histórico do Git e o do banco. O `.gitignore` bloqueia
> esse padrão de propósito.

Verificação: `bash supabase/db-tests/run.mjs` aplica todas as migrations em um
PostgreSQL descartável e confere regras de negócio, RLS e privilégios.
Detalhes em `supabase/db-tests/README.md`.

Aplicação: `supabase db push`. O schema **nunca** é editado pelo painel web —
qualquer mudança nasce como arquivo de migration versionado no Git.

---

## 8. Tabelas previstas (não criar agora)

Documentadas apenas para garantir que o modelo atual as comporta:

`orders`, `order_items`, `stock_movements`, `warehouses`, `suppliers`,
`purchase_orders`, `price_lists`, `price_list_items`, `commissions`,
`commission_rules`, `customer_interactions`, `attachments`,
`quote_approvals`, `signatures`, `audit_log`.

### Importação de catálogos de fabricante — forma prevista

Também **não criar agora**. Registrado para que o modelo atual seja conferido
contra ele:

| Tabela | Papel |
| --- | --- |
| `catalog_imports` | uma execução: fabricante, catálogo, versão, arquivo, quem rodou, status |
| `catalog_import_items` | área de revisão: uma linha por item lido, com `manufacturer_code`, dados brutos, `match_product_id`, `diff` e `decision` (`new` · `update` · `conflict` · `ignored` · `approved`) |
| `price_list_imports` | mesma ideia para tabelas de preço, casando por `manufacturer_code` |

O dado só entra em `products` na **aprovação**. Enquanto isso vive no staging,
o que mantém o catálogo AGROTORK limpo. As colunas `manufacturer_code`,
`source_*` e `technical_data` de `products` já são o destino dessa aprovação —
por isso o modelo atual não bloqueia o fluxo.

Todas se ligam a `customers`, `products` e `profiles` já existentes — nenhuma
exige reescrever o núcleo.
