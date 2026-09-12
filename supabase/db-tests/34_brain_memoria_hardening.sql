-- ============================================================
-- 34 · BRAIN Fase 2, Lote A — auditoria pré-publicação (adversarial)
-- ============================================================
-- A suíte 33 prova que a memória funciona. Esta prova que ela NÃO funciona
-- para quem não pode: cada teste tenta quebrar uma cerca, e o resultado
-- esperado é "indistinguível de não existir".
--
--   RAG-H1   fail-closed: sem perfil, inativo, sem sub, marca de sessão, banco
--   RAG-H2   vazamento por ranking: score/rank do que se vê não muda com o que não se vê
--   RAG-H3   cascata de classificação: subir o pai fecha toda a cadeia; rebaixar filho é impossível
--   RAG-H4   processamento externo: admin nunca; opt-out vale; opt-in nunca abaixo do piso
--   RAG-H5   versões: futura, expirada, superseded manual, draft, duas vigentes
--   RAG-H6   limites da busca: limite, filtros inválidos, nulos, pergunta enorme
--   RAG-H7   funções: invoker, search_path vazio, matriz de EXECUTE
--   RAG-H8   arquivo: imutabilidade lógica; mesmo sha em documentos distintos
--   RAG-H9   fontes: só aparecem as alcançáveis ou com documento visível
--   RAG-H10  chunk_products: FK ao ERP, sem duplicata, produto apagado leva o vínculo, nada escreve no ERP
--   RAG-H11  pós-deploy: limiar trigram por set_config (sem SET na função), 0,35 efetivo,
--            local à transação, corpo igual ao de produção, volatile, grants iguais
--
-- Prefixo de UUID = 34. Fixtures artificiais; limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('34343434-0000-4000-8000-000000000001','h.admin@teste.local', '{"full_name":"Admin H"}'),
 ('34343434-0000-4000-8000-000000000002','h.vend@teste.local',  '{"full_name":"Vendedor H"}'),
 ('34343434-0000-4000-8000-000000000003','h.inativo@teste.local','{"full_name":"Inativo H"}');
update public.profiles set role = 'admin' where id = '34343434-0000-4000-8000-000000000001';
update public.profiles set is_active = false where id = '34343434-0000-4000-8000-000000000003';

insert into public.products (id, code, name, unit_id, sale_price)
select '34343434-0000-4000-8000-0000000000e1', 'RAGH-001', 'Produto H (teste)', u.id, 0 from public.units u where u.code = 'UN';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('h_fab',   'Fabricante H',        'manufacturer', 'public',   'allowed'),
 ('h_int',   'AgroTork H interno',  'internal',     'internal', 'approved_provider_only'),
 ('h_adm',   'Diretoria H',         'internal',     'admin',    'forbidden'),
 ('h_vazia', 'Fonte H sem documento','other',       'internal', 'forbidden');

insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('34343434-0000-4000-8000-0000000000d1', 'h_fab', 'h-catalogo',   'Catálogo H',            'catalog',       'public'),
 ('34343434-0000-4000-8000-0000000000d2', 'h_int', 'h-tabela',     'Tabela H revenda',      'price_list',    'commercial'),
 ('34343434-0000-4000-8000-0000000000d3', 'h_int', 'h-manual',     'Manual H interno',      'manual',        'internal'),
 ('34343434-0000-4000-8000-0000000000d4', 'h_adm', 'h-diretoria',  'Nota da diretoria H',   'internal_note', 'admin');

insert into brain.document_versions (id, document_id, version_label, status, valid_from, storage_path, original_filename, mime_type, file_size, file_sha256) values
 ('34343434-0000-4000-8000-0000000000a1', '34343434-0000-4000-8000-0000000000d1', 'V1', 'active', '2026-01-01', 'h_fab/h-catalogo/V1/' || repeat('c1', 32) || '.pdf', 'cat.pdf', 'application/pdf', 1000, repeat('c1', 32)),
 ('34343434-0000-4000-8000-0000000000b1', '34343434-0000-4000-8000-0000000000d2', 'V1', 'active', '2026-01-01', 'h_int/h-tabela/V1/'   || repeat('c2', 32) || '.pdf', 'tab.pdf', 'application/pdf', 1000, repeat('c2', 32)),
 ('34343434-0000-4000-8000-0000000000c1', '34343434-0000-4000-8000-0000000000d3', 'V1', 'active', '2026-01-01', 'h_int/h-manual/V1/'   || repeat('c3', 32) || '.pdf', 'man.pdf', 'application/pdf', 1000, repeat('c3', 32)),
 ('34343434-0000-4000-8000-0000000000e9', '34343434-0000-4000-8000-0000000000d4', 'V1', 'active', '2026-01-01', 'h_adm/h-diretoria/V1/'|| repeat('c4', 32) || '.pdf', 'dir.pdf', 'application/pdf', 1000, repeat('c4', 32));

insert into brain.knowledge_ingestions (id, version_id, status, method, pipeline_version) values
 ('34343434-0000-4000-8000-0000000000f1', '34343434-0000-4000-8000-0000000000a1', 'completed', 'pdf_text', 'h-fixture'),
 ('34343434-0000-4000-8000-0000000000f2', '34343434-0000-4000-8000-0000000000b1', 'completed', 'pdf_text', 'h-fixture'),
 ('34343434-0000-4000-8000-0000000000f3', '34343434-0000-4000-8000-0000000000c1', 'completed', 'pdf_text', 'h-fixture'),
 ('34343434-0000-4000-8000-0000000000f4', '34343434-0000-4000-8000-0000000000e9', 'completed', 'pdf_text', 'h-fixture');

