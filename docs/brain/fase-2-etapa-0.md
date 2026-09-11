# AGROTORK BRAIN — Fase 2, Etapa 0: memória corporativa (auditoria e projeto)

11/09/2026 · projeto Supabase `nedmdkdhchkadijtdnja` · PostgreSQL 17.6 · branch `brain/fase-2`.
Nesta etapa **nada foi criado no banco, nenhum documento foi ingerido, nenhum embedding
foi gerado, pgvector continua desabilitado**. Tudo o que está aqui é medição (produção e
arquivos do Wilson, lidos no lugar) e projeto.

## 1. Estado final da Fase 1 no Git

| Item | Estado medido |
|---|---|
| `origin/brain/fase-1` | `00ef6f1` — CI `BRAIN Fase 1` **success** |
| `origin/main` | `26b004c` — **é ancestral** de `origin/brain/fase-1` (13 commits à frente; fast-forward possível, sem merge commit) |
| Commit documental `8217557` | **local, não publicado**: o push desta sessão é recusado pelo proxy (repositório fora do conjunto autorizado). Bundle `agrotork-brain-fase1-v8-fechamento.bundle` em `Downloads` |
| Produção × migrations | 10 migrations do BRAIN registradas (`…130000` … `…220000`), todas presentes em `origin/brain/fase-1`; nada em produção fora do Git |

O fechamento no repositório principal (push de `8217557`, CI, fast-forward de `main`,
push de `main`) **não foi executado** por bloqueio de canal, não por decisão. O que precisa
rodar, nesta ordem, em PowerShell no clone do Wilson:

```powershell
git fetch "C:\Users\wilag\Downloads\agrotork-brain-fase1-v8-fechamento.bundle" brain/fase-1:brain/fase-1-v8
git checkout brain/fase-1
git merge --ff-only brain/fase-1-v8
git push origin brain/fase-1            # aguardar o CI de 8217557 ficar verde
git checkout main
git merge --ff-only brain/fase-1        # sem merge commit
git push origin main
```

`FASE 1 ENCERRADA TAMBÉM NO REPOSITÓRIO PRINCIPAL` só pode ser declarado depois disso — e
não foi.

## 2. Branch `brain/fase-2`

Criada **localmente** em `8217557` (o commit que `main` passará a apontar após o
fast-forward). Não foi publicada — mesmo bloqueio. Nada de desenvolvimento novo entrou
em `brain/fase-1`.

## Gate de entrada (medido em produção agora)

| Item | Produção |
|---|---|
| `brain` operacional | 10 objetos (9 tabelas + view), 37+ funções |
| Pontes | 3 existentes, **0 habilitadas** |
| Cron `brain-reconciliar` | ativo; 32 execuções, 0 falhas |
| `divergencias_erp()` | 0 |
| Migrations da Fase 1 | 10 registradas |
| pgvector | **não instalado** (`vector 0.8.2` disponível) |
| ERP | 1 orçamento, 2 pedidos, 112 produtos, 1 cliente |

## Auditoria do banco (o que a memória vai REFERENCIAR)

- **`public.products`** (112): `code`, `name`, `brand_id`, `category_id`, `manufacturer_code`
  (vazio em todos), `gtin` (vazio), `technical_data jsonb` (36 com `{ncm}`, 76 vazios),
  `source_type/source_brand/source_catalog/source_version/source_reference/source_imported_at`
  — **já existe rastreabilidade de origem**: `DJI / price_list / TABELA SUBDEALER / V16.2`
  (74) e `JR SOLUÇÕES / price_list / TABELA REV JR / JAN/26` (38).
- **`public.brands`** (10): AGRES, AGROTORK, ARAG, BALDAN, DJI, JR SOLUÇÕES, KUHN, MAGNOJET,
  TOYAMA, TRIMBLE — só DJI e JR têm produtos. **As seis marcas prioritárias já existem.**
- **`public.categories`** (9, sem hierarquia usada): Drones, Pulverização, Baterias e
  energia, Abastecimento e apoio de solo, Peças e acessórios, Acessórios de solo,
  Agricultura de Precisão, Implementos, Serviços.
- **`public.suppliers`** 0, **`public.supplier_products`** 0.
- **`public.product_costs`** (186): `condition_id` (AVISTA/FATURADO), `valid_from/valid_to`,
  `source_catalog`, `source_version`, `source_reference` (`PRODUTOS!DJI-001`) — **custo
  oficial já é versionado por tabela e vigência**. A memória documental não substitui isso.
- **Storage**: `public-assets` (público, 5 MB, imagens) e `private-docs` (privado, **10 MB**,
  pdf/png/jpeg, leitura/escrita só admin). Zero objetos. **Limite de 10 MB inviabiliza os
  catálogos** (Magnojet 178 MB) — bucket novo.
- **Extensões**: `pg_trgm 1.6` (índices trigram já em `products.name`, `products.code`,
  `customers.name`, `kits.name`), `unaccent 1.1`, `pg_cron 1.6.4`, `pgcrypto`, `uuid-ossp`,
  `pg_stat_statements`, `supabase_vault`. Disponíveis e não instaladas: `vector 0.8.2`,
  `pg_net 0.20.4`, `http 1.6`.
