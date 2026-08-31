# Publicação — AgroTork Sistema Comercial

Este documento leva um desenvolvedor que nunca viu o projeto do código
validado até o sistema no ar. Nenhum segredo aqui: onde entra um valor
sensível, o texto diz **onde** buscá-lo, nunca qual é.

Estado de partida: código validado, commit local pronto, **nada publicado**.

---

## Publicação no Netlify — a ordem

Sete passos, nesta sequência. O domínio próprio é o **último**: tudo pode
ser validado antes dele, no endereço `*.netlify.app`.

| # | Passo | Detalhe |
|---|---|---|
| 1 | Criar o repositório no GitHub e enviar o código | §1 |
| 2 | Conectar o repositório ao Netlify | §2 |
| 3 | Cadastrar as variáveis de ambiente | §3 |
| 4 | Disparar o primeiro deploy | §2 |
| 5 | Anotar o endereço `https://<site>.netlify.app` | §2 |
| 6 | Rodar os smoke tests nesse endereço | §7 |
| 7 | **Só então** apontar o domínio próprio | §5 e §6 |

Entre os passos 5 e 6, cadastre o endereço `*.netlify.app` nas URLs de
Authentication do Supabase (§4) — sem isso, recuperação de senha e convite
por e-mail apontariam para o lugar errado. O login por e-mail e senha e o
link público do orçamento funcionam independentemente disso.

---

## 1. GitHub

O repositório ainda não existe — criá-lo é decisão do dono do projeto.

```bash
# Já feito: git init, .gitignore conferido, primeiro commit local.
git remote add origin git@github.com:<org>/<repo>.git
git branch -M main
git push -u origin main
```

Antes do `push`, confira uma última vez que nenhum segredo entrou — na
árvore atual **e** no histórico:

```bash
# Só os dois exemplos podem aparecer aqui.
git ls-files | grep -E "^\.env" ; echo "(esperado: .env.example e .env.production.example)"

# Chave do Supabase, JWT, service role com valor, chave privada, project ref.
git log -p --all | grep -nE "sb_(secret|publishable)_[A-Za-z0-9]|ey[J]hbGciOi[A-Za-z0-9]|SERVICE[_]ROLE[_]KEY[[:space:]]*=[[:space:]]*[^[:space:]\"']|BEGIN [A-Z ]*PRIVATE KEY|[n]edmdkdhchkadijtdnja"
echo "(vazio = limpo)"
```

Duas decisões deste comando, para ninguém "arrumá-lo" depois e perder o
que ele tem de útil:

- **Os colchetes** em `ey[J]`, `SERVICE[_]ROLE[_]KEY` e `[n]edm…` casam o
  texto procurado como regex, mas a linha do comando **não contém** esse
  texto. Sem eles, a busca encontra a si mesma neste arquivo.
- **O que vem depois de cada prefixo** (`[A-Za-z0-9]`, `= valor`) é o que
  separa segredo de menção. `service_role` sozinho é um papel do Postgres
  e aparece em dezenas de linhas das migrations — procurar a palavra solta
  devolve tanto ruído que o resultado deixa de ser lido.

Repositório **privado**. O código não tem segredo, mas expõe a modelagem
comercial da empresa — tabela de preços, margens, estrutura de kits.

---

## 2. Netlify

**Add new site → Import an existing project → GitHub → o repositório.**

A Netlify detecta Next.js sozinha. O `netlify.toml` do repositório já fixa
o que a detecção não adivinha:

| Campo | Valor | De onde vem |
|---|---|---|
| Build command | `npm run build` | `netlify.toml` |
| Publish directory | `.next` | `netlify.toml` |
| Node version | 22 | `netlify.toml` |
| Adaptador Next | automático | **não fixar versão** — a Netlify atualiza a cada build |

Não marque "static export": o sistema depende de Server Actions, Route
Handlers (os dois endpoints de PDF) e middleware. Exportação estática
quebraria login, orçamento e link público de uma vez.

---

## 3. Environment variables

**Site configuration → Environment variables.** Os nomes estão em
`.env.production.example`; os valores, no painel do Supabase
(**Project Settings → API**).

| Variável | Valor | Escopo |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Project URL | todos os deploys |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | chave `anon public` | todos os deploys |
| `NEXT_PUBLIC_SITE_URL` | domínio final, com `https://`, sem barra final | produção |

As duas primeiras são públicas por natureza — vão para o navegador de
qualquer forma, e quem decide o que cada usuário enxerga é o RLS.

**Não cadastre `SUPABASE_SERVICE_ROLE_KEY`.** Ela ignora o RLS e nenhum
código do sistema a utiliza hoje. Ver `.env.production.example`.

---

