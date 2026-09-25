# AGROTORK BRAIN — Registro de lacunas (25/09/2026)

> Revalidado no repositório nesta rodada, não copiado dos docs anteriores.
> Onde não deu para confirmar, está escrito "não confirmado no repo" em vez
> de afirmado. Ver `docs/brain/fase-2-answer-v1.md` (estado atual),
> `docs/brain/fase-2-consolidado.md` (16/09, retrato mais amplo da Fase 2) e
> `CLAUDE.md` para o histórico completo de cada item.

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
| **Diretórios temporários de teste fora do `.gitignore`** | aberto, de propósito ("ficou assim nesta rodada") | baixo — cada suíte cria com `mkdtempSync` e remove com `rmSync` ao final; `.provider-check-*` já está no `.gitignore`, os outros cinco (`​.brain-check-*`, `.answer-check-*`, `.ui-check-*`, `.comparison-check-*`, `.synthesis-check-*`) não | `.gitignore` lido nesta rodada — confirma exatamente a lista que `ci.md` §8 já descreve, sem divergência | adicionar ao `.gitignore` numa rodada de limpeza, sem urgência (uma suíte que aborte no meio pode deixar o diretório para trás) | não | não | não |

## NÃO-BLOCKER / ACCEPTED LIMITATION

| item | estado | risco | evidência | próximo passo | produção? | Wilson? | fornecedor? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Suíte 25 — BR4/BR5/BR6/BR9/BR16 herdadas** | aceito — comportamento esperado no modo desacoplado | baixo — provado nas duas pontas: com as pontes `trg_brain_*` ligadas a suíte fica 18/18, e `reconciliar_erp()` restaura a substância de cada uma | `consolidado.md` §7; `CLAUDE.md` "Pendências conhecidas" | forma, não substância: tornar as cinco condicionais a `brain.estado_das_pontes()` para não confundir com uma sexta falha real — não feito nesta rodada | não | não | não |
| **Mobile: BRAIN entra com `mobile: false`** | aceito, pendência de layout | baixo | `src/config/navigation.ts` — confirmado nesta rodada: Kits, Estoque, Entradas, Financeiro, Relatórios e BRAIN, todos `mobile: false` (barra do celular com 5 lugares, 6 itens marcados) | redesenhar a barra inferior quando entrar em pauta de UX — não é bug, é fila | não | não | não |
| **Compusystem não modelado em schema/coluna** | aceito, é a regra (`CLAUDE.md` #6) | baixo — é a proteção contra inventar dado, não uma falha | `CLAUDE.md` regra 6 | nenhum até o contrato chegar | não | — | — |

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
auditado: a cadeia inteira está provada com 633 asserções determinísticas
e com provedor real no localhost; JR, DJI e Compusystem crescem o acervo,
mas dependem de terceiros, e nenhum torna mais útil o que os dois
documentos já ingeridos sustentam hoje. Não começar aqui: cada item mexe
em produção ou em configuração do GitHub, e isso é decisão do Wilson.
