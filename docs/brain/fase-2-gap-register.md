# AGROTORK BRAIN — Registro de lacunas (25/09/2026, atualizado em 26/09/2026)

> Revalidado no repositório nesta rodada, não copiado dos docs anteriores.
> Onde não deu para confirmar, está escrito "não confirmado no repo" em vez
> de afirmado. Ver `docs/brain/fase-2-answer-v1.md` (estado atual),
> `docs/brain/fase-2-consolidado.md` (16/09, retrato mais amplo da Fase 2) e
> `CLAUDE.md` para o histórico completo de cada item. Estado de produção item
> a item: `production-readiness-checklist.md`; passo a passo:
> `production-readiness.md`.

## FECHADO NESTA RODADA (26/09/2026 — revisão independente da production readiness)

Itens SHOULD-FIX de uma revisão independente sobre `7681489`, fechados no
commit `fix(brain): fecha achados da revisão independente`. Cada teste novo
foi conferido contra a versão anterior do código (reprova sem a correção).

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **Preflight lia `.env.local` diferente do Next** | fechado | o parser próprio divergia do servidor: `KEY=FAKEabc#def` o Next carrega `FAKEabc`; `"FAKE\nabc"` entre aspas duplas vira quebra de linha real. Agora o preflight usa o carregador do próprio Next (`@next/env`, `loadEnvConfig(cwd, false)`), com o conjunto de produção `.env.production.local` → `.env.local` → `.env.production` → `.env`; a regra própria "multilinha = erro" morreu (o Next lê; a chave com quebra de linha dá `key_invalid`). `.env*` que é diretório segue exit 1 com `EISDIR` (o Next ignoraria em silêncio); `--contract` não toca disco | `check-brain-provider.mjs` PF10–PF14, PF5c (PF12b, PF13 e PF14 reprovam com o parser antigo); `env-contract.md` §3 |
| **Guarda não fixava `set -euo pipefail` nem a regex do filtro do `scope`** | fechado | as duas linhas passaram a ser exigidas com o texto exato, e só no shell do PRÓPRIO job `scope` (antes valia o shell do arquivo inteiro); nenhuma linha `ref:` nos dois workflows | `conferir-ci-app.mjs`; mutações M35–M37 (37/37 reprovam, 4 controles aprovados); `ci.md` §8 |
| **Segundo `brain-db-gate` no mesmo SHA** | fechado | `brain.yml` com push em `brain/fase-1`/`brain/fase-2` dava a um PR com essa head dois vereditos no mesmo SHA (o do push diffado contra `before`, podendo ficar verde com o do PR vermelho). Push só em `main` | `brain.yml`; `ci.md` §2 |
| **`codesForLog` podia virar identidade sem teste vermelho** | fechado | OBS4/OBS13 passam pela primeira trava (catálogo) e não enxergavam a segunda. OBS15 chama `codesForLog` direto: UUID, URL e 64-hex saem, `MJ981CAP` fica | `check-brain-synthesis.mjs` OBS15 (reprova com `codesForLog` = identidade) |
| **Contradições nos docs de readiness** | fechado | `production-readiness.md` §1.1 (lista dos 9 commits), §1.2 (guarda + 6 suítes), §1.3 (`merge_group:` já existe); checklist alinhada ao `ci.md` (4 controles) | este commit |

## FECHADO NA RODADA ANTERIOR (26/09/2026 — revisão adversarial da production readiness)

