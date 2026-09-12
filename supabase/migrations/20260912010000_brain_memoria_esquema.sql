-- ============================================================
-- AGROTORK BRAIN — Fase 2, Lote A: fundação da memória corporativa
-- ============================================================
-- Projeto em docs/brain/fase-2-etapa-0.md. Este arquivo cria SÓ a camada
-- relacional: fontes, documentos, versões, ingestões, páginas, chunks e o
-- vínculo com o catálogo do ERP. Sem pgvector, sem embedding, sem worker.
--
-- O que este lote NÃO faz, de propósito:
--   · não toca em `public`: nenhuma coluna, gatilho ou função nova no ERP;
--   · não participa de nenhuma transação comercial — a memória é uma camada
--     nova, lida por consulta;
--   · não cria bucket: o Storage `brain-documents` (privado, ~250 MB por
--     arquivo) é projetado aqui e criado no Lote B, quando o plano estiver
--     confirmado;
--   · não instala `vector`.
--
-- Decisões que saem da Etapa 0 e do inventário:
--
--   Documento é a OBRA; versão é a EDIÇÃO. "Catálogo Magnojet" é um
--   documento; V40 e V41 são versões. A nova não apaga a antiga: ela a
--   marca `superseded` e aponta para ela.
--
--   O arquivo é imutável por checksum. `file_sha256` não muda depois de
--   gravado, o caminho no Storage termina no próprio sha256, e o mesmo
--   sha256 nunca vira uma segunda versão do mesmo documento.
--
--   Nível de acesso é COLUNA em toda tabela da cadeia (documento → versão →
--   ingestão → página → chunk → vínculo com produto), copiado por gatilho a
--   partir do documento. Assim cada policy é uma comparação de coluna, sem
--   junção, e o filtro de acesso é aplicado ANTES de qualquer ranking — o
--   conjunto candidato da busca já nasce filtrado.
--
--   Tabela técnica é chunk próprio: `table_data` guarda cabeçalho, unidades
--   e linhas com números numéricos; `content` guarda a mesma tabela
--   renderizada em texto para FTS e trigram. A p. 20 do Magnojet V41 é o
--   exemplo de referência (docs/brain/fase-2-etapa-0.md, §9).
--
--   Nenhum preço de documento escreve em `public.products` ou em
--   `public.product_costs`. `chunk_products` só APONTA para o produto.
--
--   Processamento externo (mandar texto para um provedor de embedding ou
--   OCR fora do Supabase) é decisão explícita e auditável, não default:
--   `public` pode; `internal` só em provedor aprovado; `commercial` é
--   proibido salvo opt-in por documento com aprovador registrado; `admin`
--   nunca. A função `brain.external_processing_for()` é a única fonte
--   dessa resposta.
--
-- Compatibilidade: SQL testado em PostgreSQL 16, 17.6 e 18.6. Nada aqui
-- depende de recurso posterior ao 16. `unaccent` e `pg_trgm` já estão
-- instalados no schema `extensions` (migration 20260901194546), e são
-- chamados sempre qualificados.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- Tipos
-- ════════════════════════════════════════════════════════════
-- A ordem de declaração É a ordem de sensibilidade: enums comparam pela
-- posição, então `'commercial' > 'internal'` funciona sem função nenhuma.
create type brain.access_level as enum ('public', 'internal', 'commercial', 'admin');

create type brain.document_type as enum
  ('catalog', 'manual', 'price_list', 'datasheet', 'procedure', 'technical_bulletin',
   'internal_note', 'training', 'regulatory', 'other');

create type brain.version_status as enum ('draft', 'active', 'superseded', 'withdrawn');

-- Sem etapa de embedding: quando o Lote C existir, ele acrescenta o rótulo
-- (`alter type ... add value`). Este lote não reserva nem nome para vetor.
create type brain.ingestion_status as enum
  ('pending', 'extracting', 'chunking', 'completed', 'failed', 'partial');

create type brain.chunk_kind as enum
  ('text', 'table', 'price_table', 'spec', 'heading', 'list', 'caption');

create type brain.link_origin as enum ('manual', 'rule', 'ai', 'import');

create type brain.external_processing as enum ('allowed', 'approved_provider_only', 'forbidden');

-- Papéis funcionais, não pessoas: quem responde por uma fonte é um setor.
create type brain.knowledge_role as enum ('admin', 'commercial', 'technical', 'marketing');

