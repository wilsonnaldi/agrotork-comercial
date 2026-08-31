-- ============================================================
-- STORAGE: buckets e policies (migration 2000).
--
-- Roda nos dois ambientes: contra o `storage` reproduzido em
-- `00_supabase_stub.sql` e contra o Storage nativo do Supabase local.
--
-- Uma diferença importante entre eles: o Storage do Supabase instala um
-- gatilho que RECUSA `delete` direto na tabela ("Direct deletion from
-- storage tables is not allowed"), antes de a policy ser consultada. Isso
-- é proteção a mais, não a menos — mas engole a tentativa e deixaria o
-- teste sem provar nada. Por isso GL e GM provam a policy também pelo
-- caminho do catálogo (`assert_policy_nao_alcanca`), que independe do
-- gatilho e vale igual nos dois ambientes.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

select 'GF) buckets criados' as teste,
       string_agg(id || (case when public then ' (público)' else ' (privado)' end), ', ' order by id) as buckets,
       case when count(*) = 2 then 'OK' else 'FALHA: ' || count(*) end as resultado
from storage.buckets where id in ('public-assets', 'private-docs');

select 'GG) limite de tamanho e tipos permitidos' as teste,
       case when file_size_limit = 5242880
             and 'image/png' = any(allowed_mime_types)
             and not ('application/x-msdownload' = any(allowed_mime_types))
            then 'OK: 5 MB, só imagem' else 'FALHA' end as resultado
from storage.buckets where id = 'public-assets';

-- ── ADMIN escreve no bucket público ─────────────────────────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

insert into storage.objects (bucket_id, name, owner)
values ('public-assets', 'empresa/logo-agrotork.png', '11111111-1111-1111-1111-111111111111');

select 'GH) admin grava no bucket publico' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA' end as resultado
from storage.objects where name = 'empresa/logo-agrotork.png';

update storage.objects set metadata = '{"size": 12345}'::jsonb
 where name = 'empresa/logo-agrotork.png';
select 'GI) admin atualiza o proprio arquivo' as teste,
       case when metadata ->> 'size' = '12345' then 'OK' else 'FALHA' end as resultado
from storage.objects where name = 'empresa/logo-agrotork.png';

-- ── VENDEDOR lê, não escreve ────────────────────────────────
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'GJ) vendedor le o bucket publico' as teste,
       case when count(*) = 1 then 'OK' else 'FALHA: ' || count(*) end as resultado
from storage.objects where bucket_id = 'public-assets';

do $$ begin
  insert into storage.objects (bucket_id, name) values ('public-assets', 'empresa/logo-falso.png');
  raise notice 'GK) FALHA DE SEGURANCA: vendedor gravou no bucket publico';
exception when insufficient_privilege or others then
  raise notice 'GK) OK: vendedor bloqueado ao gravar no bucket publico';
end $$;


-- ── Prova de policy independente do gatilho ─────────────────
-- Lê do catálogo a expressão `using` das policies permissivas que valem
-- para o papel atual e para o comando informado, e conta quantas linhas
-- do bucket ela alcançaria. Zero = a policy não autoriza a operação.
--
-- Não é uma cópia da regra: é a regra que está no banco, executada. Se
-- alguém afrouxar a policy numa migration futura, a contagem sobe e o
-- teste acusa.
create or replace function pg_temp.policy_alcanca(p_cmd text, p_bucket text)
returns integer language plpgsql as $fn$
declare
  regra   record;
  parcial integer;
  total   integer := 0;
begin
  for regra in
    select qual
      from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and permissive = 'PERMISSIVE'
       and cmd in (p_cmd, 'ALL')
       and qual is not null
       and (roles && array['public', current_user]::name[]
            or roles && array(select rolname from pg_roles
                               where pg_has_role(current_user, oid, 'member')))
  loop
    execute format(
      'select count(*)::int from storage.objects where bucket_id = %L and (%s)',
      p_bucket, regra.qual
    ) into parcial;
    total := total + parcial;
  end loop;
  return total;
end $fn$;

do $$
declare afetadas int; barrado text := null;
begin
  begin
    update storage.objects set name = 'empresa/sequestrado.png' where bucket_id = 'public-assets';
    get diagnostics afetadas = row_count;
  exception when others then
    -- Uma proteção anterior à policy (gatilho do Storage) recusou a
    -- operação. Nada foi alterado; a policy é conferida logo abaixo.
    barrado := sqlerrm; afetadas := 0;
  end;

  if afetadas > 0 then
    raise notice 'GL) FALHA DE SEGURANCA: alterou % arquivo(s)', afetadas;
  elsif pg_temp.policy_alcanca('UPDATE', 'public-assets') > 0 then
    raise notice 'GL) FALHA DE SEGURANCA: a policy de update alcanca o arquivo do catalogo';
  elsif barrado is not null then
    raise notice 'GL) OK: vendedor nao altera arquivo do catalogo (policy nega; Storage tambem barrou)';
  else
    raise notice 'GL) OK: vendedor nao altera arquivo do catalogo';
  end if;
end $$;

do $$
declare afetadas int; barrado text := null; restantes int;
begin
  begin
    delete from storage.objects where bucket_id = 'public-assets';
    get diagnostics afetadas = row_count;
  exception when others then
    -- É AQUI que o Storage do Supabase entra: o gatilho recusa `delete`
    -- direto na tabela antes da policy. Continua sendo "nao apagou".
    barrado := sqlerrm; afetadas := 0;
  end;

  -- Independente do caminho, o arquivo do catálogo tem de continuar lá.
  select count(*) into restantes
    from storage.objects where name = 'empresa/logo-agrotork.png';

  if afetadas > 0 then
    raise notice 'GM) FALHA DE SEGURANCA: apagou % arquivo(s)', afetadas;
  elsif restantes <> 1 then
    raise notice 'GM) FALHA DE SEGURANCA: o arquivo do catalogo sumiu';
  elsif pg_temp.policy_alcanca('DELETE', 'public-assets') > 0 then
    raise notice 'GM) FALHA DE SEGURANCA: a policy de delete alcanca o arquivo do catalogo';
  elsif barrado is not null then
    raise notice 'GM) OK: vendedor nao apaga arquivo do catalogo (policy nega; Storage tambem barrou)';
  else
    raise notice 'GM) OK: vendedor nao apaga arquivo do catalogo';
  end if;
end $$;

-- ── BUCKET PRIVADO continua privado ─────────────────────────
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into storage.objects (bucket_id, name, owner)
values ('private-docs', 'contratos/segredo.pdf', '11111111-1111-1111-1111-111111111111');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select 'GN) vendedor nao le o bucket privado' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA: viu ' || count(*) end as resultado
from storage.objects where bucket_id = 'private-docs';

-- ── ANÔNIMO: lê o público, não vê o privado ─────────────────
reset role; set role anon;

select 'GO) anonimo le o bucket publico' as teste,
       case when count(*) = 1 then 'OK: o logotipo abre sem login' else 'FALHA: ' || count(*) end as resultado
from storage.objects where bucket_id = 'public-assets';

select 'GP) anonimo NAO le o bucket privado' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA: viu ' || count(*) end as resultado
from storage.objects where bucket_id = 'private-docs';

do $$ begin
  insert into storage.objects (bucket_id, name) values ('public-assets', 'anonimo.png');
  raise notice 'GQ) FALHA DE SEGURANCA: anonimo gravou arquivo';
exception when insufficient_privilege or others then
  raise notice 'GQ) OK: anonimo bloqueado ao gravar';
end $$;

reset role;
