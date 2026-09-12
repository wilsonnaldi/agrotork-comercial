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

- toda policy de leitura é `using (access_level <= (select brain.caller_access_level()))`
  — comparação de coluna contra um initPlan (o nível do chamador é calculado uma vez
  por consulta), sem junção, sem função `security definer` nova;
- o conjunto candidato da busca já nasce filtrado (§6), antes de qualquer ranking;
- não existe como um chunk ficar mais aberto que o documento.

Quem é o chamador, em **um** lugar — `brain.caller_access_level()`:

| Chamador | Nível |
|---|---|
| o próprio banco: sessão **sem JWT** e fora dos papéis de API (`postgres`, `service_role`, cron, migration) | `admin` |
| perfil **ativo** com `public.auth_role() = 'admin'` | `admin` |
| perfil **ativo** com `public.auth_role() = 'salesperson'` | `internal` |
| `anon`; `authenticated` sem `sub`; `sub` sem perfil; perfil inativo; papel desconhecido | `NULL` → não lê nada |

O mapeamento é por **papel explícito**, não por "qualquer usuário ativo": um valor novo em
`public.user_role` cai no `else` e não enxerga nada até ser mapeado aqui — na dúvida,
nega. A função **não** usa `brain.is_privileged()` da Fase 1: aquela aceita a marca de
sessão `brain.internal` (aberta pelas pontes do ERP), e uma marca de sessão pode ser
ligada por qualquer conexão que execute SQL; a memória não tem ponte e não precisa dessa
porta (ver §16, achado 1).

**Quem é "usuário ativo"?** `public.auth_role()` (security definer da Fase 0, filtra
`is_active`) sobre `public.profiles`. Todo usuário criado no Auth nasce `salesperson`
ativo (migration 20260831002100) — ou seja, **todo usuário que o Auth aceitar é
`internal`**, exatamente como já é tratado pelo ERP inteiro (clientes, produtos,
orçamentos próprios). Isso torna a política de cadastro do Auth de produção (*Allow new
users to sign up*) parte da fronteira de segurança da memória; está registrada como risco
residual (§16).

**Decisão embutida:** `commercial` não é concedido a papel nenhum hoje (tabela subdealer
é custo); só o administrador a alcança. Se um papel novo um dia puder ver preço de
revenda, muda-se essa função e nada mais.

## 4. RLS

RLS em todas as sete tabelas. Por tabela: `*_select` (leitura por nível — em
`knowledge_sources`, a fonte aparece se o chamador alcança o `default_access_level` dela
**ou** já enxerga algum documento dela; uma fonte `admin` sem documento visível não
aparece nem pelo nome), `*_admin_insert` (`with check is_admin`),
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
- **Estados, sem ambiguidade** (auditoria pré-publicação):
  - `draft` — nunca vigente, nunca buscável; é como se agenda uma edição futura;
  - `active` — no máximo **uma** por documento (índice único parcial). Ativar é um ato
    de hoje: `valid_from` no futuro é recusado (`check_violation`) — deixe `draft` até o
    dia. `active` com `valid_to < hoje` é uma edição **expirada**: não é vigente
    (`current_version()` devolve NULL) e não aparece na busca padrão, de propósito —
    preço vencido sem sucessora não se serve;
  - `superseded` — sempre com `valid_to` (o gatilho preenche com hoje se faltar);
    aparece só com `p_include_superseded` ou por `version_id`/`version_label`;
  - `withdrawn` — nunca aparece em busca, nem pedindo pelo id.
- `current_version()` é determinística: o índice `uq_document_versions_active` garante
  no máximo uma linha candidata; datas sobrepostas entre `superseded` e `active` são
  informativas (histórico), o **status** decide.
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

0. **Entrada**: nível do chamador NULL → conjunto vazio; `p_limit` NULL → 10, ≤ 0 →
   vazio, teto 100; pergunta normalizada e cortada em 1000 caracteres; `p_filters` NULL
   → `{}`; chave desconhecida, valor nulo ou mal formado → `invalid_parameter_value`
   com mensagem curta (nunca um erro do banco arrastando o corpo da função).
1. **Candidatos** (CTE `not materialized`): `chunk.access_level <= nível` + vigência +
   filtros (`source_key`, `document_id`, `document_type`, `brand_id`, `category_id`,
   `version_label`, `version_id`, `kind`, `product_id`). Tudo isso **antes** dos rankings
   — e o `EXPLAIN` mostra o predicado de acesso (o da função e o do RLS, como initPlan)
   no **mesmo nó de varredura** de cada braço, com `WindowAgg` (o ranking) acima (§16).
