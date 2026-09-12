# AGROTORK BRAIN — Fase 2, Lote B: ingestão sem vetores

Data: 12/09/2026 · Branch `brain/fase-2` · Base: Lote A em produção (`1cfc086` + correção
pós-deploy do limiar trigram, §17 de `fase-2-lote-a.md`)

Estado ao fechar este documento: **implementado e ensaiado localmente; nada aplicado em
produção** (nenhuma migration, bucket, worker, documento, configuração de Auth/Storage/plano).

## 1. O que o Lote B é

O caminho completo, sem vetor:

```
arquivo → sha256 → versão → páginas → chunks (texto e tabela) → metadados → busca textual → proveniência
```

Três peças novas e uma porta:

1. **API de ingestão em SQL** (migration `20260912030000_brain_ingestao.sql`): `brain.register_version`,
   `brain.ingestion_start`, `brain.ingestion_add_page`, `brain.ingestion_add_chunk`,
   `brain.ingestion_finish`, `brain.ingestion_fail`, `brain.ingestion_record_failure`. Toda regra — checksum, idempotência, página
   obrigatória, contagens, estado coerente — mora no banco. Qualquer worker (este, ou outro no
   futuro) só chama estas funções.
2. **Worker de ingestão** (`brain/worker`, Python 3.11+): lê PDF/XLSX/CSV/TXT/MD, calcula sha256,
   extrai texto por página, detecta tabelas técnicas, decide OCR local, fatia de forma
   determinística e grava pela API. Roda fora do banco; conecta com uma URL em variável de
   ambiente (`BRAIN_DB_URL`), nunca versionada.
3. **Trilha de consulta** (`brain.knowledge_queries`): quem perguntou, o que, com que nível,
   quantos resultados e quais chunks. Nunca o conteúdo devolvido.
4. **Porta do aplicativo**: `public.brain_search()` e `public.brain_provenance()` (as únicas funções
   do BRAIN visíveis ao PostgREST) + módulo `src/modules/brain` (Server Actions
   `askKnowledgeAction` / `knowledgeProvenanceAction`).

O que continua **fora**: pgvector, embedding, HNSW/IVFFlat, `chunk_embeddings`, provedor de
embedding (Lote C); bucket produtivo; chatbot; agente; n8n.

## 2. Arquitetura

```
        brain/worker (Python, fora do banco)           aplicativo (Next.js)
        ─────────────────────────────────────          ─────────────────────────────
        arquivo local ──► extract ──► chunk ──► db.py   askKnowledgeAction (Server Action)
                                            │                 │  sessão do usuário (RLS)
                                            ▼                 ▼
   ┌──────────────────────────────── PostgreSQL / Supabase ────────────────────────────────┐
   │ brain.register_version / ingestion_*  (security invoker; escrita = admin/service)     │
   │ brain.document_versions ─ pages ─ chunks ─ ingestions  (RLS por nível, Lote A)         │
   │ brain.search_knowledge (Lote A)  ◄── public.brain_search ──► brain.knowledge_queries   │
   │ brain.chunk_provenance (Lote A)  ◄── public.brain_provenance                            │
   │ storage.objects: policies brain_documents_* (bucket ainda não criado)                  │
   └───────────────────────────────────────────────────────────────────────────────────────┘
```

O schema `brain` não é exposto ao PostgREST (nada do BRAIN vira endpoint por acidente). O
aplicativo só enxerga as duas funções em `public`, ambas `security invoker`: o RLS do Lote A
continua sendo a autorização de verdade.

## 3. API de ingestão

