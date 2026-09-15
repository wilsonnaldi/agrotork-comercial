# Congelamento dos módulos operacionais

Com a Compusystem como fonte oficial de estoque, compras, financeiro e
faturamento, os módulos que a AGROTORK construiu para essas mesmas coisas
deixam de ser operação e passam a ser **capacidade adormecida**: o código fica,
as tabelas ficam, os testes ficam, o uso para.

**Nada aqui está aplicado.** Este documento mapeia os pontos, propõe o
mecanismo e mede o risco. Ligar o congelamento é alteração de comportamento e
depende de autorização explícita do Wilson.

Por que não apagar: o schema é testado, auditado e correto para o que se
propôs. Apagar destrói informação (inclusive a de como o problema foi
resolvido) e não resolve nada que um interruptor não resolva. Congelar é
reversível; `drop table` não é.

---

## 1. O que a produção diz hoje

Conferido em 15/09/2026, somente leitura:

| Tabela | Linhas |
| --- | --- |
| `stock_movements` | 0 |
| `stock_movement_costs` | 0 |
| `product_serials` | 0 |
| `purchases` / `purchase_items` | 0 |
| `financial_entries` / `financial_payments` | 0 |
| `supplier_products` | 0 |
| `suppliers` | 0 |

Congelar hoje não custa migração de dado nenhum: **não há dado**. Este é o
momento mais barato que vai existir.

Mas o risco não é zero, e tem endereço: o pedido **PED-2026-0002 está em
"em separação"**, e os gatilhos `trg_orders_write_stock` e
`trg_orders_write_receivable` estão **habilitados** em produção. Mover esse
pedido para "faturado" — um clique na tela de Pedidos — grava movimento de
estoque e cria um título a receber. A verdade paralela começa aí, não numa
decisão de arquitetura.

## 2. Mapa dos pontos que criam verdade paralela

### No banco (gatilhos habilitados em produção)

| Gatilho | Dispara em | Efeito |
| --- | --- | --- |
| `trg_orders_write_stock` → `write_sale_stock_movements()` | `orders`, mudança de situação para faturado | Grava saída em `stock_movements` e congela custo em `stock_movement_costs` |
| `trg_orders_write_receivable` → `write_receivable_from_order()` | `orders`, mudança de situação | Cria título a receber em `financial_entries` |
| `trg_purchases_write_payable` → `write_payable_from_purchase()` | `purchases`, recebimento | Cria título a pagar |

### No banco (funções chamadas pela aplicação)

`register_stock_movement`, `return_order_stock`, `assign_serial_to_order`,
`release_serial` (estoque) · `receive_purchase`, `cancel_purchase`,
`remember_supplier_product` (compras — `receive_purchase` **também** grava
custo em `product_costs` e movimento de estoque) · `register_financial_payment`,
`split_financial_entry`, `cancel_financial_entry` (financeiro) ·
`set_product_cost` (custo manual do produto).

### Na aplicação

| Arquivo | Ações |
| --- | --- |
| `src/modules/stock/actions.ts` | `registerMovementAction`, `createSerialAction`, `assignSerialAction`, `releaseSerialAction` |
| `src/modules/purchases/actions.ts` | `createPurchaseAction`, `updatePurchaseAction`, `addItemAction`, `removeItemAction`, `receivePurchaseAction`, `cancelPurchaseAction` |
| `src/modules/purchases/import-actions.ts` | `previewNfeAction`, `confirmImportAction` (importação de NF-e de entrada) |
| `src/modules/financial/actions.ts` | `registerPaymentAction`, `splitEntryAction`, `cancelEntryAction` |
| `src/modules/orders/actions.ts` | `changeStatusAction` — é o clique que aciona os dois gatilhos acima |
| `src/modules/products/repository.ts` | `set_product_cost` (custo digitado à mão) |

Telas correspondentes: `/estoque`, `/compras`, `/compras/importar`,
`/financeiro`, e a mudança de situação em `/pedidos/[id]`.

## 3. Mecanismo mínimo proposto

O projeto já tem o lugar certo: `src/config/permissions.ts` declara **quem
pode o quê**. Falta declarar **o que está ligado**. São perguntas diferentes e
merecem arquivos diferentes — misturar as duas transforma "desligado para
todos" em "permissão que o administrador acha que pode conceder".

Proposta: um `src/config/features.ts` com a lista de capacidades operacionais
e o estado de cada uma, mais um guarda equivalente ao `requirePermission()` em
`src/lib/auth/session.ts`. Três lugares consultam: a ação do servidor (recusa),
a navegação (esconde o item) e a tela (explica em vez de oferecer botão).

Capacidades sugeridas — nomes a confirmar na implementação:

| Capacidade | O que desliga |
| --- | --- |
| escrita de estoque | lançamento manual, ajuste, perda, número de série |
| escrita de compras | nota de entrada, recebimento, importação de NF-e |
| escrita de financeiro | título, baixa, parcelamento, estorno |
| efeito operacional do faturamento | a passagem de situação que dispara estoque e título |
| custo manual de produto | `set_product_cost` pela tela |

Ler continua permitido: quem quiser conferir o que existe, confere. O que
some é a possibilidade de criar fato novo.

**Segunda cinta, só depois e só com autorização:** o mesmo congelamento no
banco — `revoke execute` nas funções e desativação dos dois gatilhos de
faturamento. É o que impede escrita por fora da aplicação. Exige migração,
teste e autorização de produção; **não entra nesta rodada**, e a ordem importa:
aplicação primeiro, banco depois, nunca o contrário (banco desligado com tela
oferecendo o botão gera erro feio no lugar de explicação).

## 4. Risco de cada módulo se for usado antes da integração

| Módulo | Se alguém usar hoje | Gravidade |
| --- | --- | --- |
| Faturamento do pedido | Estoque e contas a receber passam a existir nos dois sistemas, com números diferentes; a diferença só aparece quando alguém procurar | **Alta** |
| Estoque | Saldo do aplicativo divergente do ERP; decisão de venda tomada sobre saldo errado | **Alta** |
| Compras / entrada de NF-e | Custo gravado em `product_costs` diferente do custo do ERP; margem e preço sugerido saem errados a partir daí | **Alta** |
| Financeiro | Título que ninguém concilia; cobrança duplicada ou baixa que não existe no ERP | **Alta** |
| Custo manual do produto | Mesma contaminação de margem, por um caminho mais curto | Média |
| Número de série | Registro isolado, sem contrapartida no ERP; recuperável, mas trabalhoso | Média |
| Fornecedores e de-para de código | Cadastro paralelo leve; útil para a memória do BRAIN, inofensivo enquanto não gerar lançamento | Baixa |

O padrão: o que grava **custo, saldo ou dinheiro** é alto. O que grava
**referência** é baixo.

## 5. Ordem de execução, quando autorizado

1. Congelar na aplicação (capacidades desligadas, telas explicando, navegação sem os itens).
2. Conferir que nada mais grava: nenhuma ação de escrita alcançável pela interface nos módulos congelados.
3. Só então, se o Wilson autorizar, a cinta no banco — com migração, teste e possibilidade de reversão.
4. A integração vem depois disso, não antes. Espelho chegando enquanto o aplicativo ainda escreve é o pior dos dois mundos.

Enquanto os passos 1 e 2 não acontecerem, a instrução operacional é humana e
vale a partir de agora: **não faturar pedido pelo aplicativo, não lançar
estoque, não dar entrada de nota, não registrar título.**