Achados reproduzidos por uma revisão adversarial sobre `2c1f1cf`, todos
fechados no commit `fix(brain): fecha achados da revisão adversarial`, cada um com teste que falha sem a correção.

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **S1 — chave colada em `BRAIN_LLM_MODEL` ia ao log** | fechado | o modelo era aceito como veio e logado em todo evento (`"model":"sk-ant-…"`), e o preflight dizia PRONTO. Novo motivo `model_invalid`: o modelo tem de casar `^[a-z0-9][a-z0-9._:@-]{0,99}$` (sem diferenciar caixa) e não pode começar por `sk-`; ordem provedor → modelo (ausente → inválido) → chave | `check-brain-provider.mjs` CFG16–CFG16d, PF7; `check-brain-synthesis.mjs` SYN34f |
| **S2 — chave com espaço/controle/não-ASCII virava `network`** | fechado | o undici recusa o cabeçalho, e o sintoma era erro de rede em toda consulta. Novo motivo `key_invalid`: só ASCII visível (0x21–0x7E) depois do trim | CFG17a–c; SYN34g |
| **S3 — arquivo MOVIDO para fora de `supabase/`/`brain/` pulava o ensaio** | fechado | `git diff` detecta rename e lista só o nome novo; com `--no-renames` o antigo aparece como removido e casa o filtro. `merge_group:` entrou nos dois workflows (inofensivo sem merge queue; o `scope` cai no `*)` → `db=true`) | `ci.md` §4 (CI8, CI9; CI1–CI7 inalterados); `check:brain-ci` fixa a linha |
| **S4 — guarda do CI contornável** | fechado | `conferir-ci-app.mjs` endurecida, ainda por texto: comentário YAML ignorado (fim do falso positivo `workflow_dispatch: # not pull_request_target`), bloco `run:` lido cru; `pull_request:`/`merge_group:` sem filho nos dois; uma única `permissions:` (topo, exatamente `contents: read`); em `brain.yml`, sem `continue-on-error`, só os dois `if:` do desenho, veredito do gate e saídas do `scope` fixados linha a linha; `\bsecrets\b`; nenhum `${{` dentro de `run:`; `lint`/`typecheck`/`build` como linhas exatas | `ci.md` §8; teste de mutação: 34 cópias mutadas reprovadas, 3 controles e os arquivos reais aprovados |
| **S5 — parser do `.env.local` do preflight** | fechado | `NOME=#x` vale vazio (como no dotenv); valor sem aspas cortado em ` #`; comentário depois de valor entre aspas; multilinha é erro explícito, sem valor; `.env.local` ilegível (EISDIR…) dá mensagem curta, sem pilha; argumento desconhecido dá a linha de uso | PF8–PF11 (com `.env.local` de verdade em diretório temporário); `env-contract.md` §3. *Substituído na revisão independente: o parser próprio saiu, a leitura é pelo `@next/env` (ver acima)* |
| **N1 — `chunkId` repetido na busca** | fechado | "o primeiro índice vence" podia abrir o card do descartado; `mapCitationsToScreen` devolve `null` com chave repetida. Com isso `internal_error:citation_mapping` ficou **alcançável** ponta a ponta pela porta `search`, sem gancho de teste | `check-brain-answer.mjs` CIT5; `check-brain-synthesis.mjs` SYN33–SYN33c (a SYN33 por texto do fonte saiu) |
| **N3 — porta que lança não deixava evento** | fechado | `search`, `externalProcessing` e `resolveProvider` lançando: sai `internal_error` com `reason` `search`/`policy`/`provider_config` (sem a mensagem) e o erro é relançado para o `catch` da action — a tela não muda | SYN35a–c; LOG1 conta também essas rodadas |
| **N4 — `kind` do `ProviderError` sem conferência** | fechado | `readonly` é só do TypeScript; `providerErrorReason` aceita só as seis categorias, o resto vira `unknown` | OBS14 |
| **N6 — oráculo circular do selo de comparação** | fechado | SYN32d passou a 10 perguntas com o selo esperado escrito à mão, conferido também no `comparison` do EVENTO; OBS11 fica como conferência de consistência | SYN32d |

## FECHADO NA RODADA DE PRODUCTION READINESS (26/09/2026)

