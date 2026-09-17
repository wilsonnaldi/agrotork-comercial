-- ============================================================
-- 38 · BRAIN Fase 2 — vigencia NAO declarada
--      (migration 20260917120000_brain_vigencia_nao_declarada)
-- ============================================================
-- O defeito que esta suite tranca: ativar uma versao sem inicio de vigencia
-- fazia o banco carimbar a data da ativacao (ou promover a data tecnica do
-- arquivo a vigencia comercial). NULL tem de significar "nao declarado", e a
-- leitura ja sabia lidar com isso — era o gatilho que inventava.
--
--   V1  valid_from EXPLICITO sobrevive a ativacao, intacto
--   V2  sem valid_from → continua NULL depois de ativar (nao vira current_date)
--   V3  com document_date e sem valid_from → continua NULL (data tecnica nao sobe)
--   V4  sem document_date e sem valid_from → continua NULL
--   V5  current_version() devolve a versao de vigencia nao declarada
--   V6  search_knowledge() devolve o conteudo dela (NULL nao e "invalido")
--   V7  supersessao: a antiga termina HOJE quando a nova nao declara inicio,
--       e na vespera quando declara — nunca no proprio dia em que comecou
--   V8  superseded sem inicio declarado ainda recebe valid_to, e sai da busca;
--       e valid_from no futuro continua barrado quando E declarado
--
-- Prefixo de UUID = 38. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('38383838-0000-4000-8000-000000000001','vig.admin@teste.local', '{"full_name":"Admin Vigencia"}');
update public.profiles set role = 'admin' where id = '38383838-0000-4000-8000-000000000001';

insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('vigfab', 'Fabricante Sem Data', 'manufacturer', 'public', 'allowed');
insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('38383838-0000-4000-8000-0000000000d1', 'vigfab', 'vigfab-tabela', 'Tabela sem vigência declarada', 'price_list', 'public'),
 ('38383838-0000-4000-8000-0000000000d2', 'vigfab', 'vigfab-sucessao', 'Tabela com sucessão', 'price_list', 'public');

-- ════════════════════════════════════════════════════════════
-- V1-V4 · o que a ativacao faz (e o que deixou de fazer) com valid_from
-- ════════════════════════════════════════════════════════════
do $$
declare v1 uuid; v2 uuid; v3 uuid; d date;
begin
  reset role;

  -- V1) valid_from EXPLICITO: a ativacao nao mexe
  v1 := brain.register_version('38383838-0000-4000-8000-0000000000d1', 'EXPL', repeat('a1', 32),
        'expl.pdf', 'application/pdf', 1000, '2026-02-04', 1);
  update brain.document_versions set valid_from = '2026-01-01', status = 'active' where id = v1;
  select valid_from into d from brain.document_versions where id = v1;
  if d <> date '2026-01-01' then raise exception 'V1 FALHOU: valid_from explicito virou %', d; end if;
  raise notice ' V1) OK: valid_from declarado (2026-01-01) sobrevive a ativacao';

  -- V3) document_date presente, valid_from ausente: a data TECNICA nao sobe.
  --     (e o caso ARAG, cujo provenance_note em producao diz, com todas as
  --      letras, que a data e do sistema de arquivos e nao da vigencia)
  update brain.document_versions set status = 'superseded' where id = v1;
  v2 := brain.register_version('38383838-0000-4000-8000-0000000000d1', 'TEC', repeat('a2', 32),
        'tec.pdf', 'application/pdf', 1000, '2024-10-17', 1);
  update brain.document_versions set status = 'active' where id = v2;
  select valid_from into d from brain.document_versions where id = v2;
  if d is not null then raise exception 'V3 FALHOU: document_date 2024-10-17 subiu para valid_from (%)', d; end if;
  if (select document_date from brain.document_versions where id = v2) <> date '2024-10-17' then
    raise exception 'V3 FALHOU: document_date foi perdida no caminho'; end if;
  raise notice ' V3) OK: document_date 2024-10-17 fica onde estava; valid_from continua NULL';

  -- V2/V4) sem document_date e sem valid_from: NULL depois de ativar.
  --        Antes, isto virava current_date — uma data com cara de oficial
  --        que so diz em que dia alguem apertou o botao.
  update brain.document_versions set status = 'superseded' where id = v2;
  v3 := brain.register_version('38383838-0000-4000-8000-0000000000d1', 'NADA', repeat('a3', 32),
        'nada.pdf', 'application/pdf', 1000, null, 1);
  if (select valid_from from brain.document_versions where id = v3) is not null then
    raise exception 'V4 FALHOU: nasceu com valid_from'; end if;
  update brain.document_versions set status = 'active' where id = v3;
  select valid_from into d from brain.document_versions where id = v3;
  if d is not null then raise exception 'V2/V4 FALHOU: ativacao carimbou % em valid_from', d; end if;
  if (select status from brain.document_versions where id = v3) <> 'active' then
    raise exception 'V2 FALHOU: nao ficou ativa'; end if;
  raise notice ' V2/V4) OK: sem data declarada, ativar NAO carimba — valid_from segue NULL e a versão está ativa';
