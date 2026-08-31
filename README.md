# AGROTORK · Sistema Comercial

Sistema web para o núcleo comercial da AGROTORK:
**Cliente → Produtos → Kits → Orçamento → PDF → Compartilhamento.**

Funciona em computador, notebook, tablet e celular com o mesmo código.

| Documento | Conteúdo |
| --- | --- |
| [`SETUP.md`](./SETUP.md) | **Comece por aqui** — instalar, configurar, conectar o Supabase, criar o primeiro admin |
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | Decisões técnicas, camadas, segurança |
| [`DATABASE.md`](./DATABASE.md) | Modelo de dados e políticas de RLS |
| [`ROADMAP.md`](./ROADMAP.md) | Fases do projeto e critérios de pronto |

---

## Stack

Next.js 16 (App Router) · React 19 · TypeScript estrito · Tailwind CSS v4 ·
Supabase (PostgreSQL + Auth + Storage) · **pdfkit** (geração do PDF no servidor) · Vercel

---

## O que o sistema já faz

| Módulo | Situação |
| --- | --- |
| Autenticação, papéis e painel | ✅ |
| Clientes | ✅ |
| Produtos, com custo isolado do vendedor | ✅ |
| Cadastros de apoio (marcas, categorias, unidades) | ✅ |
| Kits, com itens obrigatórios e opcionais | ✅ |
| Orçamentos, com preços congelados | ✅ |
| **PDF e link público** | ✅ |
| Preparação para produção (Storage, CSP, runbook) | ✅ |
| Relatórios, expiração automática, auditoria | ⬜ Fase 6 |

> **Para publicar**, siga o `SETUP.md` — seções 8 a 11 cobrem Storage,
> agendamento da expiração, hospedagem e o checklist final. Falta apenas
> provisionar o projeto Supabase real.

### PDF do orçamento

Gerado no servidor em `/api/orcamentos/[id]/pdf`, a partir **somente** dos
dados congelados no orçamento — mudar o catálogo depois não altera um PDF já
emitido. Traz o cabeçalho da empresa vindo de `app_settings.company` (nada é
inventado: campo não preenchido simplesmente não aparece), o cliente, os itens
com a composição de cada kit, os totais oficiais do banco, as condições
comerciais e o rodapé com "página X de Y".

**Custo, margem e observações internas nunca entram no documento.**

### Link público

Na ficha do orçamento, *Gerar link público* cria um endereço
`/orcamento-publico/<token>` que o cliente abre sem login. O token tem 48
caracteres aleatórios gerados pelo PostgreSQL, expira, pode ser revogado a
qualquer momento e nunca dá acesso a outro orçamento. Compartilhar um rascunho
marca o orçamento como **enviado**.

O link mostra a mesma proposta do PDF — sem custo, sem margem, sem observações
internas e sem telefone ou e-mail do cliente.

---

## Como executar

### 1. Pré-requisitos
- Node.js 20 ou superior
- Uma conta gratuita no [Supabase](https://supabase.com)

### 2. Instalar as dependências
```bash
npm install
```

### 3. Criar o projeto no Supabase
1. Crie um projeto novo (região: **South America — São Paulo**).
2. Em **Project Settings → API**, copie `Project URL`, `anon public` e `service_role`.

### 4. Configurar as variáveis de ambiente
```bash
cp .env.example .env.local
```
Preencha `.env.local` com as chaves copiadas.
**Nunca** versione esse arquivo nem cole chaves no código.

### 5. Aplicar o banco de dados
Com o [Supabase CLI](https://supabase.com/docs/guides/cli) instalado:
```bash
supabase login
supabase link --project-ref SEU-PROJECT-REF
npm run db:push
```
Alternativa sem CLI: abrir o **SQL Editor** do Supabase e rodar os arquivos de
`supabase/migrations/` **na ordem numérica**.

### 6. Criar o primeiro usuário administrador
No painel do Supabase, **Authentication → Users → Add user** (e-mail + senha,
marque "Auto Confirm"). Depois, no **SQL Editor**:

```sql
update public.profiles
   set role = 'admin', full_name = 'Seu Nome'
 where email = 'seu-email@agrotork.com.br';
```

### 7. Rodar
```bash
npm run dev
```
Abra <http://localhost:3000>.

---

## Scripts

| Comando | O que faz |
| --- | --- |
| `npm run dev` | Ambiente de desenvolvimento |
| `npm run build` | Build de produção |
| `npm run start` | Sobe o build |
| `npm run lint` | ESLint |
| `npm run typecheck` | Checagem de tipos (`tsc --noEmit`) |
| `npm run db:push` | Aplica as migrations no Supabase |
| `npm run db:types` | Regera `src/types/database.types.ts` a partir do banco |
| `npm run db:types:local` | Mesmo arquivo, gerado das migrations num PostgreSQL local |
| `npm run db:test` | Aplica as migrations em um PostgreSQL descartável e testa regras, RLS e privilégios |

> Rode `typecheck`, `lint` e `build` **antes de considerar qualquer etapa pronta**.

---

## Deploy na Vercel

1. Suba o repositório no GitHub.
2. Na Vercel, **Add New → Project** e importe o repositório.
3. Em **Environment Variables**, cadastre as quatro variáveis do `.env.local`
   (`NEXT_PUBLIC_SITE_URL` deve apontar para o domínio de produção).
4. Deploy. A cada `git push` a Vercel publica; cada Pull Request ganha um preview.

---

## Estrutura

```
src/
├─ app/          rotas (App Router) — (auth) público, (app) protegido
├─ modules/      regra de negócio por domínio (schema, repository, service, actions)
├─ components/   ui/ (design system) e layout/ (casca da aplicação)
├─ lib/          supabase, auth, format, utils
├─ config/       empresa, navegação, permissões, rótulos
└─ types/        tipos do banco
supabase/migrations/   SQL versionado — fonte da verdade do schema
```

Detalhes e regras de dependência entre camadas: `ARCHITECTURE.md` §3.

---

## Segurança em uma linha

Row Level Security ativo em **todas** as tabelas, sessão em cookie `httpOnly`,
validação Zod no servidor e nenhuma chave no código. Ver `ARCHITECTURE.md` §9.

## Publicação

Ver [`DEPLOY.md`](DEPLOY.md) — GitHub, Netlify, variáveis de ambiente, URLs do Supabase, domínio, HTTPS, smoke test e rollback.
