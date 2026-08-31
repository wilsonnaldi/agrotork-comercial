# `supabase/tests/` — asserções estruturais (pgTAP)

```bash
npx supabase test db
```

Este diretório é o que o `supabase test db` executa (via `pg_prove`), e por
isso só pode conter testes que rodem **em qualquer ordem, quantas vezes
for**, sobre o banco local já povoado pelas migrations.

O que mora aqui: a conferência da **superfície de segurança** — RLS ligado,
policies presentes e com a regra certa, funções `security definer`,
privilégios de execução, triggers de numeração, enums, buckets do Storage.
São asserções de catálogo: nenhuma linha é escrita, e a transação é
desfeita no fim. É aqui que vale rodar contra o Supabase de verdade, com
`storage` e `auth` nativos.

O que **não** mora aqui: a suíte de comportamento. Ela é uma sequência
encadeada — `01` cria o usuário que `02` usa, `02` cria o orçamento que
`09` confere — com identificadores fixos que tornam as asserções legíveis
("o vendedor 2222… não enxerga o orçamento do admin"). Rodar aquilo sobre
um banco já povoado dá `duplicate key` em cascata, e "limpar tudo antes"
destruiria justamente o encadeamento que dá sentido aos testes. Por isso
ela vive em **`supabase/db-tests/`**, em banco descartável:

```bash
npm run db:test
```

As duas se complementam: uma diz que as regras **estão** no banco, a outra
diz que elas **funcionam**.
