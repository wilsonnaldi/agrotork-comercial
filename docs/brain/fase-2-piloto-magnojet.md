# AGROTORK BRAIN — Fase 2, piloto Magnojet V41 e calibração (lote-b.2)

Data: 12/09/2026 · Branch `brain/fase-2` · Base remota auditada: `f46654a` · Lote B em
produção (migration `20260912030000`) · Worker calibrado: `lote-b.2` · Busca calibrada:
migration `20260912040000_brain_busca_calibracao_piloto.sql`.

Estado: **calibração feita e provada localmente; produção intocada** — fonte `magnojet`,
documento `magnojet-catalogo` e versão V41 registrados em `draft`, sem ingestão, sem página,
sem chunk, sem versão ativa. O conteúdo real só existe em banco local descartável.

## 1. O piloto (lote-b.1) e o que ele encontrou

Arquivo: `MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf` (V41, capa "V41 02"; InDesign 21.4, 05/06/2026;
172 páginas A4; 177 741 060 bytes; sha256 `78af9b13b54b5e6b1adf7a2b5dfdfd9996d8cb77a2bbfa89a4f623cec76365e1`).
Camada textual em todas as páginas (2 434 caracteres/página no lote-b.1); OCR não necessário.

| # | Achado no catálogo real (lote-b.1) | Extensão |
|---|---|---|
| 1 | O worker estourava memória: pdfplumber guarda os objetos de todas as páginas lidas; 172 páginas de vetores passaram de 6 GB e o processo foi morto | bloqueava o piloto |
| 2 | Tabelas de vazão: o detector por régua (`find_tables`) fundia as colunas 12–20 km/h numa célula ("77 66 5" / "8 51 46"), deixava o cabeçalho de velocidades cair como linha de dados e não propagava o código do grupo | 54 tabelas; 28 com 1 158 células fundidas; `L/ha a 12 km/h` irrespondível pelo JSONB |
| 3 | Títulos contaminados por texto vertical ("Õ E S" = SOLUÇÕES letra a letra; "OCINÔC" = CÔNICO invertido); título real da página ("MAGNO ULTRA GROSSA / CONE VAZIO") perdido quando vários títulos se seguem sem parágrafo | 1 271 de 1 272 chunks com `heading_path[1] = "Õ E S"` |
| 4 | Códigos não reconhecidos: `M 714`, `M 691/1`, `MJ059/1`, `MUG-CV 02` | 196 de 274 tabelas sem `codes` |
| 5 | `price_table` falso na p.5: "valoriza" casava com `/valor/` | 1 |
| 6 | Página de desenho (p.100) fatiada em dezenas de chunks de 1–3 palavras | 499 chunks < 40 caracteres |
| 7 | Busca: código dentro de frase zerava ("Em qual catálogo aparece a ponta MJ983CAP?"); código inexistente caía no trigram de prosa e devolvia trecho "parecido" (MJ999CAP; Arag 466113200); pergunta natural longa zerava | golden: Q1, Q5 FAIL; Q10, Q12 falsos positivos |

## 2. O que mudou (worker `lote-b.2`)

Regra preservada em tudo: **a tabela vira dado confiável primeiro; a busca recebe o dado
depois**. Nenhum número, página, código ou valor do catálogo está no código.

### 2.1 Memória (commit `7874907`, auditado nesta rodada)

`extract_pdf` chama `page.flush_cache()` + `page.close()` assim que a página foi extraída.
Antes: > 6 GB e OOM na página ~100. Depois: **pico de 1 190 MB** (`ru_maxrss`) para as 172
páginas, 426–445 s. Onde o lote-b.1 estava certo, o conteúdo continua igual: 84 das 131
páginas com tabela têm exatamente as mesmas sequências numéricas; as 47 diferentes são as
tabelas que o lote-b.1 lia errado (44 de vazão + p.8, p.83, p.149) — texto/chunking mudaram
só pelas regras de título e agregação abaixo. Os 18 + 9 testes passam.

