\set ON_ERROR_STOP on
-- No Supabase real, `anon/authenticated` já recebem grants por default privileges.
-- No stub precisamos conceder na mão para testar as policies.

-- segundo usuário: vendedor
insert into auth.users (id, email, raw_user_meta_data)
values ('22222222-2222-2222-2222-222222222222', 'vendedor@agrotork.com.br', '{"full_name":"Vendedor Teste","role":"salesperson"}'::jsonb);

-- orçamento pertencente ao vendedor
insert into public.quotes (customer_id, owner_id)
select c.id, '22222222-2222-2222-2222-222222222222' from public.customers c limit 1;

reset role;
select 'total de orçamentos no banco' as contexto, count(*) from public.quotes;

-- ── Contexto: VENDEDOR ───────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
set request.jwt.claim.role = 'authenticated';

select 'A) vendedor enxerga orçamentos' as teste, count(*) as visiveis from public.quotes;
select 'B) vendedor lê catálogo' as teste, count(*) as produtos from public.products;
select 'C) vendedor lê clientes' as teste, count(*) as clientes from public.customers;

-- não pode criar produto
do $$
begin
  insert into public.products (code, name, unit_id, sale_price)
  select 'X-999','Proibido', u.id, 10 from public.units u limit 1;
  raise notice 'D) FALHA DE SEGURANÇA: vendedor criou produto';
exception when insufficient_privilege or others then
  raise notice 'D) OK: vendedor bloqueado ao criar produto (%)', sqlerrm;
end $$;

-- não pode ler app_settings que não seja 'company'
select 'E) vendedor em app_settings' as teste, coalesce(string_agg(key, ','), 'nenhuma') as chaves from public.app_settings;

-- pode criar cliente
insert into public.customers (name) values ('Cliente do Vendedor');
select 'F) vendedor criou cliente' as teste, count(*) from public.customers where name='Cliente do Vendedor';

-- não pode criar orçamento em nome de outro
do $$
begin
  insert into public.quotes (customer_id, owner_id)
  select c.id, '11111111-1111-1111-1111-111111111111' from public.customers c limit 1;
  raise notice 'G) FALHA DE SEGURANÇA: vendedor criou orçamento para outro dono';
exception when others then
  raise notice 'G) OK: vendedor bloqueado ao criar orçamento de outro dono';
end $$;

-- ── Contexto: ADMIN ──────────────────────────────────────────
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select 'H) admin enxerga orçamentos' as teste, count(*) as visiveis from public.quotes;
select 'I) admin em app_settings' as teste, count(*) as chaves from public.app_settings;

-- ── Contexto: ANÔNIMO ────────────────────────────────────────
-- Antes, anon tinha GRANT e era a RLS que devolvia zero linhas. A migration
-- 20260901193812 revogou o próprio GRANT: agora o banco barra um degrau antes.
-- O que se afere continua o mesmo — anon não lê nada —, só que de forma mais
-- estrita, então as duas respostas contam como OK.
reset role; set role anon;
do $$
declare v_n bigint;
begin
  begin
    select count(*) into v_n from public.customers;
    if v_n = 0 then raise notice 'J) OK: anonimo nao enxerga clientes (RLS, 0 linhas)';
    else raise notice 'J) FALHA DE SEGURANCA: anonimo viu % cliente(s)', v_n; end if;
  exception when insufficient_privilege then
    raise notice 'J) OK: anonimo sem GRANT em customers (barrado antes da RLS)';
  end;

  begin
    select count(*) into v_n from public.products;
    if v_n = 0 then raise notice 'K) OK: anonimo nao enxerga produtos (RLS, 0 linhas)';
    else raise notice 'K) FALHA DE SEGURANCA: anonimo viu % produto(s)', v_n; end if;
  exception when insufficient_privilege then
    raise notice 'K) OK: anonimo sem GRANT em products (barrado antes da RLS)';
  end;
end $$;
reset role;
