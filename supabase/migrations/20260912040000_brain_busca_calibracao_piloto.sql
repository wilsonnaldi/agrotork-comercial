-- ============================================================
-- AGROTORK BRAIN — Fase 2, Lote B: calibração da busca (piloto Magnojet V41)
-- ============================================================
-- O piloto com o catálogo real mostrou três defeitos na busca do Lote A
-- (docs/brain/fase-2-piloto-magnojet.md):
--
--   1. código dentro de frase: "qual catálogo sustenta a MJ983CAP?" zerava
--      porque o token vinha com a pontuação ("mj983cap?") e o braço exato
--      comparava token inteiro com código;
--   2. código inexistente caía no trigram de prosa e devolvia um trecho
--      "parecido" (MJ999CAP → tabela de fatores; Arag 466113200 → conselho
--      sobre manômetro). Um código que não existe tem que dar ZERO;
--   3. pergunta natural longa zerava (FTS exige todos os termos) ou, no
--      trigram, casava por trigramas de palavras vazias ("qual a", " de ").
--
-- O que muda (mesma assinatura, mesmo tipo de retorno, mesmo RRF, sem vetor):
--
--   · `brain.query_codes(texto)` reconhece códigos por PADRÃO (os mesmos de
--     brain/worker/brain_worker/codes.py), não por split de espaço — a
--     pontuação ao redor não destrói o código; rótulos de versão ("V41")
--     não contam como código;
--   · CODE INTENT GUARD: se a pergunta tem código, a busca é código contra
--     código — exato (`codes && ...`) ou fuzzy de código (similaridade de
--     trigramas entre CÓDIGOS ≥ 0,6: "MJ981CA" acha MJ981CAP; "MJ999CAP"
--     não acha MJ981CAP). Sem código compatível → zero. Nunca cai para
--     trigram de prosa;
--   · pergunta sem código: trigram só sobre as PALAVRAS DE CONTEÚDO da
--     pergunta (sem stopwords: "faixa operacao sensor pressao"), FTS estrito
--     (todos os termos) e um segundo nível do mesmo braço FTS por COBERTURA
--     de lexemas (fração dos termos de conteúdo presentes no chunk, no
--     título do documento ou no nome da fonte). Evidência mínima para um
--     hit existir: código batido, OU FTS estrito, OU cobertura ≥ 1/2 com
--     pelo menos 2 termos, OU trigram ≥ 0,35 sobre as palavras de conteúdo.
--     Um rank isolado num braço fraco deixa de ser "evidência".
--
--   · FAIL-CLOSED PARA TABELA DEGRADADA (hardening final do piloto): chunk
--     `table`/`price_table` cujo `table_data.audit.quality = 'degraded'` ou
--     `audit.fatal = true` — o próprio worker sabe que a estrutura está errada
--     (número fundido, cabeçalho caído, linha engolida) e a geometria não
--     resolveu — sai dos candidatos ANTES do ranking, junto com o filtro de
--     acesso e de vigência. Nenhum filtro (version_id, source_key, kind…)
--     reabre a porta. O chunk continua gravado e rastreável
--     (`brain.chunk_provenance` por id, para diagnóstico); só não vira
--     evidência. Tabela sem `audit` (conteúdo anterior ao lote-b.2) conta
--     como trusted: o estado é declarado pelo worker, não adivinhado aqui.
--     E se o código da pergunta existe EXATO só numa tabela degradada, o
--     fuzzy não entra em ação: zero, e não o dado de um código parecido.
--
-- A migration 20260912020000 (já aplicada) não é editada: esta redefine a
-- função por cima. `supabase/operacao/08-remover-lote-b-sem-dados.sql`
-- devolve a versão do Lote A byte a byte.
--
-- Histórico do arquivo: o hardening de tabela degradada entrou por commit
-- normal enquanto esta migration AINDA NÃO tinha sido aplicada em produção
-- (ledger de produção em 20260912030000 na data), por isso não há 050000.
-- ============================================================

