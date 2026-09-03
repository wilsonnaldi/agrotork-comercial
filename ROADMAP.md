# ROADMAP — Sistema Comercial AGROTORK

Cada fase só começa depois que a anterior estiver **funcionando, testada e
responsiva**. Nada é implementado "por antecipação".

Legenda: ✅ concluído · 🟡 em andamento · ⬜ planejado

---

## Fase 0 — Fundação ✅

**Objetivo:** decidir a arquitetura e deixar o projeto de pé.

- ✅ Análise do ambiente (nenhum sistema comercial anterior encontrado)
- ✅ Extração da identidade visual (logo + site institucional)
- ✅ `ARCHITECTURE.md`, `DATABASE.md`, `ROADMAP.md`, `SETUP.md`
- ✅ Projeto Next.js 16 + React 19 + TypeScript estrito + Tailwind v4
- ✅ Estrutura de pastas modular (`src/modules/*`)
- ✅ Design system base (Button, Input, Card, Badge, Table, EmptyState…)
- ✅ Layout responsivo: sidebar no desktop, barra inferior no celular
- ✅ Migrations SQL completas com RLS
- ✅ Autenticação Supabase (login, sessão, middleware, papéis)
- ✅ Dashboard com os contadores iniciais
- ✅ Perfil do usuário (somente leitura) e verificação de permissão no servidor
- ✅ Migrations validadas em PostgreSQL real: regras de negócio, RLS e privilégios
- ✅ Auditoria de segurança: trava dos itens de orçamento aprovado e do perfil
- ✅ Suíte de regressão do banco (`npm run db:test`) e duplê de teste do Auth
- ⬜ **Provisionar o projeto Supabase** — depende de acesso à conta (ver `SETUP.md`)

**Entregue:** o sistema roda, o usuário entra, vê o painel e é bloqueado
corretamente conforme o papel. Falta apenas apontar para um Supabase real.

---

## Fase 1 — Cadastros de apoio ✅

**Objetivo:** o admin consegue configurar o catálogo antes de cadastrar produto.

- ✅ CRUD de **Unidades** — código único (`UN`, `KG`, `L`, `M`, `JG`, `HR`, …),
      aceita ou não fração. `L` e `LT` são unidades **distintas**: o sistema não
      presume equivalência
- ✅ CRUD de **Categorias** — nome único (sem distinguir maiúsculas), descrição,
      ativar/desativar
- ✅ CRUD de **Marcas** — marca **comercial** que identifica o produto; não é
      fornecedor nem distribuidor
- ✅ Tudo em **Configurações → Cadastros**, exclusivo do administrador
      (`catalog.manage`), com o RLS recusando escrita de vendedor
- ✅ Desativar preserva o vínculo e o histórico; o registro apenas deixa de ser
      oferecido em produtos novos — recusa verificada **no servidor**, não só na tela
- ✅ Exclusão física recusada pelo banco enquanto houver produto vinculado
- ✅ Testes: 26 verificações de banco (`07_cadastros.sql`) e 64 de ponta a ponta
      (`e2e-cadastros.mjs`), incluindo 360 px, 768 px e 1440 px
- ✅ **Usuários** — papel (administrador ⇄ vendedor) e ativar/desativar, em
      `Configurações → Usuários`. **Sem criação de conta**: criar usuário no Auth
      exige a `service_role`, que ignora o RLS, e a decisão foi mantê-la fora do
      ambiente. Contas nascem pelo painel (Invite user) e o trigger
      `handle_new_user` as cria como VENDEDOR — sempre (migration 2100)
- ✅ Travas contra travar o sistema: ninguém se rebaixa nem se desativa, e o
      **último administrador ativo** não pode perder o papel — regra da aplicação,
      registrada como tal no teste `IJ`
- ✅ **Dados da empresa** — os 12 campos que saem no cabeçalho do PDF e na página
      pública, gravados em `app_settings.company`. Só a razão social é obrigatória
- ✅ **Upload do logotipo** para o bucket `public-assets`, com o RLS de admin
      decidindo. Nome com sufixo de tempo (troca não fica presa em cache) e
      remoção que tira do cadastro sem apagar o arquivo — um PDF já enviado
      continua com a imagem
