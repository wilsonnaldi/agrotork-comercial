set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
set request.jwt.claim.role = 'authenticated';

-- O vendedor cria o PRÓPRIO orçamento: dispara assign_quote_number()
-- e, ao inserir item, recalculate_quote_totals() — ambas com EXECUTE
-- revogado de authenticated. Se os triggers rodarem, a revogação é segura.
insert into public.quotes (customer_id, owner_id)
select c.id, '22222222-2222-2222-2222-222222222222' from public.customers c limit 1
returning number as "L) numero gerado pelo trigger (como vendedor)";

insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
select q.id, 'custom', 'Serviço de instalação', 2, 250.00
from public.quotes q where q.owner_id = '22222222-2222-2222-2222-222222222222'
order by q.created_at desc limit 1;

select 'M) total recalculado (como vendedor)' as teste, number, subtotal, total
from public.quotes where owner_id='22222222-2222-2222-2222-222222222222' order by created_at desc limit 1;

-- Chamada DIRETA às funções administrativas deve ser negada
do $$ begin
  perform public.expire_quotes();
  raise notice 'N) FALHA: vendedor executou expire_quotes()';
exception when insufficient_privilege then raise notice 'N) OK: expire_quotes() negada ao vendedor';
end $$;

do $$ begin
  perform public.next_quote_number(2026);
  raise notice 'O) FALHA: vendedor executou next_quote_number()';
exception when insufficient_privilege then raise notice 'O) OK: next_quote_number() negada ao vendedor';
end $$;
reset role;

-- ════════════════════════════════════════════════════════════════════
-- SA1–SA4) EXECUTE dos ajudantes de autorização: o que pode e o que NÃO
--      pode ser revogado de `authenticated`.
--
-- O Security Advisor do Supabase sinaliza is_admin(), is_active_user(),
-- auth_role(), owns_quote() e quote_is_editable() como
-- "SECURITY DEFINER executável por authenticated" e sugere revogar o
-- EXECUTE. A sugestão é PERIGOSA aqui, e o motivo não é óbvio:
--
--   · Dentro de uma POLICY de RLS, a expressão é avaliada com o
--     privilégio do DONO da tabela — revogar não quebra o SELECT.
--   · Mas `validate_quote_status_transition()` é um trigger
--     SECURITY INVOKER que chama is_admin(). Ele roda com o privilégio
--     de QUEM disparou o UPDATE. Sem EXECUTE, toda troca de status de
--     orçamento passa a falhar com "permission denied for function".
--
-- Os testes abaixo fixam essa distinção. Se alguém revogar o EXECUTE
-- para fechar o aviso do Advisor, SA4) falha aqui — e não em produção,
-- na mão de um vendedor tentando enviar um orçamento.
-- ════════════════════════════════════════════════════════════════════

do $$
declare v_ok boolean;
begin
  select has_function_privilege('authenticated','public.is_admin()','execute') into v_ok;
  if v_ok then raise notice 'SA1) OK: authenticated mantem EXECUTE em is_admin() — exigido pelo trigger de status';
  else raise notice 'SA1) FALHA: EXECUTE em is_admin() foi revogado de authenticated. Ver SA4).'; end if;
end $$;

do $$
declare v_secdef boolean;
begin
  select p.prosecdef into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='validate_quote_status_transition';
  if v_secdef is false then
    raise notice 'SA2) OK: validate_quote_status_transition() e SECURITY INVOKER — por isso depende do EXECUTE do chamador';
  else
    raise notice 'SA2) ATENCAO: a funcao virou SECURITY DEFINER. Reavaliar SA1) e SA4): o EXECUTE talvez possa ser revogado agora.';
  end if;
end $$;

-- R) A policy continua funcionando mesmo sem EXECUTE para o chamador:
--    prova de que o problema NAO esta na RLS.
do $$
declare v_n bigint;
begin
  revoke execute on function public.is_admin() from authenticated;
  set local role authenticated;
  select count(*) into v_n from public.products;
  reset role;
  raise notice 'SA3) OK: sem EXECUTE, a RLS de products continua avaliando (viu % linha(s)) — policy roda com o privilegio do dono', v_n;
exception when others then
  reset role;
  raise notice 'SA3) INESPERADO: a RLS falhou sem EXECUTE (%). Rever a analise.', sqlerrm;
end $$;

-- S) O trigger de status, esse sim, quebra.
do $$
declare v_id uuid;
begin
  select id into v_id from public.quotes
   where owner_id='22222222-2222-2222-2222-222222222222' and status='draft'
   order by created_at desc limit 1;

  if v_id is null then
    raise notice 'SA4) PULADO: nenhum rascunho do vendedor para testar';
  else
    begin
      set local role authenticated;
      update public.quotes set status='sent' where id = v_id;
      reset role;
      raise notice 'SA4) FALHA: a troca de status funcionou SEM EXECUTE em is_admin(). A dependencia mudou — reavaliar SA1).';
    exception when insufficient_privilege then
      reset role;
      raise notice 'SA4) OK: sem EXECUTE em is_admin(), a troca de status e negada. E por isso que o EXECUTE NAO pode ser revogado.';
    end;
  end if;
  grant execute on function public.is_admin() to authenticated;
