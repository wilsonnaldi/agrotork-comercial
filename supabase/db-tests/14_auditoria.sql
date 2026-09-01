-- ============================================================
-- 14 · Trilha de auditoria (Fase 6.3)
--
-- O que este arquivo prova, em ordem: que o evento certo é gravado com o
-- ator certo; que o que NÃO deve virar evento não vira; que o vendedor não
-- enxerga nada; que segredo nenhum entra no log; e que ninguém — nem o
-- dono da tabela — consegue corrigir ou apagar uma linha.
--
-- As asserções são escopadas aos registros que este arquivo cria: a suíte
-- é encadeada e os arquivos anteriores já deixaram eventos no log.
--
-- Prefixo de saída: J.
-- ============================================================
\set ON_ERROR_STOP on

-- ── Fixture ─────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data) values
 ('ffffffff-0000-4000-8000-00000000f001','aud.admin@teste.local','{"full_name":"Admin Auditoria"}'::jsonb),
 ('ffffffff-0000-4000-8000-00000000f002','aud.vend.a@teste.local','{"full_name":"Vendedor Auditoria A"}'::jsonb),
 ('ffffffff-0000-4000-8000-00000000f003','aud.vend.b@teste.local','{"full_name":"Vendedor Auditoria B"}'::jsonb);

-- ── JA) o cadastro de usuário já é auditado, e o ator é o sistema ──
-- Quem insere em auth.users é o GoTrue; o perfil nasce por trigger.
-- Não há sessão, então o ator não pode ser um usuário.
do $$
declare r record;
begin
  select action, actor_kind, actor_user_id, entity_type, entity_label
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-00000000f001';

  if r.action = 'user.created' and r.actor_kind = 'system' and r.actor_user_id is null
     and r.entity_type = 'user' and r.entity_label = 'Admin Auditoria' then
    raise notice 'JA) OK: cadastro de usuario auditado como user.created, ator sistema';
  else
    raise notice 'JA) FALHA: % / % / % / %', r.action, r.actor_kind, r.entity_type, r.entity_label;
  end if;
end $$;

-- ── JB) troca de papel: o evento mais sensível, e o único sem tela ──
update public.profiles set role = 'admin' where id = 'ffffffff-0000-4000-8000-00000000f001';

do $$
declare r record;
begin
  select action, changed_fields, old_data ->> 'role' as de, new_data ->> 'role' as para
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-00000000f001' and action = 'user.role_changed';

  if r.de = 'salesperson' and r.para = 'admin' and r.changed_fields @> array['role'] then
    raise notice 'JB) OK: user.role_changed registrou % -> %', r.de, r.para;
  else
    raise notice 'JB) FALHA: role_changed veio como % -> % (campos %)', r.de, r.para, r.changed_fields;
  end if;
end $$;

-- ── Retrato para as asserções de "não gerou linha" ──────────
create temporary table aud_marco as select coalesce(max(id), 0) as id from public.audit_log;

-- ══════════════════════════════════════════════════════════
-- Criação e alteração, com sessão de verdade
-- ══════════════════════════════════════════════════════════
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f001';
set request.jwt.claim.role = 'authenticated';

insert into public.customers (id, name, document, city, state)
values ('ffffffff-0000-4000-8000-0000000000c1','Fazenda Auditoria','44.555.666/0001-77','Londrina','PR');

reset role;
set request.jwt.claim.sub = '';

do $$
declare r record;
begin
  select action, actor_kind, actor_email, actor_role::text as papel, actor_db_role,
         entity_type, entity_label, old_data, changed_fields,
         (new_data ? 'document') as tem_documento
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000c1' and action = 'customer.created';

  if r.actor_kind = 'user' and r.actor_email = 'aud.admin@teste.local' and r.papel = 'admin'
     and r.actor_db_role = 'authenticated' and r.entity_type = 'customer'
     and r.entity_label = 'Fazenda Auditoria' and r.old_data is null
     and r.changed_fields is null and r.tem_documento then
    raise notice 'JC) OK: customer.created com ator, rotulo e linha inteira; sem old_data';
  else
    raise notice 'JC) FALHA: kind=% email=% papel=% dbrole=% rotulo=% old=% campos=% doc=%',
      r.actor_kind, r.actor_email, r.papel, r.actor_db_role, r.entity_label,
      r.old_data, r.changed_fields, r.tem_documento;
  end if;
end $$;

