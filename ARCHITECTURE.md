# ARQUITETURA — Sistema Comercial AGROTORK

> Documento de decisões técnicas. Toda mudança que afete a arquitetura deve ser
> registrada aqui **antes** de ser implementada.

Versão: 1.2 — 29/08/2026
Fase atual: **Fase 0 e Fase 2 concluídas** (Clientes e Produtos). Fase 1
(cadastros de apoio) pendente, e o projeto Supabase ainda não provisionado —
ver `ROADMAP.md` e `SETUP.md`.

---

## 1. Situação encontrada

Análise do ambiente feita em 29/08/2026:

| Item | Resultado |
| --- | --- |
| Projeto de sistema comercial existente | **Não existe.** Nenhum repositório, `package.json` ou banco de dados foi encontrado. |
| Conteúdo relacionado na pasta `Desktop/Agro Tork` | Site institucional estático (`Site AGROTORK/index.html`), logotipos (`LOGO/`), materiais de marketing, planilhas comerciais (`.xlsx`) e o `AGENTS.md` do projeto do site. |
| Supabase | Não provisionado. |
| Vercel | Não provisionado. |
| Identidade visual | Extraída do site institucional e do logotipo (ver §6). |

**Conclusão:** projeto novo (greenfield). Nada foi apagado ou migrado. O site
institucional é um artefato **separado** e não é tocado por este sistema.

---

## 2. Visão geral

Aplicação web única (Next.js) que atende computador, notebook, tablet e celular
com o mesmo código — *responsive-first*, sem app nativo nesta fase.

```
                    ┌──────────────────────────────┐
   Navegador  ───▶  │  Next.js (App Router)        │
   (desktop/mobile) │  ├─ Server Components        │
                    │  ├─ Server Actions           │
                    │  └─ Route Handlers (/api)    │
                    └───────────┬──────────────────┘
                                │ @supabase/ssr (JWT do usuário)
                                ▼
                    ┌──────────────────────────────┐
                    │  Supabase                    │
                    │  ├─ PostgreSQL + RLS         │
                    │  ├─ Auth (GoTrue)            │
                    │  └─ Storage (imagens/PDF)    │
                    └──────────────────────────────┘

   Hospedagem: Vercel (frontend + funções) · Supabase (dados)
```

### Por que esta stack

| Decisão | Motivo |
| --- | --- |
| **Next.js 16 + App Router** | Um único projeto para UI e API. Server Components reduzem JavaScript no celular (o sistema será muito usado em campo, com internet ruim). |
| **TypeScript estrito** | Preço, desconto e imposto errados custam dinheiro. Tipagem forte + Zod eliminam uma classe inteira de bugs. |
| **Tailwind CSS v4** | Produtividade alta, bundle pequeno, responsividade explícita no markup. |
| **Supabase** | Postgres gerenciado + Auth + Storage + **Row Level Security** no próprio banco. Custo inicial zero, plano pago barato, sem *lock-in* (é Postgres puro; a saída é um `pg_dump`). |
| **Vercel** | Deploy do Next.js sem configuração, *preview* por branch, HTTPS e CDN inclusos. |
| **@react-pdf/renderer** | Gera PDF por código, sem Chrome *headless*. Roda em função serverless barata e rápida. Alternativa (Puppeteer) exigiria runtime pesado e custo maior. |

Nenhuma tecnologia experimental foi usada. Todas as bibliotecas escolhidas são
estáveis e amplamente adotadas.

---

## 3. Arquitetura interna — monólito modular

O sistema é um **monólito modular**: um único deploy, mas o código é dividido
por domínio de negócio. Cada módulo é uma "fatia vertical" independente, o que
permite adicionar Pedidos, Estoque ou Comissões depois **sem reescrever nada**.

```
src/
├─ app/                        # Rotas (App Router) — apenas UI e orquestração
│  ├─ (auth)/login/            # Rotas públicas
│  ├─ (app)/                   # Rotas protegidas (layout com sidebar)
│  │  ├─ dashboard/
│  │  ├─ clientes/
│  │  ├─ produtos/
│  │  ├─ kits/
│  │  ├─ orcamentos/
│  │  └─ configuracoes/        # cadastros de apoio: marcas, categorias, unidades
│  └─ api/                     # Route Handlers (PDF, links públicos, webhooks)
│
├─ modules/                    # ⬅ REGRA DE NEGÓCIO VIVE AQUI
│  └─ <dominio>/
│     ├─ types.ts              # tipos do domínio
│     ├─ schema.ts             # validação Zod (entrada e saída)
│     ├─ repository.ts         # único ponto que fala com o Supabase
│     ├─ service.ts            # regras de negócio puras (testáveis)
│     └─ actions.ts            # Server Actions ("use server") = fronteira
│
├─ components/
│  ├─ ui/                      # design system (Button, Input, Card, Table…)
│  └─ layout/                  # AppShell, Sidebar, Topbar, MobileNav
│
├─ lib/
│  ├─ supabase/                # clients (browser, server, middleware, admin)
│  ├─ auth/                    # sessão, papéis, guards
│  ├─ pdf/                     # templates e renderização de PDF
│  ├─ format/                  # moeda, data, CPF/CNPJ, telefone
│  └─ utils/
│
├─ config/                     # constantes: empresa, navegação, papéis
└─ types/                      # tipos gerados do banco (database.types.ts)

supabase/
└─ migrations/                 # SQL versionado — a fonte da verdade do schema
```

