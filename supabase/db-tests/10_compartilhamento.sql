-- ============================================================
-- COMPARTILHAMENTO: token, expiração, revogação e leitura pública.
--
-- O teste central é o de vazamento: `get_shared_quote()` é o ÚNICO
-- caminho pelo qual alguém sem login enxerga um orçamento, e ele não
-- pode devolver custo, observação interna nem id de nada.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

-- ── Orçamento compartilhável do ADMIN ───────────────────────
insert into public.customers (name, city, state) values ('Cliente do Link', 'Cambé', 'PR');

insert into public.products (code, name, unit_id, sale_price)
select 'SHR-P1', 'Produto do link', u.id, 400 from public.units u where u.code = 'UN';

insert into public.quotes (customer_id, owner_id, valid_until, payment_terms, notes, internal_notes)
select c.id, '11111111-1111-1111-1111-111111111111', current_date + 10,
       'À vista', 'Observação pública', 'SEGREDO INTERNO NAO PODE VAZAR'
from public.customers c where c.name = 'Cliente do Link';

insert into public.quote_items
  (quote_id, kind, product_id, code_snapshot, name_snapshot, unit_snapshot, quantity, unit_price, unit_cost_snapshot)
select q.id, 'product', p.id, p.code, p.name, 'UN', 2, p.sale_price, 123.45
from public.quotes q, public.products p
where p.code = 'SHR-P1'
  and q.customer_id = (select id from public.customers where name = 'Cliente do Link');

update public.quotes set status = 'sent'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');

-- ── CRIAÇÃO DO TOKEN ────────────────────────────────────────
insert into public.quote_share_tokens (quote_id, created_by)
select q.id, '11111111-1111-1111-1111-111111111111' from public.quotes q
where q.customer_id = (select id from public.customers where name = 'Cliente do Link');

select 'FE) token gerado pelo banco' as teste,
       length(token) as tamanho,
       case when length(token) = 48 and token ~ '^[0-9a-f]+$' then 'OK: 48 hex aleatórios'
            else 'FALHA' end as resultado
from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Link');

insert into public.quote_share_tokens (quote_id)
select q.id from public.quotes q
where q.customer_id = (select id from public.customers where name = 'Cliente do Link');

select 'FF) tokens sao imprevisiveis entre si' as teste,
       case when count(distinct token) = 2 then 'OK: dois valores distintos' else 'FALHA' end as resultado
from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Link');

do $$
declare v_token text; v_quote uuid;
begin
  select token into v_token from public.quote_share_tokens limit 1;
  select id into v_quote from public.quotes limit 1;
  insert into public.quote_share_tokens (quote_id, token) values (v_quote, v_token);
  raise notice 'FG) FALHA: aceitou token repetido';
exception when unique_violation then raise notice 'FG) OK: token e unico';
end $$;

create temporary table shr_token as
select ts.id, ts.token from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Link')
order by ts.created_at limit 1;
grant select on shr_token to public;

-- ── LEITURA PÚBLICA ─────────────────────────────────────────
reset role; set role anon;

select 'FH) anonimo nao le quotes direto' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA: viu ' || count(*) end as resultado
from public.quotes;

select 'FI) anonimo nao le quote_items direto' as teste,
       case when count(*) = 0 then 'OK: nenhuma linha' else 'FALHA: viu ' || count(*) end as resultado
from public.quote_items;

select 'FJ) token valido abre o orcamento' as teste,
       (public.get_shared_quote((select token from shr_token)) ->> 'number') as numero,
       case when public.get_shared_quote((select token from shr_token)) is not null
            then 'OK' else 'FALHA' end as resultado;

select 'FK) payload traz itens e totais' as teste,
       jsonb_array_length(public.get_shared_quote((select token from shr_token)) -> 'items') as itens,
       public.get_shared_quote((select token from shr_token)) ->> 'total' as total,
       case when (public.get_shared_quote((select token from shr_token)) ->> 'total') = '800.00'
            then 'OK' else 'FALHA' end as resultado;

