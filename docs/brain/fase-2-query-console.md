# AGROTORK BRAIN — Query Service e Console v0

> Primeiro ponto de uso real do BRAIN dentro do sistema comercial.
> **Sem LLM.** O que a tela entrega é *retrieval explicável*: os trechos
> recuperados, com fonte, versão e página — ou a recusa.

Implementado em 17/09/2026. Rota `/brain`, permissão `knowledge.query`
(admin e vendedor).

## 1. Por que sem resposta gerada

A camada seguinte — evidência confiável virando resposta em português, com
citações — só faz sentido depois que estas três coisas estiverem provadas
ponta a ponta: **recuperação**, **autorização** e **proveniência**. Um
gerador em cima de retrieval não auditado produz texto convincente sobre
documento errado, e ninguém percebe.

Então a v0 mostra a matéria-prima. Se a evidência estiver certa, a resposta
depois é fácil; se estiver errada, é melhor que apareça errada agora.

## 2. O caminho da pergunta

```
usuário autenticado
  └─ /brain  (Server Component, requirePermission)
       └─ BrainConsole  (client)
            └─ askKnowledgeAction   Server Action — sessão + papel
                 └─ service.ask     traduz zero linhas em recusa
                      └─ repository.search
                           └─ public.brain_search        ← grava a trilha
                                └─ brain.search_knowledge ← RLS, vigência, degradada
```

Nada disso passa pelo browser: a chave `service_role` não existe no cliente,
e o schema `brain` não é exposto ao PostgREST. As duas únicas portas são
`public.brain_search` e `public.brain_provenance`, as duas `security
invoker` — quem decide o que a pessoa vê é o RLS com a sessão dela.

## 3. Três cercas, e a última é o banco

| onde | o que faz | o que acontece se falhar |
| --- | --- | --- |
| página `/brain` | `requirePermission("knowledge.query")` | redireciona |
| Server Action | confere sessão, perfil ativo e papel | devolve `forbidden` |
| banco | `brain_search` sai vazio sem usuário ativo; RLS filtra nível | devolve zero |

A ação **não** usa `requirePermission`: aquele redireciona, o que é certo
numa página e errado num formulário já aberto — a recusa tem de voltar como
resposta, não como navegação. A cerca não afrouxa por isso; ela só deixa de
ser a única.

## 4. A escada de acesso

```
public  <  internal  <  commercial  <  admin
```

| papel | nível (`brain.caller_access_level()`) | alcança |
| --- | --- | --- |
| admin | `admin` | tudo |
| vendedor | `internal` | `public` e `internal` — **e só** |
| perfil inativo | NULL | nada, e sem trilha |
| anônimo | NULL | nada (`anon` nem tem EXECUTE) |

**Consequência que vale repetir:** um documento `commercial` é invisível
para o vendedor. Em produção isso já acontece — o orçamento interno ARAG é
`commercial`, e o Catálogo Magnojet é `public`:

| pergunta | admin | vendedor |
| --- | --- | --- |
| "vazão da MJ981CAP a 40 psi" | Magnojet V41, p. 20 | Magnojet V41, p. 20 |
| "o que é o código 4626215 da Arag" | ARAG 2024-10, p. 1 | **zero** |

Isso não é efeito colateral, é o desenho: custo e margem da casa não são do
vendedor. E a recusa é **indistinguível de inexistente** — a busca, o código
e a proveniência do trecho respondem todos vazio, sem dizer que existe um
documento que ele não pode ver. Trancado em Q8 da suíte 39.

## 5. O que a tela mostra, e o que ela nunca mostra

Cada evidência traz: **fonte · documento · versão · página · tipo · trecho ·
código(s) · nível de acesso · proveniência**.

Nunca traz: `version_id`, `document_id`, `storage_path`, `file_sha256`. A
linha crua de `brain_search` tem todos eles; `evidence.ts` os deixa de fora.
O usuário identifica o documento pelo que ele abriria para conferir — nome,
versão, página —, não por um id.

