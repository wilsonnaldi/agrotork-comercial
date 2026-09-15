# AGROTORK BRAIN — lote DJI Subdealer: pacote de pré-deploy

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14). Nada deste lote
> escreve em nenhum dos dois.

Continuação de `fase-2-dji-subdealer.md`, que fechou o gate **técnico**
(golden 9/9, adversariais 16/16, regressão do Magnojet preservada). Este
documento prepara o gate de **produção** — e não executa nada. Nenhuma linha
foi escrita em produção, nenhuma migration foi criada, nenhuma versão ativada.

---

## 1. Fonte e emissor: quem assina o documento

O documento é uma tabela de preço da linha DJI Agriculture **emitida pela
ALLCOMP**, distribuidor, para revendas subdealer. Marca e emissor são coisas
diferentes, e o esquema já sabe distinguir as duas — `knowledge_sources` tem
`kind` (`manufacturer`, `supplier`, `distributor`, `internal`, `regulator`,
`other`) e `brand_id`, que aponta para `public.brands`. **Nenhum schema novo é
necessário.**

| Opção | Vantagem | Risco | Impacto futuro |
| --- | --- | --- | --- |
| `key = dji` | É a marca que o vendedor procura; alinha com `brands.slug='dji'`; um manual da DJI cairia na mesma fonte | **A citação mentiria por omissão**: diria "DJI — Tabela Subdealer", emprestando ao preço do distribuidor a autoridade do fabricante. E se amanhã houver outro distribuidor, os dois viram a mesma fonte e não há como separar | Ruim: a fonte deixa de identificar quem emitiu |
| `key = allcomp` | Verdadeiro. A citação diz quem assinou. Preço de distribuidor fica identificado como tal; trocar de distribuidor mantém o histórico legível | Quem busca "DJI" não acha pela fonte — mas acha pela marca (`brand_id`) e pelo conteúdo (T55, T100, DB1580 estão no texto). Exige uma segunda fonte `dji` quando entrar documento do próprio fabricante | Bom: escala para vários distribuidores da mesma marca |
| `key = dji_allcomp` | Carrega os dois nomes num campo só | Chave composta num campo que não é composto. Não escala (`dji_outro`, `dji_terceiro`), e nenhuma consulta agrupa "tudo da DJI" ou "tudo da ALLCOMP" sem quebrar string | Ruim: dívida de modelagem desde o primeiro dia |
| **`key = allcomp` + `brand_id` = DJI** | As duas informações, cada uma no campo que já existe para ela: emissor na fonte, fabricante na marca | Nenhum conhecido. Exige preencher `brand_id`, que hoje fica nulo | **Recomendado** |

### Proposta

```
brain.knowledge_sources
  key                   allcomp
  name                  ALLCOMP — distribuidor DJI Agriculture
  kind                  distributor
  brand_id              698a1bcd-8d11-40ab-9058-9426f3b1039d   (public.brands 'DJI')
  default_access_level  commercial
  external_processing   forbidden
```

A citação passa a ser **"ALLCOMP — Tabela Subdealer DJI V16.2, p. 1"**: quem
emitiu, o que é, qual versão, qual página. Quando entrar documento assinado
pela própria DJI (manual, datasheet), ele ganha fonte `dji`
(`kind = manufacturer`, mesmo `brand_id`), e uma consulta por marca alcança as
duas sem confundi-las.

**Pendente de confirmação do Wilson com a ALLCOMP** — ver §2.

## 2. Versões: o que é rótulo e o que é evidência

Nenhum dos três PDFs traz o número da versão no texto. A metadata de dois
deles contradiz o nome do arquivo. Portanto o `version_label` é **declarado**,
não inferido, e isso precisa de confirmação externa antes da ingestão.

| Rótulo | Arquivo | Título interno (metadata) | SHA-256 | Pág. | Criado (metadata) | Arquivo modificado | Vigência comercial comprovada? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| V14.11 | `TABELA-SUBDEALER-V14.11.pdf` | `TABELA-SUBDEALER-**V14.10**.docx` | `dc5e4b851086c0ac…2974f29a` | 2 | 14/01/2026 09:30 (−03) | 15/01/2026 | **não** |
| V15.1 | `TABELA-SUBDEALER-V15.1 - B.pdf` | `TABELA-SUBDEALER-V15.1.xlsx` ✔ | `0b59225a943f9c7b…7290d88c` | 4 | 19/05/2026 13:45 UTC | 27/05/2026 | **não** |
| V16.2 | `TABELASUBDEALERV16.2  B.pdf` | `TABELA-SUBDEALER-**V16.1**` | `3ea3bc5940376212…cf8634e5` | 1 | 04/08/2026 13:55 UTC | 02/09/2026 | **não** |

