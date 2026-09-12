-- ============================================================
-- 35 · BRAIN Fase 2, Lote B — ingestão sem vetores (API SQL + porta do app)
-- ============================================================
-- O worker (brain/worker) só chama estas funções; aqui elas são exercidas
-- direto em SQL, com o MESMO conteúdo sintético que o worker produz para o
-- "catálogo Pontas Sol" (tests/fixtures.py): p.2 é a tabela técnica no
-- formato da p. 20 do Magnojet V41. Nenhum documento real.
--
--   B1   sha256: minúsculo, 64 hex; caminho canônico termina no sha
--   B2   mesmo arquivo (sha) → mesma versão; rótulo diferente não duplica
--   B3   arquivo diferente → versão nova (draft); mesmo rótulo é recusado
--   B4   página mantém o número; reenvio na mesma ingestão substitui; de outra, não
--   B5   chunk sem página registrada é recusado; chunk aponta para página existente
--   B6   chunking determinístico: reprocessar (p_replace) reproduz (ordinal, sha) idênticos
--   B7   tabela técnica: JSONB numérico + texto pesquisável; texto com table_data recusado
--   B8   códigos normalizados pelo gatilho
--   B9   pipeline_version obrigatório e registrado; parser, executor, tempos
--   B10  falha: status/erro coerentes; completed sem página recusado; fechar duas vezes recusado
--   B11  commercial não sai para provedor externo sem opt-in
--   B12  admin nunca
--   B13  internal só provedor aprovado
--   B14  busca acha o recém-ingerido (exato, FTS, trigram) — só depois de ativar
--   B15  proveniência completa, citação com página
--   B16  versão antiga permanece histórica (superseded, buscável só sob pedido)
--   B17  withdrawn não aparece
--   B18  RLS: vendedor não vê ingestão/página/chunk commercial; não ingere; trilha de consulta é dele
--   B19  worker não escreve no ERP; conteúdo repetido em páginas diferentes é aceito
--   B20  zero pgvector; nenhuma função nova é security definer; anon sem EXECUTE
--   BG   golden dataset (perguntas 1, 2, 5, 12, 13, 14) sobre o sintético
--
-- Prefixo de UUID = 35. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('35353535-0000-4000-8000-000000000001','ing.admin@teste.local', '{"full_name":"Admin Ingestao"}'),
 ('35353535-0000-4000-8000-000000000002','ing.vend@teste.local',  '{"full_name":"Vendedor Ingestao"}');
update public.profiles set role = 'admin' where id = '35353535-0000-4000-8000-000000000001';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('sol',      'Pontas Sol (sintetico)',   'manufacturer', 'public',     'allowed'),
 ('sol_rev',  'Sol revenda (sintetico)',  'distributor',  'commercial', 'forbidden'),
 ('sol_int',  'Sol interno (sintetico)',  'internal',     'internal',   'approved_provider_only'),
 ('sol_adm',  'Sol diretoria (sintetico)','internal',     'admin',      'forbidden');

insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('35353535-0000-4000-8000-0000000000d1', 'sol',     'sol-catalogo',  'Catálogo Sol',        'catalog',       'public'),
 ('35353535-0000-4000-8000-0000000000d2', 'sol_rev', 'sol-tabela',    'Tabela Sol revenda',  'price_list',    'commercial'),
 ('35353535-0000-4000-8000-0000000000d3', 'sol_int', 'sol-manual',    'Manual Sol interno',  'manual',        'internal'),
 ('35353535-0000-4000-8000-0000000000d4', 'sol_adm', 'sol-margem',    'Margem Sol 2026',     'internal_note', 'admin');

