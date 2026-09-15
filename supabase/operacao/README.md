# Operação do BRAIN — um caminho só

Três roteiros na ordem do deploy, mais dois de reversão. Todos rodam **no SQL Editor do Supabase**,
colados inteiros, de uma vez.

| Ordem | Arquivo | Quando |
| --- | --- | --- |
| 1 | `01-reconciliar-registro.sql` | antes de tudo, uma vez |
| 2 | `02-aplicar-brain.sql` | o deploy |
| 3 | `05-agendar-reconciliacao.sql` | logo depois do 02, para ligar o cron |
| — | `03-remover-brain-sem-dados.sql` | reversão, se nada foi usado |
| — | `04-incidente-com-dados.sql` | incidente com dado real dentro |

## Por que SQL Editor, e só ele

A garantia deste pacote é que **aplicação, validações e registro das
migrations acontecem na mesma transação**. Um `COMMIT` numa transação
abortada é executado como `ROLLBACK`, então qualquer validação que falhe
desfaz tudo.

Isso exige o arquivo inteiro numa execução só. As alternativas foram
descartadas, e por motivo:

- **`psql -f` com `\i`** funcionaria, mas obrigaria a manter dois
  roteiros — um com `\i` e um sem — e dois roteiros divergem em silêncio.
  Além disso o `\i` depende do diretório de trabalho, o que já quebrou
  uma vez aqui.
- **`supabase db push`** aplica as migrations e registra, mas **não roda
  as validações no mesmo COMMIT**: ele confirma cada migration
  separadamente. Uma pós-condição que falhasse não desfaria a anterior.
- **Rodar em pedaços** anula a transação. É a pior das três.

Por isso `02-aplicar-brain.sql` é **gerado**: o template
(`02-aplicar-brain.template.sql`) marca `-- @incluir <migration>` e
`gerar-consolidado.sh` embute o texto. Assim há um arquivo só para colar
e nenhuma cópia das migrations envelhecendo à parte —
`supabase/db-tests/conferir-operacao.sh` regera e compara a cada
execução.

**Editou uma migration do BRAIN? Rode `bash
supabase/operacao/gerar-consolidado.sh` e comite o resultado.**

## Rodar duas vezes

- **01** é seguro. Na segunda execução as nove linhas caem em "já
  acertada", a transação confirma e nada muda. A cópia do registro é
  guardada com carimbo de hora, então execuções diferentes não brigam.
- **02** não é, e recusa: a primeira coisa que ele confere é se o schema
  `brain` já existe.
- **03** e **04** recusam se o estado não for o que esperam.

## Se o `lock_timeout` estourar

03 e 04 tiram gatilhos de `public.quotes` e `public.orders`, o que pede
ACCESS EXCLUSIVE nessas tabelas. Eles usam `lock_timeout = 3s` de
propósito: numa base com movimento, esperar pelo lock enfileira todo
mundo atrás. Estourou? A transação aborta inteira, nada fica pela
metade. Veja quem está segurando e tente de novo:

```sql
select pid, state, wait_event_type, xact_start, left(query, 60)
  from pg_stat_activity
 where state <> 'idle' and pid <> pg_backend_pid()
 order by xact_start;
```

## Modo desacoplado

O primeiro deploy entra com as **três pontes desabilitadas**: os gatilhos
existem, e estão `DISABLE`. Nenhum código do BRAIN roda dentro da
transação de orçamento ou de pedido.

Quem liga o ERP ao BRAIN é o pg_cron, a cada minuto:

```
ERP confirma orçamento/pedido
  → a transação comercial termina, sem nada do BRAIN dentro
  → pg_cron chama brain.reconciliar_erp_periodico()
  → divergencias_erp() acha o que falta
  → reconciliar_erp() corrige
  → o BRAIN recebe evento, vínculo e estágio
  → a execução seguinte devolve relatório vazio
```

Conferir o estado das pontes a qualquer momento:

```sql
select * from brain.estado_das_pontes();   -- habilitado tem de ser false nos 3
```

Religar é uma migration nova com `alter table ... enable trigger`, não uma
edição do arquivo — e só depois de a reconciliação periódica ter rodado
tempo suficiente para se confiar nela.

## Depois de um período com a ponte desligada

```sql
select * from brain.divergencias_erp();   -- o que ficou fora de acordo
select * from brain.reconciliar_erp();    -- conserta e diz quanto
select * from brain.divergencias_erp();   -- tem de vir VAZIO
```

O critério de sucesso é o relatório vazio — não "zero eventos
faltantes". A reconciliação também põe a oportunidade no estágio certo,
liga o pedido, marca a venda ganha, converte o lead e desfaz a venda
cancelada no escuro. Ela não atropela decisão humana: oportunidade em
`lost` fica em `lost`.

## Reverter a busca de código numérico

`10-reverter-codigo-numerico-exato.sql` desfaz a migration
`20260915120000` e devolve `brain.search_knowledge` à definição de
`20260912040000`, byte a byte.

Ele **reintroduz um defeito de propósito**: sem a `20260915120000`, uma
pergunta por código puramente numérico que não existe (`466113201`) é
resolvida para o vizinho a um dígito (`466113200`) — quer dizer, o
sistema responde sobre uma peça com o dado de outra. Só se usa se a
correção quebrar em produção algo pior do que isso.

O script confere a assinatura antes, é transacional, reaplica os grants
e aborta se `anon` ou `public` ficarem com `EXECUTE`. A diferença de md5
que ele produz em produção é comentário, não código — está explicada no
cabeçalho do arquivo.

## Reverter o lote ARAG

`09-remover-documento-ingerido.sql` já serve: é parametrizado por slug.
Trocar a linha do slug por

```sql
v_slug text := 'agrotork-orcamento-sistemas-arag';
```

e conferir, no retrato que ele imprime ANTES de apagar: 1 versão, 1 página,
2 trechos, 1 ingestão. Se algum número divergir, `rollback;` em vez de
`commit;` — o banco não é o que a auditoria descreveu.

A fonte `agrotork_interno` fica: ela é compartilhada por desenho e vai
receber os próximos documentos internos da AGROTORK. O roteiro avisa se ela
ficar órfã; remover é decisão humana.

Detalhe do lote em `docs/brain/fase-2-arag-producao.md`.