2. **A1 — código exato**: cada palavra da pergunta e a pergunta inteira viram códigos
   normalizados (`mj 981 cap` → `MJ981CAP`); `codes && v_codes`. Ordena por número de
   códigos batidos.
3. **A2 — trigram por palavra**: `pergunta <% content_norm` (operador de
   `word_similarity`, limiar 0,35 fixado **dentro da execução** com
   `set_config('pg_trgm.word_similarity_threshold','0.35', true)` — ver §17),
   ordenado por `word_similarity`. Acha `MJ981CAB`
   quando o certo é `MJ981CAP`. O operador é o indexável em `gin_trgm_ops`; a função
   sozinha não era.
4. **B — FTS**: `websearch_to_tsquery('portuguese', pergunta)` sobre `fts`, `ts_rank_cd`.
   Índice GIN.
5. **RRF, k = 60** — o que existe hoje: **três braços, nenhum vetorial**:
   `score = 1/(60+rank_exato) + 1/(60+rank_trgm) + 1/(60+rank_fts) + [1/60 se houve
   código exato]`. Cada braço contribui só se o chunk apareceu nele. O braço vetorial do
   Lote C entra como **quarta parcela** da mesma soma; a fórmula não muda de forma. Não há
   vetor porque não há embedding: nenhuma coluna, extensão, worker ou chamada externa.

**Índices e RLS — o que se mediu.** Os três operadores (`@@`, `&&`, `<%`) têm índice GIN e
o planejador os usa quando a consulta corre **sem** RLS (`postgres`/`service_role`: ~8 ms
com 43 mil chunks). Para `authenticated`, o RLS só deixa aplicar no índice operadores
*leakproof*, e nenhum desses três é — o PostgreSQL varre os candidatos e avalia os
operadores como filtro. Medido com 43 mil chunks artificiais (PG 17.6): braço exato
17 ms, FTS 16 ms, trigram 656 ms, busca inteira ~0,7 s. Com o corpus real previsto para a
Fase 2 (~5–15 mil chunks) isso fica em 0,1–0,3 s, aceitável para o Lote A. Se um dia
pesar, o caminho é um invólucro `security definer` **com a mesma CTE de candidatos como
cerca única** (o nível continua vindo do JWT), e as suítes 33/34 já provam essa cerca —
decisão registrada, não tomada (§16, risco residual).

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

Duas suítes, ambas com fixtures artificiais no formato dos documentos reais (nenhum
documento real, nenhum dado do ERP alterado permanentemente). Ambas entram em
`npm run db:test` (`run.mjs`, que também passou a listar as suítes 31 e 32 da Fase 1).

`supabase/db-tests/33_brain_memoria.sql` — 17 asserções (a memória funciona):

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

`supabase/db-tests/34_brain_memoria_hardening.sql` — 10 asserções adversariais (a
memória **não** funciona para quem não pode):

| # | Cobre |
|---|---|
| RAG-H1 | fail-closed: `sub` sem perfil, perfil inativo, `authenticated` sem `sub`, marca `brain.internal` → NULL/zero; banco = admin; vendedor = internal e nada acima |
| RAG-H2 | vazamento por ranking: termo único de um chunk `commercial` invisível por exato/trigram/FTS/histórico/`version_id`/fonte/produto/proveniência/contagem; resposta idêntica à de um termo inexistente; **score e ranks do resultado público iguais com e sem o chunk commercial** |
| RAG-H3 | cascata: subir o documento fecha versão/ingestão/página/chunk/vínculo; rebaixar um filho por UPDATE direto é desfeito pelo carimbo; voltar reabre; vizinhos intactos |
| RAG-H4 | processamento externo: admin nunca (dois overrides); opt-out em public/internal; commercial exige opt-in e respeita parcial; internal nunca abaixo de provedor aprovado; override sem aprovação recusado; apagar o aprovador preserva a decisão |
| RAG-H5 | versões: futura recusada; draft nunca vigente; uma vigente sempre; superseded sempre com `valid_to`; expirada não é vigente nem buscável; reabertura |
| RAG-H6 | limites: `p_limit` 0/negativo/NULL/enorme; pergunta NULL/branco/enorme/caracteres especiais/injeção; 6 filtros inválidos → `invalid_parameter_value`; filtros sem casamento → vazio |
| RAG-H7 | as 16 funções: `security invoker`, `search_path = ''`, `anon` sem EXECUTE, 8 de gatilho fechadas a `authenticated`, 8 de leitura abertas a `authenticated`/`service_role` |
| RAG-H8 | arquivo: 7 campos imutáveis; metadados editáveis; mesmo sha em outra obra permitido; caminho único global; sha mal formado recusado |
| RAG-H9 | fontes: vendedor vê as alcançáveis ou com documento visível, não a fonte `admin`; admin vê todas |
| RAG-H10 | `chunk_products`: FK em `public.products`; sem duplicata; produto inexistente recusado; nenhum gatilho do Lote A no ERP; inativar mantém, apagar leva o vínculo e preserva o chunk |

