# AGROTORK BRAIN — Registro de lacunas (25/09/2026)

> Revalidado no repositório nesta rodada, não copiado dos docs anteriores.
> Onde não deu para confirmar, está escrito "não confirmado no repo" em vez
> de afirmado. Ver `docs/brain/fase-2-answer-v1.md` (estado atual),
> `docs/brain/fase-2-consolidado.md` (16/09, retrato mais amplo da Fase 2) e
> `CLAUDE.md` para o histórico completo de cada item.

## FECHADO NESTA RODADA (26/09/2026 — hardenings residuais do Answer v1)

Os dois itens que a revisão de 25/09 deixou em HARDENING. Commit: esta
rodada (`fix(brain): fecha hardenings residuais do Answer v1`). Testes que
pinam cada um: `check-brain-synthesis.mjs` (SYN19b, SYN32a–d, SYN33) e
`check-brain-answer.mjs` (CIT1–CIT4).

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **`comparison` sumia em três caminhos de saída antecipada** | fechado | o selo passou a sair só do TEXTO da pergunta: `isComparisonQuestion(pergunta)` (`comparison.ts`) = intenção explícita + ≥ 2 códigos, o mesmo critério que `planComparison` usa para `not_applicable`. `answerWith` calcula antes de qualquer gate (não lê evidência, política nem provedor — privacidade primeiro) e `base()` o aplica a todo caminho que devolve resposta: gate externo, sem provedor, erro do provedor, teto, incompleta, rejeição e sucesso. Recusas (`no_evidence`, `model_refusal`) seguem sem o selo | `check-brain-synthesis.mjs` SYN19b (agora `true`), SYN32a–d |
| **Fallback `?? c.evidenceIndex` em `citacoesParaTela`** | fechado | o helper virou `mapCitationsToScreen` (puro, em `answer.ts`): mapeia por `chunkId`, não por identidade de objeto, e é FAIL-CLOSED — aceita fora de `evidencias` ou índice fora do intervalo devolve `null`; `answerWith` confere logo depois do Evidence Gate (antes do gate externo e do provedor) e, se `null`, registra `internal_error` (`citation_mapping`) e devolve extractiva com `citations: []` e aviso genérico. Ponta a ponta o ramo é inalcançável sem gancho de teste em produção — não foi criado; a garantia é o helper testado direto | `check-brain-answer.mjs` CIT1–CIT4; `check-brain-synthesis.mjs` SYN33/SYN33b |

## FECHADO NA RODADA ANTERIOR (25/09/2026 — revisão independente)

Quatro achados de uma auditoria independente sobre o Answer v1 fechado em
17–18/09. Nenhum era número errado; os quatro eram prova certa no lugar
errado ou regra faltando um caso — a mesma classe das rodadas anteriores.
Testes que pinam cada um: `check-brain-comparison.mjs` (ADV11-FIX-f–k,
C-DOC1/C-DOC2), `check-brain-synthesis.mjs` (SYN31a–f) e
`check-brain-answer.mjs` (INJ16–INJ23) — todos falham se o fix for revertido.

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **B1 — valor único sem dono numa comparação passava** | fechado | `checkAssociation` (`exhaustiveness.ts`) rodava o corte "menos de 2 números" ANTES da regra do item órfão; um valor SOZINHO sob cabeçalho em prosa ("Para MJ981CAP a 40 psi: - 1,53 L/min") não tinha os dois números que a regra antiga exigia e passava "sem ser conferido". A ordem inverteu: órfão primeiro. `codigosNomeaveis` passou a ser códigos da evidência ∪ códigos da PERGUNTA, então um código que só a pergunta traz (ex.: MJ999CAP) não é mais "sem dono" — tem dono, só falta linha, e quem reprova é a comparação (C11e), não mais a associação com o motivo errado | `check-brain-comparison.mjs` ADV11-FIX-f a k |
| **S1 — aviso de comparação incompleta misturava dois motivos** | fechado | "não encontrei documentação para MJ981CAP" saía mesmo com a tabela da MJ981CAP visível, só porque a pergunta fixava um ponto (45 psi) fora dela. `ProductBlock.documented` separa "sem NENHUMA linha em evidência nenhuma" de "documentado, mas sem o valor no ponto pedido", e o aviso usa a frase certa para cada um (unidas por `"; "` quando os dois coexistem). `parseListingQuestion` parou de ler `40psi`/`76bar`/`276kPa` colados como código de produto | `check-brain-synthesis.mjs` SYN31a–f; `check-brain-comparison.mjs` C-DOC1/C-DOC2 |
| **S2/S3 — isenção de postura por atribuição vazava para 1ª pessoa e para o meio da frase** | fechado | (1) 1ª pessoa/imperativo (`recomendo`, `sugiro`, `compre`…) nunca tiveram isenção de atribuição de verdade — a lista antiga misturava os dois grupos, e um caso como "Conforme a tabela, recomendo…" dependia só de a frase inteira não casar; agora `VOZ_PROPRIA` está separada de `JUIZO` e só o segundo grupo aceita isenção; (2) a atribuição só isenta quando ABRE a oração — "A MJ981CAP **da tabela** é o melhor…" tinha "da tabela" como adjunto e passava; (3) a oração agora também quebra em `;`, `:`, travessão e depois de `!`/`?`; (4) `qual/quais` isenta só até 3 palavras antes da frase; (5) "é o/a melhor" exige o "é" acentuado — sem isso, a conjunção "…e o melhor…" disparava como juízo de valor | `check-brain-answer.mjs` INJ16–INJ23 |