- ✅ Testes: 10 verificações de banco (`13_empresa_usuarios.sql`) e 24 de ponta a
      ponta (`e2e-empresa-usuarios.mjs`), incluindo 360 px, 768 px e 1440 px

**Critério de pronto:** admin cadastra e edita marcas, categorias e unidades pela
interface, sem SQL. ✅ — **fase fechada.**

---

## Fase 2 — Clientes e Produtos ✅

**Objetivo:** ter a base de dados comercial.

> Clientes foi antecipado à Fase 1 a pedido, por ser o módulo de que os
> orçamentos mais dependem. Os cadastros de apoio continuam pendentes e não
> bloqueiam Clientes.

### Clientes ✅
- ✅ CRUD completo com máscara e validação de CPF/CNPJ, telefone e CEP
- ✅ CPF/CNPJ conferido por dígito verificador e coerente com o tipo de pessoa
- ✅ Bloqueio de documento duplicado, com o nome do cliente já cadastrado
- ✅ Busca por nome, nome fantasia, documento ou cidade
- ✅ Filtros por UF e por situação (ativos / inativos / todos), com paginação
- ✅ Ficha com dados, atalhos de telefone/WhatsApp/e-mail e **histórico comercial**
- ✅ Desativar e reativar preservando o histórico
- ✅ Lista responsiva: tabela no desktop, cartões no celular
- ⬜ Preenchimento de endereço por CEP (ViaCEP) — pequeno, entra quando pedir

### Produtos ✅
- ✅ CRUD completo com código único, unidade obrigatória e máscara monetária
- ✅ Custo em tabela própria com RLS de admin — vendedor recebe custo e margem nulos
- ✅ Margem derivada de custo e venda, nunca armazenada; atalho margem → preço
- ✅ Busca por código, nome e descrição
- ✅ Filtros por marca, categoria, unidade e situação, com ordenação e paginação
- ✅ Ficha com áreas preparadas para kits, histórico de preços, fornecedores e estoque
- ✅ Desativação com confirmação em dois passos; nada é excluído fisicamente
- ⬜ Envio de imagem para o Storage (hoje só endereço) — depende do Supabase
- ✅ Preparado para catálogos de fabricante: código original de fábrica (único
      por marca), procedência (`source_*`), dados técnicos e massa de teste
      identificável/removível — **sem** o importador, conforme a diretriz

### Custo, catálogo e margem ✅

- ✅ **Custo por condição de pagamento** — migration `20260902120000`: as
      tabelas de fabricante comprovam AVISTA e FATURADO, e só isso. `product_costs`
      passa a ter histórico (`valid_from`/`valid_to`) com um único custo vigente
      por produto e condição, garantido por índice único parcial. Como o
      PostgREST não infere índice parcial no `onConflict`, a gravação vai por
      `set_product_cost()`
- ✅ **"Preço nunca definido" ≠ R$ 0,00** — migration `20260902120100`:
      `sale_price_set_at` nulo significa que ninguém precificou ainda. Produto
      nessa situação entra inativo, e o app já recusa produto inativo em
      orçamento novo. É o que impede o catálogo de nascer valendo zero
- ✅ **Carga do catálogo** — 112 produtos das tabelas DJI (subdealer) e JR,
      com 186 linhas de custo nas duas condições e rastreabilidade até a linha
      do PDF de origem. Validador e gerador em `supabase/importacao/`; 25
      verificações em `15_importacao_catalogo.sql`
- ✅ **Marco Zero** — `supabase/marco-zero/`: inventário, limpeza com sete
      guards, e verificação antes e depois. Executado em 02/09/2026 com 29/29
      conferências OK
- ✅ **Setores comerciais** — os 112 classificados em 7 setores por lista
      explícita de códigos, não por palavra no nome: os 24 "DRONE MIX" da JR
      não são aeronaves, são misturadores de solo