-- ══ O TESTE QUE MAIS IMPORTA: o que NÃO pode aparecer ══
select 'FL) payload publico nao vaza custo nem dado interno' as teste,
       case
         when payload::text ilike '%SEGREDO INTERNO%' then 'FALHA: observacao interna vazou'
         when payload::text ilike '%unit_cost%'       then 'FALHA: campo de custo vazou'
         when payload::text like '%123.45%'           then 'FALHA: valor de custo vazou'
         when payload ? 'internal_notes'              then 'FALHA: chave internal_notes'
         when payload ? 'owner_id'                    then 'FALHA: id do vendedor'
         when payload ? 'customer_id'                 then 'FALHA: id do cliente'
         when payload -> 'customer' ? 'phone'         then 'FALHA: telefone do cliente'
         when payload -> 'customer' ? 'email'         then 'FALHA: e-mail do cliente'
         else 'OK: nada sensível no payload'
       end as resultado
from (select public.get_shared_quote((select token from shr_token)) as payload) p;

select 'FM) payload traz o que a proposta precisa' as teste,
       case when payload ? 'number' and payload ? 'items' and payload ? 'total'
             and payload ? 'company' and payload ? 'customer' and payload ? 'owner_name'
            then 'OK' else 'FALHA' end as resultado
from (select public.get_shared_quote((select token from shr_token)) as payload) p;

-- ── TOKEN INEXISTENTE / ADIVINHADO ──────────────────────────
select 'FN) token inexistente nao abre nada' as teste,
       case when public.get_shared_quote(repeat('a', 48)) is null then 'OK: nulo' else 'FALHA' end as resultado;

select 'FO) token curto e recusado antes da consulta' as teste,
       case when public.get_shared_quote('123') is null then 'OK' else 'FALHA' end as resultado;

select 'FP) token nulo e recusado' as teste,
       case when public.get_shared_quote(null) is null then 'OK' else 'FALHA' end as resultado;

-- ── CONTADOR DE VISUALIZAÇÕES ───────────────────────────────
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select 'FQ) acesso publico conta visualizacao' as teste,
       view_count,
       case when view_count >= 4 then 'OK: contou' else 'FALHA: ' || view_count end as resultado
from public.quote_share_tokens where id = (select id from shr_token);

select 'FR) acesso publico nao altera o orcamento' as teste,
       case when (select total from public.quotes
                  where customer_id = (select id from public.customers where name = 'Cliente do Link')) = 800.00
             and (select count(*) from public.quote_items qi join public.quotes q on q.id = qi.quote_id
                  where q.customer_id = (select id from public.customers where name = 'Cliente do Link')) = 1
            then 'OK: intacto' else 'FALHA' end as resultado;

-- ── SITUAÇÃO DO ORÇAMENTO ───────────────────────────────────
update public.quotes set status = 'draft'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');

reset role; set role anon;
select 'FS) rascunho nao circula pelo link' as teste,
       case when public.get_shared_quote((select token from shr_token)) is null then 'OK' else 'FALHA' end as resultado;

reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quotes set status = 'sent'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');
update public.quotes set status = 'cancelled'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');

reset role; set role anon;
select 'FT) cancelado nao circula pelo link' as teste,
       case when public.get_shared_quote((select token from shr_token)) is null then 'OK' else 'FALHA' end as resultado;

reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quotes set status = 'draft'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');
update public.quotes set status = 'sent'
 where customer_id = (select id from public.customers where name = 'Cliente do Link');

-- ── EXPIRAÇÃO ───────────────────────────────────────────────
update public.quote_share_tokens set expires_at = now() - interval '1 hour'
 where id = (select id from shr_token);

reset role; set role anon;
select 'FU) token expirado nao abre' as teste,
       case when public.get_shared_quote((select token from shr_token)) is null then 'OK' else 'FALHA' end as resultado;

reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quote_share_tokens set expires_at = now() + interval '10 days'
 where id = (select id from shr_token);

reset role; set role anon;
select 'FV) token dentro do prazo volta a abrir' as teste,
       case when public.get_shared_quote((select token from shr_token)) is not null then 'OK' else 'FALHA' end as resultado;

-- ── REVOGAÇÃO ───────────────────────────────────────────────
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quote_share_tokens set revoked_at = now() where id = (select id from shr_token);

select 'FW) revogar nao apaga o token nem o orcamento' as teste,
       case when (select count(*) from public.quote_share_tokens where id = (select id from shr_token)) = 1
             and (select count(*) from public.quotes
                  where customer_id = (select id from public.customers where name = 'Cliente do Link')) = 1
            then 'OK' else 'FALHA' end as resultado;

