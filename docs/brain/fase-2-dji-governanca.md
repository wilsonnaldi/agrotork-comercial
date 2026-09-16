# AGROTORK BRAIN — lote DJI Subdealer: gate de governança

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14).

O lote DJI está **tecnicamente pronto e travado por governança**. Este
documento registra o que foi apurado nos arquivos, o que ainda precisa vir da
ALLCOMP, e os dois caminhos de ingestão conforme a resposta deles.

**Nada foi ingerido em produção.**

## 1. Os três arquivos, auditados

Sem modificar nenhum byte. Conferido em 16/09/2026.

| | V14.11 | V15.1 | V16.2 |
| --- | --- | --- | --- |
| Arquivo | `TABELA-SUBDEALER-V14.11.pdf` | `TABELA-SUBDEALER-V15.1 - B.pdf` | `TABELASUBDEALERV16.2  B.pdf` |
| sha256 | `dc5e4b85…4f29a` | `0b59225a…0d88c` | `3ea3bc59…634e5` |
| bytes | 871.878 | 2.990.205 | 93.131 |
| páginas | 2 | 4 | 1 |
| Título interno | `TABELA-SUBDEALER-**V14.10**.docx` | `TABELA-SUBDEALER-**V15.1**.xlsx` | `TABELA-SUBDEALER-**V16.1**` |
| Produtor | Microsoft: Print To PDF | Skia/PDF m148 (Chrome) | Skia/PDF m150 (Chrome) |
| Origem | Word | Google Planilhas | Google Planilhas |
| Criação | 14/01/2026 09:30:36 −03 | 19/05/2026 13:45:46 UTC | 04/08/2026 13:55:05 UTC |
| Autor | vazio | ausente | ausente |

### As divergências — que são evidência, não erro a corrigir

- **V14.11**: o nome do arquivo diz V14.11, o título interno diz **V14.10**.
- **V15.1**: nome e título internos batem.
- **V16.2**: o nome diz V16.2, o título interno diz **V16.1**.

E um fato que vale mais que os três juntos: **nenhum dos PDFs declara a
versão no próprio texto**. Varrendo o corpo das sete páginas não existe
nenhuma ocorrência de "V14.11", "V15.1" ou "V16.2". O rótulo de versão vem
exclusivamente do **nome do arquivo** — que é um dado da AGROTORK, não uma
declaração da ALLCOMP.

É por isso que a confirmação dos rótulos não é burocracia: hoje não há como
provar, a partir do documento, que a tabela que chamamos de V16.2 é a que a
ALLCOMP chama de V16.2.

## 2. O que precisa vir da ALLCOMP

Três perguntas, e só três:

1. Os rótulos comerciais corretos são V14.11, V15.1 e V16.2?
2. Existe data oficial de início de vigência para cada uma?
3. A V16.2 é a tabela vigente hoje?

## 3. A fonte: ALLCOMP, não DJI

| campo | valor |
| --- | --- |
| `key` | `allcomp` |
| `name` | ALLCOMP — distribuidor DJI Agriculture |
| `kind` | `distributor` |
| `default_access_level` | `commercial` |
| `external_processing` | `forbidden` |
| marca relacionada | DJI (em `brain.documents.brand_id`) |

Quem emitiu a tabela foi a ALLCOMP, distribuidora. A DJI é a **marca** dos
produtos, não a autora do documento — ela não assina esses preços. Registrar
a fonte como "DJI" daria à tabela uma autoridade de fabricante que ela não
tem, e é o mesmo erro que o lote ARAG evitou.

O ensaio `ensaiar-dji.sh` foi alinhado a este modelo: a fonte era `dji` /
`manufacturer` e passou a ser `allcomp` / `distributor`.

## 4. A V15.1 tem quatro páginas, e só a primeira é DJI

| página | conteúdo | é DJI? |
| --- | --- | --- |
| 1 | DRONE AGRAS T100 / T70P / T25P, baterias, carregadores, geradores | **sim** |
| 2 | Ddock — Baú, Basic, Lite, Top, Connect, Wheather | não |
| 3 | GranDdock TOP/Connect/Weather — "Produto faturado pela **Zait**" | não |
| 4 | RTK SOUTH G7Q / ALPS1, controladora H6/H9, piloto automático **Sunnav** | não |

