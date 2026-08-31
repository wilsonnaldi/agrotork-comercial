-- ============================================================
-- CADASTRO: papel de administrador não se concede por metadata.
--
-- O trigger `handle_new_user` é o ÚNICO ponto do sistema que escreve em
-- `profiles` sem passar por RLS — é `security definer`. Antes da migration
-- 2100 ele lia `raw_user_meta_data ->> 'role'`, que é escrito por quem se
-- cadastra. Estes testes existem para que essa porta não reabra.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

-- ── Um usuário por variação de metadata ─────────────────────
-- Cada insert em auth.users dispara o trigger, que é o que se testa.
insert into auth.users (id, email, raw_user_meta_data) values
 ('cccccccc-0000-4000-8000-00000000c001', 'esperto1@teste.local',
  '{"full_name":"Esperto Um","role":"admin"}'::jsonb),
 ('cccccccc-0000-4000-8000-00000000c002', 'esperto2@teste.local',
  '{"full_name":"Esperto Dois","role":"admin","is_admin":true}'::jsonb),
 ('cccccccc-0000-4000-8000-00000000c003', 'esperto3@teste.local',
  '{"full_name":"Esperto Tres","role":"salesperson","is_admin":true,"admin":true}'::jsonb),
 ('cccccccc-0000-4000-8000-00000000c004', 'normal@teste.local',
  '{"full_name":"Usuario Normal"}'::jsonb),
 ('cccccccc-0000-4000-8000-00000000c005', 'semmeta@teste.local', '{}'::jsonb);

select 'HA) metadata role=admin nao promove' as teste,
       case when role = 'salesperson' then 'OK' else 'FALHA DE SEGURANCA: ' || role end as resultado
from public.profiles where id = 'cccccccc-0000-4000-8000-00000000c001';

select 'HB) role=admin + is_admin=true nao promove' as teste,
       case when role = 'salesperson' then 'OK' else 'FALHA DE SEGURANCA: ' || role end as resultado
from public.profiles where id = 'cccccccc-0000-4000-8000-00000000c002';

select 'HC) is_admin/admin soltos no metadata nao promovem' as teste,
       case when role = 'salesperson' then 'OK' else 'FALHA DE SEGURANCA: ' || role end as resultado
from public.profiles where id = 'cccccccc-0000-4000-8000-00000000c003';

select 'HD) cadastro normal continua funcionando' as teste,
       case when role = 'salesperson' and full_name = 'Usuario Normal'
                 and email = 'normal@teste.local' and is_active
            then 'OK: perfil criado, ativo, vendedor'
            else 'FALHA' end as resultado
from public.profiles where id = 'cccccccc-0000-4000-8000-00000000c004';

select 'HE) metadata vazio nao quebra o cadastro' as teste,
       case when role = 'salesperson' and full_name = '' then 'OK' else 'FALHA' end as resultado
from public.profiles where id = 'cccccccc-0000-4000-8000-00000000c005';

-- ── Variações de grafia e valores inválidos ─────────────────
-- `ADMIN` e `service_role` não são valores do enum `user_role`. Antes da
-- 2100 o cast estouraria e o INSERT em auth.users falharia junto — o
-- cadastro inteiro quebrava. Agora o metadata simplesmente não é lido.
do $$
declare grafia text;
begin
  foreach grafia in array array['ADMIN','Admin','service_role','superuser','postgres',' admin ']
  loop
    begin
      insert into auth.users (id, email, raw_user_meta_data)
      values (gen_random_uuid(), 'v' || md5(grafia) || '@teste.local',
              jsonb_build_object('role', grafia));
    exception when others then
      raise notice 'HF) FALHA: cadastro quebrou com role=%: %', grafia, sqlerrm;
    end;
  end loop;
end $$;

select 'HF) nenhuma grafia de role criou administrador' as teste,
       case when count(*) filter (where role <> 'salesperson') = 0
            then 'OK: ' || count(*) || ' usuarios, todos vendedores'
            else 'FALHA DE SEGURANCA: ' || count(*) filter (where role <> 'salesperson') || ' promovido(s)' end as resultado
from public.profiles where email like 'v%@teste.local';

-- ── O administrador legítimo continua administrador ─────────
select 'HG) admin existente nao foi rebaixado' as teste,
       case when role = 'admin' and is_active then 'OK' else 'FALHA: ' || role end as resultado
from public.profiles where id = '11111111-1111-1111-1111-111111111111';

-- ── Promoção continua possível para quem é administrador ────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

do $$ declare afetadas int; begin
  update public.profiles set role = 'admin'
   where id = 'cccccccc-0000-4000-8000-00000000c004';
  get diagnostics afetadas = row_count;
  if afetadas = 1 then raise notice 'HH) OK: administrador promove outro usuario';
  else raise notice 'HH) FALHA: administrador nao conseguiu promover (% linhas)', afetadas; end if;
end $$;

-- ── O vendedor continua sem conseguir se promover ───────────
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

do $$ declare afetadas int; begin
  update public.profiles set role = 'admin'
   where id = '22222222-2222-2222-2222-222222222222';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'HI) OK: vendedor nao se promove (RLS)';
  else raise notice 'HI) FALHA DE SEGURANCA: vendedor se promoveu'; end if;
exception when others then
  raise notice 'HI) OK: vendedor nao se promove (recusado: %)', sqlerrm;
end $$;

-- E também não promove outro vendedor.
do $$ declare afetadas int; begin
  update public.profiles set role = 'admin'
   where id = 'cccccccc-0000-4000-8000-00000000c001';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'HJ) OK: vendedor nao promove terceiro';
  else raise notice 'HJ) FALHA DE SEGURANCA: vendedor promoveu terceiro'; end if;
exception when others then
  raise notice 'HJ) OK: vendedor nao promove terceiro (recusado)';
end $$;

-- ── O vendedor recém-criado continua sem custo ──────────────
select set_config('request.jwt.claim.sub', 'cccccccc-0000-4000-8000-00000000c001', false);

select 'HK) vendedor novo nao le custo' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA DE SEGURANCA: viu ' || count(*) end as resultado
from public.product_costs;

select 'HL) vendedor novo nao ve custo na view' as teste,
       case when count(*) filter (where cost_price is not null) = 0
            then 'OK: custo nulo em products_list'
            else 'FALHA DE SEGURANCA' end as resultado
from public.products_list;

-- ── Usuário desativado continua barrado ─────────────────────
reset role;
update public.profiles set is_active = false
 where id = 'cccccccc-0000-4000-8000-00000000c003';

set role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-0000-4000-8000-00000000c003', false);

select 'HM) usuario desativado nao enxerga produto' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA: viu ' || count(*) end as resultado
from public.products;

select 'HN) is_active_user() reprova o desativado' as teste,
       case when public.is_active_user() then 'FALHA' else 'OK' end as resultado;

reset role;
