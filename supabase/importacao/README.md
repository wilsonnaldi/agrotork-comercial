# Carga de catálogo — 112 produtos (DJI + JR Soluções)

Esta pasta prepara a importação do catálogo. **Nada aqui roda sozinho** e
nada aqui é migration: migrations mudam o schema e entram no `db push`;
isto insere dados comerciais e roda quando a AGROTORK mandar.

```
dados/integrar_supabase.csv   a aba INTEGRAR_SUPABASE, exportada tal e qual
dados/rastreabilidade.csv     a trilha de cada registro de origem
validar.mjs                   as regras, conferidas fora do Excel
gerar-sql.mjs                 escreve carga_produtos.sql a partir do CSV
carga_produtos.sql            GERADO. Não edite à mão.
```

## Como usar

```bash
npm run import:validar      # confere as 112 linhas e lista pendências
npm run import:sql          # regera carga_produtos.sql (não executa nada)
npm run db:test             # a carga roda em banco descartável, com as travas
```

Aplicar de verdade é um passo separado, fora destes scripts:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/importacao/carga_produtos.sql
```

## O que a carga garante

| Regra | Onde é garantida |
|---|---|
| Transação única: entram os 112 ou nenhum | `begin`/`commit` no SQL gerado |
| Idempotente por `upper(code)` | `on conflict (upper(code)) where deleted_at is null` |
| Produto existente não perde preço nem ativação | o `do update` não toca `sale_price`, `sale_price_set_at`, `is_active` |
| Produto novo entra sem preço definido | `sale_price = 0` **e** `sale_price_set_at` nulo |
| Produto novo entra inativo | `is_active = false` |
| `manufacturer_code` nunca com marca nula | o bloco `do $$` levanta exceção antes de inserir |
| Custo por condição (AVISTA e FATURADO) | `product_costs.condition_id`, migration `20260902120000` |
| Um custo vigente por produto e condição | `idx_product_costs_vigente` |
| `PRECO_REVENDA_JR` não duplica o custo | a coluna não é lida pelo gerador |
| NCM só numérico de 8 dígitos | validado no gerador e no bloco `do $$` |
| Relatório do que entrou | `raise notice` ao final |

## Pré-requisito de cadastro

A carga precisa da marca **JR SOLUÇÕES**, que não está no seed. O próprio
SQL a cria, antes de resolver `brand_id` — porque 35 dos 38 produtos JR
têm código de fabricante, e `chk_products_manufacturer_brand` recusa
código de fabricante com marca nula.

**TOYAMA** aparece na planilha, mas só em registros que ficaram fora da
carga. Não é criada.

## Por que o preço de venda fica vazio

Nenhuma das fontes traz preço de venda. Custo, preço sugerido e preço
mínimo do cliente são coisas diferentes de preço de venda, e a planilha
nunca os misturou. No banco:

- `sale_price = 0` **com** `sale_price_set_at` nulo → preço nunca definido;
- `sale_price = 0` **com** `sale_price_set_at` preenchido → alguém decidiu
  vender por R$ 0,00.

É `is_active = false` que impede o catálogo de nascer valendo zero:
`quotes/service.ts` recusa produto inativo em orçamento novo.

## Fonte

A planilha é a origem de tudo. Os CSVs desta pasta são exportação direta
das abas, para que a carga seja revisável em `git diff` — e para que os
testes leiam exatamente o que vai para o banco.
