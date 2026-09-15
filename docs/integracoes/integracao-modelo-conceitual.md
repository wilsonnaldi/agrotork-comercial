# Integração com o ERP — modelo conceitual

Documento de projeto, não de implementação. **Nada aqui está construído**: não
existe schema de integração, tabela-espelho, executor, credencial ou chamada.
O que está escrito é a forma que a integração deve ter quando a documentação
da Compusystem chegar — e os nomes que ainda não podem ser escolhidos.

Regra que governa o resto: **nenhuma entidade tem duas fontes oficiais.**

---

## 1. Matriz de propriedade

A tabela oficial de quem manda em cada entidade — clientes, produtos, preços,
custos, estoque, compras, financeiro, vendas, faturamento, `orders`, orçamento,
memória corporativa — está em **`ARCHITECTURE.md` §14**, e é lá que ela se
mantém. Repeti-la aqui só criaria duas versões para divergirem.

Os dois termos que ela usa, definidos uma vez: **espelho** é cópia de leitura de
uma entidade do ERP, atualizada pela integração; **read model** é dado derivado,
montado para consulta e relatório. Nenhum dos dois é fonte oficial, e ambos
carregam sempre a marca de que não são.

O orçamento é o único documento comercial que continua nascendo na AGROTORK:
ele é proposta, não transação. A venda é do ERP.

## 2. `orders`: espelho, não origem

Decisão provisória oficial: **a venda nasce na Compusystem**. O `orders` do
Supabase passa a ser espelho/read model do que o ERP registrou.

Isso não elimina o caminho que começa no aplicativo. O modelo futuro, quando
houver contrato de escrita, é:

```
orçamento aprovado no app
  → pedido criado no app com situação "pendente de integração"
  → integração envia ao ERP
  → ERP confirma e devolve identificador e situação oficiais
  → Supabase grava external_id e passa a espelhar a situação do ERP
```

Enquanto esse contrato não existir, o pedido do aplicativo **não é a venda** —
é intenção comercial, e a venda oficial é a que estiver na Compusystem. Nenhum
passo desse fluxo está implementado, e nenhum deve ser implementado antes da
documentação da API.

## 3. As três camadas

```
Compusystem  ──API somente leitura──▶  camada 1: bruto
                                          ↓
                                       camada 2: normalização
                                          ↓
                                       camada 3: espelho / read model  ──▶  BRAIN
```

**Camada 1 — bruto.** Recebe o retorno da API e guarda como veio, com o
sistema de origem, a entidade, o identificador externo, o hash do conteúdo, a
hora da leitura e a execução que a produziu. Serve para três coisas:
reprocessar quando a normalização mudar, auditar divergência sem pedir os
dados de novo, e provar o que o ERP respondeu naquele momento.

**Camada 2 — normalização.** Converte a estrutura externa no modelo interno.
É o único lugar que conhece o formato da Compusystem; trocar de ERP é trocar
esta camada. Nenhuma regra de negócio da AGROTORK mora aqui.

**Camada 3 — espelho e read model.** Tabelas estáveis, com identificador
externo, hora da última alteração na origem e hora da sincronização. É o que o
BRAIN e os relatórios leem. O BRAIN **nunca** lê a camada 1.

Fora dessas três, uma quarta função transversal: reconciliação — comparar o
que existe no espelho com o que a fonte diz existir, e apontar a diferença.

## 4. Nomes de schema — em aberto de propósito

`integration`, `erp`, `compusystem`: nenhum está escolhido. Cada um tem um
defeito conhecido:

- `erp` envelhece mal se um dia houver um segundo sistema de origem;
- `compusystem` amarra o nome do fornecedor ao schema, e trocar de ERP vira renomear tabela;
- `integration` confunde trilha de execução com dado de negócio, se as duas coisas ficarem juntas.

A escolha entra junto com o desenho das colunas, e o desenho das colunas
depende da documentação. Até lá, o nome fica em aberto — **é decisão
adiada, não decisão esquecida**.

## 5. Idempotência e identificador externo

O BRAIN já resolveu essa parte. `brain.events` é append-only e idempotente por
`(source, external_id)`: o mesmo fato entregue duas vezes entra uma vez só. A
integração futura usa exatamente esse mecanismo — venda faturada na
Compusystem vira evento com `source` próprio e o identificador do ERP como
`external_id`.

