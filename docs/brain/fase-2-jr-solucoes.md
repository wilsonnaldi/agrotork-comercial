# AGROTORK BRAIN — lote JR Soluções: pré-ingestão

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14).

Preparação do lote da tabela de preços JR Soluções, feita inteiramente fora de
produção em 16/09/2026.

**Resultado: BLOQUEADO — e agora o bloqueio tem um endereço só: o arquivo.**

Em 16/09 o lote estava golden 5/10 e adversariais 8/12, e a suspeita era que
o motor precisasse de conserto. Em 17/09 o motor foi consertado (§11) e a
conta ficou assim:

| | 16/09 | 17/09 | |
| --- | --- | --- | --- |
| Adversariais | 8/12 | **11/12** | o motor melhorou |
| Golden | 5/10 | **3/10** | e é assim que tinha de ser |
| Tabelas `trusted` com produto faltando | 6 | **0** | |

O golden **caiu de propósito**. Antes, quatro provas passavam lendo tabelas
que a busca aceitava como confiáveis e que tinham um produto a menos e nomes
de coluna que eram valores de outro produto. Agora essas tabelas são
corretamente recusadas — e o sistema prefere não responder a responder daquilo.
Golden menor, integridade maior.

O que **não** se resolve no motor está em §5.6.

Reproduzir:

```
PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
  bash supabase/db-tests/ensaiar-jr.sh "<caminho>/TABELA REV JAN261.pdf"
```

## 1. O arquivo

| | |
| --- | --- |
| Caminho | `Downloads/04 - Tabelas de Preco e Marketing/TABELA REV JAN261.pdf` |
| Bytes | 232.716 |
| sha256 | `434c15a9ec1ea2c7ef4eac5746fea808be7a8b208bb4df5c9d432f4844a9a52f` |
| Páginas | 1 |
| Camada textual | sim — 4.126 caracteres, sem OCR |
| Producer / Creator | Microsoft® Excel® 2021 |
| Criação / modificação | 04/02/2026 16:28:20 −03 (iguais) |
| Autor (metadata) | `USER` |

**O que o documento declara**, no próprio corpo da página:

- emissor: "INDÚSTRIA E COMÉRCIO DE PEÇAS ROTOMOLDADAS / MÁQUINAS, SOLUÇÕES
  INDUSTRIAIS E AGRÍCOLAS";
- título e competência: **"Tabela de preços atualização Janeiro 26 - JR
  Soluções"**;
- colunas: `CÓDIGO · NCM · PRODUTO · REVENDAS · SUGERIDO`.

**O que é metadata técnica**, e não declaração: o autor `USER`, o produtor
Excel 2021, e as datas de criação e modificação. A data de criação
(04/02/2026) é **posterior** à competência declarada (Janeiro/26) — o arquivo
foi gerado em fevereiro a partir de uma tabela de janeiro.

**O que é inferência minha**, e está marcado como tal onde aparece: que
"Janeiro 26" significa a competência comercial de janeiro de 2026. O documento
não diz dia de início nem de fim de vigência.

Diferente do lote DJI, aqui **não há gate de governança**: o documento diz o
seu próprio nome e a sua própria competência, e quem assina é o fabricante.

## 2. Fonte e marca

| campo | valor |
| --- | --- |
| `key` | `jr_solucoes` |
| `name` | JR Soluções |
| `kind` | `manufacturer` |
| `default_access_level` | `commercial` |
| `external_processing` | `forbidden` |

A JR Soluções é fabricante ("INDÚSTRIA E COMÉRCIO DE PEÇAS ROTOMOLDADAS") e
assina a própria tabela — `manufacturer` está certo, sem a ambiguidade
distribuidor-versus-fabricante do lote DJI.

**Marca:** `public.brands` já tem `JR SOLUÇÕES` (com acento — é a grafia
oficial, e a armadilha do `slugify` está registrada no `CLAUDE.md`). Nada a
criar.

## 3. Documento

`jr-solucoes-tabela-revendas` · "Tabela de preços para revendas — JR Soluções"
· `price_list` · `commercial`.

## 4. `valid_from` — era inimplementável em 16/09; foi consertado em 17/09

> **Resolvido.** A migration `20260917120000_brain_vigencia_nao_declarada`
> tirou o fallback de data do gatilho de ativação. `valid_from = NULL` agora
> sobrevive e significa "vigência inicial não declarada" — que é exatamente o
> caso da JR. O ensaio foi atualizado: `document_date = 2026-01-01` (a
> competência que o PDF declara), `valid_from` NULL, versão ativa e vigente.
> A migration **não foi aplicada em produção**. O texto abaixo é o
> diagnóstico original, mantido porque é a medição que motivou o conserto.

