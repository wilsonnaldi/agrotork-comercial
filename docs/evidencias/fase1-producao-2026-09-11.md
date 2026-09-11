# AGROTORK BRAIN — Fase 1 em produção, modo desacoplado

Projeto Supabase `nedmdkdhchkadijtdnja` · PostgreSQL 17.6 · 11/09/2026, 19:36–19:47 UTC.
Tudo abaixo foi medido em produção por consulta, não deduzido. Onde um item não foi
executado, está dito.

## Veredito

**FASE 1 CONCLUÍDA EM PRODUÇÃO — MODO DESACOPLADO**

## 1. Commit implantado, CI e hashes

| Item | Valor |
|---|---|
| Roteiro executado | `supabase/operacao/02-aplicar-brain.sql` **do commit `8571a9f`** (publicado no GitHub em `brain/fase-1`) |
| md5 do arquivo | `da95ef7d03606ecba5c8c58edddc4d35` — 214 718 bytes, zero CR |
| md5 do miolo (entre `begin;` e `commit;`) | `053597f21459731bdcc4a347d7f7584b` — 211 581 bytes, igual ao ensaio local |
| `05-agendar-reconciliacao.sql` | md5 `84ae4fc640acb67b98b5a0e4701c49cc` |
| Commits posteriores (só testes/CI/correção futura; **o SQL do roteiro 02 é byte-idêntico em `8571a9f`, `60c0975` e `ec2e3ea`**) | `60c0975` here-string no lugar de `echo \| grep -q` (SIGPIPE, o vermelho do CI em D3) · `ec2e3ea` policy de `brain.channels` + suíte 32 (**não aplicada em produção**) |
| CI conhecido | run 34636499904 em `8571a9f`: deploy/reversão/idempotência/CRLF verdes, **vermelho em D3 por "Broken pipe"** — falso negativo do teste, reproduzido e corrigido em `60c0975` |
| CI verde em `60c0975`/`ec2e3ea` | **NÃO OBTIDO**: o push desta sessão está bloqueado pelo proxy (repositório fora do conjunto autorizado). Bundle incremental entregue em `Downloads` |

Como o roteiro chegou a produção: a extensão `http` (pgsql-http 1.6) foi habilitada por
alguns minutos, produção **baixou o arquivo direto do GitHub pelo SHA do commit**, conferiu
os dois md5 acima dentro de um bloco `do`, extraiu o miolo e o executou num único
`execute` — uma transação só, sem nenhum byte digitado à mão. A extensão foi removida em
seguida; a lista de extensões voltou exatamente à de antes
(`pg_cron 1.6.4, pg_stat_statements 1.11, pg_trgm 1.6, pgcrypto 1.3, plpgsql 1.0,
supabase_vault 0.3.1, unaccent 1.1, uuid-ossp 1.1`). Este caminho foi ensaiado antes em
PostgreSQL 17.6 local com ERP previamente povoado (1 orçamento, 2 pedidos): mesmo
resultado `10|3|0|9|0`.

## 2. Gate pós-deploy (exigido: 10 / 3 / 0 / 9 / 0)

| Medida | Produção |
|---|---|
| `information_schema.tables` em `brain` | **10** (9 tabelas + 1 view `journey_entries`) |
| gatilhos `trg_brain*` | **3** |
| gatilhos habilitados | **0** |
| nove versões, por lista explícita (`20260911130000` … `20260911210000`) | **9** |
| `brain.divergencias_erp()` | **0** |
| `public.audit_capture()` | `ee2f5cd583295c30fbe64eb81eec2d9e` (esperado pós-deploy) |
| funções em `brain` | 37, nenhuma com `\r` no corpo; todas `search_path=""`; nenhuma `immutable` indevida |
| eventos em `brain.events` | 3 — o orçamento `ORC-2026-0001` e os pedidos `PED-2026-0001/0002` reais, reconciliados |
| resíduo de teste | 0 leads/oportunidades/tarefas/identidades/interações; produto `FUMACA-DEPLOY` ausente |
| ERP | 1 orçamento, 2 pedidos, 112 produtos — como antes |

## 3. Produção × migrations do commit

Retrato comparável (`supabase/db-tests/retrato-brain.sql`: 38 definições de função, tabelas,
colunas, policies, índices, gatilhos com estado, constraints):

- produção: `fe11b0c2d7583457a1306664a60e3586`
- banco local construído das mesmas nove migrations: `fe11b0c2d7583457a1306664a60e3586`

