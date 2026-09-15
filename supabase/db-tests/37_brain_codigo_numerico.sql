-- ============================================================
-- 37 · BRAIN Fase 2 — codigo puramente numerico e EXATO OU NADA
--      (migration 20260915120000_brain_busca_codigo_numerico_exato)
-- ============================================================
-- O defeito que esta suite tranca: o braco fuzzy de codigo (trigram codigo x
-- codigo, limiar 0,6) tratava um digito trocado como erro de digitacao. Em
-- catalogo de peca isso e falso — 466113200 e 466113201 sao pecas diferentes —
-- e a similaridade entre elas passa de 0,6 com folga. Resultado: perguntar por
-- uma peca que NAO esta ingerida devolvia, com rank de codigo, a peca vizinha.
--
--   N1 codigo numerico EXATO responde (o caminho legitimo nao foi quebrado)
--   N2 substituicao de um digito → ZERO         (466113201, 4626216)
--   N3 digito a mais            → ZERO          (46262150, 4661132000)
--   N4 digito a menos           → ZERO          (46611320, 462621)
--   N5 mesmo prefixo, cauda diferente → ZERO    (4626299 vs 4626215)
--   N6 alfanumerico com typo continua achando   (MJ981CA → MJ981CAP)
--   N7 alfanumerico distante continua em ZERO   (MJ999CAP)
--   N8 numerico exato que so existe em tabela DEGRADADA → ZERO (fail-closed
--      continua valendo; e o vizinho numerico confiavel nao entra no lugar)
--   N9 a similaridade bruta dos pares numericos CONTINUA >= 0,6 — ou seja, o
--      zero acima vem da regra nova, nao de o fixture ter ficado facil
--  N10 o par misto (numerico x alfanumerico) nao foi excluido por engano
--  N11 fronteira: fora de 7-9 digitos o numero nao e codigo para query_codes —
--      nenhum rank de codigo sai dai (comportamento antigo, assertado aqui)
--
-- Prefixo de UUID = 37. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('37373737-0000-4000-8000-000000000001','num.admin@teste.local', '{"full_name":"Admin Numerico"}');
update public.profiles set role = 'admin' where id = '37373737-0000-4000-8000-000000000001';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('numcal', 'Pecas Numericas (calibracao)', 'manufacturer', 'public', 'allowed');
insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('37373737-0000-4000-8000-0000000000d1', 'numcal', 'numcal-catalogo', 'Catálogo de Peças Numéricas', 'catalog', 'public');

