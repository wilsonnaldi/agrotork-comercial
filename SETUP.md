# SETUP — Sistema Comercial AGROTORK

Passo a passo para deixar o projeto rodando do zero.

> **Nenhuma credencial real aparece neste documento.** Todas as chaves ficam
> apenas no seu `.env.local`, que não é versionado. Em especial, a
> `SUPABASE_SERVICE_ROLE_KEY` **nunca** deve ser colada em documento, mensagem,
> ticket, print ou código — ela ignora o RLS e dá acesso total ao banco.

---

## 1. Instalar as dependências

Pré-requisitos: **Node.js 20+** e **npm**.

```bash
npm install
```

Opcional (para os testes de banco): PostgreSQL 15+ com `psql` no PATH.

---

## 2. Configurar o ambiente

```bash
cp .env.example .env.local
```

O `.env.local` precisa conter, ao final:

| Variável | Onde encontrar | Exposta ao navegador? |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase → Project Settings → API → *Project URL* | sim |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | mesma tela → *anon public* | sim |
| `NEXT_PUBLIC_SITE_URL` | `http://localhost:3000` em desenvolvimento | sim |

A chave *anon public* ser exposta ao navegador **não** é um problema: ela não
concede nada sozinha — quem decide o que cada usuário enxerga é o RLS.

> **A `SUPABASE_SERVICE_ROLE_KEY` não entra aqui.** Ela ignora o RLS, e nenhum
> código do sistema a utiliza hoje. Só será necessária quando o módulo de
> Usuários chegar. Ver a explicação completa em `.env.example`.

O `.env.local` já está no `.gitignore`. Confirme antes do primeiro commit:

```bash
git check-ignore -v .env.local     # deve responder que está ignorado
```

Se alguma chave vazar (commit, print, mensagem), gere outra imediatamente em
**Project Settings → API → Rotate**.

---

## 3. Criar e conectar o projeto Supabase

### 3.1 Criar o projeto

1. Acesse <https://supabase.com> e entre na organização da AGROTORK.
2. **New project**.
3. Nome: `agrotork-comercial` (sugestão: um projeto para produção e, mais à
   frente, outro `agrotork-comercial-dev`).
4. **Região: `South America (São Paulo)`** — é a mais próxima de Londrina.
   Região não muda depois de criado; escolher errado custa latência em toda
   requisição.
5. Defina uma senha forte para o banco e guarde no gerenciador de senhas da
   empresa. Ela **não** vai para o `.env.local` nem para o repositório.
6. Aguarde o provisionamento (1 a 2 minutos).

### 3.2 Coletar as informações

Em **Project Settings → API**:

- *Project URL* → `NEXT_PUBLIC_SUPABASE_URL`
- *anon public* → `NEXT_PUBLIC_SUPABASE_ANON_KEY`

A *service_role* fica onde está: **não copie**. Nenhum código do sistema a
utiliza hoje, e chave que não sai do painel não vaza.

Em **Project Settings → General**:

- *Reference ID* → usado no comando de link do passo seguinte.

### 3.3 Fazer o link

```bash
npx supabase login          # abre o navegador para autenticar
npx supabase link --project-ref SEU-REFERENCE-ID
```

O link grava `supabase/.temp/` (já ignorado pelo Git). O CLI pede a senha do
banco definida em 3.1.

---

## 4. Aplicar as migrations

```bash
npm run db:push             # equivale a: npx supabase db push
```

Isso aplica, em ordem, as **21 migrations** de `supabase/migrations/`. A ordem
é a alfabética do nome do arquivo, e ela importa: extensões e enums primeiro,
depois tabelas, depois RLS, depois as correções. As 21 são aplicadas do zero a
cada `npm run db:test`, então a ordem e as dependências já estão verificadas.

**Não** altere o schema pelo painel do Supabase. Toda mudança estrutural nasce
como uma migration nova neste repositório — é assim que os ambientes se mantêm
iguais.

Depois de aplicar, regere os tipos:

```bash
npm run db:types
```

> **`database.types.ts` é gerado — e só isso.** O comando acima sobrescreve
> `src/types/database.types.ts` inteiro, toda vez. Nada escrito à mão pode
> morar lá: os apelidos de domínio (`Product`, `QuoteStatus`, `QuoteListRow`…)
> ficam em **`src/types/db.ts`**, derivados do arquivo gerado. É de lá que a
> aplicação importa — só o `db.ts` importa o arquivo gerado. Regerar não
> apaga arquitetura; se uma coluna mudar de tipo, o erro aparece no `db.ts`
> ou em quem o usa, e não em silêncio.

