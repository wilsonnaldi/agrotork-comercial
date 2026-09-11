# AGROTORK BRAIN — Fase 2, Lote A: fundação da memória corporativa (sem vetor)

Branch `brain/fase-2`. Projeto de origem: `docs/brain/fase-2-etapa-0.md`. Este documento
descreve **o que foi implementado** — para outro engenheiro ler o esquema, os testes e o
caminho de volta sem precisar da conversa que os gerou.

**Estado:** construído e testado localmente em PostgreSQL 16.13, 17.6 e 18.6.
**Não aplicado em produção.** pgvector continua desabilitado.

## 1. O que o Lote A é

A camada relacional da memória: de onde vem o conhecimento, qual obra, qual edição, qual
arquivo (por sha256), qual processo o extraiu, qual página, qual trecho, e com qual
produto do ERP o trecho se relaciona. Mais a busca textual (código exato, trigram, FTS)
e a proveniência para citação. Sem embedding, sem worker, sem bucket criado.

```
brain.knowledge_sources ──< brain.documents ──< brain.document_versions ──< brain.knowledge_ingestions
                                                          │                          │
                                                          └──< brain.document_pages ─┘ (ingestion_id)
                                                                     │
                                                                     └──< brain.document_chunks ──< brain.chunk_products >── public.products
```

Migrations: `20260912010000_brain_memoria_esquema.sql` e `20260912020000_brain_memoria_busca.sql`.
Nenhuma migration da Fase 1 (`20260911130000`…`20260911220000`) ou do ERP foi alterada.

## 2. Tabelas

| Tabela | Papel | Chaves e regras que importam |
|---|---|---|
| `knowledge_sources` | origem institucional (Magnojet, DJI, AgroTork interno) | `key` estável; `brand_id`/`supplier_id` → `public`; `owner_role`/`reviewer_role` são **setores** (enum `knowledge_role`); `default_access_level`; `external_processing` |
| `documents` | a obra | `slug` único; `access_level` (a fonte de verdade do nível); `document_type`; governança: `approved_by/approved_at` (par), `review_due_at`; `external_processing_override` **só com aprovador** (`chk_document_override_approved`) |
| `document_versions` | a edição | `version_label` único por documento; `status` draft/active/superseded/withdrawn; **uma `active` por documento** (índice único parcial); `supersedes_id`/`superseded_by_id` encadeiam; `file_sha256` + `storage_path` terminando no sha (`chk_version_path_has_sha`); `unique (document_id, file_sha256)`; arquivo **imutável** após gravado (gatilho, `restrict_violation`) |
| `knowledge_ingestions` | cada tentativa de processamento | `method`, `parser`, `pipeline_version`, `needs_ocr`, tempos, contadores, `error`/`warnings`/`metrics`; `failed` exige `error` |
| `document_pages` | texto por página | PK `(version_id, page_no)`; `text_sha256` calculado por gatilho (`sha256()` do core); `extraction` text_layer/ocr/spreadsheet/manual/none; `ingestion_id` da mesma versão (gatilho confere) |
| `document_chunks` | unidade recuperável | `(version_id, page_from)` é FK para a página; `kind`; `content` + `content_norm` (gatilho: lower + unaccent) + `fts` (coluna gerada, `to_tsvector('portuguese', content_norm)`); `table_data` obrigatório e só para `table`/`price_table` (`chk_chunk_table_shape`: `headers[]` e `rows[]`); `codes[]` normalizados (`MJ981CAP`); `content_sha256` (gatilho); único por `(version_id, ordinal)` e `(version_id, content_sha256)` |
| `chunk_products` | trecho → produto do ERP | PK `(chunk_id, product_id)`; `confidence`, `linked_by` manual/rule/ai/import, `evidence`. **Aponta; nunca escreve preço** |

