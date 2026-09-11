-- ============================================================
-- BRAIN — policies de `channels` (migration 20260911220000).
--
--   PL1  exatamente UMA policy permissiva de SELECT para authenticated;
--   PL2  vendedor ativo lê os canais e NÃO escreve;
--   PL3  administrador escreve (insert, update, delete) e a leitura
--        continua igual;
--   PL4  nenhuma tabela do brain com policy permissiva duplicada por
--        (papel, ação) — a medida do advisor.
--
-- Prefixo de UUID = 32.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('32323232-0000-4000-8000-000000000001','pl.admin@teste.local','{"full_name":"Admin Policies","role":"admin"}'),
 ('32323232-0000-4000-8000-000000000002','pl.vend@teste.local' ,'{"full_name":"Vendedor Policies","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '32323232-0000-4000-8000-000000000001';

do $$
declare v_n int;
begin
  select count(*) into v_n from pg_policies
   where schemaname='brain' and tablename='channels' and permissive='PERMISSIVE'
     and 'authenticated' = any(roles) and cmd in ('SELECT','ALL');
  if v_n <> 1 then raise exception 'PL1 FALHOU: % policies permissivas cobrem SELECT em channels', v_n; end if;
  raise notice ' PL1) OK: uma policy so cobre o SELECT de channels';
end
$$;

-- PL2: vendedor lê, não escreve
do $$
declare v_n int;
begin
  perform set_config('request.jwt.claim.sub','32323232-0000-4000-8000-000000000002',false);
  set local role authenticated;
  select count(*) into v_n from brain.channels;
  if v_n < 12 then raise exception 'PL2 FALHOU: vendedor viu % canais', v_n; end if;
  begin
    insert into brain.channels (key, name) values ('pl_teste', 'Canal do vendedor');
    raise exception 'PL2 FALHOU: vendedor inseriu canal';
  exception when insufficient_privilege then null;
  end;
  update brain.channels set name = name where key = 'other';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'PL2 FALHOU: vendedor atualizou % canal(is)', v_n; end if;
  delete from brain.channels where key = 'other';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'PL2 FALHOU: vendedor apagou % canal(is)', v_n; end if;
  reset role;
  raise notice ' PL2) OK: vendedor le os canais e nao escreve';
end
$$;

-- PL3: administrador escreve
do $$
declare v_n int;
begin
  perform set_config('request.jwt.claim.sub','32323232-0000-4000-8000-000000000001',false);
  set local role authenticated;
  insert into brain.channels (key, name, kind, sort_order) values ('pl_teste', 'Canal de teste', 'other', 999);
  update brain.channels set name = 'Canal de teste 2' where key = 'pl_teste';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'PL3 FALHOU: update afetou %', v_n; end if;
  delete from brain.channels where key = 'pl_teste';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'PL3 FALHOU: delete afetou %', v_n; end if;
  select count(*) into v_n from brain.channels;
  if v_n < 12 then raise exception 'PL3 FALHOU: administrador viu % canais', v_n; end if;
  reset role;
  raise notice ' PL3) OK: administrador insere, atualiza e apaga; a leitura continua';
end
$$;

do $$
declare r record;
begin
  for r in
    select tablename, roles, cmd, count(*) as n from pg_policies
     where schemaname='brain' and permissive='PERMISSIVE'
     group by tablename, roles, cmd having count(*) > 1
  loop
    raise exception 'PL4 FALHOU: brain.% com % policies para % em %', r.tablename, r.n, r.roles, r.cmd;
  end loop;
  raise notice ' PL4) OK: nenhuma policy permissiva duplicada no brain';
end
$$;

reset role;
delete from auth.users where id in ('32323232-0000-4000-8000-000000000001','32323232-0000-4000-8000-000000000002');