### Regras de dependência (obrigatórias)

```
app/  →  modules/*/actions  →  service  →  repository  →  Supabase
                    ↘ schema (Zod)
components/ui  ←  não conhece domínio nenhum
```

1. **Componente de UI nunca chama o Supabase direto.** Sempre via Server Action.
2. **`repository.ts` é o único lugar com query.** Trocar de banco = mexer só aqui.
3. **`service.ts` não importa React nem Next.** É código puro e testável.
4. **Um módulo não importa o `repository` de outro módulo** — só o `service`.
5. Toda entrada de usuário passa por um schema Zod **no servidor**, mesmo que já
   tenha sido validada no formulário.

### Preço de custo: por que uma tabela separada

O PostgreSQL não filtra *coluna* por papel de aplicação — `admin` e
`salesperson` são o mesmo papel de banco (`authenticated`). Enquanto
`cost_price` era coluna de `products`, esconder o custo na interface não era
proteção: bastava chamar a API com a chave pública. Por isso o custo vive em
`product_costs`, e a view `products_list` faz `left join` nela: para o vendedor
o join não encontra a linha e custo e margem chegam **nulos**, sem nenhum `if`
de aplicação. Migration `1200`, testes em `supabase/db-tests/05_custo_produto.sql`
e no e2e do módulo.

### Preparado para catálogos de fabricante (não implementado)

A AGROTORK tem catálogos oficiais dos fabricantes — o AGRIS 2026 da AGRES é o
primeiro — com **código original de fábrica**. Esses catálogos são a fonte de
cadastro mais confiável que existe, e o modelo já os comporta. O importador
**não** foi construído; o que existe é a estrutura que o receberá:

```
CATÁLOGO DO FABRICANTE
        ↓  (leitor por fabricante: PDF, XLSX, CSV)
   IMPORTAÇÃO         → grava em catalog_import_items (staging)
        ↓
  ÁREA DE REVISÃO     → casa por (brand_id, manufacturer_code)
        ↓
NOVOS · ALTERAÇÕES · CONFLITOS
        ↓
    APROVAÇÃO         → só aqui o dado entra em `products`
        ↓
 CATÁLOGO AGROTORK
```

Duas separações sustentam isso:

**1. Cadastro técnico ≠ preço.** O catálogo do fabricante fornece código, nome,
descrição, características, aplicação, unidade e imagem — nunca preço. Por isso
`technical_data` (jsonb) guarda as características e o preço mora em outro
lugar: `products.sale_price` e `product_costs.cost_price`. A futura importação
de **tabelas de preço** é um caminho separado, que casa pelo mesmo
`manufacturer_code` e toca só as colunas de preço.

**2. Identificação confiável.** `manufacturer_code` é único **por marca** — dois
fabricantes podem repetir um código, o mesmo fabricante não. É a chave de
correspondência entre catálogo, tabela de preços e cadastro. Um código de
fabricante sem marca é recusado pelo banco.

E a procedência fica registrada em cada produto: `source_type`
(`manual` · `manufacturer_catalog` · `price_list` · `test_data`),
`source_brand`, `source_catalog`, `source_version`, `source_reference` e
`source_imported_at`.

**Massa de teste.** Os produtos vindos das planilhas internas entram como
`test_data`. Não são catálogo oficial, aparecem marcados na ficha e saem com
`purge_test_products()` sem deixar rastro — os orçamentos que os citarem
mantêm o snapshot congelado.

Nada disso é o importador. É a garantia de que ele caberá.

### Cadastros de apoio: marcas, categorias e unidades

São três módulos irmãos (`src/modules/{brands,categories,units}/`) com a mesma
anatomia dos demais. Três decisões que valem registrar:

**Marca é marca comercial.** `brands` identifica o produto (ARAG, DJI, KUHN).
Não é fornecedor, não é distribuidor, não é fabricante. Quando esses conceitos
existirem, entram como cadastros próprios; o modelo atual não os mistura, e por
isso não precisará ser desfeito depois.

**Desativar é a operação; excluir não é.** Desativar preserva o vínculo e o
histórico: o produto continua apontando para o registro, e ele apenas deixa de
ser oferecido em cadastros novos. A recusa acontece no **servidor**
(`products/service.ts` → `assertReferencesUsable`), não escondendo a opção na
tela — um formulário antigo ou um POST forjado é recusado igual, e há teste de
regressão exatamente com o campo forjado. A regra vale só para a referência que
**mudou**: um produto que já usava um cadastro hoje inativo continua salvável.
Exclusão física é recusada pelo banco (`on delete restrict`).

**Unidade é identificada pelo código.** `L` e `LT` são unidades diferentes até
que alguém decida o contrário. O sistema não infere equivalência a partir de
planilha nenhuma.