### 2.2 Tabelas técnicas por geometria (`spatial.py`) + auditor (`tables.audit_table`)

Fluxo por região de tabela: `find_tables` → `build_table` → **auditor**; se o auditor acusa
algo, `reconstruct_table(page, bbox)` refaz a tabela pelas coordenadas x/y das palavras; a
reconstrução **entra só se não tiver sinal fatal** (célula fundida, cabeçalho caído, linha
engolida como cabeçalho) e (a original tinha sinal fatal, ou a reconstrução tem menos
sinais). Senão a original fica, com os sinais em `table_data.notes` e um `warning` na
ingestão. Regiões verticalmente adjacentes e alinhadas (cabeçalho numa caixa, corpo na
outra — p.162–165) são fundidas antes.

Reconstrução (nada de texto, só geometria):

1. linhas = palavras agrupadas pela coordenada vertical (tolerância 0,45 × altura mediana);
2. linhas de dados = maioria de tokens numéricos, com a assinatura (quantidade de números)
   da moda; linhas numéricas iniciais com assinatura diferente e só inteiros, ou seguidas
   de linha de texto, são cabeçalho ("4 5 6 … 25"; "80 90 100 …");
3. colunas = centros horizontais recorrentes: número em ≥ 50 % das linhas, ou o mesmo tipo
   de token curto de texto em ≥ 80 % ("UG"); o resto vai para a coluna de rótulo;
4. cada palavra vai para a coluna de centro mais próximo (≤ meio passo entre colunas);
   duas palavras na mesma célula → célula **nula** + warning — nunca se fabrica valor;
5. cabeçalho = zona acima da primeira linha de dados (+ até 1,8 linha acima da caixa, para
   o rótulo de grupo que o detector corta); corrida de palavras que cobre 2+ colunas com
   menos palavras que colunas, ou que tem uma régua-caixa logo abaixo cobrindo 2+ colunas e
   acima de mais uma linha de cabeçalho, é **grupo** ("LITROS POR HECTARE (ESPAÇAMENTO
   50CM)"); a caixa diz até onde o grupo vale; palavras isoladas empilham por coluna
   ("12" + "km/h" → "12 km/h"); texto rotacionado é remontado pela matriz do caractere
   ("GOTAS");
6. coluna de rótulo (código/série/malha): palavras fora das linhas de dados, agrupadas por
   sobreposição horizontal; **as réguas horizontais que cruzam essa coluna delimitam os
   grupos** — o rótulo vale para todas as linhas de dados dentro do mesmo intervalo (é assim
   que "MJ981CAP MUG-CV 02 MALHA 50" chega às 6 linhas de pressão). Sem régua, só a linha
   mais próxima recebe o rótulo (warning).

Chaves: grupo com unidade por extenso ("litros por hectare" → `L/ha`; "litros por minuto" →
`L/min`) gera `L_ha@12` (label "12 km/h", `units["L_ha@12"] = "L/ha"`, `groups[i]` = texto do
grupo); sem grupo, `_header_key(label)` como antes. `table_data` ganha `groups` (lista
paralela a `headers`; `[]` quando não há grupo). `render_text()` põe a linha de grupo antes
do cabeçalho.

Auditor (`audit_table`): célula com dois ou mais números; linha sem número com unidade
escrita (cabeçalho caído); cabeçalhos numéricos (linha de dados engolida); maioria de
colunas `col_N`; largura inconsistente; coluna identificadora com valor só em algumas linhas
(rótulo não propagado). Os três primeiros são **fatais** (`fatal_issues`). O plano registra
`tables_reconstructed` e `table_audit_issues` em `metrics`.

Resultado no V41: **55 tabelas de vazão (com coluna L/min), 55 reconstruídas, 55 com colunas
`L_ha@<km/h>` individuais, 0 células fundidas, 0 cabeçalho caído** (270 tabelas no total, 62
reconstruídas; 8 células fundidas restantes em 8 tabelas de acessórios — p.93, 94, 96, 97,
102 e 3 na p.110 —, mantidas originais e marcadas). Página 20, linha MJ981CAP a 40 psi:

```
CODIGO_PONTAS = "MJ981CAP MUG-CV 02 MALHA 50"  GOTAS = UG  BAR = 2.76  PSI = 40  kPa = 276  L/min = 0.77
L_ha@4 230  @5 184  @6 153  @7 131  @8 115  @9 102  @10 92  @12 77  @14 66  @16 58  @18 51  @20 46  @25 37
```

### 2.3 Títulos (`chunking.py`)

- pilha **zerada a cada página** (catálogo: cada página é uma unidade; atravessar página seria
  adivinhação);
- títulos consecutivos formam uma **corrida** e entram inteiros na pilha: a primeira corrida
  da página é o título da página (nível 1, até 10 linhas) e vira um chunk `kind = heading`
  próprio; as corridas seguintes são a seção vigente (nível 2, até 4), substituída pela
  próxima;
- candidato com mais da metade dos tokens de uma letra ("Õ E S", "O S C U") não é título;
- texto rotacionado sai do corpo na extração (`page.filter(upright)`) e vai para
  `layout.rotated_text` legível (`["SOLUÇÕES", "GOTAS"]`) — é o que elimina "Õ E S" e
  "OCINÔC" na origem.

Resultado: 0 chunks com "Õ E S"; p.20 tem `heading_path = [APLICAÇÕES DE HERBICIDAS
SISTÊMICOS, EM PRÉ E PÓS-EMERGÊNCIA, MAGNO ULTRA GROSSA, CONE VAZIO, CLASSIFICAÇÃO DE
GOTAS, …]` em todos os chunks e um chunk `heading` com o título; 168 chunks `heading` no
catálogo.

### 2.4 Códigos (`codes.py`)

Padrões genéricos: letras+dígitos com sufixo e `/n[letra]` (`MJ059/1`); série com espaço
(`MUG-CV 02`, `MAG CH 0.5`); 7–9 dígitos. **Perfil de documento** `magnojet_catalog`
(escolhido pela fonte: `PROFILE_BY_SOURCE = {"magnojet": …}` ou `--profile`): "M 714",
"M 691/1A" — só a letra M, para "A 100 metros" não virar código. Pontuação ao redor não
entra ("MJ983CAP?" → `MJ983CAP`). Forma original fica no conteúdo; `codes` recebe a
normalizada (igual a `brain.normalize_code`). Tabelas sem código: 196 → 61 de 270 (as que
restam são de dimensões/roscas sem código de peça).

### 2.5 `price_table`, fragmentos, versão

- `price_table` só com evidência real: unidade BRL, `R$`, ou cabeçalho cuja PALAVRA INTEIRA é
  preço/valor/à vista/faturado (word boundary). "valoriza" deixou de contar. Catálogo: 0.
- fragmentos curtos (cotas, rótulos de desenho) se acumulam até `MIN_MERGE` (200) antes de
  virar chunk, mesmo atravessando títulos; nada é descartado. Microchunks < 40 caracteres:
  499 → 45 (os 45 restantes são, no máximo, um por página: o texto curto que sobra no fim da
  página depois da agregação). Chunks: 1 272 → 778
  (337 text, 270 table, 168 heading, 3 list).
- `PIPELINE_VERSION = "lote-b.2"`; `chunk_config` registra `headings = page-reset+runs` e
  `fragments = aggregate<min_merge`. Determinismo: dois planos do mesmo arquivo dão chunks
  idênticos (W12); o T2 gerado a partir do plano e o worker CLI produziram fingerprint
  idêntico de páginas/chunks no piloto (transporte).

## 3. O que mudou (busca, migration `20260912040000`)

Mesma assinatura, mesmo tipo `knowledge_hit`, mesmo RRF (k = 60), sem vetor; a migration
`20260912020000` não é editada. Duas funções novas, `brain.query_codes(text)` e
`brain.query_terms(text)` (invoker, `search_path` vazio, `anon` sem EXECUTE).

