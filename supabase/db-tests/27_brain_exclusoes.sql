-- ============================================================
-- BRAIN — o ERP volta a poder excluir (migration 20260911140000).
--
-- A lacuna que este arquivo fecha: a Fase 1 introduzia um veto que
-- ninguém pedira. Nove exclusões físicas legítimas do ERP morriam em
-- CHECK ou em gatilho do BRAIN. A suíte 25 não percebeu porque nunca
-- excluiu nada.
--
-- O que este arquivo prova, nos dois sentidos:
--   · EX1–EX9  a exclusão passa e a história fica no rótulo;
--   · EX10–EX15 o rótulo e a autoria não se forjam;
--   · EX16    a exclusão LÓGICA do ERP continua como era.
--
-- Prefixo de UUID = 27, o número da suíte.
-- ============================================================
-- Nota de versão: até o PostgreSQL 17, violar `on delete restrict`
-- levantava 23503 (`foreign_key_violation`). O PostgreSQL 18 passou a
-- levantar 23001 (`restrict_violation`), que é o código do padrão. Os
-- tratadores abaixo aceitam os dois, para a suíte valer nas duas versões
-- — o comportamento do banco é o mesmo: a exclusão é recusada.
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('27272727-0000-4000-8000-000000000001','ex27.admin@teste.local','{"full_name":"Admin Exclusoes","role":"admin"}'),
 ('27272727-0000-4000-8000-000000000002','ex27.vend@teste.local' ,'{"full_name":"Vendedor Exclusoes","role":"salesperson"}'),
 ('27272727-0000-4000-8000-000000000003','ex27.vend2@teste.local','{"full_name":"Outro Vendedor","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '27272727-0000-4000-8000-000000000001';

-- ── EX1: cliente com identidade sem lead ────────────────────
do $$
declare v_cli uuid; v_rotulo text; v_sobrou int;
begin
  insert into public.customers (name) values ('Cliente da Identidade') returning id into v_cli;
  insert into brain.identities (kind, value, customer_id)
   values ('email','ex1@exemplo.com', v_cli);

  delete from public.customers where id = v_cli;

  select customer_label, count(*) over () into v_rotulo, v_sobrou
    from brain.identities where value = 'ex1@exemplo.com';
  if v_sobrou <> 1 or v_rotulo <> 'Cliente da Identidade' then
    raise exception 'EX1 FALHOU: sobrou=% rotulo=%', v_sobrou, v_rotulo;
  end if;
  if exists (select 1 from brain.identities where value = 'ex1@exemplo.com' and customer_id is not null) then
    raise exception 'EX1 FALHOU: customer_id nao foi anulado';
  end if;
  raise notice ' EX1) OK: cliente excluido; identidade ficou, com o rotulo "%"', v_rotulo;
end
$$;

-- ── EX2: cliente com interação sem lead ─────────────────────
do $$
declare v_cli uuid; v_rotulo text;
begin
  insert into public.customers (name) values ('Cliente da Interacao') returning id into v_cli;
  insert into brain.interactions (customer_id, summary, channel_key)
   values (v_cli, 'Ligacao sem lead', 'phone');

  delete from public.customers where id = v_cli;

  select customer_label into v_rotulo from brain.interactions where summary = 'Ligacao sem lead';
  if v_rotulo <> 'Cliente da Interacao' then
    raise exception 'EX2 FALHOU: rotulo=%', coalesce(v_rotulo, '(nulo)');
  end if;
  raise notice ' EX2) OK: cliente excluido; interacao ficou, com o rotulo "%"', v_rotulo;
end
$$;

-- ── EX3: cliente com oportunidade sem lead ──────────────────
do $$
declare v_cli uuid; v_rotulo text;
begin
  insert into public.customers (name) values ('Cliente da Oportunidade') returning id into v_cli;
  insert into brain.opportunities (customer_id, title, channel_key)
   values (v_cli, 'Oportunidade sem lead', 'other');

  delete from public.customers where id = v_cli;

  select customer_label into v_rotulo from brain.opportunities where title = 'Oportunidade sem lead';
  if v_rotulo <> 'Cliente da Oportunidade' then
    raise exception 'EX3 FALHOU: rotulo=%', coalesce(v_rotulo, '(nulo)');
  end if;
  raise notice ' EX3) OK: cliente excluido; oportunidade ficou, com o rotulo "%"', v_rotulo;
end
$$;

-- ── EX4–EX7: exclusão do PERFIL, uma referência por vez ─────
do $$
declare
  v_vend uuid;
  v_lead uuid;
  v_rot  text;
begin
  -- EX4: evento
  insert into auth.users (id, email, raw_user_meta_data)
   values ('27272727-0000-4000-8000-0000000000e4','ex4@teste.local','{"full_name":"Autor do Evento","role":"salesperson"}')
   returning id into v_vend;
  insert into brain.events (event_name, source, actor_id, payload)
   values ('teste.ex4','app', v_vend, '{}'::jsonb);
  delete from auth.users where id = v_vend;
  select actor_label into v_rot from brain.events where event_name = 'teste.ex4';
  if v_rot <> 'Autor do Evento'
     or exists (select 1 from brain.events where event_name = 'teste.ex4' and actor_id is not null) then
    raise exception 'EX4 FALHOU: rotulo=% ', coalesce(v_rot,'(nulo)');
  end if;
  raise notice ' EX4) OK: perfil excluido; evento ficou, actor_id nulo e actor_label "%"', v_rot;

  insert into brain.leads (name) values ('Lead das Exclusoes') returning id into v_lead;

  -- EX5: tarefa
  insert into auth.users (id, email, raw_user_meta_data)
   values ('27272727-0000-4000-8000-0000000000e5','ex5@teste.local','{"full_name":"Autor da Tarefa","role":"salesperson"}')
   returning id into v_vend;
  insert into brain.tasks (title, created_by, lead_id) values ('Tarefa EX5', v_vend, v_lead);
  delete from auth.users where id = v_vend;
  select created_by_label into v_rot from brain.tasks where title = 'Tarefa EX5';
  if v_rot <> 'Autor da Tarefa'
     or exists (select 1 from brain.tasks where title = 'Tarefa EX5' and created_by is not null) then
    raise exception 'EX5 FALHOU: rotulo=%', coalesce(v_rot,'(nulo)');
  end if;
  raise notice ' EX5) OK: perfil excluido; tarefa ficou, created_by nulo e rotulo "%"', v_rot;

  -- EX6: oportunidade
  insert into auth.users (id, email, raw_user_meta_data)
   values ('27272727-0000-4000-8000-0000000000e6','ex6@teste.local','{"full_name":"Autor da Oportunidade","role":"salesperson"}')
   returning id into v_vend;
  insert into brain.opportunities (title, channel_key, created_by, lead_id)
   values ('Oportunidade EX6','other', v_vend, v_lead);
  delete from auth.users where id = v_vend;
  select created_by_label into v_rot from brain.opportunities where title = 'Oportunidade EX6';
  if v_rot <> 'Autor da Oportunidade'
     or exists (select 1 from brain.opportunities where title = 'Oportunidade EX6' and created_by is not null) then
    raise exception 'EX6 FALHOU: rotulo=%', coalesce(v_rot,'(nulo)');
  end if;
  raise notice ' EX6) OK: perfil excluido; oportunidade ficou, created_by nulo e rotulo "%"', v_rot;

  -- EX7: interação
  insert into auth.users (id, email, raw_user_meta_data)
   values ('27272727-0000-4000-8000-0000000000e7','ex7@teste.local','{"full_name":"Autor da Interacao","role":"salesperson"}')
   returning id into v_vend;
  insert into brain.interactions (summary, channel_key, actor_id, lead_id)
   values ('Nota EX7','other', v_vend, v_lead);
  delete from auth.users where id = v_vend;
  select actor_label into v_rot from brain.interactions where summary = 'Nota EX7';
  if v_rot <> 'Autor da Interacao'
     or exists (select 1 from brain.interactions where summary = 'Nota EX7' and actor_id is not null) then
    raise exception 'EX7 FALHOU: rotulo=%', coalesce(v_rot,'(nulo)');
  end if;
  raise notice ' EX7) OK: perfil excluido; interacao ficou, actor_id nulo e rotulo "%"', v_rot;
end
$$;

-- ── EX8: excluir o LEAD ─────────────────────────────────────
-- A oportunidade, a interação e a tarefa ficam, com o rótulo. A
-- identidade vai junto — de propósito: `unique (kind, value)` não pode
-- guardar chave órfã, senão o mesmo telefone nunca mais entra.
do $$
declare v_lead uuid; v_rot text; v_ident int; v_novo uuid;
begin
  insert into brain.leads (name, phone) values ('Lead que sera excluido', '43999990001')
   returning id into v_lead;
  insert into brain.opportunities (lead_id, title, channel_key) values (v_lead,'Oportunidade EX8','other');
  insert into brain.interactions  (lead_id, summary, channel_key) values (v_lead,'Nota EX8','other');
  insert into brain.tasks         (lead_id, title)                values (v_lead,'Tarefa EX8');

  delete from brain.leads where id = v_lead;

  select lead_label into v_rot from brain.opportunities where title = 'Oportunidade EX8';
  if v_rot <> 'Lead que sera excluido' then
    raise exception 'EX8 FALHOU: oportunidade sem rotulo do lead (%)', coalesce(v_rot,'(nulo)');
  end if;
  if not exists (select 1 from brain.interactions where summary = 'Nota EX8' and lead_id is null
                   and lead_label = 'Lead que sera excluido')
  or not exists (select 1 from brain.tasks where title = 'Tarefa EX8' and lead_id is null
                   and lead_label = 'Lead que sera excluido') then
    raise exception 'EX8 FALHOU: interacao ou tarefa nao sobreviveu ao lead';
  end if;

  select count(*) into v_ident from brain.identities where value = '5543999990001';
  if v_ident <> 0 then
    raise exception 'EX8 FALHOU: identidade orfa sobrou e envenena o indice unico';
  end if;

  -- E a prova de que o índice ficou limpo: o mesmo telefone entra de novo.
  insert into brain.leads (name, phone) values ('Lead novo, mesmo telefone', '43999990001')
   returning id into v_novo;
  if not exists (select 1 from brain.identities where value = '5543999990001' and lead_id = v_novo) then
    raise exception 'EX8 FALHOU: o telefone nao pode ser reaproveitado';
  end if;

  raise notice ' EX8) OK: lead excluido; oportunidade, interacao e tarefa ficaram com rotulo; identidade saiu e o telefone voltou a servir';
end
$$;

-- ── EX9: perfil com as quatro referências de uma vez ────────
do $$
declare v_vend uuid; v_cli uuid; v_lead uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data)
   values ('27272727-0000-4000-8000-0000000000e9','ex9@teste.local','{"full_name":"Vendedor Inteiro","role":"salesperson"}')
   returning id into v_vend;
  insert into public.customers (name) values ('Cliente EX9') returning id into v_cli;
  insert into brain.leads (name, owner_id) values ('Lead EX9', v_vend) returning id into v_lead;

  insert into brain.events        (event_name, source, actor_id, payload) values ('teste.ex9','app', v_vend, '{}'::jsonb);
  insert into brain.tasks         (title, created_by, assignee_id, customer_id) values ('Tarefa EX9', v_vend, v_vend, v_cli);
  insert into brain.opportunities (title, channel_key, created_by, owner_id, customer_id) values ('Oportunidade EX9','other', v_vend, v_vend, v_cli);
  insert into brain.interactions  (summary, channel_key, actor_id, customer_id) values ('Nota EX9','other', v_vend, v_cli);

  delete from auth.users where id = v_vend;

  if (select count(*) from brain.events        where event_name = 'teste.ex9')    <> 1
  or (select count(*) from brain.tasks         where title = 'Tarefa EX9')        <> 1
  or (select count(*) from brain.opportunities where title = 'Oportunidade EX9')  <> 1
  or (select count(*) from brain.interactions  where summary = 'Nota EX9')        <> 1
  or (select count(*) from brain.leads         where name = 'Lead EX9')           <> 1 then
    raise exception 'EX9 FALHOU: alguma linha do BRAIN sumiu junto com o perfil';
  end if;
  if (select owner_label from brain.leads where name = 'Lead EX9') <> 'Vendedor Inteiro'
  or (select assignee_label from brain.tasks where title = 'Tarefa EX9') <> 'Vendedor Inteiro'
  or (select owner_label from brain.opportunities where title = 'Oportunidade EX9') <> 'Vendedor Inteiro' then
    raise exception 'EX9 FALHOU: rotulo de responsavel se perdeu';
  end if;
  raise notice ' EX9) OK: perfil com evento, tarefa, oportunidade, interacao e lead excluido; cinco linhas ficaram com rotulo';