Uma correção ao enunciado da rodada, para a auditoria: as páginas 2–4 **não
são todas Zait/GranDdock**. As páginas 2 e 3 são Ddock/GranDdock (faturadas
pela Zait); a página 4 é um terceiro contexto — RTK South e piloto Sunnav.
Quando forem tratadas, provavelmente serão **dois** documentos lógicos, não
um.

### O modelo suporta isso? Sim — e foi provado, sem schema novo

Testado em banco descartável com as migrations reais:

- **Mesmo arquivo físico em dois documentos lógicos: permitido.** A restrição
  `uq_version_file` é `UNIQUE (document_id, file_sha256)` — por documento. O
  mesmo sha256 entra nos dois.
- **Os caminhos têm de ser distintos.** `storage_path` é único global e
  `chk_version_path_has_sha` exige que termine em `/<sha>.<ext>`. Os dois
  caminhos gerados satisfazem as duas regras:
  - `allcomp/dji-tabela-subdealer/V15.1/0b59225a….pdf`
  - `zait/zait-ddock-granddock/2026-05/0b59225a….pdf`
- **Subconjunto de páginas: permitido.** `document_pages` tem PK
  `(version_id, page_no)` e só exige `page_no >= 1`. Não há regra de
  contiguidade. O documento DJI registra a página **1**; o documento Zait
  registraria as páginas **2, 3 e 4** com a numeração original — a citação
  continua dizendo a verdade sobre onde o dado está no PDF.
- **Fechar como `completed` com 1 de 4 páginas: permitido**, desde que
  `ingestion_start` declare `pages_total = 1`. A função recusa `completed`
  quando as páginas gravadas ficam abaixo do total declarado.

**O que NÃO suporta: o worker.** `brain_worker ingest` não tem opção de
subconjunto de páginas — ele ingere o arquivo inteiro. Essa é a limitação
real, e ela é do worker, não do schema.

Duas saídas, nenhuma inventando schema:

- **(a) Documento de passagem** — ingerir o arquivo inteiro num documento
  descartável, copiar a página 1 e os trechos dela para a versão DJI pelas
  mesmas funções `brain.ingestion_*`, e apagar o documento de passagem. É o
  que o ensaio já faz hoje, e é a mesma técnica do lote ARAG: nada é digitado
  à mão e o PDF original não é tocado. **Recomendada para a ingestão.**
- **(b) `--pages` no worker** — mais limpo a longo prazo, mas é mudança de
  código com testes próprios. Fica como rodada futura, não como pré-requisito.

O que **não** se faz: recortar o PDF, ou publicar Ddock/GranDdock/Zait/RTK
South sob o título "Tabela Subdealer DJI".

## 5. Achado de qualidade: a V15.1 entra com duas tabelas degradadas

Na página 1 da V15.1, dois blocos saem marcados `degraded`:

| bloco | sinais |
| --- | --- |
| DRONE AVULSO (SÓ CAIXA, COM CONTROLE) | 3 linhas de cabeçalho caídas como dados; coluna sem rótulo propagado |
| BATERIA AVULSA | 2 linhas de cabeçalho caídas; 3 de 5 colunas sem cabeçalho |

A causa é visível no PDF: naquela página os preços estão **riscados**
(`-R$ 96.750,00-`), e o risco quebra a reconstrução da tabela. V14.11 e V16.2
não têm nenhuma degradada.

Isso **não é defeito do ensaio nem bloqueio**: é o worker marcando o que não
entendeu, e a busca recusando esses dois blocos como evidência (fail-closed).
Nenhum item do golden depende deles. Mas é uma perda real de cobertura na
V15.1, e está registrado aqui para a auditoria decidir se importa.

## 6. Golden final — 10/10

Rodado com a cadeia das três versões:

```
PGHOST=/tmp/pgrun PGPORT=5433 PGUSER=postgres \
  bash supabase/db-tests/ensaiar-dji.sh \
    "<caminho>/TABELA-SUBDEALER-V14.11.pdf" \
    "<caminho>/TABELASUBDEALERV16.2  B.pdf" \
    "<caminho>/TABELA-SUBDEALER-V15.1 - B.pdf"
```