-- ════════════════════════════════════════════════════════════
-- Quem está perguntando, e até onde enxerga
-- ════════════════════════════════════════════════════════════
-- Mapeamento em UM lugar, por PAPEL explícito — nunca por "qualquer
-- usuário ativo". Hoje:
--   sessão do próprio banco (postgres, service_role, cron, migration:
--     sem JWT e fora dos papéis de API)                        → admin
--   perfil ATIVO com papel `admin`                             → admin
--   perfil ATIVO com papel `salesperson`                       → internal
--   anon, sem JWT em papel de API, inativo, sem perfil, papel
--     desconhecido                                             → NULL (nada)
-- `commercial` não é concedido a ninguém hoje: a tabela subdealer é custo,
-- e só o administrador a enxerga. Se um dia um papel novo puder ver preço
-- de revenda, muda-se AQUI e em mais lugar nenhum; até lá, um valor novo em
-- `public.user_role` cai no `else` e não enxerga nada — na dúvida, nega.
--
-- De propósito NÃO usa `brain.is_privileged()`: aquela função aceita a
-- marca de sessão `brain.internal` (aberta pelas pontes do ERP), e uma marca
-- de sessão pode ser ligada por qualquer conexão que execute SQL. A memória
-- corporativa não tem ponte nenhuma, então não precisa dessa porta.
-- `security invoker`: não abre nada; só lê o que `public.auth_role()`
-- (definer, filtra `is_active`) já responde.
create or replace function brain.caller_access_level()
returns brain.access_level language sql stable security invoker set search_path = '' as $$
  select case
    when (select auth.uid()) is null then
      case when coalesce(nullif(pg_catalog.current_setting('role', true), 'none'), session_user::text)
                not in ('anon', 'authenticated')
           then 'admin'::brain.access_level
      end
    when (select public.auth_role()) = 'admin'       then 'admin'::brain.access_level
    when (select public.auth_role()) = 'salesperson' then 'internal'::brain.access_level
    else null
  end;
$$;

-- NULL de nível nunca vira true: `null >= x` é null, e coalesce fecha.
create or replace function brain.can_read_level(p_level brain.access_level)
returns boolean language sql stable security invoker set search_path = '' as $$
  select coalesce((select brain.caller_access_level()) >= p_level, false);
$$;

revoke execute on function brain.caller_access_level()                from public, anon;
revoke execute on function brain.can_read_level(brain.access_level)   from public, anon;
grant  execute on function brain.caller_access_level()                to authenticated, service_role;
grant  execute on function brain.can_read_level(brain.access_level)   to authenticated, service_role;

-- Texto normalizado para busca: minúsculas, sem acento, espaço simples.
-- `stable` porque `unaccent` é stable (depende do dicionário).
create or replace function brain.normalize_text(p_text text)
returns text language sql stable security invoker set search_path = '' as $$
  select nullif(btrim(regexp_replace(lower(extensions.unaccent(coalesce(p_text, ''))), '\s+', ' ', 'g')), '');
$$;

-- Código de peça/modelo normalizado: maiúsculas, sem espaço, sem acento.
-- 'mj 981 cap' → 'MJ981CAP'; 't70p' → 'T70P'.
create or replace function brain.normalize_code(p_code text)
returns text language sql stable security invoker set search_path = '' as $$
  select nullif(upper(regexp_replace(extensions.unaccent(coalesce(p_code, '')), '\s+', '', 'g')), '');
$$;