end $$;

-- ════════════════════════════════════════════════════════════════════
-- SA5–SA9) Privilégios estruturais (migrations 20260909100000/110000:
--      achados A7, A10, A11, A15, A16). Estruturais: valem para TODAS
--      as tabelas e funções de `public`, inclusive as que vierem depois.
-- ════════════════════════════════════════════════════════════════════
reset role;

-- SA5) toda tabela de public tem RLS ligado (purchase_sequences nasceu sem).
do $$
declare v_sem text;
begin
  select string_agg(relname, ', ') into v_sem
    from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity;
  if v_sem is null then raise notice 'SA5) OK: todas as tabelas de public tem RLS ligado';
  else raise notice 'SA5) FALHA: sem RLS: %', v_sem; end if;
end $$;

-- SA6) contador e recálculo do pedido não são RPC do vendedor — testado
--      executando, como o vendedor, e conferindo que o contador não andou.
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
set request.jwt.claim.role = 'authenticated';
do $$
declare v_antes int; v_depois int; v_negadas int := 0;
begin
  reset role;
  select coalesce(max(last_number), 0) into v_antes from public.order_sequences;
  set role authenticated;
  begin perform public.next_order_number(2026);
  exception when insufficient_privilege then v_negadas := v_negadas + 1; end;
  begin perform public.recalculate_order_totals(gen_random_uuid());
  exception when insufficient_privilege then v_negadas := v_negadas + 1; end;
  begin perform public.next_purchase_number(2026);
  exception when insufficient_privilege then v_negadas := v_negadas + 1; end;
  begin perform public.refresh_financial_status(gen_random_uuid());
  exception when insufficient_privilege then v_negadas := v_negadas + 1; end;
  reset role;
  select coalesce(max(last_number), 0) into v_depois from public.order_sequences;
  if v_negadas = 4 and v_antes = v_depois
    then raise notice 'SA6) OK: 4 funcoes internas negadas ao vendedor; contador de pedido parado em %', v_depois;
    else raise notice 'SA6) FALHA: % negada(s) de 4; contador % -> %', v_negadas, v_antes, v_depois; end if;
end $$;
reset role;

-- SA7) TRUNCATE fora do alcance de authenticated/anon, em tudo — e o
--      default para tabela futura também.
do $$
declare v_com text; v_default text;
begin
  select string_agg(relname, ', ') into v_com
    from pg_class c where relnamespace='public'::regnamespace and relkind in ('r','v')
     and (has_table_privilege('authenticated', c.oid, 'truncate') or has_table_privilege('anon', c.oid, 'truncate'));
  select string_agg(defaclacl::text, ' ') into v_default
    from pg_default_acl where defaclnamespace='public'::regnamespace and defaclobjtype='r'
     and (defaclacl::text ~ 'authenticated=[a-zA-Z]*D' or defaclacl::text ~ 'anon=');
  if v_com is null and v_default is null
    then raise notice 'SA7) OK: nenhuma tabela com TRUNCATE para a API; default privileges limpos';
    else raise notice 'SA7) FALHA: truncate em [%]; default [%]', coalesce(v_com,'-'), coalesce(v_default,'-'); end if;
end $$;

-- SA8) toda security definer de public declara search_path = ''.
do $$
declare v_ruins text;
begin
  select string_agg(proname, ', ') into v_ruins
    from pg_proc where pronamespace='public'::regnamespace and prosecdef
     and coalesce(array_to_string(proconfig, ','), '') <> 'search_path=""';
  if v_ruins is null then raise notice 'SA8) OK: todas as security definer com search_path vazio';
  else raise notice 'SA8) FALHA: search_path fora do padrao em: %', v_ruins; end if;
end $$;

-- SA9) anon não tem privilégio algum em tabela ou view de public, e as
--      funções de margem só respondem a quem está logado.
do $$
declare v_tab text; v_fn text;
begin
  select string_agg(relname, ', ') into v_tab
    from pg_class c where relnamespace='public'::regnamespace and relkind in ('r','v')
     and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert'));
  select string_agg(p.oid::regprocedure::text, ', ') into v_fn
    from pg_proc p where pronamespace='public'::regnamespace
     and proname in ('suggested_sale_price','apply_margin_rules','round_commercial','next_order_number','next_purchase_number')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  if v_tab is null and v_fn is null
    then raise notice 'SA9) OK: anon sem privilegio em tabela/view; funcoes de margem e contadores sem EXECUTE para anon/public';
    else raise notice 'SA9) FALHA: tabelas [%]; funcoes [%]', coalesce(v_tab,'-'), coalesce(v_fn,'-'); end if;
end $$;
reset role;
