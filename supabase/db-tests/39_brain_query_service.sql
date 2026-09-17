-- ============================================================
-- 39 · BRAIN Fase 2 — Query Service e Console v0
-- ============================================================
-- Esta suite exercita a MESMA porta que o aplicativo usa: `public.brain_search`
-- e `public.brain_provenance`. Nao testa `brain.search_knowledge` direto de
-- proposito — o que o Console mostra passa por esta funcao, e e ela que
-- registra a trilha da consulta.
--
-- A escada de acesso, que e o centro de tudo aqui:
--   public < internal < commercial < admin
--   admin       -> nivel `admin`      ve tudo
--   salesperson -> nivel `internal`   ve `public` e `internal`, e SO isso
--   inativo/anonimo -> nivel NULL     nao ve nada e nao gera trilha
--
-- Ou seja: um documento `commercial` (o orcamento interno ARAG e assim em
-- producao) e invisivel para o vendedor. Isso nao e efeito colateral, e o
-- desenho — e o teste Q8 existe para que ninguem o "conserte" sem querer.
--
--   Q1  anonimo               -> zero, e nenhuma linha na trilha
--   Q2  vendedor              -> ve o publico
--   Q3  admin                 -> ve o publico e o restrito
--   Q4  usuario inativo       -> zero (o perfil desligado nao vira nivel)
--   Q7  pergunta com codigo   -> trecho certo, pelo braco exato
--   Q8  restrito x vendedor   -> zero, sem revelar que o documento existe
--   Q9  codigo inexistente    -> zero
--  Q10  documento ausente     -> zero (a pergunta de um lote nao ingerido)
--  Q11  assunto ausente       -> zero (marca que nunca entrou)
--  Q13  tabela degradada      -> nunca e evidencia, nem para admin
--  Q14  versao superseded     -> fora da busca normal; dentro so quando pedida
--  Q15  trilha da consulta    -> usuario, nivel, texto, hits, chunks, duracao
--  Q16  proveniencia          -> citacao pronta, sem nada alem do combinado
--
-- Prefixo de UUID = 39. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('39393939-0000-4000-8000-000000000001','qs.admin@teste.local',    '{"full_name":"Admin Consulta"}'),
 ('39393939-0000-4000-8000-000000000002','qs.vendedor@teste.local', '{"full_name":"Vendedor Consulta"}'),
 ('39393939-0000-4000-8000-000000000003','qs.inativo@teste.local',  '{"full_name":"Vendedor Desligado"}');
update public.profiles set role = 'admin'       where id = '39393939-0000-4000-8000-000000000001';
update public.profiles set role = 'salesperson' where id = '39393939-0000-4000-8000-000000000002';
update public.profiles set role = 'salesperson', is_active = false where id = '39393939-0000-4000-8000-000000000003';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('qs_fab',  'Fabricante Consulta', 'manufacturer', 'public',     'allowed'),
 ('qs_casa', 'Documentos da casa',  'internal',     'commercial', 'forbidden');

insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('39393939-0000-4000-8000-0000000000d1', 'qs_fab',  'qs-catalogo',  'Catálogo Consulta',           'catalog',       'public'),
 ('39393939-0000-4000-8000-0000000000d2', 'qs_casa', 'qs-orcamento', 'Orçamento interno Consulta',  'internal_note', 'commercial');