`supabase/db-tests/ensaiar-memoria.sh` — 6 cenários: suítes 33 e 34 (27 asserções);
Fase 1 intacta (9 tabelas, 3 pontes desligadas, suítes 27–32 verdes e suíte 25 com
**exatamente** as 5 falhas herdadas do modo desacoplado — ver §16); `06-remover` para com
dados e remove sem dados com o retrato da Fase 1 igual antes/depois; reaplicação;
`03-remover-brain` recusa com o Lote A presente; zero vetor, zero rótulo/objeto
"embedding". Roda no CI (`.github/workflows/brain.yml`, ex-`brain-fase-1.yml`, renomeado
com `git mv`).

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
- Sob RLS os índices GIN não são usados para `authenticated` (§6): custo linear no número
  de chunks visíveis, medido e aceito para o tamanho do corpus da Fase 2.

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

## 16. Auditoria pré-publicação (12/09/2026)

Revisão adversarial do Lote A antes da primeira publicação, feita localmente sobre
`8aa4c4f`, com o objetivo de corrigir aqui o que uma auditoria independente devolveria
como NO-GO. Tudo abaixo está coberto por teste (suíte 34, salvo onde indicado).

| # | Achado | Gravidade | Correção | Prova |
|---|---|---|---|---|
| 1 | `caller_access_level()` chamava `brain.is_privileged()`, que aceita a marca de sessão `brain.internal`. Um `authenticated` que executasse `set_config('brain.internal','on')` virava `admin` e a busca devolvia chunks `commercial` (reproduzido). Sem RPC que exponha `set_config`, não é alcançável pela API — mas é uma porta sem função na memória. | **alta** (defesa em profundidade) | A função passou a mapear por papel explícito (`auth_role()` = admin/salesperson) e a tratar sessão sem JWT como banco só fora dos papéis de API; nunca lê a marca de sessão. | RAG-H1 (marca ligada → continua `internal`, busca vazia, RLS fechado) |
| 2 | "Usuário ativo → internal" aceitava qualquer perfil ativo, inclusive um papel futuro desconhecido. | média | Papel desconhecido/NULL → NULL (nega). | RAG-H1 |
| 3 | `knowledge_sources` era legível por qualquer usuário ativo, inclusive fontes `admin` (nome, metadata). | baixa | Policy: alcança o `default_access_level` **ou** enxerga um documento da fonte. | RAG-H9 |
| 4 | Filtro inválido (`version_id` não-uuid, `kind` inexistente, JSON não-objeto, chave desconhecida) levantava erro bruto do PostgreSQL com o **corpo inteiro da função** no `CONTEXT`; `p_filters = NULL` devolvia silenciosamente vazio; `p_limit = 0` devolvia 1 linha. | média | Validação explícita antes da consulta (`invalid_parameter_value`, mensagem curta); NULL → `{}`; limite ≤ 0 → vazio; pergunta cortada em 1000 caracteres (45 KB levava 1,5 s). | RAG-H6 |
| 5 | Braço trigram usava a função `word_similarity()`, que **não** é indexável; o índice `idx_chunks_trgm` nunca seria usado. | média | Operador `<%` com limiar fixado na função; CTE `not materialized` para o predicado de acesso ir ao nó de varredura de cada braço. Medido: com RLS os GIN continuam fora (operadores não-leakproof) — documentado em §6 como decisão. | `EXPLAIN` (§6); RAG-A11 |
| 6 | Policies `using (brain.can_read_level(access_level))` chamavam `auth_role()` linha a linha. | baixa (desempenho; advisor `auth_rls_initplan`) | `access_level <= (select brain.caller_access_level())`. | RAG-A12/H1 |
| 7 | Índices: `idx_document_versions_document (document_id, status)` redundante com `uq_version_file` e `uq_document_versions_active`; `idx_chunks_access` (4 valores) inútil; FKs `ingestion_id` de páginas e chunks (`on delete restrict`) sem índice. | baixa | Dois removidos, dois criados (`idx_pages_ingestion`, `idx_chunks_ingestion`). 28 → 28 índices. | RAG-A1 |
| 8 | Ativar uma versão com `valid_from` futuro deixava o documento **sem edição vigente** até a data; `superseded` manual podia ficar sem `valid_to`. | média | Gatilho: futura recusada; `superseded` recebe `valid_to`. Estados documentados em §5. | RAG-H5 |
| 9 | `approved_by` é `on delete set null`, mas `chk_document_approval_pair` exigia os dois nulos ou os dois preenchidos: apagar o perfil de quem aprovou **falharia** na cascata do Auth. | média | A decisão fica pela data (`approved_at`) e pelo `audit_log`; a pessoa pode virar NULL. | RAG-H4 |
| 10 | `06-remover-memoria` quebrou após o achado 3 (policy de fontes depende de `documents`). | média (rollback) | `drop policy` antes das tabelas. | ensaiar-memoria M3b/M4 |
| 11 | Enum `ingestion_status` reservava o rótulo `'embedding'`. | baixa (escopo) | Removido; o Lote C acrescenta com `alter type … add value`. M6 confere que nada no schema se chama "embed*". | ensaiar-memoria M6 |
| 12 | `ensaiar-memoria.sh` (M2) contava só `ERROR`/`FALHOU`; a suíte 25 imprime `FALHA:`. O cenário estava **verde por engano**: a suíte 25 tem 5 falhas em produção desacoplada (BR4, BR5, BR6, BR9, BR16 esperam o evento no mesmo instante do UPDATE; as pontes estão desligadas e quem sincroniza é o cron). Elas já falham em `7973444`, sem o Lote A. | média (harness) | M2 agora exige exatamente essas 5 e nenhuma outra, e zero erro nas demais; `BR10` da suíte 25 contava 9 tabelas no schema e passou a conferir as 9 da Fase 1 por nome (única asserção da Fase 1 que o Lote A quebrava, por contagem). | ensaiar-memoria M2; bateria 7973444 × HEAD (§16.1) |
| 13 | O relatório anterior citava "2 erros herdados na suíte 15". Na bateria oficial (`run.mjs`, que roda a carga de catálogo antes) a suíte 15 é **verde** em `7973444` e em HEAD; os 2 erros vinham de rodar a suíte fora da ordem da bateria. | — (correção de relato) | Nenhuma. | §16.1 |
| 14 | `run.mjs` (`npm run db:test`) parava na suíte 30: 31, 32 e 33 não entravam na bateria. | baixa (harness) | 31–34 registradas. | bateria HEAD = base + 38 asserções |
| 15 | Workflow chamava-se `brain-fase-1.yml` validando a Fase 2. | — | `git mv` para `brain.yml`; passos inalterados (Fase 1: `conferir-operacao`, `ensaiar-deploy`; Fase 2: `ensaiar-memoria`). | CI (após publicação) |