Idênticos. Detalhe: 9 tabelas com RLS, 27 policies, 48 índices, 68 constraints, 11 enums,
view `journey_entries` com `security_invoker=true`, `anon` sem USAGE no schema e sem
nenhum grant em tabela ou função.

## 4. As três pontes, uma a uma

| Gatilho | Tabela | `tgenabled` |
|---|---|---|
| `trg_brain_quotes` | `public.quotes` | `D` (desabilitado) |
| `trg_brain_orders_created` | `public.orders` | `D` |
| `trg_brain_orders` | `public.orders` | `D` |

Fluxo em vigor: ERP → COMMIT → cron → `reconciliar_erp()` → BRAIN. Nenhum código do
BRAIN dentro da transação comercial.

## 5. pg_cron

`cron.job` id 2, `brain-reconciliar`, `* * * * *`, ativo, `postgres`, comando
`select brain.reconciliar_erp_periodico();`. Um único job com esse nome; o roteiro 05
remove o anterior antes de criar (D14 no ensaio prova que rodar de novo não duplica).

Execuções reais (`cron.job_run_details`): runs 11–15, 19:39 → 19:43, todas `succeeded`,
17–29 ms cada. O `return_message` do pg_cron só diz "1 row"; por isso a validação
funcional: `brain.reconciliar_erp_periodico()` chamado diretamente devolve **0** (não -1),
e os logs do Postgres no período trazem `cron job 2 starting` a cada minuto e **um único**
`[brain-reconciliacao] falhou`, exatamente às 19:43:02 — o da falha forçada da seção 8,
dentro da minha transação, não do cron.

## 6. Reconciliação idempotente

Segunda execução de `brain.reconciliar_erp()` com o banco já reconciliado:
`evento_ausente=0, estagio_atrasado=0, venda_nao_ganha=0, venda_desfeita=0,
pedido_nao_ligado=0, lead_nao_convertido=0`. Eventos continuam 3. Divergências 0.

## 7. Caso real controlado, observado pelo cron

| Hora (UTC) | Fato |
|---|---|
| 19:40:25 | ERP cria `ORC-2026-0003` (draft, pontes desligadas) e **confirma** |
| 19:40:32 | BRAIN ainda com 3 eventos; `divergencias_erp()` = `evento_ausente:quote:ORC-2026-0003`; última execução do cron 19:40:00 |
| 19:41:00 | cron run 13 (27 ms) |
| 19:41:29 | BRAIN com 4 eventos; evento id 6 = `quote.created`, `source=erp`, `status=draft`, `occurred_at` = criação do orçamento, `reconciliado_em` = 19:41:00.07; divergências **0** |
| 19:41:51 | Limpeza, numa transação: só o evento do teste removido (pelo mesmo caminho da fumaça do deploy, trigger de imutabilidade desligado e religado); orçamento removido; retrato dos 3 eventos reais conferido igual antes/depois |

Trilha de auditoria preservada em `public.audit_log`: `quote.created` e `quote.deleted`
de `ORC-2026-0003`, ator `system`/`postgres`. Nenhum dado comercial legítimo tocado.

## 8. Falha forçada — a propriedade do modo desacoplado

Numa única transação: `brain.divergencias_erp()` renomeada (quebrando a reconciliação) →
wrapper do cron devolveu **-1** sem exceção → ERP criou `ORC-2026-0004` e a atualizou
normalmente → função restaurada → orçamento de teste removido → wrapper voltou a
devolver **0** → eventos 3/3, divergências 0, ERP 1/2. Nada disso ficou visível fora da
transação: o cron continuou verde nos minutos seguintes. Não sobrou função
`*_quebrada`.

## 9. Advisors × baseline (medido antes e depois)

Segurança: **idênticos** — 3 INFO `rls_enabled_no_policy` (tabelas de sequência do ERP),
1 WARN `anon` executa `get_shared_quote` (intencional: link público), 23 WARN RPCs
`security definer` para `authenticated` (intencionais, todas em `public`),
1 WARN proteção de senha vazada desligada (Auth). **Nenhum aviso novo do BRAIN**: o
schema não está na Data API e nada é executável por `anon`.

Desempenho:

| Aviso | Antes | Depois | Classificação |
|---|---|---|---|
| INFO `unindexed_foreign_keys` | 33 | 55 (+22 em `brain`: `created_by/updated_by/actor_id/channel_key/…`) | mesmo padrão já aceito no ERP; melhoria futura |
| INFO `unused_index` | 36 | 59 (+23 em `brain`) | esperado — schema recém-criado, sem tráfego |
| **WARN `multiple_permissive_policies`** | 0 | **1**: `brain.channels`, `authenticated`, SELECT: `{channels_admin_write, channels_select}` | **novo, causado pelo BRAIN — investigado**: `for all` inclui SELECT; sem vazamento (`is_admin` ⊂ `is_active_user`), só avaliação dupla numa tabela de 12 linhas. Correção pronta e testada em `ec2e3ea` (`20260911220000`, suíte 32), **não aplicada** nesta rodada para não alterar o estado recém-validado; entra no próximo lote |

## 10. Regressão do ERP

| Item | Situação | Evidência |
|---|---|---|
| Orçamento → itens → enviado → aprovado → pedido | **executado e aprovado em produção** | fumaça do roteiro 02, com as funções reais (`create_order_from_quote`), md5 das 9 tabelas comerciais igual antes/depois |
| Criação e atualização de orçamento com a reconciliação quebrada | executado e aprovado | seção 8 |
| Auditoria (`audit_capture`) | executado e aprovado | trilha de `ORC-2026-0003` (seção 7); md5 pós-deploy esperado |
| Link público | executado (parcial) | `get_shared_quote('token inválido')` devolve nulo; não há token vivo em produção para abrir a página |
| Clientes, produtos, estoque, fornecedores, compras, financeiro, PDF, compartilhamento — no banco | executado e aprovado localmente | 408 asserções das suítes 01–32 sobre as mesmas migrations (os 2 erros da suíte 15 são pré-existentes: ela depende do catálogo semeado e falha igual sem o BRAIN) |
| Código da aplicação | inalterado | `git diff main..brain/fase-1 -- src package.json` vazio; lint, typecheck e `next build` verdes nesta branch |
| Site | no ar | `https://agrotork-comercial.netlify.app/login` renderiza "Entrar · AGROTORK" |
| **Login e telas autenticadas** | **NÃO EXECUTADO** | exige credencial; não pedida |

## Efeitos colaterais permanentes — declarados

- `public.quote_sequences` está em 4 e `public.order_sequences` em 3, mas os últimos
  números emitidos de verdade são `ORC-2026-0001` e `PED-2026-0002`. `ORC-2026-0002`
  (fumaça do deploy), `ORC-2026-0003` (caso controlado), `ORC-2026-0004` (falha forçada) e
  `PED-2026-0003` (fumaça) foram consumidos por testes e apagados; nunca viraram PDF nem
  link. O próximo orçamento real sairá `ORC-2026-0005`. Recuar as sequências para 1 e 2 é
  uma alteração de dado em produção: **fica para o Wilson decidir**; não fiz.
- `public.audit_log` guarda a trilha das fumaças (append-only, por projeto).
- `brain.events` ids 1–5 apagados (eventos das fumaças); os reais são 3 (ids restantes).
- `supabase_migrations.schema_migrations`: as nove linhas do BRAIN têm `statements` nulo
  (registradas pelo roteiro, não pela CLI); `supabase db push` só compara versões.

## Pendências

1. **Push de `60c0975` + `ec2e3ea`** (bundle `agrotork-brain-fase1-v7-incremental.bundle`)
   e CI verde nesse SHA. O SQL implantado é o de `8571a9f` e não muda nesses commits.
2. Aplicar `20260911220000_brain_channels_policy.sql` pelo caminho normal de migration.
3. `980c2ff` do repositório local do Codex nunca chegou ao GitHub; `60c0975` faz a mesma
   correção. Se `980c2ff` for publicado antes, descartar `60c0975` (nunca foi empurrado).
4. Decidir sobre as sequências de numeração (acima).
5. Regressão de login/telas autenticadas, se o Wilson quiser, com a credencial dele.

## Gate de entrada da Fase 2

Satisfeito: schema `brain` implantado; 9 tabelas + 1 view; nove migrations registradas
por lista explícita; três pontes existentes e desabilitadas; cron ativo com execuções
funcionais verificadas; `divergencias_erp()` vazio e reconciliação idempotente; auditoria
pós-deploy e advisors comparados; commit implantado identificado (`8571a9f`).

Não satisfeito no sentido estrito: **CI verde no SHA final da branch** (bloqueio de push
desta sessão). O CI de `8571a9f` provou o deploy; o vermelho foi do próprio teste.