A rodada pedia para preferir `valid_from = NULL` e só usar uma data com
necessidade técnica comprovada. **Testei, e NULL não sobrevivia à ativação.**

`20260912010000_brain_memoria_esquema.sql:315`:

```sql
new.valid_from := coalesce(new.valid_from, new.document_date, current_date);
```

Medido em banco descartável:

| cenário | `valid_from` depois de ativar |
| --- | --- |
| `document_date = 2026-01-01` | **2026-01-01** |
| sem `document_date` | **2026-09-16** — a data da ativação |

Ou seja: a escolha não é entre uma data e NULL. É entre **uma data que o
documento sustenta** e **a data em que alguém apertou o botão**. A segunda é
pior: não tem relação nenhuma com o documento e parece oficial.

Confirmei também que, antes da ativação, `register_version` de fato deixa
`valid_from` nulo, e que com nulo a busca funciona (`current_version` bate, a
CTE de vigência aceita `valid_from is null`). O problema é só a ativação.

**Decisão de 16/09, com a necessidade técnica comprovada que a rodada
exigia:** `document_date = 2026-01-01`, e `metadata.provenance_note`
registrando:

- a competência **JAN/26 é declarada pelo documento**;
- **nenhum dia oficial de início de vigência foi informado** pela JR;
- `2026-01-01` é o primeiro dia da competência declarada, escolhido porque o
  schema carimbava `current_date` se nada fosse informado;
- as datas técnicas do arquivo (04/02/2026) **não foram promovidas** a
  vigência comercial.

### 4.1 O que mudou em 17/09

O terceiro item acima era uma escolha feita **contra** o banco, não com ele.
Ela deixou de ser necessária.

| | 16/09 | 17/09 |
| --- | --- | --- |
| `document_date` | 2026-01-01 | 2026-01-01 — a competência declarada |
| `valid_from` depois de ativar | 2026-01-01 (promovido) | **NULL** — não declarado |
| se não houvesse `--date` | 2026-09-16 (dia da ativação) | **NULL** |

A JR declara a competência e não declara dia de início. Agora o banco guarda
as duas coisas separadas, e nenhuma delas é inventada. A versão continua
`active` e continua sendo a que `current_version()` devolve: **"não
declarado" não é "inválido"** — a leitura sempre soube disso (`valid_from is
null or valid_from <= current_date`), era a gravação que atropelava.

A prova L do ensaio passou a exigir esse estado inteiro, e a suíte 38
(`38_brain_vigencia_nao_declarada.sql`) tranca os oito casos.

## 5. O que bloqueia: a extração

A tabela tem **o cabeçalho uma vez só**, no topo. Os blocos seguintes
(`LINHA "LE"`, `LINHA "XT"`, `LINHA PICK UP`, …) são continuações visuais sem
cabeçalho próprio. A reconstrução trata cada bloco como uma tabela nova e
**promove a primeira linha de dados a cabeçalho**.

O retrato medido: 1 página, 11 trechos, 9 tabelas, **3 degradadas**, **29
linhas** preservadas em `rows` — para **38 linhas de produto legíveis** no
PDF.

### 5.1 Nove produtos viram nome de coluna

Em 8 das 9 tabelas, `labels[2]` é um código de produto e `labels[3]` é um NCM.
Exemplo real (`ord 3`):

```
labels = ['', 'LINHA "LE" AGITAÇÃO HIDRÁULICA', '1243', '84368000',
          'DRONE MIX 130L LE Agitação Hidráulica 220Volts',
          'R$ 5 .600,00', 'R$ 8 .200,00', '']
```

O produto 1243 não está em `rows`: ele **é** o cabeçalho. São 9 produtos
perdidos assim — a diferença entre 38 e 29.

### 5.2 E seis dessas tabelas passavam como `trusted` — corrigido em 17/09

Este era o achado mais sério. O auditor tinha a regra certa, mas o limiar não
pegava este caso:

```python
numeric_labels = sum(1 for h in (t.labels or t.headers) if parse_number(h) is not None)
if width and numeric_labels >= width / 2:
    issues.append(f"... linha de dados engolida")
