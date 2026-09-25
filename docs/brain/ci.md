# AGROTORK BRAIN — CI

> Dois workflows, duas perguntas. `brain.yml`: o banco sobe, migra, reverte
> e ingere? `brain-app.yml`: o código do BRAIN e o app que o consome
> continuam corretos, compilam e empacotam?

## 1. Os dois workflows

| Workflow | Job | Protege |
|---|---|---|
| `BRAIN` (`brain.yml`) | `deploy-reversao` | Banco, migrations, deploy/reversão, memória e ingestão (Postgres de serviço + worker Python) |
| `BRAIN App` (`brain-app.yml`) | `app-gates` | `src/modules/brain/**`, os imports compartilhados que ele puxa e o app Next inteiro |

Antes do `brain-app.yml`, um PR que mexesse só em `src/modules/brain/*.ts`
não rodava CI nenhum: o `brain.yml` filtra por `supabase/**`. Nomes de
workflow e de job são estáveis de propósito — branch protection vai
apontar para eles.

## 2. Quando cada um dispara

**`brain.yml`**: push em `brain/fase-1` e `brain/fase-2`; PR que toque
`supabase/**` ou `.github/workflows/brain.yml`; manual.

**`brain-app.yml`**: PR e push em `main`, os dois com os MESMOS caminhos;
manual.

```
src/**                                  tsconfig.json
supabase/db-tests/check-brain*.mjs      eslint.config.mjs
supabase/db-tests/conferir-ci-app.mjs   next.config.ts
package.json                            postcss.config.mjs
package-lock.json                       .github/workflows/brain-app.yml
```

Por que `src/**` inteiro: o módulo importa `src/lib/supabase/server.ts`,
`src/types/db.ts`, `src/config/permissions.ts` e `src/lib/auth/session.ts`,
e é consumido por `src/app/(app)/brain/brain-console.tsx`. Import é
transitivo; lista arquivo a arquivo esquece alguém. `src/**` custa rodadas
a mais e não tem buraco.

| Caso | Arquivo alterado | Filtro que casa | Roda? |
|---|---|---|---|
| PATH1 | `src/modules/brain/comparison.ts` | `src/**` | sim |
| PATH2 | `supabase/db-tests/check-brain-comparison.mjs` | `supabase/db-tests/check-brain*.mjs` | sim (em PR, o `brain.yml` também) |
| PATH3 | `package.json` | `package.json` | sim |
| PATH4 | `docs/x.md` | nenhum | não — de propósito |
| PATH5 | `.github/workflows/brain-app.yml` | ele mesmo | sim |
| PATH6 | `src/lib/auth/session.ts` | `src/**` | sim |

Em PR, push novo cancela a rodada velha; em `main`, nunca (`concurrency`).

## 3. Os gates, em ordem

Checkout → Node 22 (cache npm) → `npm ci` → **CI guard**
(`check:brain-ci`) → **BRAIN core** (`check:brain`) → **Answer validator**
(`check:brain-answer`) → **Provider adapter** (`check:brain-provider`) →
**BRAIN UI** (`check:brain-ui`) → **Comparison V1** (`check:brain-comparison`)
→ **ESLint** (`lint`) → **TypeScript** (`typecheck`) → **Next build** (`build`).

Barato antes de caro: guarda e suítes levam menos de um segundo cada e
apontam o erro exato antes de lint, typecheck e build, que levam dezenas
de segundos (o job inteiro, com `npm ci`, fica em torno de um minuto no
runner). Cada suíte é um step próprio — o nome do step vermelho já diz
qual.

**O contrato é o exit code.** Suíte com falha sai com 1 e o job fica
vermelho. Nada de conferir contagem fixa de asserções: foi assim que o CI
anterior ficou verde com teste quebrado. Nenhum `continue-on-error`,
nenhum `|| true`.

## 4. Sem provider real, sem segredo

- **Determinismo.** As suítes usam provedor falso: mesma entrada, mesmo
  veredito. Modelo real varia e transformaria CI em sorteio.
- **A chave é server-only.** O Preview do Netlify deliberadamente não
  recebe `BRAIN_LLM_API_KEY`, e o CI também não — o workflow não
  referencia `secrets` nenhum.

Nem as suítes nem o build precisam de variável de ambiente: `npm run build`
passa com env vazio (`CI=true`, `NEXT_TELEMETRY_DISABLED=1`).

## 5. Rodar local

```
npm run check:brain-all   # guarda + as cinco suítes; para no primeiro erro
npm run lint
npm run typecheck
npm run build
```

`check:brain-all` é conveniência local. O workflow não o usa: steps
separados deixam o vermelho legível.

## 6. Contrato para suíte nova `check:brain-*`

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
`check:brain-all`, que é agregador.

## 7. Versão do Node

`node-version: "22"`: LTS atual e o runtime em que o projeto é
desenvolvido e validado. Next 16 exige ≥ 20.9, e
`--experimental-strip-types` (usado pelas suítes) roda limpo no 22.22.

## 8. Dívida conhecida

- **Suítes moram em `supabase/db-tests/`** mas não precisam do banco. Não
  foram movidas de propósito: mudar caminho mexe em scripts, docs e
  filtros sem ganho de correção.
- **Diretórios temporários** `.brain-check-*`, `.answer-check-*`,
  `.ui-check-*`, `.comparison-check-*` nascem na raiz e são apagados por
  `rmSync`, mas não estão no `.gitignore`. Ficou assim nesta rodada.
- **Actions fixadas por tag de major** (`@v5`, `@v4`), não por SHA. Fixar
  por SHA é melhoria futura.
- **Branch protection com `paths`.** Se `app-gates` virar check
  obrigatório, um PR fora dos caminhos (só `docs/`, por exemplo) nunca
  recebe o status e trava em "Expected — Waiting for status". Na hora de
  ligar a proteção, decidir: tirar os `paths` (rodar sempre, ~1 min) ou um
  job-espelho que reporta sucesso quando nada relevante mudou. Não é desta
  rodada.