reset role; set role anon;
select 'FX) token revogado nao abre' as teste,
       case when public.get_shared_quote((select token from shr_token)) is null then 'OK' else 'FALHA' end as resultado;

reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into public.quote_share_tokens (quote_id)
select q.id from public.quotes q
where q.customer_id = (select id from public.customers where name = 'Cliente do Link');

create temporary table shr_novo as
select token from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Link')
  and ts.revoked_at is null
order by ts.created_at desc limit 1;
grant select on shr_novo to public;

reset role; set role anon;
select 'FY) token novo funciona depois da revogacao' as teste,
       case when public.get_shared_quote((select token from shr_novo)) is not null then 'OK' else 'FALHA' end as resultado;

-- ── ISOLAMENTO ENTRE VENDEDORES ─────────────────────────────
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'FZ) vendedor nao enxerga token de orcamento alheio' as teste,
       case when count(*) = 0 then 'OK' else 'FALHA: viu ' || count(*) end as resultado
from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.owner_id = '11111111-1111-1111-1111-111111111111';

do $$ declare afetadas int; begin
  update public.quote_share_tokens set revoked_at = now();
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'GA) OK: vendedor nao revoga token alheio';
  else raise notice 'GA) FALHA DE SEGURANCA: revogou % token(s)', afetadas; end if;
end $$;

do $$ declare v_id uuid; begin
  select id into v_id from public.quotes where owner_id = '11111111-1111-1111-1111-111111111111' limit 1;
  if v_id is null then
    raise notice 'GB) OK: vendedor nem enxerga orcamento alheio para criar link';
  else
    begin
      insert into public.quote_share_tokens (quote_id) values (v_id);
      raise notice 'GB) FALHA DE SEGURANCA: vendedor criou link para orcamento alheio';
    exception when others then raise notice 'GB) OK: vendedor bloqueado ao criar link alheio';
    end;
  end if;
end $$;

-- ── ACESSO CRUZADO ──────────────────────────────────────────
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into public.quotes (customer_id, owner_id)
select c.id, '11111111-1111-1111-1111-111111111111'
from public.customers c where c.name = 'Cliente do Link';

update public.quotes set status = 'sent'
 where customer_id = (select id from public.customers where name = 'Cliente do Link')
   and id not in (select quote_id from public.quote_share_tokens);

insert into public.quote_share_tokens (quote_id)
select id from public.quotes
where customer_id = (select id from public.customers where name = 'Cliente do Link')
  and id not in (select quote_id from public.quote_share_tokens);

create temporary table shr_outro as
select ts.token, q.number, q.id as quote_id from public.quote_share_tokens ts
join public.quotes q on q.id = ts.quote_id
where q.customer_id = (select id from public.customers where name = 'Cliente do Link')
order by ts.created_at desc limit 1;
grant select on shr_outro to public;

reset role; set role anon;
select 'GC) cada token abre somente o seu orcamento' as teste,
       (public.get_shared_quote((select token from shr_novo))  ->> 'number') as primeiro,
       (public.get_shared_quote((select token from shr_outro)) ->> 'number') as segundo,
       case when (public.get_shared_quote((select token from shr_novo)) ->> 'number')
              <> (public.get_shared_quote((select token from shr_outro)) ->> 'number')
            then 'OK: números diferentes' else 'FALHA' end as resultado;

-- ── ORÇAMENTO EXCLUÍDO ──────────────────────────────────────
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update public.quotes set status = 'draft' where id = (select quote_id from shr_outro);
select public.discard_quote_draft((select quote_id from shr_outro));

reset role; set role anon;
select 'GD) link de orcamento descartado nao abre' as teste,
       case when public.get_shared_quote((select token from shr_outro)) is null then 'OK' else 'FALHA' end as resultado;

-- ── INTEGRIDADE ─────────────────────────────────────────────
reset role;
select 'GE) token acompanha a exclusao fisica do orcamento' as teste,
       case when exists (
         select 1 from pg_constraint
         where conrelid = 'public.quote_share_tokens'::regclass and confdeltype = 'c'
       ) then 'OK: on delete cascade' else 'FALHA' end as resultado;

reset role;