-- ── conteudo ────────────────────────────────────────────────
do $$
declare v uuid; i uuid; v_velha uuid;
begin
  -- Catalogo publico, V2 vigente
  v_velha := brain.register_version('39393939-0000-4000-8000-0000000000d1', 'V1', repeat('91', 32), 'cat_v1.pdf', 'application/pdf', 3000, '2026-01-10', 1);
  i := brain.ingestion_start(v_velha, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-39', false, 1, false);
  perform brain.ingestion_add_page(i, 1, 'EDICAO ANTIGA Ponta QS550CAP de cone vazio, vazao antiga.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1,
    'Ponta QS550CAP de cone vazio: vazao de 0,55 litro por minuto a 40 psi na edicao antiga.',
    '{"EDICAO ANTIGA"}', null, '{"QS550CAP"}');
  perform brain.ingestion_finish(i, 'completed');

  v := brain.register_version('39393939-0000-4000-8000-0000000000d1', 'V2', repeat('92', 32), 'cat_v2.pdf', 'application/pdf', 3200, '2026-06-05', 2);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-39', false, 2, false);
  perform brain.ingestion_add_page(i, 1, 'PONTAS Ponta QS981CAP de cone vazio para herbicida sistemico.', 'text_layer');
  perform brain.ingestion_add_page(i, 2, 'TABELAS Tabela tecnica de vazao por pressao.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1,
    'Ponta QS981CAP de cone vazio para aplicacao de herbicida sistemico em barra de pulverizacao.',
    '{"PONTAS"}', null, '{"QS981CAP"}');
  -- tabela CONFIAVEL
  perform brain.ingestion_add_chunk(i, 1, 'table', 2, 2,
    'QS981CAP 2,76 bar 40 psi 0,77 L/min', '{"TABELAS"}',
    '{"audit": {"fatal": false, "issues": [], "quality": "trusted"}, "rows": [["QS981CAP", "2,76", "40", "0,77"]]}'::jsonb,
    '{"QS981CAP"}');
  -- tabela DEGRADADA: carrega um codigo que NAO existe em nenhum trecho confiavel.
  -- E o unico lugar onde QS777CAP aparece — se a busca devolver, vazou.
  perform brain.ingestion_add_chunk(i, 2, 'table', 2, 2,
    'QS777CAP valores fundidos ilegiveis', '{"TABELAS"}',
    '{"audit": {"fatal": true, "issues": ["numeros fundidos"], "quality": "degraded"}, "rows": [["QS777CAP", "?"]]}'::jsonb,
    '{"QS777CAP"}');
  perform brain.ingestion_finish(i, 'completed');

  update brain.document_versions set status = 'active', valid_from = '2026-01-10' where id = v_velha;
  update brain.document_versions set status = 'active', valid_from = '2026-06-05' where id = v;

  -- Orcamento COMERCIAL: o vendedor (nivel internal) nao alcanca
  v := brain.register_version('39393939-0000-4000-8000-0000000000d2', '2026-09', repeat('93', 32), 'orc.pdf', 'application/pdf', 1200, '2026-09-01', 1);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-39', false, 1, false);
  perform brain.ingestion_add_page(i, 1, 'ORCAMENTO Sensor QS466113200 com margem da casa.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1,
    'Sensor de pressao QS466113200 com custo de aquisicao e margem praticada pela casa.',
    '{"ORCAMENTO"}', null, '{"QS466113200"}');
  perform brain.ingestion_finish(i, 'completed');
  update brain.document_versions set status = 'active', valid_from = '2026-09-01' where id = v;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q1 · anonimo: zero, e sem trilha
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_trilha_antes int; v_trilha_depois int; v_barrado text := 'nao';
begin
  reset role;
  select count(*) into v_trilha_antes from brain.knowledge_queries;
  -- `anon` nem tem EXECUTE (revoke explicito na 20260912030000): a recusa vem
  -- ANTES do corpo da funcao. Se um dia o grant mudar, o corpo ainda fecha
  -- sozinho (`auth.uid()` nulo devolve zero) — as duas cercas sao aceitas
  -- aqui, e a unica coisa inaceitavel e evidencia.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
  begin
    select count(*) into v_n from public.brain_search('QS981CAP');
  exception when insufficient_privilege then v_barrado := 'sim'; v_n := 0;
  end;
  perform set_config('role', 'none', true); reset role;
  if v_n <> 0 then raise exception 'Q1 FALHOU: anonimo recebeu % evidencia(s)', v_n; end if;
  select count(*) into v_trilha_depois from brain.knowledge_queries;
  if v_trilha_depois <> v_trilha_antes then
    raise exception 'Q1 FALHOU: consulta anonima gravou trilha (% -> %)', v_trilha_antes, v_trilha_depois; end if;
  if not has_function_privilege('anon', 'public.brain_search(text, jsonb, integer, boolean)', 'execute') is false then
    raise exception 'Q1 FALHOU: anon ficou com EXECUTE em brain_search';
  end if;
  raise notice ' Q1) OK: anônimo não recebe evidência e não gera trilha (barrado no GRANT: %)', v_barrado;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q2/Q7/Q8/Q9/Q11 · o vendedor
-- ════════════════════════════════════════════════════════════
do $$
declare r record; v_n int;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '39393939-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  -- Q2/Q7) pergunta com codigo devolve o trecho certo, pelo braco exato
  select * into r from public.brain_search('qual a vazao da QS981CAP a 40 psi?') limit 1;
  if r.chunk_id is null then raise exception 'Q2 FALHOU: vendedor nao recebeu o catalogo publico'; end if;
  if r.rank_exact is null then raise exception 'Q7 FALHOU: codigo nao respondeu pelo braco exato'; end if;
  if r.source_key <> 'qs_fab' or r.version_label <> 'V2' then
    raise exception 'Q7 FALHOU: veio de % %', r.source_key, r.version_label; end if;
  raise notice ' Q2/Q7) OK: vendedor recebe o catálogo público — % %, p. % (rank_exact=%)', r.title, r.version_label, r.page_from, r.rank_exact;

  -- Q8) o documento COMERCIAL nao existe para ele. Nem o codigo dele.
  select count(*) into v_n from public.brain_search('QS466113200');
  if v_n <> 0 then raise exception 'Q8 FALHOU: vendedor alcancou o documento comercial (% evidencia(s))', v_n; end if;
  select count(*) into v_n from public.brain_search('margem praticada pela casa');
  if v_n <> 0 then raise exception 'Q8 FALHOU: vendedor alcancou o texto do orcamento (%)', v_n; end if;
  -- e a proveniencia direta do chunk tambem nao abre a porta
  select count(*) into v_n from (
    select public.brain_provenance(c.id) p
      from brain.document_chunks c
      join brain.document_versions v on v.id = c.version_id
     where v.document_id = '39393939-0000-4000-8000-0000000000d2') t
   where t.p is not null;
  if v_n <> 0 then raise exception 'Q8 FALHOU: proveniencia do documento comercial respondeu ao vendedor'; end if;
  raise notice ' Q8) OK: documento comercial é indistinguível de inexistente para o vendedor (busca, código e proveniência)';

  -- Q9) codigo que nao existe em lugar nenhum
  select count(*) into v_n from public.brain_search('QS999CAP');
  if v_n <> 0 then raise exception 'Q9 FALHOU: codigo inexistente devolveu %', v_n; end if;
  raise notice ' Q9) OK: código inexistente (QS999CAP) → zero';

  -- Q11) assunto que nunca foi ingerido
  select count(*) into v_n from public.brain_search('qual o manual da semeadora Kuhn?');
  if v_n <> 0 then raise exception 'Q11 FALHOU: assunto ausente devolveu %', v_n; end if;
  select count(*) into v_n from public.brain_search('qual bateria serve para T55 e T70P?');
  if v_n <> 0 then raise exception 'Q11 FALHOU: lote nao ingerido devolveu %', v_n; end if;
  raise notice ' Q11) OK: assunto ausente (Kuhn) e lote não ingerido (T55/T70P) → zero';

  perform set_config('role', 'none', true); reset role;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q3/Q13/Q14 · o admin
