# AGROTORK BRAIN — Fase 2: estado consolidado (16/09/2026)

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14).

Retrato verificado no repositório e em produção (só leitura) enquanto o lote
DJI espera a ALLCOMP. **Nenhuma escrita em produção nesta rodada.**

## 1. Onde cada peça está

| Item | Produção | Técnico | Governança | Próximo passo |
| --- | --- | --- | --- | --- |
| **A. Magnojet V41** | ativo (172 p., 778 trechos, 270 tabelas, 68 degradadas) | golden 14/14 + provas 12/12 | ok | reingerir quando houver bucket — o worker atual degrada menos (56 vs 68) |
| **B. ARAG** | ativo (1 p., 2 trechos, 2 tabelas confiáveis) | golden 7/7 + adversariais 14/14 | ok — fonte interna, marca ARAG relacionada | nenhum |
| **C. DJI Subdealer** | **ausente** | golden 9/9 + 16/16 + final 10/10 | **PENDENTE ALLCOMP** | resposta da ALLCOMP → cenário A ou B |
| **D. Fighter / técnicos** | ausente | **não maduro** — ver §2 | decisão de dado de cliente | não ingerir; decidir escopo |
| **E. KUHN** | ausente | — | — | lacuna de fonte confirmada: não existe arquivo |
| **F. Compusystem** | sem integração | — | **bloqueado por documentação externa** | aguardar resposta ao contrato |
| **G. Lote C / pgvector** | extensão **não instalada** | nada preparado | — | sem necessidade prática hoje — §5 |
| **H. Storage `brain-documents`** | bucket **não criado** | roteiro 07 pronto; 4 policies aplicadas | depende do plano Supabase | decidir plano — §4 |
| **I. Golden datasets** | — | v0 preservado; **v1 criado** | ok | atualizar v1 quando o DJI entrar |
| **J. Worker / ingestão** | pipeline `lote-b.2` | 46/46 pytest | ok | `--pages` especificado, **não implementado** — §6 |
| **K. Docs / rollback** | — | 10 roteiros em `supabase/operacao/` | ok | nenhum |

Produção, medido: migration `20260915120000` (68 no ledger) · fontes
`agrotork_interno` e `magnojet` · `allcomp` **ausente** · 2 documentos, 2
versões ativas · 173 páginas, 780 trechos, 2 ingestões · pontes **0/3** ·
divergências **0** · crons `expirar-orcamentos` (03:05) e `brain-reconciliar`
(a cada minuto), **os dois ativos** · 112 produtos no ERP, 38 deles JR ·
`pgvector` **não instalado** · bucket `brain-documents` **não criado**.

## 2. O próximo documento não é o Fighter

O `FIGHTER AD-IA.pdf` parecia o candidato natural. Auditado, não é — e o
motivo importa mais que a conclusão.

| | |
| --- | --- |
| sha256 | `f2fd522cbf3db492319e57078b1d0bb56b9cde5cce20a9bd954d2071374dfe66` |
| páginas | 17, camada textual completa, 42 "tabelas" detectadas |
| origem | `sprayflow.sprayx.com.br/show_report/18462`, impresso do Chrome em 26/10/2024 |
| título interno | **"Report Test"** |

O conteúdo é um **relatório de serviço**: "Calibração de Pulverizador",
cliente **MARCHIONI 3**, equipamento MARCHIONI FIGHTER de 9 seções e 61
pontas, ponta AD-IA 03 M042/1, medido em 25/10/2024, com 19,67% das pontas
entupidas. Três problemas, em ordem de gravidade:

1. **Não é conhecimento de referência.** A memória corporativa responde "o que
   é esta peça, quanto custa, qual a vazão". Este documento responde "como
   estava o pulverizador do Marchioni num dia de outubro de 2024". Ingerido,
   ele viraria evidência citável para perguntas gerais — exatamente o tipo de
   resposta errada que o fail-closed das tabelas degradadas existe para evitar.
2. **Tem dado de cliente identificado.** Nome do cliente, equipamento e estado
   de conservação. Colocar isso num acervo pesquisável em nível `commercial` é
   decisão de governança de dado de terceiro, não escolha técnica.
3. **A extração não serve para a substância.** As 42 tabelas são em boa parte
   andaime de gráfico; os rótulos de eixo saem espelhados (`]nim/L[`,
   `oãzaV`). O que tem valor no documento são as curvas, que não viram texto.

