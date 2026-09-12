-- ============================================================
-- AGROTORK BRAIN — Fase 2, Lote A: busca textual e proveniência
-- ============================================================
-- Dois braços, sem vetor:
--
--   A. exato / trigram  — código de peça, modelo, referência (MJ981CAP,
--      T70P, DB1580), inclusive digitados com espaço ou faltando letra;
--   B. FTS              — texto em português, sem acento, com stemming.
--
-- Os dois já são combinados por Reciprocal Rank Fusion (k = 60). Quando o
-- braço vetorial chegar (Lote C), ele entra como um terceiro `rank` na
-- mesma soma — a função cresce, não se refaz.
--
-- A regra que importa: o filtro de acesso e de vigência é uma CTE que roda
-- ANTES dos rankings. Quem não pode ler um documento não o vê em resultado,
-- em contagem nem em desempate. E como a função é `security invoker`, o
-- RLS das tabelas vale por baixo dela de qualquer jeito — o predicado
-- explícito é a segunda cerca, não a única.
-- ============================================================

-- Resultado da busca: tudo que a resposta futura precisa para citar.
create type brain.knowledge_hit as (
  chunk_id        bigint,
  score           numeric,
  rank_exact      integer,
  rank_trgm       integer,
  rank_fts        integer,
  kind            brain.chunk_kind,
  content         text,
  table_data      jsonb,
  page_from       integer,
  page_to         integer,
  heading_path    text[],
  codes           text[],
  version_id      uuid,
  version_label   text,
  version_status  brain.version_status,
  document_id     uuid,
  title           text,
  document_type   brain.document_type,
  source_key      text,
  access_level    brain.access_level,
  storage_path    text,
  file_sha256     text
);

-- ── Sincronizado com a produção (12/09/2026) ─────────────────
-- O deploy real do Lote A recusou `create function ... set
-- pg_trgm.word_similarity_threshold = 0.35` no Supabase gerenciado (o GUC
-- da extensão não é aceito como configuração de função ali, embora o
-- PostgreSQL local aceite). A correção aplicada em produção — e que este
-- arquivo passa a representar — fixa o limiar DENTRO da execução, com
-- `set_config(..., true)` (local à transação), logo depois de normalizar a
-- pergunta. Consequências:
--   · a função é VOLATILE (altera configuração de sessão), não mais stable;
--   · o limiar efetivo continua 0,35 e vale só até o fim da transação;
--   · nenhum privilégio a mais: `set_config` de um GUC de extensão é
--     permitido a qualquer papel;
--   · o corpo abaixo é BYTE A BYTE o que `pg_get_functiondef` devolve em
--     produção (md5 3b54175bfd5a335ff737b799ca3eb3b6), conferido pela
--     suíte 34 (RAG-H11). A explicação de cada bloco está na versão
--     comentada do Lote A em docs/brain/fase-2-lote-a.md §6.
--
-- Regras de entrada: nível NULL → vazio; p_limit NULL → 10, ≤ 0 → vazio,
-- teto 100; pergunta normalizada e cortada em 1000 caracteres; p_filters
-- NULL → {}; chave desconhecida, valor nulo ou mal formado →
-- invalid_parameter_value com mensagem curta.
create or replace function brain.search_knowledge(
  p_query               text,
  p_filters             jsonb   default '{}'::jsonb,
  p_limit               integer default 10,
  p_include_superseded  boolean default false
)
returns setof brain.knowledge_hit
language plpgsql security invoker
set search_path = ''
as $$
declare
  v_level brain.access_level := brain.caller_access_level();
  v_q text;
  v_codes text[];
  v_tsq tsquery;
  v_limit integer;
  v_today date := current_date;
  v_f jsonb := coalesce(p_filters, '{}'::jsonb);
  v_key text;
  v_version_id uuid; v_document_id uuid; v_brand_id uuid; v_category_id uuid; v_product_id uuid;
  v_doc_type brain.document_type; v_kind brain.chunk_kind;
  v_source_key text; v_version_label text;