### 16.1 Regressão medida (`run.mjs`, PG 17.6)

| | `7973444` | HEAD |
|---|---|---|
| asserções OK | 375 | 413 (= 375 + 7 + 4 + 17 + 10) |
| `FALHA` | 5 (suíte 25: BR4, BR5, BR6, BR9, BR16) | as mesmas 5 |
| `ERROR` | 0 | 0 |
| suíte 15 | verde | verde |
| `BR10` | OK (9 tabelas) | OK (16 tabelas, 9 da Fase 1 por nome) |

Ensaios da Fase 1 em HEAD: `ensaiar-deploy.sh` 17/17, `ensaiar-reconciliacao.sh`
10/10, `pontes-concorrentes.sh` OK, `conferir-operacao.sh` OK. `ensaiar-memoria.sh`
6/6 em PG 16.13, 17.6 e 18.6.

### 16.2 Extensões conferidas em produção (leitura, 12/09/2026)

`pg_trgm 1.6` e `unaccent 1.1` no schema `extensions`, com `gin_trgm_ops`,
`word_similarity`, o operador `<%` e `unaccent()` lá; USAGE em `extensions` para
`anon`, `authenticated` e `service_role` (o stub de testes espelha isso); `pgcrypto`
em `extensions` (o Lote A usa só `sha256()`/`gen_random_uuid()` do núcleo); `vector`
ausente; servidor PostgreSQL 17.6; 10 migrations do BRAIN registradas, última
`20260911220000`; nenhuma tabela do Lote A; 3 pontes desligadas.