O encanamento comum dos três formulários mora em `lib/forms/action-state.ts`
(`FormState`, `fail`, `collectFieldErrors`, `rawValues`, `isUniqueViolation`) e
em `app/(app)/configuracoes/catalog-form.tsx`.

### Kit ≠ kit dentro do orçamento

É a distinção que sustenta a Fase 3 e a Fase 4, e a fonte mais provável de
confusão do projeto inteiro:

| | Onde vive | O que significa | Quem mexe |
| --- | --- | --- | --- |
| **Item obrigatório do kit** | `kit_items.item_type = 'required'` | sempre entra quando o kit for usado | administrador, no cadastro |
| **Item opcional do kit** | `kit_items.item_type = 'optional'` | fica **disponível** para escolha | administrador, no cadastro |
| **Item selecionado no orçamento** | `quote_items` (Fase 4) | o que o vendedor **de fato** incluiu naquela venda | vendedor, no orçamento |

Marcar um item como opcional **não** o coloca em orçamento nenhum. Escolher
opcionais num orçamento **não** altera o cadastro do kit. São tabelas
diferentes de propósito — e é por isso que o editor de composição **não usa
caixa de seleção**: caixa de seleção é o gesto de "escolher para esta venda",
e reaproveitá-la no cadastro ensinaria o gesto errado.

**Preço.** O kit não tem preço próprio. `kits_with_price.components_total` soma
apenas os itens **obrigatórios** — o preço-base — a partir de
`products.sale_price`, sempre derivado, nunca armazenado: mudou o preço do
produto, muda o do kit. `optional_total` é informativo. Custo não passa por
aqui para ninguém: o módulo de kits jamais lê `product_costs`, então não há o
que esconder do vendedor. Se um dia a AGROTORK quiser um **preço comercial
próprio do kit** (um valor fechado, independente da soma), isso será uma coluna
nova e uma decisão explícita — hoje não existe, e `discount_percent` continua
sendo o único ajuste sobre a soma.

**Kit vazio.** Criar um kit sem itens é permitido: o cadastro é em dois passos,
o kit precisa existir para receber componentes, e exigir o contrário obrigaria
a um formulário monolítico. Um kit sem item obrigatório é **incompleto** —
marcado como tal na listagem e na ficha —, e `kitIsUsable()` é a função que a
Fase 4 vai consultar para não oferecê-lo em orçamento.

**Histórico.** Mexer no cadastro nunca reescreve venda passada: `quote_items`
guarda `components_snapshot`, `name_snapshot` e `unit_price` congelados na data
da emissão. Por isso remover um componente do kit é seguro. E kit citado em
orçamento não é excluído fisicamente — a FK `quote_items.kit_id` é
`on delete restrict` desde a migration 1600. Produto continua com `set null`
porque a massa de teste precisa sair inteira com `purge_test_products()`; a
assimetria é deliberada.

**Um produto entra uma vez por kit.** `unique (kit_id, product_id)` existe desde
a migration 0500 e vale como regra de negócio: o mesmo produto não pode ser
obrigatório e opcional ao mesmo tempo. Conferido contra as 14 páginas de kit do
catálogo Tecomec 2026 — nenhum kit real repete produto entre os dois grupos.

### Orçamento: o que congela, e por quê

O orçamento é a única parte do sistema em que **ler o cadastro atual seria um
defeito**. No instante em que um item entra, o serviço copia código, nome,
descrição, unidade, marca e preço; num kit, copia também a composição inteira.
Depois disso nenhuma consulta do módulo toca `products` ou `kits` para montar o
documento. Produto muda de preço, muda de nome, é desativado, é excluído; kit
ganha e perde componentes, é renomeado, é desativado — a proposta emitida
continua exatamente como saiu.

Os campos de congelamento já existiam desde a migration 0600 (`code_snapshot`,
`name_snapshot`, `unit_snapshot`, `brand_snapshot`, `components_snapshot`,
`unit_price`). A Fase 4 os usa; não criou nenhum.

**O snapshot do kit guarda TODOS os componentes**, inclusive os opcionais que o
vendedor recusou, cada um com `selected: true|false`:

```json
{ "product_id": "…", "code": "P-002", "name": "Mangueira 3/4\"",
  "unit": "M", "brand": "MAGNOJET", "quantity_milli": 1000,
  "unit_price_cents": 3200, "item_type": "optional", "selected": false }
```

Guardar o recusado é decisão comercial, não zelo: "este kit oferecia isto e o
cliente não quis" é informação que não se reconstrói depois — o cadastro do kit
muda, o orçamento não. E é o que permite remarcar um opcional mais tarde **sem
repreçar a proposta**: a troca trabalha sobre o snapshot, com os preços do dia
em que o kit entrou.

`quantity_milli` no snapshot é a quantidade **por unidade do kit**. A quantidade
efetiva é ela vezes a quantidade da linha: kit ×3 com componente ×2 entrega 6.

### Quem calcula o total é o banco