Conferência rápida no **SQL Editor** do Supabase:

```sql
-- Todas as tabelas de negócio com RLS ligado. Nenhuma linha com `false`.
select tablename, rowsecurity
  from pg_tables
 where schemaname = 'public'
 order by rowsecurity, tablename;

-- As funções privilegiadas: 15 `security definer`.
select proname from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef
 order by 1;

-- Os dois buckets do Storage.
select id, public from storage.buckets order by id;
```

Se preferir conferir os **tipos** antes de ter o banco real, dois scripts
aplicam as migrations num PostgreSQL descartável:

```bash
npm run db:types:local          # gera database.types.ts a partir das migrations
bash supabase/db-tests/check-types.sh   # confere a tipagem contra o schema real
```

### Os dois runners de teste de banco

| Comando | O que roda | Onde |
|---|---|---|
| `npm run db:test` | **Suíte de comportamento** — 194 checagens de regra de negócio, RLS e privilégios, em banco descartável. É o runner canônico. | Windows, macOS e Linux; usa `psql` se houver, senão Docker |
| `npx supabase test db` | **Asserções estruturais** (pgTAP) — RLS ligado, policies, `security definer`, buckets. Idempotente. | Supabase local (Docker) |

A separação não é burocracia: a suíte de comportamento é uma **sequência**
(`01` cria o usuário que `02` usa, `02` cria o orçamento que `09` confere),
com identificadores fixos que tornam a asserção legível. Rodar isso sobre o
banco local já povoado dá `duplicate key` em cascata. As asserções
estruturais, ao contrário, não dependem de ordem nem de dado — e por isso
são exatamente as que valem contra o Supabase de verdade.

No Windows, `npm run db:test` é o comando; ele não precisa de `psql` nem de
WSL, só do Docker Desktop no ar (ou de um `psql` no PATH). Os utilitários
`check-types.sh` e `gen-types.sh` continuam sendo scripts de shell — use
WSL ou Git Bash para eles.

O `check-types.sh` confere duas coisas: que o arquivo gerado tem todas as
tabelas, colunas e enums das migrations, e que as duas listas escritas à mão
em `src/types/db.ts` continuam corretas — as colunas `numeric` (o gerador não
as distingue de `integer`) e as colunas preenchidas por trigger. O TypeScript
não tem como conferir nenhuma das duas sozinho.

---

## 5. Criar o primeiro administrador

Não existe usuário inicial no repositório — de propósito. Senha nenhuma pode
ficar em código, migration ou documento.

### 5.1 Criar o usuário no Supabase Auth

No painel: **Authentication → Users → Add user**.

- E-mail: o e-mail corporativo real da pessoa.
- Password: defina uma senha forte **na hora**, e entregue por um canal seguro
  (gerenciador de senhas) — não por e-mail nem WhatsApp.
- Marque **Auto Confirm User** (evita a etapa de confirmação por e-mail).

Alternativa preferível quando houver caixa de e-mail configurada:
**Invite user** — a própria pessoa define a senha, e ninguém mais a conhece.

### 5.2 O perfil é criado sozinho

A migration `20260829000300_profiles.sql` instala um trigger em `auth.users`
que cria automaticamente a linha correspondente em `public.profiles`. Não é
preciso inserir nada à mão.

O perfil nasce sempre como **vendedor** (`salesperson`), qualquer que seja o
metadata do cadastro — é o que a migration `20260831002100` garante. Papel de
administrador não se concede no cadastro; só pelo passo explícito abaixo.

### 5.3 Promover a administrador

No **SQL Editor**, trocando o e-mail pelo real:

```sql
update public.profiles
   set role = 'admin',
       full_name = 'Nome Completo'
 where lower(email) = lower('pessoa@agrotork.com.br');
```

Confira:

```sql
select email, full_name, role, is_active from public.profiles;
```

> Enquanto o módulo de usuários não existir, este mesmo `update` é o caminho
> para promover qualquer administrador. Vendedor não precisa dele: é o papel
> padrão de todo cadastro.

### 5.4 Desativar alguém

Não apague o usuário — o histórico comercial depende dele:

```sql
update public.profiles set is_active = false
 where lower(email) = lower('pessoa@agrotork.com.br');
```

O RLS bloqueia usuário inativo mesmo que ele ainda tenha um token válido.

---

## 6. Iniciar o projeto

```bash
npm run dev
```

Abra <http://localhost:3000>. Sem sessão, você é levado para `/login`.
Depois de entrar, cai no painel.

Enquanto o `.env.local` não existir, a tela de login explica o que está
faltando em vez de quebrar.

---

## 7. Executar os testes

```bash
npm run typecheck     # TypeScript estrito
npm run lint          # ESLint
npm run build         # build de produção
npm run db:test       # migrations + regras de negócio + RLS em banco descartável
```

O `db:test` cria um banco **descartável** e não encosta no banco do Supabase.
Ele consegue um PostgreSQL sozinho, nesta ordem: `psql` no PATH com servidor
no ar, o container do Supabase local (se estiver de pé), ou um `postgres:16`
descartável via Docker. Para forçar um caminho ou apontar para outro servidor:

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres npm run db:test
DB_TEST_STRATEGY=docker npm run db:test      # psql | supabase | docker
```

Detalhes do que cada script verifica: `supabase/db-tests/README.md`.

Ao mexer em interface, confira também 360 px, 768 px e 1440 px — as capturas de
referência estão em `docs/screenshots/`.

---

## 8. Storage (logotipo e imagens)

A migration `20260829002000_storage.sql` cria dois buckets ao ser aplicada:

| Bucket | Leitura | Escrita | Para quê |
| --- | --- | --- | --- |
| `public-assets` | **qualquer um, sem login** | só administrador | logotipo e foto de produto — precisam abrir no PDF e na página pública do orçamento |
| `private-docs` | só administrador | só administrador | anexos futuros; hoje vazio |

Limites: 5 MB e apenas imagem (`png`, `jpeg`, `webp`, `svg`) no bucket público.

### Colocar o logotipo no PDF

Nada no gerador de PDF precisa mudar — ele já lê `app_settings.company.logo_url`.

1. No painel do Supabase, **Storage → public-assets → Upload**, envie o arquivo
   (por exemplo `empresa/logo-agrotork.png`).
2. Copie a URL pública que o painel mostra.
3. No **SQL Editor**:

```sql
update public.app_settings
   set value = value || jsonb_build_object('logo_url', 'COLE-A-URL-AQUI')
 where key = 'company';
```

Aproveite para preencher o resto do cabeçalho — o que ficar em branco
simplesmente não aparece no documento, e é assim de propósito:

```sql
update public.app_settings
   set value = value || jsonb_build_object(
     'legal_name', 'RAZÃO SOCIAL COMPLETA',
     'trade_name', 'AGROTORK',
     'document',   '00.000.000/0001-00',
     'phone',      '(43) 0000-0000',
     'whatsapp',   '(43) 90000-0000',
     'email',      'comercial@agrotork.com.br',
     'address',    'Rua, número, bairro',
     'city',       'Londrina',
     'state',      'PR',
     'zip_code',   '86000-000'
   )
 where key = 'company';