do $$
declare v uuid; i uuid;
begin
  v := brain.register_version('37373737-0000-4000-8000-0000000000d1', 'V1', repeat('7a', 32), 'pecas_num.pdf', 'application/pdf', 4000, '2026-06-05', 3);
  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-37', false, 3, false);
  perform brain.ingestion_add_page(i, 1, 'PECAS DE REPOSICAO Bico de pulverizacao 466113200 e conjunto 4626215.', 'text_layer');
  perform brain.ingestion_add_page(i, 2, 'ACESSORIOS Ponta MJ981CAP para barra de pulverizacao.', 'text_layer');
  perform brain.ingestion_add_page(i, 3, 'TABELA DEGRADADA Numeros fundidos que a geometria nao resolveu.', 'text_layer');

  -- p.1 — dois codigos puramente numericos, confiaveis
  perform brain.ingestion_add_chunk(i, 0, 'heading', 1, 1, 'PECAS DE REPOSICAO', '{"PECAS DE REPOSICAO"}');
  perform brain.ingestion_add_chunk(i, 1, 'text', 1, 1,
    'Bico de pulverizacao 466113200 em ceramica, para barra de aplicacao de herbicida.',
    '{"PECAS DE REPOSICAO"}', null, '{"466113200"}');
  perform brain.ingestion_add_chunk(i, 2, 'text', 1, 1,
    'Conjunto de vedacao 4626215 com anel de nitrilica e porca de aperto rapido.',
    '{"PECAS DE REPOSICAO"}', null, '{"4626215"}');

  -- p.2 — codigo alfanumerico, confiavel (o fuzzy continua valendo aqui)
  perform brain.ingestion_add_chunk(i, 3, 'text', 2, 2,
    'Ponta MJ981CAP de cone vazio para aplicacao de herbicida sistemico em barra.',
    '{"ACESSORIOS"}', null, '{"MJ981CAP"}');

  -- p.3 — numerico exato que so existe em tabela DEGRADADA, mais um vizinho
  -- numerico confiavel a um digito de distancia (o atalho que nao pode existir)
  perform brain.ingestion_add_chunk(i, 4, 'table', 3, 3,
    E'CÓDIGO ROSCA VAZÃO\n788990100 R 1 1/2 4181 3907',
    '{"TABELA DEGRADADA"}',
    jsonb_build_object('page', 3,
      'headers', jsonb_build_array('CODIGO','ROSCA','VAZAO'), 'labels', jsonb_build_array('CÓDIGO','ROSCA','VAZÃO'),
      'units', jsonb_build_object(), 'groups', jsonb_build_array(),
      'rows', jsonb_build_array(jsonb_build_array('788990100', 'R 1 1/2', '4181 3907')),
      'notes', jsonb_build_array('1 celula(s) com numeros fundidos'),
      'audit', jsonb_build_object('quality', 'degraded', 'fatal', true, 'issues', jsonb_build_array('1 celula(s) com numeros fundidos'))),
    '{"788990100"}');
  perform brain.ingestion_add_chunk(i, 5, 'text', 3, 3,
    'Adaptador 788990101 com rosca de uma polegada e vedacao integrada.',
    '{"TABELA DEGRADADA"}', null, '{"788990101"}');

  perform brain.ingestion_finish(i, 'completed', null, '[]'::jsonb, jsonb_build_object('extract_ms', 10, 'chunk_ms', 1));
  update brain.document_versions set status = 'active' where id = v;
end $$;

-- ════════════════════════════════════════════════════════════
-- N9 — o fixture e mesmo perigoso: os pares numericos passam de 0,6
-- ════════════════════════════════════════════════════════════
do $$
declare s real;
begin
  reset role;
  s := extensions.similarity('466113201', '466113200');
  if s < 0.6 then raise exception 'N9 FALHOU: fixture fraco — 466113201 x 466113200 = % (precisa >= 0,6 para o teste valer)', s; end if;
  s := extensions.similarity('46262150', '4626215');
  if s < 0.6 then raise exception 'N9 FALHOU: fixture fraco — 46262150 x 4626215 = %', s; end if;
  s := extensions.similarity('4626216', '4626215');
  if s < 0.6 then raise exception 'N9 FALHOU: fixture fraco — 4626216 x 4626215 = %', s; end if;
  s := extensions.similarity('788990101', '788990100');
  if s < 0.6 then raise exception 'N9 FALHOU: fixture fraco — 788990101 x 788990100 = %', s; end if;
  raise notice ' N9) OK: os pares numericos do fixture continuam fuzzy-compativeis (>= 0,6) — o zero dos testes abaixo vem da regra, nao de fixture facil';
end $$;

