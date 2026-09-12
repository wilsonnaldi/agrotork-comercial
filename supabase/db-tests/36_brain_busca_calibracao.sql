-- ============================================================
-- 36 · BRAIN Fase 2, Lote B — calibração da busca (migration 20260912040000)
-- ============================================================
-- O que o piloto Magnojet V41 encontrou na busca do Lote A, reproduzido em
-- sintético (nenhum documento real):
--
--   C1  query_codes: código dentro de frase, com pontuação; "M 714", "MJ059/1",
--       "MUG-CV 02", 7–9 dígitos; rótulo de versão (V41) NÃO é código
--   C2  query_terms: palavras de conteúdo sem stopwords; lexemas sem números curtos
--   C3  código dentro de frase longa aciona o braço exato ("qual catálogo sustenta a PS983CAP?")
--   C4  code intent guard: código inexistente → ZERO (nada de trigram de prosa);
--       código externo não ingerido (466113200) → ZERO
--   C5  fuzzy de código: "PS981CA" (uma letra a menos) acha PS981CAP; "PS999CAP" não
--   C6  pergunta natural sem código: cobertura de lexemas acha o bloco certo
--       ("cone vazio ultra grossa aproximadamente 0,8 L/min"); título de página
--       ("SOL ULTRA GROSSA CONE VAZIO") acha pelo heading
--   C7  evidência mínima: pergunta sem termo em comum → ZERO; um rank isolado
--       de trigram fraco não vira hit (stopwords não contam)
--   C8  pressão / vazão com código: "PS981CAP 40 psi 2,76 bar", "PS981CAP 0,77 L/min" → a tabela
--   C9  segurança: novas funções security invoker, search_path vazio, anon sem EXECUTE;
--       vendedor ativo vê público; usuário inativo → vazio; anon não executa brain_search
--   C10 filtros continuam valendo (source_key errado → zero) e superseded só sob pedido
--
-- Prefixo de UUID = 36. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('36363636-0000-4000-8000-000000000001','cal.admin@teste.local', '{"full_name":"Admin Calibracao"}'),
 ('36363636-0000-4000-8000-000000000002','cal.vend@teste.local',  '{"full_name":"Vendedor Calibracao"}'),
 ('36363636-0000-4000-8000-000000000003','cal.inat@teste.local',  '{"full_name":"Inativo Calibracao"}');
update public.profiles set role = 'admin' where id = '36363636-0000-4000-8000-000000000001';
update public.profiles set is_active = false where id = '36363636-0000-4000-8000-000000000003';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('solcal', 'Pontas Sol (calibracao)', 'manufacturer', 'public', 'allowed');
insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('36363636-0000-4000-8000-0000000000d1', 'solcal', 'solcal-catalogo', 'Catálogo Sol', 'catalog', 'public');