```

---

## 9. Expiração automática dos orçamentos

A função `expire_quotes()` existe desde a migration `0600` e passa para
`expired` todo orçamento **enviado** cuja validade venceu. Hoje **ninguém a
chama** — ela precisa de um agendamento.

O `EXECUTE` dela foi revogado de `authenticated` na migration `1000`: só
`service_role` executa. Isso é proposital, e o agendamento respeita:

1. No painel: **Database → Extensions**, habilite **`pg_cron`**.
2. No **SQL Editor**, agende a execução diária:

```sql
select cron.schedule(
  'expirar-orcamentos',
  '5 3 * * *',                       -- 03h05 UTC = 00h05 em Brasília
  $$ select public.expire_quotes(); $$
);
```

3. Conferir o agendamento e as execuções:

```sql
select jobid, schedule, jobname, active from cron.job;
select * from cron.job_run_details order by start_time desc limit 10;
```

4. Para remover: `select cron.unschedule('expirar-orcamentos');`

> **Não validado aqui.** `pg_cron` não existe no PostgreSQL local da suíte de
> testes, então o agendamento acima é o procedimento documentado, não uma
> configuração conferida. A função em si é testada (`04_travas_de_orcamento.sql`
> confere que ela expira o que deve e que o vendedor não consegue executá-la).

---

## 10. Publicar

### Onde cada coisa mora

| Camada | Onde |
| --- | --- |
| Aplicação (Next.js) | hospedagem com suporte a Node — a Vercel é o caminho mais direto por ser a fabricante do Next; qualquer plataforma que rode Node 20+ serve |
| Banco, Auth e Storage | Supabase |
| Desenvolvimento e testes | máquina local + PostgreSQL descartável (`npm run db:test`) e o duplê em `supabase/db-tests/auth-double` |

O sistema **não depende** de nada específico da Vercel: sem Edge Functions,
sem KV, sem Blob. A única exigência é Node no servidor, por causa da geração
de PDF (`pdfkit` está em `serverExternalPackages`).

### Passos

1. Suba o repositório no Git (confirme que `.env.local` **não** foi junto).
2. Importe o repositório na plataforma escolhida.
3. Cadastre as variáveis de ambiente:

   | Variável | Valor |
   | --- | --- |
   | `NEXT_PUBLIC_SUPABASE_URL` | URL do projeto Supabase |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | chave *anon public* |
   | `NEXT_PUBLIC_SITE_URL` | domínio de produção, com `https://` |

   **Não cadastre `SUPABASE_SERVICE_ROLE_KEY`.** Nenhum código a utiliza hoje;
   ver a explicação em `.env.example`.

4. Em **Supabase → Authentication → URL Configuration**, coloque o domínio de
   produção em *Site URL* e em *Redirect URLs*.
5. Deploy.

### Conferência depois do primeiro deploy

```bash
# cabeçalhos de segurança
curl -sD- -o /dev/null https://SEU-DOMINIO/login | grep -i -E "content-security-policy|x-frame|x-content-type"

# o cookie de sessão precisa ser httpOnly, Secure e SameSite=Lax
# (confira em DevTools → Application → Cookies depois de entrar)
```

Em produção o cookie ganha `Secure` automaticamente
(`NODE_ENV === "production"` em `lib/supabase/cookies.ts`); em `localhost`,
não — é o comportamento correto, porque `http://localhost` não é HTTPS.

---

## 11. Checklist de produção

Marque na ordem. Os quatro primeiros são obrigatórios; o resto é conferência.

- [ ] Projeto Supabase criado (região São Paulo) e `supabase link` feito
- [ ] `npm run db:push` aplicou as **21 migrations** sem erro
- [ ] `npm run db:types` regerou os tipos e `npm run typecheck` passou
- [ ] Primeiro administrador criado e promovido (seção 5)
- [ ] Dados da empresa preenchidos em `app_settings.company` (seção 8)
- [ ] Logotipo enviado ao bucket `public-assets` e a URL gravada
- [ ] `pg_cron` habilitado e `expirar-orcamentos` agendado (seção 9)
- [ ] Variáveis cadastradas na hospedagem, **sem** a service role
- [ ] *Site URL* e *Redirect URLs* apontando para o domínio real
- [ ] Login testado com o administrador e com um vendedor
- [ ] Vendedor **não** vê custo em `/produtos` nem na ficha
- [ ] Vendedor **não** enxerga orçamento de outro vendedor
- [ ] PDF baixa em `/orcamentos/[id]` e não traz custo nem observação interna
- [ ] Link público abre sem login, revoga e devolve 404 depois de revogado
- [ ] Cabeçalhos de segurança conferidos com `curl` (seção 10)

---

## Problemas comuns

| Sintoma | Causa provável |
| --- | --- |
| "Supabase ainda não configurado" na tela de login | `.env.local` ausente ou sem as duas variáveis públicas |
| "E-mail ou senha incorretos" com credenciais certas | usuário não confirmado — marque *Auto Confirm* ou confirme pelo painel |
| "Seu acesso está desativado" | `profiles.is_active = false` |
| Login funciona mas o painel fica zerado | migrations não aplicadas (`npm run db:push`) |
| `permission denied for table ...` | migration `20260829001000_grants.sql` não aplicada |
| Redirecionamento infinito no login | `NEXT_PUBLIC_SITE_URL` divergente do domínio real |


---

## Publicação

A publicação (GitHub → Netlify → variáveis de ambiente → URLs do Supabase →
domínio → HTTPS → smoke test → rollback) está em **`DEPLOY.md`**.

Os nomes das variáveis de produção estão em `.env.production.example` —
sem valores, de propósito.