`quote_items.line_total` é **coluna gerada** (`quantity × unit_price ×
(1 − desconto/100)`), e `recalculate_quote_totals()` roda por trigger a cada
inserção, alteração ou remoção de item e a cada mudança de desconto ou frete.

A aplicação **não tem uma função que calcule total**. As Server Actions aceitam
quantidade, desconto e quais opcionais — intenção, nunca resultado. Não existe
caminho pelo qual o navegador informe um preço: nem por engano, nem de
propósito. O que a tela mostra é o que o banco gravou.

A única aritmética de dinheiro do módulo é o preço de **uma unidade do kit**
(`kitUnitPriceCents`), que soma os componentes selecionados — e mesmo esse
resultado é recalculado no servidor a cada alteração de opcionais.

### PDF e link público: um documento, duas portas

O que sai do sistema para o cliente tem uma forma só — `QuoteDocument`
(`modules/quotes/share/document.ts`). O PDF e a página pública leem
exatamente essa estrutura e nada além dela, e é por isso que as duas
superfícies não podem divergir nem vazar.

O tipo **não tem campo de custo**. `unit_cost_snapshot`, `product_costs` e
margem não aparecem porque não existe onde colocá-los; `internal_notes`
idem. Não é uma regra a ser lembrada em cada tela: é a forma do dado.

**Tudo vem de snapshot.** Montar o documento lê `code_snapshot`,
`name_snapshot`, `unit_snapshot`, `brand_snapshot`, `components_snapshot` e
`unit_price`. Nenhuma consulta a `products`, `kits` ou `kit_items` — se
houvesse, reemitir o PDF de um orçamento antigo devolveria outro documento.
Há teste que gera o PDF, muda preço, nome, composição e situação do
catálogo inteiro, gera de novo e compara os dois textos.

Duas exceções conscientes: **cliente e empresa são lidos ao vivo**. O
orçamento nunca congelou cadastro de cliente, e é o comportamento certo —
se o endereço mudou, a proposta reemitida deve sair com o endereço atual.
Está registrado nas limitações.

**Por que Route Handler e não Server Action:** o retorno é um arquivo. O
navegador precisa de `content-type` e `content-disposition` para baixar, e
Server Action devolve dados, não corpo binário com cabeçalho.

**pdfkit** foi escolhido por rodar em Node puro — navegador headless
inviabilizaria hospedagem serverless —, por trazer fontes com WinAnsi, que
cobre todo o português, e por não exigir infraestrutura nova. Fica em
`serverExternalPackages` porque lê as métricas das próprias fontes em
tempo de execução, e empacotá-lo quebraria esses caminhos.

### Link público: `anon` não ganha acesso a tabela nenhuma

A página pública roda sem login, ou seja, como `anon` — que não tem policy
em `quotes` nem em `quote_items`, de propósito, desde a migration 0800.
Abrir policies para `anon` seria a solução errada: bastaria um erro de
expressão para vazar a carteira inteira.

O caminho é uma função `security definer` única, `get_shared_quote(token)`
(migration 1900), que valida token, revogação, expiração, exclusão do
orçamento e situação, e devolve **apenas os campos comerciais**. O `anon`
não ganha acesso a tabela alguma: ganha acesso a uma função que só sabe
responder sobre o orçamento daquele token.

Token inexistente, revogado, expirado, de orçamento descartado ou de
orçamento que não circula devolvem todos a mesma coisa — `null`, que vira
404. Não confirmamos a existência de nada para quem está tentando adivinhar.

O token vem de `gen_random_bytes(24)` no default da coluna (48 caracteres
hex), gerado pelo banco: nada sequencial, nada derivado de id, e nenhuma
chance de a aplicação inventar um gerador pior.

**Compartilhar é somente leitura**, com uma exceção documentada: gerar o
primeiro link de um RASCUNHO muda o status para `sent`, porque compartilhar
é enviar — regra que o ROADMAP fixou na Fase 0. A transição passa por
`changeStatus`, então valem a matriz de transições e o RLS; e como um
orçamento sem itens não pode ser enviado, não existe link para proposta
vazia. Abrir o link não muda nada além de `view_count`.

**Validade do token ≠ validade da proposta.** O token expira e para de
abrir; a proposta vencida **abre com aviso**, porque um cliente que clica
num link antigo precisa ver o que foi proposto, não um 404. O token nasce
com a validade comercial do orçamento, ou 30 dias quando não há validade.

### Descoberta de RLS: exclusão lógica não é um UPDATE comum

`quotes_select` filtra `deleted_at is null` — é o que faz um orçamento
descartado sumir. Só que o PostgreSQL aplica as policies de SELECT também sobre
a **linha resultante** de um UPDATE: a linha nova precisa continuar visível para
quem a alterou. Resultado: `update quotes set deleted_at = now()` era recusado
para **qualquer** usuário, administrador incluído — no Supabase real igualmente.

Ninguém tinha esbarrado nisso porque nenhum módulo anterior fazia exclusão
lógica de orçamento. A saída é a função `discard_quote_draft()` (migration
1800), `security definer`, que confere permissão e status por conta própria. A
policy de SELECT continua estrita, a regra "só rascunho se descarta" passou a
morar no banco, e há teste que falha se um dia o `update` direto voltar a
passar.