-- ── JD) alteração grava só o que mudou ──────────────────────
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f001';
update public.customers set phone = '4333334444'
 where id = 'ffffffff-0000-4000-8000-0000000000c1';
reset role;
set request.jwt.claim.sub = '';

do $$
declare r record;
begin
  select changed_fields, old_data, new_data into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000c1' and action = 'customer.updated';

  if r.changed_fields = array['phone']
     and (r.old_data ->> 'phone') is null and (r.new_data ->> 'phone') = '4333334444'
     and not (r.new_data ? 'updated_at') and not (r.new_data ? 'name') then
    raise notice 'JD) OK: diff traz so a coluna alterada, sem updated_at e sem colunas intactas';
  else
    raise notice 'JD) FALHA: campos=% old=% new=%', r.changed_fields, r.old_data, r.new_data;
  end if;
end $$;

-- ── JE) update que não muda nada não gera evento ────────────
do $$
declare v_antes bigint; v_depois bigint;
begin
  select count(*) into v_antes from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000c1';

  update public.customers set phone = '4333334444'
   where id = 'ffffffff-0000-4000-8000-0000000000c1';

  select count(*) into v_depois from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000c1';

  if v_antes = v_depois then
    raise notice 'JE) OK: update sem mudanca real nao gerou evento';
  else
    raise notice 'JE) FALHA: update inocuo gerou % linha(s)', v_depois - v_antes;
  end if;
end $$;

-- ══════════════════════════════════════════════════════════
-- Orçamento: criação, ruído e status
-- ══════════════════════════════════════════════════════════
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f002';

insert into public.quotes (id, customer_id, owner_id, notes)
values ('ffffffff-0000-4000-8000-0000000000a1',
        'ffffffff-0000-4000-8000-0000000000c1',
        'ffffffff-0000-4000-8000-00000000f002', 'AUD-ORCAMENTO');

insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
values ('ffffffff-0000-4000-8000-0000000000a1', 'custom', 'Servico auditado', 2, 300.00);
reset role;
set request.jwt.claim.sub = '';

do $$
declare r record;
begin
  select action, actor_kind, actor_email, actor_role::text as papel, entity_label
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.created';

  if r.actor_email = 'aud.vend.a@teste.local' and r.papel = 'salesperson'
     and r.entity_label like 'ORC-%' then
    raise notice 'JF) OK: quote.created atribuido ao vendedor, rotulo %', r.entity_label;
  else
    raise notice 'JF) FALHA: email=% papel=% rotulo=%', r.actor_email, r.papel, r.entity_label;
  end if;
end $$;

-- ── JG) o recálculo de totais NÃO vira evento fantasma ──────
-- `trg_quote_items_recalc` faz `update quotes set subtotal, total`. Sem o
-- filtro de colunas derivadas, cada item geraria dois eventos.
do $$
declare v_itens integer; v_orcamento integer; v_pai text;
begin
  select count(*) into v_itens from public.audit_log
   where action = 'quote.item_added' and parent_id = 'ffffffff-0000-4000-8000-0000000000a1';

  select count(*) into v_orcamento from public.audit_log
   where action = 'quote.updated' and entity_id = 'ffffffff-0000-4000-8000-0000000000a1';

  select parent_type into v_pai from public.audit_log
   where action = 'quote.item_added' and parent_id = 'ffffffff-0000-4000-8000-0000000000a1';

  if v_itens = 1 and v_orcamento = 0 and v_pai = 'quote' then
    raise notice 'JG) OK: 1 evento de item, 0 quote.updated fantasma, item ligado ao orcamento';
  else
    raise notice 'JG) FALHA: itens=% quote.updated=% parent=%', v_itens, v_orcamento, v_pai;
  end if;
end $$;

-- ── JH) transição de status genérica ────────────────────────
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f002';
update public.quotes set status = 'sent' where id = 'ffffffff-0000-4000-8000-0000000000a1';
reset role;
set request.jwt.claim.sub = '';

do $$
declare r record;
begin
  select action, old_data ->> 'status' as de, new_data ->> 'status' as para, changed_fields
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.status_changed';

  if r.de = 'draft' and r.para = 'sent' and r.changed_fields @> array['status','sent_at'] then
    raise notice 'JH) OK: quote.status_changed % -> %, com o carimbo sent_at junto', r.de, r.para;
  else
    raise notice 'JH) FALHA: % -> % (campos %)', r.de, r.para, r.changed_fields;
  end if;
end $$;

