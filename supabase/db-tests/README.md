# `supabase/db-tests/` — suíte de comportamento

```bash
npm run db:test
```

**Este é o runner canônico dos testes de banco.** Roda em Windows, macOS e
Linux e não exige `psql` instalado no host: procura, nesta ordem, um `psql`
no PATH com servidor no ar, o container do Supabase local (se estiver de
pé, sem baixar nada) e, por último, um `postgres:16` descartável.

A suíte é uma **sequência**, não um conjunto de arquivos soltos: `01` cria
os usuários que `02` usa, `02` cria o orçamento que `09` confere. Os
identificadores são fixos de propósito — é o que deixa a asserção legível.
Daí o banco descartável: sobre um banco já povoado isso vira `duplicate
key` em cascata, e limpar tudo antes destruiria o encadeamento. De quebra,
cada execução testa também que as 20 migrations aplicam do zero, em ordem.

As asserções **estruturais** (RLS ligado, policies, `security definer`,
buckets) não dependem de sequência e por isso ficam em `supabase/tests/`,
em pgTAP, rodando contra o Supabase local com `npx supabase test db`.

---

# Verificação do banco

Scripts que aplicam **todas** as migrations em um PostgreSQL descartável e
conferem o comportamento que o sistema depende. Não tocam no projeto do Supabase.

```bash
bash supabase/db-tests/run.sh
```

| Arquivo | O que verifica |
| --- | --- |
| `00_supabase_stub.sql` | Recria o mínimo do ambiente Supabase (schema `auth`, `auth.uid()`, papéis `anon`/`authenticated`/`service_role`, default privileges) |
| `01_regras_de_negocio.sql` | Perfil criado por trigger, margem calculada, preço de kit derivado, normalização de CPF/CNPJ e CEP, numeração `ORC-AAAA-NNNN`, totais por trigger, **preço congelado**, desconto por item, carimbo de status, expiração |
| `02_rls.sql` | Vendedor enxerga só os próprios orçamentos; não cria produto; não cria orçamento de outro dono; anônimo não enxerga nada; admin enxerga tudo |
| `04_travas_de_orcamento.sql` | Orçamento aprovado não pode ter itens alterados nem apagados pelo vendedor; rascunho continua editável; vendedor não se promove a admin; usuário desativado não se reativa; admin ainda corrige um aprovado |
| `05_custo_produto.sql` | Vendedor vê o produto mas recebe custo e margem **nulos**; não lê `product_costs`; não altera custo nem preço de venda; o custo permanece intacto |
| `06_origem_produto.sql` | Origem padrão `manual`; código de fabricante exige marca; mesmo código em marcas diferentes é aceito e no mesmo fabricante é bloqueado; dados técnicos sem preço; massa de teste identificável e removível por `purge_test_products()`, preservando o histórico dos orçamentos |
| `07_cadastros.sql` | Marcas, categorias e unidades: criação com `slug` por trigger, edição, duplicidade sem distinguir maiúsculas, `LT` e `L` como unidades distintas, vínculo com `products`, exclusão física recusada por FK, desativação preservando produto e vínculo, reativação, e permissões — admin administra, vendedor lê (inclusive o inativo) mas não cria, altera nem apaga |
| `08_kits.sql` | Kits: criação (inclusive kit vazio), edição, duplicidade de código, item obrigatório e opcional, `item_type` padrão, preço-base somando só os obrigatórios, produto duplicado no mesmo kit, quantidade zero e negativa, produto inexistente, vínculo com produto inativo, alternar papel, desativação preservando a composição, kit com histórico que o banco recusa apagar, orçamento congelado após alteração do kit, e permissões — admin administra, vendedor consulta mas não escreve em `kits` nem em `kit_items`, e não alcança custo pelo kit |
| `09_orcamentos.sql` | Orçamentos: numeração automática, `line_total` e totais por trigger, item de produto e de kit, snapshot do kit com TODOS os componentes (inclusive o opcional recusado), desconto por item, desconto percentual e em valor, frete, total com piso em zero, quantidade e preço inválidos, referência cruzada, exclusão de kit e de cliente com orçamento, status e carimbos, **o teste crítico de histórico** (o catálogo inteiro muda e o orçamento não), isolamento entre vendedores, aprovado e cancelado travados, e o descarte de rascunho por `discard_quote_draft()` |
| `10_compartilhamento.sql` | Compartilhamento: token de 48 hex gerado pelo banco e único, `anon` sem acesso a `quotes`/`quote_items`, leitura por `get_shared_quote()`, **teste de vazamento** (custo, observação interna, ids e contato do cliente fora do payload), token inexistente/curto/nulo, contador de visualizações, acesso que não altera o orçamento, rascunho e cancelado que não circulam, expiração, revogação, token novo depois da revogação, isolamento entre vendedores, acesso cruzado entre orçamentos e link de orçamento descartado |
| `11_storage.sql` | Storage: os dois buckets criados com limite de tamanho e tipos, administrador grava e atualiza no bucket público, vendedor lê mas não grava, não altera e não apaga, bucket privado invisível para o vendedor, anônimo lê o público (é o que faz o logotipo abrir no link do orçamento) e não lê o privado nem grava |
| `03_triggers_e_privilegios.sql` | Os triggers funcionam para o vendedor mesmo com `EXECUTE` revogado nas funções administrativas, e a chamada direta a elas é negada |

