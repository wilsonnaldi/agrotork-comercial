# AGROTORK BRAIN — CI

> Dois workflows, duas perguntas. `brain.yml`: o banco sobe, migra, reverte
> e ingere? `brain-app.yml`: o código do BRAIN e o app que o consome
> continuam corretos, compilam e empacotam?

## 1. Os dois workflows

| Workflow | Job | Papel |
|---|---|---|
| `BRAIN` (`brain.yml`) | `scope` | Decide pelo git se o diff toca banco, worker ou o próprio workflow (`db=true\|false`) |
| `BRAIN` (`brain.yml`) | `deploy-reversao` | Banco, migrations, deploy/reversão, memória e ingestão (Postgres de serviço + worker Python). Só roda com `db=true` |
| `BRAIN` (`brain.yml`) | `brain-db-gate` | Veredito final do banco; sempre reporta. **Check obrigatório** |
| `BRAIN App` (`brain-app.yml`) | `app-gates` | `src/modules/brain/**`, os imports compartilhados que ele puxa e o app Next inteiro. **Check obrigatório** |

Antes do `brain-app.yml`, um PR que mexesse só em `src/modules/brain/*.ts`
não rodava CI nenhum. Nomes de workflow e de job são estáveis de
propósito — a branch protection aponta para eles; renomear um job
obrigatório trava todo PR em "Expected".

## 2. Quando cada um dispara

Nenhum dos dois tem `paths` no gatilho. Todo PR recebe os dois vereditos.

**`brain-app.yml`**: todo PR; push em `main`; manual. O job roda inteiro
sempre (~1 min por PR, com `npm ci`). Não vale a pena economizar: o filtro
por caminho custava justamente o status fantasma da seção 3, e `src/**` já
pegava quase todo PR de código.

**`brain.yml`**: todo PR; push em `main`, `brain/fase-1` e `brain/fase-2`;
manual. O `scope` roda sempre (segundos) e o ensaio pesado só quando o
diff pede — regra na seção 4.

Em PR, push novo cancela a rodada velha; em `main`, nunca (`concurrency`,
nos dois workflows): cada merge precisa do seu veredito.

## 3. Checks obrigatórios (branch protection)

Em *Settings → Branches → main → Require status checks to pass*, marcar
exatamente estes dois:

| Check | Workflow | Por quê |
|---|---|---|
| `app-gates` | `BRAIN App` | Roda em todo PR, sem `if:`, sem `continue-on-error` |
| `brain-db-gate` | `BRAIN` | Sempre reporta (`if: always()`) e confere scope + ensaio juntos |

**Não** marcar `deploy-reversao` nem `scope`:

- **`deploy-reversao`**: job pulado por `if:` reporta **sucesso** para a
  branch protection. Se ele fosse o obrigatório, um `scope` quebrado que
  devolvesse `db=false` por engano aprovaria o PR sem ensaio nenhum. O
  gate não cai nisso: reprova se `scope` não concluiu, se `db` não é
  `true`/`false`, se `db=true` e o ensaio não passou, e se `db=false` e o
  ensaio **não** foi pulado.
- **`scope`**: diz só "rodar ou não"; passar nele não significa nada.

**Por que sem `paths`.** Check obrigatório de workflow filtrado por
caminho nunca reporta em PR fora do filtro (só `docs/`, por exemplo): o PR
fica em "Expected — Waiting for status" para sempre. Por isso o filtro do
banco saiu do gatilho e foi para dentro do workflow (`scope`), e o
`brain-app.yml` perdeu o filtro de vez.

**Merge queue.** Os dois workflows já têm o gatilho `merge_group:` (revisão
adversarial de 26/09): sem merge queue ele nunca dispara; com ela, sem o
gatilho, os checks obrigatórios nunca reportariam na fila. O `scope` trata o
evento como desconhecido — cai no `*)` do `case` e dá `db=true`, roda tudo
(CI9) —, que é o lado seguro.

`check:brain-ci` (seção 8) reprova se alguém devolver `paths` (ou qualquer
filtro) ao `pull_request:`, tirar o `if: always()` do gate, desligar o
`needs`/`if` do ensaio, puser `if:` ou `continue-on-error` onde não deve,
mexer no veredito do gate ou nas saídas do `scope`, usar
`pull_request_target`, ampliar ou redefinir `permissions`, referenciar
`secrets` ou interpolar `${{ }}` dentro de `run:` — lista completa na §8.

