-- ============================================================
-- BRAIN — Fase 2, Lote A: memória corporativa sem vetor
-- (migrations 20260912010000 e 20260912020000).
--
-- Fixtures artificiais, com o formato dos documentos reais do inventário
-- (docs/brain/fase-2-etapa-0.md): um catálogo público com duas versões
-- (V40 superseded, V41 vigente) e uma retirada (V39), uma tabela de preço
-- commercial, um procedimento internal, uma planilha admin. Nenhum dado
-- real do ERP é alterado permanentemente: o produto de teste é criado e
-- apagado aqui.
--
--   RAG-A1   esquema: 7 tabelas com RLS, 8 tipos, nada de vetor
--   RAG-A2   FKs e constraints (negativos)
--   RAG-A3   documento com varias versoes; uma vigente; encadeamento
--   RAG-A4   checksum e proveniencia do arquivo
--   RAG-A5   paginas ligadas a versao, com sha256 do texto
--   RAG-A6   chunks ligados a pagina e a ingestao
--   RAG-A7   tabela tecnica em JSONB numerico + texto pesquisavel
--   RAG-A8   chunk ↔ produto do ERP
--   RAG-A9   FTS
--   RAG-A10  codigo exato, inclusive digitado com espaco
--   RAG-A11  trigram (erro de digitacao)
--   RAG-A12  vendedor nao ve commercial/admin — nem por contagem
--   RAG-A13  nem por busca, filtro, proveniencia ou funcao auxiliar; nem escreve
--   RAG-A14  vigencia: so a versao atual por padrao; historico so quando pedido; withdrawn nunca
--   RAG-A15  reclassificar o documento reclassifica a cadeia; processamento externo
--   RAG-A16  anon: nada
--
-- Prefixo de UUID = 33.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('33333333-0000-4000-8000-000000000001','rag.admin@teste.local','{"full_name":"Admin Memoria","role":"admin"}'),
 ('33333333-0000-4000-8000-000000000002','rag.vend@teste.local' ,'{"full_name":"Vendedor Memoria","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '33333333-0000-4000-8000-000000000001';

insert into public.products (id, code, name, unit_id, sale_price)
select '33333333-0000-4000-8000-0000000000e1', 'RAGA-001', 'Ponta MJ981CAP (produto de teste)', u.id, 0
  from public.units u where u.code = 'UN';

-- ── Fixtures ────────────────────────────────────────────────
insert into brain.knowledge_sources (key, name, kind, brand_id, default_access_level, external_processing, owner_role) values
 ('magnojet', 'Magnojet', 'manufacturer', (select id from public.brands where name = 'MAGNOJET'), 'public', 'allowed', 'technical'),
 ('dji',      'DJI Agriculture', 'manufacturer', (select id from public.brands where name = 'DJI'), 'commercial', 'forbidden', 'commercial'),
 ('agrotork', 'AgroTork (interno)', 'internal', null, 'internal', 'approved_provider_only', 'admin');

insert into brain.documents (id, source_key, slug, title, document_type, access_level, owner_role) values
 ('33333333-0000-4000-8000-0000000000d1', 'magnojet', 'magnojet-catalogo',        'Catálogo Magnojet',         'catalog',       'public',     'technical'),
 ('33333333-0000-4000-8000-0000000000d2', 'dji',      'dji-tabela-subdealer',     'Tabela Subdealer DJI',      'price_list',    'commercial', 'commercial'),
 ('33333333-0000-4000-8000-0000000000d3', 'agrotork', 'calibracao-fighter-ad-ia', 'Calibração Fighter AD-IA',  'procedure',     'internal',   'technical'),
 ('33333333-0000-4000-8000-0000000000d4', 'agrotork', 'planilha-margem-2026',     'Planilha de margem 2026',   'internal_note', 'admin',      'admin');

-- sha256 ficticios, distintos, com 64 hex.
insert into brain.document_versions (id, document_id, version_label, status, document_date, valid_from, storage_path, original_filename, mime_type, file_size, file_sha256, page_count) values
 ('33333333-0000-4000-8000-0000000000a1', '33333333-0000-4000-8000-0000000000d1', 'V39', 'withdrawn', '2023-01-01', '2023-01-01',
   'magnojet/magnojet-catalogo/V39/' || repeat('39', 32) || '.pdf', 'CATALOGO V39.pdf', 'application/pdf', 150000000, repeat('39', 32), 160),
 ('33333333-0000-4000-8000-0000000000a2', '33333333-0000-4000-8000-0000000000d1', 'V40', 'active', '2025-01-01', '2025-01-01',
   'magnojet/magnojet-catalogo/V40/' || repeat('40', 32) || '.pdf', 'CATÁLOGO V40 DIGITAL.pdf', 'application/pdf', 161782956, repeat('40', 32), 168);

-- V41 entra vigente: V40 tem de virar superseded sozinha.
insert into brain.document_versions (id, document_id, version_label, status, document_date, valid_from, storage_path, original_filename, mime_type, file_size, file_sha256, page_count) values
 ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000d1', 'V41', 'active', '2026-06-01', '2026-06-01',
   'magnojet/magnojet-catalogo/V41/' || repeat('41', 32) || '.pdf', 'MAGNOJET-CATALOGO_BR41_DIGITAL-V2.pdf', 'application/pdf', 177741060, repeat('41', 32), 172),
 ('33333333-0000-4000-8000-0000000000b1', '33333333-0000-4000-8000-0000000000d2', 'V16.2', 'active', '2026-09-01', '2026-09-01',
   'dji/dji-tabela-subdealer/V16.2/' || repeat('62', 32) || '.pdf', 'TABELASUBDEALERV16.2  B.pdf', 'application/pdf', 93131, repeat('62', 32), 1),
 ('33333333-0000-4000-8000-0000000000c1', '33333333-0000-4000-8000-0000000000d3', '2024-10', 'active', '2024-10-26', '2024-10-26',
   'agrotork/calibracao-fighter-ad-ia/2024-10/' || repeat('ad', 32) || '.pdf', 'FIGHTER AD-IA.pdf', 'application/pdf', 1523781, repeat('ad', 32), 17),
 ('33333333-0000-4000-8000-0000000000e9', '33333333-0000-4000-8000-0000000000d4', '2026', 'active', '2026-09-01', '2026-09-01',
   'agrotork/planilha-margem-2026/2026/' || repeat('a9', 32) || '.xlsx', 'TABELA DE PREÇO  NOVA 2026.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 70268, repeat('a9', 32), 10);

insert into brain.knowledge_ingestions (id, version_id, status, method, parser, pipeline_version, executor, started_at, finished_at, pages_total, pages_done, chunks_created, tables_created) values
 ('33333333-0000-4000-8000-0000000000f2', '33333333-0000-4000-8000-0000000000a2', 'completed', 'pdf_text', 'fixture', 'lote-a-fixture', 'fixture', now() - interval '2 minute', now() - interval '1 minute', 168, 168, 1, 1),
 ('33333333-0000-4000-8000-0000000000f3', '33333333-0000-4000-8000-0000000000a3', 'completed', 'pdf_text', 'fixture', 'lote-a-fixture', 'fixture', now() - interval '2 minute', now() - interval '1 minute', 172, 172, 2, 1),
 ('33333333-0000-4000-8000-0000000000f4', '33333333-0000-4000-8000-0000000000b1', 'completed', 'pdf_text', 'fixture', 'lote-a-fixture', 'fixture', now() - interval '2 minute', now() - interval '1 minute', 1, 1, 1, 1),
 ('33333333-0000-4000-8000-0000000000f5', '33333333-0000-4000-8000-0000000000c1', 'completed', 'pdf_text', 'fixture', 'lote-a-fixture', 'fixture', now() - interval '2 minute', now() - interval '1 minute', 17, 17, 1, 0),
 ('33333333-0000-4000-8000-0000000000f6', '33333333-0000-4000-8000-0000000000e9', 'completed', 'xlsx',     'fixture', 'lote-a-fixture', 'fixture', now() - interval '2 minute', now() - interval '1 minute', 10, 10, 1, 0);

insert into brain.document_pages (version_id, page_no, ingestion_id, text, extraction) values
 ('33333333-0000-4000-8000-0000000000a2', 19, '33333333-0000-4000-8000-0000000000f2', 'MAGNO ULTRA GROSSA CONE VAZIO MJ981CAP 2,76 bar 40 psi 0,75 L/min', 'text_layer'),
 ('33333333-0000-4000-8000-0000000000a3',  1, '33333333-0000-4000-8000-0000000000f3', 'Estabelecida em 1985, a Magnojet revolucionou o mercado ao introduzir pontas de pulverização com núcleo de cerâmica.', 'text_layer'),
 ('33333333-0000-4000-8000-0000000000a3', 20, '33333333-0000-4000-8000-0000000000f3', 'APLICAÇÕES DE HERBICIDAS SISTÊMICOS EM PRÉ E PÓS-EMERGÊNCIA MAGNO ULTRA GROSSA CONE VAZIO MJ981CAP MUG-CV 02 ...', 'text_layer'),
 ('33333333-0000-4000-8000-0000000000b1',  1, '33333333-0000-4000-8000-0000000000f4', 'DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000 SUBDEALER REVENDA Pgto faturado R$ 165.500,00 Pgto à vista R$ 161.900,00', 'text_layer'),
 ('33333333-0000-4000-8000-0000000000c1',  3, '33333333-0000-4000-8000-0000000000f5', 'Calibração do Fighter AD-IA: passo 1, zerar o sensor; passo 2, aplicar pressão de referência.', 'text_layer'),
 ('33333333-0000-4000-8000-0000000000e9',  1, '33333333-0000-4000-8000-0000000000f6', 'TABELA DE PREÇO T100 — 2026 MARGEM AJUSTÁVEL 0,779', 'spreadsheet');

-- A p. 20 do Magnojet V41 (docs/brain/fase-2-etapa-0.md, §9), duas linhas.
insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, heading_path, content, table_data, codes) values
 ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f3', 0, 'text', 1, 1, '{"Institucional"}',
  'Estabelecida em 1985, a Magnojet revolucionou o mercado ao introduzir pontas de pulverização com núcleo de cerâmica, elevando os padrões de precisão e durabilidade.', null, '{}'),
 ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f3', 1, 'table', 20, 20, '{"PONTAS","MAGNO ULTRA GROSSA","CONE VAZIO"}',
  'MJ981CAP MUG-CV 02 gotas UG 2,07 bar 30 psi 207 kPa 0,66 L/min; 12 km/h 66 L/ha' || E'\n' ||
  'MJ981CAP MUG-CV 02 gotas UG 2,76 bar 40 psi 276 kPa 0,77 L/min; 12 km/h 77 L/ha',
  jsonb_build_object(
    'page', 20, 'family', 'MAGNO ULTRA GROSSA', 'geometry', 'CONE VAZIO',
    'headers', jsonb_build_array('codigo','serie','gotas','bar','psi','kPa','L_min','L_ha@12'),
    'units',   jsonb_build_object('bar','bar','psi','psi','kPa','kPa','L_min','L/min','L_ha@12','L/ha a 12 km/h, espacamento 50 cm'),
    'rows',    jsonb_build_array(
                 jsonb_build_array('MJ981CAP','MUG-CV 02','UG',2.07,30,207,0.66,66),
                 jsonb_build_array('MJ981CAP','MUG-CV 02','UG',2.76,40,276,0.77,77)),
    'notes',   jsonb_build_array('MALHA 50')),
  '{"MJ981CAP","mug-cv 02"}'),
 ('33333333-0000-4000-8000-0000000000a2', '33333333-0000-4000-8000-0000000000f2', 0, 'table', 19, 19, '{"PONTAS","MAGNO ULTRA GROSSA","CONE VAZIO"}',
  'MJ981CAP MUG-CV 02 gotas UG 2,76 bar 40 psi 276 kPa 0,75 L/min (edicao V40)',
  jsonb_build_object('page', 19, 'headers', jsonb_build_array('codigo','bar','psi','L_min'),
                     'rows', jsonb_build_array(jsonb_build_array('MJ981CAP',2.76,40,0.75))),
  '{"MJ981CAP"}'),
 ('33333333-0000-4000-8000-0000000000b1', '33333333-0000-4000-8000-0000000000f4', 0, 'price_table', 1, 1, '{"SUBDEALER REVENDA"}',
  'DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000: subdealer revenda faturado R$ 165.500,00; à vista R$ 161.900,00; cliente final mínimo R$ 225.000,00',
  jsonb_build_object('page', 1, 'headers', jsonb_build_array('item','faturado','a_vista','cliente_final_minimo'),
                     'units', jsonb_build_object('faturado','BRL','a_vista','BRL','cliente_final_minimo','BRL'),
                     'rows', jsonb_build_array(jsonb_build_array('DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000',165500,161900,225000))),
  '{"T100","C12000","DB2160"}'),
 ('33333333-0000-4000-8000-0000000000c1', '33333333-0000-4000-8000-0000000000f5', 0, 'text', 3, 3, '{"Calibração"}',
  'Calibração do Fighter AD-IA: passo 1, zerar o sensor; passo 2, aplicar pressão de referência; passo 3, confirmar leitura.', null, '{"AD-IA"}'),
 ('33333333-0000-4000-8000-0000000000e9', '33333333-0000-4000-8000-0000000000f6', 0, 'text', 1, 1, '{"T100 DUAL"}',
  'TABELA DE PREÇO T100 — 2026: margem ajustável 0,779; custo total; preço de venda; lucro.', null, '{"T100"}');