-- Conteudo no formato lote-b.2: chunk `heading` com o titulo da pagina, texto com
-- heading_path completo, tabela reconstruida (colunas L_ha@<km/h> individuais).
do $$
declare v uuid; i uuid;
begin
  v := brain.register_version('36363636-0000-4000-8000-0000000000d1', 'V41', repeat('c4', 32), 'catalogo_cal.pdf', 'application/pdf', 4000, '2026-06-05', 3);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-36', false, 3, false);
  perform brain.ingestion_add_page(i, 1, 'PONTAS SOL INSTITUCIONAL Fundada em 1985, a Pontas Sol desenvolve pontas de pulverização com núcleo de cerâmica.', 'text_layer');
  perform brain.ingestion_add_page(i, 2, 'APLICAÇÕES DE HERBICIDAS SISTÊMICOS SOL ULTRA GROSSA CONE VAZIO CLASSIFICAÇÃO DE GOTAS Ponta de cerâmica com alta durabilidade.', 'text_layer');
  perform brain.ingestion_add_page(i, 3, 'FILTROS Filtro de sucção M 714 com elemento M 691/1 malha 50. Manômetro: a faixa de operação deve ser adequada à pressão de trabalho.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'heading', 1, 1, E'PONTAS SOL\nINSTITUCIONAL', '{"PONTAS SOL","INSTITUCIONAL"}');
  perform brain.ingestion_add_chunk(i, 1, 'text', 1, 1, 'Fundada em 1985, a Pontas Sol desenvolve pontas de pulverização com núcleo de cerâmica, elevando os padrões de precisão e durabilidade.', '{"PONTAS SOL","INSTITUCIONAL"}');
  perform brain.ingestion_add_chunk(i, 2, 'heading', 2, 2, E'APLICAÇÕES DE HERBICIDAS SISTÊMICOS\nSOL ULTRA GROSSA\nCONE VAZIO\nCLASSIFICAÇÃO DE GOTAS', '{"APLICAÇÕES DE HERBICIDAS SISTÊMICOS","SOL ULTRA GROSSA","CONE VAZIO","CLASSIFICAÇÃO DE GOTAS"}');
  perform brain.ingestion_add_chunk(i, 3, 'text', 2, 2, 'Ponta de cerâmica com alta durabilidade e excepcional resistência ao desgaste por abrasão. Recomendado para herbicidas sistêmicos.', '{"APLICAÇÕES DE HERBICIDAS SISTÊMICOS","SOL ULTRA GROSSA","CONE VAZIO","CLASSIFICAÇÃO DE GOTAS"}');
  perform brain.ingestion_add_chunk(i, 4, 'table', 2, 2,
    E'LITROS POR HECTARE (ESPAÇAMENTO 50CM)\nCÓDIGO PONTAS GOTAS BAR PSI kPa L/min 10 km/h 12 km/h 14 km/h\nPS981CAP SOL-CV 02 MALHA 50 UG 2,07 bar 30 psi 207 kPa 0,66 L/min 80 L/ha 66 L/ha 57 L/ha\nPS981CAP SOL-CV 02 MALHA 50 UG 2,76 bar 40 psi 276 kPa 0,77 L/min 92 L/ha 77 L/ha 66 L/ha\nPS982CAP SOL-CV 025 MALHA 50 UG 2,07 bar 30 psi 207 kPa 0,83 L/min 100 L/ha 83 L/ha 71 L/ha\nPS983CAP SOL-CV 03 MALHA 50 UG 2,76 bar 40 psi 276 kPa 1,15 L/min 138 L/ha 115 L/ha 99 L/ha',
    '{"APLICAÇÕES DE HERBICIDAS SISTÊMICOS","SOL ULTRA GROSSA","CONE VAZIO","CLASSIFICAÇÃO DE GOTAS"}',
    jsonb_build_object('page', 2,
      'headers', jsonb_build_array('CODIGO_PONTAS','GOTAS','BAR','PSI','kPa','L/min','L_ha@10','L_ha@12','L_ha@14'),
      'labels',  jsonb_build_array('CÓDIGO PONTAS','GOTAS','BAR','PSI','kPa','L/min','10 km/h','12 km/h','14 km/h'),
      'groups',  jsonb_build_array(null,null,null,null,null,null,'LITROS POR HECTARE (ESPAÇAMENTO 50CM)','LITROS POR HECTARE (ESPAÇAMENTO 50CM)','LITROS POR HECTARE (ESPAÇAMENTO 50CM)'),
      'units',   jsonb_build_object('BAR','bar','PSI','psi','kPa','kPa','L/min','L/min','L_ha@10','L/ha','L_ha@12','L/ha','L_ha@14','L/ha'),
      'rows',    jsonb_build_array(
                   jsonb_build_array('PS981CAP SOL-CV 02 MALHA 50','UG',2.07,30,207,0.66,80,66,57),
                   jsonb_build_array('PS981CAP SOL-CV 02 MALHA 50','UG',2.76,40,276,0.77,92,77,66),
                   jsonb_build_array('PS982CAP SOL-CV 025 MALHA 50','UG',2.07,30,207,0.83,100,83,71),
                   jsonb_build_array('PS983CAP SOL-CV 03 MALHA 50','UG',2.76,40,276,1.15,138,115,99)),
      'notes', jsonb_build_array('reconstruction: spatial')),
    '{"PS981CAP","PS982CAP","PS983CAP","SOL-CV02","SOL-CV025","SOL-CV03"}');
  perform brain.ingestion_add_chunk(i, 5, 'text', 3, 3, 'Filtro de sucção M 714 com elemento M 691/1 malha 50. Manômetro: a faixa de operação deve ser adequada à pressão de trabalho do pulverizador.', '{"FILTROS"}', null, '{"M714","M691/1"}');
  perform brain.ingestion_finish(i, 'completed', null, '[]'::jsonb, jsonb_build_object('extract_ms', 10, 'chunk_ms', 1));
  update brain.document_versions set status = 'active' where id = v;
end $$;

-- ════════════════════════════════════════════════════════════
-- C1 / C2 — reconhecimento de código e de termos na pergunta
-- ════════════════════════════════════════════════════════════
do $$
declare c text[]; t record;
begin
  reset role;
  c := brain.query_codes('qual catálogo sustenta a PS983CAP?');
  if c <> '{PS983CAP}' then raise exception 'C1 FALHOU: pontuacao destruiu o codigo: %', c; end if;
  c := brain.query_codes('vazão do PS981CAP, e do filtro M 714 (elemento M 691/1A) e do sensor 466113200');
  if not (c @> '{PS981CAP,M714,M691/1A,466113200}') then raise exception 'C1 FALHOU: faltou codigo em %', c; end if;
  c := brain.query_codes('ponta MJ059/1 serie MUG-CV 02 e MAG CH 0.5');
  if not (c @> '{MJ059/1,MUG-CV02,MAGCH0.5}') then raise exception 'C1 FALHOU: slash/espaco: %', c; end if;
  c := brain.query_codes('o que mudou no catálogo V41?');
  if c <> '{}' then raise exception 'C1 FALHOU: rotulo de versao virou codigo: %', c; end if;
  c := brain.query_codes('Qual o manual da semeadora Kuhn?');
  if c <> '{}' then raise exception 'C1 FALHOU: prosa virou codigo: %', c; end if;
  c := brain.query_codes('preço R$ 165.500,00 em 2026 a 40 psi');
  if c <> '{}' then raise exception 'C1 FALHOU: preco/ano/pressao virou codigo: %', c; end if;
  raise notice ' C1) OK: codigo reconhecido dentro de frase e com pontuacao (PS983CAP?, M 714, M 691/1A, MJ059/1, MUG-CV 02, 466113200); V41, prosa, preco e ano nao sao codigo';

  t := brain.query_terms('Qual a faixa de operação do sensor de pressão Arag 466113200?');
  if t.content_words <> 'faixa operacao sensor pressao arag 466113200?' then raise exception 'C2 FALHOU: palavras = %', t.content_words; end if;
  t := brain.query_terms('perto de 0,8 L/min');
  if '0' = any(t.lexemes) or '8' = any(t.lexemes) then raise exception 'C2 FALHOU: numero curto virou lexema: %', t.lexemes; end if;
  if not ('l/min' = any(t.lexemes) or 'min' = any(t.lexemes)) then raise exception 'C2 FALHOU: lexemas = %', t.lexemes; end if;
  t := brain.query_terms('de a o');
  if t.content_words is not null then raise exception 'C2 FALHOU: so stopwords deveria dar nulo'; end if;
  raise notice ' C2) OK: palavras de conteudo sem stopwords; numeros curtos fora dos lexemas; so stopwords → nulo';
end $$;

-- ════════════════════════════════════════════════════════════
-- C3 / C4 / C5 — codigo em frase, code intent guard, fuzzy de codigo
-- ════════════════════════════════════════════════════════════
do $$
declare r record; n int;
begin
  reset role;
  select * into r from brain.search_knowledge('qual catálogo sustenta a PS983CAP?') limit 1;
  if r.chunk_id is null or r.page_from <> 2 or r.rank_exact is null or r.kind <> 'table' then raise exception 'C3 FALHOU: %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('Em qual catálogo aparece a ponta PS983CAP? Preciso citar a página.') limit 1;
  if r.chunk_id is null or r.page_from <> 2 or r.rank_exact is null then raise exception 'C3 FALHOU (frase longa): %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('filtro M 714, qual elemento?') limit 1;
  if r.chunk_id is null or r.page_from <> 3 or not ('M714' = any(r.codes)) then raise exception 'C3 FALHOU (M 714): %', to_jsonb(r); end if;
  raise notice ' C3) OK: codigo dentro de frase (curta e longa, com pontuacao) aciona o braco exato: PS983CAP → p.2 (tabela); M 714 → p.3';

  select count(*) into n from brain.search_knowledge('PS999CAP'); if n <> 0 then raise exception 'C4 FALHOU: PS999CAP devolveu %', n; end if;
  select count(*) into n from brain.search_knowledge('Qual a vazão da ponta Sol PS999CAP?'); if n <> 0 then raise exception 'C4 FALHOU: frase com codigo inexistente devolveu % (caiu para trigram de prosa)', n; end if;
  select count(*) into n from brain.search_knowledge('Qual a faixa de operação do sensor de pressão Arag 466113200?'); if n <> 0 then raise exception 'C4 FALHOU: 466113200 devolveu % — "faixa de operacao" e "pressao" existem no texto, mas o codigo nao', n; end if;
  select count(*) into n from brain.search_knowledge('466113200'); if n <> 0 then raise exception 'C4 FALHOU: 466113200 sozinho devolveu %', n; end if;
  raise notice ' C4) OK: code intent guard — codigo inexistente (PS999CAP) e codigo externo nao ingerido (466113200) → ZERO, mesmo com palavras da pergunta presentes no texto';

  select * into r from brain.search_knowledge('PS981CA') limit 1;
  if r.chunk_id is null or not ('PS981CAP' = any(r.codes)) then raise exception 'C5 FALHOU: fuzzy de codigo nao achou PS981CAP: %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('qual vazão da PS981CA?') limit 1;
  if r.chunk_id is null or not ('PS981CAP' = any(r.codes)) then raise exception 'C5 FALHOU (frase): %', to_jsonb(r); end if;
  if extensions.similarity('PS999CAP', 'PS981CAP') >= 0.6 then raise exception 'C5 FALHOU: limiar 0,6 deixaria PS999CAP casar PS981CAP (%)', extensions.similarity('PS999CAP', 'PS981CAP'); end if;
  if extensions.similarity('PS983CAP', 'PS981CAP') >= 0.6 then raise exception 'C5 FALHOU: irmaos PS983CAP/PS981CAP casariam (%)', extensions.similarity('PS983CAP', 'PS981CAP'); end if;
  raise notice ' C5) OK: fuzzy CODIGO x CODIGO: PS981CA (letra faltando) acha PS981CAP; PS999CAP e o irmao PS983CAP ficam abaixo de 0,6';
end $$;

-- ════════════════════════════════════════════════════════════
-- C6 / C7 / C8 — pergunta natural: cobertura, heading, evidencia minima, pressao/vazao
-- ════════════════════════════════════════════════════════════
do $$
declare r record; n int;
begin
  reset role;
  select * into r from brain.search_knowledge('cone vazio ultra grossa aproximadamente 0,8 L/min') limit 1;
  if r.chunk_id is null or r.page_from <> 2 then raise exception 'C6 FALHOU (natural): %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('Qual ponta Sol de cone vazio ultra grossa entrega perto de 0,8 L/min?') limit 1;
  if r.chunk_id is null or r.page_from <> 2 then raise exception 'C6 FALHOU (pergunta 1 do golden): %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('SOL ULTRA GROSSA CONE VAZIO') limit 1;
  if r.chunk_id is null or r.page_from <> 2 or r.kind <> 'heading' then raise exception 'C6 FALHOU (heading): %', to_jsonb(r); end if;
  raise notice ' C6) OK: pergunta natural sem codigo acha a p.2 por cobertura de lexemas (titulo da pagina + tabela); o titulo "SOL ULTRA GROSSA CONE VAZIO" devolve o chunk heading da p.2';

  select count(*) into n from brain.search_knowledge('Qual o manual da semeadora Kuhn?'); if n <> 0 then raise exception 'C7 FALHOU: Kuhn devolveu %', n; end if;
  select count(*) into n from brain.search_knowledge('qual a garantia do drone com bateria de reserva?'); if n <> 0 then raise exception 'C7 FALHOU: pergunta sem termo em comum devolveu %', n; end if;
  -- palavras parecidas mas ausentes: nem trigram (< 0,35 sobre palavras de conteudo) nem lexema → zero
  select count(*) into n from brain.search_knowledge('prensa operacion sensorial'); if n <> 0 then raise exception 'C7 FALHOU: palavras parecidas sem lexema em comum devolveram %', n; end if;
  -- uma palavra-chave sozinha e busca legitima: acha por FTS estrito (nao por trigram fraco)
  select * into r from brain.search_knowledge('pressão') limit 1;
  if r.chunk_id is null or r.rank_fts is null then raise exception 'C7 FALHOU: palavra-chave unica deveria achar por FTS: %', to_jsonb(r); end if;
  raise notice ' C7) OK: evidencia minima — sem termo em comum → zero; palavras parecidas sem lexema → zero; palavra-chave unica acha por FTS estrito, nunca por trigram isolado';

  select * into r from brain.search_knowledge('PS981CAP 40 psi 2,76 bar') limit 1;
  if r.chunk_id is null or r.kind <> 'table' or r.page_from <> 2 then raise exception 'C8 FALHOU (pressao): %', to_jsonb(r); end if;
  select * into r from brain.search_knowledge('PS981CAP 0,77 L/min') limit 1;
  if r.chunk_id is null or r.kind <> 'table' then raise exception 'C8 FALHOU (vazao): %', to_jsonb(r); end if;
  select (row_ ->> 7)::numeric into n
    from brain.search_knowledge('PS981CAP 40 psi L/ha a 12 km/h') h, jsonb_array_elements(h.table_data -> 'rows') row_
   where h.kind = 'table' and row_ ->> 0 like 'PS981CAP%' and (row_ ->> 3)::numeric = 40 limit 1;
  if n <> 77 then raise exception 'C8 FALHOU (L_ha@12): %', n; end if;
  if (select h.table_data -> 'headers' ->> 7 from brain.search_knowledge('PS981CAP 40 psi') h where h.kind = 'table' limit 1) <> 'L_ha@12' then raise exception 'C8 FALHOU: coluna L_ha@12 nao esta na posicao esperada'; end if;
  raise notice ' C8) OK: pressao (40 psi / 2,76 bar) e vazao (0,77 L/min) com codigo → a tabela da p.2; L_ha@12 = 77 numerico no JSONB';
end $$;

-- ════════════════════════════════════════════════════════════
-- C9 / C10 — seguranca, filtros
-- ════════════════════════════════════════════════════════════
do $$
declare r record; n int; v_bad text := '';
begin
  reset role;
  for r in
    select n.nspname, p.proname, p.prosecdef, p.proconfig,
           has_function_privilege('anon', p.oid, 'execute') as anon_x, has_function_privilege('authenticated', p.oid, 'execute') as auth_x
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'brain' and p.proname in ('query_codes', 'query_terms', 'search_knowledge')
  loop
    if r.prosecdef then v_bad := v_bad || r.proname || ':definer '; end if;
    if r.proconfig is null or not ('search_path=""' = any(r.proconfig)) then v_bad := v_bad || r.proname || ':search_path '; end if;
    if r.anon_x then v_bad := v_bad || r.proname || ':anon '; end if;
    if not r.auth_x then v_bad := v_bad || r.proname || ':sem-authenticated '; end if;
  end loop;
  if v_bad <> '' then raise exception 'C9 FALHOU: %', v_bad; end if;
  if (select provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'brain' and p.proname = 'search_knowledge') <> 'v' then
    raise exception 'C9 FALHOU: search_knowledge deixou de ser VOLATILE (set_config)';
  end if;

  -- vendedor ativo ve o documento publico, pela porta do app
  perform set_config('request.jwt.claim.sub', '36363636-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.brain_search('qual catálogo sustenta a PS983CAP?'); if n < 1 then raise exception 'C9 FALHOU: vendedor ativo nao ve conteudo publico'; end if;
  select count(*) into n from public.brain_search('PS999CAP'); if n <> 0 then raise exception 'C9 FALHOU: vendedor recebeu resultado para codigo inexistente'; end if;
  perform set_config('role', 'none', true); reset role;
  -- usuario inativo: vazio, sem erro, sem trilha
  perform set_config('request.jwt.claim.sub', '36363636-0000-4000-8000-000000000003', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.brain_search('qual catálogo sustenta a PS983CAP?'); if n <> 0 then raise exception 'C9 FALHOU: inativo recebeu %', n; end if;
  perform set_config('role', 'none', true); reset role;
  select count(*) into n from brain.knowledge_queries where user_id = '36363636-0000-4000-8000-000000000003'; if n <> 0 then raise exception 'C9 FALHOU: inativo deixou trilha'; end if;
  -- anon nao executa
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
  begin perform public.brain_search('PS983CAP'); raise exception 'C9 FALHOU: anon executou brain_search';
  exception when insufficient_privilege then null; end;
  perform set_config('role', 'none', true); reset role;
  raise notice ' C9) OK: query_codes/query_terms/search_knowledge invoker + search_path vazio + anon sem EXECUTE; VOLATILE mantido; vendedor ativo ve publico e recebe zero para codigo inexistente; inativo → vazio sem trilha; anon nao executa';

  select count(*) into n from brain.search_knowledge('PS983CAP', '{"source_key":"outra"}'); if n <> 0 then raise exception 'C10 FALHOU: filtro source_key ignorado'; end if;
  select count(*) into n from brain.search_knowledge('PS983CAP', '{"source_key":"solcal"}'); if n < 1 then raise exception 'C10 FALHOU: filtro source_key certo nao devolve'; end if;
  select count(*) into n from brain.search_knowledge('PS983CAP', '{"kind":"heading"}'); if n <> 0 then raise exception 'C10 FALHOU: filtro kind ignorado'; end if;
  begin perform brain.search_knowledge('x', '{"nada":1}'); raise exception 'C10 FALHOU: filtro desconhecido aceito';
  exception when invalid_parameter_value then null; end;
  raise notice ' C10) OK: filtros (source_key, kind) e validacao de filtro continuam valendo na funcao calibrada';
end $$;

-- ── limpeza ─────────────────────────────────────────────────
reset role;
delete from brain.knowledge_queries where user_id in ('36363636-0000-4000-8000-000000000001','36363636-0000-4000-8000-000000000002','36363636-0000-4000-8000-000000000003');
delete from brain.documents where id = '36363636-0000-4000-8000-0000000000d1';
delete from brain.knowledge_sources where key = 'solcal';
delete from auth.users where id in ('36363636-0000-4000-8000-000000000001','36363636-0000-4000-8000-000000000002','36363636-0000-4000-8000-000000000003');
