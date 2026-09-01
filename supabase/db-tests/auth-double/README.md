# Duplê de teste do Supabase

> **Isto NÃO é o Supabase.** É um servidor local mínimo que responde aos
> mesmos endpoints que o `@supabase/ssr` chama, para que o fluxo de
> autenticação do sistema possa ser exercitado **sem** um projeto Supabase
> e sem nenhuma credencial real.

## Para que serve

Valida o código do **nosso** lado: login, escrita e leitura dos cookies de
sessão, `getUser()` no proxy, proteção das rotas `(app)`, redirecionamento
com `?next=`, logout e as consultas do painel — todas passando pelo RLS de
um PostgreSQL de verdade.

## O que ele NÃO valida

O comportamento do GoTrue/PostgREST reais: política de senha, confirmação de
e-mail, rotação de refresh token, rate limiting, recuperação de senha. Isso só
é verificável contra um projeto Supabase.

## Endpoints implementados

| Endpoint | Uso |
| --- | --- |
| `POST /auth/v1/token?grant_type=password` | login |
| `POST /auth/v1/token?grant_type=refresh_token` | renovação de sessão |
| `GET /auth/v1/user` | quem está logado |
| `POST /auth/v1/logout` | logout |
| `GET \| HEAD /rest/v1/<tabela>` | subconjunto do PostgREST: `select`, `eq`, `neq`, `in`, `is`, `ilike`, `or`, `order`, `Range`, `Prefer: count=exact` |
| `POST /rest/v1/<tabela>` | insert e upsert (`on_conflict`), com `select` de retorno |
| `PATCH /rest/v1/<tabela>` | update com os mesmos filtros do GET |
| `DELETE /rest/v1/<tabela>` | delete com os mesmos filtros do GET — entrou na Fase 3, para remover componente de kit |
| `POST /rest/v1/rpc/<função>` | chamada de função com argumentos nomeados — entrou na Fase 4, para `discard_quote_draft` |

Toda consulta ao `/rest/v1` roda como o papel `authenticated` com
`request.jwt.claim.sub` do usuário — ou seja, **o RLS é aplicado de verdade**.

## Como executar

```bash
# 1. Banco local com as migrations e dados de exemplo
bash supabase/db-tests/dev-seed.sh

# 2. Dependências do duplê (isoladas do app)
cd supabase/db-tests/auth-double && npm install && cd -

# 3. Subir o duplê (imprime as variáveis para um .env.local DE TESTE)
node supabase/db-tests/auth-double/server.mjs

# 4. Em outro terminal: subir a aplicação apontando para o duplê
npm run build && npx next start -p 3302

# 5. Rodar as validações de ponta a ponta (semeia o banco antes de cada suíte)
BASE_URL=http://localhost:3302 bash supabase/db-tests/auth-double/run-e2e.sh
```

A suíte `e2e-expiracao.mjs` (Fase 6.2) roda `select public.expire_quotes();`
como `postgres` — exatamente o comando do job do pg_cron — e confere que o
resultado aparece sozinho na tela do vendedor, que o filtro **Expirado**
passa a encontrá-lo, e que `/rest/v1/rpc/expire_quotes` é recusado tanto
para o vendedor autenticado quanto para o anônimo.

As suítes contam registros, então precisam de um banco limpo cada uma —
é o que o `run-e2e.sh` garante. Rodar uma suíte solta também funciona:

```bash
bash supabase/db-tests/dev-seed.sh
node supabase/db-tests/auth-double/e2e-clientes.mjs
```

Nunca use essas chaves em produção: o segredo do JWT é fixo e público, e as
senhas de teste estão em `dev-seed.sh`.

## O que o `e2e-autenticacao.mjs` verifica

26 checagens, entre elas:

- rota protegida redireciona para `/login` preservando o destino (`?next=`);
- senha errada é recusada sem revelar se o e-mail existe;
- login válido entra e respeita o `?next=`;
- cookie de sessão é **httpOnly** e `sameSite=Lax`;
- sessão persiste entre abas; `/login` com sessão volta ao painel;
- logout limpa o cookie e a rota volta a ser protegida;
- **admin vê os 3 orçamentos, vendedor vê só 1** — RLS de verdade, no banco;
- vendedor não vê o menu Configurações e é barrado ao digitar a URL.