-- ── Códigos reconhecidos numa pergunta ───────────────────────
-- Espelha codes.py: letras+dígitos (+ sufixo, + /n[letra]); série com espaço
-- ("MUG-CV 02", "MAG CH 0.5"); número puro de 7–9 dígitos; "M 714"/"M 691/1A".
create or replace function brain.query_codes(p_query text)
returns text[] language sql stable security invoker set search_path = '' as $$
  with up as (select upper(extensions.unaccent(coalesce(p_query, ''))) as q),
  hits as (
    select brain.normalize_code(m[1]) as c
      from up, regexp_matches(up.q, '(?<![A-Z0-9/-])([A-Z]{1,5}-?\d{2,7}[A-Z0-9-]*(?:/\d{1,3}[A-Z]?)?)(?![A-Z0-9/-])', 'g') m
    union all
    select brain.normalize_code(m[1])
      from up, regexp_matches(up.q, '(?<![A-Z0-9/-])([A-Z]{2,4}-[A-Z]{2,3}\s?\d{1,3}(?:[.,]\d)?)(?![A-Z0-9/-])', 'g') m
    union all
    select brain.normalize_code(m[1])
      from up, regexp_matches(up.q, '(?<![A-Z0-9/-])([A-Z]{3,4}\s[A-Z]{2,3}\s\d{1,2}(?:[.,]\d)?)(?![A-Z0-9/-])', 'g') m
    union all
    select brain.normalize_code(m[1])
      from up, regexp_matches(up.q, '(?<![\w-])(\d{7,9})(?![\w-])', 'g') m
    union all
    select brain.normalize_code(m[1])
      from up, regexp_matches(up.q, '(?<![A-Z0-9/-])(M\s\d{3,4}(?:/\d{1,2}[A-Z]?)?)(?![A-Z0-9/-])', 'g') m
  )
  select coalesce(array_agg(distinct c order by c), '{}'::text[])
    from hits
   where c is not null and c <> 'COVID19'
     -- unidade seguida de série ("PSI DDC 01") não é código (espelha codes.py)
     and c !~ '^(BAR|PSI|KPA|MPA)[A-Z]'
     -- rótulo de versão não é código de peça (V41, V16.2)
     and c not in (select upper(brain.normalize_code(v.version_label)) from brain.document_versions v);
$$;

-- ── Palavras de conteúdo da pergunta (sem stopwords) ─────────
-- Devolve as palavras originais (normalizadas) que geram lexema, na ordem,
-- para o trigram; e os lexemas distintos, para a cobertura.
create or replace function brain.query_terms(p_query text, out content_words text, out lexemes text[])
returns record language sql stable security invoker set search_path = '' as $$
  with w as (
    select t.w, t.ord
      from unnest(regexp_split_to_array(coalesce(brain.normalize_text(p_query), ''), '\s+')) with ordinality t(w, ord)
     where t.w <> '' and to_tsvector('portuguese'::regconfig, t.w) <> ''::tsvector
  )
  , lex as (
    -- uma palavra com hifen ("ad-ia") gera o composto e as partes ("ad", "ia"):
    -- so o composto conta, senao a cobertura infla com um unico termo
    select distinct l
      from w, unnest(tsvector_to_array(to_tsvector('portuguese'::regconfig, w.w))) l
     where l !~ '^\d{1,2}$' and (w.w not like '%-%' or l like '%-%')
  )
  select nullif((select string_agg(w, ' ' order by ord) from w), ''),
         coalesce((select array_agg(l order by l) from lex), '{}'::text[]);
$$;

revoke execute on function brain.query_codes(text) from public, anon;
revoke execute on function brain.query_terms(text) from public, anon;
grant  execute on function brain.query_codes(text) to authenticated, service_role;
grant  execute on function brain.query_terms(text) to authenticated, service_role;

comment on function brain.query_codes(text) is
  'Codigos de peca/modelo reconhecidos numa pergunta, por padrao (nao por espaco): a pontuacao ao redor nao destroi o codigo; rotulos de versao ficam de fora.';
comment on function brain.query_terms(text) is
  'Palavras de conteudo (sem stopwords) e lexemas distintos de uma pergunta, para trigram e cobertura.';

-- ── Busca ────────────────────────────────────────────────────
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
