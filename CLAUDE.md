# AGROTORK Comercial — instruções para agentes

Sistema comercial de uma revenda de implementos agrícolas em Londrina/PR.
Fluxo central: **cliente → produtos → kits → orçamento → PDF → link público**.

**Interface em português. Código e banco em inglês.** Comentário explica o
*porquê*, não o *o quê*.

## Stack

Next.js 16 (App Router) · React 19 · TypeScript estrito · Tailwind v4 ·
Zod · Supabase (Postgres + Auth + Storage) · pdfkit. Publicado na Netlify.

## Regras que não se negociam

1. **Nada é aplicado no Supabase de produção sem autorização explícita do
   Wilson.** Vale para migration, script de dados, RLS, grants e Auth.
   Construir e testar: sempre. Aplicar: só com um "pode".
2. **Nada de `push`, `commit --amend`, `rebase` ou force push sem pedir.**
   A autoria dos commits é `AgroTork <dev@agrotork.local>` e **fica como
   está** — commits já auditados não são reescritos por questão cosmética.
3. **Testar antes de aplicar.** `npm run db:test` sobe um Postgres
   descartável, aplica todas as migrations em ordem e roda as suítes.
   Migration nova sem teste novo não entra.
4. **Destrutivo é transacional e com guard.** Script que apaga ou altera em
   massa confere a cardinalidade esperada ANTES de tocar em qualquer linha
   e levanta exceção se o banco não for o que a auditoria descreveu.
5. **Não invente dado.** Preço, custo, NCM, categoria: se a fonte não diz,
   fica vazio. `sale_price_set_at` nulo significa "preço nunca definido" —
   é diferente de R$ 0,00, e o sistema não mistura os dois.

## Como o trabalho é conduzido

Analisar → planejar (explicar se mexe em arquitetura) → implementar →
testar → corrigir → conferir responsividade (360, 768, 1440 px) → avançar.
Uma fase por vez. Nada é apagado sem necessidade.

## Invariantes de arquitetura

- **RLS é a autorização de verdade.** Verificação na aplicação é conforto
  de interface; quem barra é o banco. `requirePermission()` existe para a
  mensagem ser decente, não para proteger.
- **Custo é dado sensível.** `product_costs` e `margin_rules` são
  admin-only. Vendedor recebe `null` em custo, margem e preço sugerido —
  decidido pelo RLS, não pela tela.
- **Funções novas: `security invoker` e `set search_path = ''`.** As
  `security definer` que existem são intencionais (quebram recursão de RLS)
  e estão documentadas. Tabela nova precisa de `revoke ... from anon`
  explícito: o default do Supabase concede.
- **Dinheiro nunca passa por ponto flutuante.** Inteiro em centavos no TS,
  string decimal para colunas `numeric`. Coluna e argumento de RPC
  numéricos são declarados em `src/types/db.ts`.
- **Uma conta só.** Preço sugerido vem de `suggested_sale_price()` no
  banco. Não recalcule margem em TypeScript — duas contas divergem.
- **`src/types/database.types.ts` é gerado** (`npm run db:types`, ou
  `db:types:local` a partir das migrations). Nada de domínio mora lá;
  apelidos e ampliações ficam em `src/types/db.ts`.
- **Módulo = `schema.ts` (Zod) + `repository.ts` (dados) + `service.ts`
  (regra) + `actions.ts` (Server Actions).** Repository não tem regra de
  negócio; service não fala com o Supabase direto.

## Comandos

```
npm run dev          npm run lint         npm run build
npm run db:test      # Postgres descartável + todas as migrations + suítes
npm run db:types     # tipos do Supabase vinculado
npm run db:types:local  # tipos a partir das migrations, sem projeto
```

## Estado atual (setembro/2026)

Fases 0–5 entregues: cadastros, clientes, produtos, kits, orçamentos, PDF,
link público e auditoria. Base de produção zerada e recarregada em 02/09
com **112 produtos** das tabelas DJI (subdealer) e JR, classificados em
**7 setores comerciais**, todos **inativos e sem preço de venda** até a
margem ser definida em Configurações → Margens.

Pendências conhecidas: Usuários e Dados da empresa (Fase 1), relatórios
(Fase 6), e os commits órfãos `e3c75c9` e `7bb9605`, que contêm esse
trabalho e ainda precisam ser integrados.

## Armadilhas já pagas

- `upper('JR SOLUÇÕES') <> upper('JR SOLUCOES')`, mas `slugify()` dos dois
  dá `jr-solucoes` e o índice é único: a carga aborta. **A grafia oficial
  tem acento.**
- Os 24 produtos "DRONE MIX" da JR **não são drones** — são misturadores e
  abastecedores de solo. Classificar por palavra no nome erra feio.
- Índice único parcial não é inferido pelo `onConflict` do PostgREST.
  Upsert nessas tabelas vai por RPC ou por busca-e-decide.