-- ════════════════════════════════════════════════════════════
-- N1..N5 — numerico: exato responde, qualquer variacao devolve ZERO
-- ════════════════════════════════════════════════════════════
do $$
declare r record; n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '37373737-0000-4000-8000-000000000001', true);

  -- N1 exato
  select * into r from brain.search_knowledge('466113200') limit 1;
  if r.chunk_id is null or not ('466113200' = any(r.codes)) then raise exception 'N1 FALHOU: codigo numerico exato 466113200 nao respondeu: %', to_jsonb(r); end if;
  if r.rank_exact is null then raise exception 'N1 FALHOU: 466113200 respondeu sem rank de codigo'; end if;
  select * into r from brain.search_knowledge('4626215') limit 1;
  if r.chunk_id is null or not ('4626215' = any(r.codes)) then raise exception 'N1 FALHOU: codigo numerico exato 4626215 nao respondeu: %', to_jsonb(r); end if;
  -- dentro de frase tambem
  select * into r from brain.search_knowledge('qual a aplicacao do bico 466113200?') limit 1;
  if r.chunk_id is null or not ('466113200' = any(r.codes)) then raise exception 'N1 FALHOU: exato dentro de frase parou de funcionar: %', to_jsonb(r); end if;
  raise notice ' N1) OK: codigo puramente numerico EXATO responde, com rank de codigo, sozinho e dentro de frase';

  -- N2 substituicao de um digito
  select count(*) into n from brain.search_knowledge('466113201');
  if n <> 0 then raise exception 'N2 FALHOU: 466113201 devolveu % linha(s) — o fuzzy numerico ainda existe', n; end if;
  select count(*) into n from brain.search_knowledge('4626216');
  if n <> 0 then raise exception 'N2 FALHOU: 4626216 devolveu % linha(s)', n; end if;
  select count(*) into n from brain.search_knowledge('preciso do bico 466113201 urgente');
  if n <> 0 then raise exception 'N2 FALHOU: 466113201 dentro de frase devolveu % linha(s)', n; end if;
  raise notice ' N2) OK: um digito trocado (466113201, 4626216) devolve ZERO — sozinho e dentro de frase';

  -- N3 digito a mais (dentro da janela de 7 a 9 digitos que query_codes
  --    reconhece como codigo — ver N11 para fora dela)
  select count(*) into n from brain.search_knowledge('46262150');
  if n <> 0 then raise exception 'N3 FALHOU: 46262150 devolveu % linha(s)', n; end if;
  select count(*) into n from brain.search_knowledge('46262159');
  if n <> 0 then raise exception 'N3 FALHOU: 46262159 devolveu % linha(s)', n; end if;
  raise notice ' N3) OK: um digito a mais (46262150, 46262159) devolve ZERO';

  -- N4 digito a menos
  select count(*) into n from brain.search_knowledge('46611320');
  if n <> 0 then raise exception 'N4 FALHOU: 46611320 devolveu % linha(s)', n; end if;
  select count(*) into n from brain.search_knowledge('46613200');
  if n <> 0 then raise exception 'N4 FALHOU: 46613200 devolveu % linha(s)', n; end if;
  raise notice ' N4) OK: um digito a menos (46611320, 46613200) devolve ZERO';

  -- N5 mesmo prefixo, cauda diferente
  select count(*) into n from brain.search_knowledge('4626299');
  if n <> 0 then raise exception 'N5 FALHOU: 4626299 (mesmo prefixo de 4626215) devolveu % linha(s)', n; end if;
  select count(*) into n from brain.search_knowledge('466113299');
  if n <> 0 then raise exception 'N5 FALHOU: 466113299 devolveu % linha(s)', n; end if;
  raise notice ' N5) OK: mesmo prefixo com cauda diferente (4626299, 466113299) devolve ZERO';
end $$;