| Função | Faz | Recusa (errcode) |
|---|---|---|
| `register_version(document_id, label, sha256, filename, mime, size, date?, page_count?, metadata?) → uuid` | Mesmo documento + mesmo sha → **devolve a versão existente** (idempotente, com qualquer rótulo). Arquivo novo → versão nova em `draft`, `storage_path = <fonte>/<documento>/<rótulo>/<sha>.<ext>`. Ativar é ato separado. | sha inválido, tamanho ≤ 0, rótulo vazio (`invalid_parameter_value`); documento inexistente/invisível (`no_data_found`); **mesmo rótulo com arquivo diferente** (`unique_violation`) |
| `ingestion_start(version_id, method, parser, pipeline_version, executor?, needs_ocr?, pages_total?, replace?) → uuid` | **Trava a versão (`for update`) até o COMMIT do chamador** e abre a ingestão (`extracting`, `started_at`). Versão que já tem conteúdo só reprocessa com `replace = true`: páginas e chunks antigos saem **dentro da mesma transação** em que o conteúdo novo entra; ingestões anteriores viram histórico (`metadata.replaced_by`). | `pipeline_version` vazio; versão inexistente; ingestão aberta e commitada na versão (`object_in_use`); conteúdo existente sem `replace` (`unique_violation`) |
| `ingestion_add_page(ingestion_id, page_no, text, extraction, ocr?, layout?, metadata?)` | Grava/atualiza a página (sha do texto pelo gatilho). Reenvio na mesma ingestão substitui; de outra ingestão, nunca. Muda o status para `chunking`. | ingestão fechada (`object_not_in_prerequisite_state`); página de outra ingestão (`unique_violation`) |
| `ingestion_add_chunk(ingestion_id, ordinal, kind, page_from, page_to, content, heading_path?, table_data?, codes?, token_count?, metadata?) → bigint` | Grava o chunk. Página precisa existir na versão (FK composta); tabela precisa de `table_data` com estrutura (constraint); códigos normalizados pelo gatilho. | página não registrada (`foreign_key_violation`); ingestão fechada; forma da tabela (`check_violation`) |
| `ingestion_finish(ingestion_id, status = completed, error?, warnings?, metrics?) → knowledge_ingestions` | Fecha: `pages_done`, `chunks_created`, `tables_created` **contados nas tabelas**, não informados; `finished_at`. | `completed` sem página, ou com menos páginas que `pages_total` (`check_violation` — use `partial`); `failed` sem erro; fechar duas vezes; status fora de `completed/failed/partial` |
| `ingestion_fail(ingestion_id, error, warnings?)` | Atalho para `failed` com erro, para uma ingestão ainda aberta na transação. | idem |
| `ingestion_record_failure(version_id, method, parser, pipeline_version, executor, error, warnings?, replace_attempt?, started_at?) → knowledge_ingestions` | Trilha de uma tentativa **desfeita por rollback** (a ingestão aberta já não existe): linha `failed`, sem página nem chunk, `metadata = {rolled_back: true, replace_attempt}`. Chamada numa transação própria. | versão inexistente; erro vazio |

Todas: `security invoker`, `search_path = ''`, EXECUTE para `authenticated` e `service_role`,
nenhum para `anon`. Um `authenticated` só consegue algo se for administrador — o INSERT/UPDATE/
DELETE das tabelas é `is_admin()` no RLS (suíte 35, B18).

## 4. Worker (`brain/worker`)

```
brain/worker/
  brain_worker/
    __init__.py     PIPELINE_VERSION = "lote-b.1"
    extract.py      PDF (pdfplumber), XLSX (openpyxl), CSV, TXT/MD; OCR local (tesseract) só quando falta camada textual
    tables.py       tabela técnica → table_data (JSONB) + texto pesquisável; números pt-BR → numéricos
    chunking.py     chunking determinístico por página
    codes.py        códigos de peça/modelo (MJ981CAP, T70P, DB1580, 4626215)
    gate.py         porteiro do processamento externo (consulta brain.external_processing_for)
    db.py           só as funções da API (psycopg 3)
    pipeline.py     arquivo → plano → transação
    __main__.py     CLI: `python -m brain_worker plan|ingest`
  tests/            fixtures sintéticas (reportlab/openpyxl) + 20 testes (11 unidade, 9 com banco)
  requirements.txt
```

```
export BRAIN_DB_URL=postgresql://...            # nunca em argumento, nunca em log
python -m brain_worker plan   catalogo.pdf --json                       # só extrai e fatia
python -m brain_worker ingest catalogo.pdf --document magnojet-catalogo --label V41 [--replace] [--ocr auto|never|force] [--price-table]
```

Cada ingestão registra: arquivo (nome, tipo, tamanho), checksum, versão, `method`
(`pdf_text` / `pdf_ocr` / `xlsx` / `other`), `parser` (ex.: `pdfplumber 0.11.9`),
`pipeline_version`, `executor`, páginas totais/processadas, chunks, tabelas, `warnings`, `error`,
início/fim, `metrics` (tempos e configuração do chunking), `needs_ocr`, `text_ratio`.