## BLOCKER

Impedem algo específico de acontecer agora.

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Credencial do provedor LLM em produção** (`BRAIN_LLM_PROVIDER`/`_API_KEY`/`_MODEL`) | parcial — **existe localmente** (`.env.local` do Wilson desde 20/09; smokes reais H 10/10, A/B/C/D/F no `localhost` em 25/09); **em produção/Netlify: não confirmado no repo** (por decisão, o Preview não recebe a chave) | baixo — sem ela o sistema já é fail-closed (resposta extractiva, nunca inventa); o custo é não entregar resposta redigida em produção | `fase-2-answer-v1.md` §5 e "Estado atual"; `resolveProvider()` devolve `null` sem as três variáveis; `docs/brain/ci.md` §4 (Preview sem chave) | Wilson decide provedor aprovado e orçamento e põe a chave como env **server-only** na Netlify (nunca `NEXT_PUBLIC_`); CI e Preview continuam sem ela | sim (env de produção) | **sim** | sim — Anthropic (ou outro formalmente aprovado) |
| **Bucket `brain-documents`** não criado | aberto | baixo hoje (busca e citação funcionam sem ele — texto, tabelas em JSONB e proveniência não dependem do Storage); cresce se a reingestão do Magnojet ficar amarrada a ele | migration `20260912030000` aplica as 4 policies mas não cria o bucket (`raise notice` condicional); `consolidado.md` §4; roteiro `supabase/operacao/07-criar-bucket-brain-documents.sql` pronto e não rodado | Wilson decide Free × Pro (Free limita upload a 50 MB; Magnojet V41 tem 177 MB) → ajustar `v_limite` no roteiro 07 → criar bucket → reingerir | sim | **sim** (decisão de plano/custo) | sim — Supabase (plano pago) |
| **DJI Subdealer** travado por governança | aberto (tecnicamente pronto: golden 9/9 + 16/16 + final 10/10) | baixo tecnicamente; alto se ingerido sem confirmação — rótulo de versão não vem do documento, só do nome do arquivo | `fase-2-dji-governanca.md` — nenhum dos 3 PDFs declara a própria versão no texto | obter da ALLCOMP: rótulos corretos (V14.11/V15.1/V16.2), data de vigência de cada uma, e se a V16.2 é a vigente hoje | sim, quando liberado | **sim** (obter a resposta) | sim — ALLCOMP |
| **JR Soluções** bloqueado pelo PDF | aberto | baixo (fora de produção, não afeta nada hoje) | `fase-2-jr-solucoes.md` §12 — 9 linhas perdidas porque a única ocorrência do cabeçalho real está fundida com linhas de produto sobrepostas; herança de cabeçalho foi implementada, medida e descartada (não dispara neste arquivo) | pedir PDF sem sobreposição, ou gerar de novo a partir da planilha de origem — é a única correção que recupera as linhas, o motor não pode adivinhar o conteúdo | não ainda | **sim** (obter o arquivo) | não — é arquivo interno via Wilson |
| **Integração Compusystem** | aberto | médio a médio prazo (é a fonte oficial de todo dado operacional; enquanto não integra, tudo aqui fica isolado do ERP real) — baixo agora, porque `CLAUDE.md` proíbe desenhar schema por suposição | `CLAUDE.md` regra 6; `docs/integracoes/compusystem-contrato-integracao.md`, `compusystem-matriz-testes.md`, `congelamento-modulos-operacionais.md`, `integracao-modelo-conceitual.md`; `consolidado.md` §8 — "não há acesso direto ao banco; não há API genérica pronta; possível construir API somente leitura" | aguardar o Bloco A do contrato (URL base por ambiente, autenticação, limites, paginação) — sem isso qualquer desenho é chute | não hoje | **sim** (obter o documento) | sim — Compusystem |

