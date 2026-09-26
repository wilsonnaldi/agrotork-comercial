# AGROTORK BRAIN — Matriz de readiness de produção

> 26/09/2026. Uma linha por item, com a evidência no repositório. O passo a
> passo está em [`production-readiness.md`](production-readiness.md).
> **Ação humana nunca é READY**: READY significa que a parte do código/doc
> está pronta e provada; o que depende de painel, conta ou decisão é
> NEEDS_WILSON.

| Estado | Significa |
| --- | --- |
| **READY** | pronto no repositório, com teste ou evidência; nada a fazer antes da produção |
| **NEEDS_WILSON** | depende de decisão, acesso ou ação do Wilson |
| **BLOCKED_EXTERNAL** | depende de terceiro (fornecedor, distribuidor) |
| **DEFERRED** | conhecido, registrado, fora desta entrada em produção |
| **NOT_REQUIRED** | não é condição para ligar o Answer v1 em produção |

## Matriz

| Item | Estado | Evidência | O que falta | Quem |
| --- | --- | --- | --- | --- |
| PR #7 mergeado | NEEDS_WILSON | branch `hardening/brain-answer-v1-closure` em `98a80b0`, 10 commits sobre `main` `d80ae65`; aberto em 26/09 | merge depois de `app-gates` e `deploy-reversao` verdes | Wilson |
| PR desta branch mergeado | NEEDS_WILSON | `hardening/brain-production-readiness`, 7 commits sobre `98a80b0` | abrir PR depois do PR #7; merge com `app-gates` e `brain-db-gate` verdes | Wilson |
| CI da aplicação seguro como check obrigatório | READY | `brain-app.yml` sem `paths`, sem `if:`/`continue-on-error` no `app-gates` (commit `ecac757`); `check:brain-ci` trava essas regras (`conferir-ci-app.mjs`); `ci.md` §2–3 | vale em `main` só depois do merge; primeira rodada no GitHub não conferida daqui | — |
| CI do banco seguro como check obrigatório | READY | `brain.yml`: `scope` (git diff contra o merge-base, na dúvida `db=true`) + `brain-db-gate` com `if: always()` (commit `ecac757`); simulação local CI1–CI7 (`ci.md` §4) | idem: vale em `main` depois do merge; rodada real no GitHub não conferida daqui | — |
| Nomes dos checks obrigatórios | READY | `app-gates` (`BRAIN App`) e `brain-db-gate` (`BRAIN`); não `deploy-reversao`, não `scope` — `ci.md` §3 | — | — |
| Branch protection ligada | NEEDS_WILSON | configuração do GitHub, não visível no repositório | ligar depois do merge desta branch e de uma rodada dos workflows novos | Wilson (admin do repo) |
| Actions fixadas por SHA | READY | `checkout` v5.1.0, `setup-node` v4.4.0, `setup-python` v5.6.0 por SHA, `persist-credentials: false` (commit `ecac757`, `ci.md` §9) | — | — |
| Contrato de configuração do provedor | READY | `readProviderConfig` (`llm/config.ts`), `resolveProvider` → `{ provider, reason }`; `npm run brain:preflight` (exit 0/1/2); CFG1–CFG15, PF1–PF6, SYN34a–f (commit `56de30e`); `env-contract.md` | — | — |
| Variáveis do provedor em Production | NEEDS_WILSON | `env-contract.md` §2 e §7; preflight local em 26/09: exit 1 (não configurado, esperado) | provedor + modelo + orçamento aprovados; 3 variáveis no painel, só Production, escopo de servidor | Wilson |
| Preview sem segredo | NEEDS_WILSON | parte do repo pronta: nenhum workflow usa `secrets.` (`check:brain-ci`), Preview deliberadamente sem chave (`env-contract.md` §2) | conferir no painel que as 3 variáveis não têm valor em Deploy Preview / branch deploy | Wilson |
| Timeout da função Netlify vs 30 s do provedor | NEEDS_WILSON | `TIMEOUT_PROVIDER_MS = 30_000` (`limits.ts`, E12); `netlify.toml` não fixa timeout; `env-contract.md` §6 | confirmar no painel que a função dura mais que busca + 30 s (~40 s) | Wilson |
| Logs estruturados de outcome | READY | `GenerationEvent` tipado, sem `query` (commit `fc489a4`); privacidade OBS1–OBS13 (`d86332f`, `56de30e`); LOG1–LOG8b | — | — |
| Destino e retenção da observabilidade | NEEDS_WILSON | hoje só `console.info` no log de função da Netlify; nenhum agregador no repo | decidir se a retenção do painel basta ou se haverá destino permanente (só decisão) | Wilson |
| Rollback da síntese | READY | `BRAIN_LLM_PROVIDER=none` + redeploy → `no_provider:provider_disabled`; SYN34b, CFG3c; `production-readiness.md` §4 | executar só se preciso; confirmar no painel se mudança de variável exige redeploy (doc assume que sim) | Wilson, quando preciso |
| Plano de smoke | READY | P1–P6 com resposta e evento esperados (`production-readiness.md` §3) | — | — |
| Smoke executado em produção | NEEDS_WILSON | nada executado | rodar P1–P6 depois do deploy com provedor | Wilson |
| Ambiente local Windows (`npm ci`) | NEEDS_WILSON | `ci.md` §7: `EPERM`/`EIO` com dev server aberto (26/09) | parar `npm run dev`, rodar `npm ci` | Wilson |
| Bucket `brain-documents` | NEEDS_WILSON | não criado; migration `20260912030000` só aplica as policies; roteiro `supabase/operacao/07-…` pronto e não rodado (`fase-2-consolidado.md` §4) | decisão Free × Pro (Free limita upload a 50 MB; V41 tem 177 MB) | Wilson (+ Supabase, plano) |
| Link de citação para o Storage | DEFERRED | `[n]` mostra fonte/documento/versão/página como texto, sem `href` (gap register) | depende do bucket | — |
| Governança DJI | BLOCKED_EXTERNAL | tecnicamente pronto (golden 9/9, 16/16, final 10/10); nenhum PDF declara a própria versão (`fase-2-dji-governanca.md`) | ALLCOMP confirmar rótulos V14.11/V15.1/V16.2, vigências e se a V16.2 é a vigente | ALLCOMP, via Wilson |
| Fonte JR Soluções | NEEDS_WILSON | 9 linhas perdidas por cabeçalho fundido no PDF (`fase-2-jr-solucoes.md` §12) | PDF sem sobreposição ou regerado da planilha | Wilson |
| Contrato Compusystem | BLOCKED_EXTERNAL | sem API pronta, sem acesso ao banco (`fase-2-consolidado.md` §8; `CLAUDE.md` regra 6) | Bloco A do contrato (URL, autenticação, limites, paginação) | Compusystem, via Wilson |
| pgvector / Lote C | DEFERRED | não instalado; RRF FTS + trigram + código responde o golden (`fase-2-consolidado.md` §5) | medir quando houver pergunta que FTS + trigram erre | — |
| Deprecação node20 (`setup-node@v4`, `setup-python@v5`) | DEFERRED | `ci.md` §10 | subir major quando o aviso virar erro (mesmo procedimento de SHA) | — |
| Supply chain: `requirements.txt` sem hashes | DEFERRED | `brain/worker/requirements.txt` usa faixas (`>=`), sem `--require-hashes`; instalado no `deploy-reversao` | lock com hashes numa rodada de hardening | — |