**Transações (corrigido na auditoria pós-publicação, §20)** — duas, e só duas:

- **T1** `register_version`: a versão (draft) é confirmada sozinha — "registrada, sem conteúdo" é
  um estado legítimo e reexecutável;
- **T2** `ingestion_start` (com ou sem `replace`) + páginas + chunks + `ingestion_finish`. **Nada
  é confirmado no meio.** Com `replace`, a remoção do conteúdo antigo e o conteúdo novo entram
  ou saem juntos: se qualquer passo falhar, o rollback devolve páginas e chunks anteriores
  exatamente como estavam (ids, hashes, `ingestion_id`, busca, proveniência) e nada do novo
  sobra. A tentativa é então registrada por `ingestion_record_failure` numa transação própria
  (**T3**, só nesse caso).

Semânticas explícitas: reexecutar o mesmo arquivo é `skipped` (mesma versão, 1 ingestão);
`--replace` reprocessa e reproduz os mesmos chunks; **primeira ingestão de uma versão nova que
falha** → a versão fica `draft`, com zero páginas/chunks, uma linha `failed` na trilha
(`replace_attempt = false`), e reexecutar **sem** `--replace` ingere normalmente (D8, B22);
**crash do processo** no meio da T2 → o servidor desfaz a transação, o conteúdo anterior fica,
a trilha não recebe linha (não há quem a escreva) — o operador vê "sem ingestão nova" e
reexecuta; **duas ingestões concorrentes** na mesma versão → a segunda espera o lock da primeira
e, ao acordar, vê o conteúdo dela e é recusada sem `replace` (D9).

**Formatos e unidade de proveniência**

| Formato | Unidade "página" | `extraction` |
|---|---|---|
| PDF com camada textual | página do PDF | `text_layer` |
| PDF digitalizado | página do PDF, OCR local | `ocr` (ou `none` se não houver tesseract → ingestão `partial`) |
| XLSX | **cada aba** é uma página; a aba inteira é uma tabela | `spreadsheet` |
| CSV | uma página, uma tabela | `spreadsheet` |
| TXT/MD | páginas separadas por form-feed (`\f`); sem ele, uma página | `text_layer` |

Todo chunk aponta para uma página existente da mesma versão (FK composta do Lote A) e nunca
atravessa página (`page_from = page_to`). Não existe chunk sem página.

## 5. Chunking determinístico

Mesmo texto + mesma configuração + mesmo `pipeline_version` → mesmos chunks, byte a byte. Sem
aleatoriedade, relógio ou dependência de ambiente. Provado três vezes: no worker (W4), na API
(B6) e de ponta a ponta (I2c: hash dos `(ordinal, sha256, página)` antes e depois do `--replace`).

Regras (`chunking.py`, `CONFIG = {target: 900, max: 1400, min_merge: 200, overlap: 120, unit: page}`):

- a unidade é a página; nada cruza página;
- dentro da página o texto vira blocos: **título** (linha ≤ 80 caracteres, em caixa alta ou
  numerada, ≥ 3 letras e no máximo 25 % de dígitos — uma linha de tabela não é título) ou
  **parágrafo** (separado por linha em branco) ou **lista** (linhas iniciadas por marcador);
- parágrafos consecutivos sob o mesmo título se juntam até 900 caracteres; parágrafo maior que
  1400 é fatiado por frase, com 120 caracteres repetidos entre fatias (a única repetição
  permitida), sem cortar palavra;
- **tabela é chunk próprio** (`table` ou `price_table` quando há coluna em R$/preço), nunca
  fatiada, nunca misturada com texto; o texto da página **não** repete o que está dentro da
  tabela (pdfplumber filtra os caracteres dentro da caixa da tabela);
- `heading_path` é a pilha de títulos vigente (profundidade 3; só o primeiro nível atravessa
  páginas); entra na busca (§8);
- `ordinal` é sequencial no documento; conteúdo idêntico na mesma página é descartado (o banco
  recusaria); em páginas diferentes são dois chunks, cada um com a sua citação;