### Status do orçamento

`draft → sent → approved | rejected | expired`, mais `cancelled` (migration
1700). `rejected` é "o cliente disse não"; `cancelled` é "nós desistimos" — são
relatórios diferentes. As transições permitidas vivem em `STATUS_TRANSITIONS`
(`modules/quotes/types.ts`), e a trava real está no RLS: `quotes_update` não
deixa o vendedor tirar o próprio orçamento de `approved`, e `quote_is_editable`
congela os itens de aprovado **e** de cancelado.

### Composição: um formulário por linha, sem "salvar tudo"

O editor de composição não mantém um array no cliente. Cada linha — e cada
resultado da busca — é um `<form>` com Server Action própria: adicionar, mudar
quantidade, alternar o papel e remover são operações independentes, validadas
no servidor uma a uma. Custa mais idas ao servidor e evita a classe de bug que
o formulário de Produtos já nos cobrou caro (estado de cliente que não
sobrevive ao retorno da action). Cada alteração vale sozinha, mesmo que a
seguinte falhe.

O papel do item viaja no `value` do **botão** que envia (`item_type=required` /
`optional`), não num campo separado: um clique, uma decisão.

### Server Component não passa função para Client Component

A primeira versão de `CatalogForm` recebia os campos por função filha —
`children({ text, error })` — para não repetir o formulário três vezes. Não
funciona: a página é Server Component, e o React recusa passar função a um
Client Component ("Functions cannot be passed directly to Client Components").
O build passa; a página quebra em execução — foi o e2e que pegou.

A forma correta separa as duas metades: `useCatalogForm` (estado da ação, erros
por campo) e `CatalogFormShell` (a casca visual, com `children` já renderizados),
ambos no cliente; e um formulário próprio por cadastro
(`marcas/brand-form.tsx`, `categorias/category-form.tsx`,
`unidades/unit-form.tsx`), que é Client Component e portanto **pode** montar os
campos. A página continua Server Component e passa apenas dados e a Server
Action — que é serializável.

Regra geral: o que cruza a fronteira servidor → cliente são dados e referências
de Server Action. Função de renderização, não.

### Formulários: o React reseta o form depois da Server Action

Ao usar `<form action={serverAction}>` com `useActionState`, o React limpa os
campos quando a ação termina — e não ressincroniza os campos controlados. Na
prática, a unidade, a marca e a categoria escolhidas sumiam da tela depois de
um erro de validação, mesmo com o valor correto no estado. A solução adotada:
a ação devolve um contador `attempt`, o formulário usa esse número como `key`
e remonta inicializando tudo a partir de `state.values`. Vale para Clientes e
Produtos, com teste de regressão nos dois.

### Módulo de referência: `customers`

`src/modules/customers/` é a implementação completa do padrão e serve de molde
para os próximos módulos:

| Arquivo | Responsabilidade |
| --- | --- |
| `schema.ts` | Zod: campos, máscaras normalizadas para dígitos, CPF/CNPJ conferido por dígito verificador e coerente com o tipo de pessoa |
| `types.ts` | Tipos do domínio (`CustomerListItem`, `CustomerPage`, `CustomerHistory`) |
| `repository.ts` | Só consultas ao Supabase. Nenhum `if` de negócio |
| `service.ts` | Regras: documento único, desativar em vez de excluir, recusar exclusão de cliente com histórico |
| `actions.ts` | Server Actions: `requirePermission` primeiro, Zod depois, e devolve o que foi digitado quando dá erro |

O histórico do cliente não tem tabela própria: é uma consulta sobre `quotes`
(e, no futuro, `orders`, `interactions`) filtrada pelo RLS. Um vendedor abrindo
a ficha de um cliente de outro vendedor vê a ficha, mas não os orçamentos
alheios — verificado em teste.

### Como um módulo futuro entra sem quebrar nada

Adicionar "Pedidos" = criar `src/modules/orders/` + migration + rota
`app/(app)/pedidos/` + item na navegação. Nenhum arquivo existente precisa ser
reescrito. É por isso que a divisão é por domínio e não por tipo de arquivo.

---

## 4. Modelo de dados

Detalhado em **`DATABASE.md`**. Princípios que valem como decisão de arquitetura:

- **Chaves `uuid`** (`gen_random_uuid()`) — seguras para expor em URL e prontas
  para sincronização offline no futuro.
- **`created_at` / `updated_at`** em todas as tabelas, via trigger.
- **Soft delete** (`deleted_at`) nos cadastros — nada de perder histórico
  comercial por um clique errado.
- **Congelamento de preço (regra crítica):** `quote_items` guarda uma *cópia*
  de nome, código, unidade, preço unitário, custo e desconto no momento do
  orçamento. Se o preço do produto mudar amanhã, **o orçamento de ontem não
  muda**. O `product_id` fica apenas como referência histórica.
- **Numeração de orçamento** por sequência anual (`ORC-2026-0001`), gerada no
  banco dentro de transação — sem risco de número duplicado.
