# AGROTORK BRAIN — Fase 2: inventário de documentos e ordem de ingestão

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (ver `ARCHITECTURE.md` §14).

Levantamento de 15/09/2026 nas pastas comerciais do computador do Wilson.
**Nenhum arquivo foi movido, renomeado ou apagado**; nada foi ingerido.
Serve para responder uma pergunta só: **qual é o próximo lote, e por quê.**

O inventário da Etapa 0 (`fase-2-etapa-0.md`) continua válido; este o
atualiza com o que mudou desde então e com os arquivos que ele não cobria.

---

## 1. Estado da memória hoje

Em produção: um documento ativo, o **Catálogo Magnojet V41** (172 páginas,
778 trechos, 270 tabelas, 202 confiáveis e 68 degradadas). Nada mais.

Preparado fora de produção nesta rodada: **Tabela Subdealer DJI**, duas versões
(V14.11 histórica, V16.2 vigente), golden 9/9 e adversariais 16/16 — ver
`fase-2-dji-subdealer.md`.

## 2. Documentos comerciais encontrados

Pasta `Downloads/04 - Tabelas de Preco e Marketing`, por relevância. "Camada
textual" significa que o PDF tem texto de verdade e **não precisa de OCR**.

| Documento | Fabricante | Tipo | Pág. | Bytes | Extração | Nota |
| --- | --- | --- | --- | --- | --- | --- |
| `MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf` | Magnojet | catálogo | 172 | 177,7 MB | textual | **já em produção (V41)** |
| `TABELASUBDEALERV16.2  B.pdf` | DJI/ALLCOMP | tabela de preço | 1 | 93 KB | textual | preparado, pronto para gate |
| `TABELA-SUBDEALER-V14.11.pdf` | DJI/ALLCOMP | tabela de preço | 2 | 872 KB | textual | preparado, pronto para gate |
| `TABELA-SUBDEALER-V15.1 - B.pdf` | DJI/ALLCOMP | tabela de preço | 4 | 2,9 MB | textual | versão intermediária; fora do lote atual |
| `CATÁLOGO V40 DIGITAL.pdf` | Magnojet | catálogo | — | 161,8 MB | textual | **edição anterior do V41** — histórico |
| `TABELA REV JAN261.pdf` | JR Soluções | tabela de preço | 1 | 233 KB | textual (7 tabelas em 1 pág.) | é a fonte de `source_catalog='TABELA REV JR'` |
| `Catálogo de Produtos JR Soluções.pdf` | JR Soluções | catálogo | 2 | 4,4 MB | textual | casa com os 38 produtos JR |
| `Catálogo Digital JR.pdf` | JR Soluções | catálogo | 7 | 6,1 MB | **imagem — exige OCR** | mesmo conteúdo, pior origem |
| `CATÁLOGO-ALBUZ-BR.pdf` | Albuz | catálogo | 24 | 11,3 MB | **imagem — exige OCR** | pontas; vizinho técnico do Magnojet |
| `panfleto-albuz-digital.pdf` | Albuz | folheto | — | 26,3 MB | não inspecionado | material de marketing |
| `Lista de Preço Agosto-2025.pdf` | (a confirmar) | tabela de preço | 1 | 501 KB | textual (7 tabelas) | preço de 2025 — histórico |
| `baldan-folheto-racr.pdf` | Baldan | folheto técnico | 2 | 259 KB | textual | linha RACR |
| `Folder_LYNX_2025.pdf` | Lynx | folheto | — | 30,4 MB | não inspecionado | — |
| `CATALOGO PRODUTOS - PROJETA AGRÍCOLA 2024.pdf` | Projeta | catálogo | — | 14,4 MB | não inspecionado | com tabela de preços própria |
| `DJI AGRICULTURE - AGRAS T55 + Promoção...pdf` | DJI | banner 70×120 | — | 124,4 MB | arte | **não é fonte** — é peça gráfica |
| `Campanha de T70P e T100 (Subdealer) ALLCOMP.pptx` | ALLCOMP | campanha | — | 1,0 MB | pptx | confirma o emissor das tabelas |

Planilhas de preço (`.xlsx`) da mesma pasta — `TABELA DE PREÇO NOVA 2026`,
`TABELA DE PREÇOS`, as três `Tabela de preço BSS 2024`, `RTV LISTA DE PREÇOS
2025-01` — são internas ou de terceiros e precisam de uma decisão de escopo
antes de qualquer ingestão: algumas são tabela de fornecedor, outras são
proposta da própria AGROTORK. Não entram enquanto isso não estiver claro.

