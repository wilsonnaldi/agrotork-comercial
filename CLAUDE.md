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
6. **A Compusystem é a fonte oficial operacional.** Estoque, produtos,
   preço, custo, clientes, vendas, faturamento, compras e financeiro são
   dela. O que se constrói aqui não compete com isso: nenhuma entidade tem
   duas fontes oficiais. A integração combinada é **somente leitura**, e não
   existe ainda — enquanto a documentação da API não chegar, nada de schema
   de integração, coluna desenhada por suposição ou credencial guardada.
   Detalhe em `ARCHITECTURE.md` §14 e em `docs/integracoes/`.

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

## Estado atual (17/09/2026)

Sistema publicado na Netlify, em produção. Núcleo comercial entregue até o
Pedido de venda; estoque, compras, financeiro e importação de NF-e existem
no banco e na interface, mas **sem nenhum dado em produção** — e é isso que
o congelamento da rodada de consolidação torna barato. 112 produtos ativos e
precificados, 1 usuário administrador, 0 vendedores, 1 cliente e 2 pedidos
(todos de teste). 68 migrations aplicadas, a última `20260915120000`.

AGROTORK BRAIN: Fase 1 (CRM, identidade, eventos, jornada) em produção em
modo desacoplado — as três pontes `trg_brain_*` ficam desligadas e a
sincronia é por reconciliação. Fase 2 (memória corporativa) em produção com
**dois documentos ativos**: o Catálogo Magnojet V41 (172 páginas, 778 trechos,
202 tabelas confiáveis e 68 degradadas, que a busca recusa como evidência) e o
orçamento interno ARAG (`agrotork_interno`, 1 página, 2 trechos, 2 tabelas
confiáveis), ingerido em 15/09/2026 — ver `docs/brain/fase-2-arag-producao.md`.

A migration `20260915120000` (código puramente numérico é exato ou nada na
busca) foi **aplicada em produção em 15/09/2026**, depois de testada em
PG16/17/18. Rollback pronto em `supabase/operacao/10-…`. Era ela que travava o
lote ARAG, ingerido no mesmo dia.

Pendências conhecidas: bucket `brain-documents` não criado (as versões ativas
apontam para caminhos que ainda não existem), Lote C não iniciado, cinco
falhas herdadas na suíte 25 (BR4/5/6/9/16, esperadas no modo desacoplado), e a
barra do celular com 5 itens marcados para 4 lugares.

O lote **DJI Subdealer** está tecnicamente pronto — golden 9/9, adversariais
16/16 e golden final 10/10 com a cadeia V14.11 → V15.1 → V16.2 — e **travado
por governança**: falta a ALLCOMP confirmar rótulos e vigências. Ver
`docs/brain/fase-2-dji-governanca.md`. Dois pontos que não se negociam nesse
lote: a fonte é `allcomp` (`distributor`), não `dji` — a DJI é a marca, não a
autora da tabela; e da V15.1 só a **página 1** é evidência DJI, porque as
páginas 2–4 são Ddock/GranDdock (faturado pela Zait) e RTK South/Sunnav.

Retrato consolidado da Fase 2, com o próximo lote e o estado de cada
pendência: `docs/brain/fase-2-consolidado.md` (16/09/2026). Um aviso que saiu
de lá: o `FIGHTER AD-IA.pdf` **não** é manual de procedimento — é relatório de
calibração de um cliente identificado, e não entra sem decisão de governança.

O lote **JR Soluções** segue **BLOQUEADO**, mas o bloqueio mudou de endereço em
17/09: era o motor, agora é o arquivo — `docs/brain/fase-2-jr-solucoes.md`.
Dois consertos genéricos no worker, cada um com teste próprio e nenhum
específico da JR:

- **cabeçalho que carrega dinheiro denuncia linha engolida.** Um cabeçalho
  NOMEIA a coluna; ele nunca É um preço. O teste é o símbolo `R$`, não o parse
  numérico — este PDF quebra `R$ 5.600,00` em `R$ 5 .600,00`, e um parse
  estrito deixaria passar justamente o caso que motivou a regra. `"engolida"`
  já está em `FATAL_MARKERS`, então a tabela vira `degraded/fatal` e a busca a
  recusa. **Não há tentativa de recuperar a linha** — fail-closed primeiro.
- **NCM é classificação fiscal, não código de peça.** Coluna que o documento
  declara como NCM/NBM/CEST/HS não alimenta `codes`; se o mesmo valor também
  aparece numa coluna declarada de código, ele fica. O NCM continua inteiro em
  `table_data`.

Efeito na JR: tabelas `trusted` com produto faltando de 6 para **0**,
adversariais de 8/12 para **11/12**, e o NCM `84368000` deixou de responder
pelo braço exato (4 trechos → 0). O golden caiu de 5/10 para **3/10** **de
propósito** — as provas que ele perdeu liam justamente as tabelas que hoje são
recusadas. Golden menor, integridade maior. Nos corpos que já existiam,
**nenhuma degradação nova**: Magnojet segue em 56, DJI em 2, ARAG em 0.

**`query_codes` não foi mexido.** A hipótese de alargar a janela de 7–9 dígitos
para caber código de 3–4 foi testada ponta a ponta com os códigos já extraídos
certo: `2141` dá 1 hit, `879` dá 1 hit, `qual o preço do 2141?` dá 1 hit, NCM
dá 0. O código curto **é** recuperado, pelos braços de prosa — o que muda sem
alargar a janela é o rank, não a recuperação. Alargar é mexer em regra
transversal do BRAIN e exige documento que prove a necessidade. Fica registrado
como fronteira conhecida, não como pendência.

O que ainda trava é **o PDF**: o cabeçalho verdadeiro aparece uma vez só e essa
única ocorrência está fundida com duas linhas de produto sobrepostas, então não
existe cabeçalho limpo para herdar (a herança chegou a ser implementada, medida
e descartada por não disparar). Recuperar as 9 linhas exigiria adivinhar onde
termina a palavra do cabeçalho e começa o dado. A correção é a montante: um PDF
sem sobreposição, ou gerado de novo a partir da planilha. O cruzamento com o
ERP, esse, está limpo: 35 match exatos, 0 divergência de preço, e o `REVENDAS`
do PDF é o **custo** `AVISTA`, não o `sale_price`.

As cinco falhas da suíte 25 foram investigadas a fundo: todas são teste escrito
para a premissa da ponte ligada, nenhuma esconde risco. Detalhe e ressalvas em
`fase-2-consolidado.md` §7.

O trabalho citado como "Fase 9/10/11" e "suíte 26" **não existe em nenhuma
branch** — ver `ROADMAP.md`, "Trabalho não verificado". Não planejar em cima
dele.

## Armadilhas já pagas

- `upper('JR SOLUÇÕES') <> upper('JR SOLUCOES')`, mas `slugify()` dos dois
  dá `jr-solucoes` e o índice é único: a carga aborta. **A grafia oficial
  tem acento.**
- Os 24 produtos "DRONE MIX" da JR **não são drones** — são misturadores e
  abastecedores de solo. Classificar por palavra no nome erra feio.
- Índice único parcial não é inferido pelo `onConflict` do PostgREST.
  Upsert nessas tabelas vai por RPC ou por busca-e-decide.