insert into brain.document_pages (version_id, page_no, ingestion_id, text, extraction) values
 ('34343434-0000-4000-8000-0000000000a1', 1, '34343434-0000-4000-8000-0000000000f1', 'p1', 'text_layer'),
 ('34343434-0000-4000-8000-0000000000b1', 1, '34343434-0000-4000-8000-0000000000f2', 'p1', 'text_layer'),
 ('34343434-0000-4000-8000-0000000000c1', 1, '34343434-0000-4000-8000-0000000000f3', 'p1', 'text_layer'),
 ('34343434-0000-4000-8000-0000000000e9', 1, '34343434-0000-4000-8000-0000000000f4', 'p1', 'text_layer');

-- O termo ZQXVORBIT so existe no chunk commercial; KWZ7710 existe no publico e
-- no commercial; GLIFOX so no publico.
insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content, codes) values
 ('34343434-0000-4000-8000-0000000000a1', '34343434-0000-4000-8000-0000000000f1', 0, 'text', 1, 1, 'Ponta KWZ7710 de cerâmica para herbicida GLIFOX, vazão calibrada.', '{"KWZ7710"}'),
 ('34343434-0000-4000-8000-0000000000b1', '34343434-0000-4000-8000-0000000000f2', 0, 'text', 1, 1, 'Ponta KWZ7710: preço de revenda ZQXVORBIT confidencial.', '{"KWZ7710","ZQXVORBIT"}'),
 ('34343434-0000-4000-8000-0000000000c1', '34343434-0000-4000-8000-0000000000f3', 0, 'text', 1, 1, 'Manual interno: procedimento de calibração da ponta.', '{}'),
 ('34343434-0000-4000-8000-0000000000e9', '34343434-0000-4000-8000-0000000000f4', 0, 'text', 1, 1, 'Nota da diretoria: margem alvo e metas.', '{}');

insert into brain.chunk_products (chunk_id, product_id, linked_by)
select id, '34343434-0000-4000-8000-0000000000e1', 'manual' from brain.document_chunks where version_id in ('34343434-0000-4000-8000-0000000000a1', '34343434-0000-4000-8000-0000000000b1');

