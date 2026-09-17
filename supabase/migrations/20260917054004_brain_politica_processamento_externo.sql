-- ============================================================
-- BRAIN Fase 2 — a politica de processamento externo, legivel pelo app
-- ============================================================
-- `brain.external_processing_for(uuid)` existe desde o Lote A e e a UNICA
-- fonte da resposta "este documento pode sair para um provedor externo?".
-- Ate agora ninguem precisava dela do lado do aplicativo, porque nada saia
-- daqui. Com a sintese por LLM isso muda: antes de qualquer trecho ser
-- enviado para fora, alguem tem de perguntar.
--
-- O schema `brain` nao e exposto ao PostgREST — de proposito. As duas portas
-- que o app tem sao `public.brain_search` e `public.brain_provenance`. Esta e
-- a TERCEIRA, e a menor possivel: um invólucro que recebe ids de documento e
-- devolve a politica de cada um. Nao calcula nada, nao decide nada, nao
-- reimplementa a regra — chama a funcao versionada.
--
-- Por que em lote e nao um id por chamada: a sintese avalia todas as
-- evidencias de uma resposta ao mesmo tempo. Uma chamada por evidencia seria
-- N+1 num caminho que ja tem um provedor externo esperando do outro lado.
--
-- `security invoker`: o RLS de `brain.documents` continua valendo. Documento
-- que o chamador nao enxerga simplesmente NAO VOLTA na lista — e o lado do
-- aplicativo trata ausencia como `forbidden`, nunca como permissao. Perguntar
-- a politica nao e um jeito de descobrir que um documento existe.
--
-- Semantica da funcao versionada, para quem for ler so isto aqui:
--
--   allowed  <  approved_provider_only  <  forbidden      (ordem do enum)
--
--   access_level = 'admin'       -> forbidden, sempre
--   access_level = 'commercial'  -> forbidden, salvo override por documento
--   access_level = 'internal'    -> no minimo approved_provider_only
--   access_level = 'public'      -> override, ou a politica da fonte
--
-- Ou seja: `allowed` so e alcancavel por documento `public`. Em producao
-- (17/09/2026) isso da Magnojet `allowed` e o orcamento ARAG `forbidden` —
-- o ARAG e consultavel por um administrador dentro da AGROTORK e NAO pode
-- ser enviado a um provedor externo. As duas coisas ao mesmo tempo.
--
-- Testes: supabase/db-tests/40_brain_processamento_externo.sql (P1-P8).
--
-- SOBRE O NUMERO DESTE ARQUIVO. Ele nasceu `20260918120000`. Ao ser aplicada
-- em producao, a migration foi registrada no ledger do Supabase com o carimbo
-- do momento da aplicacao — `20260917054004` — e nao com o numero do arquivo.
-- O arquivo foi renomeado para bater com o ledger, porque o CLI decide o que
-- falta aplicar comparando o prefixo do ARQUIVO com o ledger: mantido o nome
-- antigo, um `db push` veria esta migration como pendente e a rodaria de novo.
--
-- E a SEGUNDA vez que isto acontece (a primeira foi a 20260917030427). Nao e
-- coincidencia: toda migration aplicada por fora do CLI ganha o carimbo da
-- hora. A regra ficou registrada em CLAUDE.md — conferir o `version` do
-- ledger e alinhar o arquivo na MESMA rodada da aplicacao.
--
-- O numero nao e um horario escolhido: e o carimbo real da aplicacao em
-- producao (17/09/2026), e por isso fica. Nada foi reexecutado.
-- ============================================================

create or replace function public.brain_external_processing(p_document_ids uuid[])
returns table (document_id uuid, policy text)
language sql stable security invoker set search_path = '' as $$
  select d.id, brain.external_processing_for(d.id)::text
    from brain.documents d
   where d.id = any (coalesce(p_document_ids, '{}'::uuid[]))
   limit 100;
$$;

revoke execute on function public.brain_external_processing(uuid[]) from public, anon;
grant  execute on function public.brain_external_processing(uuid[]) to authenticated, service_role;

comment on function public.brain_external_processing(uuid[]) is
  'Politica de processamento externo de cada documento, para o aplicativo decidir o que pode ser enviado a um provedor de LLM. Invólucro de brain.external_processing_for; security invoker, entao o RLS vale e documento invisivel nao volta. Ausencia significa proibido.';

-- Guarda: a funcao entrou, nao virou definer e anon nao alcanca.
do $$
declare p pg_proc%rowtype;
begin
  select * into p from pg_proc where oid = to_regprocedure('public.brain_external_processing(uuid[])');
  if p.oid is null then
    raise exception 'public.brain_external_processing(uuid[]) nao existe depois da migration';
  end if;
  if p.prosecdef then
    raise exception 'brain_external_processing virou security definer — o RLS deixaria de valer';
  end if;
  if p.proconfig is null or p.proconfig <> array['search_path=""'] then
    raise exception 'brain_external_processing sem search_path vazio: %', p.proconfig;
  end if;
  if has_function_privilege('anon', p.oid, 'execute') then
    raise exception 'anon ficou com EXECUTE em brain_external_processing';
  end if;
  raise notice 'politica de processamento externo legivel pelo aplicativo';
end
$$;
