# AGROTORK BRAIN — Fase 2, lote DJI Subdealer: calibração local

> **Nota de vocabulário.** Neste documento, "ERP" significa o schema `public`
> desta aplicação. Desde setembro/2026 o ERP da AGROTORK é a **Compusystem**
> (ver `ARCHITECTURE.md` §14); nada aqui escreve em nenhum dos dois.

Branch `brain/fase-2`. Preparação completa do lote DJI **fora de produção**:
os dois documentos foram lidos, calibrados, ingeridos num PostgreSQL
descartável e submetidos a golden e adversariais. **Nada foi ingerido,
registrado ou ativado em produção**, e nenhuma migration foi criada.

Reproduzir:

```
PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
  bash supabase/db-tests/ensaiar-dji.sh \
    "<caminho>/TABELA-SUBDEALER-V14.11.pdf" \
    "<caminho>/TABELASUBDEALERV16.2  B.pdf"
```

---

## 1. Os arquivos

| Versão | Arquivo | Bytes | SHA-256 | Páginas | Data do arquivo |
| --- | --- | --- | --- | --- | --- |
| V14.11 | `TABELA-SUBDEALER-V14.11.pdf` | 871.878 | `dc5e4b851086c0ac0d12473076a07f1f59520e6d6020f7a30c2253312974f29a` | 2 | 15/01/2026 |
| V15.1 | `TABELA-SUBDEALER-V15.1 - B.pdf` | 2.990.205 | `0b59225a943f9c7bd8ac45a453c2d7198812ac381643312b31aa2aa97290d88c` | 4 | 27/05/2026 |
| V16.2 | `TABELASUBDEALERV16.2  B.pdf` | 93.131 | `3ea3bc594037621e23e1af705d057faa00655e8caf75d75f9faf9814cf8634e5` | 1 | 02/09/2026 |

Todos em `Downloads/04 - Tabelas de Preco e Marketing`. Nenhuma duplicata
byte-a-byte na pasta; nenhum outro candidato a "subdealer DJI" no computador
(varredura por `subdealer`, `sub dealer`, `dji`, `agras`, `14.11`, `15.1`,
`16.2` em Downloads e Desktop/Agro Tork).

### A identidade da versão não está no documento

Achado que muda o desenho do lote: **nenhum dos três PDFs traz o número da
versão no texto**. A varredura por `V1x.y` no conteúdo extraído devolve nada
nos três. E a metadata contradiz o nome do arquivo em dois deles:

| Arquivo | Título interno (metadata) | Produtor | Criado em |
| --- | --- | --- | --- |
| `TABELA-SUBDEALER-V14.11.pdf` | `Microsoft Word - TABELA-SUBDEALER-**V14.10**.docx` | Microsoft: Print To PDF | 14/01/2026 |
| `TABELA-SUBDEALER-V15.1 - B.pdf` | `TABELA-SUBDEALER-V15.1.xlsx - Google Planilhas` | Skia/PDF m148 | 19/05/2026 |
| `TABELASUBDEALERV16.2  B.pdf` | `TABELA-SUBDEALER-**V16.1** - Google Planilhas` | Skia/PDF m150 | 04/08/2026 |

Ou o nome do arquivo está adiantado em relação ao documento que o gerou, ou a
planilha de origem não foi renomeada ao publicar. **A conclusão prática é a
mesma: o rótulo da versão é informação externa ao documento** e precisa ser
declarado por quem ingere, não inferido. Continua valendo o que já estava
decidido: `version_label` é dado de entrada, e a ordem entre versões vem de
`valid_from`/`supersedes`, nunca de comparar strings de nome de arquivo.

Pendência para o Wilson confirmar com a ALLCOMP: se "V14.11" e "V16.2" são os
rótulos comerciais corretos desses dois arquivos.

### Emissor

O documento é emitido pela **ALLCOMP** (distribuidor), não pela DJI. Na
preparação anterior isso apareceu na arte; nesta, aparece também no nome de um
material vizinho (`Campanha de T70P e T100 (Versão para Subdealer) ALLCOMP.pptx`).
A `knowledge_sources.key` ficou `dji` no ensaio, com nome "DJI / distribuidor
oficial" — **decisão de fonte (`dji` × `allcomp`) segue em aberto** e não
bloqueia nada: é um `update` de uma linha.

## 2. O que os documentos contêm

Os três são tabela de preço subdealer, com três condições por produto:
**Pgto faturado**, **Pgto à vista** e **CLIENTE FINAL MÍNIMO** (preço mínimo
que a DJI permite praticar). Nenhum tem camada de imagem: todos têm texto real,
**OCR não foi necessário em nenhum**.

O que muda entre eles é o que mais importa para a memória:

| | V14.11 | V15.1 | V16.2 |
| --- | --- | --- | --- |
| Linha T55 | **não existe** | **não existe** | existe (DB1050 e DB1580) |
| Baterias DB1580 / DB1050 | não | não | sim |
| T100 + 3 BAT + C12000, à vista | R$ 159.000,00 | R$ 161.900,00 | R$ 161.900,00 |
| T25P, cliente final mínimo | R$ 110.000,00 | R$ 110.000,00 | R$ 87.000,00 |
| T30 | vendido | "Saiu de linha" | "Saiu de linha" |
| Kit dual battery T100 | não | não | sim |

Duas coisas valem registro porque desmentem suposição comum: **o preço à vista
do T100 subiu já no V15.1**, não no V16.2; e **o preço mínimo ao cliente final
do T25P caiu** de 110 para 87 mil entre as versões — preço mínimo não é
monotônico, e qualquer regra que assuma "a versão nova é sempre mais cara" erra.

## 3. O que o parser encontrou (e o que foi corrigido)

O worker `lote-b.2`, como estava, lia esses documentos assim:

- **zero tabelas classificadas como `price_table`** — num documento que é só preço;
- **todas as tabelas marcadas `trusted`**, inclusive uma de 14 colunas onde 12 não tinham cabeçalho e os preços estavam em `col_4`, `col_7`, `col_12`;
- células monetárias em duas representações na mesma tabela: `165500` numa linha e o texto `-R$ 21.550,00-` na de baixo.

As correções são genéricas — nenhuma delas cita DJI, produto ou valor:

| Correção | Por que | Onde |
| --- | --- | --- |
| Traço decorativo em célula monetária (`-R$ 21.550,00-` → `21550.0`) | Exportação de planilha preenche a célula com hífen; o traço da frente só é decoração quando existe o de trás **e** há `R$`. Negativo de verdade (`R$ -21.550,00`) continua negativo | `tables.parse_number` |
| Coluna com moeda no corpo ganha unidade `BRL` | Em tabela comercial a moeda está na célula, não no cabeçalho. É isso que faz `price_table` ser reconhecida por conteúdo | `tables.build_table` |
| Preço em coluna sem nome é sinal **FATAL** | Valor que não diz se é à vista, faturado ou cliente final não é dado incompleto: é dado errado esperando para ser citado. A tabela fica `degraded` e a busca não a usa | `tables.audit_table` |
| Duas quantias na mesma célula contam como números fundidos | `-R$ 7.100,00--R$ 6.800,00-` é duas colunas que viraram uma | `tables.audit_table` |
| Unidade de uma letra só vale entre parênteses | "Pgto **à** vista" virava ampere e o preço saía "159000 A" | `tables._unit_of` |
| Título acima do cabeçalho vira `title` da tabela | O nome do produto está na linha de cima; sem promover a segunda linha, ele vira cabeçalho e os preços ficam em `col_1`/`col_2` | `tables.build_table` |
| Blocos lado a lado separados por calha vazia viram tabelas distintas | Juntos, o preço da direita responderia pergunta da esquerda | `tables.split_side_by_side` |
| Região que engloba outras é descartada | O detector devolvia a página inteira como uma tabela por cima das tabelas de verdade; o que sobra fora delas volta a ser texto, que é citável | `extract._table_regions` |

Resultado nos dois documentos:

| | antes | depois |
| --- | --- | --- |
| V14.11 — tabelas | 19, nenhuma `price_table`, 19 `trusted` sem cabeçalho de preço | **19 `price_table`, 19 `trusted`, com título e colunas nomeadas** |
| V16.2 — tabelas | 6, nenhuma `price_table`, 6 `trusted` (uma delas a página inteira) | **10 `price_table`, 10 `trusted`** + 6 trechos de texto citáveis |

## 4. Golden — 9 de 9

Rodado contra os documentos reais, num banco descartável, pelo
`ensaiar-dji.sh`. "JSONB" significa que o valor foi lido da tabela estruturada
(`table_data.rows`), não do texto.

| # | Pergunta | Esperado | Encontrado | Versão | Evidência | |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | Bateria avulsa para T55 e T70P | DB1580 | DB1580 | V16.2 | texto, p.1 (2 trechos) | PASS |
| G1b | T55 sozinho | DB1050 | `T55 (DB1050)` | V16.2 | texto, p.1 | PASS |
| G1c | T100 / T70P | DB2160 | `T100 / T70P (DB2160)` | V16.2 | texto, p.1 | PASS |
| G2 | Versão mais recente | V16.2 | V16.2 vigente, V14.11 `superseded` | — | linhagem | PASS |
| G3 | T100 + 3 BAT + C12000 (vigente) | 165.500 / 161.900 / 225.000 | idem | V16.2 | texto, p.1 | PASS |
| G3h | T100 + 3 BAT + C12000 (histórica) | à vista 159.000 | 159000 | V14.11 | JSONB, p.1 | PASS |
| G4 | T25P + 3 BAT + C8000 | 64.250 / 61.789 / 87.000 | idem | V16.2 | JSONB, p.1 | PASS |
| G5a | T55 + DB1050 + C7000 | 101.401 / 96.483 / 130.000 | idem | V16.2 | JSONB, p.1 | PASS |
| G5b | T55 + DB1580 + C12000 | 119.400 / 113.789 / 156.000 | idem | V16.2 | JSONB, p.1 | PASS |