-- ════════════════════════════════════════════════════════════
-- RAG-H1 — fail-closed
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_lvl brain.access_level;
begin
  reset role;
  -- banco falando consigo mesmo: admin
  if brain.caller_access_level() <> 'admin' then raise exception 'RAG-H1 FALHOU: postgres = %', brain.caller_access_level(); end if;

  -- JWT com sub de usuario que NAO tem perfil
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-0000000000ff', true);
  perform set_config('role', 'authenticated', true);
  v_lvl := brain.caller_access_level();
  if v_lvl is not null then raise exception 'RAG-H1 FALHOU: sem perfil recebeu %', v_lvl; end if;
  select count(*) into v_n from brain.document_chunks;
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: sem perfil leu % chunks', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710');
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: sem perfil buscou'; end if;
  select count(*) into v_n from brain.knowledge_sources;
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: sem perfil viu % fontes', v_n; end if;
  perform set_config('role', 'none', true); reset role;

  -- perfil INATIVO
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000003', true);
  perform set_config('role', 'authenticated', true);
  if brain.caller_access_level() is not null then raise exception 'RAG-H1 FALHOU: inativo tem nivel'; end if;
  select count(*) into v_n from brain.documents;
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: inativo leu documentos'; end if;
  perform set_config('role', 'none', true); reset role;

  -- papel authenticated SEM sub (JWT quebrado): nem "banco", nem usuario
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'authenticated', true);
  if brain.caller_access_level() is not null then raise exception 'RAG-H1 FALHOU: authenticated sem sub tem nivel'; end if;
  select count(*) into v_n from brain.document_chunks;
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: sem sub leu chunks'; end if;
  perform set_config('role', 'none', true); reset role;

  -- marca de sessao das pontes do ERP nao eleva ninguem
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  perform set_config('brain.internal', 'on', true);
  if brain.caller_access_level() <> 'internal' then raise exception 'RAG-H1 FALHOU: brain.internal elevou para %', brain.caller_access_level(); end if;
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT');
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: brain.internal abriu a busca'; end if;
  select count(*) into v_n from brain.document_chunks where access_level >= 'commercial';
  if v_n <> 0 then raise exception 'RAG-H1 FALHOU: brain.internal abriu o RLS'; end if;
  perform set_config('brain.internal', 'off', true);
  perform set_config('role', 'none', true); reset role;

  -- vendedor ativo: internal, e so isso
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  if brain.caller_access_level() <> 'internal' then raise exception 'RAG-H1 FALHOU: vendedor = %', brain.caller_access_level(); end if;
  if brain.can_read_level('commercial') then raise exception 'RAG-H1 FALHOU: internal le commercial'; end if;
  if brain.can_read_level('admin') then raise exception 'RAG-H1 FALHOU: internal le admin'; end if;
  if not brain.can_read_level('internal') or not brain.can_read_level('public') then raise exception 'RAG-H1 FALHOU: internal nao le o proprio nivel'; end if;
  perform set_config('role', 'none', true); reset role;

  raise notice ' RAG-H1) OK: fail-closed — sem perfil, inativo, sem sub e marca de sessao dao NULL/zero; banco = admin; vendedor = internal e nada acima';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H2 — vazamento por ranking
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; r1 record; r2 record; v_chunk_com bigint; v_content text; v_codes text[];
begin
  reset role;
  select id, content, codes into v_chunk_com, v_content, v_codes from brain.document_chunks where version_id = '34343434-0000-4000-8000-0000000000b1';

  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  -- termo unico do commercial: nada, por nenhum braco, com ou sem historico, com ou sem filtro
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT');                       if v_n <> 0 then raise exception 'RAG-H2 FALHOU: exato'; end if;
  select count(*) into v_n from brain.search_knowledge('zqxvorbi');                        if v_n <> 0 then raise exception 'RAG-H2 FALHOU: trigram'; end if;
  select count(*) into v_n from brain.search_knowledge('preço de revenda confidencial');  if v_n <> 0 then raise exception 'RAG-H2 FALHOU: fts'; end if;
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT', '{}', 100, true);      if v_n <> 0 then raise exception 'RAG-H2 FALHOU: historico'; end if;
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT', jsonb_build_object('version_id', '34343434-0000-4000-8000-0000000000b1'), 100, true);
  if v_n <> 0 then raise exception 'RAG-H2 FALHOU: por version_id'; end if;
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT', jsonb_build_object('source_key', 'h_int')); if v_n <> 0 then raise exception 'RAG-H2 FALHOU: por fonte'; end if;
  select count(*) into v_n from brain.search_knowledge('ZQXVORBIT', jsonb_build_object('product_id', '34343434-0000-4000-8000-0000000000e1')); if v_n <> 0 then raise exception 'RAG-H2 FALHOU: por produto'; end if;
  -- e a resposta e identica a de um termo que nao existe em lugar nenhum
  if (select count(*) from brain.search_knowledge('ZQXVORBIT')) <> (select count(*) from brain.search_knowledge('TERMOQUENAOEXISTE')) then
    raise exception 'RAG-H2 FALHOU: distinguivel de inexistente';
  end if;
  -- proveniencia e contagem
  if brain.chunk_provenance(v_chunk_com) is not null then raise exception 'RAG-H2 FALHOU: proveniencia'; end if;
  select count(*) into v_n from brain.document_chunks where id = v_chunk_com; if v_n <> 0 then raise exception 'RAG-H2 FALHOU: contagem por id'; end if;
  select count(*) into v_n from brain.chunk_products where chunk_id = v_chunk_com; if v_n <> 0 then raise exception 'RAG-H2 FALHOU: vinculo'; end if;

  -- KWZ7710 esta no publico e no commercial: o vendedor recebe SO o publico,
  -- e o score/rank desse resultado nao carrega informacao do commercial.
  select * into r1 from brain.search_knowledge('KWZ7710') limit 1;
  select count(*) into v_n from brain.search_knowledge('KWZ7710');
  if v_n <> 1 or r1.access_level <> 'public' then raise exception 'RAG-H2 FALHOU: KWZ7710 devolveu % (%)', v_n, r1.access_level; end if;
  perform set_config('role', 'none', true); reset role;

  -- some com o chunk commercial e repete: tem de ser byte a byte igual
  delete from brain.document_chunks where id = v_chunk_com;
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select * into r2 from brain.search_knowledge('KWZ7710') limit 1;
  perform set_config('role', 'none', true); reset role;
  if r1.chunk_id <> r2.chunk_id or r1.score <> r2.score
     or r1.rank_exact is distinct from r2.rank_exact or r1.rank_trgm is distinct from r2.rank_trgm or r1.rank_fts is distinct from r2.rank_fts then
    raise exception 'RAG-H2 FALHOU: ranking mudou com o invisivel: % vs %', to_jsonb(r1), to_jsonb(r2);
  end if;
  -- restaura o chunk commercial (mesmo conteudo)
  insert into brain.document_chunks (version_id, ingestion_id, ordinal, kind, page_from, page_to, content, codes)
  values ('34343434-0000-4000-8000-0000000000b1', '34343434-0000-4000-8000-0000000000f2', 0, 'text', 1, 1, v_content, v_codes);
  insert into brain.chunk_products (chunk_id, product_id, linked_by)
  select id, '34343434-0000-4000-8000-0000000000e1', 'manual' from brain.document_chunks where version_id = '34343434-0000-4000-8000-0000000000b1';

  raise notice ' RAG-H2) OK: termo unico do commercial e invisivel por exato/trigram/fts/historico/filtros/proveniencia/contagem; score e ranks do publico identicos com e sem o commercial (score %)', r1.score;
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H3 — cascata de classificacao
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_chunk bigint;
begin
  reset role;
  select id into v_chunk from brain.document_chunks where version_id = '34343434-0000-4000-8000-0000000000a1';
  -- sobe o catalogo publico para commercial
  update brain.documents set access_level = 'commercial' where id = '34343434-0000-4000-8000-0000000000d1';
  select count(*) into v_n from (
    select access_level from brain.document_versions   where document_id = '34343434-0000-4000-8000-0000000000d1'
    union all select access_level from brain.knowledge_ingestions where version_id = '34343434-0000-4000-8000-0000000000a1'
    union all select access_level from brain.document_pages       where version_id = '34343434-0000-4000-8000-0000000000a1'
    union all select access_level from brain.document_chunks      where version_id = '34343434-0000-4000-8000-0000000000a1'
    union all select access_level from brain.chunk_products       where chunk_id = v_chunk) t where access_level <> 'commercial';
  if v_n <> 0 then raise exception 'RAG-H3 FALHOU: % linhas ficaram para tras', v_n; end if;

  -- tentar rebaixar UM filho direto (como banco): o carimbo devolve o nivel do pai
  update brain.document_chunks set access_level = 'public' where id = v_chunk;
  if (select access_level from brain.document_chunks where id = v_chunk) <> 'commercial' then raise exception 'RAG-H3 FALHOU: chunk rebaixado por update direto'; end if;
  update brain.document_versions set access_level = 'public' where id = '34343434-0000-4000-8000-0000000000a1';
  if (select access_level from brain.document_versions where id = '34343434-0000-4000-8000-0000000000a1') <> 'commercial' then raise exception 'RAG-H3 FALHOU: versao rebaixada por update direto'; end if;
  update brain.document_pages set access_level = 'public' where version_id = '34343434-0000-4000-8000-0000000000a1';
  if exists (select 1 from brain.document_pages where version_id = '34343434-0000-4000-8000-0000000000a1' and access_level <> 'commercial') then raise exception 'RAG-H3 FALHOU: pagina rebaixada'; end if;
  update brain.chunk_products set access_level = 'public' where chunk_id = v_chunk;
  if exists (select 1 from brain.chunk_products where chunk_id = v_chunk and access_level <> 'commercial') then raise exception 'RAG-H3 FALHOU: vinculo rebaixado'; end if;

  -- o vendedor perdeu tudo: GLIFOX so existia no catalogo
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from brain.search_knowledge('GLIFOX'); if v_n <> 0 then raise exception 'RAG-H3 FALHOU: busca ainda ve'; end if;
  select count(*) into v_n from brain.document_pages where version_id = '34343434-0000-4000-8000-0000000000a1'; if v_n <> 0 then raise exception 'RAG-H3 FALHOU: pagina ainda visivel'; end if;
  select count(*) into v_n from brain.chunk_products where product_id = '34343434-0000-4000-8000-0000000000e1'; if v_n <> 0 then raise exception 'RAG-H3 FALHOU: vinculo ainda visivel'; end if;
  if brain.chunk_provenance(v_chunk) is not null then raise exception 'RAG-H3 FALHOU: proveniencia ainda visivel'; end if;
  perform set_config('role', 'none', true); reset role;

  -- volta a publico: a cadeia inteira reabre
  update brain.documents set access_level = 'public' where id = '34343434-0000-4000-8000-0000000000d1';
  if exists (select 1 from brain.chunk_products where chunk_id = v_chunk and access_level <> 'public') then raise exception 'RAG-H3 FALHOU: reabertura nao desceu ate o vinculo'; end if;
  -- e a cascata nao toca em quem nao e filho
  if (select access_level from brain.document_chunks where version_id = '34343434-0000-4000-8000-0000000000b1') <> 'commercial' then raise exception 'RAG-H3 FALHOU: cascata vazou para outro documento'; end if;
  raise notice ' RAG-H3) OK: subir o documento fecha versao/ingestao/pagina/chunk/vinculo; rebaixar filho direto e desfeito pelo carimbo; voltar reabre; vizinhos intactos';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H4 — processamento externo
