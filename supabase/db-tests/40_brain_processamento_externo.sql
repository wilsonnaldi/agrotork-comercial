-- ============================================================
-- 40 · BRAIN Fase 2 — politica de processamento externo (Answer v1)
--      (migration 20260918120000_brain_politica_processamento_externo)
-- ============================================================
-- Este gate e tao importante quanto o RLS, e e DIFERENTE dele.
--
--   RLS responde:                 esta pessoa pode LER isto?
--   external_processing responde: isto pode SAIR daqui?
--
-- As duas perguntas tem respostas independentes. O orcamento interno ARAG,
-- em producao, e "sim" para a primeira (um administrador consulta) e "nao"
-- para a segunda (nao vai para provedor de LLM nenhum). Uma resposta bonita
-- que quebre a segunda e pior do que resposta nenhuma.
--
--   P1  admin      -> forbidden sempre, mesmo com fonte allowed
--   P2  commercial -> forbidden por padrao
--   P3  commercial + override allowed -> allowed (opt-in explicito e auditado)
--   P4  internal   -> nunca melhor que approved_provider_only
--   P5  public + fonte allowed -> allowed (o unico caminho ate `allowed`)
--   P6  public + fonte forbidden -> forbidden
--   P7  documento invisivel NAO volta na lista — perguntar a politica nao
--       revela existencia
--   P8  a funcao e invoker, tem search_path vazio e anon nao alcanca
--
-- Prefixo de UUID = 40. Limpeza no fim.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('40404040-0000-4000-8000-000000000001','ep.admin@teste.local',    '{"full_name":"Admin Externo"}'),
 ('40404040-0000-4000-8000-000000000002','ep.vendedor@teste.local', '{"full_name":"Vendedor Externo"}');
update public.profiles set role = 'admin'       where id = '40404040-0000-4000-8000-000000000001';
update public.profiles set role = 'salesperson' where id = '40404040-0000-4000-8000-000000000002';

-- Duas fontes: uma liberada, uma proibida. O documento e que decide o resto.
insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) values
 ('ep_aberta',  'Fonte Liberada',  'manufacturer', 'public',  'allowed'),
 ('ep_fechada', 'Fonte Proibida',  'internal',     'public',  'forbidden');

insert into brain.documents (id, source_key, slug, title, document_type, access_level) values
 ('40404040-0000-4000-8000-0000000000d1', 'ep_aberta',  'ep-publico',     'Catálogo público',       'catalog',       'public'),
 ('40404040-0000-4000-8000-0000000000d2', 'ep_aberta',  'ep-interno',     'Nota interna',           'internal_note', 'internal'),
 ('40404040-0000-4000-8000-0000000000d3', 'ep_aberta',  'ep-comercial',   'Orçamento comercial',    'internal_note', 'commercial'),
 ('40404040-0000-4000-8000-0000000000d4', 'ep_aberta',  'ep-admin',       'Documento administrativo','internal_note', 'admin'),
 ('40404040-0000-4000-8000-0000000000d5', 'ep_fechada', 'ep-publico-nao', 'Catálogo de fonte proibida','catalog',    'public');

-- ════════════════════════════════════════════════════════════
-- P1-P6 · a politica de cada combinacao
-- ════════════════════════════════════════════════════════════
do $$
declare v_p text;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '40404040-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', true);

  -- P1) admin: nem a fonte mais liberada do mundo libera
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d4'::uuid]);
  if v_p <> 'forbidden' then raise exception 'P1 FALHOU: documento admin deu % (fonte e allowed)', v_p; end if;
  raise notice ' P1) OK: access_level admin → forbidden, mesmo com a fonte allowed';

  -- P2) commercial sem override
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d3'::uuid]);
  if v_p <> 'forbidden' then raise exception 'P2 FALHOU: commercial sem override deu %', v_p; end if;
  raise notice ' P2) OK: commercial sem override → forbidden';

  -- P3) commercial COM override e aprovador: o opt-in explicito funciona
  update brain.documents
     set external_processing_override = 'allowed',
         approved_at = now(),
         approved_by = '40404040-0000-4000-8000-000000000001'
   where id = '40404040-0000-4000-8000-0000000000d3';
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d3'::uuid]);
  if v_p <> 'allowed' then raise exception 'P3 FALHOU: override allowed nao valeu (%)', v_p; end if;
  update brain.documents set external_processing_override = null, approved_at = null, approved_by = null
   where id = '40404040-0000-4000-8000-0000000000d3';
  raise notice ' P3) OK: commercial com override e aprovador registrado → allowed';

  -- P4) internal nunca fica melhor que approved_provider_only
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d2'::uuid]);
  if v_p <> 'approved_provider_only' then raise exception 'P4 FALHOU: internal deu % (fonte allowed)', v_p; end if;
  raise notice ' P4) OK: internal com fonte allowed → approved_provider_only, nunca allowed';

  -- P5) public + fonte allowed: o UNICO caminho ate allowed
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d1'::uuid]);
  if v_p <> 'allowed' then raise exception 'P5 FALHOU: public + fonte allowed deu %', v_p; end if;
  raise notice ' P5) OK: public + fonte allowed → allowed (o único caminho)';

  -- P6) public, mas a fonte proibe
  select policy into v_p from public.brain_external_processing(array['40404040-0000-4000-8000-0000000000d5'::uuid]);
  if v_p <> 'forbidden' then raise exception 'P6 FALHOU: fonte forbidden deu %', v_p; end if;
  raise notice ' P6) OK: público de fonte proibida → forbidden — o nível não sobrepõe a fonte';

  perform set_config('role', 'none', true); reset role;