Tipos: `access_level` (`public < internal < commercial < admin` — a ordem do enum é a
ordem de sensibilidade), `document_type`, `version_status`, `ingestion_status`, `chunk_kind`,
`link_origin`, `external_processing` (`allowed < approved_provider_only < forbidden`),
`knowledge_role`, e o composto `knowledge_hit` (retorno da busca).

## 3. Nível de acesso: uma coluna em toda a cadeia

`access_level` mora em `documents` e é **copiado por gatilho** para `document_versions`,
`knowledge_ingestions`, `document_pages`, `document_chunks` e `chunk_products`
(`stamp_*`). Reclassificar o documento desce a cadeia inteira (`cascade_*_access`).
Consequências:

- toda policy de leitura é `using (brain.can_read_level(access_level))` — comparação de
  coluna, sem junção, sem função `security definer` nova;
- o conjunto candidato da busca já nasce filtrado (§6), antes de qualquer ranking;
- não existe como um chunk ficar mais aberto que o documento.

Quem é o chamador, em **um** lugar — `brain.caller_access_level()`:

| Chamador | Nível |
|---|---|
| administrador (`public.is_admin()`), ou o próprio banco (`postgres`, `service_role`, cron — via `brain.is_privileged()` da Fase 1) | `admin` |
| usuário ativo (vendedor) | `internal` |
| `anon`, inativo, sem sessão | `NULL` → não lê nada |

**Decisão embutida:** `commercial` é hoje só do administrador (tabela subdealer é custo).
Se o vendedor um dia puder ver preço de revenda, muda-se essa função e nada mais.

## 4. RLS

RLS em todas as sete tabelas. Por tabela: `*_select` (leitura por nível — em
`knowledge_sources`, qualquer usuário ativo), `*_admin_insert` (`with check is_admin`),
`*_admin_update` (`using` e `with check` `is_admin`), `*_admin_delete`. Uma policy
permissiva por (papel, ação) — guarda na própria migration, e o advisor do Supabase
mede isso. `anon` sem USAGE no schema (herdado da Fase 1) e sem grant em tabela.
`service_role` e `postgres` passam por cima do RLS por natureza: é assim que o worker
de ingestão (Lote B) vai escrever.

Nenhuma view. Nenhuma função `security definer` nova: `search_knowledge`,
`chunk_provenance`, `current_version` e `external_processing_for` são `security
invoker` com `search_path = ''` — se o chamador não pode ler, o resultado é vazio ou
`NULL`, nunca "existe mas não posso mostrar".

## 5. Versionamento e vigência

- Inserir/atualizar uma versão para `active` supersede a vigente anterior: ela vira
  `superseded`, ganha `superseded_by_id` e `valid_to = greatest(nova.valid_from - 1,
  sua valid_from)`; a nova recebe `supersedes_id`. Reativar uma edição reabre a
  vigência (`valid_to = null`) a menos que o mesmo UPDATE fixe outra.
- `withdrawn` nunca aparece em busca, nem pedindo pelo id.
- A busca padrão devolve só `active` e vigente na data. `p_include_superseded = true`
  traz as `superseded`; o filtro `version_label`/`version_id` escolhe uma edição
  específica.
- Histórico nunca é apagado por uma versão nova. Exemplos reais que o modelo cobre:
  Magnojet V40 → V41; DJI Subdealer V14.11 → V15.1 → V16.2 (preço do T100 à vista
  mudou entre elas).

## 6. Busca — `brain.search_knowledge(p_query, p_filters, p_limit, p_include_superseded)`

```sql
select * from brain.search_knowledge('mj 981 cap');
select * from brain.search_knowledge('núcleo de cerâmica', '{"source_key":"magnojet"}');
select * from brain.search_knowledge('T100', '{"product_id":"<uuid>"}', 10, true);
```

1. **Candidatos** (CTE): `can_read_level(chunk.access_level)` + vigência + filtros
   (`source_key`, `document_id`, `document_type`, `brand_id`, `category_id`,
   `version_label`, `version_id`, `kind`, `product_id`). Tudo isso **antes** dos rankings.