revoke execute on function brain.normalize_text(text) from public, anon;
revoke execute on function brain.normalize_code(text) from public, anon;
grant  execute on function brain.normalize_text(text) to authenticated, service_role;
grant  execute on function brain.normalize_code(text) to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- Fontes de conhecimento
-- ════════════════════════════════════════════════════════════
create table brain.knowledge_sources (
  key                  text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  name                 text not null,
  kind                 text not null default 'manufacturer'
                       check (kind in ('manufacturer', 'supplier', 'distributor', 'internal', 'regulator', 'other')),
  -- Ligação com o ERP. Marca e fornecedor continuam morando em public.
  brand_id             uuid references public.brands(id)     on delete set null,
  supplier_id          uuid references public.suppliers(id)  on delete set null,
  website              text,
  -- Quem responde pela fonte é um SETOR, não uma pessoa.
  owner_role           brain.knowledge_role not null default 'technical',
  reviewer_role        brain.knowledge_role not null default 'admin',
  default_access_level brain.access_level not null default 'internal',
  external_processing  brain.external_processing not null default 'approved_provider_only',
  is_active            boolean not null default true,
  metadata             jsonb not null default '{}'::jsonb,
  created_by           uuid references public.profiles(id) on delete set null,
  updated_by           uuid references public.profiles(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create trigger trg_knowledge_sources_updated_at before update on brain.knowledge_sources
  for each row execute function public.set_updated_at();

comment on table brain.knowledge_sources is
  'Origem institucional do conhecimento (Magnojet, DJI, Agres, AgroTork interno). Aponta para public.brands/suppliers; nunca os duplica.';

-- ════════════════════════════════════════════════════════════
-- Documentos (a obra) e versões (a edição)
-- ════════════════════════════════════════════════════════════
create table brain.documents (
  id                           uuid primary key default gen_random_uuid(),
  source_key                   text not null references brain.knowledge_sources(key) on delete restrict,
  slug                         text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]*$'),
  title                        text not null,
  document_type                brain.document_type not null,
  access_level                 brain.access_level not null,
  language                     text not null default 'pt-BR',
  brand_id                     uuid references public.brands(id)      on delete set null,
  category_id                  uuid references public.categories(id)  on delete set null,
  -- Governança
  owner_role                   brain.knowledge_role not null default 'technical',
  reviewer_role                brain.knowledge_role not null default 'admin',
  approved_by                  uuid references public.profiles(id) on delete set null,
  approved_at                  timestamptz,
  review_due_at                date,
  -- Opt-in/opt-out explícito de processamento externo para ESTE documento.
  -- Só vale com aprovador registrado: é uma decisão, não um default.
  external_processing_override brain.external_processing,
  metadata                     jsonb not null default '{}'::jsonb,
  created_by                   uuid references public.profiles(id) on delete set null,
  updated_by                   uuid references public.profiles(id) on delete set null,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),

  -- A decisao fica registrada pela DATA (e pelo audit_log); a pessoa e
  -- `on delete set null`, entao apagar o perfil de quem aprovou nao pode
  -- derrubar a aprovacao nem travar a exclusao do usuario.
  constraint chk_document_override_approved
    check (external_processing_override is null or approved_at is not null),
  constraint chk_document_approval_pair
    check (approved_by is null or approved_at is not null)
);

create index idx_documents_source on brain.documents (source_key);
create index idx_documents_brand  on brain.documents (brand_id) where brand_id is not null;
create index idx_documents_type   on brain.documents (document_type, access_level);

create trigger trg_documents_updated_at before update on brain.documents
  for each row execute function public.set_updated_at();

comment on table brain.documents is
  'O documento logico (a obra): "Catalogo Magnojet". Cada edicao e uma linha em document_versions.';

create table brain.document_versions (
  id                 uuid primary key default gen_random_uuid(),
  document_id        uuid not null references brain.documents(id) on delete cascade,
  version_label      text not null check (version_label <> ''),
  status             brain.version_status not null default 'draft',
  document_date      date,
  valid_from         date,
  valid_to           date,
  supersedes_id      uuid references brain.document_versions(id) on delete set null,
  -- Deferida: ao ativar uma versao nova, a anterior passa a apontar para ela
  -- ANTES de a nova existir (gatilho BEFORE INSERT). A conferencia fica para o COMMIT.
  superseded_by_id   uuid references brain.document_versions(id) on delete set null deferrable initially deferred,
  -- O arquivo original. Imutável depois de gravado (gatilho abaixo).
  storage_bucket     text not null default 'brain-documents' check (storage_bucket = 'brain-documents'),
  storage_path       text not null unique,
  original_filename  text not null,
  mime_type          text not null,
  file_size          bigint not null check (file_size > 0),
  file_sha256        text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  language           text not null default 'pt-BR',
  page_count         integer check (page_count is null or page_count >= 0),
  needs_ocr          boolean,
  text_ratio         numeric(6,4) check (text_ratio is null or text_ratio between 0 and 1),
  -- Copiado do documento por gatilho. Nunca digitado.
  access_level       brain.access_level not null,
  metadata           jsonb not null default '{}'::jsonb,
  imported_by        uuid references public.profiles(id) on delete set null,
  imported_at        timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint chk_version_validity check (valid_to is null or valid_from is null or valid_to >= valid_from),
  constraint chk_version_not_self check (supersedes_id is distinct from id and superseded_by_id is distinct from id),
  -- O caminho no Storage termina no proprio sha256: dois arquivos diferentes
  -- nunca ocupam o mesmo caminho, e substituicao silenciosa e impossivel.
  constraint chk_version_path_has_sha check (storage_path like '%/' || file_sha256 || '.%'),
  -- O mesmo arquivo nao vira segunda versao do mesmo documento.
  constraint uq_version_file unique (document_id, file_sha256),
  constraint uq_version_label unique (document_id, version_label)
);