## 4. Detecção de mudança (`scope`)

Git nativo, sem action de terceiro:

1. Base: em PR, `github.event.pull_request.base.sha`; em push,
   `github.event.before`.
2. `git merge-base <base> HEAD` (checkout com `fetch-depth: 0`).
3. `git diff --no-renames --name-only -z <merge-base> HEAD` para um
   arquivo em `$RUNNER_TEMP`. `--no-renames` porque, com a detecção de
   rename (padrão do `git diff`), um arquivo MOVIDO de `supabase/` para fora
   aparecia só com o nome novo, fora do filtro, e o ensaio era pulado
   (revisão adversarial de 26/09, CI8). Sem ela, o nome antigo sai como
   removido e casa o filtro.
4. `db=true` se algum caminho casar
   `^(supabase/|brain/|\.github/workflows/brain\.yml$)`; senão `db=false`.

Na dúvida, roda tudo (`db=true`): `workflow_dispatch`, `merge_group` ou
evento desconhecido, base que não é um SHA de 40 hex, `before` só com zeros
(branch nova), base fora do histórico (force-push) ou sem merge-base.
Errar para o lado caro, nunca para o lado que pula o ensaio.

**Por que nome de arquivo nunca chega no shell.** O contexto do evento
entra só por `env:` — nada de `${{ }}` dentro do `run:`, que viraria texto
do script antes de rodar. A lista de arquivos vai para um arquivo
NUL-separado e só é lida pelo `grep -z`; o que sai para
`$GITHUB_OUTPUT` é só `db=true|false`. Um arquivo chamado
`docs/$(touch pwned).md` é dado, não comando. Arquivo, e não pipe: com
`pipefail`, o `grep -q` fechando cedo daria SIGPIPE no `git diff` e um
falso "não mudou".

Simulação local (repo git descartável, PR montado como o GitHub monta o
merge ref, 26/09/2026):