- ✅ **Margem por setor** (`Configurações → Margens`) — migration
      `20260903020000`: percentual, markup sobre o custo **ou** margem sobre a
      venda, base de custo e arredondamento comercial, um por setor. A regra
      **sugere**, não impõe: aplicar é um segundo passo, com a lista do que
      mudaria na tela antes de gravar. Visível só ao administrador, no mesmo
      nível do custo. 16 verificações em `16_margens.sql`
- ⬜ Precificar os 112 e ativá-los — depende do percentual de cada setor

**Critério de pronto:** dá para cadastrar um cliente e um produto pelo celular
em menos de um minuto. ✅

---

## Fase 3 — Kits ✅

- ✅ CRUD de **Kits** (código único, nome, descrição, situação)
- ✅ **Item obrigatório × item opcional** (`kit_items.item_type`, migration 1600) —
      obrigatório sempre entra; opcional fica disponível para o vendedor escolher
      **no orçamento**, sem alterar o cadastro
- ✅ Montagem do kit: busca por código, código de fabricante, nome, marca ou
      categoria; quantidade; alternar obrigatório ⇄ opcional; remover
- ✅ Preço-base derivado dos componentes **obrigatórios**, nunca armazenado
- ✅ Só produto **ativo** entra em associação nova — recusa no servidor, com
      teste que forja o campo no HTML
- ✅ Um produto entra uma vez por kit (`unique (kit_id, product_id)`)
- ✅ Fração de quantidade só onde a unidade permite (regra da Fase 1)
- ✅ Desativar em vez de excluir; kit citado em orçamento não é apagável
      (`on delete restrict`)
- ✅ Vendedor consulta kits ativos e a composição; não modifica nada — RLS
- ✅ Kit sem obrigatórios é marcado como **incompleto** e não será oferecido
      em orçamento (`kitIsUsable()`)
- ✅ Testes: 29 verificações de banco (`08_kits.sql`) e 69 de ponta a ponta
      (`e2e-kits.mjs`), incluindo 360 px, 768 px e 1440 px
- ⬜ Imagem do kit (depende do Storage do Supabase)
- ⬜ Desconto padrão do kit na interface (a coluna existe desde 0500)
- ⬜ Duplicar kit existente
- ⬜ Reordenar componentes (a coluna `sort_order` existe; falta a interface)
- ⬜ Aviso ativo quando um componente do kit for desativado — hoje o produto
      inativo aparece marcado na composição, mas ninguém é notificado

**Critério de pronto:** um kit é montado pela interface, separa o que sempre
entra do que é opção, e o preço-base bate com a soma dos obrigatórios. ✅

---

## Fase 4 — Orçamentos *(módulo principal)* ✅

**Objetivo:** o fluxo completo em poucos toques no celular.

### O que ficou pronto

- ✅ Listagem com busca (número e cliente), filtros por situação e vendedor,
      ordenação e paginação — tabela no desktop, cartões no celular
- ✅ Novo orçamento: cliente, emissão, validade, condição de pagamento,
      **prazo de entrega**, observações do cliente e observações internas
- ✅ Numeração `ORC-AAAA-NNNN` gerada pelo banco, não pela aplicação
- ✅ **Produtos avulsos** com quantidade, preço congelado e desconto por item
- ✅ **Kits** com quantidade própria; componente ×2 num kit ×3 entrega 6
- ✅ **Escolha de opcionais na venda**, com obrigatórios marcados e bloqueados —
      e a possibilidade de remarcar depois, sem repreçar a proposta
- ✅ Desconto por item (%), desconto do orçamento (% e R$) e frete
- ✅ **Totalização inteiramente no servidor**: `line_total` é coluna gerada e
      `recalculate_quote_totals()` roda por trigger. Nenhuma action aceita total
- ✅ Situações `draft · sent · approved · rejected · expired · cancelled`, com
      matriz de transição e trava de RLS em aprovado e cancelado
- ✅ Descartar rascunho por `discard_quote_draft()` (migration 1800)
- ✅ Só produto **ativo** e só kit **utilizável** (`kitIsUsable`, da Fase 3)
      entram em orçamento novo — recusa no servidor, com teste que forja a URL