begin
  if v_level is null then return; end if;
  v_limit := coalesce(p_limit, 10);
  if v_limit <= 0 then return; end if;
  v_limit := least(v_limit, 100);
  v_q := left(brain.normalize_text(p_query), 1000);
  if v_q is null then return; end if;

  perform set_config('pg_trgm.word_similarity_threshold', '0.35', true);

  if jsonb_typeof(v_f) <> 'object' then
    raise exception 'p_filters deve ser um objeto JSON' using errcode = 'invalid_parameter_value';
  end if;
  for v_key in select jsonb_object_keys(v_f) loop
    if v_key not in ('source_key','document_id','document_type','brand_id','category_id','version_label','version_id','kind','product_id') then
      raise exception 'Filtro desconhecido: %', v_key using errcode = 'invalid_parameter_value';
    end if;
  end loop;
  begin
    v_version_id := (v_f ->> 'version_id')::uuid;
    v_document_id := (v_f ->> 'document_id')::uuid;
    v_brand_id := (v_f ->> 'brand_id')::uuid;
    v_category_id := (v_f ->> 'category_id')::uuid;
    v_product_id := (v_f ->> 'product_id')::uuid;
    v_doc_type := (v_f ->> 'document_type')::brain.document_type;
    v_kind := (v_f ->> 'kind')::brain.chunk_kind;
  exception when invalid_text_representation or invalid_parameter_value then
    raise exception 'Filtro com valor invalido' using errcode = 'invalid_parameter_value';
  end;
  v_source_key := v_f ->> 'source_key';
  v_version_label := v_f ->> 'version_label';
  if (v_f ? 'version_id' and v_version_id is null) or (v_f ? 'document_id' and v_document_id is null)
  or (v_f ? 'brand_id' and v_brand_id is null) or (v_f ? 'category_id' and v_category_id is null)
  or (v_f ? 'product_id' and v_product_id is null) or (v_f ? 'document_type' and v_doc_type is null)
  or (v_f ? 'kind' and v_kind is null) or (v_f ? 'source_key' and v_source_key is null)
  or (v_f ? 'version_label' and v_version_label is null) then
    raise exception 'Filtro com valor nulo' using errcode = 'invalid_parameter_value';
  end if;

  select array_agg(distinct c) into v_codes
    from (select brain.normalize_code(t) as c from unnest(regexp_split_to_array(v_q, '\s+')) t
          union all select brain.normalize_code(v_q)) s
   where c is not null and length(c) >= 2;

  v_tsq := websearch_to_tsquery('portuguese'::regconfig, v_q);

  return query
  with candidatos as not materialized (
    select c.id, c.kind, c.content, c.content_norm, c.table_data, c.page_from, c.page_to,
           c.heading_path, c.codes, c.fts, c.access_level,
           v.id as version_id, v.version_label, v.status as version_status,
           v.storage_path, v.file_sha256,
           d.id as document_id, d.title, d.document_type, d.source_key
      from brain.document_chunks c
      join brain.document_versions v on v.id = c.version_id
      join brain.documents d on d.id = v.document_id
     where c.access_level <= v_level
       and ((v.status = 'active'
              and (v.valid_from is null or v.valid_from <= v_today)
              and (v.valid_to is null or v.valid_to >= v_today))
          or (p_include_superseded and v.status = 'superseded')
          or (v_version_id is not null and v.id = v_version_id and v.status <> 'withdrawn'))
       and (v_version_id is null or v.id = v_version_id)
       and (v_source_key is null or d.source_key = v_source_key)
       and (v_document_id is null or d.id = v_document_id)
       and (v_doc_type is null or d.document_type = v_doc_type)
       and (v_brand_id is null or d.brand_id = v_brand_id)
       and (v_category_id is null or d.category_id = v_category_id)
       and (v_version_label is null or v.version_label = v_version_label)
       and (v_kind is null or c.kind = v_kind)
       and (v_product_id is null or exists (select 1 from brain.chunk_products cp where cp.chunk_id = c.id and cp.product_id = v_product_id))
  ),
  exato as (
    select id, row_number() over (order by cardinality(codes_batidos) desc, id) as rk
      from (select c.id, array(select unnest(c.codes) intersect select unnest(v_codes)) as codes_batidos
              from candidatos c
             where v_codes is not null and c.codes && v_codes) s
  ),
  trgm as (
    select id, row_number() over (order by sim desc, id) as rk
      from (select c.id, extensions.word_similarity(v_q, c.content_norm) as sim
              from candidatos c
             where v_q operator(extensions.<%) c.content_norm) s
     limit 50
  ),
  fts as (
    select id, row_number() over (order by rk_score desc, id) as rk
      from (select c.id, ts_rank_cd(c.fts, v_tsq) as rk_score
              from candidatos c
             where c.fts @@ v_tsq) s
     limit 50
  ),
  fundido as (
    select coalesce(e.id, t.id, f.id) as id,
           e.rk as rank_exact, t.rk as rank_trgm, f.rk as rank_fts,
           (coalesce(1.0 / (60 + e.rk), 0)
          + coalesce(1.0 / (60 + t.rk), 0)
          + coalesce(1.0 / (60 + f.rk), 0)
          + case when e.rk is not null then 1.0 / 60 else 0 end)::numeric(12,8) as score
      from exato e
      full join trgm t on t.id = e.id
      full join fts f on f.id = coalesce(e.id, t.id)
  )
  select c.id, fu.score, fu.rank_exact::integer, fu.rank_trgm::integer, fu.rank_fts::integer,
         c.kind, c.content, c.table_data, c.page_from, c.page_to, c.heading_path, c.codes,
         c.version_id, c.version_label, c.version_status,
         c.document_id, c.title, c.document_type, c.source_key, c.access_level,
         c.storage_path, c.file_sha256
    from fundido fu
    join candidatos c on c.id = fu.id
   order by fu.score desc, c.id
   limit v_limit;