Isso também corrige a **pergunta 11 do golden v0** ("Como calibrar o Fighter
AD-IA?"): o v0 assumia que este arquivo era um procedimento. Não é. A pergunta
continua legítima, mas **a fonte dela não existe** — é uma lacuna como a KUHN,
não um documento à espera de ingestão.

### O candidato de verdade: tabela JR Soluções

| | |
| --- | --- |
| arquivo | `Downloads/04 - Tabelas de Preco e Marketing/TABELA REV JAN261.pdf` |
| sha256 | `434c15a9ec1ea2c7ef4eac5746fea808…` |
| páginas / bytes | 1 / 232.716 |
| origem | Microsoft Excel 2021, criado 04/02/2026 |
| cabeçalho | `CÓDIGO · NCM · PRODUTO · REVENDAS · SUGERIDO` |

Por que ele é o mais maduro:

- **Declara a própria vigência no texto**: "Tabela de preços atualização
  Janeiro 26 - JR Soluções". É exatamente o que falta nas tabelas DJI e o que
  torna o gate da ALLCOMP necessário — aqui não há esse gate.
- **O emissor é o fabricante.** "INDÚSTRIA E COMÉRCIO DE PEÇAS ROTOMOLDADAS —
  JR Soluções" assina a própria tabela. A fonte é `manufacturer`, sem a
  ambiguidade distribuidor-versus-fabricante do lote DJI.
- **Já tem contraparte no ERP**: 38 produtos JR em produção, carregados com
  `source_catalog = 'TABELA REV JR'`, `source_version = 'JAN/26'`. A ingestão
  fecha o laço entre o preço no ERP e o documento que o sustenta.
- **Pequeno e limpo**: 1 página, camada textual, uma tabela.

Riscos conhecidos, para não serem surpresa: a coluna `REVENDAS` **não declara
condição de pagamento** (a carga do ERP já registra isso em nota); e a
armadilha do `slugify` com "JR SOLUÇÕES" está documentada no `CLAUDE.md`.
Precisa de fonte nova (`jr_solucoes`), **não** precisa de schema novo.

Segundo na fila: `Catálogo de Produtos JR Soluções.pdf` (2 p., textual), que
descreve os mesmos produtos. Terceiro: `baldan-folheto-racr.pdf` (2 p., 5
tabelas, textual).

**Achado lateral:** `Lista de Preço Agosto-2025.pdf` é de **ADS Drone
Solutions** — um segundo distribuidor DJI, com "Custo Subdealer" e vigência
declarada no texto ("01/08/2025 a 31/08/2025"). É histórico (expirou), mas
mostra que existe outro emissor de tabela subdealer além da ALLCOMP. Vale
saber antes de modelar a fonte do DJI como se a ALLCOMP fosse a única.

## 3. Golden dataset

`golden-dataset-v0.json` fica **intocado** — é o retrato de 11/09/2026,
quando nada estava ingerido. `git diff` sobre ele está vazio.

`golden-dataset-v1.json` (novo) mantém as 14 perguntas com a mesma redação e
acrescenta, em cada uma, `estado_produtivo` **medido em produção hoje**, não
suposto:

| classe | qtd | perguntas |
| --- | --- | --- |
| `respondida` | 5 | 1, 2, 3, 5, 10 |
| `zero_por_desenho` | 3 | 12, 13, 14 |
| `zero_por_ausencia` | 6 | 4, 6, 7, 8, 9, 11 |

O que mudou do v0 para o v1: **as perguntas 3 e 10 deixaram de ser lacuna**.
Eram "ARAG não ingerida"; hoje são respondidas pela fonte `agrotork_interno`
(1 e 2 evidências). Nenhuma expectativa histórica foi reescrita.

A distinção que o v1 introduz vale por si: `zero_por_desenho` tem de
**continuar** zero (12 é código inexistente, 13 é lacuna real, 14 é teste de
acesso); `zero_por_ausencia` vira `respondida` quando o documento entrar — e
enquanto não entra, **o zero é o próprio teste**, porque pega ingestão
acidental.

## 4. Storage — o bucket `brain-documents`

1. **É bloqueio operacional hoje?** Não.
2. **O que se perde sem ele:** o arquivo original não fica guardado no
   Supabase. `storage_path` é registrado e validado (`chk_version_path_has_sha`),
   mas aponta para um objeto que não existe. Na prática: não dá para baixar o
   PDF de origem a partir do sistema, e uma reingestão depende de o arquivo
   ainda estar no computador do Wilson.
3. **O que já funciona sem ele:** tudo o que é busca e citação — texto,
   tabelas em JSONB, proveniência página a página, `sha256` do arquivo e do
   conteúdo de cada trecho. A memória não lê o bucket para responder.
4. **Modelo correto:** bucket **privado**, caminho
   `<fonte>/<slug>/<rótulo>/<sha256>.<ext>` (já é o que o worker gera), MIME
   restrito a pdf/xlsx/csv/txt/md.
5. **Policies:** as quatro já estão aplicadas pela migration `20260912030000`
   (`brain_documents_read/write/update/delete`). O roteiro `07` recusa criar o
   bucket se elas não estiverem lá.
6. **Risco de criar agora, antes do Lote C:** nenhum de arquitetura. O risco é
   de **plano**: no Free, cada upload é limitado a 50 MB e o Catálogo Magnojet
   V41 tem 177 MB — ele não sobe. Criar o bucket agora e subir só o que cabe
   deixaria o acervo pela metade, que é pior que vazio porque parece completo.
7. **Recomendação:** resolver **depois**, e a decisão é do Wilson e é de
   plano, não técnica. Ordem: decidir Free/Pro → ajustar `v_limite` no roteiro
   07 → criar o bucket → subir os arquivos → reingerir o Magnojet com o worker
   atual (que degrada 56 tabelas em vez de 68).

## 5. Lote C / pgvector

- `pgvector` **não instalado** em produção (conferido: `pg_extension` não tem
  `vector`).
- O schema **não** tem coluna vetorial, tabela de embeddings nem rótulo
  "embed*" — e a suíte `ensaiar-memoria` (M6) trava exatamente isso.
- **Não há migration preparada.** Nada em `supabase/migrations/` cria a
  extensão.
- **Gate real:** duas decisões, nenhuma técnica. (i) confidencialidade — pode
  um documento `commercial` ser enviado a um provedor externo de embedding? O
  modelo de `external_processing` já existe e hoje diz `forbidden` para as
  três fontes; (ii) custo e escolha de modelo.
- **Necessidade prática imediata: não.** O RRF de três braços responde 5 de 5
  perguntas respondíveis do golden, e as que faltam faltam por **ausência de
  documento**, não por falha de recall. Nenhuma pergunta do golden hoje falha
  por falta de busca semântica.
- **Quando faria sentido:** quando houver pergunta em linguagem natural que o
  FTS + trigram erram com corpo já ingerido — e isso se mede, não se supõe. O
  desenho já reserva o lugar: o braço vetorial entra como **quarta parcela**
  do mesmo RRF, sem mudar a fórmula.

## 6. Worker `--pages` — especificado, não implementado

O lote DJI revelou o buraco: `brain_worker ingest` não seleciona páginas, e a
V15.1 tem 4 páginas das quais só a 1 é DJI.

**Especificação:**

```
--pages 1          --pages 1,3        --pages 2-4        --pages 1,3-5
```

- **CLI:** argumento opcional em `ingest` (e, por simetria, em `plan`). Ausente
  = todas as páginas — compatível com tudo que existe.
- **Parser:** string → `set[int]`; aceita número, lista por vírgula, intervalo
  com hífen, e combinação. Rejeita: página 0 ou negativa, intervalo invertido,
  página acima do total do arquivo, conjunto vazio.
- **Onde entra:** depois de `plan()`, filtrando `ext.pages` e `chunks`.
- **Chunk que atravessa páginas:** entra **só se estiver inteiro** dentro da
  seleção (`page_from` e `page_to` ambos selecionados). Um chunk que cite uma
  página não registrada seria recusado pelo banco de qualquer forma
  (`ingestion_add_chunk` exige página existente na versão).
- **Numeração:** preservada. Selecionar 2–4 grava as páginas **2, 3 e 4**, não
  1, 2 e 3. A citação continua dizendo a verdade sobre o PDF.
- **Métricas:** `tables_trusted`, `tables_degraded`, `degraded_pages` e
  `table_audit_issues` recalculados **só sobre as páginas escolhidas**.
- **`status`:** `completed` se todas as páginas **selecionadas** têm texto.
- **PDF × XLSX:** em planilha, "página" é aba. Mesma sintaxe, semântica
  diferente — precisa estar escrito na ajuda do CLI.
- **OCR:** `--ocr auto` decide pela proporção de texto; com subconjunto, a
  proporção deve ser a do subconjunto.

**Decisão em aberto que impede implementar agora** — e é a razão de isto ficar
como especificação: `document_versions.page_count` significa "páginas do
arquivo" ou "páginas ingeridas"? Hoje recebe o total do arquivo. Se `--pages`
passar a gravar o subconjunto, a versão perde a informação de que o arquivo
tem 4 páginas; se mantiver o total, `ingestion.pages_total` (que é o que
`ingestion_finish` confere) tem de receber o subconjunto — dois campos com
sentidos diferentes, hoje sempre iguais. **É decisão de modelagem, não de
código, e muda como a proveniência é lida.** Embutir uma escolha dessas de
lado, numa rodada de auditoria, seria o tipo de decisão silenciosa que este
projeto evita.

**Testes que a implementação precisa** (nenhum existe): página única; lista;
intervalo; misto; fora do intervalo recusado; chunk atravessando páginas;
numeração original preservada; `pages_total` versus `page_count`;
`completed` × `partial`; xlsx por aba; ausência do argumento = comportamento
de hoje, byte a byte.

**Enquanto isso**, a saída é a que já funciona e está provada duas vezes (ARAG
e ensaio DJI): documento de passagem + cópia pelas mesmas funções
`brain.ingestion_*`.

## 7. Suíte 25 — as cinco falhas herdadas

Investigadas com três bancos descartáveis. **Todas as cinco são (a)
comportamento esperado no modo desacoplado** — testes escritos para a premissa
da ponte síncrona. Provado das duas pontas: com os três gatilhos `trg_brain_*`
ligados a suíte fica **18/18**; e `brain.reconciliar_erp()` restaura a
substância de cada uma.

| | o que afirma | causa raiz | classe |
| --- | --- | --- | --- |
| **BR4** | orçamento publica 3 eventos e promove a oportunidade a `negotiation` | `trg_brain_quotes` desligado; a suíte muda `draft→sent→approved` na mesma transação | (a) |
| **BR5** | pedido marca oportunidade `won`, lead `converted`, evento com total | `trg_brain_orders_created` desligado; `opportunities.order_id` fica nulo | (a) |
| **BR6** | jornada com ≥ 8 entradas terminando em `order` | a view liga o pedido ao lead só por `opportunities.order_id` | (a) |
| **BR9** | seis verbos na auditoria | `lead.converted` e `opportunity.won` nascem de transições que não acontecem | (a) |
| **BR16** | pedido cancelado devolve a oportunidade a `negotiation` | herda o `order_id` nulo de BR5 | (a) |

Pós-reconciliação, BR5, BR9 e BR16 passam literalmente; BR4 e BR6 passam
quando a reconciliação roda **entre** as transições — que é o comportamento
real do cron de 1 minuto, confirmado ativo em produção nesta rodada.

**Nenhuma esconde risco real para produção.** Três observações de higiene:

1. **BR16 é um teste quebrado, não só desatualizado.** Com `order_id` nulo, o
   `update public.orders set status='cancelled' where id = null` afeta zero
   linhas: o teste nem chega a cancelar o pedido. Dá impressão de exercitar um
   caminho que não exercita.
2. **Um ponto cego que não é latência:** `brain.journey_entries` liga o pedido
   ao lead só por `opportunities.order_id`, e `reconciliar_erp()` pula
   oportunidades em `stage='lost'`. Um pedido nascido de orçamento cuja
   oportunidade foi dada como perdida **nunca** entra na jornada daquele lead.
   É coerente com a regra de negócio, mas não está escrito em lugar nenhum.
3. **Forma:** vale tornar as cinco condicionais a `brain.estado_das_pontes()`,
   que já existe. Cinco FALHAs permanentes no relatório são ruído que, com o
   tempo, esconde a sexta que for de verdade.

Nada foi corrigido nesta rodada, por desenho.

## 8. Compusystem

**BLOQUEADO POR DOCUMENTAÇÃO EXTERNA.** Nenhum documento novo do fornecedor
chegou. O que existe no repositório é o que a AGROTORK **enviou**: o contrato
de integração (pedido técnico), a matriz de testes, o congelamento dos módulos
operacionais e o modelo conceitual.

O que a Compusystem já informou, e que segue sendo tudo: não há acesso direto
ao banco; não há API genérica pronta; o backup pode ser fornecido; é possível
construir uma API **somente leitura**; a integração não grava no ERP.

**Próximo dado concreto necessário:** o Bloco A do contrato — URL base por
ambiente, forma de autenticação, limites e paginação. Sem isso, qualquer
desenho de sincronização é chute. Nada de schema, Edge Function, webhook ou
polling foi criado, e não deve ser.

## 9. Próximas três rodadas

| | RODADA 1 — agora | RODADA 2 — depende da ALLCOMP | RODADA 3 — avanço arquitetural |
| --- | --- | --- | --- |
| **Objetivo** | lote JR Soluções pronto fora de produção | ingerir o DJI em produção | decidir Storage e reingerir o Magnojet |
| **Pré-condições** | nenhuma | resposta da ALLCOMP (cenário A ou B) | decisão de plano Supabase |
| **Arquivos** | `TABELA REV JAN261.pdf`; novo `ensaiar-jr.sh`; doc do lote | os três PDFs DJI; `ensaiar-dji.sh`; roteiro de ingestão | roteiro `07`; worker |
| **Risco** | baixo — fora de produção | médio — escrita em produção, com rollback pronto | médio — custo e limite de upload |
| **Produção?** | não | **sim**, com GO | **sim**, com GO |
| **Quem** | Claude prepara · ChatGPT audita | Wilson obtém a resposta · Claude executa · ChatGPT audita | Wilson decide o plano · Claude executa |

Duas coisas fora dessa fila, porque dependem só de decisão: o `--pages` do
worker (precisa da decisão `page_count`) e o Lote C (precisa da decisão de
confidencialidade). Nenhuma das duas bloqueia as três rodadas acima.
