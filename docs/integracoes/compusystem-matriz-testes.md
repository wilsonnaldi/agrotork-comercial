# Compusystem — matriz de testes da integração (antes de existir)

Documento de projeto. **Nenhum destes testes está escrito**, porque a
integração não existe: não há schema, cliente, endpoint nem credencial. O que
está aqui é o que precisa passar **antes** de qualquer sincronização ser
considerada confiável — escrito agora, enquanto dá para pensar sem pressa, e
não no dia em que a documentação chegar.

Os exemplos de payload abaixo são **fictícios e genéricos**, inventados só para
dar forma ao cenário. Nenhum deles descreve a API da Compusystem, que ainda não
conhecemos. Quando a documentação real chegar, cada exemplo é substituído pelo
formato de verdade — e é aí que esta matriz vira código.

Regra que atravessa a tabela inteira: **em dúvida, não escreve.** Uma
sincronização que para e avisa custa uma manhã; uma que grava errado custa a
confiança no número, e essa não volta.

---

## 1. Idempotência e repetição

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T1 | Mesma resposta processada duas vezes | Nada muda no espelho na segunda vez; nenhum evento novo em `brain.events`; o registro bruto é reconhecido pelo hash e não duplica |
| T2 | Execução interrompida no meio e repetida do início | O resultado final é igual ao de uma execução única — sem linha órfã, sem contagem dobrada |
| T3 | Mesmo `external_id` chegando em duas páginas diferentes da mesma consulta | Entra uma vez; a duplicidade fica registrada como aviso, não como erro |
| T4 | Webhook (se existir) entregue duas vezes | Tratado pela mesma idempotência do fluxo normal; nenhuma escrita extra |
| T5 | Webhook fora de ordem: a alteração antiga chega depois da nova | O registro mais antigo **não** sobrescreve o mais novo — quem decide é a data de alteração da origem, não a ordem de chegada |

## 2. Leitura incremental

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T6 | Consulta com marca d'água (`alterado_desde`) | Só volta o que mudou depois dela; a marca avança apenas quando a execução termina inteira |
| T7 | Registro alterado **durante** a execução | Ou entra nesta execução, ou na próxima — nunca se perde entre as duas. A marca d'água usa o início da leitura, não o fim |
| T8 | Registro sem data de alteração | Tratado como sempre-desatualizado e relido; nunca ignorado silenciosamente |
| T9 | Primeira carga (sem marca d'água) | Lê tudo, em páginas, e termina com a marca d'água correta |

## 3. Exclusão, cancelamento e reaparecimento

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T10 | Registro excluído ou inativado na origem | O espelho marca como excluído e para de contar nos indicadores; a linha **não** é apagada — o histórico do que já foi lido continua |
| T11 | Documento cancelado (venda, título) | A situação muda no espelho; um pedido cancelado deixa de somar em faturamento no mesmo instante |
| T12 | Registro excluído volta a existir com o mesmo identificador | Reativa a linha existente em vez de criar outra |
| T13 | `external_id` reaproveitado para outro registro (identificador reciclado) | Detectado pela divergência de conteúdo e **recusado com alarme**, não aplicado por cima. É a falha mais perigosa da lista: sobrescreve um cliente com outro |

## 4. Falhas de transporte

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T14 | Tempo esgotado na chamada | A execução falha de forma limpa e pode ser repetida; o que já entrou continua válido |
| T15 | Resposta 429 (limite de requisições) | Espera e tenta de novo, respeitando o limite; não desiste da execução inteira por causa disso |
| T16 | Resposta 500 na origem | Nova tentativa com intervalo crescente; depois do limite, o registro vai para a fila morta e a execução continua |
| T17 | Falha no meio da paginação | A execução termina como parcial, com registro explícito de até onde leu; a marca d'água **não** avança |
| T18 | Credencial inválida ou expirada | Falha imediata e visível; nada é apagado nem marcado como excluído por causa da falta de resposta |
| T19 | Conexão cai depois do envio e antes da resposta | A repetição não duplica (T1); o estado é reconstruído pelo identificador da origem |

## 5. Contrato e formato

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T20 | Campo novo aparece na resposta | Guardado no registro bruto, ignorado pela normalização, **registrado como aviso** — mudança de contrato se descobre assim |
| T21 | Campo obrigatório some da resposta | O registro é recusado com erro explícito; não entra no espelho com o campo vazio fingindo que o dado não existe |
| T22 | Tipo muda (número vira texto, data muda de formato) | Recusado na normalização, com o valor original preservado no bruto para auditoria |
| T23 | Valor de situação desconhecido | Preservado como veio e marcado como não mapeado; nunca convertido em "o mais parecido" |
| T24 | Fuso horário ausente ou diferente do combinado | Normalizado para um fuso único e explícito; datas sem fuso são tratadas como suspeitas, não como locais |
| T25 | Relógios fora de sincronia entre origem e destino | A marca d'água tolera uma folga; um registro alterado "no futuro" não trava a leitura seguinte |

## 6. Reconciliação

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T26 | Contagem da origem diferente da contagem do espelho | A reconciliação aponta a diferença por entidade; corrigir é passo separado e explícito |
| T27 | Registro existe no espelho e não na origem | Apontado como divergência; só vira exclusão com confirmação da origem |
| T28 | Divergência plantada de propósito (teste) | Encontrada pela reconciliação — é assim que se prova que ela funciona |
| T29 | Espelho atrasado além do limite | Vira alerta de saúde da integração, com a hora da última sincronização bem-sucedida por entidade |

## 7. Fronteira com o resto do sistema

| # | Cenário | O que precisa acontecer |
| --- | --- | --- |
| T30 | Sincronização em andamento e alguém consultando os indicadores | A leitura vê um estado coerente — nunca metade de uma execução |
| T31 | Qualquer rotina da integração tentando escrever no ERP | Impossível por construção: o acesso é somente leitura. O teste existe para provar que continua assim |
| T32 | Preço vindo da tabela de fabricante × preço vindo do ERP | O do ERP prevalece; o da tabela documental é resposta de memória ("o documento informa"), nunca gravação em produto |
| T33 | Evento de venda da Compusystem chegando ao BRAIN | Entra por `brain.ingest_event` com a fonte própria; a idempotência já existente por `(source, external_id)` é quem protege |

---

## Exemplo fictício, só para fixar o formato

Nada abaixo veio da Compusystem. É um desenho de teste, não um contrato.

```
# FICTÍCIO — não é a API da Compusystem
GET /exemplo/vendas?alterado_desde=2026-09-01T00:00:00-03:00&pagina=2
{
  "pagina": 2, "paginas": 7,
  "itens": [
    {"id": "EX-0001", "numero": "12345", "situacao": "faturada",
     "alterado_em": "2026-09-02T10:15:00-03:00", "cliente_id": "EX-C-77"}
  ]
}
```

O teste T1 pega essa resposta, processa duas vezes e confere que o espelho tem
uma linha só. O T20 acrescenta um campo que a normalização não conhece e
confere que ele sobrevive no bruto sem quebrar nada. O T13 troca o conteúdo de
`EX-0001` por outro cliente e confere que a integração **recusa**.
