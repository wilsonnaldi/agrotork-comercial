# AGROTORK BRAIN — lote ARAG: calibração local

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14).

Primeiro lote de **planilha** da memória corporativa. Preparado inteiramente
fora de produção: o arquivo foi lido, o suporte a `.xlsx` foi auditado e
corrigido onde estava errado, a planilha foi ingerida num PostgreSQL
descartável e submetida a golden e adversariais.

**Golden 7/7. Adversariais 12 de 14 — e as duas falhas são um bloqueio real
de produção, não um detalhe de teste.** Ver §7.

Reproduzir:

```
PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
  bash supabase/db-tests/ensaiar-arag.sh "<caminho>/Arag.xlsx"
```

---

## 1. O arquivo

| | |
| --- | --- |
| Caminho | `Downloads/08 - Planilhas e Relatorios/Arag.xlsx` |
| Bytes | 9.974 |
| SHA-256 | `3d36a7f8a242dc4c5ec1762908bb5fa15064593df5901c96ec34b84a00d9c1d9` |
| Modificado (sistema de arquivos) | 17/10/2024 |
| Abas | 1 — `Página1`, visível, sem proteção, sem filtro, sem congelamento |
| Dimensão declarada | A1:I220 — **16 linhas com conteúdo, 204 vazias** |
| Células mescladas | 4 (`A1:I1`, `A8:H8`, `A10:I10`, `A17:H17`) |
| Fórmulas | 12 (`=H3*A3`, `=SUM(I3:I7)`, …) |
| Metadata do documento | **não existe**: o `.xlsx` não traz `docProps/core.xml`, então não há autor nem data de criação. Qualquer leitor que mostre "criado por openpyxl, hoje" está exibindo o **valor padrão** da biblioteca, não o arquivo |

A única data com evidência é a do sistema de arquivos: **17/10/2024**. É ela
que serve de `valid_from`, e o documento registra que é data técnica, não
vigência comercial declarada.

## 2. Proveniência: de quem é este documento

**A fonte é a AGROTORK, não a ARAG.** O arquivo é um orçamento interno de dois
sistemas de pulverização montados com peças ARAG (e de outros fabricantes:
a bomba `5538/2L1/94A` e a válvula `863T026S` não são necessariamente ARAG).
Não há carimbo, cabeçalho, logotipo ou metadata que o ligue oficialmente à
ARAG do Brasil.

Chamá-lo de "catálogo ARAG" daria a ele uma autoridade que ele não tem: um
preço de orçamento interno de 2024 responderia como se fosse tabela do
fabricante. O registro correto:

```
FONTE      key agrotork_interno
           name AGROTORK — documentos internos
           kind internal
           default_access_level commercial
           external_processing forbidden

DOCUMENTO  slug agrotork-orcamento-sistemas-arag
           title Orçamento interno — sistemas ARAG para bicos
           document_type internal_note
           access_level commercial
```

Marca relacionada: ARAG (`public.brands` `cf3eaca0-9014-4a33-91e8-968b39ee30a6`).
Quando houver catálogo oficial da ARAG, ele entra como fonte própria
(`key = arag`, `kind = manufacturer`), e a diferença entre "o fabricante diz" e
"nosso orçamento de 2024 dizia" fica visível na citação.

## 3. A estrutura, e o que ela quebrou

A aba tem **dois blocos empilhados**, cada um com título em célula mesclada,
cabeçalho próprio, cinco itens e uma linha TOTAL, separados por uma linha
vazia:

```
linha 1   SISTEMA PARA BICOS HIDRAULICOS        (mesclada A1:I1)
linha 2   QUANTIDADE | DESCRICAO | COD | TENSAO | CORRENTE | SINAL | FAIXA OPERACAO | VALOR UNITARIO | VALOR TOTAL
linhas 3-7  itens
linha 8   TOTAL                                  (mesclada A8:H8)
linha 9   (vazia)
linha 10  SISTEMA PARA BICOS ROTATIVOS           (mesclada A10:I10)
linha 11  cabeçalho de novo
linhas 12-16 itens
linha 17  TOTAL
```