- **Dinheiro em `numeric(14,2)`**, nunca `float`. Percentuais em `numeric(7,4)`.
  No TypeScript o valor circula como **inteiro de centavos** (`lib/format/money.ts`)
  e vai para o banco como string decimal — em nenhum ponto um preço passa por
  aritmética de ponto flutuante.
- **Custo do produto isolado** em `product_costs`, com RLS de administrador.
  Margem é derivada, nunca armazenada.
- Tabelas de apoio (`units`, `categories`, `brands`) são **dados**, não código —
  o administrador cadastra, edita e desativa pela interface.

---

## 5. Autenticação e controle de acesso

### Autenticação
- **Supabase Auth** com e-mail + senha nesta fase (magic link e OAuth ficam
  disponíveis sem mudança de arquitetura).
- Sessão em **cookies httpOnly**, renovada em `src/proxy.ts` (convenção do
  Next.js 16, sucessora do `middleware.ts`) a cada requisição. Nenhum token fica
  em `localStorage`.
- A tabela `auth.users` (gerenciada pelo Supabase) é espelhada em
  `public.profiles`, que guarda nome, papel, telefone e status. O vínculo é
  criado por trigger no cadastro.

### Autorização — dois níveis, sempre juntos
1. **No banco (RLS)** — a defesa real. Mesmo que alguém obtenha uma chave
   pública e chame a API direto, o Postgres recusa. Funções auxiliares
   `auth_role()` e `is_admin()` são usadas nas policies.
2. **Na aplicação** — `requireUser()` / `requirePermission()` nas páginas e
   Server Actions, e ocultação de menus e botões. Esconder o menu é conveniência
   de UX, **não** é segurança: a verificação no servidor é obrigatória.

### Travas de negócio aplicadas pelo banco
- Vendedor não vê orçamento de outro vendedor.
- Vendedor não altera preço de tabela nem cadastra produto, marca, categoria
  ou unidade.
- Orçamento **aprovado** fica travado para o vendedor — inclusive os itens
  (`quote_is_editable()`), para que uma proposta aceita não mude de valor.
- Vendedor não se promove a administrador.
- Usuário desativado não se reativa e não enxerga nada.
- Anônimo não enxerga nenhum dado comercial.

Cada uma dessas travas tem teste de regressão em `supabase/db-tests/`.

### Papéis
| Papel | Permissões |
| --- | --- |
| `admin` | Tudo: produtos, preços, kits, usuários, todos os orçamentos, configurações. |
| `salesperson` | Cadastra clientes, cria orçamentos, vê **apenas os seus**, consome produtos e kits. Não altera preço de tabela. |

Os papéis são um **enum no banco** (`user_role`). Adicionar `manager`,
`financial` ou `viewer` depois = uma migration com `ALTER TYPE ... ADD VALUE` e
ajuste nas policies. A matriz de permissões vive em `src/config/permissions.ts`,
em um único objeto — não espalhada por `if`s pelo código.

---

## 6. Interface e identidade visual

Extraída do site institucional e do logotipo da AGROTORK:

| Token | Valor | Uso |
| --- | --- | --- |
| `--brand` | `#d42424` | Ação primária, destaque, total |
| `--brand-dark` | `#a81c1c` | Hover, gradiente |
| `--brand-deep` | `#6e1414` | Texto sobre vermelho claro |
| `--graphite` | `#1c1c1e` | Sidebar, títulos |
| `--graphite-soft` | `#4a4a4d` | Texto secundário |
| `--sand` | `#f7f5f1` | Fundo da aplicação |
| `--line` | `#e4e2df` | Bordas |
| `--whatsapp` | `#25D366` | Ações de compartilhamento |

Tipografia: **Oswald** (títulos, números, tabelas) + **Work Sans** (texto),
as mesmas do site — carregadas via `next/font` (sem requisição externa).

Princípios de interface:
- **Mobile-first de verdade:** todo layout é escrito para 360 px e cresce.
- Alvos de toque de no mínimo **44 px**; campos com `font-size: 16px` para o
  iOS não dar zoom.
- Tabela em desktop vira **lista de cards** no celular (o mesmo dado, duas
  apresentações) — nada de rolagem horizontal.
- Navegação: sidebar fixa no desktop, **barra inferior** no celular com as
  quatro ações mais usadas + "Novo orçamento" em destaque.
- Zero gráficos complexos na primeira fase.

---

## 7. Geração de PDF

- **`@react-pdf/renderer`**, executado em um Route Handler
  (`/api/quotes/[id]/pdf`) no runtime Node.js.
- O template vive em `src/lib/pdf/templates/quote/` e é montado por **blocos**
  (`Header`, `CompanyInfo`, `CustomerBlock`, `ItemsTable`, `Totals`,
  `TermsBlock`, `Footer`). Adicionar QR Code, assinatura, dados bancários ou
  fotos depois = acrescentar um bloco, sem reescrever o documento.
- Os dados da empresa (CNPJ, endereço, contatos, logo) ficam em
  `src/config/company.ts` — um arquivo, fácil de atualizar.