## 5. Adversariais — 16 de 16

| | O que | Resultado |
| --- | --- | --- |
| A | T25P ≠ T25 | busca por T25P não traz tabela do T25 | PASS |
| B | T55 DB1050 ≠ T55 DB1580 | nunca compartilham preço | PASS |
| C | T100 ≠ T70P | nenhuma tabela mistura os dois | PASS |
| D | C7000 ≠ C12000 | nenhuma tabela mistura os dois | PASS |
| E | V14.11 ≠ V16.2 | 159.000 não aparece na busca normal | PASS |
| F | à vista ≠ faturado | nunca colapsam no mesmo valor | PASS |
| G | faturado ≠ cliente final mínimo | idem | PASS |
| H | "3 BAT" não vira preço | nenhuma quantidade virou valor | PASS |
| I | quantia não vira código | nenhum código de 5–6 dígitos nem começado por R | PASS |
| J | preço isolado não casa falso | só devolve trecho que contém o valor; valor inexistente → zero | PASS |
| K | produto inexistente | T999 → zero | PASS |
| L | versão inexistente | V15.9 não devolve V16.2 como se fosse ela | PASS |
| M | consulta histórica | pedido por V14.11 devolve só V14.11 | PASS |
| N | busca normal | só a versão vigente | PASS |
| O | tabela degradada | 29 tabelas de preço, nenhuma degradada — e degradada não entra na busca | PASS |
| P | preço nunca toca o ERP | zero produtos e zero custos criados pela ingestão | PASS |

## 6. Regressão do Magnojet

O catálogo V41 foi reprocessado inteiro com o worker corrigido:

| | produção (V41 ativa) | depois das correções |
| --- | --- | --- |
| páginas | 172 | 172 |
| chunks | 778 | 778 |
| tabelas | 270 | 270 |
| trusted / degraded | 202 / 68 | **205 / 65** |
| tabelas de vazão trusted | 55 | **55** |
| colunas marcadas BRL | — | **0** |

Três tabelas melhoraram de `degraded` para `trusted`; **nenhuma piorou**. O
reconhecimento de preço não disparou uma única vez num catálogo técnico, que é
o teste mais importante de que ele olha evidência e não palpite. O golden do
documento continua: MJ981CAP e MJ983CAP na p.20; MJ981CAP a 40 psi → 0,77 L/min
→ **77 L/ha a 12 km/h**, em tabela `trusted`; MJ999CAP e 466113200 ausentes;
M506/10 existe apenas numa tabela `degraded` da p.102 — invisível à busca, que
é exatamente o comportamento esperado.

## 7. Limitação conhecida: dinheiro em ponto flutuante

`table_data.rows` guarda números como JSON *number*; um preço com centavos vira
`float` (`61789.0`). Nas faixas destas tabelas não há perda — inteiros e `,00`
são exatos em ponto flutuante duplo —, e o sistema **só armazena e cita, nunca
calcula** com esses valores. Ainda assim é representação errada para dinheiro.

Não foi trocada de propósito: a coluna é `jsonb`, a mesma representação vale
para todo o corpo já ingerido (Magnojet em produção), e mexer nisso agora seria
migration e reingestão por motivo estético. Fica registrado como decisão
consciente, para o dia em que houver motivo real — e o dia em que houver, o
caminho é centavos em inteiro, sem migration de schema.

## 8. O que falta para este lote ir a produção

Nada disso foi feito, e nenhum passo abaixo acontece sem autorização explícita:

1. confirmar com a ALLCOMP os rótulos V14.11 e V16.2, e decidir `source_key` (`dji` × `allcomp`);
2. publicar os commits desta rodada e passar pelo CI;
3. registrar fonte e documento em produção, com `access_level = commercial`;
4. ingerir V14.11 (histórica) e V16.2 (vigente) pelo PowerShell do Wilson, com `BRAIN_DB_URL` apontando para produção;
5. conferir golden e adversariais contra produção;
6. só então marcar V16.2 como `active` e V14.11 como `superseded`.

A V15.1 fica de fora deste lote de propósito: ela é a terceira versão do mesmo
documento e entra depois, se o histórico intermediário for útil — registrar as
duas pontas já responde "o que mudou".