Pré-requisito: `psql` no PATH e um servidor local em `PGHOST`/`PGPORT`
(padrão `/tmp/pgrun:5433`). Para usar outro servidor:

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres bash supabase/db-tests/run.sh
```

---

## Outros scripts desta pasta

| Script | Para que serve |
| --- | --- |
| `check-types.sh` | Aplica as migrations num banco descartável e confere a tipagem contra o schema real: todas as tabelas, colunas e enums no arquivo gerado, e as duas listas escritas à mão em `src/types/db.ts` — colunas `numeric` (que o gerador não distingue de `integer`) e colunas preenchidas por trigger. Nenhuma das duas o TypeScript consegue validar sozinho. |
| `check-arquitetura.sh` | Diz em segundos se a camada de tipos (`src/types/db.ts` + os 3 clientes + as projeções nos repositories) está inteira nesta cópia. Rode isto ANTES de investigar dezenas de erros de typecheck: quase sempre é um merge parcial, e os erros nos módulos são consequência. |
| `gen-types.sh` (`npm run db:types:local`) | Gera `src/types/database.types.ts` a partir das migrations, no mesmo formato do Supabase. A fonte oficial continua sendo `npm run db:types`; este script serve para trabalhar sem projeto vinculado e para conferir que a regeração não quebra a camada de domínio (`npm run db:types:local && npm run typecheck`). |
| `dev-seed.sh` | Cria um banco de **desenvolvimento** local (`agrotork_dev`) com as migrations aplicadas, dois usuários de teste e alguns clientes, produtos, kit e orçamentos. Serve para rodar a aplicação sem um projeto Supabase. |
| `auth-double/` | Duplê local do Supabase (Auth + subconjunto do PostgREST) e a validação de ponta a ponta da autenticação. Ver o README de lá. |

Nada aqui é usado em produção. As senhas de `dev-seed.sh` valem apenas no banco
local descartável.

## Dois ambientes, uma suíte

Os mesmos arquivos rodam de duas formas, e é de propósito:

| | como roda | onde |
|---|---|---|
| `npm run db:test` | psql, num PostgreSQL descartável | offline, sem Docker |
| `npx supabase test db` | pg_prove, no Supabase local | com Docker |

`00_supabase_stub.sql` é o que faz a ponte: cada bloco dele só age quando o
objeto **não existe**. No Supabase local, `auth` e `storage` são nativos (e
de outro dono — tentar recriá-los dá `permission denied for schema auth`),
então o arquivo vira quase um no-op e os testes exercitam os objetos de
verdade.

`11_storage.sql` lida com a outra diferença: o Storage do Supabase instala
um gatilho que recusa `delete` direto na tabela ("Direct deletion from
storage tables is not allowed"), **antes** de a policy ser consultada. GL e
GM tratam isso como proteção a mais, não como falha — e provam a policy por
um caminho que independe do gatilho: `pg_temp.policy_alcanca()` lê do
catálogo a expressão `using` real e conta quantas linhas ela alcançaria.
Zero = a policy nega. Se alguém afrouxar a policy numa migration futura, a
contagem sobe e o teste reprova, com ou sem gatilho.