`pgvector` continua desabilitado (`vector 0.8.2` disponível, não instalado);
`pg_trgm 1.6` e `unaccent 1.1` já instalados.

---

## Fechamento definitivo — 11/09/2026, 20:00–20:05 UTC

Medido em produção nesta rodada.

**Pré-check.** HEAD remoto `brain/fase-1` = `00ef6f1` = local, árvore limpa; CI `BRAIN Fase 1`
em `00ef6f1`: **success** (1m17s). Schema `brain` presente; três pontes `D`; cron ativo,
último run `succeeded`; `divergencias_erp()` = 0; `20260911220000` não registrada;
`brain.channels` com `channels_admin_write[ALL]` + `channels_select[SELECT]` (o WARN ainda
apontado).

**Auditoria da migration `20260911220000_brain_channels_policy.sql`** (md5
`19761f54923089a68fa2f43c895999f2`, commit `ec2e3ea`): apenas `drop policy` de
`channels_admin_write` e `create policy` ×3 em `brain.channels` (insert/update/delete, só
admin) mais uma guarda de leitura em `pg_policies`. Não toca dado, leads, eventos,
oportunidades, orçamentos, pedidos, pontes, cron, `anon` nem Data API.

**Aplicação.** Uma transação: o texto executado foi conferido por md5 contra o versionado
antes do `execute`; registrada em `supabase_migrations.schema_migrations`
(`20260911220000`, `brain_channels_policy`, `statements` com o texto). Pós-condições dentro
da mesma transação: 4 policies, uma só cobrindo SELECT, pontes desligadas.

**Pós-check** (numa transação com `rollback`, sem persistir nada): admin autenticado lê 12
canais e insere/atualiza/apaga (1/1); `anon` recebe `insufficient_privilege`; RLS
habilitada; migration registrada com `statements=1`; tabela continua com 12 canais.

**Advisors.** Segurança: **idênticos** ao baseline (3 INFO sequências; WARN
`get_shared_quote` público — intencional; 23 WARN RPCs `security definer` — intencionais;
WARN leaked password protection — Auth). Desempenho: **`multiple_permissive_policies`
desapareceu**; restam só INFO — `unindexed_foreign_keys` 55 (33 do ERP + 22 do BRAIN,
mesmo padrão `created_by/updated_by`) e `unused_index` 56 (baixou de 59: a reconciliação
já usa três índices do `brain`). **Zero WARN de desempenho.**

**Gate operacional.** Pontes 3/0 ligadas; cron ativo, **25 execuções, 0 não-`succeeded`**;
divergências 0; segunda reconciliação `0,0,0,0,0,0`; eventos reais 3
(`ORC-2026-0001, PED-2026-0001, PED-2026-0002`), nenhum apagado; ERP 1/2/112; migrations
do BRAIN registradas: **10**; `audit_capture` `ee2f5cd5…e2d9e`; `vector` não instalado.

**Regressão executada nesta rodada** (PostgreSQL 17.6 local, todas as migrations
incluindo `220000`): suítes 25 (19), 27 (16), 28 (8), 29 (3), 30 (8), 31 (7), **32 (4)**,
02 (4), 18 (31), 14 (34) — 134 asserções, 0 erros; 09 e 10 passam na ordem do `run.sh`
(20 e 5) e falham fora dela por dependerem do contexto das suítes anteriores, não do
BRAIN; `ensaiar-deploy.sh` 17 cenários; `conferir-operacao.sh` verde. Login e telas
autenticadas: não executados (exige credencial).

**Sequências de numeração**: não recuadas, por decisão do Wilson. `ORC-2026-0002/0003/0004`
e `PED-2026-0003` ficam como lacunas históricas de teste.

**Riscos residuais conhecidos.** (1) Modo desacoplado: entre o COMMIT do ERP e a próxima
execução do cron há até ~60 s em que o BRAIN não conhece o fato — por desenho.
(2) O wrapper devolve `-1` sem marcar o job como `failed`; o sinal é o `warning`
`[brain-reconciliacao] falhou` no log do Postgres e o relatório `divergencias_erp()` não
esvaziar — vale um alerta na Fase 2. (3) INFO de FKs sem índice no `brain`: mesmo padrão
aceito no ERP; revisitar quando houver volume. (4) Telas autenticadas sem regressão de UI
nesta rodada.

**Veredito final:** FASE 1 100% CONCLUÍDA — PRODUÇÃO ESTÁVEL EM MODO DESACOPLADO.