-- Uma unica versao vigente por documento. E tambem o indice de
-- `current_version()`: (document_id) where status = 'active'.
create unique index uq_document_versions_active on brain.document_versions (document_id) where status = 'active';
-- A FK document_id ja e coberta por uq_version_file (document_id, file_sha256).
-- Mesmo arquivo registrado em outro documento? Busca por sha256.
create index idx_document_versions_sha on brain.document_versions (file_sha256);

create trigger trg_document_versions_updated_at before update on brain.document_versions
  for each row execute function public.set_updated_at();

comment on table brain.document_versions is
  'Cada edicao de um documento (Magnojet V40, V41; DJI Subdealer V14.11, V15.1, V16.2). Nova versao nao apaga a antiga: a marca superseded e aponta para ela.';

-- Nivel de acesso vem do documento; o arquivo e imutavel.
create or replace function brain.stamp_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select d.access_level into new.access_level from brain.documents d where d.id = new.document_id;
  if new.access_level is null then
    raise exception 'Versao sem documento: %', new.document_id using errcode = 'foreign_key_violation';
  end if;

  if tg_op = 'UPDATE' then
    if new.file_sha256 is distinct from old.file_sha256
    or new.storage_path is distinct from old.storage_path
    or new.storage_bucket is distinct from old.storage_bucket
    or new.file_size is distinct from old.file_size
    or new.mime_type is distinct from old.mime_type
    or new.original_filename is distinct from old.original_filename
    or new.document_id is distinct from old.document_id then
      raise exception 'O arquivo de uma versao e imutavel (sha256, caminho, tamanho, tipo, nome). Arquivo diferente e versao nova.'
        using errcode = 'restrict_violation';
    end if;
  end if;

  -- Ao ativar, a vigente anterior passa a superseded e as duas se apontam.
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    update brain.document_versions v
       set status = 'superseded',
           superseded_by_id = new.id,
           -- Nunca antes do proprio inicio: ativar uma edicao com data mais antiga
           -- que a vigente e raro, mas nao pode virar excecao de constraint.
           valid_to = coalesce(v.valid_to, greatest(new.valid_from - 1, v.valid_from), current_date)
     where v.document_id = new.document_id and v.status = 'active' and v.id <> new.id;
    if new.supersedes_id is null then
      select v.id into new.supersedes_id from brain.document_versions v
       where v.document_id = new.document_id and v.superseded_by_id = new.id
       order by v.imported_at desc limit 1;
    end if;
    new.valid_from := coalesce(new.valid_from, new.document_date, current_date);
    -- Reativar uma edicao (superseded/withdrawn → active) reabre a vigencia,
    -- a menos que o mesmo UPDATE tenha fixado um valid_to de proposito.
    if tg_op = 'UPDATE' and new.valid_to is not distinct from old.valid_to then
      new.valid_to := null;
    end if;
  end if;

  -- Estados sem ambiguidade (auditoria pre-publicacao):
  --   · ativar e um ato de HOJE: `valid_from` no futuro nao existe — a edicao
  --     que ainda nao vale fica `draft` ate o dia, e so entao e ativada. Sem
  --     isso, o documento ficaria sem edicao vigente entre a ativacao e a data;
  --   · `superseded` sempre tem fim de vigencia: sem `valid_to` seria uma
  --     "antiga" que nunca terminou.
  if new.status = 'active' and new.valid_from > current_date then
    raise exception 'Nao se ativa uma versao com valid_from no futuro (%). Deixe em draft ate la.', new.valid_from
      using errcode = 'check_violation';
  end if;
  if new.status = 'superseded' then
    new.valid_to := coalesce(new.valid_to, current_date);
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_version() from public, anon, authenticated;

create trigger trg_document_versions_stamp before insert or update on brain.document_versions
  for each row execute function brain.stamp_version();

-- ════════════════════════════════════════════════════════════
-- Ingestoes — "qual processo gerou estes chunks?"
-- ════════════════════════════════════════════════════════════
create table brain.knowledge_ingestions (
  id               uuid primary key default gen_random_uuid(),
  version_id       uuid not null references brain.document_versions(id) on delete cascade,
  status           brain.ingestion_status not null default 'pending',
  method           text not null check (method in ('pdf_text', 'pdf_ocr', 'xlsx', 'docx', 'pptx', 'manual', 'other')),
  parser           text,                 -- 'pdfplumber 0.11', 'tesseract 5.3 por+eng'
  pipeline_version text not null,        -- 'lote-a-fixture', 'v1'
  needs_ocr        boolean not null default false,
  executor         text,                 -- 'worker@maquina', 'fixture', e-mail do operador
  started_at       timestamptz,
  finished_at      timestamptz,
  pages_total      integer check (pages_total is null or pages_total >= 0),
  pages_done       integer check (pages_done is null or pages_done >= 0),
  chunks_created   integer check (chunks_created is null or chunks_created >= 0),
  tables_created   integer check (tables_created is null or tables_created >= 0),
  error            text,
  warnings         jsonb not null default '[]'::jsonb,
  metrics          jsonb not null default '{}'::jsonb,
  metadata         jsonb not null default '{}'::jsonb,
  access_level     brain.access_level not null,      -- copiado da versao
  created_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),

  constraint chk_ingestion_times check (finished_at is null or started_at is null or finished_at >= started_at),
  constraint chk_ingestion_failed_has_error check (status <> 'failed' or error is not null)
);