-- ════════════════════════════════════════════════════════════
-- N6 / N7 / N10 — alfanumerico nao mudou
-- ════════════════════════════════════════════════════════════
do $$
declare r record; n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '37373737-0000-4000-8000-000000000001', true);

  -- N6 typo alfanumerico continua achando por fuzzy
  if extensions.similarity('MJ981CA', 'MJ981CAP') < 0.6 then raise exception 'N6 FALHOU: fixture — MJ981CA x MJ981CAP abaixo de 0,6'; end if;
  select * into r from brain.search_knowledge('MJ981CA') limit 1;
  if r.chunk_id is null or not ('MJ981CAP' = any(r.codes)) then raise exception 'N6 FALHOU: fuzzy alfanumerico legitimo (MJ981CA → MJ981CAP) quebrou: %', to_jsonb(r); end if;
  if r.rank_exact is null then raise exception 'N6 FALHOU: MJ981CA respondeu sem rank de codigo — o braco fuzzy alfanumerico morreu'; end if;
  raise notice ' N6) OK: alfanumerico com um caractere a menos (MJ981CA → MJ981CAP) continua achando por fuzzy, com rank de codigo';

  -- N7 alfanumerico distante continua em zero
  select count(*) into n from brain.search_knowledge('MJ999CAP');
  if n <> 0 then raise exception 'N7 FALHOU: MJ999CAP devolveu % linha(s)', n; end if;
  raise notice ' N7) OK: alfanumerico distante (MJ999CAP) continua devolvendo ZERO';

  -- N10 o par misto nao foi excluido por engano: um codigo alfanumerico da
  -- pergunta contra um codigo numerico do candidato so e barrado se AMBOS forem
  -- numericos. Aqui a pergunta e alfanumerica e nao ha exato: sem candidato
  -- compativel, zero — mas por distancia, nao pela regra nova.
  if extensions.similarity('466113200X', '466113200') < 0.6 then raise exception 'N10 FALHOU: fixture — 466113200X x 466113200 abaixo de 0,6'; end if;
  select * into r from brain.search_knowledge('466113200X') limit 1;
  if r.chunk_id is null or not ('466113200' = any(r.codes)) then raise exception 'N10 FALHOU: par misto (pergunta alfanumerica x candidato numerico) foi barrado por engano: %', to_jsonb(r); end if;
  raise notice ' N10) OK: a regra so barra o par quando os DOIS lados sao digitos — par misto (466113200X → 466113200) continua no fuzzy';
end $$;

-- ════════════════════════════════════════════════════════════
-- N8 — fail-closed de tabela degradada continua valendo no numerico
-- ════════════════════════════════════════════════════════════
do $$
declare n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '37373737-0000-4000-8000-000000000001', true);

  -- 788990100 existe EXATO, mas so na tabela degradada → zero (nem a degradada,
  -- nem o vizinho numerico confiavel 788990101 no lugar dela)
  select count(*) into n from brain.search_knowledge('788990100');
  if n <> 0 then raise exception 'N8 FALHOU: 788990100 (exato so na degradada) devolveu % linha(s)', n; end if;
  select count(*) into n from brain.search_knowledge('788990100', '{}'::jsonb, 100, true);
  if n <> 0 then raise exception 'N8 FALHOU: 788990100 vazou com limite alto e superseded (% linha(s))', n; end if;
  select count(*) into n from brain.search_knowledge('788990100', jsonb_build_object('kind', 'table'));
  if n <> 0 then raise exception 'N8 FALHOU: 788990100 vazou com filtro kind=table (% linha(s))', n; end if;
  select count(*) into n from brain.search_knowledge('788990100', jsonb_build_object('source_key', 'numcal'));
  if n <> 0 then raise exception 'N8 FALHOU: 788990100 vazou com filtro source_key (% linha(s))', n; end if;
  -- e o vizinho continua respondendo pelo proprio codigo exato
  select count(*) into n from brain.search_knowledge('788990101') where '788990101' = any(codes);
  if n < 1 then raise exception 'N8 FALHOU: 788990101 (exato, confiavel) parou de responder'; end if;
  -- nenhuma degradada em lugar nenhum
  select count(*) into n from brain.search_knowledge('rosca vazao', jsonb_build_object('document_id', '37373737-0000-4000-8000-0000000000d1'))
   where kind = 'table' and table_data -> 'audit' ->> 'quality' = 'degraded';
  if n <> 0 then raise exception 'N8 FALHOU: busca natural devolveu a degradada'; end if;
  raise notice ' N8) OK: numerico exato que so existe em tabela degradada devolve ZERO (com limite 100, superseded, kind e source_key) e o vizinho numerico confiavel nao entra no lugar dela';
end $$;

