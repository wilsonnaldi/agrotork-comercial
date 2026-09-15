-- ============================================================
-- 10 · Rollback de 20260915120000_brain_busca_codigo_numerico_exato
-- ============================================================
-- Restaura brain.search_knowledge(text, jsonb, integer, boolean) na definicao
-- de 20260912040000_brain_busca_calibracao_piloto.sql — byte a byte, incluindo
-- comentarios e espacos: o corpo abaixo foi extraido daquele arquivo (linhas
-- 121–313, md5 da migration de origem 59533b03280c68d77aa5acba8086c2f6), sem
-- nenhuma edicao.
--
-- Efeito de rodar isto: o braco fuzzy de codigo volta a aceitar pares
-- puramente numericos (466113201 volta a devolver o chunk de 466113200).
-- Ou seja, isto reintroduz o defeito de propósito — so se usa se a correcao
-- quebrar algo pior em producao.
--
-- Guard: a funcao tem de existir com a assinatura esperada antes de trocar.
-- Transacional. Os grants sao reaplicados no fim e conferidos.
--
-- UMA DIFERENCA COSMETICA, MEDIDA E ESPERADA: a definicao que esta HOJE em
-- producao e a mesma desta, SEM os comentarios `--` (foram removidos quando a
-- 20260912040000 foi aplicada la). Conferido em 15/09/2026, so leitura:
--
--   md5 bruto        producao 9123a8d4ac389433a30f9775c4cc625a
--                    versionado 21b2f43731ab0d17f8f781845aa52830
--   md5 sem comentario e com espaco normalizado — OS DOIS LADOS:
--                    30986f47a02ec8f2c452e0474c8f9a43
--
-- Ou seja: mesmo codigo, comentario a mais. Rodar este rollback em producao
-- deixa a funcao funcionalmente identica a de antes e muda o md5 bruto de
-- 9123a8d4… para 21b2f437… — nao e divergencia, e o comentario voltando.
--
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/operacao/10-reverter-codigo-numerico-exato.sql
-- ============================================================
begin;

do $guard$
begin
  if to_regprocedure('brain.search_knowledge(text, jsonb, integer, boolean)') is null then
    raise exception 'ROLLBACK ABORTADO: brain.search_knowledge(text, jsonb, integer, boolean) nao existe neste banco';
  end if;
  if (select prosecdef from pg_proc where oid = to_regprocedure('brain.search_knowledge(text, jsonb, integer, boolean)')) then
    raise exception 'ROLLBACK ABORTADO: a funcao esta security definer — nao e a definicao que este script conhece';
  end if;
end $guard$;