create index idx_ingestions_version on brain.knowledge_ingestions (version_id, created_at desc);
create index idx_ingestions_status  on brain.knowledge_ingestions (status) where status in ('pending', 'extracting', 'chunking');

-- ════════════════════════════════════════════════════════════
-- Paginas — a unidade de proveniencia
-- ════════════════════════════════════════════════════════════
create table brain.document_pages (
  version_id    uuid not null references brain.document_versions(id) on delete cascade,
  page_no       integer not null check (page_no >= 1),
  ingestion_id  uuid not null references brain.knowledge_ingestions(id) on delete restrict,
  text          text not null default '',
  text_sha256   text not null check (text_sha256 ~ '^[0-9a-f]{64}$'),
  extraction    text not null check (extraction in ('text_layer', 'ocr', 'spreadsheet', 'manual', 'none')),
  ocr           boolean not null default false,
  layout        jsonb not null default '{}'::jsonb,   -- caixas de tabela/figura detectadas
  metadata      jsonb not null default '{}'::jsonb,
  access_level  brain.access_level not null,          -- copiado da versao
  created_at    timestamptz not null default now(),
  primary key (version_id, page_no)
);

-- FK ingestion_id (on delete restrict): sem indice, apagar uma ingestao
-- varreria as paginas inteiras.
create index idx_pages_ingestion on brain.document_pages (ingestion_id);

comment on table brain.document_pages is
  'Texto por pagina. E aqui que a resposta futura encontra "p. 20". sha256 do texto permite saber se a extracao mudou.';

-- ════════════════════════════════════════════════════════════
-- Chunks — o que se recupera
-- ════════════════════════════════════════════════════════════
create table brain.document_chunks (
  id             bigint generated always as identity primary key,
  version_id     uuid not null references brain.document_versions(id) on delete cascade,
  ingestion_id   uuid not null references brain.knowledge_ingestions(id) on delete restrict,
  ordinal        integer not null check (ordinal >= 0),
  kind           brain.chunk_kind not null default 'text',
  page_from      integer not null check (page_from >= 1),
  page_to        integer not null check (page_to >= 1),
  heading_path   text[] not null default '{}',
  content        text not null check (content <> ''),
  content_norm   text not null default '',            -- gatilho: lower + unaccent
  content_sha256 text not null default '',            -- gatilho
  -- Tabela tecnica: cabecalho, unidades e linhas com NUMEROS numericos.
  table_data     jsonb,
  -- Codigos extraidos, normalizados (MJ981CAP, T70P, DB1580): busca exata.
  codes          text[] not null default '{}',
  token_count    integer check (token_count is null or token_count >= 0),
  metadata       jsonb not null default '{}'::jsonb,
  access_level   brain.access_level not null,          -- copiado da versao
  -- Indexavel: gerado a partir do texto ja normalizado. `to_tsvector(regconfig, text)` e immutable.
  fts            tsvector generated always as (to_tsvector('portuguese'::regconfig, content_norm)) stored,
  created_at     timestamptz not null default now(),

  constraint chk_chunk_pages check (page_to >= page_from),
  -- O chunk aponta para uma pagina que EXISTE naquela versao.
  constraint fk_chunk_page foreign key (version_id, page_from)
    references brain.document_pages (version_id, page_no) on delete cascade,
  -- Tabela e tabela: com estrutura, ou nao e tabela.
  constraint chk_chunk_table_shape check (
    (kind not in ('table', 'price_table') and table_data is null)
    or (kind in ('table', 'price_table')
        and table_data is not null
        and jsonb_typeof(table_data -> 'headers') = 'array'
        and jsonb_typeof(table_data -> 'rows') = 'array'
        and jsonb_array_length(table_data -> 'headers') > 0)
  ),
  constraint uq_chunk_ordinal unique (version_id, ordinal),
  constraint uq_chunk_content unique (version_id, content_sha256)
);