Branch `hardening/brain-production-readiness`, sobre `98a80b0` (PR #7).

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **Action pinning por SHA** | fechado | `checkout` v5.1.0, `setup-node` v4.4.0 e `setup-python` v5.6.0 fixadas por SHA de commit, versão em comentário; checkout com `persist-credentials: false` | commit `ecac757`; `ci.md` §9 |
| **`paths` × check obrigatório (status fantasma)** | fechado — decidido | `brain-app.yml` perdeu os `paths` (roda em todo PR, ~1 min); em `brain.yml` o filtro saiu do gatilho para o job `scope` (git diff contra o merge-base, na dúvida `db=true`), e `brain-db-gate` (`if: always()`) é o check obrigatório do banco. Não foi preciso job-espelho | commit `ecac757`; `ci.md` §2–4 (CI1–CI7); `check:brain-ci` trava as regras |
| **Worker Python fora do CI de PR** | fechado | antes, `brain.yml` só disparava em PR que tocasse `supabase/**` ou o próprio workflow: PR só em `brain/worker/**` não rodava pytest nem o ensaio de ingestão. O `scope` inclui `brain/` na regra de `db=true` (CI4) | commit `ecac757`; `ci.md` §4 |
| **Outcome estruturado da síntese** | fechado | `GenerationEvent` tipado (`observability.ts`), taxonomia fechada de `outcome`/`reason` com trava de compilação; sai `query` (fica `queryLength`), nenhum texto livre; códigos só em comparação, filtrados pelo catálogo das evidências aceitas | commits `fc489a4`, `d86332f`, `56de30e`; `check-brain-synthesis.mjs` LOG1–LOG8b, OBS1–OBS15; `fase-2-answer-v1.md` §5.1 |
| **Credencial do provedor — contrato** | parcial → **contrato pronto**; env de produção **NEEDS_WILSON** | `readProviderConfig` (puro) com motivos fechados; `resolveProvider` → `{ provider, reason }`; `no_provider` loga o motivo; `npm run brain:preflight` (exit 0/1/2, sem valores) | commit `56de30e`; CFG1–CFG17c, PF1–PF14 + PF5c, SYN34a–h (os três últimos grupos ampliados nas revisões adversarial e independente); `env-contract.md`. A linha em BLOCKER segue aberta para a parte de produção |
| **Diretórios temporários de teste fora do `.gitignore`** | fechado | os cinco padrões que faltavam entraram no `.gitignore`; cada suíte apaga o temporário em `process.on("exit")` logo após o `mkdtempSync` | commit `e0d5d3c`; `ci.md` §7 |

## FECHADO NESTA BRANCH (26/09/2026 — hardenings residuais do Answer v1)

Os dois itens que a revisão de 25/09 deixou em HARDENING. Commit `e608e9d`
(`fix(brain): fecha hardenings residuais do Answer v1`). Testes que
pinam cada um: `check-brain-synthesis.mjs` (SYN19b, SYN32a–d, SYN33) e
`check-brain-answer.mjs` (CIT1–CIT4).

| item | estado | o que mudou | evidência |
| --- | --- | --- | --- |
| **`comparison` sumia em três caminhos de saída antecipada** | fechado | o selo passou a sair só do TEXTO da pergunta: `isComparisonQuestion(pergunta)` (`comparison.ts`) = intenção explícita + ≥ 2 códigos, o mesmo critério que `planComparison` usa para `not_applicable`. `answerWith` calcula antes de qualquer gate (não lê evidência, política nem provedor — privacidade primeiro) e `base()` o aplica a todo caminho que devolve resposta: gate externo, sem provedor, erro do provedor, teto, incompleta, rejeição e sucesso. Recusas (`no_evidence`, `model_refusal`) seguem sem o selo | `check-brain-synthesis.mjs` SYN19b (agora `true`), SYN32a–d |
| **Fallback `?? c.evidenceIndex` em `citacoesParaTela`** | fechado | o helper virou `mapCitationsToScreen` (puro, em `answer.ts`): mapeia por `chunkId`, não por identidade de objeto, e é FAIL-CLOSED — aceita fora de `evidencias` ou índice fora do intervalo devolve `null`; `answerWith` confere logo depois do Evidence Gate (antes do gate externo e do provedor) e, se `null`, registra `internal_error` (`citation_mapping`) e devolve extractiva com `citations: []` e aviso genérico. Na época o ramo era inalcançável ponta a ponta; desde a revisão adversarial (N1, acima) `chunkId` repetido também é `null` e o ramo é exercitado pela porta `search` | `check-brain-answer.mjs` CIT1–CIT5; `check-brain-synthesis.mjs` SYN33–SYN33c |

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
| **Credencial do provedor LLM em produção** (`BRAIN_LLM_PROVIDER`/`_API_KEY`/`_MODEL`) | parcial — **contrato pronto** em 26/09 (`readProviderConfig`, `brain:preflight`, commit `56de30e`); **existe localmente** (`.env.local` do Wilson desde 20/09; smokes reais H 10/10, A/B/C/D/F no `localhost` em 25/09); **env de produção/Netlify: NEEDS_WILSON** — não confirmado no repo (por decisão, o Preview não recebe a chave) | baixo — sem ela o sistema já é fail-closed (resposta extractiva, nunca inventa); o custo é não entregar resposta redigida em produção | `fase-2-answer-v1.md` §5 e "Estado atual"; `resolveProvider()` devolve `{ provider: null, reason }` sem as três variáveis; contrato, `npm run brain:preflight` e rollback em `env-contract.md` (26/09; timeout das funções da Netlify a confirmar, §6 de lá); `docs/brain/ci.md` §6 (Preview sem chave) | Wilson decide provedor aprovado e orçamento e põe a chave como env **server-only** na Netlify (nunca `NEXT_PUBLIC_`); CI e Preview continuam sem ela — passo a passo em `production-readiness.md` §2 | sim (env de produção) | **sim** | sim — Anthropic (ou outro formalmente aprovado) |
| **Timeout da função Netlify não verificado** (novo, 26/09) | NEEDS_WILSON | médio no dia de ligar o provedor — o adapter corta em 30 s (`TIMEOUT_PROVIDER_MS`); se a função da Netlify morrer antes de busca + 30 s, o usuário vê erro genérico em vez do fallback extractivo | `limits.ts`; `netlify.toml` não declara timeout; `env-contract.md` §6 | Wilson confere no painel o timeout das funções de produção (≥ ~40 s) antes de cadastrar a chave | sim | **sim** | não (depende do plano Netlify) |
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
| **`internal_error` alcançável ponta a ponta** (26/09; antes registrado como inalcançável) | fechado | nenhum resíduo — `citation_mapping` sai pela busca com `chunkId` repetido (N1) e `search`/`policy`/`provider_config` pelas portas que lançam (N3); o LOG8 perdeu a lista `INALCANCAVEIS` e exige os 10 outcomes | `check-brain-synthesis.mjs` SYN33–SYN33c, SYN35a–c, LOG8, OBS1; `check-brain-answer.mjs` CIT1–CIT5 | nenhum; em produção a contagem deve ser 0 — qualquer ocorrência é defeito a investigar pela `reason` (`production-readiness.md` §5) | não | não | não |
| **`none_fit_context` inalcançável com os limites de hoje** (novo, 26/09) | declarado, aceito | baixo — toda evidência aceita tem ≤ `MAX_CHARS_POR_EVIDENCIA` (20.000) e o orçamento é `MAX_CHARS_CONTEXTO` (62.000); a primeira (20.000 + 200) sempre cabe, então o motivo não sai | `limits.ts`; `answer.ts` (`assessEvidence`); `check-brain-synthesis.mjs` SYN23 e comentário do LOG8b | nenhum; se os limites mudarem, o motivo volta a ser alcançável e precisa de teste | não | não | não |
| **Limites do `codesForLog`** (novo, 26/09) | aceito, segunda trava | baixo — é filtro de FORMA (até 16 caracteres, letra/dígito/hífen): sozinho deixaria passar CNPJ de 14 dígitos ou segredo curto (OBS13). Por isso a primeira trava é `comparisonCodesForLog` (só o que está no catálogo `codes` das evidências aceitas). Resíduo: um token com forma de código que a ingestão tenha posto no catálogo de uma evidência iria ao log; código real com mais de 16 caracteres ou com ponto/barra fica só na contagem. **N2 da revisão adversarial (26/09), registrado e aceito:** o catálogo `codes` é dado da INGESTÃO, não prova de que o token é código de produto — o log confia no worker (`test_w29`: preço, telefone e CNPJ não entram em `codes`); se a extração de códigos mudar, esta trava muda junto | `observability.ts`; `check-brain-synthesis.mjs` OBS4, OBS13 | nenhum; revisar se entrar corpus com código de produto fora dessa forma | não | não | não |
| **`provider_error:unknown` junta causas diferentes** (revisão adversarial, 26/09) | aberto, backlog | baixo — o adapter mapeia 401/403 → `auth` e 429 → `rate_limit`, mas HTTP 400 (modelo inexistente, parâmetro recusado), 5xx/529 (provedor fora/sobrecarregado) e qualquer outro status caem em `unknown`; e `stop_reason: "max_tokens"` não é conferido — texto cortado segue ao validador e sai como `answer_rejected` (ou passa, se o corte cair num ponto limpo). Nada disso vaza conteúdo; o custo é diagnóstico pior | `src/modules/brain/llm/anthropic.ts` (`!resposta.ok`, `extrairTexto`) | HARDENING: categorias `bad_request`/`upstream` e um motivo para resposta truncada, com teste no adapter e na taxonomia | não | não | não |
| **`brain/worker/requirements.txt` sem hashes** (novo, 26/09) | aberto | baixo — as dependências do worker são instaladas no `deploy-reversao` por faixa de versão (`>=`), sem `--require-hashes`; uma versão nova publicada dentro da faixa entra sem revisão | `brain/worker/requirements.txt`; `brain.yml` (`pip install --quiet -r …`) | lock com hashes numa rodada de hardening de supply chain | não | não | não |
| **NOTE — PR com base trocada guarda `brain-db-gate` velho** (revisão independente, 26/09) | registrado; mitigação na branch protection | baixo — retarget de base sem push novo não dispara rodada; o check que aparece foi calculado contra a base antiga (outro diff no `scope`) | comportamento do GitHub Actions (`pull_request` sem `edited` nos tipos padrão) | "Require branches to be up to date before merging" no item de branch protection (INFRA FUTURA; checklist §4) | não | sim (junto com a branch protection) | não |
| **NOTE — exceção em `toEvidence`/`assessEvidence`/`planComparison`/`validateAnswer` só deixa `[brain.action]`** (revisão independente, 26/09) | aberto, backlog HARDENING | baixo — as quatro são puras e cobertas por suíte; se uma lançar (bug), não sai evento `[brain.synthesis]` — só a linha `[brain.action]` com `errorName` — e a contagem por outcome não vê a consulta | `synthesis.ts` (`answerWith`); `actions.ts` | envolver como as portas (N3): `internal_error` com `reason` próprio e relançar | não | não | não |
| **NOTE — `buildUserMessage` dentro do `try` do provedor** (revisão independente, 26/09) | aberto, backlog | baixo — se a montagem da mensagem lançar (bug local), o evento sai `provider_error:unknown`, atribuindo ao provedor uma falha nossa | `synthesis.ts`, bloco `try { provider.generate({ … userMessage: buildUserMessage(…) }) }` | montar a mensagem antes do `try` (e cair no item acima) | não | não | não |
| **NOTE — `MODELO_VALIDO` aceita `:` e `@`** (revisão independente, 26/09) | registrado, risco baixo | baixo — necessários para identificadores de modelo com versão/sufixo; o que importa (prefixo `sk-`, espaço, controle) é recusado; um token com `:`/`@` ainda iria ao campo `model` do log | `llm/config.ts` (`MODELO_VALIDO`); CFG16–CFG16d | nenhum; revisar se o provedor mudar a forma dos identificadores | não | não | não |
| **NOTE — `[brain.action].errorName` sem limite** (revisão independente, 26/09) | registrado, baixo | baixo — é `e.name` como veio: classe de erro de terceiro (ou `name` atribuído em tempo de execução) pode trazer texto longo ou de alta cardinalidade ao log | `actions.ts` (`console.error("[brain.action]", …)`) | se virar ruído: lista fechada de nomes (o resto `other`) ou corte de tamanho | não | não | não |

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
| **Branch protection com required status checks** | NEEDS_WILSON — a decisão técnica fechou em 26/09 (ver FECHADO NESTA RODADA); falta ligar | baixo — sem ela, nada impede merge com CI vermelho; se já existe alguma regra, não é visível pelo repositório | `ci.md` §3; `production-readiness.md` §1.3 | depois do merge desta branch e de uma rodada dos workflows em `main`: exigir PR e os checks `app-gates` e `brain-db-gate` — **não** `deploy-reversao` (pulado por `if:` reporta sucesso) nem `scope` —, e marcar **"Require branches to be up to date before merging"** (PR com base trocada guardaria o `brain-db-gate` velho; ver NOTE em HARDENING); PASSO EXATO em `production-readiness-checklist.md` §4 | não | sim (acesso de admin ao repo GitHub) | não |
| **Deprecação do node20 em `setup-node@v4` e `setup-python@v5`** (novo, 26/09) | DEFERRED — bump de major | baixo hoje — funcionam; o GitHub está aposentando o node20 nos runners | `ci.md` §10 | quando o aviso virar erro, subir para o major seguinte, trocando SHA e comentário juntos (`ci.md` §9) | não | não | não |

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
2. **Branch protection** com `app-gates` e `brain-db-gate` como checks
   obrigatórios (não `deploy-reversao`: job pulado reporta sucesso). Os
   `paths` já saíram do gatilho em 26/09 (`ci.md` §3); falta ligar, depois
   do merge.
3. **Observabilidade mínima dos outcomes** `[brain.synthesis]` em produção
   (contagem por outcome, sem conteúdo) — o evento está tipado e sem a
   pergunta desde 26/09 (LOG1–LOG8b, OBS1–OBS15); falta contar com dado real
   (`production-readiness.md` §5.4) e decidir destino/retenção.

*(26/09: os três itens estão no runbook `production-readiness.md` e na
matriz `production-readiness-checklist.md`.)*

É a rodada mais lógica porque destrava o maior valor já construído e
auditado: a cadeia inteira está provada com 777 asserções determinísticas
(`check:brain-all` em 26/09, depois da revisão independente)
e com provedor real no localhost; JR, DJI e Compusystem crescem o acervo,
mas dependem de terceiros, e nenhum torna mais útil o que os dois
documentos já ingeridos sustentam hoje. Não começar aqui: cada item mexe
em produção ou em configuração do GitHub, e isso é decisão do Wilson.