-- ── definicao anterior, byte a byte ──────────────────────────
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
  v_code_intent boolean;
  v_terms record;
  v_words text;
  v_lex text[];
  v_nlex integer;
  v_tsq tsquery;
  v_tsq_or tsquery;
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

  -- codigos por padrao (pontuacao nao destroi o codigo); intencao de codigo
  v_codes := brain.query_codes(v_q);
  v_code_intent := cardinality(v_codes) > 0;

  -- palavras de conteudo e lexemas (sem stopwords, sem numeros curtos)
  v_terms := brain.query_terms(v_q);
  v_words := coalesce(v_terms.content_words, v_q);
  v_lex := v_terms.lexemes;
  v_nlex := cardinality(v_lex);
  v_tsq := websearch_to_tsquery('portuguese'::regconfig, v_q);
  -- OR das palavras de conteudo (websearch ignora pontuacao); a cobertura e
  -- conferida lexema a lexema, sem reanalisar o texto
  v_tsq_or := case when v_terms.content_words is not null
                   then websearch_to_tsquery('portuguese'::regconfig, replace(v_terms.content_words, ' ', ' OR '))
                   else null end;

  return query
  with visiveis as not materialized (
    -- tudo que o chamador pode ver, vigente e dentro dos filtros — INCLUINDO
    -- tabelas degradadas (so para saber que um codigo existe)
    select c.id, c.kind, c.content, c.content_norm, c.table_data, c.page_from, c.page_to,
           c.heading_path, c.codes, c.fts, c.access_level,
           v.id as version_id, v.version_label, v.status as version_status,
           v.storage_path, v.file_sha256,
           d.id as document_id, d.title, d.document_type, d.source_key,
           to_tsvector('portuguese'::regconfig, brain.normalize_text(d.title || ' ' || s.name)) as doc_fts,
           (c.kind in ('table', 'price_table')
            and (coalesce(c.table_data -> 'audit' ->> 'quality', 'trusted') = 'degraded'
                 or coalesce((c.table_data -> 'audit' ->> 'fatal')::boolean, false))) as degradada
      from brain.document_chunks c
      join brain.document_versions v on v.id = c.version_id
      join brain.documents d on d.id = v.document_id
      join brain.knowledge_sources s on s.key = d.source_key
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
  -- tabela que o worker marcou como degradada nunca e evidencia (fail-closed,
  -- antes do ranking; nenhum filtro reabre)
  candidatos as not materialized (
    select * from visiveis where not degradada
  ),
  -- codigos da pergunta que existem EXATOS em algo visivel (mesmo degradado):
  -- para esses nao ha fuzzy — se a unica evidencia e degradada, a resposta e zero,
  -- nao o dado de um codigo parecido
  exatos_presentes as (
    select qc from unnest(v_codes) qc where exists (select 1 from visiveis a where qc = any(a.codes))
  ),
  -- braco de codigo: exato primeiro, depois fuzzy CODIGO x CODIGO (>= 0,6) so para
  -- codigo da pergunta que nao existe exato em lugar nenhum
  codigo as (
    select id, row_number() over (order by exatos desc, sim desc, id) as rk
      from (select c.id,
                   cardinality(array(select unnest(c.codes) intersect select unnest(v_codes))) as exatos,
                   coalesce((select max(extensions.similarity(cc, qc)) from unnest(c.codes) cc, unnest(v_codes) qc
                              where qc not in (select qc from exatos_presentes)), 0) as sim
              from candidatos c
             where v_code_intent
               and (c.codes && v_codes
                    or exists (select 1 from unnest(c.codes) cc, unnest(v_codes) qc
                                where qc not in (select qc from exatos_presentes)
                                  and extensions.similarity(cc, qc) >= 0.6))) s
  ),
  -- com intencao de codigo, so os chunks do braco de codigo seguem; sem codigo compativel, nada segue
  base as not materialized (
    select c.* from candidatos c
     where (not v_code_intent) or c.id in (select id from codigo)
  ),
  trgm as (
    select id, row_number() over (order by sim desc, id) as rk
      from (select c.id, extensions.word_similarity(v_words, c.content_norm) as sim
              from base c
             where v_words operator(extensions.<%) c.content_norm) s
     limit 50
  ),
  fts as (
    -- um braco, dois niveis: estrito (todos os termos) acima; cobertura de lexemas abaixo
    select id, row_number() over (order by estrito desc, cobertura desc, rk_score desc, id) as rk, estrito, cobertura, batidos
      from (select c.id,
                   (c.fts @@ v_tsq) as estrito,
                   ts_rank_cd(c.fts, v_tsq) as rk_score,
                   (select count(*) from unnest(v_lex) l
                     where l = any(tsvector_to_array(c.fts || c.doc_fts))) as batidos,
                   case when v_nlex > 0
                        then (select count(*) from unnest(v_lex) l
                               where l = any(tsvector_to_array(c.fts || c.doc_fts)))::numeric / v_nlex
                        else 0 end as cobertura
              from base c
             where c.fts @@ v_tsq or (v_tsq_or is not null and (c.fts || c.doc_fts) @@ v_tsq_or)) s
     where estrito or (cobertura >= 0.5 and batidos >= 2)
     limit 50
  ),
  fundido as (
    select coalesce(e.id, t.id, f.id) as id,
           e.rk as rank_exact, t.rk as rank_trgm, f.rk as rank_fts,
           (coalesce(1.0 / (60 + e.rk), 0)
          + coalesce(1.0 / (60 + t.rk), 0)
          + coalesce(1.0 / (60 + f.rk), 0)
          + case when e.rk is not null then 1.0 / 60 else 0 end)::numeric(12,8) as score
      from codigo e
      full join trgm t on t.id = e.id
      full join fts f on f.id = coalesce(e.id, t.id)
  )
  select c.id, fu.score, fu.rank_exact::integer, fu.rank_trgm::integer, fu.rank_fts::integer,
         c.kind, c.content, c.table_data, c.page_from, c.page_to, c.heading_path, c.codes,
         c.version_id, c.version_label, c.version_status,
         c.document_id, c.title, c.document_type, c.source_key, c.access_level,
         c.storage_path, c.file_sha256
    from fundido fu
    join base c on c.id = fu.id
   order by fu.score desc, c.id
   limit v_limit;
end;
$$;

revoke execute on function brain.search_knowledge(text, jsonb, integer, boolean) from public, anon;
grant  execute on function brain.search_knowledge(text, jsonb, integer, boolean) to authenticated, service_role;

comment on function brain.search_knowledge(text, jsonb, integer, boolean) is
  'Busca hibrida sem vetor, calibrada no piloto Magnojet: codigo por padrao (exato ou fuzzy codigo x codigo; com codigo na pergunta, so codigo compativel responde), trigram sobre palavras de conteudo, FTS estrito + cobertura de lexemas; fundidos por RRF (k=60). Acesso, vigencia e tabela degradada (table_data.audit) sao filtrados ANTES do ranking.';

-- ── conferencia dos grants depois do rollback ────────────────
do $conf$
declare atual text[];
begin
  select coalesce(array_agg(a order by a), '{}')
    into atual
    from (select unnest(proacl)::text as a
            from pg_proc where oid = to_regprocedure('brain.search_knowledge(text, jsonb, integer, boolean)')) t
   where a like 'authenticated=%' or a like 'service_role=%' or a like '=%' or a like 'anon=%';
  if exists (select 1 from unnest(atual) a where a like 'anon=%' or a like '=%') then
    raise exception 'ROLLBACK ABORTADO: anon ou public ficou com EXECUTE: %', atual;
  end if;
  if not exists (select 1 from unnest(atual) a where a like 'authenticated=X%')
     or not exists (select 1 from unnest(atual) a where a like 'service_role=X%') then
    raise exception 'ROLLBACK ABORTADO: grants de EXECUTE nao foram restaurados: %', atual;
  end if;
  raise notice 'Rollback aplicado. Grants conferidos: %', atual;
end $conf$;

commit;
-- rollback;   -- (use no lugar do commit para so conferir o que aconteceria)