## HARDENING

Limites conhecidos e registrados da própria lógica de validação — não bloqueiam nada, mas valem acompanhar.

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Pertinência não verificada (ADV4-LIMIT)** | aberto, aceito por desenho | médio — numa pergunta pontual sobre a MJ981CAP, um fato verdadeiro e citado só sobre a MJ982CAP passa; os gates provam verdade e vínculo, não pertinência | commit `d2446f1` (matriz adversarial), classe registrada como limite, não fechada | nenhum planejado; se aparecer em produção, a correção é conferir que o código do sujeito da resposta é o mesmo da pergunta pontual | não | não | não |
| **Injeção qualitativa COM atribuição (INJ-LIMIT)** | fechado por desenho — não é bug | baixo — "Segundo o documento, o produto é o melhor do mercado" passa a postura, porque é o documento falando e a tela mostra a atribuição | `check-brain-answer.mjs`, seção INJ, caso `INJ-LIMIT` | nenhum — alargar a lista para pegar isto reprovaria as formas documentais legítimas (INJ9–INJ15) | não | não | não |
| **Custo aceito: imperativo documental sem atribuição vira extractivo** | fechado, custo registrado | baixo — é falso positivo (fail-closed), não fail-open: "Não deixe de limpar os bicos", mesmo sendo do manual, reprova por postura | commit `c4feff3` — "Custo aceito e registrado" | nenhum; refinamento futuro só se esse padrão aparecer com frequência real em produção | não | não | não |
| **Custo aceito: valor correto sob cabeçalho em prosa também reprova (ADV11)** | fechado, custo registrado | baixo — fail-closed: "Para MJ981CAP a 40 psi [1]:" não é cabeçalho (prosa não cria bloco), então mesmo um valor correto ali embaixo, sem código nem cabeçalho de bloco, reprova pela regra `UNIDADES_DE_VALOR` | commit `9201f9a` — "ADV11-FIX-CUSTO (a prosa com os valores CERTOS também reprova)" | nenhum planejado; alargar a gramática do cabeçalho é a alternativa, registrada e não escolhida | não | não | não |
| **Citação sem link para a página do documento** | aberto, depende do bucket | baixo/médio (usabilidade — hoje `[n]` mostra fonte/documento/versão/página como texto) | `grep -n "href\|storage" src/app/(app)/brain/brain-console.tsx` — zero ocorrências, confirmado nesta rodada | depois do bucket `brain-documents` existir, adicionar o link | sim, eventualmente | indireto (depende do item acima) | indireto (Supabase, plano) |
| **Golden dataset v1 não cobre os casos adversariais/postura de 25/09** | não confirmado no repo se precisa atualização | baixo — o golden mede recuperação e cobertura de corpus (14 perguntas), não é a suíte que testa injeção/postura; essa cobertura já está em `check-brain-answer`/`check-brain-comparison`/`check-brain-synthesis` | `golden-dataset-v1.json` — 14 perguntas, sem menção a INJ/ADV/stance | nenhum — os dois conjuntos de teste têm propósitos diferentes; revisar só se o golden passar a servir de suíte de regressão adversarial também | não | não | não |