A captura `docs/screenshots/painel-vendedor-rls.png` é gerada por este script.

## O que o `e2e-clientes.mjs` verifica

31 checagens do módulo Clientes, entre elas:

- CNPJ inválido é recusado e o formulário não perde o que foi digitado;
- cadastro válido grava e a ficha mostra documento, WhatsApp e CEP formatados;
- documento duplicado é bloqueado com o nome do cliente já existente;
- busca funciona por nome parcial, documento e cidade;
- edição salva; desativar tira da listagem padrão; reativar devolve;
- vendedor cadastra cliente e vê a carteira compartilhada;
- **o histórico do cliente esconde orçamento de outro vendedor** (RLS);
- nenhuma rolagem horizontal em 360, 768 e 1440 px.

Gera as capturas `clientes-*.png` em `docs/screenshots/`.

## O que o `e2e-produtos.mjs` verifica

66 checagens do módulo Produtos, entre elas:

- validação de nome, unidade obrigatória e preço de venda;
- **a unidade escolhida sobrevive ao erro de validação** (regressão do reset de formulário);
- máscara monetária monta o valor da direita para a esquerda;
- margem derivada de custo e venda, e o atalho margem → preço de venda;
- código normalizado para maiúsculas e duplicidade bloqueada com mensagem clara,
  inclusive com caixa diferente;
- busca por código, nome e descrição; filtros e ordenação; paginação em 2 páginas;
- desativação com confirmação em dois passos, com opção de desistir;
- **vendedor não vê custo nem margem** na lista nem na ficha, não vê botões de
  escrita e é barrado ao digitar `/produtos/novo`;
- **código do fabricante**: exige marca, é único dentro da marca, aceita a mesma
  numeração em outro fabricante, é normalizado e entra na busca;
- ficha de produto vindo de catálogo mostra procedência, versão e dados técnicos,
  e a massa de teste aparece marcada como tal.

Gera as capturas `produtos-*.png` em `docs/screenshots/`.

## O que o `e2e-cadastros.mjs` verifica

64 checagens dos cadastros de apoio (marcas, categorias e unidades), entre elas:

- criação, edição, busca, filtro por situação e estado vazio nos três cadastros;
- duplicidade bloqueada **sem distinguir maiúsculas** ("Jacto" x "jacto");
- código de unidade normalizado para maiúsculas e recusado quando tem espaço;
- **`LT` e `L` convivem como unidades distintas** — nenhuma equivalência é presumida;
- desativação em dois passos, com opção de desistir, e reativação;
- registro inativo some do formulário de produto **e o servidor recusa mesmo com o
  campo forjado**: o teste reinsere a opção removida via DOM e confirma que o
  produto não é criado — a proteção não está no HTML;
- desativar preserva produto, vínculo e edição: o produto de uma marca desativada
  continua listado, continua mostrando a marca e continua salvável;
- **vendedor não vê Configurações** e é barrado nas seis rotas do módulo, mas
  consulta os cadastros ativos pelo catálogo e pelos filtros;
- nenhuma rolagem horizontal em 360, 768 e 1440 px.

Gera as capturas `configuracoes-*.png` e `cadastros-*.png` em `docs/screenshots/`.

## O que o `e2e-kits.mjs` verifica

69 checagens do módulo Kits, entre elas:

- validação do cabeçalho, código normalizado para maiúsculas e duplicidade bloqueada;
- criação leva direto para a montagem, e o kit nasce vazio dizendo isso;
- busca de componente por código, código de fabricante, nome, marca e categoria;
- **os dois papéis num clique:** o mesmo resultado da busca entra como obrigatório
  ou como opcional, pelo `value` do botão;
- produto que já está no kit aparece marcado e não pode entrar de novo;
- quantidade zero recusada; **fração recusada em unidade que não aceita** (UN) e
  aceita onde a unidade permite (M);
- **produto inativo não aparece na busca e o servidor recusa mesmo com o campo
  forjado** — o teste reescreve o `product_id` no DOM e confirma que nada entrou;