-- Uma "ingestao" inteira do catalogo, como o worker faria. Reutilizada em varios testes.
create or replace function pg_temp.ingerir_catalogo(p_label text, p_sha text, p_replace boolean default false)
returns table (version_id uuid, ingestion_id uuid) language plpgsql as $$
declare v uuid; i uuid;
begin
  v := brain.register_version('35353535-0000-4000-8000-0000000000d1', p_label, p_sha, 'catalogo_sintetico.pdf', 'application/pdf', 3983, '2026-06-01', 3);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.1', 'suite-35', false, 3, p_replace);
  perform brain.ingestion_add_page(i, 1, 'PONTAS SOL INSTITUCIONAL Fundada em 1985, a Pontas Sol desenvolve pontas de pulverização com núcleo de cerâmica.', 'text_layer');
  perform brain.ingestion_add_page(i, 2, 'PONTAS SOL ULTRA GROSSA CONE VAZIO Aplicações de herbicidas sistêmicos. MALHA 50.', 'text_layer');
  perform brain.ingestion_add_page(i, 3, 'CAPÍTULO 3 CALIBRAÇÃO A ponta deve ser escolhida conforme a calda.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1, 'Fundada em 1985, a Pontas Sol desenvolve pontas de pulverização com núcleo de cerâmica, elevando os padrões de precisão e durabilidade.', '{"PONTAS SOL","INSTITUCIONAL"}');
  perform brain.ingestion_add_chunk(i, 1, 'text', 2, 2, 'Aplicações de herbicidas sistêmicos em pré e pós-emergência. MALHA 50. Espaçamento entre bicos de 50 cm.', '{"PONTAS SOL","PONTAS","SOL ULTRA GROSSA CONE VAZIO"}');
  perform brain.ingestion_add_chunk(i, 2, 'table', 2, 2,
    E'Código Série Gotas Pressão (bar) Pressão (psi) Vazão (L/min) L/ha a 12 km/h\\nPS981CAP SOL-CV 02 UG 2,07 bar 30 psi 0,66 L/min 66 L/ha\\nPS981CAP SOL-CV 02 UG 2,76 bar 40 psi 0,77 L/min 77 L/ha\\nPS982CAP SOL-CV 025 UG 2,07 bar 30 psi 0,83 L/min 83 L/ha\\nPS983CAP SOL-CV 03 UG 2,76 bar 40 psi 1,15 L/min 115 L/ha',
    '{"PONTAS SOL","PONTAS","SOL ULTRA GROSSA CONE VAZIO"}',
    jsonb_build_object('page', 2,
      'headers', jsonb_build_array('Codigo','Serie','Gotas','Pressao_bar','Pressao_psi','Vazao_L/min','L/ha_a_12_km/h'),
      'labels',  jsonb_build_array('Código','Série','Gotas','Pressão (bar)','Pressão (psi)','Vazão (L/min)','L/ha a 12 km/h'),
      'units',   jsonb_build_object('Pressao_bar','bar','Pressao_psi','psi','Vazao_L/min','L/min','L/ha_a_12_km/h','L/ha'),
      'rows',    jsonb_build_array(
                   jsonb_build_array('PS981CAP','SOL-CV 02','UG',2.07,30,0.66,66),
                   jsonb_build_array('PS981CAP','SOL-CV 02','UG',2.76,40,0.77,77),
                   jsonb_build_array('PS982CAP','SOL-CV 025','UG',2.07,30,0.83,83),
                   jsonb_build_array('PS983CAP','SOL-CV 03','UG',2.76,40,1.15,115)),
      'notes', jsonb_build_array()),
    '{"ps981cap","PS982CAP","ps 983 cap","SOL-CV 02"}');
  perform brain.ingestion_add_chunk(i, 3, 'text', 3, 3, 'A ponta de pulverização deve ser escolhida conforme a calda, a pressão de trabalho e o alvo. A vazão nominal é medida a 3 bar e a 40 psi.', '{"PONTAS SOL","CAPÍTULO 3 CALIBRAÇÃO"}');
  perform brain.ingestion_finish(i, 'completed', null, '[]'::jsonb, jsonb_build_object('extract_ms', 12, 'chunk_ms', 1));
  return query select v, i;
end $$;

-- ════════════════════════════════════════════════════════════
-- B1 / B2 / B3 — versao por checksum
-- ════════════════════════════════════════════════════════════
do $$
declare v1 uuid; v1b uuid; v2 uuid; r record; v_ok int := 0;
begin
  reset role;
  v1 := brain.register_version('35353535-0000-4000-8000-0000000000d1', 'V1', upper(repeat('a1', 32)), 'CATALOGO SOL V1.pdf', 'application/pdf', 3983, '2026-06-01', 3);
  select * into r from brain.document_versions where id = v1;
  if r.file_sha256 <> repeat('a1', 32) then raise exception 'B1 FALHOU: sha nao normalizado: %', r.file_sha256; end if;
  if r.storage_path <> 'sol/sol-catalogo/V1/' || repeat('a1', 32) || '.pdf' then raise exception 'B1 FALHOU: caminho = %', r.storage_path; end if;
  if r.status <> 'draft' or r.storage_bucket <> 'brain-documents' or r.page_count <> 3 then raise exception 'B1 FALHOU: %', to_jsonb(r); end if;
  begin perform brain.register_version('35353535-0000-4000-8000-0000000000d1', 'Vx', 'nao-e-sha', 'x.pdf', 'application/pdf', 1); raise exception 'x';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin perform brain.register_version('35353535-0000-4000-8000-0000000000d1', 'Vx', repeat('b2', 32), 'x.pdf', 'application/pdf', 0); raise exception 'x';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin perform brain.register_version('35353535-0000-4000-8000-0000000000dd', 'Vx', repeat('b2', 32), 'x.pdf', 'application/pdf', 1); raise exception 'x';
  exception when no_data_found then v_ok := v_ok + 1; end;
  if v_ok <> 3 then raise exception 'B1 FALHOU: % de 3 recusas', v_ok; end if;
  raise notice ' B1) OK: sha256 normalizado (64 hex minusculo), caminho sol/sol-catalogo/V1/<sha>.pdf, draft; sha invalido, tamanho 0 e documento inexistente recusados';

  -- B2: mesmo arquivo → mesma versao, com qualquer rotulo
  v1b := brain.register_version('35353535-0000-4000-8000-0000000000d1', 'V1', repeat('a1', 32), 'CATALOGO SOL V1.pdf', 'application/pdf', 3983);
  if v1b <> v1 then raise exception 'B2 FALHOU: mesmo sha criou outra versao'; end if;
  v1b := brain.register_version('35353535-0000-4000-8000-0000000000d1', 'V1-copia', repeat('a1', 32), 'outro-nome.pdf', 'application/pdf', 3983);
  if v1b <> v1 then raise exception 'B2 FALHOU: mesmo sha com outro rotulo criou outra versao'; end if;
  if (select count(*) from brain.document_versions where document_id = '35353535-0000-4000-8000-0000000000d1') <> 1 then raise exception 'B2 FALHOU: contagem'; end if;
  raise notice ' B2) OK: o mesmo sha256 devolve a mesma versao, com o mesmo rotulo ou outro; nada duplica';

  -- B3: arquivo diferente → versao nova; mesmo rotulo com arquivo diferente → recusado
  v2 := brain.register_version('35353535-0000-4000-8000-0000000000d1', 'V2', repeat('a2', 32), 'CATALOGO SOL V2.pdf', 'application/pdf', 4100);
  if v2 = v1 then raise exception 'B3 FALHOU: arquivo diferente nao criou versao'; end if;
  begin
    perform brain.register_version('35353535-0000-4000-8000-0000000000d1', 'V2', repeat('a3', 32), 'CATALOGO SOL V2b.pdf', 'application/pdf', 4200);
    raise exception 'B3 FALHOU: mesmo rotulo aceitou arquivo diferente';
  exception when unique_violation then null; end;
  if (select count(*) from brain.document_versions where document_id = '35353535-0000-4000-8000-0000000000d1') <> 2 then raise exception 'B3 FALHOU: contagem'; end if;
  delete from brain.document_versions where id in (v1, v2);
  raise notice ' B3) OK: arquivo diferente cria versao nova (draft); rotulo repetido com arquivo diferente e recusado';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B4 / B5 / B7 / B8 / B9 — paginas, chunks, tabela, codigos, metadados
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; i uuid; i2 uuid; r record; v_ok int := 0; n int;
begin
  reset role;
  select * into r from pg_temp.ingerir_catalogo('V1', repeat('c1', 32));
  v := r.version_id; i := r.ingestion_id;

  -- B9: metadados da ingestao
  select * into r from brain.knowledge_ingestions where id = i;
  if r.status <> 'completed' or r.pipeline_version <> 'lote-b.1' or r.parser <> 'pdfplumber 0.11.9' or r.method <> 'pdf_text' or r.executor <> 'suite-35'
     or r.pages_total <> 3 or r.pages_done <> 3 or r.chunks_created <> 4 or r.tables_created <> 1
     or r.started_at is null or r.finished_at is null or r.finished_at < r.started_at or (r.metrics ->> 'extract_ms')::int <> 12 then
    raise exception 'B9 FALHOU: %', to_jsonb(r);
  end if;
  begin perform brain.ingestion_start(v, 'pdf_text', 'x', '   ', null, false, 3, true); raise exception 'x';
  exception when invalid_parameter_value then null; end;
  raise notice ' B9) OK: pipeline_version/parser/metodo/executor/inicio/fim/metricas registrados; contagens saem das tabelas (3 paginas, 4 chunks, 1 tabela); pipeline_version vazio recusado';

  -- B4: pagina mantem numero; reenvio na mesma ingestao substitui; ingestao fechada nao aceita
  if (select string_agg(page_no::text, ',' order by page_no) from brain.document_pages where version_id = v) <> '1,2,3' then raise exception 'B4 FALHOU: numeros'; end if;
  begin perform brain.ingestion_add_page(i, 2, 'novo texto', 'text_layer'); raise exception 'B4 FALHOU: ingestao fechada aceitou pagina';
  exception when object_not_in_prerequisite_state then null; end;
  -- numa ingestao aberta (replace): reenvio substitui o texto e o sha
  i2 := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.1', 'suite-35', false, 3, true);
  perform brain.ingestion_add_page(i2, 2, 'texto A', 'text_layer');
  perform brain.ingestion_add_page(i2, 2, 'texto B', 'text_layer');
  select * into r from brain.document_pages where version_id = v and page_no = 2;
  if r.text <> 'texto B' or r.text_sha256 <> encode(sha256(convert_to('texto B', 'UTF8')), 'hex') or r.ingestion_id <> i2 then raise exception 'B4 FALHOU: reenvio: %', to_jsonb(r); end if;
  if (select count(*) from brain.document_pages where version_id = v) <> 1 then raise exception 'B4 FALHOU: replace nao limpou as paginas antigas'; end if;
  raise notice ' B4) OK: paginas 1,2,3 com o numero certo; reenvio na mesma ingestao substitui texto e sha; ingestao fechada recusa; replace limpa o anterior';

  -- B5: chunk sem pagina registrada e recusado
  begin perform brain.ingestion_add_chunk(i2, 0, 'text', 7, 7, 'sem pagina'); raise exception 'B5 FALHOU: chunk sem pagina aceito';
  exception when foreign_key_violation then null; end;
  perform brain.ingestion_add_chunk(i2, 0, 'text', 2, 2, 'com pagina');
  if not exists (select 1 from brain.document_chunks c join brain.document_pages p on p.version_id = c.version_id and p.page_no = c.page_from where c.ingestion_id = i2) then
    raise exception 'B5 FALHOU: chunk nao aponta para pagina';
  end if;
  perform brain.ingestion_fail(i2, 'suite-35: ingestao de teste abandonada');
  raise notice ' B5) OK: chunk em pagina nao registrada e recusado; chunk aceito aponta para pagina existente da mesma versao';

  -- Reingere de verdade para os proximos testes.
  select * into r from pg_temp.ingerir_catalogo('V1', repeat('c1', 32), true);
  v := r.version_id; i := r.ingestion_id;

  -- B7: tabela tecnica
  select * into r from brain.document_chunks where version_id = v and kind = 'table';
  if jsonb_typeof(r.table_data -> 'rows' -> 1 -> 5) <> 'number' or (r.table_data -> 'rows' -> 1 ->> 5)::numeric <> 0.77
     or (r.table_data -> 'rows' -> 1 ->> 6)::numeric <> 77 or r.table_data -> 'units' ->> 'Vazao_L/min' <> 'L/min' then
    raise exception 'B7 FALHOU: table_data: %', r.table_data;
  end if;
  if r.content !~ '0,77 L/min 77 L/ha' then raise exception 'B7 FALHOU: texto da tabela'; end if;
  begin perform brain.ingestion_add_chunk(i, 9, 'text', 2, 2, 'texto com tabela', '{}', '{"headers":["a"],"rows":[]}'::jsonb); raise exception 'x';
  exception when check_violation then v_ok := v_ok + 1; when object_not_in_prerequisite_state then v_ok := v_ok + 1; end;
  -- consulta quantitativa sobre o JSONB: qual linha entrega 0,77 L/min?
  select count(*) into n from brain.document_chunks c, jsonb_array_elements(c.table_data -> 'rows') row
   where c.version_id = v and c.kind = 'table' and (row ->> 5)::numeric = 0.77 and row ->> 0 = 'PS981CAP';
  if n <> 1 then raise exception 'B7 FALHOU: consulta quantitativa achou %', n; end if;
  raise notice ' B7) OK: table_data com numeros numericos (0,77 L/min → 77 L/ha), unidades, texto pesquisavel; consulta quantitativa por JSONB; texto com table_data recusado';

  -- B8: codigos normalizados
  if r.codes <> array['PS981CAP','PS982CAP','PS983CAP','SOL-CV02'] then raise exception 'B8 FALHOU: codes = %', r.codes; end if;
  raise notice ' B8) OK: codes normalizados e ordenados pelo gatilho: %', r.codes;
end
$$;

-- ════════════════════════════════════════════════════════════
-- B6 — determinismo (reprocessar reproduz)
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; r record; antes text; depois text; n_ing int; n_rep int;
begin
  reset role;
  select v2.id into v from brain.document_versions v2 where v2.file_sha256 = repeat('c1', 32);
  select string_agg(ordinal || ':' || content_sha256 || ':' || kind || ':' || page_from, '|' order by ordinal) into antes from brain.document_chunks where version_id = v;
  select * into r from pg_temp.ingerir_catalogo('V1', repeat('c1', 32), true);
  select string_agg(ordinal || ':' || content_sha256 || ':' || kind || ':' || page_from, '|' order by ordinal) into depois from brain.document_chunks where version_id = v;
  if antes <> depois then raise exception 'B6 FALHOU: reprocessar mudou os chunks'; end if;
  select count(*), count(*) filter (where metadata ? 'replaced_by') into n_ing, n_rep from brain.knowledge_ingestions where version_id = v;
  if n_rep < 1 or n_ing < 2 then raise exception 'B6 FALHOU: historico de ingestoes: % / %', n_ing, n_rep; end if;
  -- sem p_replace, versao com conteudo e recusada
  begin perform brain.ingestion_start(v, 'pdf_text', 'x', 'lote-b.1', null, false, 3, false); raise exception 'B6 FALHOU: reprocessou sem replace';
  exception when unique_violation then null; end;
  raise notice ' B6) OK: reprocessar com p_replace reproduz (ordinal, sha256, kind, pagina) identicos; ingestoes anteriores viram historico (replaced_by); sem replace e recusado';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B10 — falhas coerentes
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; i uuid; r record; v_ok int := 0;
begin
  reset role;
  v := brain.register_version('35353535-0000-4000-8000-0000000000d3', '2024-10', repeat('d3', 32), 'manual.pdf', 'application/pdf', 1000, null, 2);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber', 'lote-b.1', 'suite-35', false, 2);
  -- completed sem pagina: recusado
  begin perform brain.ingestion_finish(i, 'completed'); raise exception 'x';
  exception when check_violation then v_ok := v_ok + 1; end;
  -- failed sem erro: recusado
  begin perform brain.ingestion_finish(i, 'failed', ''); raise exception 'x';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  -- 1 de 2 paginas como completed: recusado; como partial: aceito
  perform brain.ingestion_add_page(i, 1, 'so a primeira', 'text_layer');
  begin perform brain.ingestion_finish(i, 'completed'); raise exception 'x';
  exception when check_violation then v_ok := v_ok + 1; end;
  select * into r from brain.ingestion_finish(i, 'partial', null, '["pagina 2 sem texto"]'::jsonb);
  if r.status <> 'partial' or r.pages_done <> 1 or r.pages_total <> 2 or r.warnings -> 0 #>> '{}' <> 'pagina 2 sem texto' then raise exception 'B10 FALHOU: partial: %', to_jsonb(r); end if;
  -- fechar duas vezes: recusado
  begin perform brain.ingestion_finish(i, 'completed'); raise exception 'x';
  exception when object_not_in_prerequisite_state then v_ok := v_ok + 1; end;
  -- duas ingestoes abertas na mesma versao: recusado
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber', 'lote-b.1', 'suite-35', false, 2, true);
  begin perform brain.ingestion_start(v, 'pdf_text', 'pdfplumber', 'lote-b.1', 'suite-35', false, 2, true); raise exception 'x';
  exception when object_in_use then v_ok := v_ok + 1; end;
  select * into r from brain.ingestion_fail(i, 'suite-35: parser explodiu na pagina 2');
  if r.status <> 'failed' or r.error !~ 'explodiu' or r.finished_at is null then raise exception 'B10 FALHOU: fail: %', to_jsonb(r); end if;
  if v_ok <> 5 then raise exception 'B10 FALHOU: % de 5 recusas', v_ok; end if;
  raise notice ' B10) OK: completed sem pagina, failed sem erro, completed com 1/2 paginas, fechar duas vezes e duas ingestoes abertas recusados; partial e failed com erro coerentes';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B11 / B12 / B13 — processamento externo (a resposta que o worker consulta)
-- ════════════════════════════════════════════════════════════
do $$
begin
  reset role;
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d2') <> 'forbidden' then raise exception 'B11 FALHOU'; end if;
  update brain.documents set external_processing_override = 'approved_provider_only', approved_by = '35353535-0000-4000-8000-000000000001', approved_at = now() where id = '35353535-0000-4000-8000-0000000000d2';
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d2') <> 'approved_provider_only' then raise exception 'B11 FALHOU: opt-in parcial'; end if;
  update brain.documents set external_processing_override = null, approved_by = null, approved_at = null where id = '35353535-0000-4000-8000-0000000000d2';
  raise notice ' B11) OK: commercial e forbidden por padrao; so com opt-in registrado abre (e so ate onde o opt-in diz)';
  update brain.documents set external_processing_override = 'allowed', approved_by = '35353535-0000-4000-8000-000000000001', approved_at = now() where id = '35353535-0000-4000-8000-0000000000d4';
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d4') <> 'forbidden' then raise exception 'B12 FALHOU'; end if;
  raise notice ' B12) OK: admin e forbidden mesmo com override allowed';
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d3') <> 'approved_provider_only' then raise exception 'B13 FALHOU'; end if;
  update brain.knowledge_sources set external_processing = 'allowed' where key = 'sol_int';
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d3') <> 'approved_provider_only' then raise exception 'B13 FALHOU: fonte allowed abriu internal'; end if;
  if brain.external_processing_for('35353535-0000-4000-8000-0000000000d1') <> 'allowed' then raise exception 'B13 FALHOU: public'; end if;
  raise notice ' B13) OK: internal fica em approved_provider_only mesmo com a fonte em allowed; public e allowed';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B14 / B15 / B16 / B17 — busca, proveniencia, historico
-- ════════════════════════════════════════════════════════════
do $$
declare v1 uuid; v2 uuid; r record; n int; prov jsonb;
begin
  reset role;
  select id into v1 from brain.document_versions where file_sha256 = repeat('c1', 32);
  -- draft: nada aparece, mesmo para o administrador
  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.search_knowledge('PS981CAP');
  if n <> 0 then raise exception 'B14 FALHOU: draft apareceu'; end if;
  perform set_config('role', 'none', true); reset role;

  update brain.document_versions set status = 'active', valid_from = '2026-06-01' where id = v1;

  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select * into r from brain.search_knowledge('PS981CAP') limit 1;
  if r.chunk_id is null or r.rank_exact <> 1 or r.kind <> 'table' or r.page_from <> 2 then raise exception 'B14 FALHOU: exato: %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('ps 981 cap') limit 1;
  if r.rank_exact <> 1 then raise exception 'B14 FALHOU: com espaco'; end if;
  select * into r from brain.search_knowledge('núcleo de cerâmica') limit 1;
  if r.page_from <> 1 or r.rank_fts is null then raise exception 'B14 FALHOU: fts: %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('PS981CAB') limit 1;
  if r.rank_trgm is null or r.codes @> '{PS981CAP}' is not true then raise exception 'B14 FALHOU: trigram: %', to_jsonb(r); end if;
  raise notice ' B14) OK: so depois de ativar; exato (PS981CAP, "ps 981 cap"), FTS (nucleo de ceramica → p.1) e trigram (PS981CAB) acham o recem-ingerido';

  -- B15: proveniencia completa
  select * into r from brain.search_knowledge('PS981CAP') limit 1;
  prov := brain.chunk_provenance(r.chunk_id);
  if prov ->> 'citation' <> 'Pontas Sol (sintetico) — Catálogo Sol V1, p. 2' then raise exception 'B15 FALHOU: citacao = %', prov ->> 'citation'; end if;
  if prov -> 'file' ->> 'sha256' <> repeat('c1', 32) or prov -> 'file' ->> 'path' !~ ('/' || repeat('c1', 32) || '\.pdf$') then raise exception 'B15 FALHOU: arquivo'; end if;
  if prov -> 'ingestion' ->> 'pipeline_version' <> 'lote-b.1' or prov -> 'page' ->> 'extraction' <> 'text_layer' or (prov -> 'page' ->> 'page_no')::int <> 2 then raise exception 'B15 FALHOU: ingestao/pagina'; end if;
  if prov -> 'source' ->> 'key' <> 'sol' or prov -> 'document' ->> 'slug' <> 'sol-catalogo' or prov -> 'version' ->> 'label' <> 'V1' then raise exception 'B15 FALHOU: cadeia'; end if;
  raise notice ' B15) OK: proveniencia chunk → p.2 → ingestao lote-b.1 → V1 → sol-catalogo → sol → arquivo/sha256; citacao "%"', prov ->> 'citation';
  perform set_config('role', 'none', true); reset role;

  -- B16: V2 ativa supersede V1; V1 vira historico
  select * into r from pg_temp.ingerir_catalogo('V2', repeat('c2', 32));
  v2 := r.version_id;
  update brain.document_versions set status = 'active', valid_from = '2026-09-01' where id = v2;
  if (select status from brain.document_versions where id = v1) <> 'superseded' then raise exception 'B16 FALHOU: V1 nao superseded'; end if;
  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.search_knowledge('PS981CAP'); if n <> 1 then raise exception 'B16 FALHOU: padrao devolveu %', n; end if;
  select version_label into r from brain.search_knowledge('PS981CAP') limit 1; if r.version_label <> 'V2' then raise exception 'B16 FALHOU: padrao nao e V2'; end if;
  select count(*) into n from brain.search_knowledge('PS981CAP', '{}', 10, true); if n <> 2 then raise exception 'B16 FALHOU: historico devolveu %', n; end if;
  select count(*) into n from brain.search_knowledge('PS981CAP', jsonb_build_object('version_label', 'V1'), 10, true); if n <> 1 then raise exception 'B16 FALHOU: V1 pedida'; end if;
  perform set_config('role', 'none', true); reset role;
  raise notice ' B16) OK: V2 ativa supersede V1; padrao devolve so V2; V1 continua buscavel sob pedido (historico/version_label)';

  -- B17: withdrawn nunca
  update brain.document_versions set status = 'withdrawn' where id = v1;
  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.search_knowledge('PS981CAP', jsonb_build_object('version_id', v1), 10, true);
  perform set_config('role', 'none', true); reset role;
  if n <> 0 then raise exception 'B17 FALHOU: withdrawn apareceu'; end if;
  raise notice ' B17) OK: withdrawn nao aparece nem pedindo pelo id';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B18 — RLS na ingestao e na porta do app
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; i uuid; r record; n int; v_ok int := 0; v_chunk bigint;
begin
  reset role;
  -- conteudo commercial ingerido pelo banco
  v := brain.register_version('35353535-0000-4000-8000-0000000000d2', '2026-09', repeat('e2', 32), 'tabela.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 9000, null, 1);
  i := brain.ingestion_start(v, 'xlsx', 'openpyxl 3.1.5', 'lote-b.1', 'suite-35', false, 1);
  perform brain.ingestion_add_page(i, 1, '', 'spreadsheet');
  perform brain.ingestion_add_chunk(i, 0, 'price_table', 1, 1, 'DRONE SOL S100 + 3 BAT + CARREGADOR C12000 165500 161900 225000 ZQXSEGREDO', '{}',
    '{"headers":["Item","Faturado_R","A_vista_R"],"units":{"Faturado_R":"BRL"},"rows":[["DRONE SOL S100",165500,161900]]}'::jsonb, '{"S100","C12000","ZQXSEGREDO"}');
  perform brain.ingestion_finish(i, 'completed');
  update brain.document_versions set status = 'active', valid_from = current_date where id = v;
  select id into v_chunk from brain.document_chunks where version_id = v;

  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.knowledge_ingestions where id = i; if n <> 0 then raise exception 'B18 FALHOU: ingestao commercial visivel'; end if;
  select count(*) into n from brain.document_pages where version_id = v; if n <> 0 then raise exception 'B18 FALHOU: pagina commercial visivel'; end if;
  select count(*) into n from public.brain_search('ZQXSEGREDO'); if n <> 0 then raise exception 'B18 FALHOU: brain_search vazou'; end if;
  select count(*) into n from public.brain_search('S100'); if n <> 0 then raise exception 'B18 FALHOU: brain_search vazou por codigo'; end if;
  if public.brain_provenance(v_chunk) is not null then raise exception 'B18 FALHOU: brain_provenance vazou'; end if;
  -- vendedor nao ingere (RLS de insert e admin)
  begin perform brain.register_version('35353535-0000-4000-8000-0000000000d1', 'Vv', repeat('f1', 32), 'x.pdf', 'application/pdf', 1); raise exception 'x';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin perform brain.ingestion_start(v, 'pdf_text', 'x', 'lote-b.1'); raise exception 'x';
  exception when insufficient_privilege then v_ok := v_ok + 1; when no_data_found then v_ok := v_ok + 1; end;
  -- a trilha de consulta: a busca do vendedor fica registrada em nome dele; ele nao le a trilha; admin le
  select count(*) into n from public.brain_search('PS981CAP');
  if n <> 1 then raise exception 'B18 FALHOU: brain_search do vendedor devolveu %', n; end if;
  select count(*) into n from brain.knowledge_queries; if n <> 0 then raise exception 'B18 FALHOU: vendedor le a trilha'; end if;
  begin delete from brain.knowledge_queries; get diagnostics n = row_count; if n <> 0 then raise exception 'B18 FALHOU: vendedor apagou trilha'; end if;
  exception when insufficient_privilege then null; end;
  perform set_config('role', 'none', true); reset role;
  if v_ok <> 2 then raise exception 'B18 FALHOU: % de 2 escritas recusadas', v_ok; end if;

  select * into r from brain.knowledge_queries where user_id = '35353535-0000-4000-8000-000000000002' order by id desc limit 1;
  if r.id is null or r.caller_level <> 'internal' or r.hits <> 1 or r.query_text <> 'PS981CAP' or cardinality(r.top_chunk_ids) <> 1 or r.origin <> 'app' then
    raise exception 'B18 FALHOU: trilha: %', to_jsonb(r);
  end if;
  -- as buscas vazias do vendedor tambem ficaram (hits = 0), sem revelar nada
  select count(*) into n from brain.knowledge_queries where user_id = '35353535-0000-4000-8000-000000000002' and hits = 0 and query_text in ('ZQXSEGREDO', 'S100');
  if n <> 2 then raise exception 'B18 FALHOU: buscas vazias nao registradas (%)', n; end if;
  -- sem usuario (anon): brain_search nao executa
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
  begin select count(*) into n from public.brain_search('PS981CAP'); raise exception 'B18 FALHOU: anon buscou pela porta';
  exception when insufficient_privilege then null; end;
  perform set_config('role', 'none', true); reset role;
  raise notice ' B18) OK: vendedor nao ve ingestao/pagina/chunk commercial (nem por brain_search/brain_provenance), nao registra versao nem abre ingestao; trilha registra as buscas dele (hits 1 e 0) e so o admin le; anon sem porta';
end
$$;

-- ════════════════════════════════════════════════════════════
-- B19 / B20 — ERP intocado, conteudo repetido entre paginas, zero vetor, funcoes
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; i uuid; n int; r record; v_bad text := '';
begin
  reset role;
  -- B19: nada do worker toca o ERP
  select count(*) into n from public.products where code like 'PS98%' or code like 'S100%';
  if n <> 0 then raise exception 'B19 FALHOU: produto criado no ERP'; end if;
  select count(*) into n from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
   join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
   where cn.nspname = 'public' and pn.nspname = 'brain' and not t.tgisinternal and t.tgname not like 'trg_brain_%';
  if n <> 0 then raise exception 'B19 FALHOU: gatilho do brain no ERP'; end if;
  -- conteudo repetido em paginas DIFERENTES e aceito (rodape, aviso); na MESMA pagina, nao
  v := brain.register_version('35353535-0000-4000-8000-0000000000d3', '2025-01', repeat('e9', 32), 'manual2.pdf', 'application/pdf', 1000, null, 2);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber', 'lote-b.1', 'suite-35', false, 2);
  perform brain.ingestion_add_page(i, 1, 'p1', 'text_layer');
  perform brain.ingestion_add_page(i, 2, 'p2', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1, 'Aviso legal repetido em todas as paginas.');
  perform brain.ingestion_add_chunk(i, 1, 'text', 2, 2, 'Aviso legal repetido em todas as paginas.');
  begin perform brain.ingestion_add_chunk(i, 2, 'text', 2, 2, 'Aviso legal repetido em todas as paginas.'); raise exception 'B19 FALHOU: duplicata na mesma pagina aceita';
  exception when unique_violation then null; end;
  perform brain.ingestion_finish(i, 'completed');
  raise notice ' B19) OK: nenhum produto/gatilho do worker no ERP; conteudo repetido em paginas diferentes aceito (dois chunks, duas citacoes); na mesma pagina recusado';

  -- B20
  if exists (select 1 from pg_extension where extname = 'vector') then raise exception 'B20 FALHOU: vector'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'brain' and udt_name in ('vector','halfvec','sparsevec')) then raise exception 'B20 FALHOU: coluna vetorial'; end if;
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid join pg_namespace ns on ns.oid = t.typnamespace where ns.nspname = 'brain' and e.enumlabel ilike '%embed%') then raise exception 'B20 FALHOU: rotulo embedding'; end if;
  for r in
    select n.nspname, p.proname, p.prosecdef, p.proconfig,
           has_function_privilege('anon', p.oid, 'execute') as anon_x, has_function_privilege('authenticated', p.oid, 'execute') as auth_x
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where (n.nspname = 'brain' and p.proname in ('register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail'))
        or (n.nspname = 'public' and p.proname in ('brain_search','brain_provenance'))
  loop
    n := coalesce(n, 0);
    if r.prosecdef then v_bad := v_bad || r.proname || ':definer '; end if;
    if r.proconfig is null or not ('search_path=""' = any(r.proconfig)) then v_bad := v_bad || r.proname || ':search_path '; end if;
    if r.anon_x then v_bad := v_bad || r.proname || ':anon '; end if;
    if not r.auth_x then v_bad := v_bad || r.proname || ':sem-authenticated '; end if;
  end loop;
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where (ns.nspname = 'brain' and p.proname in ('register_version','ingestion_start','ingestion_add_page','ingestion_add_chunk','ingestion_finish','ingestion_fail'))
      or (ns.nspname = 'public' and p.proname in ('brain_search','brain_provenance'));
  if n <> 8 then raise exception 'B20 FALHOU: % de 8 funcoes', n; end if;
  if v_bad <> '' then raise exception 'B20 FALHOU: %', v_bad; end if;
  if not (select relrowsecurity from pg_class where oid = 'brain.knowledge_queries'::regclass) then raise exception 'B20 FALHOU: knowledge_queries sem RLS'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'brain' and grantee = 'anon') then raise exception 'B20 FALHOU: anon com grant'; end if;
  raise notice ' B20) OK: sem vector/coluna vetorial/rotulo embedding; 8 funcoes do Lote B security invoker, search_path vazio, anon sem EXECUTE; knowledge_queries com RLS';