- `codes[]`: letras+dígitos (`MJ981CAP`, `T70P`, `DB1580`, `C12000`, `MUG-CV02`) e números
  puros de 7–9 dígitos (código Arag `4626215`); preço em reais (até 6 dígitos inteiros) fica de
  fora de propósito. O banco normaliza de novo ao gravar.

## 6. Tabelas técnicas (Magnojet p. 20 como referência)

`table_data` = `{page, headers, labels, units, rows, notes}`: `headers` são chaves estáveis sem
acento (`Pressao_bar`, `Vazao_L/min`, `L/ha_a_12_km/h`), `labels` são os cabeçalhos como estão
no documento (`Pressão (bar)`, `Vazão (L/min)`), `units` vêm do próprio cabeçalho (`bar`, `psi`,
`L/min`, `L/ha`, `km/h`, `BRL`… — só por token inteiro: o "m" de "mínimo" não vira metro),
`rows` têm **números numéricos** (`"2,76"` → `2.76`, `"1.234,56"` → `1234.56`, `"R$ 165.500,00"`
→ `165500.0`). O texto pesquisável (`content`) é o cabeçalho + uma linha por registro:
`PS981CAP SOL-CV 02 UG 2,76 bar 40 psi 0,77 L/min 77 L/ha`. Consulta quantitativa direto no JSONB
(B7, BG2: "PS981CAP a 40 psi → 77 L/ha").

## 7. OCR

Decisão por PDF: `text_ratio` = caracteres por página (média). Abaixo de 40 o PDF é tratado como
digitalizado (`needs_ocr = true`) e o OCR **local** (tesseract, via pytesseract) roda só nas
páginas sem texto; com camada textual confiável o OCR não roda mesmo em `--ocr auto` (W6).
`--ocr never` desliga; `--ocr force` obriga. Sem tesseract instalado, as páginas ficam
`extraction = none` e a ingestão fecha `partial` com aviso — nunca `completed` fingindo.
Qualidade: por enquanto `text_ratio` e o aviso por página; métrica de confiança do OCR fica para
quando houver documento digitalizado real (Albuz, Catálogo Digital JR — inventário da Etapa 0).
Idioma: `por+eng` quando o pacote português existe, senão `eng` (o CI tem só `eng`).

## 8. Busca (o que mudou no Lote A)

Os três braços e o RRF (k = 60) do Lote A continuam **inalterados** — a função
`brain.search_knowledge` é byte a byte a de produção (`RAG-H11`). O que a migração do Lote B muda
é o **schema** que a alimenta:

- `document_chunks.heading_norm` (gatilho `stamp_chunk`, normalizado como `content_norm`) e o
  `fts` regenerado como `setweight(to_tsvector('portuguese', heading_norm), 'A') ||
  setweight(to_tsvector('portuguese', content_norm), 'B')`. Sem isso, "cone vazio ultra grossa"
  (título da tabela, não do texto das linhas) não achava a tabela (BG1);
- o texto da tabela começa pelo cabeçalho ("Vazão (L/min)"): "vazão" só existia ali;
- `uq_chunk_content` passou de `(version_id, content_sha256)` para `(version_id, page_from,
  content_sha256)`: um catálogo repete rodapé/aviso em páginas diferentes e o primeiro documento
  sintético com parágrafo repetido esbarrou na constraint antiga (B19, D3).

Limite conhecido: `websearch_to_tsquery` é **E** entre termos — perguntas longas com palavras que
não estão no chunk não casam por FTS (o trigram e o código exato compensam parte). A resposta
"não encontrei evidência suficiente" (`SEM_EVIDENCIA` no módulo) é preferida a inventar; recall
semântico é o Lote C.

## 9. Proveniência

`brain.chunk_provenance` (Lote A) devolve chunk → página → ingestão → versão → documento → fonte →
arquivo/sha256 e a citação `"<fonte> — <título> <versão>, p. N"`. O Lote B garante que cada elo
existe de verdade: a ingestão registra `pipeline_version`, `parser`, `method`, `extraction` e
`ocr` por página; o arquivo é identificado pelo sha256 que também termina o `storage_path`.
`public.brain_provenance` repassa com a sessão do usuário (NULL para quem não pode ler).

## 10. Storage (projetado; bucket não criado)