Três perguntas para a ALLCOMP, e são de uma linha cada:

1. Os rótulos comerciais desses três arquivos são V14.11, V15.1 e V16.2?
2. Cada tabela tem data de início de vigência? Qual?
3. A V16.2 é a vigente hoje?

### Estratégia conservadora de datas, enquanto não há resposta

Não inventar vigência. `valid_from` = **data de criação do PDF** (a mais antiga
data em que se pode provar que o documento existia), e a diferença entre data
técnica e vigência comercial fica registrada no próprio documento:

```
V14.11  valid_from 2026-01-14  valid_to 2026-05-18  status superseded
V15.1   valid_from 2026-05-19  valid_to 2026-08-03  status superseded
V16.2   valid_from 2026-08-04  valid_to (aberto)    status active
```

com `metadata.provenance_note`:
*"Rótulo de versão declarado pela AGROTORK a partir do nome do arquivo; o
documento não o traz no texto e a metadata interna diverge (V14.10 / V16.1).
valid_from é a data de criação do PDF, não vigência comercial informada pelo
emissor."*

Quando a ALLCOMP responder, corrigir é um `update` de três linhas.

## 3. V15.1 entra em produção? Recomendação: **sim, as três** — com uma ressalva

| Critério | V14.11 + V16.2 | As três |
| --- | --- | --- |
| Valor histórico | duas pontas: o que mudou entre elas | a curva inteira |
| Continuidade de preço | **não responde "quando mudou"** — o T100 subiu já no V15.1 | responde |
| Golden | cobre o atual e o histórico | acrescenta o intermediário |
| Linhagem | cadeia de dois | cadeia real de três, com `supersedes` encadeado |
| Custo | — | +4 páginas, +11 trechos |
| Risco | — | duas tabelas `degraded` na p.1 (fail-closed cuida) |
| Redundância | — | baixa: preços diferentes em cada versão |

O argumento decisivo é o primeiro: **o preço à vista do T100 mudou de 159.000
para 161.900 no V15.1**, não no V16.2. Sem essa versão, a pergunta "quando o
preço mudou?" tem resposta errada. E a V15.1 é a única das três cuja metadata
concorda com o nome do arquivo — é a mais confiável quanto ao próprio rótulo.

**Ressalva, e ela precisa de decisão:** a V15.1 tem 4 páginas, e as páginas 2 a
4 **não são tabela DJI**. São plataformas GranDdock, faturadas pela **Zait**,
com preço cliente final e revendedor e código FINAME. Entraram no mesmo PDF
como anexo.

Duas saídas honestas:

- **(i) ingerir a V15.1 inteira** — a citação sempre carrega versão e página, então quem ler "V15.1, p. 2" vê de onde veio. É o que se recomenda: recortar páginas seria publicar como "V15.1" um arquivo que não é o V15.1;
- (ii) ingerir só a p. 1 — exigiria uma opção de recorte que o worker não tem, e criaria um documento que não corresponde a nenhum arquivo real.

Se o Wilson preferir separar, o caminho limpo é um **segundo documento**
(`zait-granddock`, fonte `zait`, `kind = supplier`) apontando para o mesmo
arquivo — não recortar este.

## 4. Identificadores previstos

Nada foi criado. UUID nenhum é inventado: os que o banco gera ficam marcados
como "gerado no insert".

```
FONTE
  key                   allcomp
  name                  ALLCOMP — distribuidor DJI Agriculture
  kind                  distributor
  brand_id              698a1bcd-8d11-40ab-9058-9426f3b1039d
  default_access_level  commercial
  external_processing   forbidden

DOCUMENTO
  source_key            allcomp
  slug                  dji-tabela-subdealer
  title                 Tabela Subdealer DJI
  document_type         price_list
  access_level          commercial
  id                    (gerado no insert)

VERSÕES                 id (gerado no insert) para as três
  V14.11  arquivo TABELA-SUBDEALER-V14.11.pdf     sha dc5e4b85…f29a  2 pág.  application/pdf
          storage  brain-documents/allcomp/dji-tabela-subdealer/V14.11/<sha>.pdf
  V15.1   arquivo TABELA-SUBDEALER-V15.1 - B.pdf  sha 0b59225a…d88c  4 pág.  application/pdf
          storage  brain-documents/allcomp/dji-tabela-subdealer/V15.1/<sha>.pdf
  V16.2   arquivo TABELASUBDEALERV16.2  B.pdf     sha 3ea3bc59…34e5  1 pág.  application/pdf
          storage  brain-documents/allcomp/dji-tabela-subdealer/V16.2/<sha>.pdf

CADEIA                  V14.11 → V15.1 → V16.2   (supersedes / superseded_by)
ATIVA PLANEJADA         V16.2
PIPELINE                lote-b.2
INGESTÃO                uma por versão (id gerado no insert)
```