insert into brain.chunk_products (chunk_id, product_id, confidence, linked_by, evidence)
select c.id, '33333333-0000-4000-8000-0000000000e1', 1.0, 'manual', 'codigo MJ981CAP na tabela'
  from brain.document_chunks c where c.version_id = '33333333-0000-4000-8000-0000000000a3' and c.kind = 'table';
insert into brain.chunk_products (chunk_id, product_id, confidence, linked_by, evidence)
select c.id, '33333333-0000-4000-8000-0000000000e1', 0.6, 'rule', 'teste: vinculo de chunk commercial a produto publico'
  from brain.document_chunks c where c.version_id = '33333333-0000-4000-8000-0000000000b1';

-- ════════════════════════════════════════════════════════════
-- RAG-A1 — esquema
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int;
begin
  select count(*) into v_n from pg_tables where schemaname = 'brain' and rowsecurity
     and tablename in ('knowledge_sources','documents','document_versions','knowledge_ingestions','document_pages','document_chunks','chunk_products');
  if v_n <> 7 then raise exception 'RAG-A1 FALHOU: % das 7 tabelas com RLS', v_n; end if;
  select count(*) into v_n from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'brain' and t.typtype = 'e'
     and t.typname in ('access_level','document_type','version_status','ingestion_status','chunk_kind','link_origin','external_processing','knowledge_role');
  if v_n <> 8 then raise exception 'RAG-A1 FALHOU: % dos 8 tipos', v_n; end if;
  if exists (select 1 from pg_extension where extname = 'vector') then raise exception 'RAG-A1 FALHOU: vector instalado'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'brain' and udt_name in ('vector','halfvec','sparsevec')) then
    raise exception 'RAG-A1 FALHOU: coluna vetorial';
  end if;
  if exists (select 1 from pg_indexes where schemaname = 'brain' and (indexdef ilike '%hnsw%' or indexdef ilike '%ivfflat%')) then
    raise exception 'RAG-A1 FALHOU: indice vetorial';
  end if;
  select count(*) into v_n from pg_indexes where schemaname = 'brain' and tablename = 'document_chunks'
     and indexname in ('idx_chunks_fts','idx_chunks_trgm','idx_chunks_codes');
  if v_n <> 3 then raise exception 'RAG-A1 FALHOU: indices de busca: %', v_n; end if;
  raise notice ' RAG-A1) OK: 7 tabelas com RLS, 8 tipos, indices FTS/trigram/codigos, nada de vetor';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A2 — constraints (negativos)