- bucket `brain-documents`, **privado**, sem URL pública, objeto = `storage_path` da versão
  (`<fonte>/<documento>/<rótulo>/<sha256>.<ext>`);
- policies em `storage.objects` (na migration, inertes até o bucket existir): leitura se o
  chamador alcança o `access_level` da versão dona do caminho; insert/update/delete só
  `is_admin()`; **insert e rename exigem versão registrada** (§20): o `with check` só aceita
  objeto cujo `name` seja exatamente o `storage_path` de uma `brain.document_versions` com
  `storage_bucket = 'brain-documents'` — nem admin consegue subir objeto órfão nem renomear
  para um caminho não registrado (B23);
- criação do bucket: `supabase/operacao/07-criar-bucket-brain-documents.sql`, idempotente, exige
  as 4 policies, tipos permitidos PDF/XLSX/CSV/TXT/MD;
- **limite de tamanho depende do plano** (§16): o projeto está no plano **Free**, cujo teto de
  upload é **50 MB por arquivo** seja qual for o `file_size_limit` do bucket. Catálogo Magnojet
  V41 = 177 MB, V40 = 162 MB. Os ~250 MB projetados na Etapa 0 exigem plano Pro;
- o worker não sobe arquivo neste lote: registra o `storage_path` canônico e ingere do arquivo
  local. Upload é passo do próximo checkpoint, depois da decisão de plano.

## 11. Segurança e processamento externo

- Signup público do Auth: **desligado** em produção (gate fechado em 12/09); não alterado aqui.
- RLS: `knowledge_queries` com RLS (insert só do próprio usuário ativo; select só admin; sem
  update/delete — trilha append-only). As 7 tabelas do Lote A inalteradas.
- Funções: 9 novas (7 da API + 2 em `public`), todas `security invoker` + `search_path = ''`, `anon` sem EXECUTE (B20, RAG-H7).
- Nenhuma chave, senha ou token em código, fixture, log, documentação ou bundle; a conexão do worker
  vem de `BRAIN_DB_URL` e o ensaio usa socket/porta locais.
- **Porteiro externo** (`gate.py`): antes de qualquer byte sair do ambiente aprovado, `allow(document_id,
  provider)` consulta `brain.external_processing_for`: `allowed` → pode; `approved_provider_only` →
  só provedor da lista aprovada (vazia no Lote B); `forbidden` ou documento invisível → **não sai**.
  Não há bypass: nenhum provedor externo está configurado neste lote (OCR é local) — o porteiro existe
  para o Lote C herdar a regra testada (D5, B11–B13).
- Matriz confirmada (B11–B13, RAG-H4): public `allowed`; internal `approved_provider_only` (piso,
  mesmo com a fonte em `allowed`); commercial `forbidden` salvo opt-in registrado (parcial fica
  parcial); admin `forbidden` sempre.
- O worker **não escreve no ERP**: nenhum gatilho do brain em `products`/`product_costs`/
  `margin_rules`/`stock_movements`; nenhum produto criado (B19, D6, I2d).

## 12. Versionamento

Como no Lote A (§5 de `fase-2-lote-a.md`), com o que o worker acrescenta: versão nasce `draft`
(nunca aparece na busca, nem para admin — B14); ativar é `update ... set status = 'active'`
(decisão humana); a ativa anterior vira `superseded` (B16); `withdrawn` nunca aparece (B17);
mesmo arquivo em rótulo diferente não duplica; rótulo repetido com arquivo diferente é recusado
(B2, B3, D2, D3).

## 13. Golden dataset

`docs/brain/golden-dataset-v0.json` inalterado (sem justificativa para mudar). As perguntas
1, 2, 5, 12, 13 e 14 são exercitadas na suíte 35 (`BG*`) sobre o documento sintético
"Pontas Sol" (PS981CAP ↔ MJ981CAP, tabela no formato da p. 20): vazão pela tabela e pelo JSONB,
L/ha a 40 psi = 77, versão vigente citada por padrão, código inexistente → zero, Kuhn → zero e
zero fonte, planilha admin invisível ao vendedor (nem por tema nem pelo número) e visível ao
administrador. As demais (Arag.xlsx, DJI V14.11→V16.2, Fighter AD-IA) dependem de documento
real e ficam para a ingestão piloto autorizada.

