# AGROTORK BRAIN — Runbook de produção do Answer v1

> 26/09/2026, branch `hardening/brain-production-readiness`. **Tudo aqui é
> passo FUTURO.** Nesta rodada nada foi feito em produção, na Netlify, no
> GitHub remoto ou no Supabase (§7). O estado de cada item está em
> [`production-readiness-checklist.md`](production-readiness-checklist.md);
> o contrato das variáveis, em [`env-contract.md`](env-contract.md); o CI, em
> [`ci.md`](ci.md).

Ordem de uso: §1 (merge e proteção) → §2 (provedor) → §3 (smoke) → §5
(observar). §4 é a saída de emergência e vale a qualquer momento depois do §2.

## 1. Pré-merge

### 1.1 O que está em fila

| Branch | Base | Commits | O que é |
| --- | --- | --- | --- |
| `hardening/brain-answer-v1-closure` (**PR #7**) | `main` (`d80ae65`) | 10, até `98a80b0` | fechamento do Answer v1: state machine da síntese (SYN), matriz adversarial, postura, comparação incompleta antes do provedor, revisão independente de 25/09 |
| `hardening/brain-production-readiness` (esta) | `98a80b0` (cabeça do PR #7) | 6 + este de docs | hardenings residuais, outcomes tipados, privacidade do log, CI sem status fantasma, higiene dos testes, contrato do provedor + `brain:preflight` |

Esta branch nasce em cima do PR #7. Ordem obrigatória: **PR #7 entra
primeiro**; só então abrir o PR desta branch contra `main` (o diff dele passa
a mostrar só os commits daqui).

### 1.2 Checks que precisam estar verdes

**No PR #7** (workflows ainda na versão de `98a80b0`, com `paths` no
gatilho):

| Check | Roda porque | Observação |
| --- | --- | --- |
| `BRAIN App / app-gates` | o PR toca `src/**` e `supabase/db-tests/check-brain*.mjs` | guarda + 6 suítes + lint + typecheck + build |
| `BRAIN / deploy-reversao` | o PR toca `supabase/**` | antes desta branch é o **único** check de banco, e só dispara em PR que toque `supabase/**` ou o próprio `brain.yml` — PR só de `brain/worker/**` não rodava o ensaio |

**No PR desta branch** (workflows novos, sem `paths`):

| Check | Workflow | Esperado |
| --- | --- | --- |
| `app-gates` | `BRAIN App` | verde; roda em todo PR |
| `scope` | `BRAIN` | `db=true` (o diff toca `supabase/db-tests/` e `.github/workflows/brain.yml`) |
| `deploy-reversao` | `BRAIN` | roda (porque `db=true`) e fica verde |
| `brain-db-gate` | `BRAIN` | verde; é o veredito do banco |

Local, antes de publicar: `npm run check:brain-all` passou em 26/09 (exit 0,
sete suítes). Lint, typecheck e build ficam com o `app-gates`.

### 1.3 Branch protection (recomendada, depois do merge desta branch)

Em *Settings → Branches → main*:

- **Exigir pull request** antes do merge.
- **Exigir status checks**, exatamente dois: `app-gates` e `brain-db-gate`.
- Force push e exclusão da branch: **desligados** (`CLAUDE.md`, regra 2).

**Não** marcar `deploy-reversao` nem `scope` (`ci.md` §3):

- `deploy-reversao` pulado por `if:` reporta **sucesso**. Obrigatório, ele
  deixaria um `scope` quebrado (`db=false` por engano) aprovar PR sem ensaio.
  O `brain-db-gate` reprova esse caso: `scope` não concluído, `db` inválido,
  `db=true` sem ensaio verde ou `db=false` com ensaio que não foi pulado.
- `scope` só decide "rodar ou não"; passar nele não prova nada.

**Quando ligar:** só depois que esta branch estiver em `main` e os dois
workflows tiverem rodado pelo menos uma vez com os jobs novos — o GitHub só
oferece na lista o nome de um check que já reportou. Ligar antes, com os
`paths` antigos, trava PR só de `docs/` em "Expected — Waiting for status".

Se um dia houver merge queue: os dois workflows precisam de `merge_group:`
(`ci.md` §3). Hoje não têm.

### 1.4 Netlify: o que o merge muda e o que não muda

- O merge em `main` gera deploy de produção do código. **Não liga a
  síntese**: sem as três variáveis, `resolveProvider()` devolve
  `{ provider: null, reason: "provider_missing" }` e o BRAIN responde de
  forma extractiva, como hoje.
- Variáveis do provedor: **só no contexto Production**, escopo de servidor
  (funções). Deploy Preview e branch deploy ficam **sem chave, de
  propósito**: código de PR não recebe credencial (`env-contract.md` §2).
- Nunca `NEXT_PUBLIC_BRAIN_LLM*`: o Next embute esse prefixo no JavaScript do
  navegador. O preflight sai com exit 2 se existir.

### 1.5 Desfazer um merge

- **Reverter por PR**: botão *Revert* do PR no GitHub, ou `git revert -m 1
  <sha-do-merge>` numa branch nova + PR. O revert passa pelos mesmos checks.
- **Nunca** `push --force`, `reset` em `main` ou reescrita de histórico.
- O deploy da Netlify acompanha `main`: o revert mergeado gera o deploy de
  volta. Variáveis de ambiente não são afetadas por revert de código — para
  desligar a síntese, §4.

## 2. Provedor: os dez passos

Nenhum foi executado. Cada um depende de decisão ou acesso do Wilson.

| # | Passo | Como | Pronto quando |
| --- | --- | --- | --- |
| 1 | Aprovar o provedor | decisão do Wilson; hoje o código suporta só `anthropic` (`SUPPORTED_PROVIDERS`, `llm/config.ts`) | provedor aprovado por escrito |
| 2 | Confirmar o modelo | identificador exato para `BRAIN_LLM_MODEL`; o código não fixa modelo | identificador anotado |
| 3 | Orçamento e limite | teto de gasto/limite de uso na conta do provedor | limite configurado no provedor |
| 4 | Cadastrar as variáveis em **Production** | `BRAIN_LLM_PROVIDER=anthropic`, `BRAIN_LLM_MODEL=<modelo>`, `BRAIN_LLM_API_KEY=<secret>`, escopo de servidor | os três NOMES aparecem no painel, só em Production |
| 5 | **Nunca** em Preview | conferir que nenhuma das três tem valor em Deploy Preview / branch deploy | Preview sem valor |
| 6 | **Nunca** `NEXT_PUBLIC_` | conferir que não existe `NEXT_PUBLIC_BRAIN_LLM*` em contexto nenhum | nenhuma |
| 7 | Deploy | novo deploy de produção do mesmo commit (variável nova só vale a partir do deploy seguinte, `env-contract.md` §5) | deploy publicado |
| 8 | Smoke controlado | P1–P6 do §3, uma vez cada, como administrador | resultados batem com a tabela do §3 |
| 9 | Observar outcomes | contagem do §5.4 nos primeiros dias | nenhum `no_provider`, nenhum `internal_error` |
| 10 | Rollback, se preciso | `BRAIN_LLM_PROVIDER=none` (ou remover a variável) + redeploy — §4 | log volta a `no_provider` |

Antes do passo 4, e depois de qualquer mudança, `npm run brain:preflight`
(`env-contract.md` §3) — manual, local, sem rede, fora do CI:

- imprime, por variável, só `presente`/`ausente` (nunca valor, pedaço ou
  tamanho), se existe `NEXT_PUBLIC_BRAIN_LLM*`, se o provedor é suportado, se
  o modelo está preenchido e o veredito;
- **exit 0** `PRONTO PARA PRODUÇÃO (configuração)` · **exit 1** `NÃO
  CONFIGURADO: <reason>` · **exit 2** existe `NEXT_PUBLIC_BRAIN_LLM*`;
- `npm run brain:preflight -- --contract` só imprime o contrato (nomes,
  valores aceitos, regras e os cinco motivos) e não lê o ambiente;
- **não** prova que a chave é válida (exigiria chamar o provedor) e **não**
  lê o painel da Netlify: roda onde as variáveis existem, ou confere-se no
  painel só os NOMES e o escopo.

Antes do passo 7, **confirmar o timeout das funções** da Netlify no painel
(`env-contract.md` §6): o adapter corta o provedor em 30 s
(`TIMEOUT_PROVIDER_MS`); a função precisa durar mais que busca + 30 s, senão
é encerrada antes do fallback extractivo e o usuário vê erro genérico. O
`netlify.toml` não fixa esse valor.

## 3. Smoke de produção

Uma rodada, **como administrador**, no console do BRAIN em produção, depois
do passo 7. Cada pergunta gera **uma** linha `[brain.synthesis]` no log.
Valores esperados: Catálogo Magnojet V41, p. 20 (`golden-dataset-v1.json`,
fixtures de `check-brain-answer`/`-synthesis`/`-comparison`).

| # | Pergunta (exata) | Resposta esperada na tela | Evento esperado |
| --- | --- | --- | --- |
| P1 | `Qual a vazão da MJ981CAP a 40 psi?` | sintetizada: **0,77 L/min**, `[1]` = V41 p. 20 | `outcome: "answered"`, sem `reason`, `comparison: false`, `provider: "anthropic"`, `model` = o cadastrado, `durationMs` número, `evidencesSent` ≥ 1 |
| P2 | `Quais as vazões da MJ981CAP em bar possíveis?` | sintetizada com **os 6 pares**: 2,07 bar → 0,66 · 2,76 → 0,77 · 3,45 → 0,86 · 4,14 → 0,94 · 4,83 → 1,01 · 5,52 bar → 1,08 L/min | `answered`, `comparison: false`, provider/model preenchidos. Faltar um par ou colar ponto da MJ982CAP dá `answer_rejected`/`completeness`; par trocado, `answer_rejected`/`association` |
| P3 | `Compare a vazão da MJ981CAP e MJ985CAP a 40 psi. Quanto por cento a MJ985CAP entrega a mais?` | sintetizada, selo "Comparação": MJ981CAP **0,77**, MJ985CAP **1,53**, diferença **0,76 L/min**, **98,7%** (calculados em código, não pelo modelo) | `answered`, `comparison: true`, provider/model preenchidos. Valor trocado entre produtos: `answer_rejected`/`comparison` |
| P4 | `Compare a vazão da MJ981CAP e MJ999CAP a 40 psi` | extractiva, aviso **"Não dá para concluir a comparação: não encontrei documentação para MJ999CAP nesta consulta. Os trechos encontrados para os demais códigos estão abaixo, na íntegra."** | `comparison_incomplete`, `comparison: true`, `evidencesSent: 0`, `provider: null`, `model: null`, `durationMs: null`, `codes: []`, `codesMissingDocumented: 0`, `codesMissingUndocumented: 1` — **provedor chamado 0×** |
| P5 | `Qual a vazão da MJ999CAP?` | sem resposta (`no_evidence`), modelo não chamado | `no_evidence`, `reason: "none_retrieved"` (0 evidências, medido em `fase-2-answer-v1.md` §9), `comparison: false`, `provider: null` |
| P6 | `Compare a vazão da MJ981CAP e do sensor ARAG 466113200` (**admin**) | extractiva, aviso **O documento "Orçamento interno — sistemas ARAG para bicos" não pode ser processado por um serviço externo. A consulta continua disponível, com os trechos na íntegra.** | `external_processing_forbidden`, sem `reason`, `comparison: true`, `evidencesSent: 0`, `provider: null`, `model: null` — **provedor chamado 0×** |

Notas:

- **P4 e P6 são o ponto do smoke**: provam, em produção, que a cadeia
  encerra ANTES do provedor. `provider` diferente de `null` nesses dois é
  falha grave — desligar a síntese (§4) e investigar.
- P6 depende da sessão: o orçamento ARAG é `commercial`; um vendedor não o vê
  (§9 de `fase-2-answer-v1.md`), e a mesma pergunta cairia em
  `comparison_incomplete`. O título no aviso é o do manifesto
  (`fase-2-arag.md`); a ordem "forbidden antes da comparação" é a de SYN19.
- `answer_rejected` em P1–P3 **não é incidente**: a trava fez o trabalho e a
  tela mostra os trechos. É achado para investigar pela `reason`, não motivo
  de rollback. Rollback é para `provider_error` recorrente, custo fora do
  previsto, ou `provider` preenchido em P4/P6.
- Antes do passo 4 do §2, a mesma P1 dá a linha de base: `no_provider`,
  `reason: "provider_missing"`.
- P1–P3 com provedor real **não foram rodadas em produção**. Localmente, com
  provedor real, os smokes de 25/09 passaram (`fase-2-gap-register.md`,
  credencial). Em produção, o esperado acima vem do código e das suítes.

**Ler o evento.** Cada consulta escreve
`console.info("[brain.synthesis]", JSON)` (`synthesis.ts`). Na Netlify, ele
aparece nos logs de função do deploy de produção (a função de servidor do
Next); filtrar pelo texto `[brain.synthesis]`. O caminho exato no painel e a
retenção dependem da conta — confirmar no painel (NEEDS_WILSON no checklist).

## 4. Rollback da síntese sem desligar o BRAIN

Não precisa de feature flag nem de deploy de código:

1. No painel da Netlify, contexto Production: `BRAIN_LLM_PROVIDER=none` (ou
   `off`/`disabled`, ou remover a variável). A chave pode ficar — `none`
   vence.
2. **Redeploy do mesmo commit.** O código relê `process.env` a cada consulta
   (`DEPS.resolveProvider` em `synthesis.ts`), mas a variável alterada no
   painel só chega às funções no deploy seguinte (`env-contract.md` §5). Se o
   painel oferecer aplicar sem redeploy, não contar com isso sem conferir:
   **confirmar no painel** (NEEDS_WILSON).
3. Conferir: a próxima consulta responde **extractiva** (trechos na íntegra,
   aviso "A síntese automática não está configurada neste ambiente…"), e o log
   passa a `outcome: "no_provider"` com `reason: "provider_disabled"` (valor
   `none`/`off`/`disabled`) ou `"provider_missing"` (variável removida).

Prova em teste: **SYN34b** (`none` com chave e modelo presentes →
`no_provider:provider_disabled`, provedor 0×), SYN34a (`provider_missing`),
SYN34f (a tela não distingue os motivos) em `check-brain-synthesis.mjs`;
**CFG3c** em `check-brain-provider.mjs`.

Religar: voltar `BRAIN_LLM_PROVIDER=anthropic` + redeploy + P1.

## 5. Observabilidade

### 5.1 O evento

Uma linha por consulta, tipo `GenerationEvent`
(`src/modules/brain/observability.ts`):

| Campo | Tipo | Quando |
| --- | --- | --- |
| `event` | `"brain.synthesis"` | sempre |
| `outcome` | `GenerationOutcome` | sempre |
| `reason` | `GenerationReason` | só em `no_evidence`, `no_provider`, `provider_error`, `answer_rejected`, `internal_error` |
| `comparison` | boolean | sempre; sai só do texto da pergunta (`isComparisonQuestion`) |
| `queryLength` | número | sempre (no lugar da pergunta) |
| `evidencesRetrieved` / `evidencesAccepted` / `evidencesDropped` | número | sempre |
| `evidencesSent` | número | 0 quando o provedor não foi chamado |
| `provider` / `model` | string ou `null` | só quando o provedor foi chamado |
| `durationMs` | número ou `null` | só quando o provedor devolveu |
| `totalMs` | número | sempre |
| `codesCount` | número | só em `comparison_too_many` |
| `codes` / `codesMissingDocumented` / `codesMissingUndocumented` | lista / número / número | só em `comparison_incomplete` |

### 5.2 Taxonomia (fechada)

**outcome** (`GENERATION_OUTCOMES`): `answered`, `no_evidence`,
`external_processing_forbidden`, `comparison_too_many`,
`comparison_incomplete`, `no_provider`, `provider_error`, `model_refusal`,
`answer_rejected`, `internal_error`.

**reason** (`GENERATION_REASONS`), por outcome:

| outcome | reasons |
| --- | --- |
| `no_evidence` | `none_retrieved`, `none_passed_gate`, `none_fit_context` |
| `no_provider` | `provider_missing`, `provider_disabled`, `provider_unsupported`, `model_missing`, `key_missing` |
| `provider_error` | `timeout`, `auth`, `rate_limit`, `network`, `invalid_response`, `unknown` |
| `answer_rejected` | `grounding`, `format`, `completeness`, `association`, `comparison`, `stance` |
| `internal_error` | `citation_mapping` |

Dois valores declarados e **inalcançáveis hoje**: `internal_error` (SYN33b;
garantia pelo helper puro, CIT1–CIT4) e `none_fit_context` (toda evidência
aceita tem ≤ 20.000 caracteres e o orçamento é 62.000, então a primeira
sempre cabe — `limits.ts`, SYN23). Se aparecerem em produção, é defeito.

### 5.3 O que NÃO vai ao log

A pergunta (nem hash — fica `queryLength`; ela já está em
`brain.knowledge_queries`, sob RLS, leitura só de admin) · conteúdo de
evidência · prompt · corpo ou mensagem de erro do provedor · chave · ids
(UUID, `chunk_id`, `document_id`) · caminho de Storage · sha256 · detalhe da
rejeição do validador · código de produto fora de `comparison_incomplete` (e
ali só os que o catálogo das evidências aceitas conhece). Testes: LOG1–LOG8b
e OBS1–OBS13 em `check-brain-synthesis.mjs`.

### 5.4 O que contar

Por período (dia/semana), a partir das linhas `[brain.synthesis]`:

| # | Pergunta | Conta |
| --- | --- | --- |
| 1 | Quantas consultas sintetizam? | `answered` ÷ total |
| 2 | Quantas ficam sem evidência? | `no_evidence`, por `reason` |
| 3 | Quantas o processamento externo barra? | `external_processing_forbidden` |
| 4 | Quantas comparações ficam incompletas? | `comparison_incomplete` (+ `codesMissingUndocumented` > 0: código que o corpus não tem) |
| 5 | Quantas passam do teto de códigos? | `comparison_too_many` |
| 6 | Quantas respostas a trava rejeita, e por qual? | `answer_rejected` por `reason`: `grounding`, `association`, `comparison`, `stance`, `completeness`, `format` |
| 7 | Quantas o modelo recusa? | `model_refusal` |
| 8 | O provedor falha, e como? | `provider_error` por `reason`: `timeout`, `auth`, `network`, `rate_limit`, `invalid_response`, `unknown` |
| 9 | A configuração está inteira? | `no_provider` — com o provedor ligado deve ser **0** |
| 10 | Quanto demora? | `durationMs` (provedor) e `totalMs` (consulta), mediana e máximo; `durationMs` perto de 30.000 = timeout batendo |

`internal_error` deve ser sempre 0. `auth` = chave errada ou revogada;
`timeout` recorrente = conferir o timeout da função (§2).

Não há agregador no repositório: a contagem é leitura do log. Destino
permanente e retenção são decisão pendente (NEEDS_WILSON no checklist).

## 6. Ambiente local (Windows)

**Parar o `npm run dev` antes de `npm ci`.** O dev server segura o binário
nativo do `lightningcss` (`.node`) e o `npm ci` falha com `EPERM`/`EIO` ao
apagar `node_modules` (visto em 26/09/2026, `ci.md` §7). Sequência: parar o
dev server → `npm ci` → `npm run dev`.

## 7. O que esta rodada NÃO fez

- nenhuma mudança em produção (Supabase, Netlify, variáveis, deploy);
- nenhum segredo lido, criado ou gravado — chave só aparece como `<secret>`;
- nenhuma branch protection ligada no GitHub;
- nenhum merge, nenhum PR aberto, nenhum push;
- nenhum smoke em produção: P1–P6 são o roteiro, não um resultado.