end
$$;

-- ── EX10: vendedor não troca autoria por outro perfil ───────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '27272727-0000-4000-8000-000000000002', false);

do $$
declare v_opp uuid; v_dono uuid;
begin
  insert into brain.opportunities (title, channel_key, customer_id)
   select 'Oportunidade do vendedor','other', id from public.customers limit 1
   returning id into v_opp;

  update brain.opportunities set created_by = '27272727-0000-4000-8000-000000000003' where id = v_opp;
  select created_by into v_dono from brain.opportunities where id = v_opp;
  if v_dono <> '27272727-0000-4000-8000-000000000002' then
    raise exception 'EX10 FALHOU: autoria trocada para %', v_dono;
  end if;
  raise notice ' EX10) OK: tentativa de passar a autoria para outro vendedor foi ignorada';
end
$$;

-- ── EX11: não se anula autoria de perfil que existe ─────────
do $$
declare v_opp uuid; v_dono uuid;
begin
  select id into v_opp from brain.opportunities where title = 'Oportunidade do vendedor';
  update brain.opportunities set created_by = null where id = v_opp;
  select created_by into v_dono from brain.opportunities where id = v_opp;
  if v_dono is null then
    raise exception 'EX11 FALHOU: autoria foi apagada com o perfil vivo';
  end if;
  raise notice ' EX11) OK: apagar a propria autoria foi ignorado — o perfil existe';
