-- ============================================================
-- AGROTORK BRAIN — Fase 2, Lote B: ingestão sem vetores
-- ============================================================
-- O Lote A criou as tabelas da memória e a busca. Este lote cria o CAMINHO
-- por onde um arquivo vira versão → páginas → chunks → metadados, e a
-- porta pela qual o aplicativo consulta a memória. Continua sem vetor.
--
-- O que entra aqui:
--
--   1. API de ingestão em SQL (`brain.register_version`,
--      `brain.ingestion_start/add_page/add_chunk/finish/fail`). O worker
--      (Python, fora do banco — brain/worker) só chama estas funções; toda
--      regra — checksum, idempotência, página obrigatória, contagens,
--      estado coerente — mora aqui, então vale para qualquer worker futuro.
--      `security invoker`: quem chama precisa poder escrever nas tabelas
--      (administrador pelo RLS, ou service_role/postgres).
--
--   2. Auditoria de consulta: `brain.knowledge_queries`. Cada busca feita
--      pelo aplicativo deixa quem perguntou, o que, com que nível, quantos
--      resultados e quais chunks. Sem o texto dos resultados.
--
--   3. A porta do aplicativo: `public.brain_search()` e
--      `public.brain_provenance()`. O schema `brain` não é exposto ao
--      PostgREST (decisão: nada do BRAIN vira endpoint por acidente); estas
--      duas funções em `public` são as ÚNICAS que o app enxerga, são
--      `security invoker` e só repassam para as funções do brain, que já
--      filtram por RLS. `brain_search` registra a auditoria.
--
--   4. Storage: as policies do bucket `brain-documents` em storage.objects
--      (leitura por nível da versão dona do arquivo; escrita só do
--      administrador e só em nome que é `storage_path` de uma versão
--      registrada — sem objeto órfão). O BUCKET NÃO É CRIADO AQUI: criar exige decisão de
--      plano (o plano atual limita o arquivo a 50 MB; o Catálogo Magnojet
--      V41 tem 177 MB). O roteiro supabase/operacao/07-criar-bucket-brain-
--      documents.sql cria o bucket quando autorizado; as policies abaixo
--      ficam inertes até lá.
--
-- O que NÃO entra: pgvector, embedding, worker dentro do banco, gatilho em
-- tabela do ERP, escrita em preço/custo/estoque.
--
-- Compatibilidade: PostgreSQL 16, 17.6 e 18.6. Nada de `SET <guc de
-- extensão>` na declaração de função (o Supabase gerenciado recusa —
-- docs/brain/fase-2-lote-a.md §17).
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. Auditoria de consulta
-- ════════════════════════════════════════════════════════════
create table brain.knowledge_queries (
  id            bigint generated always as identity primary key,
  user_id       uuid references public.profiles(id) on delete set null,
  caller_level  brain.access_level,                 -- nivel no momento da pergunta
  query_text    text not null,                      -- ja cortado em 1000 caracteres
  filters       jsonb not null default '{}'::jsonb,
  hits          integer not null default 0,
  top_chunk_ids bigint[] not null default '{}',     -- os ids devolvidos, na ordem
  duration_ms   integer,
  origin        text not null default 'app' check (origin in ('app', 'test', 'other')),
  created_at    timestamptz not null default now()
);

create index idx_knowledge_queries_user on brain.knowledge_queries (user_id, created_at desc);
create index idx_knowledge_queries_at   on brain.knowledge_queries (created_at desc);

comment on table brain.knowledge_queries is
  'Trilha de consulta a memoria: quem perguntou, o que, com que nivel, quantos resultados e quais chunks. Nunca guarda o conteudo devolvido.';

alter table brain.knowledge_queries enable row level security;

-- Quem pergunta registra a PROPRIA pergunta; so o administrador le a trilha.
create policy knowledge_queries_insert_self on brain.knowledge_queries for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.is_active_user()));
create policy knowledge_queries_admin_select on brain.knowledge_queries for select to authenticated
  using ((select public.is_admin()));
