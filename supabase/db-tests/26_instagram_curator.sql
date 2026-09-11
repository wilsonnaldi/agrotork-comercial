-- ============================================================
-- instagram_curator — baseline (migration 20260911090000).
--
-- A lacuna que este arquivo fecha: o schema existia em produção e não
-- existia no Git. Um banco novo montado a partir das migrations não
-- reproduzia produção, e ninguém tinha como provar o contrário.
--
-- O que este arquivo prova:
--   · o schema, os 2 enums, as 6 tabelas e as 4 funções nascem do Git;
--   · `anon` e `authenticated` não enxergam o schema — nem por USAGE;
--   · RLS está ligada nas 6 tabelas, com a policy de `service_role`;
--   · a trava distribuída funciona: um dono pega, o outro não;
--   · a trava vencida é tomada pelo próximo;
--   · `updated_at` é carimbado pelo gatilho, não pela aplicação;
--   · os checks de identidade de `references` recusam meia-URL;
--   · rodar a migration DE NOVO não quebra nem apaga nada (é o caso de
--     produção, onde o schema já existe).
-- ============================================================
reset role;

-- ── IC1: a estrutura veio inteira do Git ─────────────────────
do $$
declare
  v_tabelas int; v_enums int; v_funcs int; v_policies int; v_rls int; v_idx int;
begin
  select count(*) into v_tabelas from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r';
  select count(*) into v_enums from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'instagram_curator' and t.typtype = 'e';
  select count(*) into v_funcs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator';
  select count(*) into v_policies from pg_policies where schemaname = 'instagram_curator';
  select count(*) into v_rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r' and c.relrowsecurity;
  select count(*) into v_idx from pg_indexes where schemaname = 'instagram_curator';

  if v_tabelas <> 6 or v_enums <> 2 or v_funcs <> 4 or v_policies <> 6 or v_rls <> 6 or v_idx <> 17 then
    raise exception 'IC1 FALHOU: % tabelas, % enums, % funcoes, % policies, % com RLS, % indices',
      v_tabelas, v_enums, v_funcs, v_policies, v_rls, v_idx;
  end if;
  raise notice ' IC1) OK: 6 tabelas (todas com RLS), 2 enums, 4 funcoes, 6 policies, 17 indices';
end
$$;

-- ── IC2: toda função com search_path vazio ───────────────────
do $$
declare v_frouxa text;
begin
  select string_agg(p.proname, ', ') into v_frouxa
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'instagram_curator'
     and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%';
  if v_frouxa is not null then
    raise exception 'IC2 FALHOU: sem search_path fixo: %', v_frouxa;
  end if;
  raise notice ' IC2) OK: as 4 funcoes tem search_path fixo';
end
$$;

-- ── IC3: o ERP não enxerga o curador ─────────────────────────
do $$
declare v_anon boolean; v_auth boolean; v_tab int;
begin
  v_anon := has_schema_privilege('anon', 'instagram_curator', 'usage');
  v_auth := has_schema_privilege('authenticated', 'instagram_curator', 'usage');
  select count(*) into v_tab
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'instagram_curator' and c.relkind = 'r'
     and (has_table_privilege('anon', c.oid, 'select')
          or has_table_privilege('authenticated', c.oid, 'select'));
  if v_anon or v_auth or v_tab > 0 then
    raise exception 'IC3 FALHOU: anon=% authenticated=% tabelas legiveis=%', v_anon, v_auth, v_tab;
  end if;
  raise notice ' IC3) OK: anon e authenticated sem USAGE no schema e sem SELECT em nenhuma tabela';
end
$$;

-- ── IC4: a trava distribuída ─────────────────────────────────
insert into instagram_curator.runs (executor) values ('teste-baseline');

do $$
declare
  v_run   uuid;
  v_dono1 uuid := '26262626-0000-4000-8000-000000000001';
  v_dono2 uuid := '26262626-0000-4000-8000-000000000002';
  v_a boolean; v_b boolean; v_c boolean; v_d boolean;
