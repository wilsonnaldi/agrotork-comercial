-- ============================================================
-- Excluir cliente (migration 20260903110000).
--
-- A lacuna que este arquivo fecha: a suíte de cadastro cobria criar,
-- editar e desativar cliente — nunca excluir. O `update deleted_at` que
-- a aplicação fazia era recusado pelo próprio PostgreSQL, e ninguém
-- percebeu porque o caminho nunca foi exercitado contra o banco.
--
-- O que este arquivo prova:
--   · o UPDATE direto continua recusado (é o defeito, documentado);
--   · a função exclui, e a linha continua no banco;
--   · cliente com orçamento não se exclui — se desativa;
--   · cliente com pedido também não, mesmo sem orçamento vivo;
--   · o vendedor não exclui cliente nenhum.
-- ============================================================
reset role;

-- Prefixo de UUID = numero da suite. Os prefixos de letra (aaaa…, ffff…)
-- acabaram, e colisao entre suites so aparece na hora de rodar.
insert into auth.users (id, email, raw_user_meta_data) values
 ('20202020-0000-4000-8000-00000000e001','excl.admin@teste.local','{"full_name":"Admin Exclusao","role":"admin"}'),
 ('20202020-0000-4000-8000-00000000e002','excl.vend@teste.local','{"full_name":"Vendedor Exclusao","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = '20202020-0000-4000-8000-00000000e001';

-- Três clientes: um limpo, um com orçamento, um com pedido.
insert into public.customers (name) values
 ('Cliente Sem Historico'),
 ('Cliente Com Orcamento'),
 ('Cliente Com Pedido');

insert into public.quotes (customer_id, owner_id)
select c.id, '20202020-0000-4000-8000-00000000e002'
  from public.customers c where c.name = 'Cliente Com Orcamento';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '20202020-0000-4000-8000-00000000e001', false);

-- ── EX1: o UPDATE direto é recusado — é o defeito ───────────
do $$
declare v_erro text;
begin
  begin
    update public.customers set deleted_at = now() where name = 'Cliente Sem Historico';
    raise notice 'EX1) FALHA: o UPDATE direto passou — a policy de SELECT afrouxou';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX1) OK: UPDATE direto recusado — %', left(v_erro, 52);
  end;
end $$;

-- ── EX2: a função exclui, e a linha continua no banco ───────
do $$
declare v_visivel int; v_marcado int;
begin
  perform public.delete_customer(
    (select id from public.customers where name = 'Cliente Sem Historico'));

  select count(*)::int into v_visivel
    from public.customers where name = 'Cliente Sem Historico';

  reset role;
  select count(*)::int into v_marcado
    from public.customers where name = 'Cliente Sem Historico' and deleted_at is not null;

  if v_visivel = 0 and v_marcado = 1
    then raise notice 'EX2) OK: sumiu da listagem e a linha continua no banco';
    else raise notice 'EX2) FALHA: visivel % / marcado %', v_visivel, v_marcado; end if;
end $$;

-- ── EX3: cliente com orçamento não se exclui ────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '20202020-0000-4000-8000-00000000e001', false);

do $$
declare v_erro text; v_ainda int;
begin
  begin
    perform public.delete_customer(
      (select id from public.customers where name = 'Cliente Com Orcamento'));
    raise notice 'EX3) FALHA: excluiu cliente com orcamento';
  exception when foreign_key_violation then
    get stacked diagnostics v_erro = message_text;
    select count(*)::int into v_ainda
      from public.customers where name = 'Cliente Com Orcamento';
    if v_ainda = 1
      then raise notice 'EX3) OK: recusado e cliente intacto — %', left(v_erro, 48);
      else raise notice 'EX3) FALHA: recusou mas o cliente sumiu'; end if;
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX3) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── EX4: o histórico de OUTRO vendedor também barra ─────────
-- A checagem que existia em `service.ts` lia os orçamentos com o RLS do
-- usuário. Um administrador que não enxergasse o orçamento do vendedor
-- excluiria o cliente assim mesmo. A função conta sem RLS, de propósito.
do $$
declare v_dono uuid;
begin
  reset role;
  select owner_id into v_dono from public.quotes q
    join public.customers c on c.id = q.customer_id
   where c.name = 'Cliente Com Orcamento' limit 1;

  if v_dono = '20202020-0000-4000-8000-00000000e002'
    then raise notice 'EX4) OK: o orcamento que barrou EX3 e de outro vendedor';
    else raise notice 'EX4) FALHA: dono inesperado %', v_dono; end if;
end $$;

-- ── EX5: cliente com pedido, sem orçamento vivo, também barra ─
-- O orçamento pode ter sido descartado depois de virar pedido. Contar só
-- orçamento deixaria o cliente do pedido órfão.
set role authenticated;
select set_config('request.jwt.claim.sub', '20202020-0000-4000-8000-00000000e001', false);

do $$
declare v_q uuid; v_erro text;
begin
  reset role;
  insert into public.quotes (customer_id, owner_id, status)
  select c.id, '20202020-0000-4000-8000-00000000e002', 'approved'
    from public.customers c where c.name = 'Cliente Com Pedido'
  returning id into v_q;

  perform public.create_order_from_quote(v_q);

  -- Some o orçamento: sobra só o pedido apontando para o cliente.
  update public.quotes set deleted_at = now() where id = v_q;

  set role authenticated;
  begin
    perform public.delete_customer(
      (select id from public.customers where name = 'Cliente Com Pedido'));
    raise notice 'EX5) FALHA: excluiu cliente que tem pedido';
  exception when foreign_key_violation then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX5) OK: pedido tambem barra a exclusao — %', left(v_erro, 48);
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX5) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── EX6: o vendedor não exclui cliente ──────────────────────
select set_config('request.jwt.claim.sub', '20202020-0000-4000-8000-00000000e002', false);

do $$
declare v_erro text; v_id uuid;
begin
  insert into public.customers (name) values ('Cliente do Vendedor') returning id into v_id;
  begin
    perform public.delete_customer(v_id);
    raise notice 'EX6) FALHA: vendedor excluiu cliente';
  exception when insufficient_privilege then
    raise notice 'EX6) OK: vendedor cadastra cliente, mas nao exclui';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX6) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── EX7: anônimo não alcança a função ───────────────────────
do $$
declare v_erro text;
begin
  reset role;
  set local role anon;
  begin
    perform public.delete_customer(gen_random_uuid());
    raise notice 'EX7) FALHA: anonimo executou delete_customer';
  exception when insufficient_privilege then
    raise notice 'EX7) OK: anonimo sem privilegio de execucao';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'EX7) OK: anonimo barrado — %', left(v_erro, 45);
  end;
end $$;

reset role;