end
$$;

-- ════════════════════════════════════════════════════════════
-- P7 · perguntar a politica nao revela existencia
-- ════════════════════════════════════════════════════════════
do $$
declare v_n int; v_total int;
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '40404040-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  -- o vendedor (nivel internal) nao enxerga commercial nem admin
  select count(*) into v_n from public.brain_external_processing(
    array['40404040-0000-4000-8000-0000000000d3'::uuid, '40404040-0000-4000-8000-0000000000d4'::uuid]);
  if v_n <> 0 then raise exception 'P7 FALHOU: vendedor recebeu politica de % documento(s) que nao enxerga', v_n; end if;

  -- e continua recebendo a dos que enxerga
  select count(*) into v_total from public.brain_external_processing(
    array['40404040-0000-4000-8000-0000000000d1'::uuid, '40404040-0000-4000-8000-0000000000d2'::uuid,
          '40404040-0000-4000-8000-0000000000d3'::uuid, '40404040-0000-4000-8000-0000000000d4'::uuid]);
  if v_total <> 2 then raise exception 'P7 FALHOU: esperava 2 politicas visiveis, veio %', v_total; end if;

  -- id que nao existe: some, sem erro e sem pista
  select count(*) into v_n from public.brain_external_processing(array['40404040-0000-4000-8000-00000000dead'::uuid]);
  if v_n <> 0 then raise exception 'P7 FALHOU: id inexistente devolveu linha'; end if;

  perform set_config('role', 'none', true); reset role;
  raise notice ' P7) OK: documento invisível não volta na lista — ausência é a resposta, e o app trata ausência como proibido';
end
$$;

-- ════════════════════════════════════════════════════════════
-- P8 · a porta em si
-- ════════════════════════════════════════════════════════════
do $$
declare p pg_proc%rowtype;
begin
  reset role;
  select * into p from pg_proc where oid = to_regprocedure('public.brain_external_processing(uuid[])');
  if p.oid is null then raise exception 'P8 FALHOU: a funcao nao existe'; end if;
  if p.prosecdef then raise exception 'P8 FALHOU: virou security definer — o RLS deixaria de valer'; end if;
  if p.proconfig is null or p.proconfig <> array['search_path=""'] then
    raise exception 'P8 FALHOU: search_path vazio nao foi preservado: %', p.proconfig; end if;
  if has_function_privilege('anon', p.oid, 'execute') then raise exception 'P8 FALHOU: anon com EXECUTE'; end if;
  if not has_function_privilege('authenticated', p.oid, 'execute') then raise exception 'P8 FALHOU: authenticated sem EXECUTE'; end if;
  raise notice ' P8) OK: security invoker, search_path vazio, anon sem EXECUTE, authenticated com EXECUTE';
end
$$;

-- ── limpeza ─────────────────────────────────────────────────
reset role;
delete from brain.documents where id in (
  '40404040-0000-4000-8000-0000000000d1','40404040-0000-4000-8000-0000000000d2',
  '40404040-0000-4000-8000-0000000000d3','40404040-0000-4000-8000-0000000000d4',
  '40404040-0000-4000-8000-0000000000d5');
delete from brain.knowledge_sources where key in ('ep_aberta','ep_fechada');
delete from auth.users where id in ('40404040-0000-4000-8000-000000000001','40404040-0000-4000-8000-000000000002');