| Braço | Antes (Lote A) | Agora |
|---|---|---|
| código | tokens por espaço → `normalize_code` → `codes && …`; "mj983cap?" não batia | `query_codes`: os padrões de `codes.py` em SQL; pontuação não destrói; rótulo de versão visível ("V41") não é código |
| **code intent guard** | não existia; código inexistente caía no trigram de prosa | pergunta com código → só chunks com código **exato** ou **fuzzy código × código** (`similarity ≥ 0,6`: "MJ981CA" acha MJ981CAP; MJ999CAP × MJ981CAP = 0,38 e irmãos 983 × 981 = 0,50 ficam fora) seguem; nenhum compatível → **zero**. Trigram/FTS só desempatam entre os que passaram |
| trigram | `word_similarity(pergunta inteira, content_norm) ≥ 0,35` — trigramas de "qual a", " de " somavam | sobre as **palavras de conteúdo** (sem stopwords: "faixa operacao sensor pressao"); limiar 0,35 mantido via `set_config` (RAG-H11 continua provando) |
| FTS | `websearch_to_tsquery` (todos os termos) | dois níveis no mesmo braço: estrito acima; abaixo, **cobertura de lexemas** — fração dos lexemas de conteúdo presentes no chunk ∪ título do documento ∪ nome da fonte; entra com cobertura ≥ 1/2 e ≥ 2 lexemas. Números de 1–2 dígitos não contam; palavra com hífen conta uma vez ("ad-ia" não vira 3 termos) |
| evidência mínima | qualquer rank em qualquer braço | código batido, ou FTS estrito, ou cobertura ≥ 1/2 (≥ 2 termos), ou trigram ≥ 0,35 sobre palavras de conteúdo. Uma palavra-chave sozinha ("pressão") acha por FTS estrito; "prensa operacion sensorial" → zero |

Limiar de cobertura 1/2 e fuzzy 0,6 foram escolhidos por prova, não por olhar o PDF: suíte 36
(sintético) + golden real; 0,5 de fuzzy deixaria irmãos de série (MJ983CAP ↔ MJ981CAP)
casarem; 0,7 recusaria uma letra faltando no fim. Limitação assumida: código curto com
letra faltando no meio ("KW7710" → KWZ7710 = 0,50) dá zero — melhor zero que o dado de
outra peça.

`08-remover-lote-b-sem-dados.sql` desfaz também a 040000 (funções auxiliares saem;
`search_knowledge` volta ao corpo do Lote A byte a byte, md5 `3b54175b…`, conferido); `06`
idem. RAG-H11 espera o md5 da 040000 (`334adb12…`) quando `brain.query_codes` existe e o do
Lote A quando não.

## 4. Golden real V2 (catálogo V41 completo em banco local, lote-b.2 + 040000)

Chamador `postgres` (nível admin); a versão foi ativada **só no banco local**. Chunk ids são
do banco local; `ord` é o ordinal determinístico.