-- ════════════════════════════════════════════════════════════
do $$
declare v_ok int := 0;
begin
  -- chunk numa pagina que nao existe
  begin
    insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content)
    values ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f3', 99, 'text', 999, 999, 'x');
    raise exception 'RAG-A2 FALHOU: chunk em pagina inexistente';
  exception when foreign_key_violation then v_ok := v_ok + 1; end;
  -- tabela sem table_data
  begin
    insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content)
    values ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f3', 99, 'table', 20, 20, 'x');
    raise exception 'RAG-A2 FALHOU: tabela sem estrutura';
  exception when check_violation then v_ok := v_ok + 1; end;
  -- texto com table_data
  begin
    insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content, table_data)
    values ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f3', 99, 'text', 20, 20, 'x', '{"headers":["a"],"rows":[]}');
    raise exception 'RAG-A2 FALHOU: texto com estrutura de tabela';
  exception when check_violation then v_ok := v_ok + 1; end;
  -- ingestao de outra versao
  begin
    insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content)
    values ('33333333-0000-4000-8000-0000000000a3', '33333333-0000-4000-8000-0000000000f2', 99, 'text', 20, 20, 'x');
    raise exception 'RAG-A2 FALHOU: ingestao de outra versao aceita';
  exception when foreign_key_violation then v_ok := v_ok + 1; end;
  -- caminho no storage sem o sha256
  begin
    insert into brain.document_versions (document_id, version_label, storage_path, original_filename, mime_type, file_size, file_sha256)
    values ('33333333-0000-4000-8000-0000000000d1', 'V42', 'magnojet/x/V42/arquivo.pdf', 'x.pdf', 'application/pdf', 1, repeat('42', 32));
    raise exception 'RAG-A2 FALHOU: caminho sem sha256 aceito';
  exception when check_violation then v_ok := v_ok + 1; end;
  -- mesmo arquivo como segunda versao do mesmo documento
  begin
    insert into brain.document_versions (document_id, version_label, storage_path, original_filename, mime_type, file_size, file_sha256)
    values ('33333333-0000-4000-8000-0000000000d1', 'V41-copia', 'magnojet/x/V41c/' || repeat('41', 32) || '.pdf', 'x.pdf', 'application/pdf', 1, repeat('41', 32));
    raise exception 'RAG-A2 FALHOU: mesmo sha256 virou segunda versao';
  exception when unique_violation then v_ok := v_ok + 1; end;
  -- arquivo imutavel
  begin
    update brain.document_versions set file_sha256 = repeat('ff', 32) where id = '33333333-0000-4000-8000-0000000000a3';
    raise exception 'RAG-A2 FALHOU: sha256 alterado';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  -- segunda versao vigente do mesmo documento por UPDATE direto
  begin
    update brain.document_versions set status = 'active' where id = '33333333-0000-4000-8000-0000000000a1';
    -- o gatilho supersede a V41 antes; entao NAO e violacao — e comportamento: V39 vira vigente. Desfaz.
    if (select count(*) from brain.document_versions where document_id = '33333333-0000-4000-8000-0000000000d1' and status = 'active') <> 1 then
      raise exception 'RAG-A2 FALHOU: duas vigentes';
    end if;
    update brain.document_versions set status = 'active' where id = '33333333-0000-4000-8000-0000000000a3';
    update brain.document_versions set status = 'withdrawn', superseded_by_id = null where id = '33333333-0000-4000-8000-0000000000a1';
    v_ok := v_ok + 1;
  end;
  -- override de processamento externo sem aprovador
  begin
    update brain.documents set external_processing_override = 'allowed' where id = '33333333-0000-4000-8000-0000000000d2';
    raise exception 'RAG-A2 FALHOU: opt-in sem aprovador';
  exception when check_violation then v_ok := v_ok + 1; end;
  if v_ok <> 9 then raise exception 'RAG-A2 FALHOU: % de 9 negativos', v_ok; end if;
  raise notice ' RAG-A2) OK: 9 constraints negativas (pagina, tabela x2, ingestao, caminho, sha duplicado, imutavel, uma vigente, opt-in)';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A3 — versoes