-- Os tres bracos da busca, cada um com o SEU operador indexavel:
--   fts   @@   (tsvector)      idx_chunks_fts
--   <%    trigram por palavra  idx_chunks_trgm   (word_similarity via operador)
--   &&    codigos              idx_chunks_codes
create index idx_chunks_fts       on brain.document_chunks using gin (fts);
create index idx_chunks_trgm      on brain.document_chunks using gin (content_norm extensions.gin_trgm_ops);
create index idx_chunks_codes     on brain.document_chunks using gin (codes);
-- Cobre a FK version_id e a FK composta (version_id, page_from).
create index idx_chunks_version   on brain.document_chunks (version_id, page_from);
create index idx_chunks_ingestion on brain.document_chunks (ingestion_id);
create index idx_chunks_kind      on brain.document_chunks (kind) where kind in ('table', 'price_table');
-- Sem indice em access_level: quatro valores, o planejador nao o usaria; o
-- filtro de acesso e avaliado no mesmo no de varredura que os bracos acima.

comment on table brain.document_chunks is
  'Unidade pesquisavel. content para FTS/trigram; table_data para tabela tecnica com numeros; codes para busca exata de codigo/modelo. Nunca cruza uma tabela.';

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
  new.content_sha256 := encode(sha256(convert_to(new.content, 'UTF8')), 'hex');
  new.codes := coalesce((select array_agg(distinct c order by c)
                           from unnest(new.codes) raw, lateral (select brain.normalize_code(raw)) n(c)
                          where c is not null), '{}');
  return new;
end;
$$;

revoke execute on function brain.stamp_chunk() from public, anon, authenticated;

create trigger trg_document_chunks_stamp before insert or update on brain.document_chunks
  for each row execute function brain.stamp_chunk();

-- Paginas e ingestoes: nivel copiado da versao; sha256 do texto da pagina.
create or replace function brain.stamp_page()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select v.access_level into new.access_level from brain.document_versions v where v.id = new.version_id;
  if new.access_level is null then
    raise exception 'Pagina sem versao: %', new.version_id using errcode = 'foreign_key_violation';
  end if;
  if not exists (select 1 from brain.knowledge_ingestions i where i.id = new.ingestion_id and i.version_id = new.version_id) then
    raise exception 'A ingestao % nao e desta versao %', new.ingestion_id, new.version_id using errcode = 'foreign_key_violation';
  end if;
  new.text_sha256 := encode(sha256(convert_to(new.text, 'UTF8')), 'hex');
  return new;
end;
$$;

create or replace function brain.stamp_ingestion()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select v.access_level into new.access_level from brain.document_versions v where v.id = new.version_id;
  if new.access_level is null then
    raise exception 'Ingestao sem versao: %', new.version_id using errcode = 'foreign_key_violation';
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_page()      from public, anon, authenticated;
revoke execute on function brain.stamp_ingestion() from public, anon, authenticated;

create trigger trg_document_pages_stamp before insert or update on brain.document_pages
  for each row execute function brain.stamp_page();
create trigger trg_knowledge_ingestions_stamp before insert or update on brain.knowledge_ingestions
  for each row execute function brain.stamp_ingestion();