| # | Pergunta | Esperado | Obtido | chunk / ord | pág. | score (braços) | Resultado |
|---|---|---|---|---|---|---|---|
| 1 | cone vazio ultra grossa ≈ 0,8 L/min | MJ981CAP 0,77 / MJ982CAP 0,83, p.20 | heading p.20 (MAGNO ULTRA GROSSA CONE VAZIO) + tabela p.20 (0,77 e 0,83 L/min) | 68/67, 72/71 | 20 | 0,0303 (trgm 1, fts 12); 0,0164 (fts 1) | **PASS** (cobertura) |
| 2 | MJ981CAP 40 psi → L/ha a 12 km/h | 77 | tabela p.20; `L_ha@12 = 77` (number) | 72/71 | 20 | 0,0495 (exato 1, fts 1) | **PASS** (retrieval + quantitativo) |
| 3 | código 4626215 Arag | sem evidência | zero | — | — | — | PASS (guard) |
| 4 | bateria T55/T70P | sem evidência | zero | — | — | — | PASS |
| 5 | catálogo da MJ983CAP | V41 p.20 | tabela p.20 (códigos MJ980…985CAP) | 72/71 | 20 | 0,0495 (exato 1, fts 1) | **PASS** (código em frase) |
| 6 | versão tabela DJI | sem evidência | zero | — | — | — | PASS |
| 7 | preço T100 V14.11→V16.2 | sem evidência | zero | — | — | — | PASS |
| 8 | preço T25P | sem evidência | zero | — | — | — | PASS |
| 9 | comparação kits T55 | sem evidência | zero | — | — | — | PASS |
| 10 | sensor Arag 466113200 | sem evidência | **zero** (antes: falso positivo p.150) | — | — | — | PASS (guard) |
| 11 | calibrar Fighter AD-IA | sem evidência | **zero** (o catálogo tem pontas "AD-IA"; com o hífen contando uma vez a cobertura fica 1/3) | — | — | — | PASS |
| 12 | vazão MJ999CAP | nenhum número | **zero** (antes: 2 falsos positivos) | — | — | — | PASS (guard) |
| 13 | manual Kuhn | sem evidência | zero | — | — | — | PASS |
| 14 | margem T100 (planilha admin) | vendedor: nada | zero (planilha não ingerida) | — | — | — | PASS (trivial) |

Provas A–K:

| Gate | Consulta | Resultado |
|---|---|---|
| A código exato | `MJ981CAP` | tabela p.20, ex/tg/fts 1/1/1 — **PASS** |
| B código em frase | `qual catálogo sustenta a MJ983CAP?` | tabela p.20, exato 1 — **PASS** |
| C heading | `MAGNO ULTRA GROSSA CONE VAZIO` | chunk `heading` da p.20 em 1º (p.22 e p.18 atrás) — **PASS** |
| D pressão | `MJ981CAP 40 psi 2,76 bar` | tabela p.20, 1/1/1 — **PASS** |
| E vazão | `MJ981CAP 0,77 L/min` | tabela p.20, 1/1/1 — **PASS** |
| F taxa | `MJ981CAP 40 psi L/ha a 12 km/h` | tabela p.20; `headers[13] = L_ha@12`, valor **77**, `jsonb_typeof = number` — **PASS** |
| G inexistente | `MJ999CAP` | zero — **PASS** |
| H externo | `466113200` | zero — **PASS** |
| I não ingeridos | `bateria DB1580 do T55`, `semeadora Kuhn`, Q3/4/6–9/11/13 | zero — **PASS** |
| J proveniência | chunk 72 | chunk → p.20 (sha do texto) → ingestão lote-b.2 → V41 → `magnojet-catalogo` → fonte `magnojet` → arquivo/sha `78af9b13…`; citação "Magnojet — Catálogo Magnojet V41, p. 20" — **PASS** |
| K segurança | `public.brain_search` | admin ativo 1 hit; vendedor ativo 1 hit (documento public) e zero para MJ999CAP; inativo zero e sem trilha; anon `insufficient_privilege`; trilha do vendedor registrada — **PASS** |

Provas extras: nome/tipo `ponta cone vazio ultra grossa MUG-CV` → heading + tabela p.20
(antes zero); `cone vazio ultra grossa aproximadamente 0,8 L/min` → p.20 (antes zero);
fuzzy `MJ981CA` → tabela p.20; `filtro de sucção M 714 malha 50` → p.101/100/109 (antes
p.102/6/7, sem código).

## 4b. Hardening final: tabela degradada nunca é evidência

Auditoria do código publicado (`1c6cdde`) apontou o que faltava: quando a reconstrução não
resolvia um sinal fatal, a tabela original continuava no pipeline só com os sinais em
`notes`, e a busca não sabia que ela era ruim — as 8 células fundidas residuais podiam
virar "evidência técnica". Correção (commit normal sobre a migration 040000, que **ainda não
tinha sido aplicada em produção**; por isso não há 050000):