## DATA/CORPUS

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Corpus ativo: só 2 documentos** (Magnojet V41 + ARAG) | aceito, é o estado da Fase 2 hoje | baixo | `CLAUDE.md` "Estado atual" — 780 trechos, 2 fontes | crescer via JR/DJI/outros, cada um condicionado ao seu próprio blocker acima | — | — | — |
| **`query_codes` não alarga a janela de 7–9 dígitos** para código curto (3–4) | fronteira conhecida, não é pendência | baixo — medido ponta a ponta: código curto **é** recuperado pelos braços de prosa; o que muda sem alargar é o rank, não o recall | `fase-2-jr-solucoes.md` §11.3 | nenhum — alargar é regra transversal do BRAIN (afeta Magnojet, ARAG, DJI) e exige documento que prove necessidade | não | não | não |

## INFRA FUTURA

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **pgvector / Lote C** | não instalado, sem migration preparada | baixo — **aceito como não-blocker**: o RRF de três braços (FTS + trigram + código) responde 5/5 perguntas respondíveis do golden; nenhuma falha hoje é de recall | `consolidado.md` §5 — `pg_extension` conferido sem `vector`; schema sem coluna vetorial nem rótulo "embed*" (suíte `ensaiar-memoria` M6 trava isso) | medir quando aparecer pergunta em linguagem natural que FTS+trigram erre com corpo já ingerido — não se supõe, se mede | sim, quando decidido | sim (confidencialidade + custo) | sim, eventualmente — provedor de embedding |
| **Worker `--pages`** | **fechado** — implementado (contradiz `consolidado.md` de 16/09, que é anterior à implementação) | — | `CLAUDE.md` "Estado atual"; `brain/worker/brain_worker/__main__.py` — `add_argument("--pages", …)` em `ingest` e `plan`, confirmado no código nesta rodada | nenhum — está em produção desde 17/09 | — | — | — |
| **Action pinning por SHA** no lugar de tag de major | aberto, melhoria futura | baixo | `.github/workflows/brain-app.yml` usa `actions/checkout@v5` e `actions/setup-node@v4`; `brain.yml` usa `@v5`/`@v5` — confirmado nesta rodada, nenhum workflow fixa por SHA | fixar quando houver rodada de hardening de CI/supply chain | não | não | não |
| **Branch protection com required status checks** | não confirmado no repo (é configuração do GitHub, não visível nos arquivos) | baixo hoje — nenhum check obrigatório configurado ainda, então o risco descrito abaixo ainda não se materializou | `ci.md` §8 — dívida conhecida | ao ligar a proteção: decidir entre tirar os `paths` do `brain-app.yml` (roda sempre, ~1 min) ou um job-espelho que reporta sucesso quando nada relevante mudou — um PR só de `docs/` nunca dispara `app-gates` e travaria em "Waiting for status" se ele virar obrigatório com os `paths` como estão | não | sim (acesso de admin ao repo GitHub) | não |
| **Diretórios temporários de teste fora do `.gitignore`** | aberto, de propósito ("ficou assim nesta rodada") | baixo — cada suíte cria com `mkdtempSync` e remove com `rmSync` ao final; `.provider-check-*` já está no `.gitignore`, os outros cinco (`.brain-check-*`, `.answer-check-*`, `.ui-check-*`, `.comparison-check-*`, `.synthesis-check-*`) não | `.gitignore` lido nesta rodada — confirma exatamente a lista que `ci.md` §8 já descreve, sem divergência | adicionar ao `.gitignore` numa rodada de limpeza, sem urgência (uma suíte que aborte no meio pode deixar o diretório para trás) | não | não | não |