- **Papéis**: `user_role` = `admin | salesperson`; 1 perfil (admin). `anon` sem USAGE em
  `brain`. Data API não expõe `brain`.
- **Tamanho do banco**: 18 MB.

Conclusão: **nada a duplicar**. Marca, categoria, produto, custo e vigência de custo já
existem e viram chaves estrangeiras da memória.

## 3. Inventário inicial de fontes e documentos

Lidos no lugar (pastas conectadas `Desktop\Agro Tork` e `Downloads`; a listagem do Desktop
estourou o limite de 2 000 entradas por causa dos repositórios — os documentos fora deles
foram cobertos). Perfil medido com `pdfinfo`/`pdftotext`/`pdfimages` nos arquivos que
foram copiados para inspeção (só leitura; nada foi ingerido).

### Prioritários (as seis marcas)

| Documento | Marca | Tipo | Versão | Pág. | Tamanho | Texto | Tabelas | Imagens | Scan | Sensib. | Liga a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf` | Magnojet | catálogo | **V41** (InDesign 21.4) | 172 | 177,7 MB | sim, ~1.900 c/pág | **sim — 63 páginas com tabelas de vazão L/min × bar/psi/kPa × km/h → L/ha** | 14/pág | não | public | produtos futuros (pontas, filtros); hoje 0 produtos Magnojet no ERP |
| `CATÁLOGO V40 DIGITAL.pdf` | Magnojet | catálogo | **V40** (Illustrator 29.5) | 168 | 161,8 MB | sim | sim | 17/pág | não | public | **versão anterior da mesma obra** — caso de versionamento |
| `Quick-Catal-AGRI_2026_x-LATAM_InLav_2026.04-03_BR.pdf` | Agres (Tecomec) | catálogo resumido | 2026.04 | 68 | 50,5 MB | sim, ~760 c/pág (0,15% do arquivo) | fichas com especificações | 22/pág | não | public | já há `ANALISE-CATALOGO-AGRES-2026.md` (38 KB) com a estrutura página a página — reaproveitar |
| `Arag.xlsx` | Arag | lista de peças / cotação | 10/2024 | 1 aba | 10 KB | sim | **sim — código, tensão, corrente, sinal, faixa (0–20 bar, 2,5–50 l/min), preço** | — | — | internal (tem preço) | peças Arag não cadastradas |
| `baldan-folheto-racr.pdf` | Baldan | folheto | InDesign 14 | 2 | 0,26 MB | sim | espec. | 9/pág | não | public | implementos (categoria existe, 0 produtos) |
| `TABELA-SUBDEALER-V14.11.pdf` / `V15.1 - B.pdf` / `V16.2 B.pdf` | DJI | **tabela de preço** | V14.11 → V15.1 → **V16.2** | 2 / 4 / 1 | 0,9 / 3,0 / 0,1 MB | sim | sim (faturado / à vista / cliente final mínimo) | poucas | não | **commercial** (custo subdealer) | **74 produtos DJI têm `source_catalog='TABELA SUBDEALER' / 'V16.2'`** e 186 `product_costs` |
| `TABELA SÓ DRONE SET25 REVENDA.pdf` | DJI (revenda) | tabela de preço | set/25 | 1 | 0,5 MB | sim | sim | — | não | commercial | — |
| `T50 - Material Informativo.xlsx`, `T40 - Material Informativo (1).xlsx`, `T20P&T40 - Controle Remoto.xlsx`, `C12000 Material Information（CN&EN&JP）.xlsx`, `DJI Accessories Quotation Form.xlsx` | DJI | ficha técnica / lista de acessórios | — | — | 57 / 1,8 / 2,3 / 8,0 / 0,16 MB | planilha | sim | embutidas | — | internal | drones e acessórios DJI |
| `T100 U5 & Smartfarm Web Introdução a Novas Funções (PT-BR).pptx` (×2 iguais), `Treinamento Novos Modelos.docx`, `Apresentação Academy 2024/2025.pdf` | DJI | treinamento | — | — | 19 / 18 / 19 / 6 MB | sim | — | muitas | — | internal | — |
| `DJI AGRICULTURE - AGRAS T55 + Promoção …pdf`, `Banners T25 + T50 + M3M.pdf`, flyers de bateria | DJI | marketing | — | — | 124 / 19 MB | pouco | não | tudo | — | public | — |
| **Kuhn** | — | **nenhum documento encontrado** | | | | | | | | | marca existe, 0 produtos |

### Relevantes fora das seis marcas

| Documento | Marca | Tipo | Pág. | Tamanho | Texto | Observação |
|---|---|---|---|---|---|---|
| `CATÁLOGO-ALBUZ-BR.pdf` | Albuz (pontas) | catálogo | 24 | 11,3 MB | **não — 0 caracteres, 22 imagens/pág: precisa de OCR** | concorre/complementa Magnojet em pontas |
| `Catálogo Digital JR.pdf` | JR Soluções | catálogo | 7 | 6,1 MB | **não (imagem) — OCR** | 38 produtos JR no ERP |
| `Catálogo de Produtos JR Soluções.pdf` | JR | catálogo | 2 | 4,4 MB | sim | |
| `TABELA REV JAN261.pdf` | JR | tabela de preço | 1 | 0,2 MB | sim (Excel) | **é a fonte de `source_catalog='TABELA REV JR' / 'JAN/26'`** |
| `[JR] Portifólio Geral….pdf` | JR | catálogo | — | 8,1 MB | — | |
| `Manual PSI.pdf`, `Treinamento Geradores .pdf`, `D12000iE RATO - Treino de Reparo.pptx`, `boletim_informativo_TG17000CXE-XP.pdf` | Toyama/geradores | manual / treinamento | 12 / 56 | 4,6 / 8,0 MB | sim (PowerPoint→PDF) | |
| `Calibração MARCHIONI/FIGHTER AD-IA.pdf`, `CV-IA`, `MUG` | Marchioni | procedimento | 17 | 1,5 MB | sim, quase sem imagem | bom PDF "técnico simples" para o piloto |
| `CATALOGO PRODUTOS - PROJETA AGRÍCOLA 2024.pdf` + `TABELA DE PREÇOS PROJETA - 2024.pdf` | Projeta | catálogo + preço | — | 14,4 / 1,3 MB | — | par obra/preço |
| `SOLCERA-AGRO-WEB.pdf` | Solcera | catálogo | — | 192 MB | — | |
| `TABELA DE PREÇO  NOVA 2026.xlsx` | AgroTork interno | planilha de precificação (margem, custo, lucro) | 10 abas | 70 KB | fórmulas | **admin** — contém custo e margem |
| `AGROTORK_IMPORTACAO_PRODUTOS_V4_DEFINITIVA.xlsx` e família | AgroTork interno | carga do catálogo | — | 0,14 MB | | admin; origem dos 112 produtos |
| `08 - Planilhas e Relatorios/*` (ficha de aplicação, troca de peças, garantia) | AgroTork interno | procedimento | — | — | | internal |

### Fora de escopo (encontrados, **não entram**)

`02 - Financeiro` (boletos), `05 - Documentos e Contratos` (contratos sociais, CNPJ,
credores, contrato de locação), `07 - Pessoal`, `11 - Digitalizacoes (Scans)` (WhatsApp e
CamScanner), `13 - Certificados Digitais`, `Contratos/` no Desktop. Todos sensíveis
(admin ou pessoal) e sem valor para o RAG técnico-comercial. Ficam **fora** do bucket.

### O que o inventário ensina

1. Os catálogos que importam são **grandes (50–180 MB) e cheios de imagem**; o texto é
   0,15–1% do arquivo. Storage e limite de tamanho decidem a arquitetura antes do RAG.
2. **Tabelas são o coração**: o Magnojet tem 63 páginas de tabela de vazão com 13 colunas
   de velocidade. Chunk de texto corrido destruiria isso.
3. **Versionamento é real e já apareceu três vezes**: Magnojet V40→V41, DJI V14.11→V15.1→V16.2
   (preço do T100 à vista: 159.000 → 161.900), JR JAN/26. O ERP já grava
   `source_version` — a memória precisa casar com isso, não competir.
4. Dois documentos relevantes **exigem OCR** (Albuz, Catálogo Digital JR): OCR entra como
   capacidade do pipeline, não como exceção.
5. **Não há documento Kuhn** e não há manual Arag/Magnojet além de catálogo. Lacuna a
   perguntar ao Wilson.

## 4. Arquitetura proposta

```
arquivo (Storage privado, nome imutável com sha256)
  → brain.document_versions (checksum, páginas, status, vigência)
  → ingestão assíncrona (pg_cron + fila em brain.knowledge_ingestions; extração FORA do banco)
  → brain.document_pages (texto por página, checksum da página)
  → brain.document_chunks (texto + table_data jsonb + codes[] + tsvector + página)
  → brain.chunk_embeddings (por modelo, particionada)
  → brain.search_knowledge(): filtro de acesso e vigência ANTES → FTS + trigram + vetor → RRF
  → resposta com proveniência (chunk → página → versão → documento → fonte → arquivo → sha256)
```

Princípios que saem direto da Fase 1 e do inventário:

- **Zero processamento nas transações do ERP.** Nenhuma ponte, nenhum trigger em `public`.
  Ingestão roda por job (pg_cron chamando um worker externo — Edge Function ou n8n na
  Fase 3), nunca dentro de orçamento/pedido.
- **Extração fora do banco.** PDF de 180 MB não se processa em plpgsql. O banco guarda
  estado, texto, tabelas e vetores; o worker (Python: `pdfplumber`/`pymupdf`, `tesseract`
  quando `precisa_ocr`) faz o trabalho pesado e grava por página, com retomada.
- **Referenciar, não duplicar**: `brand_id`, `product_id`, `category_id`, `condition_id`
  apontam para `public`. Preço em documento vira `chunk` com `kind='price_table'` e
  **nunca** escreve em `public.product_costs` ou `products.sale_price`.
- **Modelo de embedding é dado, não esquema**: `embedding_models` + partições por modelo.
- **Acesso é filtro, não pós-processamento**: RLS nas tabelas e o mesmo predicado dentro
  da função de busca, aplicado ao conjunto candidato antes de qualquer ranking.

## 5. Modelo de dados (proposta; nomes ajustados onde o desenho pediu)

```sql
create type brain.access_level as enum ('public', 'internal', 'commercial', 'admin');
create type brain.document_type as enum ('catalog','manual','price_list','datasheet','procedure',
  'technical_bulletin','internal_note','training','regulatory','other');
create type brain.version_status as enum ('draft','active','superseded','withdrawn');
create type brain.ingestion_status as enum ('pending','extracting','chunking','embedding','completed','failed','partial');
create type brain.chunk_kind as enum ('text','table','price_table','spec','heading','caption');
create type brain.link_origin as enum ('manual','rule','ai','import');

-- Origem do conhecimento. brand_id/supplier_id são a ligação com o ERP; `key` é estável.
brain.knowledge_sources (
  key text pk check (key ~ '^[a-z][a-z0-9_]*$'),   -- 'magnojet', 'dji', 'agres', 'agrotork'
  name text, kind text check (kind in ('manufacturer','supplier','distributor','internal','regulator','other')),
  brand_id uuid references public.brands on delete set null,
  supplier_id uuid references public.suppliers on delete set null,
  website text, metadata jsonb, created_at)

-- A OBRA, não o arquivo. "Catálogo Magnojet" é um documento; V40 e V41 são versões.
brain.documents (
  id uuid pk, source_key text references brain.knowledge_sources,
  title text, document_type brain.document_type, access_level brain.access_level,
  language text default 'pt-BR', brand_id uuid references public.brands,
  category_id uuid references public.categories,
  slug text unique,                       -- 'magnojet-catalogo'
  metadata jsonb, created_by, created_at, updated_at)

-- Cada edição. Nova versão NÃO apaga a antiga: supersedes/superseded_by encadeiam.
brain.document_versions (
  id uuid pk, document_id uuid references brain.documents,
  version_label text,                      -- 'V41', 'V16.2', '2026.04'
  status brain.version_status, valid_from date, valid_to date,
  supersedes_id uuid references brain.document_versions,   -- a anterior
  published_at date,
  storage_bucket text, storage_path text,  -- imutável: <source>/<document>/<version>/<sha256>.<ext>
  file_sha256 text not null, file_size bigint, mime_type text, page_count int,
  needs_ocr boolean, text_ratio numeric,   -- medido na ingestão
  imported_at timestamptz, imported_by uuid, metadata jsonb,
  unique (document_id, file_sha256),       -- mesmo arquivo não vira segunda versão
  unique (document_id, version_label))

-- Uma linha por tentativa de ingestão; idempotente por (version_id, pipeline_version).
brain.knowledge_ingestions (
  id uuid pk, version_id uuid references brain.document_versions,
  status brain.ingestion_status, pipeline_version text,     -- 'v1-pdfplumber-ocr'
  executor text, started_at, finished_at, duration_ms int,
  pages_done int, pages_total int, chunks_created int, tables_created int,
  embedding_model_id uuid, errors jsonb, warnings jsonb, metadata jsonb,
  unique (version_id, pipeline_version, status) where status = 'completed')

-- Texto por página: proveniência de página e reprocessamento sem reler o PDF.
brain.document_pages (
  version_id uuid, page_no int, text text, text_sha256 text, ocr boolean,
  layout jsonb,                            -- caixas de tabela/figura detectadas
  primary key (version_id, page_no))

-- O que se recupera. `content` é o texto pesquisável; `table_data` guarda a estrutura.
brain.document_chunks (
  id bigint identity pk, version_id uuid references brain.document_versions on delete cascade,
  ordinal int, kind brain.chunk_kind,
  page_from int, page_to int,
  heading_path text[],                     -- {'PONTAS','MAGNO ULTRA GROSSA','CONE VAZIO'}
  content text not null,                   -- texto (ou renderização linear da tabela)
  table_data jsonb,                        -- {headers, units, rows, notes, page}
  codes text[],                            -- códigos extraídos: {'MJ981CAP','MUG-CV 02'}
  token_count int, content_sha256 text,
  fts tsvector generated always as (to_tsvector('portuguese', public.immutable_unaccent(content))) stored,
  metadata jsonb,
  unique (version_id, ordinal), unique (version_id, content_sha256))

-- Vínculo com o catálogo real. Nunca altera public.products.
brain.chunk_products (
  chunk_id bigint references brain.document_chunks on delete cascade,
  product_id uuid references public.products on delete cascade,
  confidence numeric(4,3) check (confidence between 0 and 1),
  linked_by brain.link_origin, linked_by_user uuid, evidence text, created_at,
  primary key (chunk_id, product_id))

brain.embedding_models (
  id uuid pk, provider text, model text, dimensions int, version text,
  is_current boolean, cost_per_mtok numeric, metadata jsonb, created_at,
  unique (provider, model, version))

-- Particionada por modelo: cada partição tem vector(n) do SEU n e índice HNSW próprio.
brain.chunk_embeddings (
  chunk_id bigint references brain.document_chunks on delete cascade,
  model_id uuid references brain.embedding_models,
  embedding vector not null,               -- typmod na partição
  created_at, primary key (chunk_id, model_id)) partition by list (model_id);
```

Índices: `document_chunks` — GIN em `fts`, GIN `gin_trgm_ops` em `content`, GIN em
`codes`, btree `(version_id, page_from)`; `chunk_embeddings_<modelo>` — HNSW
`vector_cosine_ops` (`m=16, ef_construction=64`); `document_versions` —
`(document_id, status)` e índice único parcial "uma `active` por documento".

Ajustes em relação ao pedido: **`document_pages` entra** (proveniência de página e
reprocessamento barato); `chunk_embeddings` **particionada por modelo** (o HNSW exige
dimensão fixa; partição resolve sem uma tabela por modelo à mão); `codes text[]`
extraído na ingestão (busca exata/trigram de código sem depender do vetor).

## 6. Storage

- Bucket novo **`brain-knowledge`**, privado, `file_size_limit` ≥ 250 MB (o `private-docs`
  tem 10 MB), MIME: pdf, xlsx, docx, pptx, png, jpeg.
- Caminho **imutável**: `<source_key>/<document_slug>/<version_label>/<sha256>.<ext>`. Um
  arquivo diferente nunca ocupa o mesmo caminho — substituição silenciosa é impossível
  por construção; a policy de UPDATE em `storage.objects` para esse bucket é negada.
- Escrita: só `service_role` (worker) e admin. Leitura: **nunca por URL pública**; a
  função `brain.signed_url_for_version(version_id)` (security definer) confere o nível de
  acesso do chamador e devolve URL assinada de curta duração (Storage `createSignedUrl`,
  via Edge Function — o banco não assina).
- `file_sha256` conferido no upload e reconferido na ingestão; divergência = `failed`.
- **Risco de plano**: o limite de tamanho de objeto depende do plano Supabase (Free 50 MB,
  Pro até 50 GB). Confirmar o plano antes do primeiro upload de 178 MB.

## 7. Versionamento

- `documents` = obra; `document_versions` = edição. Nova versão: `status='active'`,
  `supersedes_id` aponta para a anterior, que passa a `superseded` com `valid_to`.
- Mesmo arquivo (mesmo `sha256`) do mesmo documento → **não cria versão**; a ingestão
  retorna a existente (RAG2, RAG13).
- Versão antiga continua pesquisável **só quando pedida** (`include_superseded=true` ou
  filtro `version_label`) — RAG15. Busca padrão: `status='active'` e vigente na data.
- `withdrawn`: sai de toda busca, arquivo fica.

## 8. Chunking

Página é a unidade de proveniência; o chunk nunca cruza uma tabela.

1. **Extração por página** (`pdfplumber`; `pymupdf` para blocos e imagens): texto com
   coordenadas, blocos, tabelas detectadas (linhas/colunas).
2. **OCR** quando `text_ratio < 0,02` ou `chars/pág < 80` (Albuz, Catálogo Digital JR):
   `tesseract` por-BR + eng, guardando `ocr=true` na página e na proveniência.
3. **Hierarquia**: seção/família/título viram `heading_path` por heurística de fonte e caixa
   (o Agres tem "duas linhas repetidas em todas as páginas", já mapeado na análise
   existente; o Magnojet tem cabeçalho de família + série da ponta).
4. **Texto corrido**: 300–700 tokens, quebra em parágrafo/lista, sobreposição de 1 frase.
   Prefixo de contexto no `content`: `"[Catálogo Magnojet V41 · p.20 · MAGNO ULTRA GROSSA ·
   CONE VAZIO] …"` — o embedding vê onde está.
5. **Códigos**: regex por padrão de fabricante (`MJ\d{3}[A-Z]*`, `MUG-CV \d+`, `DB\d{3,4}`,
   `4626215`, `863T026S`…) → `codes[]`; também o número da página e a versão.
6. **Tabelas**: chunk próprio, `kind='table'` (ver §9). Tabela grande (63 linhas × 17
   colunas) é dividida **por grupo de linhas que compartilha a chave** (uma ponta = um
   chunk), mantendo o cabeçalho completo em cada parte.
7. **Deduplicação** por `content_sha256` dentro da versão; entre versões, chunks idênticos
   são detectados para relatório "o que mudou de V40 para V41" (não para pular embedding).

## 9. Tratamento de tabelas

Exemplo real — Magnojet V41, p. 20, ponta MJ981CAP (MUG-CV 02):

```json
{
  "page": 20, "family": "MAGNO ULTRA GROSSA", "geometry": "CONE VAZIO",
  "headers": ["codigo","serie","gotas","bar","psi","kPa","L_min","L_ha@4","L_ha@5","L_ha@6","L_ha@7","L_ha@8","L_ha@9","L_ha@10","L_ha@12","L_ha@14","L_ha@16","L_ha@18","L_ha@20","L_ha@25"],
  "units": {"bar":"bar","psi":"psi","kPa":"kPa","L_min":"L/min","L_ha@*":"L/ha (espaçamento 50 cm, km/h)"},
  "rows": [
    ["MJ981CAP","MUG-CV 02","UG",2.07,30,207,0.66,199,159,133,114,100,89,80,66,57,50,44,40,32],
    ["MJ981CAP","MUG-CV 02","UG",2.76,40,276,0.77,230,184,153,131,115,102,92,77,66,58,51,46,37]
  ],
  "notes": ["MALHA 50", "APLICAÇÕES DE HERBICIDAS SISTÊMICOS EM PRÉ E PÓS-EMERGÊNCIA"]
}
```

- `content` recebe a **renderização linear** da mesma tabela (uma linha por registro, com
  unidades) para FTS, trigram e embedding: `MJ981CAP MUG-CV 02 gotas UG 2,76 bar 40 psi
  0,77 L/min …`.
- Números ficam **numéricos** no JSONB (vírgula decimal convertida), com a unidade no
  cabeçalho — é o que permite, no futuro, `where (row->>'L_min')::numeric between 0.75 and
  0.85` sem passar pelo LLM.
- Página, família e observações ficam na tabela e na proveniência.
- Validação na ingestão: nº de colunas constante por tabela, células numéricas parseáveis;
  falha vira `warning` e a tabela cai para `kind='text'` com marcação `table_parse_failed`.

## 10. Embeddings

Não decidido; a arquitetura suporta troca. Candidatos, com custo por 1 M tokens de
entrada (valores públicos de setembro/2026 a confirmar no dia da contratação):

| Provider / modelo | Dim. | Custo | Observação |
|---|---|---|---|
| OpenAI `text-embedding-3-small` | 1536 (reduzível) | ~US$ 0,02 | barato, bom em PT-BR |
| OpenAI `text-embedding-3-large` | 3072 | ~US$ 0,13 | melhor recall; 2× o índice |
| Voyage `voyage-3.5` / `-lite` | 1024 | ~US$ 0,06 / 0,02 | forte em documentos técnicos |
| Local (`bge-m3`, `multilingual-e5-large`) | 1024 | infra própria | zero envio de documento para fora — atende o requisito de confidencialidade para `admin` |

Recomendação para o piloto: **um modelo barato hospedado** para `public/internal` e a
**decisão explícita do Wilson** sobre `commercial/admin` (enviar tabela de custo a um
provedor externo exige autorização; alternativa é modelo local para esses níveis, ou não
vetorizar esses documentos e servi-los só por FTS/trigram — que para tabela de preço
funciona bem). `chunk_embeddings` particionada permite os dois modelos coexistirem e a
comparação A/B antes de desativar um.

## 11. Retrieval híbrido

`brain.search_knowledge(p_query text, p_embedding vector default null, p_filters jsonb
default '{}', p_k int default 10, p_include_superseded boolean default false)`
— `security invoker` (RLS vale), `set search_path = ''`.

1. **Candidatos** (CTE): `document_versions` com `status='active'` (ou superseded se
   pedido) e vigência na data; `documents.access_level` ≤ nível do chamador; filtros
   `brand_id`, `source_key`, `document_type`, `product_id` (via `chunk_products`),
   `category_id`, `version_label`, `kind`.
2. Sobre os candidatos, três rankings independentes, cada um `limit 50`:
   - **FTS**: `fts @@ websearch_to_tsquery('portuguese', unaccent(q))`, `ts_rank_cd`;
   - **Trigram/exato**: `codes @> {q}` (exato, peso máximo) e `similarity(content, q)`
     com `%` — é o que acha `MJ981CAP` digitado como `mj 981 cap`;
   - **Vetor**: `embedding <=> p_embedding` na partição do modelo corrente (HNSW,
     `ef_search=80`), só se `p_embedding` veio.
3. **RRF** com `k=60`: `score = Σ 1/(60 + rank_i)`; empate favorece `codes` exato.
4. Devolve `chunk_id, score, kind, content, table_data, page_from, page_to, heading_path,
   version_id, version_label, document_id, title, source_key, storage_path, file_sha256`.

Por que RRF e não pesos: os três scores têm escalas incomparáveis; RRF é estável sem
calibração e fácil de auditar. Pesos entram só depois do golden dataset medir.

## 12. Segurança

| Nível | Quem lê | Exemplos |
|---|---|---|
| `public` | qualquer usuário ativo (admin, salesperson) | catálogos de fabricante, folhetos |
| `internal` | qualquer usuário ativo | manuais, treinamentos, fichas, procedimentos |
| `commercial` | usuário ativo — **a definir**: hoje `salesperson` vê preço de venda mas não custo; tabela subdealer é custo → provavelmente **admin** | tabelas de preço de revenda |
| `admin` | `is_admin()` | planilhas de margem/custo, contratos, importação |

- RLS em `documents`, `document_versions`, `document_pages`, `document_chunks`,
  `chunk_embeddings`, `chunk_products`: `using (brain.can_read_level(access_level))`,
  reaproveitando `public.is_admin()` / `public.is_active_user()` e `brain.assert_caller()`.
  `anon`: nada (já é assim no schema).
- **A busca vetorial nunca vê chunk que o chamador não pode ler**: a função é `security
  invoker`, a CTE de candidatos aplica o nível, e o índice HNSW só é consultado sobre esse
  conjunto (`WHERE` antes do `ORDER BY <=>` — com pgvector 0.8 o filtro é aplicado com
  *iterative index scan*, sem perder recall).
- Storage: leitura só por URL assinada emitida após a mesma checagem; bucket sem
  listagem pública.
- Documento recuperado é **dado**: o prompt do respondedor (Fase 3) coloca chunks entre
  delimitadores e instrui a ignorar instruções embutidas; nenhuma ferramenta é acionada a
  partir de conteúdo de documento; nenhum chunk altera permissão.
- Envio a provedor externo: só níveis `public/internal` sem autorização adicional; `commercial/admin` exigem decisão do Wilson (§10).
- Testes previstos: vazamento entre níveis (RAG9), documento `withdrawn` some da busca,
  versão `superseded` só aparece quando pedida, `anon` não executa a função.

## 13. Proveniência

Cada resultado carrega a cadeia inteira, e a resposta cita assim:

> Fonte: **Catálogo Magnojet V41**, p. 20 (tabela "MAGNO ULTRA GROSSA · CONE VAZIO"),
> arquivo `MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf`, sha256 `78af9b13b5…`.

`chunk_id → document_chunks.page_from → document_versions.version_label/file_sha256/storage_path
→ documents.title → knowledge_sources.key → URL assinada do original`. Tabelas citam
também a linha (`row_index`). Resposta sem chunk de suporte acima de um limiar de score
(a calibrar no golden dataset) devolve: **"Não encontrei documentação suficiente para
afirmar isso."** — e distingue *dado do documento* / *inferência* / *recomendação*.

## 14. Golden dataset (v0)

`docs/brain/golden-dataset-v0.json` — 14 perguntas com resposta esperada, fonte, página
quando conhecida e comportamento sem evidência. Resumo:

| # | Tipo | Pergunta | Esperado |
|---|---|---|---|
| 1 | vazão | Qual ponta Magnojet cone vazio ultra grossa entrega perto de 0,8 L/min? | MJ981CAP (MUG-CV 02) a 2,76 bar / 40 psi = 0,77 L/min; MJ982CAP (025) a 2,07 bar = 0,83 L/min — V41 p. 20 |
| 2 | vazão+velocidade | Com a MJ981CAP a 40 psi, quantos L/ha a 12 km/h? | 77 L/ha (espaçamento 50 cm) — V41 p. 20 |
| 3 | código | O que é o código 4626215 da Arag? | Fluxômetro Wolf, 12 V, 2,5–50 l/min — `Arag.xlsx` (internal) |
| 4 | compatibilidade | Qual bateria avulsa serve para T55 e T70P? | DB1580 — TABELA SUBDEALER V16.2 |
| 5 | catálogo | Em qual catálogo aparece a ponta MJ983CAP? | Magnojet V41 (e V40); página 20 na V41 |
| 6 | versão | Qual é a versão mais recente da tabela subdealer DJI? | V16.2 (supersede V15.1 e V14.11) |
| 7 | versão | O que mudou no preço à vista do T100 + 3 bat + C12000 entre V14.11 e V16.2? | 159.000 → 161.900 (faturado 165.500 nos dois) — **commercial** |
| 8 | preço | Qual o preço subdealer à vista do T25P + 3 bat + C8000 na tabela vigente? | R$ 61.789,00 — V16.2; **não altera `products.sale_price`** |
| 9 | comparação | Compare T55 com DB1050 e com DB1580 (kit carregador) | 96.483 vs 113.789 à vista; cliente final mínimo 130.000 vs 156.000 — V16.2 |
| 10 | espec. | Qual a faixa do sensor de pressão Arag 466113200? | 0–20 bar, 4–20 mA — `Arag.xlsx` |
| 11 | procedimento | Como calibrar o Fighter AD-IA? | passos do PDF Marchioni (17 p.) — resposta deve citar página |
| 12 | sem resposta | Qual a vazão da ponta Magnojet MJ999CAP? | não existe: "não encontrei documentação suficiente" |
| 13 | sem resposta | Qual o manual da semeadora Kuhn? | nenhum documento Kuhn: mesma resposta |
| 14 | acesso | (como salesperson) Qual a margem da T100 na planilha 2026? | planilha é `admin`: **não aparece** nem como "existe mas não posso mostrar" |

Cada item registra `documentos_validos`, `paginas_esperadas` e `sem_evidencia` (o que o
sistema deve dizer). A resposta esperada dos itens de preço é a **do documento**, e o
dataset marca explicitamente que ela não é o preço oficial do ERP.

## 15. Estimativa de volume

| Corpus | Docs | Páginas | Chunks (est.) | Tokens p/ embedding | Arquivos |
|---|---|---|---|---|---|
| Piloto (Magnojet V41+V40, Agres, DJI V16.2/V15.1/V14.11, Arag.xlsx, Baldan, Marchioni AD-IA, Albuz c/ OCR) | 10 | ~640 | ~2.500 (≈ 900 tabelas) | ~1,3 M | ~410 MB |
| Corpus técnico-comercial completo do inventário | ~45 | ~1.800 | ~8.000 | ~4 M | ~1,2 GB |
| Crescimento anual (novas versões, novos fabricantes) | +15/ano | +600 | +3.000 | +1,5 M | +400 MB |

Banco: ~8 000 chunks × (texto ~2 KB + JSONB ~2 KB + vetor 1536×2 B halfvec ≈ 3 KB) ≈
60 MB + índices ≈ 150 MB. Hoje o banco tem 18 MB.

## 16. Estimativa de custo (premissas explícitas)

- Embedding piloto: 1,3 M tokens × US$ 0,02/M = **US$ 0,03**; corpus completo US$ 0,08;
  re-embedding total ao trocar de modelo: < US$ 1. Com `-large`: ×6,5.
- Storage: 1,2 GB → dentro do Pro (100 GB); Free (1 GB) **não cabe** já no piloto.
- Egress de URL assinada: proporcional ao uso; catálogo de 178 MB baixado 10×/mês = 1,8 GB.
- Worker de ingestão: Edge Function tem limite de tempo/memória incompatível com 178 MB +
  OCR; **worker Python** (container barato ou n8n com nó de código) — custo ≈ US$ 5–15/mês
  ou zero se rodar na máquina da AgroTork sob demanda.
- LLM de resposta (Fase 3): fora desta estimativa.
- OCR: `tesseract` local, zero.

Nenhum serviço será contratado sem orçamento aprovado.

## 17. Riscos

1. **Limite de tamanho de arquivo no Storage** (plano) — verificar antes do piloto.
2. **Qualidade da extração de tabelas** em PDF de InDesign com colunas rotacionadas
   (o cabeçalho "LITROS POR HECTARE" do Magnojet está em ângulo): validar em 5 páginas
   antes de generalizar; fallback humano de correção do JSONB.
3. **OCR em catálogo de imagem** (Albuz, JR): acurácia de códigos; marcar `ocr=true` e
   confiança baixa na proveniência.
4. **Confidencialidade × provedor externo**: tabela subdealer é custo; decisão pendente.
5. **Dois vocabulários de versão**: `products.source_version='V16.2'` e
   `document_versions.version_label` precisam do mesmo texto — regra de normalização.
6. **Vazamento por junção**: `chunk_products` liga chunk `admin` a produto `public`;
   a busca por produto tem de aplicar o nível do chunk, não do produto (teste RAG9b).
7. **Alucinação por tabela mal lida**: número certo na linha errada é pior que "não sei";
   por isso a validação de tabela é bloqueante e o golden dataset tem 2 itens quantitativos.
8. **Deriva de PDF**: fabricante republica com o mesmo nome e outro conteúdo — o caminho
   com sha256 e `unique(document_id, file_sha256)` tornam isso visível.
9. **Push bloqueado nesta sessão**: publicação da branch depende do Wilson.

## 18. Ordem de implementação (próximos lotes, cada um com migration + teste + GO/NO-GO)

1. **Lote A — esquema sem vetor**: enums, `knowledge_sources`, `documents`,
   `document_versions`, `knowledge_ingestions`, `document_pages`, `document_chunks`,
   `chunk_products`, RLS, bucket `brain-knowledge` e policies de Storage, FTS + trigram,
   `search_knowledge()` **sem** vetor. Testes RAG1, RAG2, RAG3, RAG4, RAG7, RAG8, RAG9,
   RAG10, RAG11, RAG13, RAG14, RAG15 já passam sem embedding. **pgvector ainda não.**
2. **Lote B — worker de ingestão** (fora do banco): extração, OCR, tabelas → JSONB,
   chunking, upload com sha256; piloto com Marchioni AD-IA (simples), DJI V16.2 (tabela de
   preço, 1 página), Agres (fichas), Magnojet V41 p. 18–30 (tabelas de vazão) e V40 (versão
   anterior), Albuz (OCR). Golden dataset rodando sobre FTS+trigram → baseline.
3. **Lote C — vetor**: `create extension vector with schema extensions` (0.8.2),
   `embedding_models`, `chunk_embeddings` particionada, HNSW, RRF completo, RAG5, RAG6,
   RAG12. Modelo de embedding escolhido com a decisão de confidencialidade.
4. **Lote D — avaliação**: métricas (recall@5 por pergunta, citação correta, latência p95,
   custo por consulta), comparação de dois modelos, relatório GO/NO-GO da Fase 2.

Cada lote respeita as regras da Fase 1: migration com teste, ensaio em PostgreSQL 17.6
local, CI verde no SHA, `GO — FASE 2 SEGURA PARA PRODUÇÃO` ou `NO-GO` antes de qualquer
`PODE APLICAR FASE 2`.

## Perguntas que dependem do Wilson

1. Plano Supabase atual (limite de objeto no Storage)?
2. Tabela subdealer DJI (custo): nível `commercial` visível ao vendedor ou `admin`?
3. Pode-se enviar documentos `public/internal` a um provedor externo de embedding? E
   `commercial`?
4. Existem documentos Kuhn, manuais Arag/Magnojet, ou catálogo técnico DJI (não só tabela)
   em outro lugar (Drive, e-mail)?
5. Quem é o responsável por atualizar cada fonte (quem recebe a tabela nova da DJI, o
   catálogo novo da Magnojet)?