-- Trilha e append-only para a API: sem policy de update/delete → ninguem altera ou apaga.

grant select, insert on brain.knowledge_queries to authenticated, service_role;
grant usage, select on sequence brain.knowledge_queries_id_seq to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- 1b. Ajuste no Lote A: conteudo repetido em paginas diferentes
-- ════════════════════════════════════════════════════════════
-- `uq_chunk_content` era (version_id, content_sha256). Um catalogo real
-- repete texto em paginas diferentes (rodape legal, aviso, a mesma tabela
-- em duas paginas) e o worker esbarrava nisso no primeiro documento
-- sintetico com um paragrafo repetido. A unidade de proveniencia e a
-- PAGINA: o mesmo conteudo em paginas diferentes sao dois chunks legitimos,
-- cada um citando a sua pagina. Dentro da mesma pagina continua unico.
alter table brain.document_chunks drop constraint uq_chunk_content;
alter table brain.document_chunks add constraint uq_chunk_content unique (version_id, page_from, content_sha256);

-- ── Titulos entram na busca ─────────────────────────────────
-- "SOL ULTRA GROSSA · CONE VAZIO" e o titulo da tabela, nao esta no texto
-- das linhas. Sem isto, "cone vazio ultra grossa" nao acha a tabela. O
-- caminho de titulos vira texto normalizado (gatilho) e entra no `fts` com
-- peso A; o conteudo fica com peso B. O trigram continua so no conteudo.
alter table brain.document_chunks add column heading_norm text not null default '';
alter table brain.document_chunks drop column fts;
alter table brain.document_chunks add column fts tsvector generated always as (
  setweight(to_tsvector('portuguese'::regconfig, heading_norm), 'A')
  || setweight(to_tsvector('portuguese'::regconfig, content_norm), 'B')
) stored;
create index idx_chunks_fts on brain.document_chunks using gin (fts);

create or replace function brain.stamp_chunk()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select v.access_level into new.access_level from brain.document_versions v where v.id = new.version_id;
  if new.access_level is null then
    raise exception 'Chunk sem versao: %', new.version_id using errcode = 'foreign_key_violation';
  end if;
  if not exists (select 1 from brain.knowledge_ingestions i where i.id = new.ingestion_id and i.version_id = new.version_id) then
    raise exception 'A ingestao % nao e desta versao %', new.ingestion_id, new.version_id using errcode = 'foreign_key_violation';
  end if;
  new.content_norm   := coalesce(brain.normalize_text(new.content), '');
  new.heading_norm   := coalesce(brain.normalize_text(array_to_string(new.heading_path, ' ')), '');
  new.content_sha256 := encode(sha256(convert_to(new.content, 'UTF8')), 'hex');
  new.codes := coalesce((select array_agg(distinct c order by c)
                           from unnest(new.codes) raw, lateral (select brain.normalize_code(raw)) n(c)
                          where c is not null), '{}');
  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. API de ingestao
-- ════════════════════════════════════════════════════════════

-- Registrar (ou reencontrar) a versao de um arquivo.
--   · mesmo documento + mesmo sha256 → devolve a versao que ja existe (nada
--     duplica; o worker pode ser reexecutado sem medo);
--   · arquivo diferente → versao NOVA, em `draft`. Ativar e decisao
--     separada (`update ... set status = 'active'`), nunca automatica.
create or replace function brain.register_version(
  p_document_id        uuid,
  p_version_label      text,
  p_file_sha256        text,
  p_original_filename  text,
  p_mime_type          text,
  p_file_size          bigint,
  p_document_date      date    default null,
  p_page_count         integer default null,
  p_metadata           jsonb   default '{}'::jsonb
)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_id      uuid;
  v_doc     record;
  v_ext     text;
  v_path    text;
  v_sha     text := lower(coalesce(p_file_sha256, ''));