-- ════════════════════════════════════════════════════════════
do $$
declare r record; v_n int;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '39393939-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);

  -- Q3) alcanca o comercial
  select * into r from public.brain_search('QS466113200') limit 1;
  if r.chunk_id is null then raise exception 'Q3 FALHOU: admin nao alcancou o documento comercial'; end if;
  if r.access_level <> 'commercial' then raise exception 'Q3 FALHOU: nivel inesperado %', r.access_level; end if;
  raise notice ' Q3) OK: admin alcança o documento comercial (%, nível %)', r.title, r.access_level;
  -- e continua alcancando o publico
  select count(*) into v_n from public.brain_search('QS981CAP');
  if v_n = 0 then raise exception 'Q3 FALHOU: admin perdeu o catalogo publico'; end if;

  -- Q13) tabela degradada nunca e evidencia — nem para quem pode tudo
  select count(*) into v_n from public.brain_search('QS777CAP');
  if v_n <> 0 then raise exception 'Q13 FALHOU: tabela degradada virou evidencia para admin (%)', v_n; end if;
  -- prova de que o fixture nao ficou facil: o trecho existe mesmo
  select count(*) into v_n from brain.document_chunks where 'QS777CAP' = any(codes);
  if v_n <> 1 then raise exception 'Q13 FALHOU: o fixture degradado sumiu (%)', v_n; end if;
  raise notice ' Q13) OK: o único trecho com QS777CAP é degradado e a busca o recusa — existe no banco, não na resposta';

  -- Q14) versao superseded fora da busca normal
  select count(*) into v_n from public.brain_search('QS550CAP');
  if v_n <> 0 then raise exception 'Q14 FALHOU: versao superseded respondeu na busca normal (%)', v_n; end if;
  select count(*) into v_n from public.brain_search('QS550CAP', '{}'::jsonb, 10, true);
  if v_n = 0 then raise exception 'Q14 FALHOU: nem pedindo superseded a V1 aparece'; end if;
  raise notice ' Q14) OK: V1 superseded fica fora da busca normal e só aparece quando pedida (% evidência(s))', v_n;

  perform set_config('role', 'none', true); reset role;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q4 · usuario inativo
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_antes int; v_depois int;
begin
  reset role;
  select count(*) into v_antes from brain.knowledge_queries;
  perform set_config('request.jwt.claim.sub', '39393939-0000-4000-8000-000000000003', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.brain_search('QS981CAP');
  perform set_config('role', 'none', true); reset role;
  if v_n <> 0 then raise exception 'Q4 FALHOU: usuario inativo recebeu % evidencia(s)', v_n; end if;
  select count(*) into v_depois from brain.knowledge_queries;
  if v_depois <> v_antes then raise exception 'Q4 FALHOU: usuario inativo gravou trilha'; end if;
  raise notice ' Q4) OK: perfil desligado não vira nível de acesso — zero, e sem trilha';
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q15 · a trilha da consulta
-- ════════════════════════════════════════════════════════════
do $$
declare r record; v_n int;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '39393939-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.brain_search('vazao da QS981CAP a 40 psi');
  perform set_config('role', 'none', true); reset role;

  select * into r from brain.knowledge_queries
   where user_id = '39393939-0000-4000-8000-000000000002'
   order by created_at desc, id desc limit 1;
  if r.id is null then raise exception 'Q15 FALHOU: a consulta nao deixou trilha'; end if;
  if r.query_text <> 'vazao da QS981CAP a 40 psi' then raise exception 'Q15 FALHOU: texto gravado = %', r.query_text; end if;
  if r.caller_level <> 'internal' then raise exception 'Q15 FALHOU: nivel gravado = % (esperava internal)', r.caller_level; end if;
  if r.hits <> v_n then raise exception 'Q15 FALHOU: hits % <> % devolvidos', r.hits, v_n; end if;
  if cardinality(r.top_chunk_ids) <> v_n then raise exception 'Q15 FALHOU: top_chunk_ids nao bate com hits'; end if;
  if r.duration_ms is null or r.duration_ms < 0 then raise exception 'Q15 FALHOU: duracao invalida'; end if;
  if r.origin <> 'app' then raise exception 'Q15 FALHOU: origem = %', r.origin; end if;
  -- a trilha guarda o que foi PERGUNTADO, nunca o que foi devolvido
  if to_jsonb(r)::text like '%cone vazio%' then raise exception 'Q15 FALHOU: a trilha guardou o conteudo devolvido'; end if;
  raise notice ' Q15) OK: trilha com usuário, nível internal, texto, % hit(s), chunks e % ms — e sem o conteúdo devolvido', r.hits, r.duration_ms;
end
$$;

-- ════════════════════════════════════════════════════════════
-- Q16 · proveniencia pronta para citar
-- ════════════════════════════════════════════════════════════
do $$
declare v_chunk bigint; v_prov jsonb;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '39393939-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select chunk_id into v_chunk from public.brain_search('QS981CAP') limit 1;
  select public.brain_provenance(v_chunk) into v_prov;
  perform set_config('role', 'none', true); reset role;

  if v_prov is null then raise exception 'Q16 FALHOU: proveniencia veio nula para trecho visivel'; end if;
  if v_prov->>'citation' is null then raise exception 'Q16 FALHOU: sem citacao pronta'; end if;
  if v_prov->>'citation' not like '%Catálogo Consulta V2%' then
    raise exception 'Q16 FALHOU: citacao inesperada: %', v_prov->>'citation'; end if;
  raise notice ' Q16) OK: proveniência pronta para citar — "%"', v_prov->>'citation';
end
$$;

-- ── limpeza ─────────────────────────────────────────────────
reset role;
delete from brain.knowledge_queries where user_id in
 ('39393939-0000-4000-8000-000000000001','39393939-0000-4000-8000-000000000002','39393939-0000-4000-8000-000000000003');
delete from brain.documents where id in ('39393939-0000-4000-8000-0000000000d1','39393939-0000-4000-8000-0000000000d2');
delete from brain.knowledge_sources where key in ('qs_fab','qs_casa');
delete from auth.users where id in
 ('39393939-0000-4000-8000-000000000001','39393939-0000-4000-8000-000000000002','39393939-0000-4000-8000-000000000003');