- O PDF é gerado **sob demanda** a partir do orçamento salvo. Não guardamos o
  arquivo, então corrigir o template corrige todos os PDFs. (Quando existir
  assinatura digital, aí sim o arquivo passa a ser versionado no Storage.)

---

## 8. Compartilhamento

1. **Baixar PDF** — link direto para o Route Handler.
2. **Compartilhar** — `navigator.share()` (Web Share API) no celular, que abre
   a folha nativa do Android/iOS com WhatsApp, e-mail etc. Em desktop, cai
   automaticamente para "copiar link".
3. **Link público** — cada orçamento pode gerar um token opaco
   (`quote_share_tokens`) com validade; quem tem o link vê o PDF sem login e
   sem acessar mais nada do sistema.

A integração direta com a API do WhatsApp **não** é feita agora. A arquitetura
já prevê: a tabela `quotes` tem `status` e o módulo tem um ponto de extensão
`notifications` para plugar o envio depois.

---

## 9. Segurança

| Camada | Medida |
| --- | --- |
| Transporte | HTTPS obrigatório (Vercel), HSTS. |
| Sessão | Cookies `httpOnly`, `secure` (em produção), `sameSite=lax`, renovados em `src/proxy.ts`. Ver nota abaixo. |
| Banco | **RLS ativo em todas as tabelas**, sem exceção. Policies por papel. |
| Segredos | Somente em variáveis de ambiente. Hoje o sistema **não usa nenhum segredo**: as duas variáveis obrigatórias são públicas por natureza (URL e *anon key*, que o RLS limita). Ver a nota sobre a service role. |
| Entrada | Zod no servidor em toda Server Action. |
| Saída | Sem dados de cliente em rota pública; link compartilhado usa token opaco com expiração. |
| Cabeçalhos | `Content-Security-Policy` com nonce por resposta (`lib/security/csp.ts`, aplicada no proxy) + `X-Frame-Options: DENY`, `Referrer-Policy`, `X-Content-Type-Options`, `Permissions-Policy` em `next.config.ts`. |
| Auditoria | `created_by` / `updated_by` nas tabelas transacionais. |

Nenhuma chave é versionada. O `.env.example` documenta as variáveis; o `.env.local` está no `.gitignore`.

### Content-Security-Policy com nonce

A CSP não pode viver em `next.config.ts`: cada resposta precisa de um `nonce`
diferente. Ela é montada no proxy, que grava o nonce **no cabeçalho da
requisição** — é de lá que o Next o lê para assinar as próprias tags de
`<script>` — e no cabeçalho da resposta.

```
script-src 'self' 'nonce-<aleatório>' 'strict-dynamic'
```

Sem `unsafe-inline` (que anularia o nonce) e sem `unsafe-eval`. Com
`strict-dynamic`, os pedaços que o script assinado carrega herdam a permissão;
qualquer script injetado, não. `frame-ancestors 'none'`, `form-action 'self'`,
`object-src 'none'` e `base-uri 'self'` fecham o resto.

A exceção consciente é `style-src 'unsafe-inline'`: o Next injeta estilo inline
na renderização, e CSS não executa código. É o ponto mais fraco da política.

Em desenvolvimento a política é afrouxada, porque o HMR usa `eval`.

A suíte de autenticação confere os cabeçalhos e que **o nonce muda a cada
resposta** — assim uma mudança futura no proxy não os apaga em silêncio.

### Por que a service role não está configurada

`SUPABASE_SERVICE_ROLE_KEY` ignora o RLS por completo. O cliente que a
consumiria (`lib/supabase/admin.ts`) existe pronto, mas **nenhum código o
importa** — foi escrito para o módulo de Usuários, que ainda não chegou.

Enquanto isso, a configuração mais segura é a que não tem o segredo: chave que
não está no ambiente não vaza em log, em variável de build nem em captura de
tela. O `.env.example` e o `SETUP.md` instruem a **não** cadastrá-la, e o e2e
confere que a expressão "service_role" não aparece no HTML servido.

### Trilha de auditoria: por que trigger, e por que só administrador lê

Três fatos do sistema decidiram a estratégia, e nenhum deles é preferência de
estilo:

1. A expiração automática roda pelo **pg_cron** como `postgres` — sem
   `auth.uid()`, sem Server Action, sem requisição HTTP. Registrar
   `quote.expired` pela aplicação é impossível.
2. Trocar o papel de um usuário **não tem tela**: é `update public.profiles set
   role='admin'` no SQL Editor. O evento mais sensível do sistema não passa por
   nenhum código nosso.
3. Toda mutação vai pelo PostgREST, e cada requisição é a sua própria
   transação — a aplicação não consegue fazer `set_config('app.motivo', …)`
   antes do `update` para o trigger ler. Por isso **não existe campo de motivo
   livre**: o verbo de negócio (`quote.approved`, `product.cost_changed`) é
   derivado do diff.

Dentro de uma função `security definer`, `current_user` é o **dono** da função,
não quem disparou a escrita. Usá-lo para identificar o ator classificaria todo
mundo como sistema. O que sobrevive é o GUC `role` — exatamente o que o
PostgREST define com `set local role authenticated`. É de lá que sai
`actor_db_role`, e é ele que distingue "foi o cron" de "foi alguém no painel".