- **Estado formal** em `table_data.audit = {"quality": "trusted" | "degraded", "fatal": bool,
  "issues": [...]}`, calculado por `TechnicalTable.stamp_audit()` (auditor, não string de
  `notes`) para PDF, XLSX e CSV. `degraded` = sobrou sinal fatal (número fundido, cabeçalho
  caído, linha engolida) depois da reconstrução; sinal não fatal (coluna sem nome, rótulo não
  propagado) fica em `issues` e a tabela continua `trusted`. Métricas `tables_trusted`,
  `tables_degraded`, `degraded_pages` no plano/ingestão.
- **Nada inventado, nada descartado**: a tabela degradada segue gravada como chunk `table`
  com a representação original ("4181 3907" continua string), página, códigos e sinais;
  `brain.chunk_provenance(id)` continua funcionando para diagnóstico.
- **Busca fail-closed**: em `brain.search_knowledge`, a CTE `visiveis` aplica acesso, vigência
  e filtros; `candidatos` = `visiveis` sem `degradada` (`audit.quality = 'degraded'` ou
  `audit.fatal = true`, só para `table`/`price_table`) — **antes do ranking**; nenhum filtro
  (`version_id`, `source_key`, `kind`, `p_limit`, `superseded`) reabre. Tabela sem `audit`
  (conteúdo anterior ao lote-b.2) conta como trusted: o estado é declarado pelo worker.
  E o fuzzy de código só vale para código que **não existe exato em nada visível**: se o
  código da pergunta existe só numa tabela degradada, a resposta é zero — não o dado de um
  código parecido (na V41 real: `M506/10` existe só em tabela degradada da p.102 e devolvia
  `M506/1`; agora zero).
- Tabelas herdam a seção da página só quando a página tem uma única seção; com várias, só
  o título da página (atribuir a última seção a todas seria adivinhar) — W16.

V41 real com o hardening: **270 tabelas → 202 trusted, 68 degraded**; as **55 tabelas de
vazão são trusted** e a **p.20 é trusted** (`{"quality": "trusted", "fatal": false,
"issues": []}`). Páginas com tabela degradada: 10–15 (matrizes de propriedades: cabeçalho
caído), 57, 90, 152, 153 (linha engolida como cabeçalho), 93, 94, 96, 97, 102, 110 (célula
fundida), 158–161 (45 grades de recomendação de pressão: cabeçalho caído + colunas sem
nome). Varredura: para cada um dos 105 códigos das tabelas degradadas, a busca pelo próprio
código **nunca** devolve a tabela degradada (0 vazamentos); o texto confiável das mesmas
páginas continua sendo achado (p.102: "filtro de linha M 506" → texto da p.102).

Testes: W13 (fixture adversarial `make_degraded_pdf`: célula "4181 3907 3200 …" fundida,
reconstrução recusada, `degraded/fatal`, string intacta, chunk rastreável), W14 (p.20-like
`trusted`, `L_ha@12 = 77`), W15 (sinal não fatal não degrada; fundido degrada), W16
(tabela × seção); suíte 36 C11 (zero por código, frase, número, `version_id`, `source_key`,
`kind`, limite 100, `superseded`; fuzzy não resgata `PSDEG99` exato-degradado e ainda acha
`PSDEG9 → PSDEG98`; texto da página segue; `chunk_provenance` do degradado funciona) e C12
(warning não fatal → trusted e pesquisável). `codes.py`/`query_codes`: unidade seguida de
série ("PSI DDC 01") deixou de virar código.

## 5. Testes e regressão