## 4. Supabase Auth URLs

**Authentication → URL Configuration**, depois que a Netlify der o domínio.

| Campo | Valor |
|---|---|
| Site URL | `https://<domínio-de-produção>` |
| Redirect URLs | `https://<domínio-de-produção>/**` |
| Redirect URLs (prévia, opcional) | `https://<site>.netlify.app/**` e `https://deploy-preview-*--<site>.netlify.app/**` |

Escopo real disso hoje, para não configurar no escuro:

- O login usa **e-mail e senha** (`signInWithPassword`). Não há OAuth, link
  mágico nem rota de callback — não existe `/auth/callback` no projeto.
- Por isso o **Site URL** só passa a importar de fato quando forem ligados
  recuperação de senha ou convite por e-mail: é ele que monta o link do
  e-mail. Cadastre mesmo assim, para que esses recursos já nasçam certos.
- O **link público do orçamento** não depende de nada disso. Ele é montado
  a partir do cabeçalho da requisição (`currentBaseUrl()`), e quem autoriza
  a leitura é o TOKEN, validado por `get_shared_quote()` no banco. O mesmo
  vale para o PDF público.

---

## 5. Domínio

Nada a fazer até o domínio final estar decidido. Quando estiver:

1. Netlify → **Domain management → Add a domain**.
2. No registrador (Registro.br, no caso de um `.com.br`), apontar conforme
   a Netlify instruir — `CNAME` para o subdomínio, ou os nameservers da
   Netlify se ela for gerir a zona.
3. Propagação: minutos a algumas horas.
4. Atualizar `NEXT_PUBLIC_SITE_URL` e o **Site URL** do Supabase para o
   domínio novo, e refazer o deploy.

Até lá o sistema funciona no domínio `*.netlify.app`, inclusive o link
público — ele acompanha o domínio em que o usuário está.

---

## 6. HTTPS

Automático: a Netlify emite certificado Let's Encrypt assim que o DNS
resolve. Depois de emitido, ligue **Force HTTPS** em Domain management.

O `upgrade-insecure-requests` da CSP (`src/lib/security/csp.ts`) já assume
HTTPS em produção, e os cookies de sessão do Supabase são `Secure` —
em HTTP o login simplesmente não persiste. Não há o que ajustar no código.

---

## 7. Smoke test

Na ordem, logo após o primeiro deploy. Os três primeiros são os que de
fato podem quebrar na virada para a Netlify.

1. **Middleware/proxy.** Abrir `/dashboard` sem sessão: tem de redirecionar
   para `/login`. É o item nº 1 por um motivo concreto: no Next 16 o
   middleware virou `src/proxy.ts` e passou a ser compilado para o runtime
   **Node**, deixando de aparecer como função edge no
   `middleware-manifest.json` (que sai vazio). O artefato está completo —
   `.next/server/middleware.js` carrega o chunk com as rotas públicas e a
   CSP, e o rastreamento (`.nft.json`) o inclui —, mas quem liga esse
   artefato à infraestrutura é o adaptador da Netlify. Se este teste
   falhar, o sintoma será: página protegida abrindo sem login, ou CSP sem
   nonce. Nesse caso, conferir a versão do adaptador antes de mexer no
   código.
2. **CSP com nonce.** Abrir qualquer página logada e conferir o console: sem
   violação de CSP, e a interface responde a clique (se o nonce não chegar,
   o React não hidrata e a tela fica "morta"). A Netlify avalia headers
   depois do middleware — daí a conferência.
3. **PDF.** Baixar o PDF de um orçamento. É o caminho que usa `pdfkit`
   (CommonJS, declarado em `serverExternalPackages`) dentro de uma função
   de servidor.
4. Login com o administrador; criar e salvar um rascunho de orçamento.
5. Gerar link público e abri-lo em **aba anônima**; baixar o PDF público.
6. Conferir que a página pública **não** mostra custo, margem nem
   observação interna.
7. Entrar como vendedor e confirmar que ele não vê orçamento alheio.
8. Conferir 360 px, 768 px e 1440 px na listagem de orçamentos.

---

## 8. Rollback

Sem tocar no banco:

- **Netlify → Deploys → o deploy anterior → Publish deploy.** Volta em
  segundos; o Git não muda.
- Para desfazer no código: `git revert <hash>` e novo push. Não use
  `push --force` em `main`.

Rollback de **banco** é outra história e não tem botão: as migrations são
aplicadas para a frente. Desfazer uma exige uma migration nova que reverta
o efeito. Por isso `supabase db push` contra produção é sempre uma decisão
consciente, nunca um passo de rotina — e por isso nenhum passo deste
documento o executa.

---

## Antes de qualquer deploy