begin
  select id into v_run from instagram_curator.runs where executor = 'teste-baseline';

  v_a := instagram_curator.acquire_lock('curador', v_dono1, 60, v_run);
  v_b := instagram_curator.acquire_lock('curador', v_dono2, 60, v_run);   -- outro dono: não leva
  v_c := instagram_curator.heartbeat_lock('curador', v_dono2, 60);        -- nem renova
  v_d := instagram_curator.heartbeat_lock('curador', v_dono1, 60);        -- o dono renova

  if not v_a or v_b or v_c or not v_d then
    raise exception 'IC4 FALHOU: pegou=% invasor_pegou=% invasor_renovou=% dono_renovou=%',
      v_a, v_b, v_c, v_d;
  end if;

  -- TTL fora da faixa é recusado.
  begin
    perform instagram_curator.acquire_lock('curador', v_dono1, 10, v_run);
    raise exception 'IC4 FALHOU: aceitou ttl de 10s';
  exception when others then
    if sqlerrm not like '%lock ttl%' then raise; end if;
  end;

  -- Trava vencida: o próximo toma.
  -- `locks_expiry_order` exige expires_at > acquired_at: para simular um
  -- vencimento é preciso recuar a aquisição junto, não só o vencimento.
  update instagram_curator.locks
     set acquired_at  = now() - interval '10 minutes',
         heartbeat_at = now() - interval '10 minutes',
         expires_at   = now() - interval '1 minute'
   where lock_name = 'curador';
  if not instagram_curator.acquire_lock('curador', v_dono2, 60, v_run) then
    raise exception 'IC4 FALHOU: trava vencida nao foi tomada';
  end if;
  if instagram_curator.release_lock('curador', v_dono1) then
    raise exception 'IC4 FALHOU: quem nao e dono soltou a trava';
  end if;
  if not instagram_curator.release_lock('curador', v_dono2) then
    raise exception 'IC4 FALHOU: o dono nao soltou a trava';
  end if;

  raise notice ' IC4) OK: um dono por vez, ttl entre 30s e 3600s, trava vencida e tomada, so o dono solta';
end
$$;

-- ── IC5: identidade da referência e carimbo automático ───────
do $$
declare v_id uuid; v_antes timestamptz; v_depois timestamptz;
begin
  -- Meia-identidade é recusada: ou tem shortcode + URL + rota, ou não tem nada.
  begin
    insert into instagram_curator."references" (shortcode, origin) values ('ABC123', 'teste');
    raise exception 'IC5 FALHOU: aceitou shortcode sem URL';
  exception when check_violation then null;
  end;

  -- URL que não bate com o shortcode também é recusada.
  begin
    insert into instagram_curator."references" (shortcode, canonical_url, observed_route, origin)
    values ('ABC123', 'https://instagram.com/p/OUTRO/', 'p', 'teste');
    raise exception 'IC5 FALHOU: aceitou URL de outro shortcode';
  exception when check_violation then null;
  end;

  insert into instagram_curator."references" (shortcode, canonical_url, observed_route, origin)
  values ('ABC123', 'https://www.instagram.com/p/ABC123/', 'p', 'teste')
  returning id, updated_at into v_id, v_antes;

  -- `completed` sem carimbo de conclusão é recusado.
  begin
    update instagram_curator."references" set status = 'completed' where id = v_id;
    raise exception 'IC5 FALHOU: aceitou completed sem completed_at';
  exception when check_violation then null;
  end;

  -- `now()` não anda dentro de uma transação: quem prova o gatilho é a
  -- tentativa de escrever um `updated_at` mentiroso e vê-lo ser ignorado.
  update instagram_curator."references"
     set topic = 'pulverizacao', updated_at = timestamptz '2000-01-01 00:00:00+00'
   where id = v_id;
  select updated_at into v_depois from instagram_curator."references" where id = v_id;
  if v_depois <> now() or v_depois = timestamptz '2000-01-01 00:00:00+00' then
    raise exception 'IC5 FALHOU: updated_at ficou em % — o gatilho nao carimbou', v_depois;
  end if;

  raise notice ' IC5) OK: meia-identidade, URL trocada e completed sem data recusados; updated_at mentiroso foi sobrescrito';
end
$$;

-- ── IC6: a migration é idempotente (o caso de produção) ──────
-- Reaplicar o arquivo inteiro não pode apagar linha nenhuma nem falhar.
do $$
declare v_refs int; v_runs int;
begin
  select count(*) into v_refs from instagram_curator."references";
  select count(*) into v_runs from instagram_curator.runs;
  perform set_config('instagram_curator.test.refs', v_refs::text, false);
  perform set_config('instagram_curator.test.runs', v_runs::text, false);
end
$$;

\i supabase/migrations/20260911090000_instagram_curator_baseline.sql

do $$
declare v_refs int; v_runs int; v_antes_refs int; v_antes_runs int;
begin
  select count(*) into v_refs from instagram_curator."references";
  select count(*) into v_runs from instagram_curator.runs;
  v_antes_refs := current_setting('instagram_curator.test.refs')::int;
  v_antes_runs := current_setting('instagram_curator.test.runs')::int;
  if v_refs <> v_antes_refs or v_runs <> v_antes_runs then
    raise exception 'IC6 FALHOU: reaplicar a migration mexeu em dado — references % -> %, runs % -> %',
      v_antes_refs, v_refs, v_antes_runs, v_runs;
  end if;
  raise notice ' IC6) OK: migration reaplicada sem erro e sem tocar em dado (% referencia(s), % execucao(oes))',
    v_refs, v_runs;
end
$$;

-- Limpeza: esta suíte não deixa lixo para as seguintes.
delete from instagram_curator.events;
delete from instagram_curator."references" where origin = 'teste';
delete from instagram_curator.runs where executor = 'teste-baseline';