| Onde | O quê | Qtde |
|---|---|---|
| `brain/worker/tests/test_worker.py` | W1–W6 (anteriores) + W7 tabela por geometria com fixture `make_flow_pdf` (cabeçalho de dois níveis, sem régua vertical entre velocidades, régua de grupo na coluna de código, título vertical, títulos consecutivos, rótulos de desenho, "valoriza"), W7b auditor, W8 títulos, W9 códigos, W10 `price_table`, W11 fragmentos, W12 `lote-b.2` determinístico, W13–W16 trusted/degraded e tabela × seção | 22 |
| `brain/worker/tests/test_pipeline_db.py` | D1–D9 (pipeline_version `lote-b.2`) | 9 |
| `supabase/db-tests/36_brain_busca_calibracao.sql` | C1–C10 (item 3) + C11/C12 (item 4b) | 12 |
| `supabase/db-tests/34_brain_memoria_hardening.sql` | RAG-H11 adaptado (md5 condicional; controle do limiar com palavra "glyfox" 0,40) | = |
| `supabase/db-tests/ensaiar-ingestao.sh` | I1 (35+36 = 42), I3 (31 pytest), I4 (06 remove A+B+calibração; reaplicação 71), I7 (08 devolve o retrato do Lote A com a 040000 aplicada), I8 | 8 |
| `run.mjs` | suíte 36 na bateria | +12 |

Rodado em PG16 (16.13), PG17.6 e PG18.6: `ensaiar-memoria` 6/6 e `ensaiar-ingestao` 8/8 nos
três; bateria completa 457 OK, 5 `FALHA` herdadas (BR4/5/6/9/16, suíte 25) mantidas na
comparação de baseline, 0 ERROR; `conferir-operacao`, `ensaiar-deploy` 17/17,
`ensaiar-reconciliacao` 10/10, `pontes-concorrentes` verdes; `tsc` limpo; tipos gerados sem
diff (nada novo em `public`). O PDF Magnojet não está no Git (I5).

## 6. Transporte para a ingestão produtiva (não resolvido nesta rodada, por decisão)

O worker fala psycopg (TCP). Deste ambiente o banco não é alcançável (host direto só IPv6;
pooler bloqueado; só HTTPS sai) e a T2 do catálogo tem 1,7 MB — inviável pelo MCP e
incompatível com "uma única transação" se fatiada. Opções, para o ChatGPT decidir:

- **A. worker no PC do Wilson** (`BRAIN_DB_URL` com credencial de serviço, `python -m
  brain_worker ingest … --document magnojet-catalogo --label V41`, perfil automático pela
  fonte): caminho oficial, uma transação, `register_version` idempotente reaproveita a V41
  já registrada. Custo: Python 3.11 + `requirements.txt` no PC; a credencial é dele.
- **B. transporte HTTPS seguro**: um "envelope" assinado (plano `lote-b.2` como JSON) enviado
  por HTTPS a uma Edge Function ou RPC de serviço que reexecuta as chamadas da API numa
  transação. Exige código novo em produção (não feito) e revisão de segurança.
- **C. executor agendado**: `pg_cron` + `pg_net` não instalados; exigiria extensão nova. Não
  recomendado agora.

Recomendação: **A** — é o fluxo já auditado (T1/T2/T3), sem código novo em produção.

## 7. Riscos residuais

- 68 tabelas degradadas (item 4b) ficam fora da busca por desenho — recomendação de pressão
  (p.158–161), matrizes de propriedades (p.10–15), roscas/dimensões com célula fundida
  (p.93, 94, 96, 97, 102, 110) e linha engolida (p.90, 97, 152, 153) — até que uma
  reconstrução própria para esses layouts exista; o texto dessas páginas continua
  pesquisável. Pseudo-códigos gerados dentro delas ("MUGPSI30") só existem em chunks
  degradados e não alcançam a busca.
- p.48 (MJC): reconstrução aceita com 1 aviso (coluna de rótulo fragmentada); valores
  numéricos corretos.
- Fuzzy de código não cobre letra faltando no meio de código curto (0,50 < 0,6) — zero por
  desenho.
- A cobertura usa título do documento e nome da fonte: "Magnojet" na pergunta conta para
  qualquer chunk do catálogo (intencional; documentado).
- Versão ativa em produção continua inexistente; nada do golden foi executado lá.