begin
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'sha256 invalido' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_file_size, 0) <= 0 then
    raise exception 'file_size deve ser positivo' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(btrim(p_version_label), '') = '' then
    raise exception 'version_label obrigatorio' using errcode = 'invalid_parameter_value';
  end if;

  select d.id, d.slug, d.source_key into v_doc from brain.documents d where d.id = p_document_id;
  if v_doc.id is null then
    raise exception 'Documento % nao existe (ou nao e visivel)', p_document_id using errcode = 'no_data_found';
  end if;

  -- Ja registrada? Mesmo arquivo, mesma obra: e a mesma versao.
  select v.id into v_id from brain.document_versions v
   where v.document_id = p_document_id and v.file_sha256 = v_sha;
  if v_id is not null then
    return v_id;
  end if;
  -- Mesmo rotulo, arquivo diferente: nao e "a mesma versao corrigida" — e
  -- um erro do operador. Rotulo novo para arquivo novo.
  if exists (select 1 from brain.document_versions v where v.document_id = p_document_id and v.version_label = btrim(p_version_label)) then
    raise exception 'O rotulo % ja pertence a outro arquivo deste documento; arquivo diferente pede rotulo diferente', btrim(p_version_label)
      using errcode = 'unique_violation';
  end if;

  -- Caminho canonico: <fonte>/<documento>/<rotulo>/<sha256>.<ext>
  v_ext := lower(nullif(regexp_replace(coalesce(p_original_filename, ''), '^.*\.', ''), coalesce(p_original_filename, '')));
  if v_ext is null or v_ext !~ '^[a-z0-9]{1,8}$' then v_ext := 'bin'; end if;
  v_path := v_doc.source_key || '/' || v_doc.slug || '/'
         || regexp_replace(btrim(p_version_label), '[^A-Za-z0-9._-]+', '-', 'g') || '/'
         || v_sha || '.' || v_ext;

  insert into brain.document_versions
    (document_id, version_label, status, document_date, storage_path, original_filename,
     mime_type, file_size, file_sha256, page_count, metadata, imported_by)
  values
    (p_document_id, btrim(p_version_label), 'draft', p_document_date, v_path, coalesce(p_original_filename, v_sha || '.' || v_ext),
     coalesce(p_mime_type, 'application/octet-stream'), p_file_size, v_sha, p_page_count, coalesce(p_metadata, '{}'::jsonb),
     (select auth.uid()))
  returning id into v_id;
  return v_id;
end;
$$;

-- Abrir uma ingestao. Uma versao que JA tem paginas/chunks so e reprocessada
-- com `p_replace = true`: as paginas e chunks antigos saem, a ingestao antiga
-- fica como historico apontando para a nova.
--
-- ATOMICIDADE (auditoria pos-publicacao): a remocao do conteudo antigo, as
-- paginas e chunks novos e o fechamento (`ingestion_finish`) pertencem a UMA
-- transacao do chamador — o worker nao confirma nada entre `ingestion_start`
-- e `ingestion_finish`. Se qualquer passo falhar, o rollback devolve as
-- paginas e chunks anteriores exatamente como estavam; a tentativa e entao
-- registrada por `ingestion_record_failure` numa transacao propria. Um
-- replace que falha NUNCA deixa a versao sem o conhecimento valido anterior.
--
-- CONCORRENCIA: a linha da versao e travada (`for update`) ate o fim da
-- transacao. Dois workers na mesma versao se serializam: o segundo espera o
-- primeiro terminar e entao ve o conteudo dele (e e recusado sem replace).
create or replace function brain.ingestion_start(
  p_version_id        uuid,
  p_method            text,
  p_parser            text,
  p_pipeline_version  text,
  p_executor          text    default null,
  p_needs_ocr         boolean default false,
  p_pages_total       integer default null,
  p_replace           boolean default false
)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_id uuid;
  v_n  int;