- alternar obrigatório ⇄ opcional, alterar quantidade e remover componente;
- ficha com composição separada, contagens, preço-base e preço unitário;
- desativar em dois passos com opção de desistir; composição preservada; reativar;
- kit sem obrigatórios marcado como **incompleto** na ficha e na listagem;
- **vendedor** vê só kits ativos, sem filtro de situação, sem botões de escrita,
  sem custo, e é barrado em `/kits/novo` e `/kits/[id]/editar`;
- nenhuma rolagem horizontal em 360, 768 e 1440 px, nas quatro telas.

Gera as capturas `kits-*.png` em `docs/screenshots/`.

## O que o `e2e-orcamentos.mjs` verifica

82 checagens do módulo Orçamentos, entre elas:

- criação com número gerado pelo banco; cliente obrigatório;
- produto avulso com quantidade, e subtotal recalculado pelo banco a cada item;
- **unidade UN recusa quantidade fracionada**; produto inativo não é oferecido;
- **kit incompleto e kit inativo ficam fora**, e o servidor recusa os dois mesmo
  quando o id é forçado pela URL;
- tela de opcionais com obrigatórios **marcados e desabilitados**;
- kit entra com o preço-base; marcar um opcional sobe o preço; desmarcar volta;
- **snapshot guarda os 3 componentes**, com os 2 não escolhidos registrados;
- quantidade do kit multiplica a linha e a composição mostra a quantidade efetiva;
- desconto por item, desconto percentual do orçamento e frete — todos conferidos
  contra o valor **gravado no banco**, não contra o que a tela mostra;
- desconto acima de 100% recusado, sem alterar o total;
- **o teste de histórico**: preço e nome dos produtos mudam, um componente sai do
  kit, o kit é renomeado e desativado — e o md5 dos itens do orçamento continua
  idêntico, com os nomes antigos ainda na tela;
- fluxo de situação (rascunho → enviado → aprovado), carimbo de envio, orçamento
  sem itens que não pode ser enviado, descarte de rascunho;
- **vendedor** não vê nem abre orçamento alheio, não tem filtro por vendedor, não
  vê custo, e é redirecionado ao tentar editar um aprovado;
- nenhuma rolagem horizontal em 360, 768 e 1440 px, nas quatro telas.

Gera as capturas `orcamentos-*.png` em `docs/screenshots/`.

## O que o `e2e-pdf-compartilhamento.mjs` verifica

72 checagens do PDF e do link público, entre elas:

**PDF**
- responde 200 com `application/pdf` e `content-disposition` de anexo;
- o arquivo começa com `%PDF-` e tem exatamente uma página (sem páginas em branco);
- traz número, empresa com CNPJ e contato, cliente, produto e marca do snapshot,
  kit com a composição incluída e os **opcionais não incluídos em seção à parte**,
  condições comerciais, observações, vendedor, total oficial e "página 1 de 1";
- **não** traz observação interna, custo, nem as palavras "margem" ou "custo";
- **teste crítico de histórico:** o PDF é gerado, o catálogo inteiro muda (preço,
  nome, composição do kit, produto e kit desativados) e o PDF é gerado de novo —
  os dois textos são idênticos.

**Compartilhamento**
- gerar link marca o rascunho como enviado; o token tem 48 caracteres hex e o
  endereço não contém o id do orçamento;
- a página pública abre sem login, mostra a proposta e formata o CNPJ;
- **não** mostra observação interna, custo, margem nem o id do orçamento, e é `noindex`;
- o PDF público responde 200 com o mesmo conteúdo restrito;
- token inexistente, token curto e o **id do orçamento usado como token** devolvem 404;
- token de outro orçamento abre só o outro; token expirado devolve 404;
- revogar invalida o link na hora (página e PDF), sem tocar no orçamento, e um
  link novo funciona;
- vendedor não baixa PDF nem administra link de orçamento alheio;
- página pública sem rolagem horizontal em 360, 768 e 1440 px.

Gera as capturas `orcamento-publico-*.png` e `orcamentos-compartilhamento.png`.