end
$$;

-- ════════════════════════════════════════════════════════════
-- BG — golden dataset (docs/brain/golden-dataset-v0.json) sobre o sintetico
-- ════════════════════════════════════════════════════════════
-- Mapeamento: MJ981CAP → PS981CAP, Magnojet V41 → Catalogo Sol V2 (vigente),
-- V40 → V1 (agora withdrawn na suite; a pergunta 5 usa a V2 + historico),
-- planilha de margem (admin) → 'Margem Sol 2026'.
do $$
declare r record; n int; v uuid; i uuid;
begin
  reset role;
  -- documento admin com o numero que o vendedor NAO pode ver
  v := brain.register_version('35353535-0000-4000-8000-0000000000d4', '2026', repeat('a9', 32), 'margem.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 7000, null, 1);
  i := brain.ingestion_start(v, 'xlsx', 'openpyxl 3.1.5', 'lote-b.1', 'suite-35', false, 1);
  perform brain.ingestion_add_page(i, 1, '', 'spreadsheet');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1, 'TABELA DE PREÇO S100 — 2026: margem ajustável 0,779; custo total; preço de venda; lucro.', '{}', null, '{"S100"}');
  perform brain.ingestion_finish(i, 'completed');
  update brain.document_versions set status = 'active', valid_from = current_date where id = v;

  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  -- G1 (vazao): "qual ponta de cone vazio ultra grossa entrega perto de 0,8 L/min?" → a tabela da p.2, com 0,77 e 0,83 no JSONB
  select * into r from brain.search_knowledge('cone vazio ultra grossa vazão') limit 1;
  if r.kind <> 'table' or r.page_from <> 2 then raise exception 'BG1 FALHOU: %', to_jsonb(r); end if;
  select count(*) into n from jsonb_array_elements(r.table_data -> 'rows') row where (row ->> 5)::numeric between 0.7 and 0.9;
  if n <> 2 then raise exception 'BG1 FALHOU: % linhas perto de 0,8 L/min (esperava 0,77 e 0,83)', n; end if;
  raise notice ' BG1) OK: "cone vazio ultra grossa vazão" (titulo via heading_norm + cabecalho da tabela) cai na tabela da p.2; JSONB tem as 2 linhas entre 0,7 e 0,9 L/min (0,77 PS981CAP; 0,83 PS982CAP)';
  -- G2 (vazao_velocidade): "com a PS981CAP a 40 psi, quantos L/ha a 12 km/h?" → 77
  select * into r from brain.search_knowledge('PS981CAP 40 psi L/ha 12 km/h') limit 1;
  select (row ->> 6)::numeric into n from jsonb_array_elements(r.table_data -> 'rows') row where row ->> 0 = 'PS981CAP' and (row ->> 4)::numeric = 40;
  if n <> 77 then raise exception 'BG2 FALHOU: L/ha = %', n; end if;
  raise notice ' BG2) OK: PS981CAP a 40 psi → 77 L/ha a 12 km/h, lido do JSONB (verificacao quantitativa)';
  -- G5 (catalogo/versao): "em qual catalogo aparece PS983CAP?" → V2 vigente; V1 so pedindo (aqui V1 esta withdrawn: zero)
  select version_label into r from brain.search_knowledge('PS983CAP') limit 1;
  if r.version_label <> 'V2' then raise exception 'BG5 FALHOU: padrao = %', r.version_label; end if;
  raise notice ' BG5) OK: PS983CAP e citado na V2 (vigente) por padrao';
  -- G12 (sem resposta): PS999CAP nao existe → zero; nenhum numero aparece
  select count(*) into n from brain.search_knowledge('PS999CAP'); if n <> 0 then raise exception 'BG12 FALHOU: % resultados', n; end if;
  raise notice ' BG12) OK: codigo inexistente (PS999CAP) → zero resultados: "nao encontrei evidencia suficiente"';
  -- G13 (Kuhn): fonte inexistente → zero, e nada de outro fabricante e devolvido como se fosse Kuhn
  select count(*) into n from brain.search_knowledge('manual da semeadora Kuhn'); if n <> 0 then raise exception 'BG13 FALHOU: % resultados', n; end if;
  select count(*) into n from brain.knowledge_sources where key ilike '%kuhn%'; if n <> 0 then raise exception 'BG13 FALHOU: fonte Kuhn existe'; end if;
  raise notice ' BG13) OK: Kuhn continua lacuna de fonte: zero resultados, zero fonte';
  -- G14 (acesso): margem ajustavel do S100 na planilha admin → vendedor: zero; admin: acha 0,779
  select count(*) into n from brain.search_knowledge('margem ajustável S100 tabela de preço 2026'); if n <> 0 then raise exception 'BG14 FALHOU: vendedor viu %', n; end if;
  -- pelo numero: o trigram pode devolver a tabela PUBLICA (0,77 L/min); o que nao pode e devolver o documento admin ou o numero 0,779
  select count(*) into n from brain.search_knowledge('0,779') where access_level = 'admin' or content ~ '0,779';
  if n <> 0 then raise exception 'BG14 FALHOU: vendedor achou o numero'; end if;
  perform set_config('role', 'none', true); reset role;
  perform set_config('request.jwt.claim.sub', '35353535-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select * into r from brain.search_knowledge('margem ajustável S100') limit 1;
  if r.content !~ '0,779' or r.access_level <> 'admin' then raise exception 'BG14 FALHOU: admin nao achou: %', to_jsonb(r); end if;
  perform set_config('role', 'none', true); reset role;
  raise notice ' BG14) OK: vendedor nao ve a planilha admin nem por tema nem pelo numero; administrador acha 0,779';
end
$$;

reset role;
drop function pg_temp.ingerir_catalogo(text, text, boolean);

-- Limpeza: so o que esta suite criou.
delete from brain.knowledge_queries where user_id in ('35353535-0000-4000-8000-000000000001','35353535-0000-4000-8000-000000000002');
delete from brain.documents where id in ('35353535-0000-4000-8000-0000000000d1','35353535-0000-4000-8000-0000000000d2','35353535-0000-4000-8000-0000000000d3','35353535-0000-4000-8000-0000000000d4');
delete from brain.knowledge_sources where key in ('sol', 'sol_rev', 'sol_int', 'sol_adm');
delete from auth.users where id in ('35353535-0000-4000-8000-000000000001','35353535-0000-4000-8000-000000000002');
