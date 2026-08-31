# Publicação — AgroTork Sistema Comercial

Este documento leva um desenvolvedor que nunca viu o projeto do código
validado até o sistema no ar. Nenhum segredo aqui: onde entra um valor
sensível, o texto diz **onde** buscá-lo, nunca qual é.

Estado de partida: código validado, commit local pronto, **nada publicado**.

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
   para `/login`. É o item nº 1 porque no Next 16 o middleware passou a se
   chamar `proxy.ts`, e é a peça mais nova da cadeia de deploy.
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