-- ── JI) aprovação vira verbo próprio ────────────────────────
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f001';   -- admin
update public.quotes set status = 'approved' where id = 'ffffffff-0000-4000-8000-0000000000a1';
reset role;
set request.jwt.claim.sub = '';

do $$
declare r record;
begin
  select action, actor_role::text as papel, old_data ->> 'status' as de,
         new_data ->> 'status' as para, (new_data ->> 'approved_at') is not null as carimbou
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.approved';

  if r.de = 'sent' and r.para = 'approved' and r.papel = 'admin' and r.carimbou then
    raise notice 'JI) OK: quote.approved (sent -> approved) pelo administrador, com approved_at';
  else
    raise notice 'JI) FALHA: % -> % papel=% carimbou=%', r.de, r.para, r.papel, r.carimbou;
  end if;
end $$;

-- ── JJ) recusa e cancelamento ───────────────────────────────
-- A migration 20260901201459 fechou a máquina de estados no banco. Sair de
-- 'approved' é privilégio de administrador, e 'rejected' só vem de 'sent'.
-- O que este teste afere é o VERBO registrado na auditoria, não o atalho.
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f001';   -- admin

do $$
declare v_rej integer; v_can integer;
begin
  update public.quotes set status = 'draft'     where id = 'ffffffff-0000-4000-8000-0000000000a1';
  update public.quotes set status = 'sent'      where id = 'ffffffff-0000-4000-8000-0000000000a1';
  update public.quotes set status = 'rejected'  where id = 'ffffffff-0000-4000-8000-0000000000a1';
  update public.quotes set status = 'cancelled' where id = 'ffffffff-0000-4000-8000-0000000000a1';

  select count(*) into v_rej from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.rejected';
  select count(*) into v_can from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.cancelled';

  if v_rej = 1 and v_can = 1 then
    raise notice 'JK) OK: quote.rejected e quote.cancelled com verbos proprios';
  else
    raise notice 'JK) FALHA: rejected=% cancelled=%', v_rej, v_can;
  end if;
end $$;

reset role;
set request.jwt.claim.sub = '';

-- ── JL) expiração pelo cron: ator é o sistema, não um usuário ──
-- Roda exatamente como o pg_cron roda, sem sessão nenhuma.
do $$
declare r record; v_expirados integer;
begin
  update public.quotes set status = 'draft'
   where id = 'ffffffff-0000-4000-8000-0000000000a1';
  update public.quotes
     set status = 'sent', valid_until = current_date - 1
   where id = 'ffffffff-0000-4000-8000-0000000000a1';

  select public.expire_quotes() into v_expirados;

  select action, actor_kind, actor_user_id, actor_db_role,
         old_data ->> 'status' as de, new_data ->> 'status' as para
    into r
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.expired';

  if r.actor_kind = 'system' and r.actor_user_id is null and r.actor_db_role = 'postgres'
     and r.de = 'sent' and r.para = 'expired' then
    raise notice 'JL) OK: quote.expired com ator sistema, sem usuario, % -> %', r.de, r.para;
  else
    raise notice 'JL) FALHA: kind=% uid=% dbrole=% % -> %',
      r.actor_kind, r.actor_user_id, r.actor_db_role, r.de, r.para;
  end if;
end $$;

-- ══════════════════════════════════════════════════════════
-- Dados sensíveis
-- ══════════════════════════════════════════════════════════

-- ── JM) custo do produto é auditado ─────────────────────────
do $$
declare v_produto uuid; r record;
begin
  insert into public.products (code, name, unit_id, sale_price)
  select 'AUD-P1', 'Produto auditado', u.id, 500.00 from public.units u limit 1
  returning id into v_produto;

  insert into public.product_costs (product_id, cost_price) values (v_produto, 300.00);
  update public.product_costs set cost_price = 250.00 where product_id = v_produto;

  select action, old_data ->> 'cost_price' as de, new_data ->> 'cost_price' as para, parent_type
    into r
  from public.audit_log
  where entity_type = 'product_cost' and entity_id = v_produto::text and operation = 'UPDATE';

  if r.action = 'product.cost_changed' and r.de = '300.00' and r.para = '250.00'
     and r.parent_type = 'product' then
    raise notice 'JM) OK: product.cost_changed registrou % -> %', r.de, r.para;
  else
    raise notice 'JM) FALHA: % / % -> % / parent=%', r.action, r.de, r.para, r.parent_type;
  end if;
end $$;