## 14. Testes

| Onde | O quê | Asserções |
|---|---|---|
| `supabase/db-tests/35_brain_ingestao.sql` | B1–B24 + BG1, BG2, BG5, BG12, BG13, BG14 — B21 `--replace` atômico (falha após remoção → conteúdo anterior idêntico, falha auditada, sucesso sem mistura), B22 primeira ingestão falhada (draft vazio, reingestão sem `--replace`, `object_in_use` para ingestão aberta), B23 storage sem objeto órfão, B24 usuário inativo/sem perfil na busca | 30 |
| `brain/worker/tests/test_worker.py` | W1–W6: sha/mime/assinatura, páginas e tabela, números pt-BR, códigos, determinismo, isolamento de páginas, títulos, XLSX/TXT, OCR | 11 |
| `brain/worker/tests/test_pipeline_db.py` | D1–D9 contra o banco: ingestão completa, idempotência e `--replace`, arquivo diferente, busca+proveniência após ativar, porteiro externo, falha registrada e ERP intocado; **D7** falha forçada em 4 pontos do `--replace` (após `start`, após páginas, no meio dos chunks, antes de `finish`) com retrato de páginas/chunks/hashes/busca/proveniência idêntico e zero conteúdo parcial; **D8** semântica da primeira ingestão falhada; **D9** duas ingestões concorrentes da mesma versão serializam no lock | 9 |
| `supabase/db-tests/ensaiar-ingestao.sh` | I1–I8: suíte 35 (30); worker de ponta a ponta com PDF sintético (CLI); pytest (D1–D9); `06` remove A+B e `03` recusa; reaplicação → 33/34/35 (59); zero vetor e zero documento real versionado; bucket só pelo roteiro 07; **I7** `08` remove só o Lote B com retrato estrutural igual ao do Lote A puro; **I8** `08` recusa conteúdo repetido em páginas diferentes | 8 cenários |
| `supabase/db-tests/34_brain_memoria_hardening.sql` | + RAG-H11/H11b (sincronização pós-deploy do limiar trigram) | +2 |

`npm run db:test` (`run.mjs`) inclui a suíte 35. Documentos usados: **somente sintéticos**, gerados
na hora por `brain/worker/tests/fixtures.py` (reportlab/openpyxl, `invariant=1` para bytes
estáveis). Nenhum PDF/XLSX/DOCX versionado (I5 confere com `git ls-files`).

## 15. Rollback

`supabase/operacao/06-remover-memoria-sem-dados.sql` passou a remover **A + B** numa transação:
as 2 funções `public.brain_*`, as 6 da API, `knowledge_queries`, as 4 policies de storage, e
então tudo do Lote A; apaga os 3 registros do ledger; confere o retrato da Fase 1 antes e
depois. Continua recusando se qualquer das sete tabelas de conteúdo tiver linha (a trilha de
consulta pode ter linhas). O `03-remover-brain` (Fase 1) segue exigindo o `06` antes. Ensaiado em
I4 e M3/M4.

**Voltar só o Lote B, preservando o Lote A** (`supabase/operacao/08-remover-lote-b-sem-dados.sql`,
exigido pela auditoria pós-publicação, §20): uma transação que remove `public.brain_search`,
`public.brain_provenance`, as 7 funções da API (inclusive `ingestion_record_failure`),
`knowledge_queries` e as 4 policies `brain_documents_*`, e devolve `document_chunks` ao formato
exato do Lote A — sem `heading_norm`, `fts` gerado só de `content_norm` (`to_tsvector('portuguese',
content_norm)`), índice `idx_chunks_fts` recriado, `uq_chunk_content (version_id, content_sha256)`,
`stamp_chunk()` restaurado byte a byte da migration `010000`. Apaga apenas o registro
`20260912030000` do ledger; `010000` e `020000` ficam. Pré-condições: Lote A presente, Lote B
presente, e **recusa** se houver chunk com o mesmo conteúdo em páginas diferentes da mesma versão
(o formato do Lote A não admite; a mensagem manda decidir à mão). Pós-condições: nenhum objeto
do Lote B, expressão do `fts`, colunas da constraint, índice, ledger, 7 tabelas do Lote A,
`search_knowledge`/`chunk_provenance` presentes, retrato da Fase 1 igual, pontes desligadas,
zero `vector`. `supabase/db-tests/retrato-memoria.sql` gera o retrato estrutural (colunas, tipos,
expressões geradas, constraints, índices, policies, md5 das funções, triggers, enums, ledger) usado
para provar que **Lote A → +B → 08 = Lote A** (I7). Única diferença invisível ao retrato: a coluna
`fts` recriada fica na última posição física da tabela (Postgres não reordena colunas sem
reconstruir a tabela); nenhum código do sistema depende de `select *` em `document_chunks`.