O worker, como estava, lia a aba inteira como **uma tabela só**: o título do
primeiro sistema ficava valendo para as linhas do segundo, e o cabeçalho
repetido da linha 11 virava linha de dados. Pior: a tabela saía marcada
`trusted`. Uma pergunta sobre o sistema rotativo seria respondida sob o título
do hidráulico — a versão documental da verdade paralela.

Três correções genéricas (nenhuma menciona ARAG):

| Correção | O que faz | Onde |
| --- | --- | --- |
| `split_stacked` | Blocos separados por linha inteiramente vazia viram tabelas distintas. Conservador: 4+ linhas úteis, bloco de 2+ linhas, 2+ blocos | `tables.py` |
| Cabeçalho repetido no corpo é sinal **fatal** | Linha que repete os próprios rótulos é cabeçalho caído; a tabela vira `degraded` e a busca não a usa. Rede de segurança para quando não houver linha vazia separando | `tables.py` |
| Proveniência de planilha | Planilha não tem página: a nota do trecho passa a ser **`aba: Página1, linhas 1–8`** | `tables.py` + `extract.py` |

E uma quarta, que resolve um problema de código:

| Correção | O que faz |
| --- | --- |
| Coluna que **se declara** de código (`COD`, `CÓDIGO`, `REF`, `SKU`) tem seu conteúdo lido como código | Resgata `46202G`, `863T026S` e `5538/2L1/94A`, que começam por dígito e que nenhum padrão genérico alcança sem produzir falso positivo em `4-20MAH` ou `0,5AH`. Aqui não se adivinha: o documento já disse que aquela coluna é código |

Resultado: **2 tabelas, ambas `trusted`**, cada uma com seu título e seu
intervalo de linhas.

## 4. Golden — 7 de 7

| # | Pergunta | Esperado | Encontrado | Evidência | |
| --- | --- | --- | --- | --- | --- |
| G1 | `466113200` | SENSOR PRESSAO, 0-20 BAR | idem, em 2 blocos | texto | PASS |
| G1b | valor unitário do sensor | 1098 | 1098 | JSONB | PASS |
| G2 | `4626215` | FLUXOMETRO WOLF, 2,5-50 l/min | idem | texto | PASS |
| G2b | valor unitário do fluxômetro | 1630 | 1630 | JSONB | PASS |
| G3 | proveniência | aba + intervalo de linhas | `aba: Página1, linhas 1–8` e `linhas 10–17` | notas | PASS |
| G4 | dois blocos | dois títulos distintos | hidráulicos e rotativos | `table_data.title` | PASS |
| G5 | `46202G` (começa por dígito) | reconhecido | pela coluna COD, só no bloco rotativo | `codes` | PASS |

O que os dois códigos do golden respondem, exatamente como está na planilha e
sem nada acrescentado:

- **466113200** — SENSOR PRESSAO, 12V, 0,5AH, sinal 4-20MAH, faixa 0-20 BAR, valor unitário 1.098. Aparece **nos dois sistemas** (linhas 3 e 12).
- **4626215** — FLUXOMETRO WOLF, 12V, 0,5AH, "1 pulso 5,8v a cada x ML", faixa 2,5-50 l/min, valor unitário 1.630. Só no sistema hidráulico (linha 4).

Não há coluna de marca, categoria ou unidade na planilha. **Não foram
inventadas**: o golden registra os campos que existem.

## 5. Adversariais — 12 de 14

C (preço não vira código) · D (telefone e CNPJ não viram código) · E (exato
entra pelo braço exato) · F (aproximação acha o dígito faltando, não o código
distante) · G (linha vazia não vira produto) · H (cabeçalho não vira dado) ·
I (fórmula não vaza como texto) · J (um bloco não empresta contexto ao outro) ·
K (código presente nos dois sistemas devolve as duas evidências) · L (produto
inexistente → zero) · M (nenhuma tabela degradada) · N (zero escrita no ERP).

**A e B falham**, e é bloqueio de produção — §7.

## 6. Limitações registradas