2. **A1 — código exato**: cada palavra da pergunta e a pergunta inteira viram códigos
   normalizados (`mj 981 cap` → `MJ981CAP`); `codes && v_codes`. Ordena por número de
   códigos batidos.
3. **A2 — trigram**: `word_similarity(pergunta, content_norm)` e sobre os códigos,
   corte 0,35 (acha `MJ981CAB` quando o certo é `MJ981CAP`). Índice GIN `gin_trgm_ops`.
4. **B — FTS**: `websearch_to_tsquery('portuguese', pergunta)` sobre `fts`, `ts_rank_cd`.
   Índice GIN.
5. **RRF, k = 60**: `score = Σ 1/(60+rank)`; código exato soma um braço a mais. O
   braço vetorial do Lote C entra como quarto termo na mesma soma.

Retorna `knowledge_hit`: chunk, os três ranks, `content`, `table_data`, páginas,
`heading_path`, `codes`, versão (id, label, status), documento (id, título, tipo),
fonte, nível, `storage_path`, `file_sha256`.

## 7. Proveniência — `brain.chunk_provenance(chunk_id)`

JSON com `chunk`, `page`, `ingestion`, `version`, `document`, `source`, `file` (bucket,
caminho, nome original, mime, tamanho, sha256) e `citation` pronta:
`"Magnojet — Catálogo Magnojet V41, p. 20"`. `NULL` para quem não pode ler.

## 8. Tabelas técnicas

`kind = 'table'` (ou `'price_table'`) exige `table_data` com `headers[]` e `rows[]`;
`units{}`, `notes[]`, `page`, `family` são livres. Números ficam numéricos (a fixture
reproduz a p. 20 do Magnojet V41: `MJ981CAP … 2,76 bar → 0,77 L/min → 77 L/ha a 12
km/h`). O `content` do mesmo chunk carrega a tabela renderizada em texto, então FTS,
trigram e código exato funcionam sobre ela. Consulta quantitativa sem LLM:

```sql
select c.id, r from brain.document_chunks c, jsonb_array_elements(c.table_data->'rows') r
 where c.kind = 'table' and (r->>6)::numeric between 0.75 and 0.85;
```

## 9. Processamento externo — `brain.external_processing_for(document_id)`

| Nível do documento | Resultado |
|---|---|
| `admin` | `forbidden`, sempre — opt-in é ignorado |
| `commercial` | `forbidden`, salvo `external_processing_override` no documento (que exige `approved_by` + `approved_at`) |
| `internal` | no mínimo `approved_provider_only`; pode ser `forbidden` pela fonte ou pelo override; nunca `allowed` |
| `public` | o que a fonte define (`allowed` por padrão), ou o override |

Nenhum processamento externo é executado neste lote. A função existe para o worker
perguntar antes de mandar qualquer byte para fora.

## 10. Storage (projetado, não criado)

Bucket privado **`brain-documents`**, limite projetado 250 MB por arquivo, MIME pdf/xlsx/
docx/pptx/png/jpeg. Caminho imutável `<source_key>/<document_slug>/<version_label>/<sha256>.<ext>`
— o esquema já exige que `storage_path` termine no `file_sha256` e que `storage_bucket
= 'brain-documents'`. Policies de Storage: escrita só `service_role`/admin, UPDATE
negado (substituição silenciosa impossível), leitura por URL assinada emitida depois
da mesma checagem de nível. Criação do bucket, policies e confirmação do limite do
plano ficam para o Lote B.

## 11. Auditoria

`public.audit_capture()` (o mesmo do ERP e da Fase 1) em `knowledge_sources`,
`documents` e `document_versions`: quem cadastrou, reclassificou ou ativou uma versão
fica em `public.audit_log`. Páginas e chunks não são auditados linha a linha — a
ingestão que os gerou é a trilha (`ingestion_id` em cada um).

## 12. Testes