## 16. Decisões que exigem o Wilson (não tomadas aqui)

1. **Plano/Storage**: com Free, o upload é limitado a 50 MB por arquivo — Magnojet V41 (177 MB) e
   V40 (162 MB) não sobem. Opções: (a) plano Pro e bucket a 250 MB; (b) ficar no Free e ingerir
   catálogos grandes **do arquivo local** (o worker já faz isso; só o download do original pela
   memória fica indisponível); (c) comprimir/dividir os PDFs. O roteiro 07 só roda depois disso.
2. **Autorização para criar o bucket em produção** (roteiro 07) e **para a ingestão piloto** de
   documentos reais (Magnojet V41, um DJI, um Agres/Arag) — com o nível de acesso de cada um.
3. **Kuhn** continua lacuna de fonte (sem documento, sem pesquisa na internet).

## 17. Riscos e limitações

- FTS é E entre termos (§8); perguntas longas dependem de trigram/código. Recall semântico = Lote C.
- OCR: só tesseract local, sem métrica de confiança; sem pacote `por` no CI.
- Tabelas: pdfplumber detecta tabelas com linhas/grades; tabelas "sem borda" podem virar texto
  corrido (aviso por página). A p. 20 real do Magnojet precisa da ingestão piloto para calibrar.
- Desempenho sob RLS (Lote A §6) inalterado: custo linear nos chunks visíveis.
- `search_knowledge` não foi alterada de propósito (md5 = produção); melhorias de ranking ficam
  para depois da ingestão piloto, com o golden dataset real.
- Advisors de produção após o Lote A: sem WARN de segurança novo nas tabelas `brain`; WARNs
  anteriores do ERP (funções `security definer` em `public`) e *Leaked Password Protection
  Disabled* são baseline, fora deste lote. Performance: 13 FKs do Lote A sem índice (§18).
- Hardening futuro registrado, não aplicado: `handle_new_user()` criar cadastro espontâneo com
  `is_active = false`.

## 18. FKs do Lote A sem índice (advisor `unindexed_foreign_keys`)

| FK | DELETE/UPDATE relevante? | Cardinalidade | Caminho de consulta | Decisão |
|---|---|---|---|---|
| `documents.category_id` | `on delete set null` (categorias raramente somem) | dezenas de documentos | filtro `category_id` da busca (join por documento, poucas linhas) | **útil depois** — criar quando houver centenas de documentos |
| `document_versions.supersedes_id`, `superseded_by_id` | `set null` ao apagar versão (raro); `stamp_version` procura `superseded_by_id = new.id` por documento | poucas por documento | por documento, já filtrado por `document_id` | desnecessário |
| `documents.approved_by/created_by/updated_by`, `document_versions.imported_by`, `knowledge_ingestions.created_by`, `knowledge_sources.created_by/updated_by`, `chunk_products.linked_by_user` | `set null` ao apagar perfil — evento raro, tabelas pequenas | dezenas a centenas | nunca consultadas por pessoa | desnecessário |
| `knowledge_sources.brand_id`, `supplier_id` | `set null` ao apagar marca/fornecedor (raro) | dezenas | nenhuma | desnecessário |

Nenhum índice novo neste lote por esse motivo; `knowledge_queries.user_id` (Lote B) já nasce
indexado porque é o caminho de leitura da trilha.

## 19. Diferenças local × produção

- Funções não usam `SET <guc de extensão>` na declaração (o gerenciado recusa); limiar trigram por
  `set_config` no corpo (Lote A §17). Os testes locais rodam em PG 16/17.6/18.6 puros com o stub.