-- ── JN) preço de venda tem evento próprio ───────────────────
do $$
declare v_produto uuid; v_conta integer;
begin
  select id into v_produto from public.products where code = 'AUD-P1';
  update public.products set sale_price = 480.00 where id = v_produto;

  select count(*) into v_conta from public.audit_log
   where entity_id = v_produto::text and action = 'product.price_changed';

  if v_conta = 1 then raise notice 'JN) OK: product.price_changed com verbo proprio';
  else raise notice 'JN) FALHA: % evento(s) de price_changed', v_conta; end if;
end $$;

-- ── JO) o token do link NUNCA entra no log ──────────────────
do $$
declare v_token text; v_id uuid; r record; v_vazou integer;
begin
  -- O orçamento saiu de JL como 'expired'; só volta a 'sent' passando por
  -- 'draft'. O que interessa aqui é o token, não o atalho de status.
  update public.quotes set status = 'draft' where id = 'ffffffff-0000-4000-8000-0000000000a1';
  update public.quotes set status = 'sent'  where id = 'ffffffff-0000-4000-8000-0000000000a1';

  insert into public.quote_share_tokens (quote_id)
  values ('ffffffff-0000-4000-8000-0000000000a1')
  returning id, token into v_id, v_token;

  select action, new_data ->> 'token' as tok, parent_id into r
  from public.audit_log
  where entity_type = 'quote_share_token' and entity_id = v_id::text and operation = 'INSERT';

  -- Varredura: o token real não pode aparecer em NENHUMA linha do log.
  select count(*) into v_vazou from public.audit_log
   where coalesce(old_data::text, '') || coalesce(new_data::text, '') like '%' || v_token || '%';

  if r.action = 'quote.link_created' and r.tok = '[REDIGIDO]' and v_vazou = 0
     and r.parent_id = 'ffffffff-0000-4000-8000-0000000000a1' then
    raise notice 'JO) OK: quote.link_created com token redigido; token real ausente do log inteiro';
  else
    raise notice 'JO) FALHA DE SEGURANCA: acao=% token=% vazamentos=%', r.action, r.tok, v_vazou;
  end if;
end $$;

-- ── JP) visita pública não vira evento ──────────────────────
do $$
declare v_token text; v_antes bigint; v_depois bigint; v_payload jsonb;
begin
  select token into v_token from public.quote_share_tokens
   where quote_id = 'ffffffff-0000-4000-8000-0000000000a1' and revoked_at is null limit 1;

  select count(*) into v_antes from public.audit_log;
  v_payload := public.get_shared_quote(v_token);
  v_payload := public.get_shared_quote(v_token);
  select count(*) into v_depois from public.audit_log;

  if v_payload is not null and v_antes = v_depois then
    raise notice 'JP) OK: duas visitas ao link publico nao geraram evento (view_count e ruido)';
  else
    raise notice 'JP) FALHA: link abriu=% ; % linha(s) criada(s)',
      (v_payload is not null), v_depois - v_antes;
  end if;
end $$;

-- ── JQ) revogação do link vira evento ───────────────────────
do $$
declare v_conta integer;
begin
  update public.quote_share_tokens set revoked_at = now()
   where quote_id = 'ffffffff-0000-4000-8000-0000000000a1' and revoked_at is null;

  select count(*) into v_conta from public.audit_log
   where parent_id = 'ffffffff-0000-4000-8000-0000000000a1' and action = 'quote.link_revoked';

  if v_conta = 1 then raise notice 'JQ) OK: quote.link_revoked registrado';
  else raise notice 'JQ) FALHA: % evento(s) de link_revoked', v_conta; end if;
end $$;

-- ══════════════════════════════════════════════════════════
-- Isolamento: quem lê o quê
-- ══════════════════════════════════════════════════════════
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f002';   -- vendedor A

do $$
declare v_tudo integer; v_proprios integer;
begin
  select count(*) into v_tudo from public.audit_log;
  select count(*) into v_proprios from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000a1';

  if v_tudo = 0 and v_proprios = 0 then
    raise notice 'JR) OK: vendedor le ZERO linhas, inclusive dos proprios orcamentos';
  else
    raise notice 'JR) FALHA DE SEGURANCA: vendedor leu % linha(s), % do proprio orcamento', v_tudo, v_proprios;
  end if;
end $$;