- ✅ Isolamento entre vendedores pelo RLS; administrador enxerga tudo
- ✅ Testes: 51 verificações de banco (`09_orcamentos.sql`, com o teste crítico
      de histórico) e 82 de ponta a ponta (`e2e-orcamentos.mjs`)

### O que NÃO entrou (de propósito)

- ⬜ Item livre ("custom") — a coluna `kind` já prevê; falta a interface
- ⬜ Duplicar orçamento
- ⬜ Reordenar itens (`sort_order` existe; falta o gesto na tela)
- ⬜ Cadastro rápido de cliente de dentro do orçamento
- ⬜ Dashboard alimentado com dados reais de orçamento
- ⬜ `unit_cost_snapshot` (margem real do orçamento) — exige tabela própria com
      RLS de administrador, como `product_costs`; decisão da fase de relatórios

**Critério de pronto:** um vendedor cria um orçamento com produto e kit, escolhe
opcionais, aplica desconto e salva — e o documento não muda quando o catálogo
muda. ✅

---

## Fase 5 — PDF e compartilhamento ✅

- ✅ **PDF profissional** gerado no servidor com `pdfkit`: cabeçalho da empresa
      a partir de `app_settings.company`, identificação do orçamento, bloco do
      cliente, tabela de itens, composição dos kits, totais, condições
      comerciais e rodapé com "página X de Y"
- ✅ **PDF montado só com snapshots** — nenhuma consulta a `products`, `kits`
      ou `kit_items`. Teste gera o PDF, muda o catálogo inteiro e compara
- ✅ Nada de custo, margem ou observação interna no documento: o tipo
      `QuoteDocument` não tem esses campos
- ✅ Download em `/api/orcamentos/[id]/pdf`, com botão na ficha
- ✅ **Link público com token** de 48 caracteres gerado por
      `gen_random_bytes(24)` no banco — nunca sequencial, nunca derivado de id
- ✅ Página pública `/orcamento-publico/[token]`, sem login, `noindex`
- ✅ PDF pelo link público, com o mesmo conteúdo restrito
- ✅ **Expiração** (validade do token ≠ validade da proposta) e **revogação**,
      com histórico de links na ficha
- ✅ Copiar link e **Web Share API** (folha nativa do celular)
- ✅ Compartilhar um rascunho marca o orçamento como **enviado**
- ✅ `anon` continua sem policy em `quotes`/`quote_items`: quem lê pelo link é
      `get_shared_quote()`, `security definer`, que só sabe responder sobre o
      orçamento daquele token
- ✅ Testes: 27 verificações de banco (`10_compartilhamento.sql`) e 72 de ponta
      a ponta (`e2e-pdf-compartilhamento.mjs`), incluindo o teste de vazamento

### O que NÃO entrou (de propósito)

- ⬜ Logo da empresa no PDF — `app_settings.company.logo_url` já é lido e o
      campo existe; falta o Storage do Supabase para hospedar o arquivo
- ⬜ Foto do produto no PDF — `image_url_snapshot` é capturado desde a Fase 4,
      mas nenhum produto tem imagem enquanto o Storage não existir
- ⬜ QR Code, assinatura, dados bancários e termos comerciais no PDF
- ⬜ Envio automático por WhatsApp ou e-mail (Fase 6+)

**Critério de pronto:** o PDF sai bonito, com os valores oficiais do orçamento,
e o link é enviado pelo WhatsApp em dois toques. ✅

---

## Preparação para produção 🟡

Feito entre as fases 5 e 6, sem abrir módulo comercial novo.

- ✅ **Storage** — migration `2000` cria `public-assets` (leitura pública,
      escrita de administrador) e `private-docs` (só administrador), com limite
      de 5 MB e apenas imagem no bucket público. As policies são executadas e
      testadas na suíte local (`11_storage.sql`, 12 verificações)
- ✅ **Content-Security-Policy com nonce por resposta**, sem `unsafe-inline` e
      sem `unsafe-eval` em script; `frame-ancestors 'none'`, `form-action`,
      `object-src 'none'`, `base-uri`. Validada com as 410 verificações de e2e