```bash
npm run lint
npm run typecheck
npm run build
npm run db:test
```

Os quatro têm de passar. O `db:test` usa um banco descartável e não encosta
no Supabase.

---

# Produção

Auditoria do deploy real em `https://agrotork-comercial.netlify.app` — o que
está confirmado funcionando, e o que ainda depende de configuração no painel.

## Netlify — confirmado

| Item | Estado |
|---|---|
| Build | `npm run build`, publish `.next`, Node 22 (`netlify.toml`) |
| Adaptador Next | automático, sem versão fixada |
| SSR / App Router / Route Handlers / Server Actions | funcionando |
| **Proxy (`src/proxy.ts`)** | **funcionando** — as cinco rotas protegidas redirecionam sem sessão, e `/login` redireciona para `/dashboard` com sessão |
| **CSP com nonce** | **funcionando** — header presente, nonce diferente a cada resposta, 14 scripts carregando com ele, React hidratando |
| Headers de segurança | `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy` |
| **PDF (pdfkit)** | **funcionando** nas duas rotas — `application/pdf`, assinatura `%PDF-` |

Nada disso precisa de ajuste. O risco que existia — o proxy do Next 16 não ser
publicado pelo adaptador — **não se concretizou**.

### Variáveis de ambiente

| Variável | Classificação | Observação |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | **obrigatória** (produção e dev) | 3 consumidores |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | **obrigatória** (produção e dev) | 3 consumidores |
| `NEXT_PUBLIC_SITE_URL` | **opcional** | `env.siteUrl()` não tem nenhum consumidor; o link público vem do cabeçalho da requisição |
| `SUPABASE_SERVICE_ROLE_KEY` | **não usar** | Único consumidor é `admin.ts`, que não tem importador. Não cadastrar |

## Supabase — o que ainda depende do painel

Nada abaixo pode ser feito por migration ou por código: são configurações do
projeto. Estão em ordem de urgência.

### 1. Cadastro público de usuários — VERIFICAR ANTES DE OPERAR

**Authentication → Sign In / Providers → Email → "Allow new users to sign up".**

O sistema não tem tela de cadastro, mas a API de Auth do Supabase é pública por
natureza: a URL do projeto e a chave `anon` viajam no navegador, como devem. Se
o cadastro estiver habilitado, qualquer pessoa com essas duas informações pode
chamar `/auth/v1/signup` diretamente.

E há um agravante específico deste schema. O trigger `handle_new_user`
(migration 0300) monta o perfil assim:

```sql
coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'salesperson')
```

O `raw_user_meta_data` é enviado por quem se cadastra. Um cadastro com
`data: { role: "admin" }` nasceria **administrador** — e administrador enxerga
custo, margem e todos os orçamentos.

O RLS está correto e não é o furo: `profiles_update_self` já impede promoção
depois (`role = public.auth_role()`). O problema é o momento do INSERT, feito
por uma função `security definer`, fora do RLS.

**Ação imediata:** desabilitar o cadastro público. Com ele desligado, usuários
só nascem pelo painel ou por convite, e o vetor fecha.

**Correção estrutural, para não depender de uma caixinha marcada:** uma
migration nova que faça `handle_new_user` ignorar o `role` do metadata e
sempre criar `salesperson`, deixando a promoção a admin como operação
explícita. Não foi feita nesta etapa porque alterar migrations exige
autorização — está proposta, aguardando.

### 2. Auth para o domínio de produção

**Authentication → URL Configuration**

| Campo | Valor |
|---|---|
| Site URL | `https://agrotork-comercial.netlify.app` — e depois o domínio próprio |
| Redirect URLs | `https://agrotork-comercial.netlify.app/**` |
| Redirect URLs (prévia) | `https://deploy-preview-*--agrotork-comercial.netlify.app/**` |

Escopo real: o login é e-mail e senha (`signInWithPassword`); não há OAuth,
link mágico nem rota de callback. O Site URL passa a importar quando forem
usados recuperação de senha ou convite — é ele que monta o link do e-mail.
O link público do orçamento **não depende disto**: quem autoriza é o token.

Ainda em Authentication, revisar e anotar a decisão de cada item:

- **Confirm email** — ligado é o mais seguro; exige SMTP configurado, senão o
  convite não chega.
- **SMTP** — o remetente padrão do Supabase tem limite baixo e não serve para
  operação real. Configurar um provedor próprio antes de convidar vendedores.
- **Sessão** — definir JWT expiry e refresh token rotation conforme o uso em
  campo (celular do vendedor tende a pedir sessão mais longa).
- **Rate limits** — os padrões cobrem o caso normal; revisar se houver
  tentativa de força bruta.