| Caso | Diff | `db` |
|---|---|---|
| CI1 | só `docs/` | `false` |
| CI2 | `supabase/migrations/*.sql` (PR e push em main) | `true` |
| CI3 | `supabase/db-tests/*` | `true` |
| CI4 | `brain/worker/*.py` | `true` |
| CI5 | `.github/workflows/brain.yml` | `true` |
| CI6 | só `package.json` + `README.md` (PR e push) | `false` |
| CI7 | `before` só zeros · base fora do histórico · base inválida · `workflow_dispatch` | `true` (todos) |
| CI7 | `docs/$(touch pwned).md`, nome com `` ` `` e com quebra de linha | `false`, nenhum `pwned` criado |
| CI8 | `git mv supabase/migrations/001.sql archive/001.sql` (PR e push) · `git mv brain/worker/w.py tools/w.py` · `git rm` de migration | `true` (todos; sem `--no-renames` os dois `git mv` davam `false`) |
| CI9 | `merge_group` | `true` (cai no `*)`) |

Rodada de novo em 26/09, depois do `--no-renames`, com o bloco `run:` do
`scope` extraído do próprio `brain.yml`: CI1–CI7 com o mesmo resultado da
tabela, CI8 e CI9 como acima.

## 5. Os gates do `app-gates`, em ordem

Checkout → Node 22 (cache npm) → `npm ci` → **CI guard**
(`check:brain-ci`) → **BRAIN core** (`check:brain`) → **Answer validator**
(`check:brain-answer`) → **Provider adapter** (`check:brain-provider`) →
**BRAIN UI** (`check:brain-ui`) → **Comparison V1** (`check:brain-comparison`)
→ **Synthesis state machine** (`check:brain-synthesis`) → **ESLint** (`lint`)
→ **TypeScript** (`typecheck`) → **Next build** (`build`).

Barato antes de caro: guarda e suítes levam menos de um segundo cada e
apontam o erro exato antes de lint, typecheck e build, que levam dezenas
de segundos (o job inteiro, com `npm ci`, fica em torno de um minuto no
runner). Cada suíte é um step próprio — o nome do step vermelho já diz
qual.

**O contrato é o exit code.** Suíte com falha sai com 1 e o job fica
vermelho. Nada de conferir contagem fixa de asserções: foi assim que o CI
anterior ficou verde com teste quebrado. Nenhum `continue-on-error`,
nenhum `|| true`.

## 6. Sem provider real, sem segredo

- **Determinismo.** As suítes usam provedor falso: mesma entrada, mesmo
  veredito. Modelo real varia e transformaria CI em sorteio.
- **A chave é server-only.** O Preview do Netlify deliberadamente não
  recebe `BRAIN_LLM_API_KEY`, e o CI também não — nenhum dos dois
  workflows referencia `secrets.` (o `check:brain-ci` reprova se aparecer).
  O checkout usa `persist-credentials: false`: o token do job não fica
  gravado no `.git/config` do runner.

Nem as suítes nem o build precisam de variável de ambiente: `npm run build`
passa com env vazio (`CI=true`, `NEXT_TELEMETRY_DISABLED=1`).

`npm run brain:preflight` (conferência da configuração do provedor) é
**manual e local, não é step de CI** — o nome não começa com `check:brain`
de propósito, para a guarda não exigi-lo no workflow. Ver
[`env-contract.md`](env-contract.md).

## 7. Rodar local

```
npm run check:brain-all   # guarda + as seis suítes; para no primeiro erro
npm run lint
npm run typecheck
npm run build
```

`check:brain-all` é conveniência local. O workflow não o usa: steps
separados deixam o vermelho legível.

Cada suíte copia os módulos para um diretório temporário na raiz
(`.brain-check-*`, `.answer-check-*`, `.provider-check-*`, `.ui-check-*`,
`.comparison-check-*`, `.synthesis-check-*`, `.nfe-check-*` — na raiz para
o import achar `node_modules`). Ele é apagado ao fim **mesmo se a suíte
explodir no meio** (`process.on("exit")` logo após o `mkdtempSync`; a de
síntese usa `try/finally`), e os padrões estão no `.gitignore` para o caso
de um `kill -9` deixar sobra.

### Ambiente local

- **Windows: parar o `npm run dev` antes de `npm ci`.** O dev server
  mantém aberto o binário nativo do `lightningcss` (`.node`), e o `npm ci`
  falha com `EPERM`/`EIO` ao tentar apagar `node_modules` (visto em
  26/09/2026). Parar o dev server, rodar `npm ci`, subir de novo.

## 8. Contrato para suíte nova `check:brain-*`

1. **package.json** — script `check:brain-<nome>`.
2. **workflow** — step `run: npm run check:brain-<nome>` em
   `brain-app.yml` (e entra no `check:brain-all`).
3. **Rodar local** — passa em `npm run check:brain-all`.
4. **Determinístico** — sem rede, sem banco, sem env; falha = exit 1.
5. **Sem segredo real** — provedor falso, nenhuma chave.

O passo 2 não depende de memória: `check:brain-ci`
(`supabase/db-tests/conferir-ci-app.mjs`) lista todo script `check:brain*`
do `package.json` e exige a linha `run: npm run <nome>` exata no workflow —
`check:brain` não é satisfeito por `check:brain-answer`, e `|| true` no fim
reprova. Esqueceu o step, o próprio CI fica vermelho. Única exceção:
`check:brain-all`, que é agregador — e a guarda também exige que toda
suíte apareça nele como `npm run <nome>` (comando a comando, separado por
`&&`), para o "rodar local" não ficar menor que o CI.

Além das suítes, a mesma guarda confere as regras de workflow da seção 3.
Endurecida na revisão adversarial de 26/09 — continua **texto puro, sem
parser de YAML** —, com duas regras de leitura: comentário YAML (linha
inteira ou ` #…` no fim) não conta, então `workflow_dispatch: # not
pull_request_target` não reprova; e o conteúdo de um bloco `run: |` é lido
**cru**, porque o Actions interpola `${{ }}` antes do shell, inclusive numa
linha de comentário do shell.

| Onde | Regra |
|---|---|
| os dois | `pull_request:` e `merge_group:` presentes, sozinhos na linha e **sem filho** (nada de `paths`, `branches`, `types`, nem forma de fluxo `{…}`) |
| os dois | sem `pull_request_target` |
| os dois | uma única `permissions:`, no topo, com exatamente `contents: read`; nenhuma no nível de job (ali ela substitui a do topo) |
| os dois | nenhuma menção a `secrets` (`secrets.X`, `secrets['X']`, `toJSON(secrets)`) |
| os dois | nenhum `${{` dentro de `run:` (contexto só por `env:`) |
| `brain-app.yml` | sem `paths`, sem `continue-on-error`, sem `if:`; `run: npm run lint`, `typecheck` e `build` como linhas exatas (sem `\|\| true`) |
| `brain.yml` | job `scope`; `deploy-reversao` com `needs: scope` e `if: needs.scope.outputs.db == 'true'`; `brain-db-gate` com `if: always()` e `needs: [scope, deploy-reversao]` |
| `brain.yml` | sem `continue-on-error`; só dois `if:` no arquivo, exatamente os dois acima |
| `brain.yml` | veredito do gate fixado linha a linha (`SCOPE` = success; `true)` exige `success`; `false)` exige `skipped`; `*)` reprova) e o `env:` `SCOPE`/`DB`/`HEAVY` ligado a `needs.*` |
| `brain.yml` | `scope` escreve `db=true` e `db=false`, o `*)` do evento chama `heavy`, o diff usa `--no-renames`, e o output `db` vem do step |

Teste de mutação (26/09, fora do repositório): 34 cópias dos workflows e do
`package.json`, cada uma com uma alteração que abriria um buraco (`paths`,
`types:`, `pull_request: {paths: …}`, `pull_request` removido,
`continue-on-error`, `if:` extra, `permissions` no job ou ampliada,
`read-all`, `secrets.K`, `secrets['X']`, `toJSON(secrets)`, `${{ }}` num
`run:` e num comentário dentro dele, `|| true` no veredito ou no lint,
`skipped`→`success`, `HEAVY` constante, `scope` sempre `false`, sem
`--no-renames`, evento desconhecido virando leve, build trocado, suíte fora
do agregador, sem `merge_group`): as 34 reprovam. Controles aprovados: os
arquivos reais, `workflow_dispatch: # not pull_request_target`, comentário
depois de `pull_request:`, e os dois workflows em CRLF.