-- ════════════════════════════════════════════════════════════
-- Vinculo chunk ↔ produto do ERP
-- ════════════════════════════════════════════════════════════
create table brain.chunk_products (
  chunk_id        bigint not null references brain.document_chunks(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  confidence      numeric(4,3) not null default 1 check (confidence between 0 and 1),
  linked_by       brain.link_origin not null default 'manual',
  linked_by_user  uuid references public.profiles(id) on delete set null,
  evidence        text,
  access_level    brain.access_level not null,          -- copiado do chunk
  created_at      timestamptz not null default now(),
  primary key (chunk_id, product_id)
);

create index idx_chunk_products_product on brain.chunk_products (product_id);

comment on table brain.chunk_products is
  'Trecho documental → produto de public.products. Aponta; nunca cria catalogo paralelo nem escreve preco.';

create or replace function brain.stamp_chunk_product()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select c.access_level into new.access_level from brain.document_chunks c where c.id = new.chunk_id;
  if new.access_level is null then
    raise exception 'Vinculo sem chunk: %', new.chunk_id using errcode = 'foreign_key_violation';
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_chunk_product() from public, anon, authenticated;

create trigger trg_chunk_products_stamp before insert or update on brain.chunk_products
  for each row execute function brain.stamp_chunk_product();

-- ════════════════════════════════════════════════════════════
-- Reclassificar um documento reclassifica a cadeia inteira
-- ════════════════════════════════════════════════════════════
-- Um UPDATE em documents.access_level desce: versoes → ingestoes, paginas,
-- chunks → vinculos. Cada gatilho BEFORE UPDATE reconfere com o pai, entao
-- basta "tocar" as linhas filhas.
create or replace function brain.cascade_document_access()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  update brain.document_versions set access_level = new.access_level where document_id = new.id;
  return null;
end;
$$;

create or replace function brain.cascade_version_access()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  update brain.knowledge_ingestions set access_level = new.access_level where version_id = new.id;
  update brain.document_pages       set access_level = new.access_level where version_id = new.id;
  update brain.document_chunks      set access_level = new.access_level where version_id = new.id;
  return null;
end;
$$;

create or replace function brain.cascade_chunk_access()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  update brain.chunk_products set access_level = new.access_level where chunk_id = new.id;
  return null;
end;
$$;

revoke execute on function brain.cascade_document_access() from public, anon, authenticated;
revoke execute on function brain.cascade_version_access()  from public, anon, authenticated;
revoke execute on function brain.cascade_chunk_access()    from public, anon, authenticated;

create trigger trg_documents_cascade_access after update of access_level on brain.documents
  for each row when (old.access_level is distinct from new.access_level)
  execute function brain.cascade_document_access();
create trigger trg_document_versions_cascade_access after update of access_level on brain.document_versions
  for each row when (old.access_level is distinct from new.access_level)
  execute function brain.cascade_version_access();
create trigger trg_document_chunks_cascade_access after update of access_level on brain.document_chunks
  for each row when (old.access_level is distinct from new.access_level)
  execute function brain.cascade_chunk_access();

-- ════════════════════════════════════════════════════════════
-- Processamento externo — a unica resposta
-- ════════════════════════════════════════════════════════════
create or replace function brain.external_processing_for(p_document_id uuid)
returns brain.external_processing language sql stable security invoker set search_path = '' as $$
  select case d.access_level
    when 'admin'      then 'forbidden'::brain.external_processing
    when 'commercial' then coalesce(d.external_processing_override, 'forbidden'::brain.external_processing)
    when 'internal'   then greatest(coalesce(d.external_processing_override, s.external_processing),
                                    'approved_provider_only'::brain.external_processing)
    else                   coalesce(d.external_processing_override, s.external_processing)
  end
  from brain.documents d
  join brain.knowledge_sources s on s.key = d.source_key
  where d.id = p_document_id;
$$;
-- Nota: `greatest` sobre o enum usa a ordem de declaracao — allowed <
-- approved_provider_only < forbidden — entao `internal` fica no minimo em "so
-- provedor aprovado" e so pode ficar MAIS restrito (forbidden), nunca menos.

revoke execute on function brain.external_processing_for(uuid) from public, anon;
grant  execute on function brain.external_processing_for(uuid) to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- RLS — leitura por nivel, escrita so do administrador
-- ════════════════════════════════════════════════════════════
-- `service_role` e `postgres` (worker, cron, migration) passam por cima do
-- RLS por natureza; `anon` nao tem USAGE no schema. As policies abaixo sao
-- para `authenticated`, e a leitura e uma comparacao de coluna: o conjunto
-- candidato de qualquer busca ja nasce sem o que o chamador nao pode ver.
-- `(select brain.caller_access_level())` vira initPlan: o nivel do chamador
-- e calculado UMA vez por consulta, nao uma vez por linha (advisor
-- auth_rls_initplan). Nivel NULL: `x <= null` e null → linha negada.
alter table brain.knowledge_sources    enable row level security;
alter table brain.documents            enable row level security;
alter table brain.document_versions    enable row level security;
alter table brain.knowledge_ingestions enable row level security;
alter table brain.document_pages       enable row level security;
alter table brain.document_chunks      enable row level security;
alter table brain.chunk_products       enable row level security;

-- Fonte e visivel se o chamador alcanca o nivel padrao dela OU ja enxerga
-- algum documento dela (a subconsulta em documents corre sob o RLS de
-- documents). Uma fonte `admin` sem documento publico nao aparece nem por nome.
create policy knowledge_sources_select on brain.knowledge_sources for select to authenticated
  using (default_access_level <= (select brain.caller_access_level())
         or exists (select 1 from brain.documents d where d.source_key = knowledge_sources.key));
create policy knowledge_sources_admin_insert on brain.knowledge_sources for insert to authenticated
  with check ((select public.is_admin()));
create policy knowledge_sources_admin_update on brain.knowledge_sources for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy knowledge_sources_admin_delete on brain.knowledge_sources for delete to authenticated
  using ((select public.is_admin()));

create policy documents_select on brain.documents for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy documents_admin_insert on brain.documents for insert to authenticated
  with check ((select public.is_admin()));
create policy documents_admin_update on brain.documents for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy documents_admin_delete on brain.documents for delete to authenticated
  using ((select public.is_admin()));

create policy document_versions_select on brain.document_versions for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy document_versions_admin_insert on brain.document_versions for insert to authenticated
  with check ((select public.is_admin()));
create policy document_versions_admin_update on brain.document_versions for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy document_versions_admin_delete on brain.document_versions for delete to authenticated
  using ((select public.is_admin()));

create policy knowledge_ingestions_select on brain.knowledge_ingestions for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy knowledge_ingestions_admin_insert on brain.knowledge_ingestions for insert to authenticated
  with check ((select public.is_admin()));
create policy knowledge_ingestions_admin_update on brain.knowledge_ingestions for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy knowledge_ingestions_admin_delete on brain.knowledge_ingestions for delete to authenticated
  using ((select public.is_admin()));

create policy document_pages_select on brain.document_pages for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy document_pages_admin_insert on brain.document_pages for insert to authenticated
  with check ((select public.is_admin()));
create policy document_pages_admin_update on brain.document_pages for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy document_pages_admin_delete on brain.document_pages for delete to authenticated
  using ((select public.is_admin()));

create policy document_chunks_select on brain.document_chunks for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy document_chunks_admin_insert on brain.document_chunks for insert to authenticated
  with check ((select public.is_admin()));
create policy document_chunks_admin_update on brain.document_chunks for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy document_chunks_admin_delete on brain.document_chunks for delete to authenticated
  using ((select public.is_admin()));

create policy chunk_products_select on brain.chunk_products for select to authenticated
  using (access_level <= (select brain.caller_access_level()));
create policy chunk_products_admin_insert on brain.chunk_products for insert to authenticated
  with check ((select public.is_admin()));
create policy chunk_products_admin_update on brain.chunk_products for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy chunk_products_admin_delete on brain.chunk_products for delete to authenticated
  using ((select public.is_admin()));

-- Grants: o schema ja nega tudo a anon/public por default (migration 130000).
grant select, insert, update, delete on
  brain.knowledge_sources, brain.documents, brain.document_versions, brain.knowledge_ingestions,
  brain.document_pages, brain.document_chunks, brain.chunk_products
  to authenticated, service_role;
grant usage, select on sequence brain.document_chunks_id_seq to authenticated, service_role;

-- Auditoria de alteracao de dados: mesmo audit_capture do ERP.
create trigger trg_audit_knowledge_sources after insert or update or delete on brain.knowledge_sources
  for each row execute function public.audit_capture('knowledge_source', 'key', 'name', '', '');
create trigger trg_audit_documents after insert or update or delete on brain.documents
  for each row execute function public.audit_capture('document', 'id', 'title', '', '');
create trigger trg_audit_document_versions after insert or update or delete on brain.document_versions
  for each row execute function public.audit_capture('document_version', 'id', 'version_label', 'document', 'document_id');

-- ════════════════════════════════════════════════════════════
-- Guardas do lote
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; r record;
begin
  -- Nenhuma tabela da memoria sem RLS.
  select count(*) into v_n from pg_tables
   where schemaname = 'brain'
     and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions',
                       'document_pages','document_chunks','chunk_products')
     and not rowsecurity;
  if v_n <> 0 then raise exception 'Tabela da memoria sem RLS'; end if;

  -- Nenhuma policy permissiva duplicada por (papel, acao) — o advisor mede isso.
  for r in
    select tablename, roles, cmd, count(*) as n from pg_policies
     where schemaname = 'brain' and permissive = 'PERMISSIVE'
     group by tablename, roles, cmd having count(*) > 1
  loop
    raise exception 'brain.% com % policies permissivas para % em %', r.tablename, r.n, r.roles, r.cmd;
  end loop;

  -- Nada de vetor neste lote.
  if exists (select 1 from pg_extension where extname = 'vector') then
    raise exception 'pgvector instalado — nao pertence ao Lote A';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'brain' and udt_name in ('vector', 'halfvec', 'sparsevec')) then
    raise exception 'Coluna vetorial no brain — nao pertence ao Lote A';
  end if;

  -- Nenhuma funcao nova declarada immutable (invariante da 20260911160000).
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  if v_n <> 0 then raise exception 'Funcao do brain declarada immutable indevidamente'; end if;

  -- anon continua sem nada.
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'brain' and grantee = 'anon') then
    raise exception 'anon com grant em tabela do brain';
  end if;
end
$$;