-- ════════════════════════════════════════════════════════════
do $$
declare v40 record; v41 record;
begin
  select * into v40 from brain.document_versions where id = '33333333-0000-4000-8000-0000000000a2';
  select * into v41 from brain.document_versions where id = '33333333-0000-4000-8000-0000000000a3';
  if v40.status <> 'superseded' then raise exception 'RAG-A3 FALHOU: V40 em %', v40.status; end if;
  if v40.superseded_by_id <> v41.id then raise exception 'RAG-A3 FALHOU: V40 nao aponta para V41'; end if;
  if v41.supersedes_id <> v40.id then raise exception 'RAG-A3 FALHOU: V41 nao aponta para V40'; end if;
  if v40.valid_to <> date '2026-05-31' then raise exception 'RAG-A3 FALHOU: valid_to da V40 = %', v40.valid_to; end if;
  if (select count(*) from brain.document_versions where document_id = '33333333-0000-4000-8000-0000000000d1') <> 3 then
    raise exception 'RAG-A3 FALHOU: historico perdido';
  end if;
  if brain.current_version('33333333-0000-4000-8000-0000000000d1') <> v41.id then raise exception 'RAG-A3 FALHOU: current_version'; end if;
  raise notice ' RAG-A3) OK: V39 withdrawn, V40 superseded (valid_to 2026-05-31) ← V41 vigente; historico inteiro preservado';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A4 / A5 / A6 / A7 — proveniencia, paginas, chunks, tabela