begin
  -- Trava a versao ate o COMMIT do chamador: serializa ingestoes concorrentes.
  perform 1 from brain.document_versions v where v.id = p_version_id for update;
  if not found then
    raise exception 'Versao % nao existe (ou nao e visivel)', p_version_id using errcode = 'no_data_found';
  end if;
  if coalesce(btrim(p_pipeline_version), '') = '' then
    raise exception 'pipeline_version obrigatorio' using errcode = 'invalid_parameter_value';
  end if;
  -- Uma ingestao aberta e COMMITADA so existe se alguem confirmou no meio (SQL
  -- a mao); o worker nunca faz isso. Ainda assim, nao se abre outra por cima.
  if exists (select 1 from brain.knowledge_ingestions i where i.version_id = p_version_id
              and i.status in ('pending', 'extracting', 'chunking')) then
    raise exception 'Ja existe uma ingestao em andamento para a versao %', p_version_id using errcode = 'object_in_use';
  end if;

  select count(*) into v_n from brain.document_chunks c where c.version_id = p_version_id;
  if v_n > 0 or exists (select 1 from brain.document_pages pg where pg.version_id = p_version_id) then
    if not p_replace then
      raise exception 'A versao % ja tem conteudo ingerido (% chunks). Use p_replace = true para reprocessar.', p_version_id, v_n
        using errcode = 'unique_violation';
    end if;
    delete from brain.document_chunks where version_id = p_version_id;
    delete from brain.document_pages  where version_id = p_version_id;
  end if;

  insert into brain.knowledge_ingestions
    (version_id, status, method, parser, pipeline_version, needs_ocr, executor, started_at, pages_total, created_by)
  values
    (p_version_id, 'extracting', p_method, p_parser, btrim(p_pipeline_version), coalesce(p_needs_ocr, false), p_executor, now(), p_pages_total, (select auth.uid()))
  returning id into v_id;

  if v_n > 0 or p_replace then
    update brain.knowledge_ingestions i
       set metadata = i.metadata || jsonb_build_object('replaced_by', v_id, 'replaced_at', now())
     where i.version_id = p_version_id and i.id <> v_id and i.status in ('completed', 'partial', 'failed');
  end if;
  return v_id;
end;
$$;

-- Uma pagina. Reenviar a mesma pagina na MESMA ingestao substitui o texto
-- (o worker pode corrigir); de outra ingestao, nunca.
create or replace function brain.ingestion_add_page(
  p_ingestion_id  uuid,
  p_page_no       integer,
  p_text          text,
  p_extraction    text,
  p_ocr           boolean default false,
  p_layout        jsonb   default '{}'::jsonb,
  p_metadata      jsonb   default '{}'::jsonb
)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_version uuid; v_status brain.ingestion_status;
begin
  select i.version_id, i.status into v_version, v_status from brain.knowledge_ingestions i where i.id = p_ingestion_id;
  if v_version is null then
    raise exception 'Ingestao % nao existe (ou nao e visivel)', p_ingestion_id using errcode = 'no_data_found';
  end if;
  if v_status not in ('extracting', 'chunking') then
    raise exception 'Ingestao % nao esta aberta (status %)', p_ingestion_id, v_status using errcode = 'object_not_in_prerequisite_state';
  end if;
  insert into brain.document_pages (version_id, page_no, ingestion_id, text, extraction, ocr, layout, metadata)
  values (v_version, p_page_no, p_ingestion_id, coalesce(p_text, ''), p_extraction, coalesce(p_ocr, false),
          coalesce(p_layout, '{}'::jsonb), coalesce(p_metadata, '{}'::jsonb))
  on conflict (version_id, page_no) do update
     set text = excluded.text, extraction = excluded.extraction, ocr = excluded.ocr,
         layout = excluded.layout, metadata = excluded.metadata, ingestion_id = excluded.ingestion_id
   where brain.document_pages.ingestion_id = excluded.ingestion_id;
  if not found then
    raise exception 'Pagina % da versao % pertence a outra ingestao', p_page_no, v_version using errcode = 'unique_violation';
  end if;
  update brain.knowledge_ingestions i set status = 'chunking'
   where i.id = p_ingestion_id and i.status = 'extracting';