- Storage: localmente o stub reproduz `storage.buckets/objects`; as policies são criadas nos dois
  ambientes; o bucket só pelo roteiro 07.
- OCR: tesseract presente localmente (`eng`), ausente no CI — o worker degrada para `partial`.
- `pgcrypto` em `public` localmente e em `extensions` na produção; o Lote B usa só `sha256()`
  do núcleo.
- Worker: conecta como `postgres` no ensaio; em produção conectará com credencial de serviço,
  configurada fora do repositório.

## 20. Auditoria pós-publicação (NO-GO sobre `66c0353`) — o que foi corrigido

Lote B **não foi publicado**; a auditoria do ChatGPT devolveu dois bloqueadores e um hardening.
Tudo abaixo está em commits novos sobre `66c0353`, sem push, sem deploy, produção intocada.

| # | Achado | Gravidade | Correção | Prova |
|---|---|---|---|---|
| 1 | `--replace` não era atômico: o worker fazia commit logo depois de `ingestion_start` (que já apagara páginas e chunks antigos); uma falha posterior perdia o conteúdo válido anterior | **bloqueador** | `ingestion_start` + páginas + chunks + `ingestion_finish` numa única transação (T2); qualquer erro → `rollback` completo, conteúdo anterior intacto; a tentativa falhada é registrada **depois**, em transação independente, por `brain.ingestion_record_failure` (T3) — §4 | D7 (4 pontos de falha), B21, I3 |
| 2 | Rollback só de A+B (`06`): não havia caminho para voltar o Lote B preservando o Lote A publicado | **bloqueador** | `08-remover-lote-b-sem-dados.sql` + `retrato-memoria.sql` — §15 | I7 (retrato Lote A puro = retrato após 08; 33/34 verdes depois), I8 (recusa conteúdo repetido entre páginas) |
| 3 | Storage aceitava objeto órfão: admin podia subir qualquer `name` no bucket, sem versão registrada | hardening | `brain_documents_write` e `brain_documents_update` exigem `storage.objects.name = storage_path` de uma `document_versions` em `brain-documents` — §10 | B23 (órfão e variante `.PDF` recusados, caminho exato aceito, rename para órfão recusado, vendedor não escreve, leitura por nível) |
| 4 | `public.brain_search` com usuário inativo ou sem perfil: `caller_access_level()` nulo, mas a função ainda gravava trilha em `knowledge_queries` antes de devolver vazio | defeito | retorna vazio **antes** de gravar quando `auth.uid()` ou o nível é nulo | B24 |
| 5 | Duas ingestões da mesma versão ao mesmo tempo: a verificação de "ingestão aberta" só via linhas commitadas | defeito | `ingestion_start` trava a versão com `select … for update`; a segunda espera e, ao ver conteúdo/ingestão da primeira, é recusada | D9, B22 |
| 6 | Semântica da **primeira** ingestão falhada de uma versão nova não estava definida | lacuna | versão fica `draft` com 0 páginas/0 chunks e uma `knowledge_ingestions` `failed` (`rolled_back=true`, `replace_attempt=false`); reingestão **sem** `--replace` completa normalmente; histórico `failed → completed` — §4 | D8, B22 |

Ajustes de acompanhamento: `06` também remove `ingestion_record_failure`; `ingestion_fail`
continua existindo (fecha ingestão aberta na mesma transação) mas o worker não a usa mais; o
crash do worker no meio de T2 deixa a sessão morrer e o Postgres desfaz tudo — sem registro de
falha nesse caso (não há quem o escreva), o que a próxima ingestão detecta pela ausência de
ingestão aberta e pelo conteúdo anterior intacto.

**O que não mudou**: `pg_trgm` sincronizado (RAG-H11), limiar 0,35 por `set_config(..., true)`,
`search_knowledge` VOLATILE e byte-idêntica à produção, RLS e fail-closed do Lote A, `brain_search`/
`brain_provenance` (assinaturas), trilha de consulta, tabelas técnicas em JSONB, chunking
determinístico, OCR local, porteiro externo, zero pgvector, pontes desligadas, ERP como fonte
da verdade, autoria `AgroTork <dev@agrotork.local>`, as 5 `FALHA` herdadas da suíte 25 na
bateria (BR4/5/6/9/16) continuam visíveis e comparadas com a baseline.