```
evento no ERP → normalização → brain.ingest_event(source, external_id) → deduplicação → processamento
```

Duas observações que evitam confusão futura:

- hoje, `source = 'erp'` em `brain.events` significa **o próprio schema `public` da AGROTORK**, não a Compusystem. São três eventos em produção, e o valor não será renomeado; a Compusystem entra como fonte nova, com nome próprio;
- o schema de `brain.events` **não muda** por causa da integração. Ele já comporta o que ela precisa.

Fora do BRAIN, a mesma disciplina: toda linha de espelho carrega o
identificador externo, e o sistema da AGROTORK nunca depende do identificador
do ERP fora da tabela de vínculo.

## 6. Reconciliação

O molde já existe e está em produção: `brain.divergencias_erp()` compara dois
lados e lista o que não bate, sem corrigir por conta própria; `reconciliar_erp()`
corrige o que a lista apontou. A integração repete a forma: comparar contagem e
hora de alteração entre fonte e espelho por entidade, listar divergência, e só
então corrigir.

Reconciliação não é a mesma coisa que sincronização. A sincronização traz o
que mudou; a reconciliação responde "o espelho está mentindo?".

## 7. Observabilidade — o que medir

Nenhuma destas métricas está implementada. Todas devem existir antes de a
integração ser considerada confiável:

data e hora da última sincronização bem-sucedida por entidade; duração da
execução; registros lidos, alterados e ignorados; erros por execução e por
registro; tentativas e repetições; atraso entre a alteração na origem e a
chegada ao espelho; divergências encontradas na reconciliação; registros que
esgotaram as tentativas (fila morta); eventos rejeitados por duplicidade; e a
versão da API que respondeu.

A saúde da integração é dado de banco, não de log: o painel lê uma consulta,
não um arquivo.

## 8. Matriz de testes — antes de qualquer uso produtivo

| O que testar | O que precisa acontecer |
| --- | --- |
| Idempotência | O mesmo registro entregue duas vezes não vira dois |
| Repetição do mesmo payload | Sem alteração no espelho, sem evento novo |
| Filtro incremental | Só o que mudou depois da marca d'água é lido |
| Exclusão na origem | O espelho marca como excluído; não fica fantasma |
| Cancelamento | Situação do documento reflete o cancelamento |
| Paginação | Nenhum registro pulado nem repetido entre páginas |
| Tempo esgotado | A execução falha limpa e é repetível |
| Repetição após falha | Não duplica o que já entrou |
| Limite de requisições | A execução respeita o limite e continua depois |
| Payload inválido | Um registro ruim não derruba a execução inteira |
| Mudança de estrutura na origem | Detectada e registrada, não engolida |
| Reconciliação | Divergência plantada é encontrada |
| Falha no meio da execução | Não deixa o espelho pela metade sem registro disso |
| Credencial inválida ou expirada | Falha explícita, sem apagar o que já existe |
| Webhook duplicado (se houver) | Tratado pela mesma idempotência |
| Evento fora de ordem | Registro mais antigo não sobrescreve o mais novo |

## 9. Riscos classificados

**Alto** — estoque duplicado (duas verdades sobre o mesmo saldo); financeiro
paralelo; faturamento paralelo; preço ou custo divergente entre ERP e
aplicativo; origem ambígua do pedido.

**Médio** — cliente duplicado (cadastro no app e no ERP sem vínculo); situação
de documento atrasada no espelho; produto desatualizado.

**Baixo** — cache e metadados não operacionais; contagem aproximada em painel;
atraso em indicador que não dispara decisão.

O que separa alto de médio é simples: risco alto é aquele em que alguém decide
errado (vende o que não tem, cobra o que já foi pago) por acreditar no sistema
errado.

## 10. O que não fazer antes da documentação

Criar schema. Escolher nome definitivo. Escrever normalizador. Guardar
credencial. Desenhar coluna a partir de suposição sobre o que a Compusystem
devolve. Implementar fluxo de escrita. Qualquer um desses cria trabalho que
será refeito e, pior, documentação que parece verdade.