```

Com 8 colunas são precisos **4** cabeçalhos numéricos. Aqui a linha engolida
tem **2** células numéricas (código e NCM) — as outras são texto. Então o
sinal não dispara e a tabela entra como **confiável**.

Resultado: 6 tabelas com um produto faltando e nomes de coluna que são valores
de outro produto **eram aceitas pela busca como evidência**. Pior que
degradada: degradada é recusada; aquela era servida.

**Corrigido** — ver §11.1. Hoje as 9 tabelas degradam corretamente e nenhuma
com produto faltando segue `trusted`.

### 5.3 O código do produto não vira código; o NCM vira

Nenhum código de produto entrou em `codes`. Em **todos** os 11 trechos,
`codes` contém só NCM: `84329000`, `84368000`, `84369000`, `84818099`,
`90282010`.

Duas causas somadas:

1. como o cabeçalho não foi reconhecido como `CÓDIGO`, o caminho de coluna
   declarada não disparou (é o que funcionou no lote ARAG com a coluna `COD`);
2. `brain.query_codes` reconhece número puro como código **de 7 a 9 dígitos**.
   Os códigos da JR têm **3 ou 4** (`2141`, `879`, `1243`) — ficam de fora. Os
   NCMs têm 8 — entram.

Medido direto na função:

| entrada | `query_codes` |
| --- | --- |
| `2141` | `{}` |
| `879` | `{}` |
| `84368000` | `{84368000}` |

É exatamente ao contrário do útil: o que identifica a peça é invisível, o que
não identifica (classificação fiscal compartilhada por 30 produtos) responde
pelo braço de código em 4 trechos.

**Corrigido do lado da extração** — ver §11.2. O NCM saiu de `codes` e o
braço exato deixou de responder por ele (medido: de 4 trechos para 0).

Sobre a **fronteira de `query_codes`**: ela não precisou ser mexida. Ver
§11.3 — com os códigos extraídos, buscar "2141" já funciona.

### 5.4 Dois produtos estão fisicamente sobrepostos no PDF

A primeira linha da tabela traz duas linhas impressas uma sobre a outra:

```
11239663 8844336688000000 DDRROONNEE MMIIXX 123000LL LLTT NNEEWW …
```

É a intercalação de `1296`/`1363`, de `84368000` duas vezes, e de
`R$ 5.600,00`/`R$ 6.900,00`. São os produtos **1296 (DRONE MIX 130L LT NEW)** e
**1363 (200L LT NEW)**. O worker marcou o trecho como `degraded / fatal` com
"4 celula(s) com numeros fundidos" — **o fail-closed funcionou**. Mas os dois
produtos ficam sem evidência.

Defeito do arquivo, não do worker. Corrige-se pedindo à JR um PDF sem
sobreposição, ou gerando o PDF de novo a partir da planilha.

### 5.5 Preços perdem a formatação de forma inconsistente

Na mesma coluna convivem `'R$ 8 .200,00'` (string) e `10200.0` (número), além
de `'R$ 3 30,00'` e `'R$ 5 40,00'` — o `R$ 330,00` com espaço no meio. Não
impede a leitura, mas obriga quem consome a tratar dois tipos na mesma coluna.

### 5.6 Por que as 9 linhas não se recuperam: o PDF não tem cabeçalho limpo

O cabeçalho verdadeiro (`CÓDIGO NCM PRODUTO REVENDAS SUGERIDO`) aparece **uma
vez só**, no topo — e essa única ocorrência está **fundida com as duas linhas
sobrepostas do §5.4**. Os rótulos da primeira tabela saem assim:

```
['', '', 'CÓDIGO 1296', 'NCM 84368000',
 'PRODUTO REVENDAS DRONE MIX 130L LT NEW 2x18lpm 12volts R$ 5 .600,00', …]