O painel **Detalhes da busca** (chunk, score, `rank_exact`, `rank_trgm`,
`rank_fts`, fonte técnica) só é montado quando quem pergunta é admin. O
vendedor não o vê porque ele não vem no payload, não porque está escondido
por CSS. E quem decide é o papel de quem perguntou, nunca a requisição:
pedir debug não é um jeito de virar administrador.

## 6. Fail-closed

Quatro situações, uma resposta honesta em cada:

| situação | status | o que a tela diz |
| --- | --- | --- |
| nenhuma evidência | `no_evidence` | "Não encontrei documentação suficiente para responder com segurança." |
| só tabela degradada | `no_evidence` | idem — a degradada nunca é evidência, nem para admin |
| documento fora de vigência | `no_evidence` | idem |
| sem permissão | `forbidden` | "Seu perfil não tem acesso à memória corporativa." |
| erro | `error` | "Não foi possível consultar a memória agora." |

Em nenhuma delas o sistema completa por conhecimento geral, faz inferência
comercial ou usa o cadastro do ERP como substituto silencioso. Medido em
produção, somente leitura:

| pergunta | evidências |
| --- | --- |
| "Qual a vazão da MJ981CAP a 40 psi?" | 1 — Magnojet · Catálogo Magnojet V41 · p. 20 |
| "O que é o código 4626215 da Arag?" | 1 — AGROTORK interno · Orçamento ARAG 2024-10 · p. 1 |
| "Qual a faixa de operação do sensor Arag 466113200?" | 2 — ARAG |
| "Qual a vazão da MJ999CAP?" | **0** |
| "Qual bateria serve para T55 e T70P?" | **0** — DJI não está em produção |
| "Qual o manual da semeadora Kuhn?" | **0** |

As três últimas são o ponto. O sistema sabe dizer que não sabe.

## 7. Trilha da consulta

`public.brain_search` já gravava em `brain.knowledge_queries`, e não
precisou de ajuste: **usuário, nível no momento da pergunta, texto (cortado
em 1000), filtros, quantidade de resultados, ids dos trechos devolvidos,
duração em ms e origem**.

Duas coisas que ela deliberadamente **não** guarda: o conteúdo devolvido
(Q15 confere) e qualquer segredo. E consulta de usuário anônimo ou inativo
não gera linha nenhuma — sem nível de acesso não há busca nem trilha.

Nada é registrado na camada TypeScript: haveria duas contagens da mesma
pergunta.

## 8. Testes

| | |
| --- | --- |
| `npm run check:brain` | 29 asserções — entrada (Zod), sanitização, recusas |
| suíte `39_brain_query_service.sql` | Q1–Q16 contra `public.brain_search` |

A suíte 39 usa a mesma porta que o aplicativo, não `brain.search_knowledge`
direto: é por ali que o Console passa e é ali que a trilha é gravada.

Dois cuidados no fixture, para o teste não ficar fácil: o código da tabela
degradada (`QS777CAP`) não existe em nenhum trecho confiável — se a busca o
devolver, vazou de verdade —, e Q13 confirma que o trecho **está** no banco,
para distinguir "recusado" de "nunca existiu".

## 9. O que esta rodada não fez

- **Nenhuma migration.** O schema já sustentava tudo.
- **Nenhum LLM, embedding ou pgvector.**
- **Nenhuma escrita de dado do BRAIN em produção.** A validação das sete
  perguntas foi por `brain.search_knowledge`, que não registra trilha —
  `brain_search` registraria, e registrar é escrever.
- **Nenhum deploy.** O app não foi publicado nesta rodada.

## 10. O que vem depois

Nesta ordem, e só nesta:

1. o bucket `brain-documents`, para a citação virar link para o arquivo;
2. mais documentos (DJI depende da ALLCOMP; JR, de um PDF sem sobreposição);
3. **só então** a camada de resposta natural com citações, em cima de
   evidência que já se provou confiável.
