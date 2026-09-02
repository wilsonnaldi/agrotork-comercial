# Marco Zero — base limpa antes da carga de catálogo

Quatro scripts, na ordem. **Só o 02 altera dados**, e ele não roda sozinho.

```
01_inventario.sql              leitura   pode rodar sempre
02_limpeza.sql                 ESCRITA   só com autorização explícita
03_verificacao_pos_limpeza.sql leitura   antes de carregar
04_verificacao_pos_carga.sql   leitura   depois de carregar
```

## Ensaio antes de valer

```bash
# 1. fotografia
psql "$DATABASE_URL" -f supabase/marco-zero/01_inventario.sql

# 2. ENSAIO: mesmo script, terminando em ROLLBACK — nada muda
sed 's/^commit;$/rollback;/' supabase/marco-zero/02_limpeza.sql > /tmp/ensaio.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f /tmp/ensaio.sql

# 3. valendo (só depois da aprovação)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/marco-zero/02_limpeza.sql

# 4. conferência
psql "$DATABASE_URL" -f supabase/marco-zero/03_verificacao_pos_limpeza.sql
```

## O que o 02 apaga

Orçamentos e o que pende deles, clientes, kits, produtos e custos, e os
dois cadastros chamados "AGROTORK TESTE". Nada mais.

## O que ele não toca

Schema, migrations, funções, triggers, RLS, policies, grants, unidades,
categorias e marcas do seed, condições de preço, `app_settings` (os dados
reais da empresa ficam), `profiles`, `auth.users`, storage.

`audit_log` **não é apagável**: a migration `20260901060000` instalou
guardas de UPDATE, DELETE e TRUNCATE, e nem o dono da tabela passa. A
trilha do período de testes sobrevive de propósito — é a prova de que a
limpeza aconteceu e de quem a fez.

## Os guards

O 02 aborta antes de apagar qualquer coisa se encontrar um banco
diferente do que a auditoria descreveu: contagem de produtos, custos,
clientes, orçamentos, itens, links, kits; qualquer orçamento **aprovado**;
qualquer produto com **preço de venda definido** fora o de teste; cadastros
de apoio alterados; `app_settings.company` ausente; administrador ativo
inexistente. Depois de apagar, confere de novo — e se algo que devia
sobreviver sumiu, levanta exceção e a transação inteira volta atrás.

## Pré-requisito da carga

O CSV da carga diz `JR SOLUCOES`; o banco tem `JR SOLUÇÕES`. O importador
casa marca por `upper(name)`, que **não** ignora acento, então ele tentaria
criar a marca de novo — e o slug `jr-solucoes` já existe, com índice único.
A carga aborta na primeira instrução.

Resolver antes de carregar, de um dos dois jeitos:

1. **corrigir o CSV para `JR SOLUÇÕES`** (a grafia correta, e a que já
   aparece na tela) e regerar o SQL com `npm run import:sql`; ou
2. apagar a marca no marco zero (`remover_marca_jr = true` no 02) e deixar
   a carga criar `JR SOLUCOES`.

A opção 1 é a recomendada. O `03_verificacao_pos_limpeza.sql` termina
justamente conferindo isto.