O bucket `brain-documents` **não existe** em produção (roteiro
`operacao/07`). Enquanto não for criado, a ingestão roda com o arquivo local e
`storage_path` fica registrado sem objeto — foi assim no piloto Magnojet.

## 5. Golden que roda DEPOIS da ingestão em produção

O mesmo conjunto que passou no ensaio, agora contra produção. Com as três
versões, o histórico ganha um degrau a mais (G3m).

| # | Consulta | Esperado | Versão | Pág. | Evidência | |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | "Qual bateria avulsa serve para T55 e T70P?" | DB1580 | V16.2 | 1 | texto | ☐ |
| G1b | "bateria avulsa T55 DB1050" | `T55 (DB1050)` | V16.2 | 1 | texto | ☐ |
| G1c | "bateria T100 T70P DB2160" | `T100 / T70P (DB2160)` | V16.2 | 1 | texto | ☐ |
| G2 | versão vigente | V16.2 `active`, V14.11 e V15.1 `superseded` | — | — | linhagem | ☐ |
| G3 | "DRONE AGRAS T100 3 BAT CARREGADOR C12000 preço" | 165.500 / 161.900 / 225.000 | V16.2 | 1 | texto | ☐ |
| G3m | idem, filtro `version_label=V15.1`, superseded | à vista 161.900 | V15.1 | 1 | JSONB | ☐ |
| G3h | idem, filtro `version_label=V14.11`, superseded | à vista 159.000 | V14.11 | 1 | JSONB | ☐ |
| G4 | "T25P carregador C8000" | 64.250 / 61.789 / 87.000 | V16.2 | 1 | JSONB | ☐ |
| G5a | "T55 DB1050 carregador C7000" | 101.401 / 96.483 / 130.000 | V16.2 | 1 | JSONB | ☐ |
| G5b | "T55 DB1580 carregador C12000" | 119.400 / 113.789 / 156.000 | V16.2 | 1 | JSONB | ☐ |

Cada linha tem que devolver também a **citação** de
`brain.chunk_provenance(chunk_id)` — no formato "ALLCOMP — Tabela Subdealer
DJI V16.2, p. 1" — e o `version_id`. Os 16 adversariais A–P
(`ensaiar-dji.sh`) rodam na sequência, com um acréscimo: com a V15.1 no meio,
o adversarial **M** (consulta histórica não mistura versões) passa a valer
para três versões, não duas.

## 6. Rollback

`supabase/operacao/09-remover-documento-ingerido.sql`, já escrito e **testado
num banco descartável**: remove as versões, páginas, trechos e ingestões de um
documento por cascata, conta tudo antes de apagar (guarda de cardinalidade),
imprime os caminhos de Storage para apagar à parte, e **não remove a fonte** —
a chave estrangeira é `RESTRICT` e o roteiro só avisa se ela ficou órfã.
Transação única, com `rollback;` comentado no fim para o caso de a contagem
não bater.

No ensaio, removeu 2 versões, 3 páginas, 39 trechos e 2 ingestões, deixando a
fonte intacta e o banco zerado de conteúdo.

## 7. Gates

| Gate | Situação | O que falta |
| --- | --- | --- |
| **GO técnico** | **SIM** | Nada. Golden 9/9, adversariais 16/16, worker auditado genericamente, Magnojet sem regressão |
| **GO governança** | **PENDENTE** | Confirmação da ALLCOMP sobre os rótulos das três versões e a vigência; decisão do Wilson sobre a fonte (`allcomp` + `brand_id`) e sobre a V15.1 inteira × documento Zait separado |
| **GO produção** | **NÃO** | Depende do de cima. Depois: registrar fonte e documento, ingerir pelo PowerShell com `BRAIN_DB_URL` de produção, rodar o golden de §5, e só então marcar V16.2 como `active` |

Sem maquiagem: o lote está pronto **tecnicamente** e parado **por governança**.
A pergunta que destrava é de uma linha, e é com a ALLCOMP.