## NÃO-BLOCKER / ACCEPTED LIMITATION

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Suíte 25 — BR4/BR5/BR6/BR9/BR16 herdadas** | aceito — comportamento esperado no modo desacoplado | baixo — provado nas duas pontas: com as pontes `trg_brain_*` ligadas a suíte fica 18/18, e `reconciliar_erp()` restaura a substância de cada uma | `consolidado.md` §7; `CLAUDE.md` "Pendências conhecidas" | forma, não substância: tornar as cinco condicionais a `brain.estado_das_pontes()` para não confundir com uma sexta falha real — não feito nesta rodada | não | não | não |
| **Mobile: BRAIN entra com `mobile: false`** | aceito, pendência de layout | baixo | `src/config/navigation.ts` — confirmado nesta rodada: Kits, Estoque, Entradas, Financeiro, Relatórios e BRAIN, todos `mobile: false` (barra do celular com 5 lugares, 6 itens marcados) | redesenhar a barra inferior quando entrar em pauta de UX — não é bug, é fila | não | não | não |
| **Compusystem não modelado em schema/coluna** | aceito, é a regra (`CLAUDE.md` #6) | baixo — é a proteção contra inventar dado, não uma falha | `CLAUDE.md` regra 6 | nenhum até o contrato chegar | não | — | — |
| **Forbidden + incompleta: só o motivo do forbidden aparece** (achado da revisão independente de 25/09) | aceito, é a ordem por desenho | baixo — quando uma comparação é ao mesmo tempo estruturalmente incompleta (código sem evidência) E envolve um documento `forbidden`, o gate de processamento externo vem ANTES do gate de comparação em `answerWith`, então o aviso só fala do documento proibido; o motivo da incompleta nunca aparece, mesmo sendo verdadeiro também | `check-brain-synthesis.mjs` SYN19 — plano `SERIA incompleto`, mas o outcome é `external_processing_forbidden`, provider 0× | nenhum — a ordem está correta: "isto pode sair daqui?" é uma pergunta anterior a "a comparação está completa?", e misturar os dois avisos arriscaria vazar que um documento proibido existe (a mesma razão por trás de "ausência de política é proibição") | não | não | não |
| **SYN16e e SYN16b (near-tautológicos)** (achado da revisão independente de 25/09) | anotado, não corrigido | muito baixo — SYN16e confere que a resposta extractiva não contém "Diferença/maior/menor/%", mas a resposta extractiva é só a renderização local das evidências aceitas (nunca teve essas palavras para começar, o teste não força nenhum caminho que poderia inserir uma); SYN16b confere `s16a.entrada === null`, que já é implicado por `s16a.chamadas === 0` (conferido em SYN16a, uma linha acima) — os dois continuam úteis como documentação executável, mas não aumentam a cobertura real | `check-brain-synthesis.mjs`, seção SYN15–SYN19 | nenhum — não vale reescrever teste que já passa só para ficar "menos redundante"; registrado para quem for mexer nessa seção não reintroduzir os dois achando que testam algo que não testam | não | não | não |

## Próxima macro rodada recomendada

**Answer v1 em produção.** Três decisões que só o Wilson toma, mais o
fechamento técnico que as acompanha:

1. **Credencial em produção** — provedor aprovado, orçamento, chave
   server-only na Netlify (CI e Preview continuam sem ela). Localmente a
   cadeia já roda com provedor real e passa nos smokes; o que falta é a
   decisão, não código.
2. **Branch protection** com `app-gates` (e o `deploy-reversao` do
   `brain.yml`) como checks obrigatórios — antes, decidir o que fazer com os
   `paths` do `brain-app.yml` (rodar sempre, ou job-espelho), senão PR só
   de `docs/` trava em "Waiting for status".
3. **Observabilidade mínima dos outcomes** `[brain.synthesis]` em produção
   (contagem por outcome, sem conteúdo) — a taxonomia é fechada e testada
   (LOG8); é o que dirá, com dado real, se stance, órfão e incompleta estão
   custando respostas e se a cadeia se comporta como no harness.

É a rodada mais lógica porque destrava o maior valor já construído e
auditado: a cadeia inteira está provada com 658 asserções determinísticas
e com provedor real no localhost; JR, DJI e Compusystem crescem o acervo,
mas dependem de terceiros, e nenhum torna mais útil o que os dois
documentos já ingeridos sustentam hoje. Não começar aqui: cada item mexe
em produção ou em configuração do GitHub, e isso é decisão do Wilson.