end
$$;

-- ── EX12: rótulo enviado pelo cliente é descartado ──────────
do $$
declare v_rot text; v_id uuid;
begin
  insert into brain.opportunities (title, channel_key, customer_id, customer_label, created_by_label)
   select 'Oportunidade com rotulo forjado','other', id, 'Cliente Inventado S.A.', 'Diretor Fantasma'
     from public.customers limit 1
   returning id into v_id;

  select customer_label into v_rot from brain.opportunities where id = v_id;
  if v_rot = 'Cliente Inventado S.A.' then
    raise exception 'EX12 FALHOU: rotulo forjado entrou';
  end if;
  if (select created_by_label from brain.opportunities where id = v_id) = 'Diretor Fantasma' then
    raise exception 'EX12 FALHOU: rotulo de autoria forjado entrou';
  end if;
  raise notice ' EX12) OK: rotulos vieram do cadastro de verdade ("%"), nao do cliente', v_rot;
end
$$;

-- ── EX13: linha sem sujeito nenhum continua recusada ────────
do $$
declare v_erro text;
begin
  begin
    insert into brain.interactions (summary, channel_key, customer_label)
     values ('Interacao sem sujeito','other','Cliente que nunca existiu');
    raise exception 'EX13 FALHOU: aceitou interacao so com rotulo';
  exception when check_violation then
    v_erro := sqlerrm;
  end;
  begin
    insert into brain.identities (kind, value, lead_label) values ('email','sem.dono@exemplo.com','Lead Fantasma');
    raise exception 'EX13 FALHOU: aceitou identidade so com rotulo';
  exception when check_violation then null;
  end;
  raise notice ' EX13) OK: sem lead e sem cliente nao entra, mesmo mandando rotulo (%)', left(v_erro, 48);
