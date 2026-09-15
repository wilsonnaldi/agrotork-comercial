# AGROTORK BRAIN — lote ARAG em produção

> **Nota de vocabulário.** "ERP" aqui é o schema `public` desta aplicação. O
> ERP da AGROTORK é a Compusystem (`ARCHITECTURE.md` §14).

Segundo documento da memória corporativa em produção, e o primeiro de
**planilha**. Ingerido em **15/09/2026**, depois que a migration
`20260915120000` (código puramente numérico é exato ou nada) fechou o bloqueio
descrito em `fase-2-arag.md` §7.

**Golden 7/7 · adversariais 14/14 · regressão Magnojet sem falha.**

## 1. O que entrou

| | |
| --- | --- |
| Fonte | `agrotork_interno` — "AGROTORK — documentos internos", `kind internal`, `commercial`, `external_processing forbidden` (**criada nesta rodada**) |
| Documento | `agrotork-orcamento-sistemas-arag` — "Orçamento interno — sistemas ARAG para bicos", `internal_note`, `commercial`, marca ARAG |
| Versão | `2024-10`, `valid_from 2024-10-17`, 1 página |
| Arquivo | `Arag.xlsx`, 9.974 bytes, sha256 `3d36a7f8…c1d9` |
| Ingestão | pipeline `lote-b.2`, parser `openpyxl 3.1.5`, método `xlsx` |
| Conteúdo | 1 página, 2 trechos `price_table`, **2 trusted, 0 degradada** |

A proveniência de planilha é **aba + intervalo de linhas**, não "página 1":
`aba: Página1, linhas 1–8` e `aba: Página1, linhas 10–17`.

## 2. Por que a fonte é a AGROTORK, e não a ARAG

O arquivo é um orçamento **interno** que cita peças ARAG. Não tem autoria da
ARAG, não tem vigência comercial declarada, e o `.xlsx` sequer tem
`docProps/core.xml` — não existe autor nem data de criação registrados dentro
dele. Chamá-lo de "catálogo ARAG" daria a ele uma autoridade que ele não tem.

Por isso: fonte `internal` da AGROTORK, marca ARAG **relacionada** pelo
`brand_id`, e um `provenance_note` na versão dizendo em letras claras que o
`valid_from` é a data técnica do arquivo no sistema de arquivos.

## 3. Como o conteúdo chegou em produção

O worker não tem — e não deve ter — credencial de produção. O caminho foi o
mesmo do Magnojet: **roteiro SQL no editor**, com o conteúdo gerado pelo
worker, não digitado.

1. `ensaiar-arag.sh` rodou sobre o arquivo real num PostgreSQL descartável;
2. o conteúdo gravado por ele foi extraído em chamadas `brain.ingestion_*`;
3. o roteiro foi **testado num segundo banco descartável** e comparado com o
   ensaio trecho a trecho;
4. só então foi executado em produção, numa transação com guards.

A prova de que produção recebeu exatamente o que foi ensaiado são os hashes,
idênticos nos três bancos (ensaio, replay e produção):

| trecho | `content_sha256` | `md5(table_data)` |
| --- | --- | --- |
| 0 · hidráulicos | `f54524e8…607c2` | `cbbb85bd…dcc7` |
| 1 · rotativos | `9510dce4…68a5c` | `bbcb3c4f…eec8` |

## 4. Gates

Golden 7/7 — G1/G1b sensor 466113200 e valor 1098; G2/G2b fluxômetro 4626215 e
valor 1630; G3 proveniência por aba e linhas nos dois blocos; G4 dois blocos,
dois títulos; G5 `46202G` reconhecido pela coluna COD só no rotativo.

Adversariais 14/14 — incluindo os três que dependem da `20260915120000`:
`466113201`, `46262150` e `46611320` devolvem **zero**, enquanto `466113200` e
`4626215` respondem pelo braço exato. Preço não virou código, telefone/CNPJ
não viraram código, fórmula não vazou como texto, bloco rotativo não aparece
sob o título hidráulico, zero escrita no ERP.

Regressão Magnojet — `MJ981CAP`, `MJ983CAP`, `MJ981CA → MJ981CAP`,
`MJ999CAP → zero`, `L_ha@12 = 77` numérico na p.20, **degraded leak 0**. O
`M 714` continua com as mesmas 3 evidências de antes: o ARAG não contaminou o
Magnojet, e o Magnojet não invadiu o ARAG.

## 5. Rollback

Não há script novo: `supabase/operacao/09-remover-documento-ingerido.sql`
já é parametrizado. Trocar a linha do slug por:

```sql
v_slug text := 'agrotork-orcamento-sistemas-arag';
```

Cardinalidades esperadas no retrato que ele imprime antes de apagar — se não
baterem, `rollback;` em vez de `commit;`:

| | |
| --- | --- |
| versões | 1 |
| páginas | 1 |
| trechos | 2 |
| ingestões | 1 |

A fonte `agrotork_interno` **não é removida**: ela é compartilhada por
desenho, e é onde os próximos documentos internos da AGROTORK vão entrar. O
roteiro avisa se ela ficar órfã, e a decisão é humana.

Não há objeto no Storage para apagar: o bucket `brain-documents` continua não
criado, e a versão registra o `storage_path` que ele terá quando existir —
mesmo padrão do Magnojet.

## 6. Estado depois da rodada

2 fontes, 2 documentos, 2 versões (uma ativa por documento), 173 páginas, 780
trechos, 272 tabelas das quais 68 degradadas — todas do Magnojet. Pontes
desligadas, divergências 0, ERP intacto (112 produtos, 2 pedidos).

DJI continua **não ingerido**: consulta por `DB1580`/`T55` devolve zero, e
isso é ausência de documento, não regressão.