```

Não existe, em lugar nenhum do arquivo, uma linha de cabeçalho íntegra. Para
recuperar as 9 linhas seria preciso **adivinhar** onde termina a palavra do
cabeçalho e começa o dado, dentro de células que já carregam dois produtos
sobrepostos. Isso é inventar conteúdo, e não se faz.

**A correção é a montante:** pedir à JR um PDF sem sobreposição, ou gerar o
PDF de novo a partir da planilha. Com um cabeçalho legítimo, a cadeia inteira
funciona — é o que os testes W35 e §11.3 demonstram em tabela com cabeçalho.

## 6. Semântica comercial

Nada foi renomeado nem interpretado.

- **`REVENDAS`** → `preco_revendas`. O PDF **não declara condição de
  pagamento**: não diz à vista, faturado, prazo nem desconto. Fica registrado
  como **CONDIÇÃO DE PAGAMENTO NÃO DECLARADA**. Não virou "custo", "à vista"
  nem "preço de compra".
- **`SUGERIDO`** → preço sugerido do documento. **Não** é
  `public.products.sale_price` — e a medição do §7 mostra que de fato não é.

## 7. Cruzamento PDF × ERP

Produção, **somente SELECT**. 38 produtos com `source_catalog = 'TABELA REV JR'`
e `source_version = 'JAN/26'` — o número bate com o registrado.

| classe | qtd |
| --- | --- |
| **A** match exato (código + preço) | **35** |
| **B** mesma peça, sem código no PDF | **3** |
| **C** preço documental ≠ ERP | **0** |
| **D** produto do PDF ausente no ERP | **0** |
| **E** produto do ERP ausente no PDF | **2** |
| **F** ambíguo | **0** |

**A (35):** o `REVENDAS` do PDF bate **centavo a centavo** com
`public.product_costs.cost_price` na condição `AVISTA`, para os 35 produtos com
código legível.

**B (3):** `JR-024`, `JR-034` e `JR-035` — as três linhas em que o PDF não traz
CÓDIGO (uma tem a célula vazia, outra tem `*`, outra só o NCM). O ERP também
tem `manufacturer_code` nulo nesses três. Casaram por preço, sem ambiguidade.

**E (2):** `JR-001` (1296) e `JR-002` (1363) — exatamente os dois produtos
sobrepostos do §5.4. Estão corretos no ERP (5.600 e 6.900), o que indica que a
carga os leu de uma origem legível, não deste PDF.

**Onde cada coluna foi parar** — e esta é a conclusão que importa:

| coluna do PDF | onde está no ERP |
| --- | --- |
| `REVENDAS` | `product_costs.cost_price`, condição `AVISTA` — **custo**, não preço |
| `SUGERIDO` | **em lugar nenhum** |
| — | `products.sale_price` é preço da AGROTORK, definido depois; não é nenhuma das duas colunas |

Exemplo: `879` (MEDIDOR DE FLUXO DIGITAL) — PDF `REVENDAS 300` / `SUGERIDO 450`;
ERP custo AVISTA `300,00`, `sale_price` `440,00`. Os três números são
diferentes e cada um tem um dono.

**Nada foi corrigido no ERP.** Não havia o que corrigir: a divergência classe
C é zero.

## 8. Golden e adversariais

Golden **5/10**: passam G2 (879 por prosa), G3 (descrição natural), G6
(inexistente → zero), G9 (proveniência) e G10 (isolamento de fonte). Falham
G1, G4, G5 (o produto 2141 foi engolido pelo cabeçalho), G7 (nenhum código de
produto em `codes`) e G8 (o NCM responde pelo braço de código).

Adversariais **8/12**: falham B (o NCM devolve 4 trechos), D (ver abaixo), G
(6 tabelas `trusted` com dado no cabeçalho) e H (29 linhas de 38).

**Adversarial D, e é achado próprio:** "DRONE MIX 9000L TURBO" — produto que
não existe — devolve **3 trechos**, todos com `rank_exact` nulo, ou seja por
prosa. A regra de cobertura de lexemas (≥ 0,5 e ≥ 2 lexemas) é satisfeita só
com "drone" e "mix". Num catálogo em que **quase todo produto começa por
"DRONE MIX"**, esse filtro é fraco. Não é regressão nem defeito do braço de
código; é uma característica dos braços de prosa encontrando um corpo de
nomes muito repetitivos. Vale medir de novo depois que os códigos passarem a
funcionar, porque aí a intenção de código assume.

## 9. Regressão

Nenhum código de produção mudou nesta rodada — só entrou `ensaiar-jr.sh` e
esta documentação. Ainda assim:

| | |
| --- | --- |
| Worker (pytest) | **46/46** |
| Suíte de banco | sem falha nova; as 5 herdadas da 25 seguem iguais |
| ARAG | golden **7/7**, adversariais **14/14** |
| Magnojet | golden **14/14**, provas **12/12**, degraded leak **0** |
| numeric exact-only | preservado (suíte 37 verde na suíte de banco) |
| DJI | continua **ausente** de produção |
| Golden v1 | consistente |

## 10. Rollback

`09-remover-documento-ingerido.sql` com
`v_slug := 'jr-solucoes-tabela-revendas'`, **executado** no banco descartável
depois da ingestão de ensaio:

| | antes | depois |
| --- | --- | --- |
| documentos | 1 | **0** |
| versões | 1 | **0** |
| páginas | 1 | **0** |
| trechos | 11 | **0** |
| ingestões | 1 | **0** |
| **fontes** | 1 | **1 — `jr_solucoes` mantida** |
| ERP | 0 | 0 |

O roteiro imprimiu o caminho de Storage antes de apagar e avisou que a fonte
ficou órfã, deixando a remoção dela como decisão humana. Magnojet e ARAG não
foram tocados (não existem naquele banco; em produção o roteiro é por slug).

## 11. O que foi consertado no motor (17/09/2026)

Dois commits, cada um com teste próprio, nenhum específico da JR.

### 11.1 `fix(worker): detecta linha de dados engolida em cabeçalho`

Regra nova, genérica: **um cabeçalho NOMEIA a coluna; ele nunca É um preço.**
Se o símbolo de moeda aparece num rótulo, o que está ali é uma linha de
produto que a reconstrução promoveu a cabeçalho. Basta um — preço em rótulo
não acontece por acaso.

O teste é o **símbolo**, não o parse numérico: este PDF quebra
`R$ 5.600,00` em `R$ 5 .600,00`, e um parse estrito deixaria passar justamente
o caso que motivou a regra.

`"engolida"` já está em `FATAL_MARKERS`, então a tabela vira `degraded/fatal`
e a busca a recusa. **Não há tentativa de recuperar a linha** — fail-closed
correto primeiro.

Efeito medido: JR de 3 para **9** degradadas, **0** tabelas com produto
faltando em `trusted`. Nos corpos que já existiam, **nenhuma degradação nova**:
Magnojet segue em 56, DJI em 2, ARAG em 0. W34 trava isso com os cabeçalhos
reais dos três.

### 11.2 `fix(worker): NCM é classificação fiscal, não código de peça`

Quando a tabela **declara** uma coluna como NCM/NBM/CEST/HS code, os valores
dela saem de `codes`. Estrutural, não regex — o documento já disse o que
aquilo é.

Precedência explícita: se o mesmo valor também aparece numa coluna declarada
de **código**, ele fica (W36). O NCM continua inteiro em `table_data`.

Efeito medido: `84368000` deixou de responder pelo braço exato — de 4 trechos
para **0**.

### 11.3 `query_codes` não precisou mudar

A hipótese era que a janela de 7–9 dígitos teria de se abrir para caber código
de 3–4. **Testado ponta a ponta com os códigos já extraídos corretamente:**

| busca | resultado |
| --- | --- |
| `2141` | **1 hit**, trecho certo, `rank_trgm=1 rank_fts=1` |
| `879` | **1 hit**, trecho certo |
| `qual o preço do 2141?` | **1 hit** |
| `84368000` (NCM) | **0** |

O código curto **é encontrado** — pelos braços de prosa, não pelo braço de
código. O que muda sem alargar a janela é o **rank**, não a recuperação.

Alargar `query_codes` é mexer numa regra transversal do BRAIN, com migration
e efeito sobre Magnojet, ARAG e DJI. Fazer isso sem um documento que prove a
necessidade seria especulação. Fica registrado, não feito.

### 11.4 Herança de cabeçalho: implementada, medida, descartada

Tentei recuperar as 9 linhas fazendo o bloco de continuação herdar o cabeçalho
do bloco anterior. **Não dispara neste documento**, e o motivo é o §5.6: a
única ocorrência do cabeçalho verdadeiro está fundida com as linhas
sobrepostas, então não existe cabeçalho limpo para herdar. Removi em vez de
deixar código que nenhum corpo exercita.


## 12. O que falta para destravar

Três dos quatro itens que esta seção listava em 16/09 foram resolvidos em
17/09 (§11). O que sobrou é um item só — e ele não está no código.

1. **Pedir um PDF sem sobreposição**, ou gerar o PDF de novo a partir da
   planilha de origem. É a única correção que recupera as 9 linhas perdidas
   e os produtos 1296 e 1363, e é a única que o motor não pode fazer por
   conta própria sem adivinhar conteúdo (§5.6). **Este é o bloqueio.**

Resolvidos, para registro:

- ~~Fazer o auditor marcar como degradada a tabela cujo cabeçalho contém
  valor de produto~~ — §11.1. Hoje 0 tabelas passam confiáveis com produto
  faltando.
- ~~Decidir o que fazer com o NCM~~ — §11.2. Coluna fiscal declarada não
  alimenta `codes`; o NCM segue inteiro em `table_data`.
- ~~Rever a janela de 7–9 dígitos de `query_codes`~~ — §11.3. Medido: não
  precisa. O código curto é recuperado pelos braços de prosa; o que muda é o
  rank. Alargar a janela é mexer em regra transversal do BRAIN e não tem
  documento que prove a necessidade. Fica registrado como fronteira
  conhecida, não como pendência.

Nada disso é urgente: o lote não está em produção e o ERP já tem os 38
produtos com o custo certo. O que este ensaio garante é que, quando o arquivo
chegar corrigido, dá para medir no mesmo dia.