## NEEDS_WILSON

### 1. Merge do PR #7, depois o PR desta branch

- **AÇÃO:** mergear o PR #7 em `main`; em seguida abrir e mergear o PR de
  `hardening/brain-production-readiness`.
- **POR QUÊ:** esta branch nasce da cabeça do PR #7 (`98a80b0`); fora de
  ordem, o PR dela arrasta os 10 commits do #7 junto.
- **RISCO:** baixo. Nenhum dos dois liga a síntese: sem as variáveis, a
  produção segue extractiva. O merge dispara deploy de produção de código.
- **PASSO EXATO:** PR #7 → conferir `BRAIN App / app-gates` e `BRAIN /
  deploy-reversao` verdes → merge. Depois: PR da branch contra `main` →
  conferir `app-gates`, `scope`, `deploy-reversao`, `brain-db-gate` verdes →
  merge.
- **VALIDAÇÃO:** em `main`, os workflows rodam no push; `brain-db-gate` e
  `app-gates` verdes no commit de merge. Console do BRAIN em produção
  responde P1 extractiva (sem provedor).
- **ROLLBACK:** *Revert* do PR (ou `git revert -m 1 <merge>` + PR). Nunca
  force push.

### 2. Provedor, modelo e orçamento

- **AÇÃO:** aprovar o provedor (o código suporta `anthropic`), escolher o
  identificador do modelo e fixar orçamento/limite na conta do provedor.
- **POR QUÊ:** é a única coisa entre o código pronto e a resposta redigida
  em produção; é decisão comercial e de custo.
- **RISCO:** custo sem teto se o limite não for posto no provedor.
  Conteúdo: só sai o que passa no gate de processamento externo
  (ARAG é `forbidden`).
- **PASSO EXATO:** decidir; anotar o identificador do modelo; configurar o
  limite de gasto no painel do provedor.
- **VALIDAÇÃO:** decisão registrada; limite visível no painel do provedor.
- **ROLLBACK:** não se aplica (decisão); o desligamento técnico é o item 3.

### 3. Variáveis em Production na Netlify + timeout da função

- **AÇÃO:** cadastrar as 3 variáveis só no contexto Production, escopo de
  servidor; confirmar o timeout das funções.
- **POR QUÊ:** liga a síntese. O timeout precisa cobrir busca + 30 s, senão a
  função morre antes do fallback extractivo.
- **RISCO:** chave em Preview (código de PR com credencial) ou com
  `NEXT_PUBLIC_` (chave no navegador); timeout curto (erro genérico em vez de
  trechos).
- **PASSO EXATO:** `npm run brain:preflight -- --contract` para os nomes →
  no painel, Production: `BRAIN_LLM_PROVIDER=anthropic`,
  `BRAIN_LLM_MODEL=<modelo>`, `BRAIN_LLM_API_KEY=<secret>` → conferir que
  nenhuma tem valor em Deploy Preview/branch deploy e que não existe
  `NEXT_PUBLIC_BRAIN_LLM*` → conferir o timeout das funções (≥ ~40 s) →
  redeploy de produção → smoke P1–P6 (`production-readiness.md` §3).
- **VALIDAÇÃO:** P1 com `outcome: "answered"` e `provider: "anthropic"`; P4
  e P6 com `provider: null`; nenhum `no_provider` depois do deploy.
- **ROLLBACK:** `BRAIN_LLM_PROVIDER=none` (ou remover) + redeploy → log
  `no_provider:provider_disabled` (§4 do runbook).

### 4. Branch protection em `main`

- **AÇÃO:** exigir PR e os checks `app-gates` e `brain-db-gate`.
- **POR QUÊ:** sem a regra, nada impede merge com CI vermelho. Se já existe
  alguma regra no GitHub, não é visível pelo repositório.
- **RISCO:** ligar antes do merge desta branch trava PR só de `docs/` em
  "Expected — Waiting for status" (workflows antigos com `paths`); marcar
  `deploy-reversao` deixaria passar PR sem ensaio (job pulado = sucesso).
- **PASSO EXATO:** depois do item 1 e de uma rodada dos workflows em `main`
  → *Settings → Branches → main* → exigir pull request; exigir status checks
  `app-gates` e `brain-db-gate` (só esses); force push e exclusão desligados.
- **VALIDAÇÃO:** PR de teste só com `docs/` mostra os dois checks e fica
  mergeável quando verdes; `brain-db-gate` verde com `deploy-reversao`
  pulado.
- **ROLLBACK:** desmarcar a regra no mesmo painel.

### 5. Destino e retenção da observabilidade

- **AÇÃO:** decidir se a retenção dos logs de função da Netlify basta ou se
  haverá destino permanente para `[brain.synthesis]`.
- **POR QUÊ:** as contagens do §5.4 do runbook só valem pelo período que o
  log fica guardado; a retenção depende da conta e não está no repositório.
- **RISCO:** baixo; o evento não carrega pergunta nem conteúdo (OBS1–OBS13),
  então mandar para outro destino não expõe dado de cliente.
- **PASSO EXATO:** conferir no painel onde ficam e por quanto tempo os logs
  de função; decidir. Só decisão nesta fase — nada a implementar.
- **VALIDAÇÃO:** decisão registrada no gap register.
- **ROLLBACK:** não se aplica.

### 6. Bucket Supabase `brain-documents`

- **AÇÃO:** decidir Free × Pro e, com um "pode", criar o bucket pelo roteiro
  `supabase/operacao/07-criar-bucket-brain-documents.sql`.
- **POR QUÊ:** as versões ativas apontam para caminhos que não existem; sem
  bucket não há link de citação para a página nem reingestão do Magnojet com
  o arquivo guardado.
- **RISCO:** custo (plano); Free limita upload a 50 MB e o Magnojet V41 tem
  177 MB (`fase-2-consolidado.md` §4). Não bloqueia o Answer v1: busca e
  citação funcionam sem ele.
- **PASSO EXATO:** decidir o plano → ajustar `v_limite` no roteiro 07 →
  autorizar a aplicação em produção (`CLAUDE.md` regra 1).
- **VALIDAÇÃO:** bucket privado existe; as 4 policies da migration
  `20260912030000` passam a valer sobre ele.
- **ROLLBACK:** pelo próprio roteiro/painel, antes de qualquer upload.

### 7. Governança DJI (ALLCOMP)

- **AÇÃO:** obter da ALLCOMP os rótulos corretos (V14.11/V15.1/V16.2), a
  vigência de cada uma e se a V16.2 é a vigente hoje.
- **POR QUÊ:** nenhum dos 3 PDFs declara a própria versão; o rótulo hoje
  viria só do nome do arquivo (`fase-2-dji-governanca.md`).
- **RISCO:** alto se ingerido sem confirmação (versão ou vigência errada
  vira resposta errada citada).
- **PASSO EXATO:** enviar as três perguntas à ALLCOMP; repassar a resposta.
- **VALIDAÇÃO:** resposta por escrito, com data.
- **ROLLBACK:** não se aplica (nada é ingerido antes).

### 8. Fonte JR Soluções

- **AÇÃO:** conseguir um PDF da tabela JR sem sobreposição, ou regerado da
  planilha de origem.
- **POR QUÊ:** 9 linhas se perdem porque o único cabeçalho real está fundido
  com linhas de produto (`fase-2-jr-solucoes.md` §12); o motor não pode
  adivinhar o conteúdo.
- **RISCO:** baixo; o lote está fora de produção.
- **PASSO EXATO:** pedir o arquivo novo; entregar para o ensaio local.
- **VALIDAÇÃO:** ensaio JR sem linha engolida (tabelas `trusted` completas).
- **ROLLBACK:** não se aplica.

### 9. Contrato Compusystem

- **AÇÃO:** obter o Bloco A do contrato de integração (URL base por
  ambiente, autenticação, limites, paginação).
- **POR QUÊ:** `CLAUDE.md` regra 6 — sem a documentação, nada de schema,
  coluna ou credencial de integração.
- **RISCO:** nenhum imediato; médio prazo, o BRAIN segue isolado do ERP.
- **PASSO EXATO:** cobrar a Compusystem pelo documento
  (`docs/integracoes/compusystem-contrato-integracao.md`).
- **VALIDAÇÃO:** documento recebido.
- **ROLLBACK:** não se aplica.

### 10. `npm ci` local no Windows

- **AÇÃO:** reinstalar as dependências no PC.
- **POR QUÊ:** um `npm ci` abortado em 26/09 deixou o `node_modules` local
  parcialmente removido; com o dev server aberto, o `npm ci` falha com
  `EPERM`/`EIO` no binário do `lightningcss` (`ci.md` §7).
- **RISCO:** baixo; só o ambiente local.
- **PASSO EXATO:** parar o `npm run dev` → `npm ci` → `npm run dev`.
- **VALIDAÇÃO:** `npm ci` termina sem erro; `npm run check:brain-all` passa.
- **ROLLBACK:** não se aplica (repetir o `npm ci`).