end;
$$;

-- Um chunk. A pagina precisa existir (FK composta); tabela precisa de
-- estrutura (constraint); codigos sao normalizados pelo gatilho.
create or replace function brain.ingestion_add_chunk(
  p_ingestion_id  uuid,
  p_ordinal       integer,
  p_kind          brain.chunk_kind,
  p_page_from     integer,
  p_page_to       integer,
  p_content       text,
  p_heading_path  text[]  default '{}',
  p_table_data    jsonb   default null,
  p_codes         text[]  default '{}',
  p_token_count   integer default null,
  p_metadata      jsonb   default '{}'::jsonb
)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare v_version uuid; v_status brain.ingestion_status; v_id bigint;
begin
  select i.version_id, i.status into v_version, v_status from brain.knowledge_ingestions i where i.id = p_ingestion_id;
  if v_version is null then
    raise exception 'Ingestao % nao existe (ou nao e visivel)', p_ingestion_id using errcode = 'no_data_found';
  end if;
  if v_status not in ('extracting', 'chunking') then
    raise exception 'Ingestao % nao esta aberta (status %)', p_ingestion_id, v_status using errcode = 'object_not_in_prerequisite_state';
  end if;
  if not exists (select 1 from brain.document_pages pg where pg.version_id = v_version and pg.page_no = p_page_from) then
    raise exception 'Chunk aponta para a pagina %, que nao foi registrada nesta versao', p_page_from using errcode = 'foreign_key_violation';
  end if;
  insert into brain.document_chunks
    (version_id, ingestion_id, ordinal, kind, page_from, page_to, heading_path, content, table_data, codes, token_count, metadata)
  values
    (v_version, p_ingestion_id, p_ordinal, p_kind, p_page_from, coalesce(p_page_to, p_page_from),
     coalesce(p_heading_path, '{}'), p_content, p_table_data, coalesce(p_codes, '{}'), p_token_count, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_id;
  update brain.knowledge_ingestions i set status = 'chunking' where i.id = p_ingestion_id and i.status = 'extracting';
  return v_id;
end;
$$;

-- Fechar: contagens saem das tabelas (nao do que o worker diz), status
-- coerente, erro obrigatorio em `failed`.
create or replace function brain.ingestion_finish(
  p_ingestion_id  uuid,
  p_status        brain.ingestion_status default 'completed',
  p_error         text  default null,
  p_warnings      jsonb default '[]'::jsonb,
  p_metrics       jsonb default '{}'::jsonb
)
returns brain.knowledge_ingestions language plpgsql security invoker set search_path = '' as $$
declare v_row brain.knowledge_ingestions; v_pages int; v_chunks int; v_tables int;
begin
  select * into v_row from brain.knowledge_ingestions i where i.id = p_ingestion_id;
  if v_row.id is null then
    raise exception 'Ingestao % nao existe (ou nao e visivel)', p_ingestion_id using errcode = 'no_data_found';
  end if;
  if v_row.status not in ('extracting', 'chunking', 'pending') then
    raise exception 'Ingestao % ja foi fechada (status %)', p_ingestion_id, v_row.status using errcode = 'object_not_in_prerequisite_state';
  end if;
  if p_status not in ('completed', 'failed', 'partial') then
    raise exception 'Status final invalido: %', p_status using errcode = 'invalid_parameter_value';
  end if;
  if p_status = 'failed' and coalesce(btrim(p_error), '') = '' then
    raise exception 'Ingestao falhada precisa de erro' using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_pages  from brain.document_pages  pg where pg.ingestion_id = p_ingestion_id;
  select count(*), count(*) filter (where kind in ('table', 'price_table')) into v_chunks, v_tables
    from brain.document_chunks c where c.ingestion_id = p_ingestion_id;

  -- "completed" com zero paginas nao e conclusao: e falha disfarcada.
  if p_status = 'completed' and v_pages = 0 then
    raise exception 'Ingestao completed sem nenhuma pagina registrada' using errcode = 'check_violation';
  end if;
  if p_status = 'completed' and v_row.pages_total is not null and v_pages < v_row.pages_total then
    raise exception 'Ingestao completed com % de % paginas — use partial', v_pages, v_row.pages_total using errcode = 'check_violation';
  end if;

  update brain.knowledge_ingestions i
     set status = p_status, error = nullif(btrim(coalesce(p_error, '')), ''),
         warnings = coalesce(p_warnings, '[]'::jsonb), metrics = coalesce(p_metrics, '{}'::jsonb),
         finished_at = now(), pages_done = v_pages, chunks_created = v_chunks, tables_created = v_tables,
         pages_total = coalesce(i.pages_total, v_pages)
   where i.id = p_ingestion_id
  returning * into v_row;
  return v_row;
end;
$$;

-- Atalho para o worker registrar uma falha sem perder o que ja entrou.
create or replace function brain.ingestion_fail(p_ingestion_id uuid, p_error text, p_warnings jsonb default '[]'::jsonb)
returns brain.knowledge_ingestions language sql security invoker set search_path = '' as $$
  select brain.ingestion_finish(p_ingestion_id, 'failed', p_error, p_warnings, '{}'::jsonb);
$$;

-- Registrar uma tentativa que FALHOU e foi desfeita por rollback: a ingestao
-- aberta nao existe mais (saiu com o rollback), entao a trilha e escrita
-- aqui, numa transacao propria, sem pagina nem chunk. `p_replace_attempt`
-- diz se era um reprocessamento (o conteudo anterior continua intacto).
create or replace function brain.ingestion_record_failure(
  p_version_id        uuid,
  p_method            text,
  p_parser            text,
  p_pipeline_version  text,
  p_executor          text,
  p_error             text,
  p_warnings          jsonb   default '[]'::jsonb,
  p_replace_attempt   boolean default false,
  p_started_at        timestamptz default null
)
returns brain.knowledge_ingestions language plpgsql security invoker set search_path = '' as $$
declare v_row brain.knowledge_ingestions;
begin
  if not exists (select 1 from brain.document_versions v where v.id = p_version_id) then
    raise exception 'Versao % nao existe (ou nao e visivel)', p_version_id using errcode = 'no_data_found';
  end if;
  if coalesce(btrim(p_error), '') = '' then
    raise exception 'Falha registrada precisa de erro' using errcode = 'invalid_parameter_value';
  end if;
  insert into brain.knowledge_ingestions
    (version_id, status, method, parser, pipeline_version, executor, started_at, finished_at,
     pages_done, chunks_created, tables_created, error, warnings, metadata, created_by)
  values
    (p_version_id, 'failed', coalesce(p_method, 'other'), p_parser, coalesce(nullif(btrim(p_pipeline_version), ''), 'desconhecido'),
     p_executor, coalesce(p_started_at, now()), now(), 0, 0, 0, btrim(p_error), coalesce(p_warnings, '[]'::jsonb),
     jsonb_build_object('rolled_back', true, 'replace_attempt', coalesce(p_replace_attempt, false)), (select auth.uid()))
  returning * into v_row;
  return v_row;
end;
$$;

revoke execute on function brain.ingestion_record_failure(uuid, text, text, text, text, text, jsonb, boolean, timestamptz) from public, anon;
grant  execute on function brain.ingestion_record_failure(uuid, text, text, text, text, text, jsonb, boolean, timestamptz) to authenticated, service_role;

revoke execute on function brain.register_version(uuid, text, text, text, text, bigint, date, integer, jsonb) from public, anon;
revoke execute on function brain.ingestion_start(uuid, text, text, text, text, boolean, integer, boolean)      from public, anon;
revoke execute on function brain.ingestion_add_page(uuid, integer, text, text, boolean, jsonb, jsonb)         from public, anon;
revoke execute on function brain.ingestion_add_chunk(uuid, integer, brain.chunk_kind, integer, integer, text, text[], jsonb, text[], integer, jsonb) from public, anon;
revoke execute on function brain.ingestion_finish(uuid, brain.ingestion_status, text, jsonb, jsonb)           from public, anon;
revoke execute on function brain.ingestion_fail(uuid, text, jsonb)                                            from public, anon;
grant  execute on function brain.register_version(uuid, text, text, text, text, bigint, date, integer, jsonb) to authenticated, service_role;
grant  execute on function brain.ingestion_start(uuid, text, text, text, text, boolean, integer, boolean)      to authenticated, service_role;
grant  execute on function brain.ingestion_add_page(uuid, integer, text, text, boolean, jsonb, jsonb)         to authenticated, service_role;
grant  execute on function brain.ingestion_add_chunk(uuid, integer, brain.chunk_kind, integer, integer, text, text[], jsonb, text[], integer, jsonb) to authenticated, service_role;
grant  execute on function brain.ingestion_finish(uuid, brain.ingestion_status, text, jsonb, jsonb)           to authenticated, service_role;
grant  execute on function brain.ingestion_fail(uuid, text, jsonb)                                            to authenticated, service_role;
-- `authenticated` so consegue algo com estas funcoes se for administrador:
-- todas escrevem em tabelas cujo INSERT/UPDATE/DELETE e `is_admin()` no RLS.

-- ════════════════════════════════════════════════════════════
-- 3. A porta do aplicativo (schema public, security invoker)
-- ════════════════════════════════════════════════════════════
-- Busca + trilha. O texto da pergunta e cortado como na busca (1000);
-- a trilha guarda ids, nunca conteudo. Falha na trilha nao derruba a busca?
-- Derruba, de proposito: consulta sem registro nao e consulta.
create or replace function public.brain_search(
  p_query               text,
  p_filters             jsonb   default '{}'::jsonb,
  p_limit               integer default 10,
  p_include_superseded  boolean default false
)
returns setof brain.knowledge_hit language plpgsql security invoker set search_path = '' as $$
declare
  v_t0    timestamptz := clock_timestamp();
  v_hits  brain.knowledge_hit[];
  v_uid   uuid := (select auth.uid());
begin
  if v_uid is null or brain.caller_access_level() is null then
    return;   -- sem usuario ativo nao ha trilha (a policy recusaria) nem busca
  end if;
  select coalesce(array_agg(h order by h.score desc, h.chunk_id), '{}')
    into v_hits
    from brain.search_knowledge(p_query, p_filters, p_limit, p_include_superseded) h;

  insert into brain.knowledge_queries (user_id, caller_level, query_text, filters, hits, top_chunk_ids, duration_ms, origin)
  values (v_uid, brain.caller_access_level(), left(coalesce(p_query, ''), 1000), coalesce(p_filters, '{}'::jsonb),
          coalesce(cardinality(v_hits), 0), coalesce((select array_agg(x.chunk_id) from unnest(v_hits) x), '{}'),
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::integer, 'app');

  return query select * from unnest(v_hits);
end;
$$;

create or replace function public.brain_provenance(p_chunk_id bigint)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select brain.chunk_provenance(p_chunk_id);
$$;

revoke execute on function public.brain_search(text, jsonb, integer, boolean) from public, anon;
revoke execute on function public.brain_provenance(bigint)                     from public, anon;
grant  execute on function public.brain_search(text, jsonb, integer, boolean) to authenticated, service_role;
grant  execute on function public.brain_provenance(bigint)                     to authenticated, service_role;

comment on function public.brain_search(text, jsonb, integer, boolean) is
  'Porta do aplicativo para a memoria corporativa: repassa a brain.search_knowledge (RLS por baixo) e registra a consulta em brain.knowledge_queries.';

-- ════════════════════════════════════════════════════════════
-- 4. Storage: policies do bucket brain-documents (o bucket nao e criado aqui)
-- ════════════════════════════════════════════════════════════
-- O nome do objeto e o storage_path da versao: quem pode ler a versao pode
-- baixar o arquivo; so o administrador grava. O bucket e privado (sem URL
-- publica) e nasce pelo roteiro 07, quando autorizado.
do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'Schema storage ausente: policies do bucket brain-documents nao criadas (banco sem Supabase Storage).';
    return;
  end if;

  drop policy if exists brain_documents_read   on storage.objects;
  drop policy if exists brain_documents_write  on storage.objects;
  drop policy if exists brain_documents_update on storage.objects;
  drop policy if exists brain_documents_delete on storage.objects;

  execute $p$
    create policy brain_documents_read on storage.objects
      for select to authenticated
      using (bucket_id = 'brain-documents'
             and exists (select 1 from brain.document_versions v
                          where v.storage_bucket = 'brain-documents' and v.storage_path = storage.objects.name
                            and v.access_level <= (select brain.caller_access_level())))
  $p$;
  -- Sem objeto orfao: so entra (ou e renomeado para) um nome que JA e o
  -- storage_path de uma versao registrada. O bucket nunca acumula arquivo
  -- sem identidade documental no BRAIN — nem por administrador.
  execute $p$
    create policy brain_documents_write on storage.objects
      for insert to authenticated
      with check (bucket_id = 'brain-documents' and (select public.is_admin())
                  and exists (select 1 from brain.document_versions v
                               where v.storage_bucket = 'brain-documents' and v.storage_path = storage.objects.name))
  $p$;
  execute $p$
    create policy brain_documents_update on storage.objects
      for update to authenticated
      using (bucket_id = 'brain-documents' and (select public.is_admin()))
      with check (bucket_id = 'brain-documents' and (select public.is_admin())
                  and exists (select 1 from brain.document_versions v
                               where v.storage_bucket = 'brain-documents' and v.storage_path = storage.objects.name))
  $p$;
  execute $p$
    create policy brain_documents_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'brain-documents' and (select public.is_admin()))
  $p$;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Guardas do lote
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; r record;
begin
  if not (select relrowsecurity from pg_class where oid = 'brain.knowledge_queries'::regclass) then
    raise exception 'knowledge_queries sem RLS';
  end if;
  for r in
    select tablename, roles, cmd, count(*) as n from pg_policies
     where schemaname = 'brain' and permissive = 'PERMISSIVE'
     group by tablename, roles, cmd having count(*) > 1
  loop
    raise exception 'brain.% com % policies permissivas para % em %', r.tablename, r.n, r.roles, r.cmd;
  end loop;
  if exists (select 1 from pg_extension where extname = 'vector') then
    raise exception 'pgvector instalado — nao pertence ao Lote B';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'brain' and udt_name in ('vector', 'halfvec', 'sparsevec')) then
    raise exception 'Coluna vetorial no brain — nao pertence ao Lote B';
  end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  if v_n <> 0 then raise exception 'Funcao do brain declarada immutable indevidamente'; end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('brain', 'public') and p.prosecdef
     and p.proname in ('register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail','ingestion_record_failure','brain_search','brain_provenance');
  if v_n <> 0 then raise exception 'Funcao do Lote B declarada security definer'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'brain' and grantee = 'anon') then
    raise exception 'anon com grant em tabela do brain';
  end if;
  -- Nenhum gatilho do brain em tabela do ERP alem das 3 pontes da Fase 1 (desligadas).
  select count(*) into v_n from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
   where cn.nspname = 'public' and n.nspname = 'brain' and not t.tgisinternal and t.tgname not like 'trg_brain_%';
  if v_n <> 0 then raise exception 'Gatilho do brain em tabela do ERP'; end if;
end
$$;
