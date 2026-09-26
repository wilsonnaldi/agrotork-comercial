# AGROTORK BRAIN — contrato de ambiente do provedor de síntese

> Pacote C (26/09/2026). Três variáveis de servidor ligam a síntese do
> Answer v1. Este documento diz quais são, onde cada uma pode existir, como
> conferir sem expor valor e como desligar. A regra mora em código, num
> lugar só: `src/modules/brain/llm/config.ts` (`readProviderConfig`), usada
> pelo servidor (`resolveProvider`) e pelo preflight.

## 1. As variáveis

| Variável | Valor | Obrigatória para sintetizar |
|---|---|---|
| `BRAIN_LLM_PROVIDER` | `anthropic` — ou `none` / `off` / `disabled` para desligar | sim |
| `BRAIN_LLM_MODEL` | identificador do modelo, não vazio | sim |
| `BRAIN_LLM_API_KEY` | `<secret>` | sim |

- Valores são aparados; vazio ou só espaço conta como **ausente**.
- Conferência em ordem **provedor → modelo → chave**: sem chave, o resto
  ainda é validado, e o motivo aponta a chave só quando o resto está certo.
- Configuração pela metade = síntese **desligada**. Nunca há tentativa às
  cegas: o console responde de forma extractiva, com os trechos na íntegra.
- Neste documento, e em qualquer relatório, valor de chave só aparece como
  `<secret>`.

## 2. Onde cada uma existe

| Ambiente | Provedor | Chave | Por quê |
|---|---|---|---|
| **Production** (Netlify) | `anthropic` | `<secret>`, escopo **só servidor** (Functions/Runtime) | é o único lugar onde a síntese roda |
| **Deploy Preview / branch deploy** | ausente ou `none` | **nenhuma**, de propósito | código de PR não recebe credencial; o Preview responde de forma extractiva |
| **CI** (`brain.yml`, `brain-app.yml`) | nenhuma | **nenhuma**, de propósito | as suítes usam provedor falso; `check:brain-ci` reprova qualquer `secrets.` |
| Local (`.env.local`) | a critério do Wilson | nunca versionada (`.env*.local` no `.gitignore`) | smoke manual |

**Nunca `NEXT_PUBLIC_`.** Nenhuma variável `NEXT_PUBLIC_BRAIN_LLM*` pode
existir em ambiente nenhum: o Next embute esse prefixo no JavaScript do
navegador. O preflight trata isso como erro (exit 2) mesmo com o resto certo.

## 3. Conferir sem expor: `npm run brain:preflight`

Manual e local — **não é step de CI** (o nome não começa com `check:brain`,
então a guarda do CI não o exige). Não chama o provedor, o banco nem a rede.

```
npm run brain:preflight              # lê o ambiente + .env.local do diretório atual
npm run brain:preflight -- --contract  # só o contrato; ignora o ambiente (seguro para CI/docs)
```

Imprime, por variável, **só** `presente` / `ausente` — nem valor, nem
pedaço, nem tamanho —, se existe alguma `NEXT_PUBLIC_BRAIN_LLM*`, se o
provedor é suportado, se o modelo está preenchido e o veredito:

| Exit | Veredito |
|---|---|
| 0 | `PRONTO PARA PRODUÇÃO (configuração)` |
| 1 | `NÃO CONFIGURADO: <reason>` (lista abaixo) |
| 2 | existe `NEXT_PUBLIC_BRAIN_LLM*` — remover antes de qualquer coisa |

O preflight **não** prova que a chave é válida (isso exigiria chamar o
provedor). Ele prova que a configuração fecha. As variáveis cadastradas no
painel da Netlify não são lidas daqui: para conferi-las, rode o preflight no
mesmo ambiente em que elas existem, ou confira no painel os NOMES e o
escopo.

## 4. Motivos (`reason`) quando não há provedor

O outcome `no_provider` do log `[brain.synthesis]` leva um destes motivos
(e só o motivo — nunca o valor da variável). A tela recebe sempre o mesmo
aviso genérico ("A síntese automática não está configurada neste
ambiente…"): quem pergunta não precisa saber qual variável falta.

| `reason` | Quando |
|---|---|
| `provider_missing` | `BRAIN_LLM_PROVIDER` ausente ou vazia |
| `provider_disabled` | `BRAIN_LLM_PROVIDER` = `none` / `off` / `disabled` |
| `provider_unsupported` | outro valor (não é ecoado: pode ser a chave colada na variável errada) |
| `model_missing` | `BRAIN_LLM_MODEL` ausente ou vazia |
| `key_missing` | `BRAIN_LLM_API_KEY` ausente ou vazia |

Testes: `check-brain-provider.mjs` CFG1–CFG15 (parser e `resolveProvider`
com ambiente inventado) e PF1–PF6 (o preflight como processo filho);
`check-brain-synthesis.mjs` SYN34a–f (cada motivo chega ao log, provedor
0×, aviso idêntico).

## 5. Rollback

Desligar a síntese em produção sem deploy de código: no painel da Netlify,
**`BRAIN_LLM_PROVIDER=none`** (ou remover a variável) e disparar um novo
deploy do mesmo commit (variável alterada no painel só vale para as funções
a partir do deploy seguinte). Resultado: toda consulta volta a ser extractiva, com as evidências
na íntegra, e o log passa a registrar `no_provider` com
`reason: provider_disabled` (ou `provider_missing`). A chave pode continuar
cadastrada — `none` vence. Prova: **SYN34b** (`none` com chave e modelo
presentes → `no_provider:provider_disabled`, provedor chamado 0×) e CFG3c.

## 6. Tempo de espera

`TIMEOUT_PROVIDER_MS = 30_000` (`src/modules/brain/limits.ts`): o
AbortController do adapter corta a chamada e a leitura do corpo nesse teto
(E12), e a consulta cai no extractivo com `provider_error:timeout`.

Para esse corte acontecer **dentro** da requisição, o timeout da função de
servidor da Netlify precisa ser maior que **busca + 30 s**. O repositório
não fixa esse valor (`netlify.toml` não o declara, e o padrão depende do
plano da conta). **NEEDS_WILSON:** confirmar no painel o timeout das
funções do site em produção; se for menor que ~40 s, a função pode ser
encerrada antes do fallback extractivo, e o usuário veria erro genérico em
vez dos trechos.

## 7. Checklist para ligar em produção

1. `npm run brain:preflight -- --contract` para ter os nomes à mão.
2. No painel da Netlify, escopo **Production**, contexto de **Functions**:
   `BRAIN_LLM_PROVIDER=anthropic`, `BRAIN_LLM_MODEL=<modelo>`,
   `BRAIN_LLM_API_KEY=<secret>`. Nenhuma em Deploy Preview; nenhuma com
   `NEXT_PUBLIC_`.
3. Conferir o timeout das funções (§6).
4. Deploy; uma consulta de smoke; no log, o outcome deve sair de
   `no_provider` para `answered` (ou `answer_rejected`/`provider_error` com
   motivo). Roteiro completo (P1–P6, evento esperado de cada uma):
   [`production-readiness.md`](production-readiness.md) §3.
5. Rollback: §5.
