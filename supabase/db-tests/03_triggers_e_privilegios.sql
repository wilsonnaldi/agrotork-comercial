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