`supabase/db-tests/33_brain_memoria.sql` — 17 asserções, com fixtures artificiais no
formato dos documentos reais (nenhum documento real, nenhum dado do ERP alterado
permanentemente):

| # | Cobre |
|---|---|
| RAG-A1 | 7 tabelas com RLS, 8 tipos, índices FTS/trigram/códigos, zero vetor |
| RAG-A2 | 9 negativos: chunk em página inexistente, tabela sem `table_data`, texto com `table_data`, ingestão de outra versão, caminho sem sha, sha duplicado, arquivo imutável, uma vigente, opt-in sem aprovador |
| RAG-A3 | V39 withdrawn, V40 superseded ← V41 vigente, `valid_to`, `current_version()` |
| RAG-A4 | cadeia de proveniência e citação |
| RAG-A5 | páginas ligadas à versão, sha256 do texto, nível copiado |
| RAG-A6 | chunk → página e ingestão, sha256 do conteúdo |
| RAG-A7 | JSONB numérico + texto pesquisável, consulta quantitativa |
| RAG-A8 | vínculo com produto do ERP; preço e custo intactos |
| RAG-A9/10/11 | FTS, código exato (com espaço), trigram (erro de digitação) — como vendedor |
| RAG-A12 | vendedor conta zero linhas commercial/admin em todas as tabelas |
| RAG-A13 | nem busca, filtro por documento/produto, proveniência, política externa ou `current_version` vazam; vendedor não escreve; admin vê |
| RAG-A14 | vigência: só V41; histórico só pedindo; withdrawn nunca |
| RAG-A15 | política externa por nível; reclassificação desce a cadeia e o vendedor perde acesso |
| RAG-A16 | `anon` não lê nem busca |

`supabase/db-tests/ensaiar-memoria.sh` — 6 cenários: suíte 33; Fase 1 intacta (9
tabelas, 3 pontes desligadas, suítes 25–32 verdes ao lado do Lote A); `06-remover` para
com dados e remove sem dados com o retrato da Fase 1 igual antes/depois; reaplicação;
`03-remover-brain` recusa com o Lote A presente; zero vetor. Roda no CI.

## 13. Rollback

`supabase/operacao/06-remover-memoria-sem-dados.sql`: uma transação; recusa se houver
qualquer linha nas sete tabelas ou dependente externo; remove funções, tipos, tabelas e
as duas linhas do registro; confere que a Fase 1 (9 tabelas, 3 pontes com o mesmo
estado, `divergencias_erp()`) está igual. O `03-remover-brain-sem-dados.sql` (Fase 1)
agora **para** se o Lote A estiver aplicado e manda rodar o `06` antes.

## 14. Limitações do Lote A (por desenho)

- Sem vetor: perguntas semânticas sem termo em comum com o texto não acham nada.
- Sem worker: páginas e chunks entram por SQL (fixture) — o pipeline real é o Lote B.
- Sem bucket: `storage_path` é conferido por formato, não por existência do objeto.
- `commercial` = admin até decisão do Wilson.
- Provedor "aprovado" para `approved_provider_only` ainda não tem lista — Lote B/C.
- Busca por código exige que a ingestão extraia `codes[]`; o Lote A só normaliza.

## 15. O que fica para os próximos lotes

- **B** — worker de ingestão fora do banco (pdfplumber/pymupdf, OCR quando
  `text_ratio < 0,02`, tabelas → JSONB, `codes[]` por regex de fabricante), bucket
  `brain-documents` + policies, piloto com Marchioni AD-IA, DJI V16.2, Agres, Magnojet
  V41 p. 18–30 e V40, Albuz (OCR); golden dataset rodando sobre FTS+trigram → baseline.
- **C** — `vector` 0.8.2 no schema `extensions`, `embedding_models`, `chunk_embeddings`
  particionada por modelo, HNSW, quarto braço do RRF; decisão de confidencialidade por
  nível.
- **D** — avaliação (recall@5, citação correta, latência, custo), comparação de modelos,
  GO/NO-GO da Fase 2.
