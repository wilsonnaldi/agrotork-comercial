-- ============================================================
-- BRAIN — volatilidade das funções (migration 20260911160000).
--
-- A lacuna que este arquivo fecha: `keep_authorship` foi declarada
-- `immutable` sendo que lê `public.profiles`. O gatilho a chama com
-- parâmetros, o que esconde o erro no caminho comum; com argumento
-- constante o planejador dobra a chamada e congela o resultado no plano.
--
-- O que este arquivo prova:
--   VL1  consulta preparada com argumento constante enxerga a mudança
--        no banco — era aqui que o plano em cache mentia;
--   VL2  nenhuma função do BRAIN que leia tabela está `immutable`;
--   VL3  a `security definer` que decide autoria continua decidindo
--        certo nas quatro combinações.
-- ============================================================
reset role;

-- ── VL1: o plano em cache não pode congelar a resposta ──────
do $$
declare
  v_perfil uuid := '29292929-0000-4000-8000-000000000001';
  v_antes  uuid;
  v_depois uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data)
   values (v_perfil, 'vl1@teste.local', '{"full_name":"Perfil VL1","role":"salesperson"}');

  -- Argumento CONSTANTE de propósito: é a forma que o planejador pode
  -- dobrar quando a função se declara immutable.
  execute format(
    'prepare vl1_fixa as select brain.keep_authorship(null::uuid, %L::uuid)', v_perfil);

  -- Cinco execuções: a partir da sexta o PostgreSQL costuma trocar o
  -- plano personalizado pelo genérico, e é o genérico que fica em cache.
  for i in 1..5 loop
    execute 'execute vl1_fixa' into v_antes;
  end loop;
  if v_antes is distinct from v_perfil then
    execute 'deallocate vl1_fixa';
    raise exception 'VL1 FALHOU: com o perfil vivo a autoria deveria ser preservada, veio %',
      coalesce(v_antes::text, 'nulo');
  end if;

  delete from auth.users where id = v_perfil;

  execute 'execute vl1_fixa' into v_depois;
  execute 'deallocate vl1_fixa';

  if v_depois is not null then
    raise exception 'VL1 FALHOU: perfil removido e o plano em cache ainda devolve % — a funcao esta immutable de novo', v_depois;
  end if;
  if not brain.profile_missing(v_perfil) then
    raise exception 'VL1 FALHOU: o perfil nao foi removido, o ensaio nao vale';
  end if;

  raise notice ' VL1) OK: plano em cache com argumento constante enxergou a remocao do perfil (antes % / depois nulo)',
    left(v_antes::text, 8);
end
$$;

-- ── VL2: nada que leia tabela pode ser immutable ────────────
do $$
declare v_errada text; v_total int;
begin
  select string_agg(p.proname || ' (' || p.provolatile::text || ')', ', '), count(*)
    into v_errada, v_total
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain'
     and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  if v_total > 0 then
    raise exception 'VL2 FALHOU: % declarada(s) IMMUTABLE sem ser', v_errada;
  end if;

  -- E as duas legítimas continuam imutáveis: são conta pura sobre o
  -- argumento, e é isso que deixa o índice de expressão valer.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'brain' and p.proname in ('normalize_phone','normalize_identity')
         and p.provolatile = 'i') <> 2 then
    raise exception 'VL2 FALHOU: normalize_phone/normalize_identity deixaram de ser immutable';
  end if;

  raise notice ' VL2) OK: so normalize_phone e normalize_identity sao immutable — as duas nao leem tabela';
end
$$;

-- ── VL3: as quatro combinações de autoria ───────────────────
do $$
declare
  v_a uuid := '29292929-0000-4000-8000-00000000000a';
  v_b uuid := '29292929-0000-4000-8000-00000000000b';
  v_sumido uuid := '29292929-0000-4000-8000-0000000000ff';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
   (v_a, 'vl3a@teste.local', '{"full_name":"VL3 A","role":"salesperson"}'),
   (v_b, 'vl3b@teste.local', '{"full_name":"VL3 B","role":"salesperson"}');

  if brain.keep_authorship(v_a, v_a) is distinct from v_a then
    raise exception 'VL3 FALHOU: sem troca deveria manter';
  end if;
  if brain.keep_authorship(v_b, v_a) is distinct from v_a then
    raise exception 'VL3 FALHOU: troca por outro perfil deveria ser ignorada';
  end if;
  if brain.keep_authorship(null, v_a) is distinct from v_a then
    raise exception 'VL3 FALHOU: anular com o perfil vivo deveria ser ignorado';
  end if;
  if brain.keep_authorship(null, v_sumido) is not null then
    raise exception 'VL3 FALHOU: anular com o perfil ausente deveria passar';
  end if;

  delete from auth.users where id in (v_a, v_b);
  raise notice ' VL3) OK: mantem / ignora troca / ignora nulo com perfil vivo / aceita nulo com perfil ausente';
end
$$;
