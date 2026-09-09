-- ============================================================
-- Trava do orçamento aprovado e proteção do perfil.
-- Regressão das brechas encontradas na auditoria de 29/08/2026.
-- ============================================================
insert into auth.users (id, email, raw_user_meta_data) values
 ('33333333-3333-3333-3333-333333333333','trava.admin@teste.local','{"full_name":"Admin Trava","role":"admin"}'),
 ('44444444-4444-4444-4444-444444444444','trava.vend@teste.local','{"full_name":"Vendedor Trava","role":"salesperson"}');

-- O papel NÃO vem mais do metadata (migration 2100): o trigger cria todo
-- mundo como `salesperson`. Promover é operação explícita — exatamente o
-- que o SETUP.md §5.3 manda fazer em produção. A fixture faz o mesmo.
update public.profiles set role = 'admin'
 where id in (
 '33333333-3333-3333-3333-333333333333'
 );


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

-- ════════════════════════════════════════════════════════════
-- V–X) Guardas da migration 20260909100000 (achados A2 e A6)
-- ════════════════════════════════════════════════════════════

-- V) o dono NÃO reescreve número, sequência, carimbos e autoria do
--    próprio rascunho; o estado fica como estava.
set role authenticated;
set request.jwt.claim.sub='44444444-4444-4444-4444-444444444444';
set request.jwt.claim.role='authenticated';
do $$
declare v_q uuid; v_num text; v_seq int; v_created timestamptz; v_ok boolean := true;
begin
  select id, number, sequence_number, created_at into v_q, v_num, v_seq, v_created
    from public.quotes where owner_id='44444444-4444-4444-4444-444444444444' and status='draft' limit 1;

  begin
    update public.quotes set number='ORC-2019-0001', sequence_year=2019, sequence_number=1 where id=v_q;
    v_ok := false;
  exception when check_violation then null; end;
  begin
    update public.quotes set approved_at='2019-01-03', sent_at='2019-01-02' where id=v_q;
    v_ok := false;
  exception when check_violation then null; end;
  begin
    update public.quotes set created_at='2019-01-01', created_by=null where id=v_q;
    v_ok := false;
  exception when check_violation then null; end;
  begin
    update public.quotes set revision=99, supersedes_quote_id=v_q where id=v_q;
    v_ok := false;
  exception when check_violation then null; end;

  if v_ok and (select number from public.quotes where id=v_q) = v_num
     and (select sequence_number from public.quotes where id=v_q) = v_seq
     and (select created_at from public.quotes where id=v_q) = v_created
     and (select approved_at from public.quotes where id=v_q) is null
    then raise notice 'V) OK: numero, carimbos e autoria do orcamento nao sao do vendedor';
    else raise notice 'V) FALHA: alguma coluna de controle foi aceita (numero agora %)',
      (select number from public.quotes where id=v_q); end if;
end $$;

-- W) `issue_date` continua sendo formulário: o dono muda.
do $$
declare v_q uuid;
begin
  select id into v_q from public.quotes
   where owner_id='44444444-4444-4444-4444-444444444444' and status='draft' limit 1;
  update public.quotes set issue_date = current_date - 3 where id=v_q;
  if (select issue_date from public.quotes where id=v_q) = current_date - 3
    then raise notice 'W) OK: issue_date e do formulario e continua livre';
    else raise notice 'W) FALHA: issue_date nao mudou'; end if;
exception when others then raise notice 'W) FALHA: issue_date barrada (%)', sqlerrm;
end $$;
reset role;

-- X) usuário DESATIVADO não insere item no próprio rascunho (a 0903080000
--    tinha perdido o is_active_user() de quote_is_editable).
update public.profiles set is_active=false where id='44444444-4444-4444-4444-444444444444';
set role authenticated;
set request.jwt.claim.sub='44444444-4444-4444-4444-444444444444';
set request.jwt.claim.role='authenticated';
do $$
declare v_q uuid; v_antes int; v_depois int; v_editavel boolean;
begin
  reset role;
  select id into v_q from public.quotes
   where owner_id='44444444-4444-4444-4444-444444444444' and status='draft' limit 1;
  select count(*) into v_antes from public.quote_items where quote_id=v_q;
  set role authenticated;

  select public.quote_is_editable(v_q) into v_editavel;
  begin
    insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
    values (v_q, 'custom', 'Item do desativado', 1, 10);
  exception when others then null; end;

  reset role;
  select count(*) into v_depois from public.quote_items where quote_id=v_q;
  if not v_editavel and v_depois = v_antes
    then raise notice 'X) OK: usuario desativado nao edita item (quote_is_editable=false, % item(ns) antes e depois)', v_antes;
    else raise notice 'X) FALHA: editavel=% ; itens antes % / depois %', v_editavel, v_antes, v_depois; end if;
end $$;
reset role;
update public.profiles set is_active=true where id='44444444-4444-4444-4444-444444444444';
