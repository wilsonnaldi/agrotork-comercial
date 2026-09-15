-- ============================================================
-- REMOVER UM DOCUMENTO INGERIDO — rollback de um lote da memória
-- ============================================================
-- Desfaz a ingestão de UM documento (todas as suas versões, páginas, trechos
-- e trilhas de ingestão), sem tocar em nenhum outro documento nem no esquema.
-- É o caminho de volta de um lote: DJI Subdealer, ARAG, o que for.
--
-- COMO USAR: troque o slug na linha `v_slug` abaixo e cole o arquivo inteiro
-- no SQL Editor do Supabase. Uma transação: qualquer pré-condição que falhe
-- aborta tudo e nada é removido.
--
-- O que ele apaga, e só isso:
--   · brain.document_chunks  (por cascata da versão)
--   · brain.document_pages   (por cascata da versão)
--   · brain.knowledge_ingestions (por cascata da versão)
--   · brain.document_versions (por cascata do documento)
--   · brain.documents        (a linha do slug)
--
-- O que ele NÃO apaga:
--   · a FONTE (brain.knowledge_sources). Fonte é compartilhada: a mesma
--     'dji' pode ter outros documentos amanhã. A chave estrangeira é
--     RESTRICT, então o banco recusaria de qualquer jeito — o roteiro só
--     informa se a fonte ficou órfã, para a remoção ser decisão humana.
--   · nada em public: o worker nunca escreveu lá, e isto também não escreve.
--   · o arquivo no Storage, quando houver: o objeto se apaga à parte,
--     depois, com o caminho que o relatório abaixo imprime.
--
-- Guarda de cardinalidade (regra 4 do CLAUDE.md): o roteiro conta o que vai
-- apagar ANTES de apagar e mostra o retrato. Se o número não for o que a
-- auditoria descreveu, aborte com `rollback;` em vez de `commit;`.
-- ============================================================

begin;

do $$
declare
  v_slug      text := 'dji-tabela-subdealer';   -- ← TROQUE AQUI
  v_doc       uuid;
  v_fonte     text;
  v_versoes   int;
  v_paginas   bigint;
  v_chunks    bigint;
  v_ingest    bigint;
  v_outros    int;
  v_caminhos  text;
begin
  select id, source_key into v_doc, v_fonte from brain.documents where slug = v_slug;
  if v_doc is null then
    raise exception 'documento % nao existe — nada a remover', v_slug;
  end if;

  select count(*) into v_versoes from brain.document_versions where document_id = v_doc;
  select count(*) into v_paginas from brain.document_pages p
    join brain.document_versions v on v.id = p.version_id where v.document_id = v_doc;
  select count(*) into v_chunks from brain.document_chunks c
    join brain.document_versions v on v.id = c.version_id where v.document_id = v_doc;
  select count(*) into v_ingest from brain.knowledge_ingestions i
    join brain.document_versions v on v.id = i.version_id where v.document_id = v_doc;
  select string_agg(coalesce(storage_bucket || '/' || storage_path, '(sem arquivo no Storage)'), E'\n    ')
    into v_caminhos from brain.document_versions where document_id = v_doc;
  select count(*) into v_outros from brain.documents where source_key = v_fonte and id <> v_doc;

  raise notice 'documento % (%)', v_slug, v_doc;
  raise notice '  versoes: %  paginas: %  trechos: %  ingestoes: %', v_versoes, v_paginas, v_chunks, v_ingest;
  raise notice '  arquivos no Storage (apagar a parte, depois):';
  raise notice '    %', coalesce(v_caminhos, '(nenhum)');
  if v_outros = 0 then
    raise notice '  a fonte "%" fica SEM documentos — remover ou nao e decisao humana', v_fonte;
  else
    raise notice '  a fonte "%" continua com % outro(s) documento(s) — nao mexer', v_fonte, v_outros;
  end if;

  delete from brain.documents where id = v_doc;

  -- Pós-condição: não pode sobrar nada pendurado na versão removida.
  if exists (select 1 from brain.document_versions where document_id = v_doc) then
    raise exception 'sobrou versao do documento % apos o delete', v_slug;
  end if;
  raise notice 'removido.';
end $$;

-- Confira o retrato acima antes de confirmar.
commit;
-- rollback;   -- ← use este no lugar do commit se a contagem nao bater