- **MFA** — recomendável para as contas **admin**, que enxergam custo e
  margem. Não é necessário para vendedor.

### 3. Security Advisor

**Database → Advisors → Security Advisor.** Rodar e resolver o que aparecer.
O schema já nasce com RLS em todas as 13 tabelas de negócio e nenhuma policy
alcançando `anon` — o esperado é uma lista curta.

### 4. Storage

Os buckets `public-assets` (leitura pública, escrita de admin, 5 MB, só
imagem) e `private-docs` (admin) são criados pela migration 2000. Conferir em
**Storage → Buckets** que ambos existem no projeto real.

### 5. Backup e recuperação

Não presumo qual plano está contratado — confira em **Settings → Billing**.

| Plano | O que existe |
|---|---|
| Free | Backup diário, retenção curta, **sem PITR**. Restauração é abrir ticket |
| Pro | Backup diário com retenção maior; **PITR é add-on pago** |

Enquanto não houver PITR, o risco concreto é: um `UPDATE` ou `DELETE` sem
`WHERE` no SQL Editor perde tudo o que aconteceu desde o último backup diário.

Recomendação, na ordem do custo:

1. **Nunca** rodar SQL de escrita no painel de produção. Toda mudança
   estrutural nasce como migration versionada — é o que já está estabelecido.
2. Exportar `pg_dump` antes de qualquer operação fora do comum, e guardar fora
   do Supabase.
3. Avaliar PITR quando o volume de orçamentos justificar. Para um sistema
   comercial, perder um dia de propostas é caro.

## Domínio

Ainda não configurado. Quando `sistema.agrotork.com.br` (ou outro) estiver
decidido:

1. **Netlify → Domain management → Add a domain**.
2. **DNS no Registro.br**: `CNAME` do subdomínio para o endereço que a Netlify
   indicar. Se a Netlify for gerir a zona, trocar os nameservers.
3. **HTTPS**: certificado Let's Encrypt automático; depois ligar **Force
   HTTPS**. O `upgrade-insecure-requests` da CSP e os cookies `Secure` do
   Supabase já assumem HTTPS.
4. **Supabase Auth**: trocar Site URL e Redirect URLs para o domínio novo.
5. **`NEXT_PUBLIC_SITE_URL`** na Netlify, e refazer o deploy.
6. **Link público de orçamento**: acompanha o domínio automaticamente (vem do
   cabeçalho da requisição). Links já gerados continuam válidos no endereço
   antigo enquanto ele responder.

## Usuários — limitação conhecida

O modelo de papéis está completo: `admin` e `salesperson` no enum, matriz em
`src/config/permissions.ts`, RLS por papel, e usuário desativado barrado no
login e na sessão (`is_active`).

**O que não existe é a tela.** Não há módulo de usuários: `/configuracoes` tem
marcas, categorias, unidades e perfil. A permissão `users.manage` está
declarada, sem implementação.

Consequência prática: **para incluir um vendedor hoje, o administrador precisa
criar o usuário no painel do Supabase** (Authentication → Users → Add user),
com `full_name` no metadata. O trigger cria o perfil como `salesperson`.

Isso funciona, mas não escala e depende de alguém com acesso ao painel — que é
justamente o acesso que não se quer distribuir. O módulo de usuários é o
próximo candidato natural de roadmap.

## Smoke test

Depois de todo deploy. Os três primeiros são os que podem quebrar na virada de
infraestrutura.

1. **Rota protegida sem sessão** — `/dashboard` em aba anônima redireciona
   para `/login`.
2. **CSP e hidratação** — página logada sem violação no console, e a interface
   responde a clique.
3. **PDF** — baixar o PDF de um orçamento.
4. Login com admin; logout; login de novo.
5. Criar marca, categoria, unidade, produto e kit.
6. Criar orçamento, adicionar produto e kit, conferir o total.
7. Gerar link público e abrir em **aba anônima**; baixar o PDF público.
8. Conferir que a página pública **não** mostra custo, margem nem observação
   interna.
9. Entrar como vendedor: não vê orçamento alheio, não vê custo.
10. Conferir 360 px, 768 px e 1440 px.

## Rollback

**Deploy:** Netlify → Deploys → o deploy anterior → **Publish deploy**. Volta
em segundos e o Git não muda.

**Código:** `git revert <hash>` e novo push. Nunca `push --force` em `main`.

**Banco:** não tem botão. As migrations só andam para a frente; desfazer uma
exige uma migration nova que reverta o efeito. Daí a regra que sustenta tudo
isto: **nenhuma alteração de schema fora de migration versionada**. Um `ALTER`
feito à mão no painel não existe no repositório, não é reproduzível e não tem
como ser reproduzido — e é assim que um ambiente começa a divergir do outro.