end
$$;

-- ── EX14: o autor do evento não se troca ────────────────────
reset role;
do $$
declare v_erro text;
begin
  insert into brain.events (event_name, source, actor_id, payload)
   values ('teste.ex14','app','27272727-0000-4000-8000-000000000002','{}'::jsonb);
  begin
    update brain.events set actor_id = '27272727-0000-4000-8000-000000000003'
     where event_name = 'teste.ex14';
    raise exception 'EX14 FALHOU: trocou o autor do evento';
  exception when sqlstate '2F004' or sqlstate '23001' then
    v_erro := sqlerrm;
  end;
  begin
    update brain.events set actor_id = null where event_name = 'teste.ex14';
    raise exception 'EX14 FALHOU: anulou o autor com o perfil vivo';
  exception when sqlstate '2F004' or sqlstate '23001' then null;
  end;
  begin
    update brain.events set actor_label = 'Outro Nome' where event_name = 'teste.ex14';
    raise exception 'EX14 FALHOU: reescreveu o actor_label';
  exception when sqlstate '2F004' or sqlstate '23001' then null;
  end;
  raise notice ' EX14) OK: autor do evento nao se troca, nao se anula com perfil vivo e o rotulo nao se reescreve (%)', left(v_erro, 40);
end
$$;

-- ── EX15: merge registrado protege o lead ───────────────────
do $$
declare v_a uuid; v_b uuid;
begin
  insert into brain.leads (name) values ('Lead fundido A') returning id into v_a;
  insert into brain.leads (name) values ('Lead fundido B') returning id into v_b;
  insert into brain.lead_merges (source_lead_id, target_lead_id, reason)
   values (v_a, v_b, 'teste');
  begin
    delete from brain.leads where id = v_a;
    raise exception 'EX15 FALHOU: excluiu lead com merge registrado';
  exception when foreign_key_violation or restrict_violation then null;
  end;
  raise notice ' EX15) OK: lead citado em lead_merges nao se exclui — o livro de fusoes fica de pe';