Saída: uma linha `✓` por conferência e o total no fim.

## 9. Versão do Node e actions fixadas

`node-version: "22"`: LTS atual e o runtime em que o projeto é
desenvolvido e validado. Next 16 exige ≥ 20.9, e
`--experimental-strip-types` (usado pelas suítes) roda limpo no 22.22.

**Actions fixadas por SHA de commit**, com a versão em comentário. Tag pode
ser movida por quem controla o repositório da action; SHA não.

| Action | Versão | SHA |
|---|---|---|
| `actions/checkout` | v5.1.0 | `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` |
| `actions/setup-node` | v4.4.0 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/setup-python` | v5.6.0 | `a26af69be951a213d495a4c3e4e4022e16d87065` |

Conferir (tags leves: o SHA da tag é o próprio commit):

```
git ls-remote --tags https://github.com/actions/checkout | grep v5.1.0
git ls-remote --tags https://github.com/actions/setup-node | grep v4.4.0
git ls-remote --tags https://github.com/actions/setup-python | grep v5.6.0
```

Para atualizar: trocar SHA **e** comentário juntos, conferindo com o mesmo
comando. Os majors ficaram onde estavam (checkout v5, setup-node v4,
setup-python v5) — subir major é mudança separada.

## 10. Dívida conhecida

- **Suítes moram em `supabase/db-tests/`** mas não precisam do banco. Não
  foram movidas de propósito: mudar caminho mexe em scripts, docs e
  filtros sem ganho de correção.
- **`setup-node@v4` e `setup-python@v5` rodam em node20**, que o GitHub
  está aposentando nos runners. Hoje funcionam; quando o aviso de
  deprecação virar erro, subir para o major seguinte (mudança à parte,
  com o mesmo procedimento de SHA da seção 9).
- **`if: always()` no gate** também roda quando a rodada é cancelada
  (push novo no PR): esse gate cancelado reprova, mas é da rodada velha —
  o commit novo recebe o seu próprio veredito.