1. **Código numérico com decimal.** `402085.10` está guardado na planilha como número (402085,1). O texto pesquisável mostra `402085,1` e o código sai como `402085.1`. É o que o arquivo contém; corrigir exigiria saber que aquilo é código com duas casas, e a planilha não diz.
2. **Código de 6 dígitos não é reconhecido por padrão.** `402745` só entra porque está na coluna `COD`. O padrão genérico exige 7 a 9 dígitos de propósito: seis dígitos é o tamanho de um preço (`165500`), e baixar o limite criaria falso positivo em toda tabela comercial.
3. **Fórmula sem valor calculado fica vazia.** A linha TOTAL do segundo bloco tem `=SUM(...)` com valor em cache, e aparece; uma fórmula gravada por ferramenta que não calcula chegaria como nada. Nunca como texto cru — isso está testado (W30).
4. **Dinheiro em ponto flutuante**, como no lote DJI e pelo mesmo motivo: a coluna é `jsonb`, o sistema só armazena e cita, e trocar a representação agora seria migration e reingestão por motivo estético.

## 7. Bloqueio para produção: aproximação em código numérico

O adversarial A e o B falham, e a causa é a mesma:

```
busca por 466113201  (código que NÃO existe)  → devolve 2 trechos do 466113200
busca por 46262150   (código que NÃO existe)  → devolve 1 trecho do 4626215
```

O braço aproximado de `brain.search_knowledge` aceita candidato com
similaridade de trigrama **≥ 0,6**. Medido:

| Par | Similaridade | Deveria casar? | Casa hoje? |
| --- | --- | --- | --- |
| `466113201` × `466113200` | **0,667** | não — é outra peça | **sim** |
| `46262150` × `4626215` | **0,700** | não | **sim** |
| `4626215` × `4626216` | **0,600** | não | **sim, no limite** |
| `MJ981CA` × `MJ981CAP` | 0,700 | **sim** — letra faltando é erro de digitação | sim |
| `MJ999CAP` × `MJ981CAP` | 0,385 | não | não |
| `DB1580` × `DB1050` | 0,273 | não | não |
| `C12000` × `C10000` | 0,444 | não | não |

O limiar funciona bem para código **alfanumérico** e falha para código
**puramente numérico**: num número de peça cada dígito é significado, não há
ortografia, e um dígito trocado é outra peça — nunca um erro de digitação que
o sistema deva resolver sozinho. O corpo ARAG é inteiramente numérico, e é por
isso que o problema aparece aqui e não apareceu no Magnojet nem no DJI.

**Correção proposta** (uma linha na CTE `codigo` de `brain.search_knowledge`,
migration nova, não escrita nesta rodada): excluir do braço aproximado os
códigos em que **tanto a consulta quanto o candidato são puramente numéricos**
— para esses, só casamento exato.

```sql
-- dentro do exists(...) do braço aproximado, acrescentar:
  and not (qc ~ '^[0-9]+$' and cc ~ '^[0-9]+$')
```

Isso não mexe em nada que hoje funciona: `MJ981CA → MJ981CAP` continua (tem
letras), e todos os pares alfanuméricos acima seguem idênticos. Precisa de
migration, teste na suíte 36 e GO do ChatGPT — **é decisão de segurança de
busca, não de worker**, e por isso não foi aplicada por conta própria.

**Enquanto não for corrigido, o lote ARAG não vai a produção**: ingerir um
corpo de códigos numéricos com essa busca significa responder pergunta sobre
uma peça com o preço de outra.

## 8. Gate produtivo

| Gate | Situação | O que falta |
| --- | --- | --- |
| GO técnico | **PARCIAL** | Golden 7/7 e 12 de 14 adversariais. Faltam A e B, que dependem da correção de §7 |
| GO governança | **SIM** | A proveniência está resolvida: fonte interna da AGROTORK, marca ARAG relacionada, nada apresentado como catálogo de fabricante |
| GO produção | **NÃO** | Depende de §7 |

Ordem recomendada: corrigir a busca (migration + suíte 36 + GO do ChatGPT) →
rodar `ensaiar-arag.sh` de novo e ver A e B verdes → então o gate produtivo do
ARAG, que é curto: registrar fonte e documento, ingerir, rodar o golden,
ativar.
