-- ============================================================
-- Trava do orçamento aprovado e proteção do perfil.
-- Regressão das brechas encontradas na auditoria de 29/08/2026.
-- ============================================================
insert into auth.users (id, email, raw_user_meta_data) values
 ('33333333-3333-3333-3333-333333333333','trava.admin@teste.local','{"full_name":"Admin Trava","role":"admin"}'),
 ('44444444-4444-4444-4444-444444444444','trava.vend@teste.local','{"full_name":"Vendedor Trava","role":"salesperson"}');

insert into public.customers (name) values ('Cliente da Trava');

-- um orçamento APROVADO e um RASCUNHO, ambos do mesmo vendedor
insert into public.quotes (customer_id, owner_id, status)
select c.id,'44444444-4444-4444-4444-444444444444','approved' from public.customers c where c.name='Cliente da Trava';
insert into public.quotes (customer_id, owner_id, status)
select c.id,'44444444-4444-4444-4444-444444444444','draft' from public.customers c where c.name='Cliente da Trava';

insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
select q.id,'custom','Item aprovado',1,1000 from public.quotes q
where q.owner_id='44444444-4444-4444-4444-444444444444' and q.status='approved';

set role authenticated;
set request.jwt.claim.sub='44444444-4444-4444-4444-444444444444';

-- P) vendedor NÃO altera item de orçamento aprovado
do $$ declare v numeric; begin
  update public.quote_items set unit_price=1 where name_snapshot='Item aprovado';
  select total into v from public.quotes where status='approved' and owner_id='44444444-4444-4444-4444-444444444444';
  if v = 1 then raise notice 'P) BRECHA: total do aprovado virou %', v;
  else raise notice 'P) OK: aprovado permanece em %', v; end if;
exception when others then raise notice 'P) OK: alteracao bloqueada'; end $$;

-- Q) vendedor NÃO apaga item de orçamento aprovado
do $$ begin
  delete from public.quote_items where name_snapshot='Item aprovado';
  if not exists (select 1 from public.quote_items where name_snapshot='Item aprovado')
    then raise notice 'Q) BRECHA: item do aprovado foi apagado';
    else raise notice 'Q) OK: item do aprovado preservado'; end if;
exception when others then raise notice 'Q) OK: exclusao bloqueada'; end $$;

-- R) vendedor AINDA consegue trabalhar no rascunho (o fluxo principal não pode quebrar)
do $$ declare v numeric; begin
  insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
  select q.id,'custom','Item rascunho',2,300 from public.quotes q
  where q.owner_id='44444444-4444-4444-4444-444444444444' and q.status='draft';
  select total into v from public.quotes where status='draft' and owner_id='44444444-4444-4444-4444-444444444444';
  raise notice 'R) OK: rascunho editavel, total %', v;
exception when others then raise notice 'R) FALHA: rascunho ficou bloqueado (%)', sqlerrm; end $$;

-- S) vendedor não se promove a admin
do $$ begin
  update public.profiles set role='admin' where id='44444444-4444-4444-4444-444444444444';
  if (select role from public.profiles where id='44444444-4444-4444-4444-444444444444')='admin'
    then raise notice 'S) BRECHA: vendedor virou admin';
    else raise notice 'S) OK: promocao ignorada'; end if;
exception when others then raise notice 'S) OK: promocao bloqueada'; end $$;

-- T) usuário desativado não se reativa
reset role;
update public.profiles set is_active=false where id='44444444-4444-4444-4444-444444444444';
set role authenticated;
set request.jwt.claim.sub='44444444-4444-4444-4444-444444444444';
do $$ begin
  update public.profiles set is_active=true where id='44444444-4444-4444-4444-444444444444';
  perform 1;
exception when others then null; end $$;
reset role;
select 'T) usuario desativado' as teste,
       case when is_active then 'BRECHA: reativou sozinho' else 'OK: continua desativado' end as resultado
from public.profiles where id='44444444-4444-4444-4444-444444444444';

-- U) admin ainda consegue corrigir um orçamento aprovado
update public.profiles set is_active=true where id='44444444-4444-4444-4444-444444444444';
set role authenticated;
set request.jwt.claim.sub='33333333-3333-3333-3333-333333333333';
do $$ begin
  update public.quote_items set notes='ajuste do admin' where name_snapshot='Item aprovado';
  raise notice 'U) OK: admin edita orcamento aprovado';
exception when others then raise notice 'U) FALHA: admin bloqueado (%)', sqlerrm; end $$;
reset role;