end
$$;

-- ════════════════════════════════════════════════════════════
-- V5-V6 · NULL nao e "invalido": a versao vale e aparece
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; i uuid; n int;
begin
  reset role;
  select id into v from brain.document_versions where version_label = 'NADA';

  i := brain.ingestion_start(v, 'pdf_text', 'pdfplumber 0.11.9', 'lote-b.2', 'suite-38', false, 1, false);
  perform brain.ingestion_add_page(i, 1, 'TABELA SEM VIGENCIA Bico rotativo 466113200 para barra de pulverizacao.', 'text_layer');
  perform brain.ingestion_add_chunk(i, 0, 'text', 1, 1,
    'Bico rotativo 466113200 em ceramica para barra de pulverizacao de herbicida.',
    '{"TABELA SEM VIGENCIA"}', null, '{"466113200"}');
  perform brain.ingestion_finish(i, 'completed');

  -- V5) current_version: a CTE ja fazia `valid_from is null or ...`; o teste
  --     prova que a ponta de gravacao agora produz o NULL que ela espera.
  if brain.current_version('38383838-0000-4000-8000-0000000000d1') <> v then
    raise exception 'V5 FALHOU: versao de vigencia nao declarada nao e a vigente'; end if;
  raise notice ' V5) OK: current_version() devolve a versão de vigência não declarada';

  -- V6) e a busca a enxerga
  perform set_config('request.jwt.claim.sub', '38383838-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.search_knowledge('466113200');
  perform set_config('role', 'none', true); reset role;
  if n < 1 then raise exception 'V6 FALHOU: conteudo de versao sem valid_from nao aparece na busca'; end if;
  raise notice ' V6) OK: search_knowledge() devolve o conteúdo (% evidência(s)) — NULL não é "inválido"', n;
end
$$;

-- ════════════════════════════════════════════════════════════
-- V7 · supersessao: quando a antiga termina
-- ════════════════════════════════════════════════════════════
do $$
declare va uuid; vb uuid; vc uuid; d date;
begin
  reset role;

  -- a antiga COM inicio declarado; a nova SEM. Antes, `greatest(null - 1,
  -- v.valid_from)` colapsava em v.valid_from e encerrava a antiga no proprio
  -- dia em que ela comecou: uma vigencia de um dia, inventada pela aritmetica.
  va := brain.register_version('38383838-0000-4000-8000-0000000000d2', 'A', repeat('b1', 32),
        'a.pdf', 'application/pdf', 1000, null, 1);
  update brain.document_versions set valid_from = '2026-03-01', status = 'active' where id = va;

  vb := brain.register_version('38383838-0000-4000-8000-0000000000d2', 'B', repeat('b2', 32),
        'b.pdf', 'application/pdf', 1000, null, 1);
  update brain.document_versions set status = 'active' where id = vb;

  select valid_to into d from brain.document_versions where id = va;
  if d = date '2026-03-01' then
    raise exception 'V7 FALHOU: a antiga terminou no proprio dia em que comecou (2026-03-01)'; end if;
  if d <> current_date then
    raise exception 'V7 FALHOU: sem inicio declarado na nova, a antiga devia terminar hoje (%), terminou em %', current_date, d; end if;
  if (select status from brain.document_versions where id = va) <> 'superseded' then
    raise exception 'V7 FALHOU: a antiga nao ficou superseded'; end if;
  raise notice ' V7a) OK: nova sem início declarado → a anterior termina HOJE, não no dia em que começou';

  -- e quando a nova DECLARA inicio, a antiga termina na vespera — inalterado
  update brain.document_versions set valid_from = '2026-03-02' where id = vb;
  vc := brain.register_version('38383838-0000-4000-8000-0000000000d2', 'C', repeat('b3', 32),
        'c.pdf', 'application/pdf', 1000, null, 1);
  update brain.document_versions set valid_from = '2026-06-10', status = 'active' where id = vc;
  select valid_to into d from brain.document_versions where id = vb;
  if d <> date '2026-06-09' then
    raise exception 'V7 FALHOU: com inicio declarado (2026-06-10) a antiga devia terminar em 2026-06-09, terminou em %', d; end if;
  raise notice ' V7b) OK: nova com início declarado (2026-06-10) → a anterior termina na véspera (2026-06-09)';
end
$$;

-- ════════════════════════════════════════════════════════════
-- V8 · superseded sem inicio declarado, e o futuro que continua barrado
-- ════════════════════════════════════════════════════════════
do $$
declare v uuid; vf uuid; n int; d date;
begin
  reset role;
  select id into v from brain.document_versions where version_label = 'NADA';

  -- superseder manualmente a versao de vigencia nao declarada
  update brain.document_versions set status = 'superseded' where id = v;
  select valid_to into d from brain.document_versions where id = v;
  if d is null then
    raise exception 'V8 FALHOU: superseded sem inicio declarado ficou sem valid_to — "antiga que nunca terminou"'; end if;
  if (select valid_from from brain.document_versions where id = v) is not null then
    raise exception 'V8 FALHOU: superseder inventou um valid_from'; end if;
  if brain.current_version('38383838-0000-4000-8000-0000000000d1') is not null then
    raise exception 'V8 FALHOU: documento sem vigente devolveu algo'; end if;

  perform set_config('request.jwt.claim.sub', '38383838-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from brain.search_knowledge('466113200');
  perform set_config('role', 'none', true); reset role;
  if n <> 0 then raise exception 'V8 FALHOU: versao superseded ainda responde na busca normal (%)', n; end if;
  raise notice ' V8a) OK: superseded sem início declarado recebe valid_to (%) e sai da busca', d;

  -- o bloqueio de vigencia futura continua valendo quando a data E declarada
  vf := brain.register_version('38383838-0000-4000-8000-0000000000d1', 'FUT', repeat('a4', 32),
        'fut.pdf', 'application/pdf', 1000, null, 1);
  update brain.document_versions set valid_from = current_date + 1 where id = vf;
  begin
    update brain.document_versions set status = 'active' where id = vf;
    raise exception 'V8 FALHOU: ativou versao com valid_from no futuro';
  exception when check_violation then null; end;
  raise notice ' V8b) OK: valid_from declarado no futuro continua barrado na ativação';
end
$$;

-- ── limpeza ─────────────────────────────────────────────────
reset role;
delete from brain.knowledge_queries where user_id = '38383838-0000-4000-8000-000000000001';
delete from brain.documents where id in ('38383838-0000-4000-8000-0000000000d1', '38383838-0000-4000-8000-0000000000d2');
delete from brain.knowledge_sources where key = 'vigfab';
delete from auth.users where id = '38383838-0000-4000-8000-000000000001';