-- ════════════════════════════════════════════════════════════
do $$
declare v_chunk bigint; v_prov jsonb; v_n int; v_row jsonb;
begin
  select id into v_chunk from brain.document_chunks where version_id = '33333333-0000-4000-8000-0000000000a3' and kind = 'table';
  v_prov := brain.chunk_provenance(v_chunk);
  if v_prov -> 'file' ->> 'sha256' <> repeat('41', 32) then raise exception 'RAG-A4 FALHOU: sha256 do arquivo'; end if;
  if v_prov -> 'file' ->> 'path' not like '%/' || repeat('41', 32) || '.pdf' then raise exception 'RAG-A4 FALHOU: caminho'; end if;
  if v_prov ->> 'citation' <> 'Magnojet — Catálogo Magnojet V41, p. 20' then raise exception 'RAG-A4 FALHOU: citacao = %', v_prov ->> 'citation'; end if;
  if v_prov -> 'source' ->> 'key' <> 'magnojet' or v_prov -> 'document' ->> 'slug' <> 'magnojet-catalogo' then raise exception 'RAG-A4 FALHOU: cadeia'; end if;
  raise notice ' RAG-A4) OK: chunk → pagina → ingestao → versao → documento → fonte → arquivo/sha256; citacao "%"', v_prov ->> 'citation';

  select count(*) into v_n from brain.document_pages where version_id = '33333333-0000-4000-8000-0000000000a3';
  if v_n <> 2 then raise exception 'RAG-A5 FALHOU: % paginas', v_n; end if;
  if (select text_sha256 from brain.document_pages where version_id = '33333333-0000-4000-8000-0000000000a3' and page_no = 20)
     <> encode(sha256(convert_to((select text from brain.document_pages where version_id = '33333333-0000-4000-8000-0000000000a3' and page_no = 20), 'UTF8')), 'hex') then
    raise exception 'RAG-A5 FALHOU: sha256 da pagina';
  end if;
  if (select access_level from brain.document_pages where version_id = '33333333-0000-4000-8000-0000000000b1' and page_no = 1) <> 'commercial' then
    raise exception 'RAG-A5 FALHOU: nivel da pagina nao copiado';
  end if;
  raise notice ' RAG-A5) OK: paginas ligadas a versao, sha256 do texto conferido, nivel copiado';

  if v_prov -> 'ingestion' ->> 'pipeline_version' <> 'lote-a-fixture' or v_prov -> 'page' ->> 'page_no' <> '20' then
    raise exception 'RAG-A6 FALHOU: ingestao/pagina na proveniencia';
  end if;
  if (select content_sha256 from brain.document_chunks where id = v_chunk)
     <> encode(sha256(convert_to((select content from brain.document_chunks where id = v_chunk), 'UTF8')), 'hex') then
    raise exception 'RAG-A6 FALHOU: sha256 do chunk';
  end if;
  raise notice ' RAG-A6) OK: chunk ligado a pagina 20 e a ingestao lote-a-fixture; sha256 do conteudo conferido';

  select table_data -> 'rows' -> 1 into v_row from brain.document_chunks where id = v_chunk;
  if jsonb_typeof(v_row -> 6) <> 'number' or (v_row ->> 6)::numeric <> 0.77 then raise exception 'RAG-A7 FALHOU: L/min = %', v_row -> 6; end if;
  if (v_row ->> 7)::numeric <> 77 then raise exception 'RAG-A7 FALHOU: L/ha@12 = %', v_row -> 7; end if;
  -- consulta quantitativa direta no JSONB, sem LLM
  select count(*) into v_n
    from brain.document_chunks c, jsonb_array_elements(c.table_data -> 'rows') r
   where c.kind = 'table' and c.version_id = '33333333-0000-4000-8000-0000000000a3'
     and (r ->> 6)::numeric between 0.75 and 0.85;
  if v_n <> 1 then raise exception 'RAG-A7 FALHOU: consulta quantitativa achou %', v_n; end if;
  if (select fts from brain.document_chunks where id = v_chunk) @@ to_tsquery('portuguese', 'mj981cap') is not true then
    raise exception 'RAG-A7 FALHOU: texto da tabela nao indexado';
  end if;
  raise notice ' RAG-A7) OK: tabela em JSONB numerico (0,77 L/min → 77 L/ha) e no texto pesquisavel';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A8 — chunk ↔ produto do ERP
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_preco numeric;
begin
  select count(*) into v_n from brain.chunk_products where product_id = '33333333-0000-4000-8000-0000000000e1';
  if v_n <> 2 then raise exception 'RAG-A8 FALHOU: % vinculos', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('MJ981CAP', jsonb_build_object('product_id', '33333333-0000-4000-8000-0000000000e1'));
  if v_n < 1 then raise exception 'RAG-A8 FALHOU: filtro por produto vazio'; end if;
  select sale_price into v_preco from public.products where id = '33333333-0000-4000-8000-0000000000e1';
  if v_preco <> 0 then raise exception 'RAG-A8 FALHOU: preco do ERP mudou'; end if;
  if (select count(*) from public.product_costs where product_id = '33333333-0000-4000-8000-0000000000e1') <> 0 then
    raise exception 'RAG-A8 FALHOU: custo criado no ERP';
  end if;
  raise notice ' RAG-A8) OK: 2 chunks apontam para RAGA-001; filtro por produto funciona; preco e custo do ERP intactos';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A9 / A10 / A11 — os bracos da busca (como vendedor)