-- ── JS) e não escreve ───────────────────────────────────────
do $$
declare v_linhas integer;
begin
  insert into public.audit_log (actor_kind, actor_db_role, action, operation, entity_type, entity_id)
  values ('user','authenticated','fake.event','INSERT','quote','forjado');
  raise notice 'JS) FALHA DE SEGURANCA: vendedor inseriu linha no log';
exception when others then
  raise notice 'JS) OK: vendedor bloqueado ao inserir no log (%)', sqlerrm;
end $$;

set request.jwt.claim.sub = 'ffffffff-0000-4000-8000-00000000f001';   -- admin

do $$
declare v_tudo integer;
begin
  select count(*) into v_tudo from public.audit_log;
  if v_tudo > 0 then raise notice 'JT) OK: administrador le a trilha (% linhas)', v_tudo;
  else raise notice 'JT) FALHA: administrador nao leu nada'; end if;
end $$;

-- ── JU) administrador lê, mas não corrige ───────────────────
do $$ begin
  update public.audit_log set action = 'quote.approved' where id = (select min(id) from public.audit_log);
  raise notice 'JU) FALHA DE SEGURANCA: administrador alterou o log';
exception when others then
  raise notice 'JU) OK: administrador bloqueado ao alterar o log (%)', sqlerrm;
end $$;

do $$ begin
  delete from public.audit_log where id = (select min(id) from public.audit_log);
  raise notice 'JV) FALHA DE SEGURANCA: administrador apagou linha do log';
exception when others then
  raise notice 'JV) OK: administrador bloqueado ao apagar do log (%)', sqlerrm;
end $$;

reset role;
set request.jwt.claim.sub = '';

-- ── JW) anônimo não enxerga nada ────────────────────────────
set role anon;
do $$
declare v_tudo integer;
begin
  select count(*) into v_tudo from public.audit_log;
  if v_tudo = 0 then raise notice 'JW) OK: anonimo le zero linhas';
  else raise notice 'JW) FALHA DE SEGURANCA: anonimo leu % linha(s)', v_tudo; end if;
exception when insufficient_privilege then
  raise notice 'JW) OK: anonimo sem privilegio sequer para consultar o log';
end $$;
reset role;
set request.jwt.claim.sub = '';

-- ══════════════════════════════════════════════════════════
-- Imutabilidade: nem o dono da tabela corrige
-- ══════════════════════════════════════════════════════════
do $$ begin
  update public.audit_log set action = 'quote.approved' where id = (select min(id) from public.audit_log);
  raise notice 'JX) FALHA DE SEGURANCA: o dono da tabela alterou o log';
exception when others then
  raise notice 'JX) OK: dono da tabela bloqueado ao alterar (%)', sqlerrm;
end $$;

do $$ begin
  delete from public.audit_log where id = (select min(id) from public.audit_log);
  raise notice 'JY) FALHA DE SEGURANCA: o dono da tabela apagou linha do log';
exception when others then
  raise notice 'JY) OK: dono da tabela bloqueado ao apagar (%)', sqlerrm;
end $$;

do $$ begin
  truncate public.audit_log;
  raise notice 'JZ) FALHA DE SEGURANCA: TRUNCATE apagou o log inteiro';
exception when others then
  raise notice 'JZ) OK: TRUNCATE recusado (%)', sqlerrm;
end $$;

-- ══════════════════════════════════════════════════════════
-- O rastro sobrevive ao que ele descreve
-- ══════════════════════════════════════════════════════════
do $$
declare v_antes integer; v_depois integer;
begin
  select count(*) into v_antes from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000a1';

  delete from public.quote_share_tokens where quote_id = 'ffffffff-0000-4000-8000-0000000000a1';
  delete from public.quote_items       where quote_id = 'ffffffff-0000-4000-8000-0000000000a1';
  delete from public.quotes            where id       = 'ffffffff-0000-4000-8000-0000000000a1';

  select count(*) into v_depois from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-0000000000a1';

  if v_depois > v_antes then
    raise notice 'JAA) OK: apagar o orcamento nao apagou o rastro (% -> % linhas, com o proprio delete)',
      v_antes, v_depois;
  else
    raise notice 'JAA) FALHA: rastro foi de % para % linhas', v_antes, v_depois;
  end if;
end $$;

do $$
declare v_conta integer;
begin
  update public.profiles set is_active = false where id = 'ffffffff-0000-4000-8000-00000000f003';
  select count(*) into v_conta from public.audit_log
   where entity_id = 'ffffffff-0000-4000-8000-00000000f003' and action = 'user.deactivated';
  if v_conta = 1 then raise notice 'JAB) OK: desativacao de usuario auditada e rastro preservado';
  else raise notice 'JAB) FALHA: % evento(s) de user.deactivated', v_conta; end if;