-- ════════════════════════════════════════════════════════════
do $$
begin
  reset role;
  -- admin: nunca, com qualquer override
  update brain.documents set external_processing_override = 'allowed', approved_by = '34343434-0000-4000-8000-000000000001', approved_at = now() where id = '34343434-0000-4000-8000-0000000000d4';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d4') <> 'forbidden' then raise exception 'RAG-H4 FALHOU: admin allowed'; end if;
  update brain.documents set external_processing_override = 'approved_provider_only' where id = '34343434-0000-4000-8000-0000000000d4';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d4') <> 'forbidden' then raise exception 'RAG-H4 FALHOU: admin approved_provider'; end if;
  -- public com opt-OUT: vale
  update brain.documents set external_processing_override = 'forbidden', approved_by = '34343434-0000-4000-8000-000000000001', approved_at = now() where id = '34343434-0000-4000-8000-0000000000d1';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d1') <> 'forbidden' then raise exception 'RAG-H4 FALHOU: opt-out public'; end if;
  update brain.documents set external_processing_override = null, approved_by = null, approved_at = null where id = '34343434-0000-4000-8000-0000000000d1';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d1') <> 'allowed' then raise exception 'RAG-H4 FALHOU: public default'; end if;
  -- commercial: default forbidden; opt-in parcial fica parcial; opt-in total abre
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d2') <> 'forbidden' then raise exception 'RAG-H4 FALHOU: commercial default'; end if;
  update brain.documents set external_processing_override = 'approved_provider_only', approved_by = '34343434-0000-4000-8000-000000000001', approved_at = now() where id = '34343434-0000-4000-8000-0000000000d2';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d2') <> 'approved_provider_only' then raise exception 'RAG-H4 FALHOU: commercial parcial'; end if;
  -- internal: piso e approved_provider_only, mesmo com a fonte em allowed
  update brain.knowledge_sources set external_processing = 'allowed' where key = 'h_int';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d3') <> 'approved_provider_only' then raise exception 'RAG-H4 FALHOU: internal com fonte allowed'; end if;
  update brain.documents set external_processing_override = 'forbidden', approved_by = '34343434-0000-4000-8000-000000000001', approved_at = now() where id = '34343434-0000-4000-8000-0000000000d3';
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000d3') <> 'forbidden' then raise exception 'RAG-H4 FALHOU: internal opt-out'; end if;
  -- override sem aprovacao registrada: recusado (constraint)
  begin
    update brain.documents set approved_by = null, approved_at = null where id = '34343434-0000-4000-8000-0000000000d3';
    raise exception 'RAG-H4 FALHOU: override ficou sem aprovacao';
  exception when check_violation then null; end;
  begin
    update brain.documents set approved_by = null, approved_at = null, external_processing_override = null where id = '34343434-0000-4000-8000-0000000000d3';
    update brain.documents set external_processing_override = 'allowed' where id = '34343434-0000-4000-8000-0000000000d3';
    raise exception 'RAG-H4 FALHOU: override entrou sem aprovacao';
  exception when check_violation then null; end;
  -- apagar o perfil de quem aprovou: a decisao (data + override) fica, a pessoa vira NULL, o usuario sai
  update brain.documents set external_processing_override = 'approved_provider_only', approved_by = '34343434-0000-4000-8000-000000000001', approved_at = now() where id = '34343434-0000-4000-8000-0000000000d2';
  delete from auth.users where id = '34343434-0000-4000-8000-000000000001';
  if (select approved_by from brain.documents where id = '34343434-0000-4000-8000-0000000000d2') is not null
     or (select approved_at from brain.documents where id = '34343434-0000-4000-8000-0000000000d2') is null
     or brain.external_processing_for('34343434-0000-4000-8000-0000000000d2') <> 'approved_provider_only' then
    raise exception 'RAG-H4 FALHOU: apagar o aprovador mexeu na decisao';
  end if;
  insert into auth.users (id, email, raw_user_meta_data) values ('34343434-0000-4000-8000-000000000001','h.admin@teste.local', '{"full_name":"Admin H"}');
  update public.profiles set role = 'admin' where id = '34343434-0000-4000-8000-000000000001';
  -- documento inexistente: NULL, nao "allowed"
  if brain.external_processing_for('34343434-0000-4000-8000-0000000000dd') is not null then raise exception 'RAG-H4 FALHOU: inexistente nao e NULL'; end if;
  raise notice ' RAG-H4) OK: admin nunca (2 overrides); opt-out vale em public/internal; commercial exige opt-in e respeita parcial; internal nunca abaixo de provedor aprovado; override sem aprovacao recusado; apagar o aprovador preserva a decisao';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H5 — estados de versao
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_id uuid;
begin
  reset role;
  -- futura: nao se ativa
  begin
    insert into brain.document_versions (document_id, version_label, status, valid_from, storage_path, original_filename, mime_type, file_size, file_sha256)
    values ('34343434-0000-4000-8000-0000000000d3', 'V2', 'active', current_date + 1, 'h_int/h-manual/V2/' || repeat('c5', 32) || '.pdf', 'm2.pdf', 'application/pdf', 1000, repeat('c5', 32));
    raise exception 'RAG-H5 FALHOU: ativou versao futura';
  exception when check_violation then null; end;
  -- a mesma, como draft: aceita, e nao aparece em busca nem em current_version
  insert into brain.document_versions (id, document_id, version_label, status, valid_from, storage_path, original_filename, mime_type, file_size, file_sha256)
  values ('34343434-0000-4000-8000-0000000000c2', '34343434-0000-4000-8000-0000000000d3', 'V2', 'draft', current_date + 1, 'h_int/h-manual/V2/' || repeat('c5', 32) || '.pdf', 'm2.pdf', 'application/pdf', 1000, repeat('c5', 32));
  if brain.current_version('34343434-0000-4000-8000-0000000000d3') <> '34343434-0000-4000-8000-0000000000c1' then raise exception 'RAG-H5 FALHOU: draft virou vigente'; end if;
  -- duas vigentes por fora do gatilho: impossivel (indice unico parcial)
  begin
    update brain.document_versions set status = 'active' where id = '34343434-0000-4000-8000-0000000000c2';
    -- o gatilho supersede a V1 — entao o que se testa e o caminho SEM gatilho:
    -- reativar a V1 tem de superseder a V2, e nunca haver duas.
    update brain.document_versions set status = 'active' where id = '34343434-0000-4000-8000-0000000000c1';
  exception when check_violation then null; end;
  select count(*) into v_n from brain.document_versions where document_id = '34343434-0000-4000-8000-0000000000d3' and status = 'active';
  if v_n <> 1 then raise exception 'RAG-H5 FALHOU: % vigentes', v_n; end if;
  -- V2 (valid_from amanha) nao pode ser ativada — confirma que o bloqueio vale tambem no UPDATE
  update brain.document_versions set valid_from = current_date where id = '34343434-0000-4000-8000-0000000000c2';
  update brain.document_versions set status = 'active' where id = '34343434-0000-4000-8000-0000000000c2';
  if brain.current_version('34343434-0000-4000-8000-0000000000d3') <> '34343434-0000-4000-8000-0000000000c2' then raise exception 'RAG-H5 FALHOU: V2 nao ficou vigente'; end if;
  if (select status from brain.document_versions where id = '34343434-0000-4000-8000-0000000000c1') <> 'superseded' then raise exception 'RAG-H5 FALHOU: V1 nao foi superseded'; end if;
  if (select valid_to from brain.document_versions where id = '34343434-0000-4000-8000-0000000000c1') is null then raise exception 'RAG-H5 FALHOU: superseded sem valid_to'; end if;
  -- superseded manual (sem sucessora) tambem ganha valid_to
  update brain.document_versions set status = 'superseded' where id = '34343434-0000-4000-8000-0000000000c2';
  if (select valid_to from brain.document_versions where id = '34343434-0000-4000-8000-0000000000c2') is null then raise exception 'RAG-H5 FALHOU: superseded manual sem valid_to'; end if;
  if brain.current_version('34343434-0000-4000-8000-0000000000d3') is not null then raise exception 'RAG-H5 FALHOU: documento sem vigente devolveu algo'; end if;
  -- expirada: active com valid_to no passado nao e vigente e nao aparece na busca
  update brain.document_versions set status = 'active', valid_to = current_date - 2 where id = '34343434-0000-4000-8000-0000000000c1';
  if brain.current_version('34343434-0000-4000-8000-0000000000d3') is not null then raise exception 'RAG-H5 FALHOU: expirada e vigente'; end if;
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from brain.search_knowledge('procedimento de calibração');
  if v_n <> 0 then raise exception 'RAG-H5 FALHOU: expirada apareceu na busca'; end if;
  perform set_config('role', 'none', true); reset role;
  -- reabrir: valid_to null → vigente de novo
  update brain.document_versions set valid_to = null where id = '34343434-0000-4000-8000-0000000000c1';
  if brain.current_version('34343434-0000-4000-8000-0000000000d3') <> '34343434-0000-4000-8000-0000000000c1' then raise exception 'RAG-H5 FALHOU: reabertura'; end if;
  -- valid_to antes de valid_from: recusado
  begin
    update brain.document_versions set valid_to = date '2025-01-01' where id = '34343434-0000-4000-8000-0000000000c1';
    raise exception 'RAG-H5 FALHOU: valid_to < valid_from aceito';
  exception when check_violation then null; end;
  delete from brain.document_versions where id = '34343434-0000-4000-8000-0000000000c2';
  raise notice ' RAG-H5) OK: futura recusada (draft ate o dia); draft nunca vigente; uma vigente sempre; superseded sempre com valid_to; expirada nao e vigente nem buscavel; reabertura funciona';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H6 — limites da busca
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_ok int := 0;
begin
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from brain.search_knowledge('KWZ7710', '{}', 0);    if v_n <> 0 then raise exception 'RAG-H6 FALHOU: limite 0 devolveu %', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', '{}', -3);   if v_n <> 0 then raise exception 'RAG-H6 FALHOU: limite negativo'; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', '{}', null); if v_n <> 2 then raise exception 'RAG-H6 FALHOU: limite null = %', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', '{}', 1);    if v_n <> 1 then raise exception 'RAG-H6 FALHOU: limite 1'; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', '{}', 100000); if v_n <> 2 then raise exception 'RAG-H6 FALHOU: limite enorme'; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', null);       if v_n <> 2 then raise exception 'RAG-H6 FALHOU: filtros null'; end if;
  select count(*) into v_n from brain.search_knowledge(null);                 if v_n <> 0 then raise exception 'RAG-H6 FALHOU: pergunta null'; end if;
  select count(*) into v_n from brain.search_knowledge('   ');                if v_n <> 0 then raise exception 'RAG-H6 FALHOU: pergunta em branco'; end if;
  select count(*) into v_n from brain.search_knowledge('''"%_\ ' || E'\n' || 'KWZ7710');  if v_n <> 2 then raise exception 'RAG-H6 FALHOU: caracteres especiais = %', v_n; end if;
  select count(*) into v_n from brain.search_knowledge(repeat('KWZ7710 ', 20000)); if v_n <> 2 then raise exception 'RAG-H6 FALHOU: pergunta enorme = %', v_n; end if;
  select count(*) into v_n from brain.search_knowledge('kwz7710'' or 1=1 --');  if v_n <> 2 then raise exception 'RAG-H6 FALHOU: injecao = %', v_n; end if;
  -- filtros invalidos: erro limpo e classificado, nunca erro do banco
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('version_id', 'nao-e-uuid'));
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('kind', 'foo'));
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('document_type', 'foo'));
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', '[1]'::jsonb);
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('chave_desconhecida', 1));
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('source_key', null));
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  if v_ok <> 6 then raise exception 'RAG-H6 FALHOU: % de 6 filtros invalidos classificados', v_ok; end if;
  -- filtros validos que nao casam: vazio, sem erro
  select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('version_id', '00000000-0000-0000-0000-000000000000')); if v_n <> 0 then raise exception 'RAG-H6 FALHOU: versao inexistente'; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('document_id', '00000000-0000-0000-0000-000000000000')); if v_n <> 0 then raise exception 'RAG-H6 FALHOU: documento inexistente'; end if;
  select count(*) into v_n from brain.search_knowledge('KWZ7710', jsonb_build_object('kind', 'table', 'source_key', 'h_fab')); if v_n <> 0 then raise exception 'RAG-H6 FALHOU: combinacao'; end if;
  perform set_config('role', 'none', true); reset role;
  raise notice ' RAG-H6) OK: limite 0/negativo = nada, null = 10, teto 100; pergunta null/branco/enorme/especial/injecao inofensivas; 6 filtros invalidos → invalid_parameter_value; filtros sem casamento → vazio';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H7 — funcoes: invoker, search_path, matriz de EXECUTE
-- ════════════════════════════════════════════════════════════
do $$
declare r record; v_n int := 0; v_bad text := '';
begin
  reset role;
  for r in
    select p.oid, p.proname, p.prosecdef, p.proconfig, p.prorettype::regtype::text as rt,
           has_function_privilege('anon',          p.oid, 'execute') as anon_x,
           has_function_privilege('authenticated', p.oid, 'execute') as auth_x,
           has_function_privilege('service_role',  p.oid, 'execute') as svc_x
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'brain'
       and p.proname in ('search_knowledge','chunk_provenance','current_version','external_processing_for',
                         'caller_access_level','can_read_level','normalize_text','normalize_code',
                         'stamp_version','stamp_chunk','stamp_page','stamp_ingestion','stamp_chunk_product',
                         'cascade_document_access','cascade_version_access','cascade_chunk_access')
  loop
    v_n := v_n + 1;
    if r.prosecdef then v_bad := v_bad || r.proname || ':definer '; end if;
    if r.proconfig is null or not ('search_path=""' = any(r.proconfig)) then v_bad := v_bad || r.proname || ':search_path '; end if;
    if r.anon_x then v_bad := v_bad || r.proname || ':anon '; end if;
    if r.rt = 'trigger' then
      if r.auth_x then v_bad := v_bad || r.proname || ':trigger-authenticated '; end if;
    else
      if not r.auth_x or not r.svc_x then v_bad := v_bad || r.proname || ':sem-grant '; end if;
    end if;
  end loop;
  if v_n <> 16 then raise exception 'RAG-H7 FALHOU: % de 16 funcoes', v_n; end if;
  if v_bad <> '' then raise exception 'RAG-H7 FALHOU: %', v_bad; end if;
  -- e as 8 funcoes de trigger nao sao chamaveis por ninguem da API
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.prorettype = 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  if v_n <> 0 then raise exception 'RAG-H7 FALHOU: % funcoes de trigger executaveis pela API', v_n; end if;
  raise notice ' RAG-H7) OK: 16 funcoes security invoker com search_path vazio; anon sem EXECUTE em nenhuma; 8 de trigger fechadas a authenticated; 8 de leitura abertas a authenticated/service_role';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H8 — arquivo: imutabilidade logica
-- ════════════════════════════════════════════════════════════
do $$
declare v_ok int := 0; v_n int;
begin
  reset role;
  -- cada campo do arquivo, um por um
  begin update brain.document_versions set file_sha256 = repeat('ee', 32) where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; when check_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set storage_path = 'outro/' || repeat('c1', 32) || '.pdf' where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set file_size = 2 where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set mime_type = 'text/plain' where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set original_filename = 'x.pdf' where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set document_id = '34343434-0000-4000-8000-0000000000d3' where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; end;
  begin update brain.document_versions set storage_bucket = 'outro' where id = '34343434-0000-4000-8000-0000000000a1'; raise exception 'x';
  exception when restrict_violation then v_ok := v_ok + 1; when check_violation then v_ok := v_ok + 1; end;
  if v_ok <> 7 then raise exception 'RAG-H8 FALHOU: % de 7 campos protegidos', v_ok; end if;
  -- o que NAO e arquivo continua editavel
  update brain.document_versions set needs_ocr = false, text_ratio = 0.98, metadata = '{"ok":true}' where id = '34343434-0000-4000-8000-0000000000a1';
  -- mesmo sha em documento DIFERENTE: permitido (mesmo arquivo, duas obras), em caminho diferente
  insert into brain.document_versions (id, document_id, version_label, status, storage_path, original_filename, mime_type, file_size, file_sha256)
  values ('34343434-0000-4000-8000-0000000000a2', '34343434-0000-4000-8000-0000000000d3', 'V1-copia', 'draft', 'h_int/h-manual/V1-copia/' || repeat('c1', 32) || '.pdf', 'cat.pdf', 'application/pdf', 1000, repeat('c1', 32));
  -- mesmo caminho em outro documento: nunca (unico global)
  begin
    insert into brain.document_versions (document_id, version_label, status, storage_path, original_filename, mime_type, file_size, file_sha256)
    values ('34343434-0000-4000-8000-0000000000d2', 'Vx', 'draft', 'h_fab/h-catalogo/V1/' || repeat('c1', 32) || '.pdf', 'cat.pdf', 'application/pdf', 1000, repeat('c1', 32));
    raise exception 'RAG-H8 FALHOU: caminho duplicado aceito';
  exception when unique_violation then null; end;
  -- sha com letra maiuscula ou tamanho errado: recusado
  begin
    insert into brain.document_versions (document_id, version_label, status, storage_path, original_filename, mime_type, file_size, file_sha256)
    values ('34343434-0000-4000-8000-0000000000d2', 'Vy', 'draft', 'h_int/h-tabela/Vy/' || repeat('C9', 32) || '.pdf', 't.pdf', 'application/pdf', 1000, repeat('C9', 32));
    raise exception 'RAG-H8 FALHOU: sha maiusculo aceito';
  exception when check_violation then null; end;
  delete from brain.document_versions where id = '34343434-0000-4000-8000-0000000000a2';
  raise notice ' RAG-H8) OK: 7 campos do arquivo imutaveis (sha, caminho, bucket, tamanho, tipo, nome, documento); metadados editaveis; mesmo sha em outra obra permitido; caminho unico; sha mal formado recusado';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H9 — fontes visiveis
-- ════════════════════════════════════════════════════════════
do $$
declare v_keys text;
begin
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select string_agg(key, ',' order by key) into v_keys from brain.knowledge_sources where key like 'h\_%';
  -- h_fab (public), h_int (tem documento internal visivel), h_vazia (padrao internal, sem documento). h_adm: nao.
  if v_keys is distinct from 'h_fab,h_int,h_vazia' then raise exception 'RAG-H9 FALHOU: vendedor ve fontes [%]', v_keys; end if;
  perform set_config('role', 'none', true); reset role;
  -- admin ve as quatro
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select string_agg(key, ',' order by key) into v_keys from brain.knowledge_sources where key like 'h\_%';
  if v_keys is distinct from 'h_adm,h_fab,h_int,h_vazia' then raise exception 'RAG-H9 FALHOU: admin ve fontes [%]', v_keys; end if;
  perform set_config('role', 'none', true); reset role;
  raise notice ' RAG-H9) OK: vendedor ve fontes alcancaveis ou com documento visivel (h_fab, h_int, h_vazia), nao a fonte admin; administrador ve as 4';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H10 — chunk_products e o ERP
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_chunk bigint;
begin
  reset role;
  -- FK aponta para public.products
  select count(*) into v_n from pg_constraint c
   where c.conrelid = 'brain.chunk_products'::regclass and c.contype = 'f' and c.confrelid = 'public.products'::regclass;
  if v_n <> 1 then raise exception 'RAG-H10 FALHOU: FK para public.products'; end if;
  -- duplicata: nunca
  select id into v_chunk from brain.document_chunks where version_id = '34343434-0000-4000-8000-0000000000a1';
  begin
    insert into brain.chunk_products (chunk_id, product_id) values (v_chunk, '34343434-0000-4000-8000-0000000000e1');
    raise exception 'RAG-H10 FALHOU: vinculo duplicado aceito';
  exception when unique_violation then null; end;
  -- produto inexistente: nunca
  begin
    insert into brain.chunk_products (chunk_id, product_id) values (v_chunk, '34343434-0000-4000-8000-0000000000ee');
    raise exception 'RAG-H10 FALHOU: produto inexistente aceito';
  exception when foreign_key_violation then null; end;
  -- nenhum gatilho do Lote A em tabela do ERP (as 3 pontes da Fase 1 em
  -- quotes/orders sao de outro lote e continuam desligadas — suite 25/31)
  select count(*) into v_n from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
   where cn.nspname = 'public' and n.nspname = 'brain' and not t.tgisinternal
     and p.proname in ('stamp_version','stamp_chunk','stamp_page','stamp_ingestion','stamp_chunk_product',
                       'cascade_document_access','cascade_version_access','cascade_chunk_access');
  if v_n <> 0 then raise exception 'RAG-H10 FALHOU: % gatilhos do Lote A no ERP', v_n; end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
   join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
   where cn.nspname = 'public' and c.relname in ('products', 'product_costs', 'margin_rules', 'stock_movements')
     and n.nspname = 'brain' and not t.tgisinternal;
  if v_n <> 0 then raise exception 'RAG-H10 FALHOU: % gatilhos do brain em produto/custo/margem/estoque', v_n; end if;
  -- produto inativado: vinculo fica (o ERP decide a visibilidade do produto); apagado: vinculo some
  update public.products set is_active = false where id = '34343434-0000-4000-8000-0000000000e1';
  select count(*) into v_n from brain.chunk_products where product_id = '34343434-0000-4000-8000-0000000000e1';
  if v_n <> 2 then raise exception 'RAG-H10 FALHOU: inativar produto mexeu no vinculo (%)', v_n; end if;
  delete from public.products where id = '34343434-0000-4000-8000-0000000000e1';
  select count(*) into v_n from brain.chunk_products where product_id = '34343434-0000-4000-8000-0000000000e1';
  if v_n <> 0 then raise exception 'RAG-H10 FALHOU: produto apagado deixou % vinculos', v_n; end if;
  -- e o chunk continua la: o vinculo e que morre, nao o conhecimento
  if not exists (select 1 from brain.document_chunks where id = v_chunk) then raise exception 'RAG-H10 FALHOU: chunk sumiu com o produto'; end if;
  raise notice ' RAG-H10) OK: FK em public.products; sem duplicata; produto inexistente recusado; nenhum gatilho do brain no ERP; inativar mantem, apagar leva o vinculo e preserva o chunk';
end
$$;

-- ════════════════════════════════════════════════════════════
-- RAG-H11 — sincronizacao pos-deploy do limiar trigram
-- ════════════════════════════════════════════════════════════
-- Em producao o Supabase gerenciado recusou `create function ... set
-- pg_trgm.word_similarity_threshold = 0.35`; a funcao passou a fixar o
-- limiar com set_config(..., true) dentro da execucao. Este teste prova que
-- o arquivo versionado e o que esta em producao e que o comportamento e o
-- aprovado no Lote A.
do $$
declare v_cfg text[]; v_vol "char"; v_md5 text; v_antes text; v_durante text; v_sim real; r record; v_n int;
begin
  reset role;
  select p.proconfig, p.provolatile, md5(pg_get_functiondef(p.oid)) into v_cfg, v_vol, v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.proname = 'search_knowledge';
  -- 1. nenhum GUC de extensao na declaracao da funcao; so o search_path vazio
  if exists (select 1 from unnest(v_cfg) c where c like 'pg_trgm.%') then raise exception 'RAG-H11 FALHOU: SET pg_trgm na declaracao'; end if;
  if v_cfg <> array['search_path=""'] then raise exception 'RAG-H11 FALHOU: proconfig = %', v_cfg; end if;
  -- 2. volatile (altera configuracao de sessao), nao stable
  if v_vol <> 'v' then raise exception 'RAG-H11 FALHOU: volatilidade = %', v_vol; end if;
  -- 3. corpo byte a byte igual ao aplicado em producao em 12/09/2026
  if v_md5 <> '3b54175bfd5a335ff737b799ca3eb3b6' then raise exception 'RAG-H11 FALHOU: definicao diverge da producao (md5 %)', v_md5; end if;

  -- 4. limiar efetivo 0,35 durante a execucao: 'kw7710' tem similaridade 0,50
  --    com o chunk KWZ7710 — passa em 0,35 e NAO passaria no default 0,6.
  v_sim := extensions.word_similarity('kw7710', 'ponta kwz7710 de ceramica para herbicida glifox, vazao calibrada.');
  if v_sim < 0.35 or v_sim >= 0.6 then raise exception 'RAG-H11 FALHOU: similaridade de controle = %', v_sim; end if;
  v_antes := current_setting('pg_trgm.word_similarity_threshold', true);
  perform set_config('request.jwt.claim.sub', '34343434-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select * into r from brain.search_knowledge('kw7710') limit 1;
  if r.chunk_id is null or r.rank_trgm is null then raise exception 'RAG-H11 FALHOU: trigram a 0,35 nao achou KWZ7710: %', to_jsonb(r); end if;
  -- e o mesmo termo, com o limiar em 0,6, nao acha por trigram (prova de que e o 0,35 que decide)
  perform set_config('pg_trgm.word_similarity_threshold', '0.6', true);
  select count(*) into v_n from brain.document_chunks where 'kw7710' operator(extensions.<%) content_norm;
  if v_n <> 0 then raise exception 'RAG-H11 FALHOU: controle a 0,6 achou %', v_n; end if;
  -- 5. a funcao (re)fixa 0,35 a cada chamada, mesmo depois de alguem mexer no GUC
  select * into r from brain.search_knowledge('kw7710') limit 1;
  if r.rank_trgm is null then raise exception 'RAG-H11 FALHOU: nao refixou o limiar'; end if;
  v_durante := current_setting('pg_trgm.word_similarity_threshold', true);
  if v_durante <> '0.35' then raise exception 'RAG-H11 FALHOU: limiar apos a chamada = %', v_durante; end if;
  perform set_config('role', 'none', true); reset role;
  raise notice ' RAG-H11) OK: sem SET na declaracao, volatile, corpo = producao (md5 %), limiar 0,35 efetivo (controle: 0,50 passa; a 0,6 nao), refixado a cada chamada; antes da chamada era %', v_md5, coalesce(v_antes, '(default)');
end
$$;

-- 6. o set_config e LOCAL a transacao: o bloco anterior terminou e o limiar
--    voltou ao default (0,6) — nada vaza entre transacoes.
do $$
declare v_agora text;
begin
  v_agora := current_setting('pg_trgm.word_similarity_threshold', true);
  if v_agora = '0.35' then raise exception 'RAG-H11b FALHOU: limiar vazou para outra transacao (%)', v_agora; end if;
  raise notice ' RAG-H11b) OK: em nova transacao o limiar e % — nada vazou', coalesce(v_agora, '(default)');
end
$$;

reset role;

-- Limpeza: so o que esta suite criou.
delete from brain.documents where id in ('34343434-0000-4000-8000-0000000000d1','34343434-0000-4000-8000-0000000000d2','34343434-0000-4000-8000-0000000000d3','34343434-0000-4000-8000-0000000000d4');
delete from brain.knowledge_sources where key in ('h_fab', 'h_int', 'h_adm', 'h_vazia');
delete from public.products where id = '34343434-0000-4000-8000-0000000000e1';
delete from auth.users where id in ('34343434-0000-4000-8000-000000000001','34343434-0000-4000-8000-000000000002','34343434-0000-4000-8000-000000000003');
