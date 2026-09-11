# Operação do BRAIN — um caminho só

Quatro roteiros, na ordem. Todos rodam **no SQL Editor do Supabase**,
colados inteiros, de uma vez.

| Ordem | Arquivo | Quando |
| --- | --- | --- |
| 1 | `01-reconciliar-registro.sql` | antes de tudo, uma vez |
| 2 | `02-aplicar-brain.sql` | o deploy |
| 3 | `03-remover-brain-sem-dados.sql` | logo depois, se nada foi usado |
| 4 | `04-incidente-com-dados.sql` | incidente com dado real dentro |

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