### 16.3 Matriz de EXECUTE

| Função | `anon` | `authenticated` | `service_role` | Por quê |
|---|---|---|---|---|
| `search_knowledge`, `chunk_provenance`, `current_version`, `external_processing_for` | não | sim | sim | leitura; `security invoker`, o RLS filtra por baixo e o resultado é vazio/NULL sem nível |
| `caller_access_level`, `can_read_level` | não | sim | sim | usadas pelas policies (o chamador precisa poder executá-las) |
| `normalize_text`, `normalize_code` | não | sim | sim | puras, sem acesso a dado |
| `stamp_*` (5), `cascade_*` (3) | não | não | não | gatilhos: disparam sem EXECUTE do chamador; ninguém as chama à mão |

### 16.4 Riscos residuais

- **Cadastro no Auth**: todo usuário que o Auth de produção aceitar nasce `salesperson`
  ativo = `internal`. É a fronteira do ERP inteiro, não só da memória; a configuração
  *Allow new users to sign up* do projeto precisa estar desligada (ou o convite ser o
  único caminho). Conferência de painel, fora do escopo deste lote.
- **`brain.is_privileged()` da Fase 1** continua aceitando a marca de sessão
  `brain.internal` nas funções do CRM (leads, oportunidades, reconciliação). A memória
  não depende mais dela; a Fase 1 fica como está (fechada), registrado para auditoria.
- **Desempenho sob RLS**: custo linear nos chunks visíveis (§6). Aceito para o corpus da
  Fase 2; mitigação desenhada, não aplicada.
- **Suíte 25 em modo desacoplado**: 5 asserções da Fase 1 pressupõem pontes ligadas.
  Pendência da Fase 1; o ensaio da memória só garante que o Lote A não muda esse
  conjunto.
- **`brain` fora do PostgREST**: `search_knowledge` só é alcançável do app via schema
  exposto ou invólucro em `public` — decisão do Lote B, junto com a auditoria de consulta.

## 17. Correção pós-deploy: limiar trigram (12/09/2026)

**O que aconteceu.** No deploy real do Lote A, o Supabase gerenciado recusou a
declaração `create function brain.search_knowledge(...) ... set
pg_trgm.word_similarity_threshold = 0.35` (a versão publicada em `1cfc086`). O
PostgreSQL local (16, 17.6, 18.6) aceita essa cláusula; o gerenciado não aceitou o GUC
de extensão como configuração de função. A correção foi aplicada **em produção, durante
o deploy**: a cláusula `set` saiu da declaração e o limiar passou a ser fixado dentro
da execução, logo após normalizar a pergunta:

```sql
perform set_config('pg_trgm.word_similarity_threshold', '0.35', true);
```

Consequências: o limiar efetivo continua 0,35; é local à transação (`true`), então
nada vaza para a chamada seguinte em outra transação; a função deixa de ser `stable` e
passa a **`VOLATILE`** (altera configuração de sessão); nenhum privilégio a mais é
necessário (`set_config` de GUC de extensão é permitido a qualquer papel); grants
inalterados (`authenticated`, `service_role`; `anon` sem EXECUTE); RLS por baixo
inalterado.

**O que este repositório fez.** A migration `20260912020000_brain_memoria_busca.sql`
foi reescrita para criar **diretamente** a versão correta — o corpo da função é byte a
byte o que `pg_get_functiondef` devolve em produção (md5
`3b54175bfd5a335ff737b799ca3eb3b6`). **Produção já contém a correção; o commit apenas
sincroniza o código versionado ao estado real.** Não é uma migration nova: o ledger de
produção continua com `20260912010000` e `20260912020000`, e uma instalação do zero
cria a função certa de primeira. A suíte 34 ganhou `RAG-H11`/`RAG-H11b`: sem `SET
pg_trgm` na declaração, `VOLATILE`, md5 igual ao de produção, limiar 0,35 efetivo
(termo de controle com similaridade 0,50 é achado; a 0,6 não seria), refixado a cada
chamada e sem vazamento entre transações.

**Diferença local × gerenciado, registrada:** funções com `SET <guc-de-extensão>` na
declaração não devem ser usadas neste projeto; o padrão é `set_config(..., true)` no
corpo.