end;
$$;

revoke execute on function brain.search_knowledge(text, jsonb, integer, boolean) from public, anon;
grant  execute on function brain.search_knowledge(text, jsonb, integer, boolean) to authenticated, service_role;

comment on function brain.search_knowledge(text, jsonb, integer, boolean) is
  'Busca hibrida sem vetor: codigo exato + trigram + FTS, fundidos por RRF (k=60). O filtro de acesso e vigencia roda ANTES do ranking. Filtros: source_key, document_id, document_type, brand_id, category_id, version_label, version_id, kind, product_id.';

-- ════════════════════════════════════════════════════════════
-- Proveniencia — a cadeia inteira de um chunk
-- ════════════════════════════════════════════════════════════
-- chunk → pagina → ingestao → versao → documento → fonte → arquivo/sha256.
-- `security invoker`: se o chamador nao pode ler o chunk, devolve NULL —
-- nem "existe mas nao posso mostrar".
create or replace function brain.chunk_provenance(p_chunk_id bigint)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'chunk',     jsonb_build_object('id', c.id, 'kind', c.kind, 'ordinal', c.ordinal,
                                    'page_from', c.page_from, 'page_to', c.page_to,
                                    'heading_path', c.heading_path, 'codes', c.codes,
                                    'content_sha256', c.content_sha256),
    'page',      jsonb_build_object('page_no', pg.page_no, 'extraction', pg.extraction, 'ocr', pg.ocr,
                                    'text_sha256', pg.text_sha256),
    'ingestion', jsonb_build_object('id', i.id, 'status', i.status, 'method', i.method,
                                    'parser', i.parser, 'pipeline_version', i.pipeline_version,
                                    'needs_ocr', i.needs_ocr, 'finished_at', i.finished_at),
    'version',   jsonb_build_object('id', v.id, 'label', v.version_label, 'status', v.status,
                                    'valid_from', v.valid_from, 'valid_to', v.valid_to,
                                    'supersedes_id', v.supersedes_id, 'superseded_by_id', v.superseded_by_id,
                                    'page_count', v.page_count),
    'document',  jsonb_build_object('id', d.id, 'slug', d.slug, 'title', d.title,
                                    'type', d.document_type, 'access_level', d.access_level,
                                    'brand_id', d.brand_id),
    'source',    jsonb_build_object('key', s.key, 'name', s.name, 'kind', s.kind, 'brand_id', s.brand_id),
    'file',      jsonb_build_object('bucket', v.storage_bucket, 'path', v.storage_path,
                                    'original_filename', v.original_filename, 'mime_type', v.mime_type,
                                    'size', v.file_size, 'sha256', v.file_sha256),
    'citation',  s.name || ' — ' || d.title || ' ' || v.version_label || ', p. ' || c.page_from
                 || case when c.page_to <> c.page_from then '–' || c.page_to else '' end
  )
  from brain.document_chunks c
  join brain.document_pages pg on pg.version_id = c.version_id and pg.page_no = c.page_from
  join brain.knowledge_ingestions i on i.id = c.ingestion_id
  join brain.document_versions v on v.id = c.version_id
  join brain.documents d on d.id = v.document_id
  join brain.knowledge_sources s on s.key = d.source_key
  where c.id = p_chunk_id;
$$;

revoke execute on function brain.chunk_provenance(bigint) from public, anon;
grant  execute on function brain.chunk_provenance(bigint) to authenticated, service_role;

comment on function brain.chunk_provenance(bigint) is
  'Cadeia completa de proveniencia de um chunk, pronta para citar: fonte, documento, versao, pagina, arquivo e sha256. NULL se o chamador nao pode ler.';

-- ════════════════════════════════════════════════════════════
-- Versao vigente de um documento, e historico
-- ════════════════════════════════════════════════════════════
create or replace function brain.current_version(p_document_id uuid)
returns uuid language sql stable security invoker set search_path = '' as $$
  select v.id from brain.document_versions v
   where v.document_id = p_document_id and v.status = 'active'
     and (v.valid_from is null or v.valid_from <= current_date)
     and (v.valid_to   is null or v.valid_to   >= current_date)
   limit 1;
$$;

revoke execute on function brain.current_version(uuid) from public, anon;
grant  execute on function brain.current_version(uuid) to authenticated, service_role;

-- Guardas
do $$
begin
  if exists (select 1 from pg_extension where extname = 'vector') then
    raise exception 'pgvector instalado — nao pertence ao Lote A';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'brain' and p.provolatile = 'i'
                and p.proname not in ('normalize_phone', 'normalize_identity')) then
    raise exception 'Funcao do brain declarada immutable indevidamente';
  end if;
end
$$;