-- ════════════════════════════════════════════════════════════
do $$
declare r record; v_n int;
begin
  perform set_config('request.jwt.claim.sub', '33333333-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  select * into r from brain.search_knowledge('núcleo de cerâmica') limit 1;
  if r.chunk_id is null or r.rank_fts is null or r.version_label <> 'V41' or r.page_from <> 1 then
    raise exception 'RAG-A9 FALHOU: %', to_jsonb(r);
  end if;
  raise notice ' RAG-A9) OK: FTS "núcleo de cerâmica" → V41 p. 1 (rank_fts=%)', r.rank_fts;

  select * into r from brain.search_knowledge('MJ981CAP') limit 1;
  if r.rank_exact <> 1 or r.kind <> 'table' or r.version_label <> 'V41' then raise exception 'RAG-A10 FALHOU: %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('mj 981 cap') limit 1;
  if r.rank_exact <> 1 or r.version_label <> 'V41' then raise exception 'RAG-A10 FALHOU (com espaco): %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('ad-ia') limit 1;
  if r.rank_exact <> 1 or r.access_level <> 'internal' then raise exception 'RAG-A10 FALHOU (AD-IA): %', to_jsonb(r); end if;
  raise notice ' RAG-A10) OK: codigo exato — MJ981CAP, "mj 981 cap" e AD-IA no topo (rank_exact=1)';

  select * into r from brain.search_knowledge('MJ981CAB') limit 1;   -- erro de digitacao
  if r.chunk_id is null or r.rank_trgm is null or r.codes @> '{MJ981CAP}' is not true then raise exception 'RAG-A11 FALHOU: %', to_jsonb(r); end if;
  raise notice ' RAG-A11) OK: trigram — "MJ981CAB" acha MJ981CAP (rank_trgm=%)', r.rank_trgm;

  perform set_config('role', 'none', true);
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A12 / A13 — vendedor nao ve commercial nem admin, de jeito nenhum
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_chunk_com bigint; v_chunk_adm bigint; v_prov jsonb; v_ep brain.external_processing;
begin
  reset role;
  select id into v_chunk_com from brain.document_chunks where version_id = '33333333-0000-4000-8000-0000000000b1';
  select id into v_chunk_adm from brain.document_chunks where version_id = '33333333-0000-4000-8000-0000000000e9';

  perform set_config('request.jwt.claim.sub', '33333333-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  if brain.caller_access_level() <> 'internal' then raise exception 'RAG-A12 FALHOU: nivel do vendedor = %', brain.caller_access_level(); end if;
  -- contagem direta
  select count(*) into v_n from brain.document_chunks where access_level in ('commercial', 'admin');
  if v_n <> 0 then raise exception 'RAG-A12 FALHOU: vendedor conta % chunks restritos', v_n; end if;
  select count(*) into v_n from brain.documents;
  if v_n <> 2 then raise exception 'RAG-A12 FALHOU: vendedor ve % documentos (esperava 2)', v_n; end if;
  select count(*) into v_n from brain.document_versions where access_level in ('commercial', 'admin');
  if v_n <> 0 then raise exception 'RAG-A12 FALHOU: versoes restritas visiveis'; end if;
  select count(*) into v_n from brain.document_pages where access_level in ('commercial', 'admin');
  if v_n <> 0 then raise exception 'RAG-A12 FALHOU: paginas restritas visiveis'; end if;
  select count(*) into v_n from brain.chunk_products where access_level in ('commercial', 'admin');
  if v_n <> 0 then raise exception 'RAG-A12 FALHOU: vinculo restrito visivel'; end if;
  select count(*) into v_n from brain.knowledge_ingestions where access_level in ('commercial', 'admin');
  if v_n <> 0 then raise exception 'RAG-A12 FALHOU: ingestao restrita visivel'; end if;
  raise notice ' RAG-A12) OK: vendedor (internal) conta zero linhas commercial/admin em chunks, documentos, versoes, paginas, vinculos e ingestoes';

  -- busca: T100 esta num chunk commercial e num admin; 'margem' so no admin
  select count(*) into v_n from brain.search_knowledge('T100');
  if v_n <> 0 then raise exception 'RAG-A13 FALHOU: busca "T100" devolveu % ao vendedor', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('margem ajustável');
  if v_n <> 0 then raise exception 'RAG-A13 FALHOU: busca "margem" devolveu % ao vendedor', v_n; end if;
  -- filtro por documento restrito
  select count(*) into v_n from brain.search_knowledge('T100', jsonb_build_object('document_id', '33333333-0000-4000-8000-0000000000d2'));
  if v_n <> 0 then raise exception 'RAG-A13 FALHOU: filtro por documento restrito vazou'; end if;
  -- filtro por produto: o produto liga um chunk publico e um commercial — so o publico volta
  select count(*) into v_n from brain.search_knowledge('MJ981CAP T100', jsonb_build_object('product_id', '33333333-0000-4000-8000-0000000000e1'));
  if v_n <> 1 then raise exception 'RAG-A13 FALHOU: filtro por produto devolveu % (esperava so o publico)', v_n; end if;
  if exists (select 1 from brain.search_knowledge('MJ981CAP T100', jsonb_build_object('product_id', '33333333-0000-4000-8000-0000000000e1')) where access_level <> 'public') then
    raise exception 'RAG-A13 FALHOU: chunk restrito no filtro por produto';
  end if;
  -- proveniencia e funcoes auxiliares: NULL, nao "existe mas nao posso"
  v_prov := brain.chunk_provenance(v_chunk_com);
  if v_prov is not null then raise exception 'RAG-A13 FALHOU: proveniencia de chunk commercial vazou'; end if;
  v_prov := brain.chunk_provenance(v_chunk_adm);
  if v_prov is not null then raise exception 'RAG-A13 FALHOU: proveniencia de chunk admin vazou'; end if;
  v_ep := brain.external_processing_for('33333333-0000-4000-8000-0000000000d4');
  if v_ep is not null then raise exception 'RAG-A13 FALHOU: politica do documento admin vazou'; end if;
  if brain.current_version('33333333-0000-4000-8000-0000000000d2') is not null then raise exception 'RAG-A13 FALHOU: current_version vazou'; end if;
  -- escrita: nada
  begin
    insert into brain.documents (source_key, slug, title, document_type, access_level) values ('magnojet', 'x-vend', 'x', 'other', 'public');
    raise exception 'RAG-A13 FALHOU: vendedor inseriu documento';
  exception when insufficient_privilege then null; end;
  update brain.documents set title = 'alterado' where id = '33333333-0000-4000-8000-0000000000d1';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'RAG-A13 FALHOU: vendedor atualizou documento'; end if;
  delete from brain.document_chunks where version_id = '33333333-0000-4000-8000-0000000000a3';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'RAG-A13 FALHOU: vendedor apagou chunk'; end if;
  raise notice ' RAG-A13) OK: nem busca, filtro por documento/produto, proveniencia, politica externa ou current_version revelam commercial/admin; vendedor nao escreve';

  perform set_config('role', 'none', true);
  reset role;

  -- E o administrador ve o que e dele.
  perform set_config('request.jwt.claim.sub', '33333333-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  if brain.caller_access_level() <> 'admin' then raise exception 'RAG-A13 FALHOU: nivel do admin'; end if;
  select count(*) into v_n from brain.search_knowledge('T100');
  if v_n <> 2 then raise exception 'RAG-A13 FALHOU: admin viu % para T100 (esperava 2)', v_n; end if;
  if brain.chunk_provenance(v_chunk_com) -> 'document' ->> 'access_level' <> 'commercial' then raise exception 'RAG-A13 FALHOU: proveniencia para admin'; end if;
  perform set_config('role', 'none', true);
  reset role;
  raise notice ' RAG-A13b) OK: administrador ve os 2 chunks T100 (commercial e admin) e a proveniencia commercial';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A14 — vigencia
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; r record;
begin
  perform set_config('request.jwt.claim.sub', '33333333-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from brain.search_knowledge('MJ981CAP');
  if v_n <> 1 then raise exception 'RAG-A14 FALHOU: padrao devolveu % (esperava so V41)', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('MJ981CAP', '{}', 10, true);
  if v_n <> 2 then raise exception 'RAG-A14 FALHOU: com historico devolveu % (esperava V40+V41)', v_n; end if;
  select * into r from brain.search_knowledge('MJ981CAP', jsonb_build_object('version_label', 'V40'), 10, true) limit 1;
  if r.version_label <> 'V40' or r.version_status <> 'superseded' or r.page_from <> 19 then raise exception 'RAG-A14 FALHOU: V40 pedida: %', to_jsonb(r); end if;
  -- withdrawn nunca, nem pedindo
  select count(*) into v_n from brain.search_knowledge('MJ981CAP', jsonb_build_object('version_id', '33333333-0000-4000-8000-0000000000a1'), 10, true);
  if v_n <> 0 then raise exception 'RAG-A14 FALHOU: withdrawn apareceu'; end if;
  perform set_config('role', 'none', true);
  reset role;
  raise notice ' RAG-A14) OK: padrao = so V41 (0,77 L/min); historico so quando pedido (V40 = 0,75); withdrawn nunca';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A15 — reclassificacao em cascata e processamento externo
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int;
begin
  reset role;
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d1') <> 'allowed' then raise exception 'RAG-A15 FALHOU: public'; end if;
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d3') <> 'approved_provider_only' then raise exception 'RAG-A15 FALHOU: internal'; end if;
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d2') <> 'forbidden' then raise exception 'RAG-A15 FALHOU: commercial default'; end if;
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d4') <> 'forbidden' then raise exception 'RAG-A15 FALHOU: admin'; end if;
  -- opt-in commercial com aprovador registrado
  update brain.documents set external_processing_override = 'allowed', approved_by = '33333333-0000-4000-8000-000000000001', approved_at = now()
   where id = '33333333-0000-4000-8000-0000000000d2';
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d2') <> 'allowed' then raise exception 'RAG-A15 FALHOU: opt-in commercial'; end if;
  -- admin nunca, mesmo com opt-in
  update brain.documents set external_processing_override = 'allowed', approved_by = '33333333-0000-4000-8000-000000000001', approved_at = now()
   where id = '33333333-0000-4000-8000-0000000000d4';
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d4') <> 'forbidden' then raise exception 'RAG-A15 FALHOU: admin com opt-in'; end if;
  -- internal nao sobe alem de provedor aprovado
  update brain.documents set external_processing_override = 'allowed', approved_by = '33333333-0000-4000-8000-000000000001', approved_at = now()
   where id = '33333333-0000-4000-8000-0000000000d3';
  if brain.external_processing_for('33333333-0000-4000-8000-0000000000d3') <> 'approved_provider_only' then raise exception 'RAG-A15 FALHOU: internal subiu'; end if;

  -- Reclassificar o procedimento para commercial: a cadeia inteira acompanha.
  update brain.documents set access_level = 'commercial' where id = '33333333-0000-4000-8000-0000000000d3';
  select count(*) into v_n from (
    select access_level from brain.document_versions where document_id = '33333333-0000-4000-8000-0000000000d3'
    union all select access_level from brain.knowledge_ingestions where version_id = '33333333-0000-4000-8000-0000000000c1'
    union all select access_level from brain.document_pages where version_id = '33333333-0000-4000-8000-0000000000c1'
    union all select access_level from brain.document_chunks where version_id = '33333333-0000-4000-8000-0000000000c1') t
   where access_level <> 'commercial';
  if v_n <> 0 then raise exception 'RAG-A15 FALHOU: % linhas nao acompanharam a reclassificacao', v_n; end if;
  -- e o vendedor deixa de ver
  perform set_config('request.jwt.claim.sub', '33333333-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from brain.search_knowledge('ad-ia');
  perform set_config('role', 'none', true);
  reset role;
  if v_n <> 0 then raise exception 'RAG-A15 FALHOU: vendedor ainda ve o documento reclassificado'; end if;
  update brain.documents set access_level = 'internal' where id = '33333333-0000-4000-8000-0000000000d3';
  raise notice ' RAG-A15) OK: politica externa por nivel (public allowed / internal so aprovado / commercial opt-in com aprovador / admin nunca); reclassificar desce a cadeia inteira';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-A16 — anon
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from brain.document_chunks;
    raise exception 'RAG-A16 FALHOU: anon leu chunks';
  exception when insufficient_privilege then null; end;
  begin
    select count(*) into v_n from brain.search_knowledge('MJ981CAP');
    raise exception 'RAG-A16 FALHOU: anon buscou';
  exception when insufficient_privilege then null; end;
  perform set_config('role', 'none', true);
  reset role;
  raise notice ' RAG-A16) OK: anon nao le nem busca';
end
$$;

reset role;

-- Limpeza: so o que esta suite criou. audit_log e append-only por projeto.
delete from brain.documents where id in ('33333333-0000-4000-8000-0000000000d1','33333333-0000-4000-8000-0000000000d2','33333333-0000-4000-8000-0000000000d3','33333333-0000-4000-8000-0000000000d4');
delete from brain.knowledge_sources where key in ('magnojet', 'dji', 'agrotork');
delete from public.products where id = '33333333-0000-4000-8000-0000000000e1';
delete from auth.users where id in ('33333333-0000-4000-8000-000000000001','33333333-0000-4000-8000-000000000002');