- ✅ Cabeçalhos conferidos por teste, para não sumirem em silêncio
- ✅ **Service role removida da configuração**: nenhum código a usa hoje, e
      chave que não está no ambiente não vaza. Documentado onde e quando voltará
- ✅ `check-types.sh` — confere `database.types.ts` contra o schema real das
      migrations (231 colunas, 17 tabelas/views, 6 enums) enquanto `db:types`
      não pode rodar
- ✅ `SETUP.md` virou runbook de produção: Storage, logotipo, agendamento da
      expiração, hospedagem e checklist de 15 itens
- ⬜ **Provisionar o projeto Supabase real** — depende de acesso à conta
- ⬜ Aplicar as migrations no banco real (`npm run db:push`)
- ⬜ Regerar os tipos do banco real (`npm run db:types`)
- ⬜ Validar Auth, RLS, Storage, PDF e link público contra o Supabase real
- ⬜ Agendar `expire_quotes()` com `pg_cron` (procedimento documentado, não
      validável sem o projeto real)

**Critério de pronto:** o sistema roda com o Supabase real, com o vendedor sem
enxergar custo e o link público funcionando no domínio de produção.

---

## Fase 6 — Refino e operação 🟡

- ✅ **Relatórios** (`/relatorios`) — orçamentos por período (este mês, mês
      anterior, 90 dias, ano), quebra por situação e por vendedor, valor emitido,
      valor aprovado, ticket médio e **taxa de conversão**
- ✅ Conversão é **aprovados ÷ decididos**, e "decidido" é aprovado, recusado ou
      expirado. Rascunho e enviado seguem em aberto — contá-los como perda faria a
      taxa cair só porque a proposta é recente. `cancelled` fica de fora: é
      desistência nossa, não resposta do cliente. Nulo ≠ zero por cento
- ✅ Agregação na aplicação, sem migration: o **RLS continua sendo o único** a
      decidir o que cada um soma. Vendedor vê só a própria carteira e não enxerga
      a quebra por vendedor (`reports.readAll`). O limite é conhecido e está
      comentado no repository — com dezenas de milhares de orçamentos por ano, a
      soma migra para uma view agregada
- ✅ Testes: 17 verificações de ponta a ponta (`e2e-relatorios.mjs`) que semeiam
      situações conhecidas e **conferem a aritmética** — total, aprovado, ticket
      médio e conversão —, além do isolamento por RLS e 360/768/1440 px
- ✅ **Expiração automática de orçamentos (cron do Supabase)** — migration
      `20260901052525_expire_quotes_schedule` cria o índice da varredura,
      reafirma os privilégios de `expire_quotes()` e agenda o job
      `expirar-orcamentos` (`5 3 * * *`). Coberto por `13_expiracao.sql`
      (25 verificações) e por `e2e-expiracao.mjs` (15). `pg_cron` 1.6.4 está
      habilitado no projeto remoto e o job consta em `cron.job`. SETUP.md §9
- ✅ **Log de auditoria** — migration `20260901060000_audit_log` cria
      `audit_log` (somente-anexação, leitura só de administrador), a função
      `audit_capture()` e triggers em 13 tabelas. Registra quem, o quê,
      quando, em qual registro e o antes/depois. Coberto por
      `14_auditoria.sql` (32 verificações), 13 asserções pgTAP e
      `e2e-auditoria.mjs` (17). Aplicada no Supabase remoto.
      DATABASE.md §4.13, ARCHITECTURE.md §9
- ✅ **Endurecimento de RLS e privilégios** — 11 migrations entre
      `20260901190230` e `20260901214750`: `search_path` vazio em todas as
      25 funções, revogação de todo privilégio de tabela do `anon`, extensões
      fora do schema `public`, máquina de estados do orçamento no banco,
      proteção de `subtotal`/`total` contra PATCH direto e consolidação das
      policies permissivas. Coberto por `db:test` (246 asserções).
- ⬜ Backup e rotina de restauração documentada
- ⬜ Domínio próprio (`sistema.agrotork.com.br`) e ambiente de produção
- ⬜ Treinamento da equipe e manual curto de uso

---

## Onda 1 — Pedido de venda 🟡