end $$;

-- ══════════════════════════════════════════════════════════
-- Superfície: privilégios, RLS e forma da função
-- ══════════════════════════════════════════════════════════
do $$
declare v_ruins text := '';
begin
  if has_table_privilege('authenticated','public.audit_log','insert') then v_ruins := v_ruins || 'auth-insert '; end if;
  if has_table_privilege('authenticated','public.audit_log','update') then v_ruins := v_ruins || 'auth-update '; end if;
  if has_table_privilege('authenticated','public.audit_log','delete') then v_ruins := v_ruins || 'auth-delete '; end if;
  if has_table_privilege('authenticated','public.audit_log','truncate') then v_ruins := v_ruins || 'auth-truncate '; end if;
  if has_table_privilege('anon','public.audit_log','select') then v_ruins := v_ruins || 'anon-select '; end if;
  if has_table_privilege('anon','public.audit_log','insert') then v_ruins := v_ruins || 'anon-insert '; end if;
  if not has_table_privilege('authenticated','public.audit_log','select') then v_ruins := v_ruins || 'admin-sem-select '; end if;

  if v_ruins = '' then
    raise notice 'JAC) OK: privilegios corretos — authenticated so SELECT, anon nada';
  else
    raise notice 'JAC) FALHA: privilegios indevidos: %', v_ruins;
  end if;
end $$;

do $$
declare v_secdef boolean; v_config text[]; v_dono text; v_exec boolean;
begin
  select p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner),
         has_function_privilege('authenticated','public.audit_capture()','execute')
    into v_secdef, v_config, v_dono, v_exec
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'audit_capture';

  -- 20260901193926 trocou 'public' pelo search_path VAZIO, que é mais restrito.
  if v_secdef and v_config @> array['search_path=""'] and not v_exec then
    raise notice 'JAD) OK: audit_capture() security definer, search_path fixo, sem EXECUTE para authenticated (dono %)', v_dono;
  else
    raise notice 'JAD) FALHA: secdef=% config=% execute=%', v_secdef, v_config, v_exec;
  end if;
end $$;

do $$
declare v_rls boolean; v_policies integer; v_cmd text;
begin
  select relrowsecurity into v_rls from pg_class where oid = 'public.audit_log'::regclass;
  select count(*) into v_policies from pg_policies where schemaname='public' and tablename='audit_log';
  select cmd into v_cmd from pg_policies where schemaname='public' and tablename='audit_log' limit 1;

  if v_rls and v_policies = 1 and v_cmd = 'SELECT' then
    raise notice 'JAE) OK: RLS ligado, exatamente 1 policy e de SELECT';
  else
    raise notice 'JAE) FALHA: rls=% policies=% cmd=%', v_rls, v_policies, v_cmd;
  end if;
end $$;

-- ── JAF) sanidade de concorrência ───────────────────────────
-- Sem encadeamento de hash não há disputa entre inserções. O que precisa
-- valer é que eventos de transações diferentes ficam distinguíveis.
do $$
declare v_txids integer;
begin
  update public.customers set notes = 'nota 1' where id = 'ffffffff-0000-4000-8000-0000000000c1';
  update public.customers set notes = 'nota 2' where id = 'ffffffff-0000-4000-8000-0000000000c1';

  select count(distinct metadata ->> 'txid') into v_txids
  from public.audit_log
  where entity_id = 'ffffffff-0000-4000-8000-0000000000c1' and action = 'customer.updated';

  if v_txids >= 2 then
    raise notice 'JAF) OK: eventos de transacoes diferentes tem txid distinto (%)', v_txids;
  else
    raise notice 'JAF) FALHA: % txid distinto(s)', v_txids;
  end if;
end $$;

-- ── JAG) nenhum evento perdeu ator nem entidade ─────────────
do $$
declare v_ruins integer;
begin
  select count(*) into v_ruins from public.audit_log
   where entity_id is null or entity_type is null or action is null
      or actor_db_role is null or actor_kind is null;
  if v_ruins = 0 then raise notice 'JAH) OK: nenhuma linha do log com ator ou entidade em branco';
  else raise notice 'JAH) FALHA: % linha(s) incompleta(s)', v_ruins; end if;
end $$;
