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

Reconferido em 15/09/2026 contra o código: 13 funções do banco chamadas pelos
módulos operacionais, 18 Server Actions de escrita (4 estoque, 6 compras, 2
importação de NF-e, 3 financeiro, 3 pedidos) e os dois gatilhos de faturamento
acima, todos habilitados. Nada mudou desde o mapa anterior.

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

## 4. Módulos operacionais congelados até a integração com o ERP

Esta é a lista oficial. Congelado significa: o código fica, a tabela fica, o
teste fica — **o uso para**. Para cada um, por que para, qual é a fonte certa,
o que acontece se for usado assim mesmo, e o que precisa ser verdade para
voltar a valer.

| Módulo | Risco se usado hoje | Motivo do congelamento | Fonte oficial correta | Condição para reativação |
| --- | --- | --- | --- | --- |
| **Faturamento do pedido** (`changeStatusAction` → `trg_orders_write_stock`, `trg_orders_write_receivable`) | **Alto** — estoque e contas a receber passam a existir nos dois sistemas com números diferentes, e a diferença só aparece quando alguém procurar | Faturar é ato do ERP: é ele que emite a nota, baixa o estoque e gera o título | Compusystem | Nunca volta como está. Se um dia o pedido nascer no app, o faturamento continua sendo do ERP e o app só espelha a situação |
| **Estoque** (`register_stock_movement`, `return_order_stock`, tela `/estoque`) | **Alto** — saldo do aplicativo divergente do ERP, e decisão de venda tomada sobre saldo errado | O saldo real é o que o ERP controla; um segundo livro não vira verdade por ser bem escrito | Compusystem | Só como leitura do espelho. Lançamento manual não volta — ajuste de estoque é no ERP |
| **Compras / entrada de NF-e** (`receive_purchase`, `confirmImportAction`, tela `/compras`) | **Alto** — grava custo em `product_costs` diferente do custo do ERP, e a partir daí margem e preço sugerido saem errados | A entrada de mercadoria é o que forma custo, e custo é do ERP | Compusystem | Não volta como lançamento. O leitor de XML pode voltar como **conferência** (comparar nota com o que o ERP registrou), nunca como escrita |
| **Financeiro** (`register_financial_payment`, `split_financial_entry`, `cancel_financial_entry`, tela `/financeiro`) | **Alto** — título que ninguém concilia, cobrança duplicada ou baixa que não existe no ERP | Contas a receber e a pagar são do sistema que emite a nota e recebe o dinheiro | Compusystem | Só como leitura do espelho, para indicador e alerta. Baixa e estorno não voltam |
| **Custo manual do produto** (`set_product_cost`) | Médio — mesma contaminação de margem, por um caminho mais curto | Custo digitado compete com o custo oficial sem nenhuma trilha que os concilie | Compusystem | Volta só se a Compusystem não expuser custo — e, nesse caso, com marca explícita de que é estimativa da AGROTORK, não custo oficial |
| **Número de série** (`product_serials`, `assign_serial_to_order`, `release_serial`) | Médio — registro isolado, sem contrapartida no ERP; recuperável, mas trabalhoso | Só faz sentido junto do estoque que o ERP controla | Compusystem, **se** controlar série; caso contrário AGROTORK | Reabre se a resposta ao bloco D confirmar que o ERP **não** controla série — aí é lacuna legítima, não verdade paralela |
| **Fornecedores e de-para de código** (`suppliers`, `supplier_products`) | Baixo — cadastro paralelo leve, útil à memória do BRAIN, inofensivo enquanto não gerar lançamento | Não gera custo, saldo nem dinheiro | Compusystem para o cadastro; AGROTORK para o de-para | Permanece utilizável como referência; não precisa ser congelado |
| **Orçamento, kit, PDF, link público** | — | **Não é congelado.** É o que sobra de operação própria: proposta comercial, anterior à venda | AGROTORK | Não se aplica |

O padrão que separa as linhas: o que grava **custo, saldo ou dinheiro** é alto;
o que grava **referência** é baixo. E a condição comum a todas as reativações é
a mesma — um espelho funcionando, reconciliado, com a fonte oficial respondendo.
Reativar antes disso é recriar o problema que o congelamento resolve.

## 5. Ordem de execução, quando autorizado

1. Congelar na aplicação (capacidades desligadas, telas explicando, navegação sem os itens).
2. Conferir que nada mais grava: nenhuma ação de escrita alcançável pela interface nos módulos congelados.
3. Só então, se o Wilson autorizar, a cinta no banco — com migração, teste e possibilidade de reversão.
4. A integração vem depois disso, não antes. Espelho chegando enquanto o aplicativo ainda escreve é o pior dos dois mundos.

Enquanto os passos 1 e 2 não acontecerem, a instrução operacional é humana e
vale a partir de agora: **não faturar pedido pelo aplicativo, não lançar
estoque, não dar entrada de nota, não registrar título.**