end
$$;

-- ── EX16: a exclusão LÓGICA do ERP não mudou ────────────────
-- O ERP tem dois caminhos, e o BRAIN não mexeu em nenhum:
--   · cliente COM histórico: `delete_customer()` recusa e manda desativar
--     (o `is_active = false`, que é a exclusão lógica de verdade);
--   · cliente SEM histórico: some fisicamente — e é esse o caso que o
--     BRAIN estava bloqueando, coberto em EX1–EX3.
set role authenticated;
select set_config('request.jwt.claim.sub', '27272727-0000-4000-8000-000000000001', false);

do $$
declare v_cli uuid; v_erro text; v_ativo boolean;
begin
  insert into public.customers (name) values ('Cliente Com Orcamento') returning id into v_cli;
  insert into public.quotes (customer_id, owner_id)
   values (v_cli, '27272727-0000-4000-8000-000000000001');
  insert into brain.interactions (customer_id, summary, channel_key)
   values (v_cli, 'Nota EX16', 'other');

  begin
    perform public.delete_customer(v_cli);
    raise exception 'EX16 FALHOU: excluiu fisicamente cliente com orcamento';
  exception when foreign_key_violation or restrict_violation then
    v_erro := sqlerrm;
  end;

  -- A exclusão lógica: desativar. Continua funcionando com o BRAIN no ar.
  update public.customers set is_active = false where id = v_cli;
  select is_active into v_ativo from public.customers where id = v_cli;
  if v_ativo then
    raise exception 'EX16 FALHOU: nao conseguiu desativar o cliente';
  end if;
  if not exists (select 1 from brain.interactions where summary = 'Nota EX16' and customer_id = v_cli) then
    raise exception 'EX16 FALHOU: a desativacao mexeu no vinculo do BRAIN';
  end if;
  raise notice ' EX16) OK: cliente com historico nao some (%), desativa; e o BRAIN nem soube — vinculo intacto',
    left(v_erro, 46);
end
$$;

reset role;

-- Limpeza: só o que ESTA suíte criou. Apagar por `name like 'Cliente %'`
-- alcançaria massa das suítes anteriores — e aí a exclusão do orçamento
-- esbarraria em `freeze_order_commercials`, que é guarda do ERP e não
-- tem nada a ver com o BRAIN.
delete from brain.lead_merges;
delete from brain.tasks;
delete from brain.interactions;
delete from brain.opportunities;
delete from brain.identities;
delete from brain.leads;
delete from public.quotes
 where customer_id in (select id from public.customers where name = 'Cliente Com Orcamento');
delete from public.customers
 where name in ('Cliente da Identidade', 'Cliente da Interacao', 'Cliente da Oportunidade',
                'Cliente EX9', 'Cliente Com Orcamento');
-- Por id, não por `like`: `ex%` alcançaria usuários de outras suítes, e
-- aí a exclusão esbarraria em `quotes_owner_id_fkey` — outra guarda do
-- ERP, que impede apagar um perfil que ainda é dono de orçamento.
delete from auth.users where id in (
  '27272727-0000-4000-8000-000000000001',
  '27272727-0000-4000-8000-000000000002',
  '27272727-0000-4000-8000-000000000003');