Só administrador lê, e isso vem da migration `1200`: o custo saiu de `products`
para `product_costs` porque o PostgreSQL **não filtra coluna por papel**.
Auditar `cost_price` recria esse dado. Se o vendedor lesse a trilha, o custo
vazaria por ali — e `05_custo_produto.sql` continuaria passando, porque ela
testa `product_costs`, não o log. A trilha do vendedor sobre os próprios
orçamentos é funcionalidade comercial, e fica para uma fase própria.

O log é evidência, não tabela de trabalho: `revoke` total, uma única policy (de
leitura), e três triggers que recusam UPDATE, DELETE e TRUNCATE — inclusive
para o dono da tabela, que o `revoke` não alcança. Encadeamento de hash foi
avaliado e adiado: serializa as inserções e é peso desproporcional para um
sistema com dois usuários.

Verificado em `supabase/db-tests/14_auditoria.sql`,
`supabase/tests/000_seguranca.test.sql` e
`supabase/db-tests/auth-double/e2e-auditoria.mjs`.

### Nota sobre o cookie de sessão

O `@supabase/ssr` grava o cookie **sem** `httpOnly` por padrão, porque supõe um
cliente Supabase rodando no navegador. Este sistema é server-first: login,
sessão e consultas acontecem em Server Components e Server Actions. Então
`src/lib/supabase/cookies.ts` força `httpOnly` em toda gravação — um XSS deixa
de conseguir roubar o token.

Consequência assumida: um `createBrowserClient` não enxergaria a sessão. Por
isso `lib/supabase/client.ts` foi removido (não era importado por ninguém). Se
no futuro algo precisar do Supabase no navegador — Realtime, por exemplo —, o
token deve ser passado explicitamente do servidor, nunca lido de
`document.cookie`.

Verificado em `supabase/db-tests/auth-double/e2e-autenticacao.mjs`.

---

## 10. Hospedagem e ambientes

| Camada | Onde |
| --- | --- |
| Aplicação | hospedagem com Node 20+. A Vercel é o caminho mais direto por ser a fabricante do Next, mas **nada no código depende dela**: sem Edge Functions, sem KV, sem Blob. A única exigência é Node no servidor, por causa do `pdfkit`. |
| Banco, Auth e Storage | Supabase |
| Desenvolvimento e testes | máquina local, com PostgreSQL descartável (`npm run db:test`) e o duplê em `supabase/db-tests/auth-double` |

Deploy é `git push`. As migrations são aplicadas pelo Supabase CLI
(`supabase db push`), versionadas em `supabase/migrations/` — o schema nunca é
alterado "na mão" pelo painel.

O passo a passo de produção, incluindo Storage, agendamento da expiração e o
checklist final, está no `SETUP.md` (seções 8 a 11).

Custo estimado inicial: **US$ 0** (planos gratuitos de Vercel e Supabase),
migrando para ~US$ 45/mês quando o volume justificar.

---

## 11. Multiusuário

- Todos os usuários compartilham a mesma base (é uma única empresa).
- O isolamento é **por papel e por dono do registro**, aplicado via RLS.
- O schema já está preparado para multi-empresa/filial no futuro: bastaria
  adicionar `organization_id` às tabelas e um predicado nas policies — sem
  reescrever a aplicação.

---

## 12. Verificação

| Comando | O que cobre |
| --- | --- |
| `npm run typecheck` | TypeScript estrito, sem `any` |
| `npm run lint` | ESLint (flat config do Next 16) |
| `npm run build` | Build de produção |
| `npm run db:test` | Aplica **todas** as migrations em um PostgreSQL descartável e testa regras de negócio, RLS, privilégios e travas de orçamento (`supabase/db-tests/`) |
| `supabase/db-tests/auth-double/run-e2e.sh` | Duplê local do Supabase + 123 checagens de ponta a ponta: sessão (26), Clientes (31) e Produtos (66), incluindo RLS visível na tela |

Alteração de interface exige conferir 360 px, 768 px e 1440 px — as capturas
ficam em `docs/screenshots/`.

Sobre privilégios: o Supabase concede acesso a `anon`/`authenticated` por
*default privileges*. A migration `1000_grants.sql` declara isso explicitamente
para o repositório não depender desse comportamento implícito, e revoga
`EXECUTE` das funções administrativas (`expire_quotes`, `next_quote_number`,
`recalculate_quote_totals`) — que continuam funcionando via trigger porque são
`security definer`. Isso está coberto por teste.

---

## 13. Decisões deliberadamente adiadas

Registradas para não serem esquecidas nem implementadas cedo demais:

- Integração com API do WhatsApp (Cloud API) — Fase 5.
- Assinatura digital do orçamento — Fase 5.
- Modo offline / PWA com fila de sincronização — reavaliar na Fase 4.
- Tabelas de preço por região/cliente e regras de comissão — Fase 3.
- Cache/edge de leitura — só quando houver métrica que justifique.