**Objetivo:** registrar o negócio fechado, sem tornar editável o que já foi
vendido.

### Banco ✅ *(migration `20260903060000`, publicada em 03/09/2026)*

- ✅ `orders`, `order_items`, `order_sequences` — espelham
  `quotes`/`quote_items`: mesmos snapshots, `line_total` gerado, totais
  calculados pelo banco
- ✅ Numeração `PED-AAAA-NNNN` em sequência própria, separada do orçamento
- ✅ `create_order_from_quote()` — só orçamento aprovado, e uma vez só
- ✅ `create_quote_from_order()` — renegociar cria orçamento novo em rascunho,
  ligado à origem, sem tocar no pedido
- ✅ `trg_orders_freeze` — conteúdo comercial congelado para vendedor **e**
  administrador; situação e operacional seguem editáveis
- ✅ Situações `confirmed → picking → invoiced → delivered`, com `cancelled`
  antes do faturamento, e carimbo de data em cada uma
- ✅ `order_items` sem policy de escrita: a composição só nasce pela conversão
- ✅ 19 asserções em `supabase/db-tests/18_pedidos.sql`, incluindo o teste
  crítico de histórico e o congelamento valendo para o administrador

### Interface ✅ *(módulo `src/modules/orders/`)*

- ✅ Listagem `/pedidos` com busca, filtro por situação e por vendedor,
  ordenação e paginação — tabela no desktop, lista no celular
- ✅ Detalhe `/pedidos/[id]`, somente leitura no comercial, com selo
  "Congelado" sobre os itens
- ✅ Botão "Gerar pedido" no orçamento aprovado; quando o pedido já existe,
  o cartão vira link para ele em vez de oferecer o botão de novo
- ✅ Botão "Renegociar" no pedido, com confirmação, levando ao orçamento novo
- ✅ Mudança de situação: só os botões que o banco aceita a partir da atual
- ✅ Item "Pedidos" na navegação (sidebar e barra do celular)
- ⬜ Conferência visual em 360, 768 e 1440 px — falta o olho humano
- ⬜ Formulário de previsão de entrega (a coluna existe e é editável)

### O que NÃO entra nesta onda (de propósito)

- Estoque: dar baixa exige `stock_movements`, que é a Onda 2
- Emissão de nota fiscal: fica fora do app, via API de terceiro
- Custo no item do pedido: exporia a margem ao vendedor; é da fase de
  relatórios, com tabela própria e RLS de administrador

---

## Backlog — depois do núcleo estável

Nada aqui entra sem que as fases 1–6 estejam concluídas.

| Item | Depende de |
| --- | --- |
| Estoque e movimentações | Onda 1 (banco ✅, interface pendente) |
| Fornecedores e compras | Estoque |
| Vendedores externos e comissões | Fase 4 + relatórios |
| Tabelas de preço e margens por cliente/região | Fase 2 |
| Fluxo de aprovação de orçamento | Fase 4 |
| Integração WhatsApp Cloud API | Fase 5 |
| Assinatura digital | Fase 5 |
| Dashboard com gráficos | Fase 6 |
| Controle financeiro (contas a receber) | Pedidos |
| Integrações externas (ERP, NF-e) | Pedidos |
| **Importação de catálogos de fabricante** (AGRIS 2026 e outros): leitura → área de revisão → aprovação | Fase 1 (unidades/marcas cadastráveis) |
| **Importação de tabelas de preço**, casando pelo código do fabricante | Importação de catálogos |
| IA (sugestão de kit, resumo de cliente, busca em linguagem natural) | Base de dados populada |
| App mobile / PWA offline | Reavaliar após uso real em campo |

---

## Como o trabalho é conduzido

Para **cada** item, sempre nesta ordem:

1. Analisar o código existente
2. Planejar a alteração (e explicar, se afetar arquitetura)
3. Implementar
4. Testar (`npm run typecheck`, `npm run lint`, `npm run build`)
5. Corrigir
6. Verificar responsividade em 360 px, 768 px e 1440 px
7. Só então avançar

Nada é apagado sem necessidade. Nada é substituído por preferência pessoal.