## 3. Preflight das lacunas do golden (sem ingerir)

| Alvo do golden | Fonte existe? | Onde | Sustentaria? |
| --- | --- | --- | --- |
| **ARAG 466113200** (sensor de pressão) | **sim** | `Downloads/08 - Planilhas e Relatorios/Arag.xlsx` (9.974 bytes, sha `3d36a7f8a242dc4c…`) | **sim** — planilha com `COD`, descrição, tensão, corrente, sinal, faixa de operação e valor. O 466113200 aparece como SENSOR PRESSAO, 0-20 BAR, R$ 1.098 |
| **ARAG 4626215** (fluxômetro) | **sim** | mesmo arquivo | **sim** — FLUXOMETRO WOLF, 2,5–50 L/min, R$ 1.630 |
| **KUHN** (manual de semeadora) | **não** | nenhum arquivo com "kuhn" ou "semeadora" no computador | **não** — lacuna de fonte confirmada, como já registrado |
| **FIGHTER AD-IA** (calibração) | **sim** | `Downloads/06 - Tecnico, Manuais e Treinamentos/Calibração MARCHIONI/FIGHTER AD-IA.pdf` (1.523.781 bytes, sha `f2fd522cbf3db492…`, 17 páginas) | **sim** — relatório de calibração com camada textual e tabelas por seção (vazão média L/min, vazão total, coeficiente de variação, % aprovado) |

Ressalva importante sobre a ARAG: o arquivo é uma **planilha interna da
AGROTORK** (orçamento de sistema para bicos hidráulicos), não um catálogo
oficial ARAG. Responde o golden, mas a fonte precisa ser declarada pelo que
é — `kind` interno, `access_level` commercial — e nunca apresentada como
documento do fabricante.

Também na mesma pasta de calibração: `FIGHTER CV-IA`, `FIGHTER MUG`,
`VALTRA AD-IA`, `VALTRA MUG`, `JD MUG`, `JD ST` e `Report Test` — sete
relatórios irmãos, mesma estrutura. Se um funcionar, funcionam todos.

## 4. Prioridade do próximo lote

Critérios: quantas perguntas do golden o documento fecha, valor comercial,
qualidade do documento, facilidade de leitura, cobertura de produto, risco e
dependência de OCR. Nenhum deles depende da Compusystem.

**P0 — fecham golden aberto**

| Lote | Por quê | Custo |
| --- | --- | --- |
| **DJI Subdealer V14.11 + V16.2** | já preparado e ensaiado; fecha as perguntas de preço, versão e histórico | só o gate de produção |
| **ARAG (planilha)** | fecha 466113200 e 4626215, os dois códigos do golden que hoje dão zero por falta de fonte | baixo: xlsx, 1 aba, leitura direta |

**P1 — tabela comercial essencial**

| Lote | Por quê | Custo |
| --- | --- | --- |
| **JR: `TABELA REV JAN261.pdf` + `Catálogo de Produtos JR Soluções.pdf`** | os 38 produtos JR do catálogo AGROTORK vêm daí; camada textual, 7 tabelas numa página | baixo |
| **Magnojet V40** | edição anterior do documento já ativo: exercita versão histórica com um documento que já conhecemos | médio (161 MB) |

**P2 — técnico**

| Lote | Por quê | Custo |
| --- | --- | --- |
| **FIGHTER / calibração MARCHIONI** | sete relatórios com camada textual e tabelas limpas; responde pergunta de campo ("que vazão deu na calibração") | baixo por arquivo |
| **Albuz** | catálogo de pontas, vizinho técnico do Magnojet | **alto: é imagem, exige OCR** |
| **Baldan RACR, Projeta, Lynx** | folhetos de linha; cobertura de catálogo | baixo a médio |

**P3 — histórico**

`Lista de Preço Agosto-2025`, planilhas BSS 2024, RTV 2025: só quando houver
pergunta que exija série histórica de preço.

### Recomendação

Depois do gate do DJI, **o próximo lote é ARAG**. É o de melhor relação entre
esforço e resultado: uma planilha de 10 KB, uma aba, leitura direta, e fecha
dois códigos que hoje o BRAIN responde com zero. E exercita um caminho que
ainda não foi exercitado com documento real — **fonte `.xlsx`**, onde cada aba
é uma página. O JR vem em seguida, por ser o que mais casa com o catálogo que
já está em `products`.

Albuz fica para quando houver disposição de encarar OCR: 24 páginas de imagem
é o dobro de trabalho de qualquer outro item desta lista, e o Magnojet já cobre
a mesma pergunta técnica para a marca que a AGROTORK mais vende.