O terceiro argumento é opcional: sem ele, a cadeia curta V14.11 → V16.2 que
já existia continua rodando igual (9/9 + 16/16, conferido).

| | prova | resultado |
| --- | --- | --- |
| F1 | DB1580 avulsa T55/T70P | V16.2 |
| F2 | DB1050 → T55 | V16.2 |
| F3 | DB2160 → T100/T70P | presente nas três versões |
| F4 | cadeia V14.11 → V15.1 → V16.2, V16.2 vigente | ok |
| F5 | T100+C12000 V16.2 | 165.500 / 161.900 / 225.000 |
| F6 | T100+C12000 V15.1 | 165.500 / 161.900 / 225.000 |
| F7 | T100+C12000 V14.11 | 165.500 / **159.000** / 225.000 |
| F8 | T25P+C8000 V16.2 | 64.250 / 61.789 / 87.000 |
| F9 | T55 DB1050+C7000 V16.2 | 101.401 / 96.483 / 130.000 |
| F10 | T55 DB1580+C12000 V16.2 | 119.400 / 113.789 / 156.000 |

Mais três provas que não contam ponto mas travam regressão: proveniência
completa em todo hit (`version_id`, rótulo, página, fonte `allcomp`,
documento); T55 **não existe** na V14.11 nem na V15.1 (é produto novo da
V16.2); e a V15.1 do documento DJI não tem nenhum trecho de
Ddock/GranDdock/Zait/RTK South.

### Duas descobertas que mudam como o golden tem de ser lido

1. **T100 + C12000 é idêntico na V15.1 e na V16.2** — 165.500 / 161.900 /
   225.000 nas duas. O preço à vista subiu de 159.000 (V14.11) para 161.900
   (V15.1) e parou. Ou seja: **o T100 não distingue V15.1 de V16.2.** Quem
   separa as duas é o **T25P**, que caiu de 79.000 para 64.250 (−19%).
   Um golden que só olhasse T100 daria falso verde.
2. **O T100 vira tabela só na V14.11.** V15.1 e V16.2 vêm do Google Planilhas
   (Skia) e naquela faixa não há borda para a reconstrução morder — o bloco
   fica como trecho de texto. Por isso F7 lê do JSONB e F5/F6 leem do texto.
   Não é perda: o valor está lá e é citável; muda só por onde se confere.

## 7. Cenário A — ALLCOMP confirma tudo

`version_label` = o rótulo que a ALLCOMP confirmar. `valid_from` = a data
oficial de cada tabela. `status` pela cadeia: V14.11 e V15.1 `superseded`,
V16.2 `active`. `metadata.provenance_note` registra que rótulo e vigência
foram confirmados pela ALLCOMP, com a data da confirmação e o canal.

## 8. Cenário B — ALLCOMP não confirma, ou não tem a data

Conservador, e explícito sobre o que não se sabe:

- `version_label` = o rótulo do **nome do arquivo** (V14.11, V15.1, V16.2),
  declarado pela AGROTORK, não pela ALLCOMP.
- `valid_from` = a data técnica mais antiga comprovável do PDF — a data de
  criação interna (14/01/2026, 19/05/2026, 04/08/2026), que é anterior ou
  igual a qualquer data de sistema de arquivos.
- `metadata.provenance_note` diz, em letras claras:
  - o rótulo veio do nome do arquivo;
  - o documento **não declara a versão no texto**;
  - o título interno diverge (V14.10 na V14.11; V16.1 na V16.2);
  - `valid_from` é data técnica, **não** vigência comercial oficial;
  - a ALLCOMP não confirmou até a data da ingestão.

A cadeia e o `status` seguem iguais — a ordem entre as três é observável
pelas datas de criação, independentemente do rótulo.

## 9. Rollback

`supabase/operacao/09-remover-documento-ingerido.sql` com
`v_slug := 'dji-tabela-subdealer'`. Auditado contra o estado ingerido:
remove versões, páginas, trechos, ingestões e o documento; **mantém a fonte
`allcomp`** e avisa que ela ficou órfã. Lista o caminho de Storage de cada
versão antes de apagar, para o objeto ser removido à parte depois.

## 10. O que falta para a produção

Só a resposta da ALLCOMP. Tudo o mais está pronto e conferido.