-- ════════════════════════════════════════════════════════════
-- N11 — a fronteira de brain.query_codes, registrada (NAO e o fuzzy de codigo)
-- ════════════════════════════════════════════════════════════
-- query_codes reconhece numero puro como codigo de 7 a 9 digitos. Fora dessa
-- janela (6 digitos ou 10+) a pergunta nao tem intencao de codigo: os bracos de
-- prosa (trigram e FTS) respondem, e a trigram pode casar o numero de 9 digitos
-- que esta DENTRO do texto. Isso e comportamento antigo de query_codes, que
-- 20260915120000 nao alterou de proposito (o escopo aprovado era o braco fuzzy
-- de codigo). Fica aqui assertado para ser fronteira conhecida e nao surpresa:
-- se um dia a janela mudar, este teste cai e a decisao volta a mesa.
do $$
declare n integer; r record;
begin
  reset role;
  if brain.query_codes('4661132000') <> '{}' then raise exception 'N11 FALHOU: 10 digitos viraram codigo — a janela de query_codes mudou'; end if;
  if brain.query_codes('462621') <> '{}' then raise exception 'N11 FALHOU: 6 digitos viraram codigo — a janela de query_codes mudou'; end if;
  if brain.query_codes('466113200') <> '{466113200}' then raise exception 'N11 FALHOU: 9 digitos deixaram de ser codigo'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '37373737-0000-4000-8000-000000000001', true);
  -- fora da janela nao ha rank de codigo: se aparecer alguma coisa, e prosa
  for r in select * from brain.search_knowledge('4661132000') loop
    if r.rank_exact is not null then raise exception 'N11 FALHOU: numero de 10 digitos ganhou rank de codigo (%)', to_jsonb(r); end if;
  end loop;
  for r in select * from brain.search_knowledge('462621') loop
    if r.rank_exact is not null then raise exception 'N11 FALHOU: numero de 6 digitos ganhou rank de codigo (%)', to_jsonb(r); end if;
  end loop;
  raise notice ' N11) OK: fora da janela de 7-9 digitos o numero nao e codigo — nenhum rank de codigo sai dai (o que responde e prosa, comportamento antigo de query_codes, fora do escopo desta migration)';
end $$;

-- ── seguranca: a redefinicao preservou invoker, search_path e grants ─
do $$
declare p pg_proc%rowtype; cfg text[];
begin
  reset role;
  select * into p from pg_proc where oid = to_regprocedure('brain.search_knowledge(text, jsonb, integer, boolean)');
  if p.prosecdef then raise exception 'N-SEG FALHOU: search_knowledge virou security definer'; end if;
  cfg := p.proconfig;
  if cfg is null or cfg <> array['search_path=""'] then raise exception 'N-SEG FALHOU: search_path vazio nao foi preservado: %', cfg; end if;
  if p.provolatile <> 'v' then raise exception 'N-SEG FALHOU: volatilidade mudou (%) — o set_config do limiar trigram exige VOLATILE', p.provolatile; end if;
  if has_function_privilege('anon', p.oid, 'execute') then raise exception 'N-SEG FALHOU: anon ficou com EXECUTE'; end if;
  if not has_function_privilege('authenticated', p.oid, 'execute') then raise exception 'N-SEG FALHOU: authenticated perdeu EXECUTE'; end if;
  if not has_function_privilege('service_role', p.oid, 'execute') then raise exception 'N-SEG FALHOU: service_role perdeu EXECUTE'; end if;
  raise notice ' N-SEG) OK: security invoker, search_path vazio, anon sem EXECUTE, authenticated e service_role com EXECUTE';
end $$;

-- ── limpeza ─────────────────────────────────────────────────
reset role;
delete from brain.knowledge_queries where user_id = '37373737-0000-4000-8000-000000000001';
delete from brain.documents where id = '37373737-0000-4000-8000-0000000000d1';
delete from brain.knowledge_sources where key = 'numcal';
delete from auth.users where id = '37373737-0000-4000-8000-000000000001';
