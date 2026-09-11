-- ============================================================
-- BRAIN — as pontes do ERP sob estresse (migration 20260911150000).
--
-- A lacuna que este arquivo fecha: a suíte 25 provava que a ponte
-- FUNCIONA. Nunca provou o que acontece quando ela QUEBRA — e era
-- exatamente aí que estava a promessa não verificada de "nunca derruba
-- uma venda".
--
-- O que este arquivo prova:
--   PT1  `exception when others` NÃO captura cancelamento/timeout;
--   PT2  erro comum na escrita do BRAIN: a venda é salva assim mesmo;
--   PT3  falha no processamento de oportunidade/lead: idem;
--   PT4  contenção de lock entre duas transações: a venda sobrevive;
--   PT5  timeout dentro da ponte: a venda CAI — e é assim que se declara;
--   PT6  o que faltou se descobre e se repõe, sem duplicar;
--   PT7  o gatilho DIFERIDO forçado com SET CONSTRAINTS: o fluxo inteiro.
--
-- Prefixo de UUID = 28.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('28282828-0000-4000-8000-000000000001','ponte.admin@teste.local','{"full_name":"Admin Pontes","role":"admin"}'),
 ('28282828-0000-4000-8000-000000000002','ponte.vend@teste.local' ,'{"full_name":"Vendedor Pontes","role":"salesperson"}');
update public.profiles set role = 'admin' where id = '28282828-0000-4000-8000-000000000001';

insert into public.customers (id, name, city, state)
 values ('28282828-0000-4000-8000-0000000000c1','Fazenda das Pontes','Londrina','PR');

-- ── PT1: o que OTHERS captura e o que não captura ───────────
-- O manual do PostgreSQL: "OTHERS casa com todos os tipos de erro exceto
-- QUERY_CANCELED e ASSERT_FAILURE". O relatório de 11/09 dizia o
-- contrário. Aqui a afirmação vira medida.
do $$
declare v_others boolean := false; v_nomeado boolean := false;
begin
  begin
    begin
      perform 1/0;
    exception when others then v_others := true;
    end;
  exception when others then null;
  end;
  if not v_others then raise exception 'PT1a FALHOU: OTHERS nao capturou division_by_zero'; end if;
  raise notice ' PT1a) OK: erro comum e capturado por OTHERS';

  v_others := false;
  begin
    begin
      raise exception 'cancelamento' using errcode = 'query_canceled';
    exception when others then v_others := true;
    end;
  exception when query_canceled then v_nomeado := true;
  end;
  if v_others or not v_nomeado then
    raise exception 'PT1b FALHOU: others=% nomeado=%', v_others, v_nomeado;
  end if;
  raise notice ' PT1b) OK: query_canceled ESCAPA de OTHERS (so o tratador pelo nome pegou)';
end
$$;

-- PT1c: o mesmo, atravessando a ponte de verdade. Um gatilho temporário
-- levanta `query_canceled` dentro do bloco protegido — e a venda cai.
do $$
declare v_quote uuid; v_caiu boolean := false;
begin
  insert into brain.leads (name, customer_id)
   values ('Lead do cancelamento','28282828-0000-4000-8000-0000000000c1');
  insert into public.quotes (customer_id, owner_id, notes)
   values ('28282828-0000-4000-8000-0000000000c1','28282828-0000-4000-8000-000000000002','PT1c')
   returning id into v_quote;
  insert into brain.opportunities (quote_id, customer_id, title, channel_key)
   values (v_quote, '28282828-0000-4000-8000-0000000000c1','Oportunidade PT1c','other');

  create or replace function brain.teste_cancela() returns trigger
   language plpgsql as $t$ begin
     raise exception 'cancelamento simulado na ponte' using errcode = 'query_canceled';
   end $t$;
  create trigger trg_teste_cancela before update on brain.opportunities
   for each row execute function brain.teste_cancela();

  begin
    update public.quotes set status = 'sent' where id = v_quote;
  exception when query_canceled then
    v_caiu := true;
  end;

  drop trigger trg_teste_cancela on brain.opportunities;
  drop function brain.teste_cancela();

  if not v_caiu then
    raise exception 'PT1c FALHOU: o cancelamento na ponte nao derrubou a venda';
  end if;
  if (select status from public.quotes where id = v_quote) <> 'draft' then
    raise exception 'PT1c FALHOU: o status mudou apesar do cancelamento';
  end if;
  raise notice ' PT1c) OK (e este e o LIMITE): cancelamento dentro da ponte derruba a venda — o orcamento ficou em draft';
end
$$;

-- ── PT2: erro comum dentro da ponte, venda salva ────────────
-- Quebra-se `ingest_event` de propósito; o orçamento tem de entrar
-- assim mesmo, e o barramento fica sem o evento.
do $$
declare v_quote uuid; v_eventos int;
begin
  alter function brain.ingest_event(text, text, jsonb, text, timestamptz, text, uuid, uuid, uuid, uuid, text, text, uuid, integer, jsonb)
    rename to ingest_event_guardado;
  begin
    insert into public.quotes (customer_id, owner_id)
     values ('28282828-0000-4000-8000-0000000000c1','28282828-0000-4000-8000-000000000002')
     returning id into v_quote;
  exception when others then
    alter function brain.ingest_event_guardado(text, text, jsonb, text, timestamptz, text, uuid, uuid, uuid, uuid, text, text, uuid, integer, jsonb)
      rename to ingest_event;
    raise exception 'PT2 FALHOU: a ponte derrubou o orcamento — %', sqlerrm;
  end;
  alter function brain.ingest_event_guardado(text, text, jsonb, text, timestamptz, text, uuid, uuid, uuid, uuid, text, text, uuid, integer, jsonb)
    rename to ingest_event;

  if v_quote is null or not exists (select 1 from public.quotes where id = v_quote) then
    raise exception 'PT2 FALHOU: o orcamento nao foi salvo';
  end if;
  select count(*) into v_eventos from brain.events where payload ->> 'quote_id' = v_quote::text;
  if v_eventos <> 0 then
    raise exception 'PT2 FALHOU: era para o evento ter se perdido, e vieram %', v_eventos;
  end if;
  perform set_config('brain.teste.quote_orfao', v_quote::text, false);
  raise notice ' PT2) OK: ingest_event quebrada; orcamento % salvo, barramento sem o evento',
    (select number from public.quotes where id = v_quote);
end
$$;

-- ── PT3: falha no processamento de oportunidade/lead ────────
-- Um CHECK impossível em `brain.opportunities` faz o UPDATE de estágio
-- explodir no meio da ponte. A venda continua tendo de passar.
do $$
declare v_quote uuid; v_opp uuid; v_lead uuid;
begin
  insert into brain.leads (name, customer_id)
   values ('Lead das Pontes','28282828-0000-4000-8000-0000000000c1') returning id into v_lead;
  insert into public.quotes (customer_id, owner_id)
   values ('28282828-0000-4000-8000-0000000000c1','28282828-0000-4000-8000-000000000002')
   returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key)
   values (v_lead, v_quote, 'Oportunidade das Pontes','other') returning id into v_opp;

  alter table brain.opportunities add constraint chk_teste_impossivel check (stage <> 'proposal');
  begin
    update public.quotes set status = 'sent' where id = v_quote;
  exception when others then
    alter table brain.opportunities drop constraint chk_teste_impossivel;
    raise exception 'PT3 FALHOU: a ponte derrubou o envio do orcamento — %', sqlerrm;
  end;
  alter table brain.opportunities drop constraint chk_teste_impossivel;

  if (select status from public.quotes where id = v_quote) <> 'sent' then
    raise exception 'PT3 FALHOU: o orcamento nao foi enviado';
  end if;
  if (select stage from brain.opportunities where id = v_opp) = 'proposal' then
    raise exception 'PT3 FALHOU: o estagio mudou apesar do CHECK';
  end if;
  raise notice ' PT3) OK: o estagio da oportunidade falhou, o orcamento foi enviado do mesmo jeito (estagio segue em %)',
    (select stage from brain.opportunities where id = v_opp);
end
$$;

-- ── PT6: descobrir e repor o que faltou ─────────────────────
set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', '28282828-0000-4000-8000-000000000001', false);

do $$
declare v_orfao uuid; v_faltando int; v_reposto int; v_de_novo int; v_segunda int;
begin
  v_orfao := current_setting('brain.teste.quote_orfao')::uuid;

  select count(*) into v_faltando from brain.erp_events_faltando() where id = v_orfao;
  if v_faltando <> 1 then
    raise exception 'PT6 FALHOU: o orcamento orfao nao apareceu na lista (%)', v_faltando;
  end if;

  v_reposto := brain.repor_eventos_erp();
  if v_reposto < 1 then
    raise exception 'PT6 FALHOU: nada foi reposto';
  end if;

  select count(*) into v_de_novo from brain.erp_events_faltando() where id = v_orfao;
  if v_de_novo <> 0 then
    raise exception 'PT6 FALHOU: o orcamento continua faltando depois da reposicao';
  end if;

  -- Segunda execução: idempotente.
  v_segunda := brain.repor_eventos_erp();
  if v_segunda <> 0 then
    raise exception 'PT6 FALHOU: a segunda reposicao criou % evento(s)', v_segunda;
  end if;

  raise notice ' PT6) OK: % venda(s) sem evento encontradas e repostas; a segunda reposicao nao duplicou nada', v_reposto;
end
$$;

-- Vendedor não repõe evento.
do $$
begin
  perform set_config('request.jwt.claim.sub', '28282828-0000-4000-8000-000000000002', false);
  begin
    perform brain.repor_eventos_erp();
    raise exception 'PT6b FALHOU: vendedor repos evento';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from brain.erp_events_faltando()) then
    raise exception 'PT6b FALHOU: vendedor enxergou a lista de faltantes';
  end if;
  raise notice ' PT6b) OK: reposicao e lista de faltantes sao so do administrador';
end
$$;

reset role;

-- ── PT7: o gatilho DIFERIDO, forçado e conferido ────────────
-- `trg_brain_orders_created` é `deferrable initially deferred`: sem
-- `set constraints ... immediate` ele só dispararia no COMMIT, e um
-- teste que dá ROLLBACK jamais o executaria. Aqui o pedido é montado
-- inteiro, o gatilho é forçado, as assertivas correm — e só então se
-- desfaz tudo.
begin;
do $$
declare
  v_quote uuid; v_order uuid; v_lead uuid; v_opp uuid;
  v_prod  uuid; v_total numeric; v_evento numeric;
begin
  insert into public.products (code, name, unit_id, sale_price)
  select 'PT7-001', 'Pulverizador das Pontes', u.id, 125000.00 from public.units u where u.code = 'UN'
  returning id into v_prod;
  if v_prod is null then raise exception 'PT7 sem unidade UN na base de teste'; end if;

  insert into brain.leads (name, customer_id)
   values ('Lead do Pedido','28282828-0000-4000-8000-0000000000c1') returning id into v_lead;
  insert into public.quotes (customer_id, owner_id, status)
   values ('28282828-0000-4000-8000-0000000000c1','28282828-0000-4000-8000-000000000002','draft')
   returning id into v_quote;
  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Oportunidade do Pedido','other','28282828-0000-4000-8000-0000000000c1')
   returning id into v_opp;

  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot, quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Pulverizador das Pontes', 'PT7-001', 2, 125000.00, 1);

  -- Os carimbos sao do banco: quem os manda pelo formulario e recusado.
  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;

  v_order := public.create_order_from_quote(v_quote);

  -- O pedido está montado. AGORA o gatilho diferido roda.
  set constraints public.trg_brain_orders_created immediate;

  select total into v_total  from public.orders where id = v_order;
  select (payload ->> 'total')::numeric into v_evento
    from brain.events where event_name = 'order.created' and payload ->> 'order_id' = v_order::text;

  if v_evento is null then
    raise exception 'PT7 FALHOU: o gatilho diferido nao publicou order.created';
  end if;
  if v_evento <> v_total then
    raise exception 'PT7 FALHOU: evento com total % e pedido com total %', v_evento, v_total;
  end if;
  if (select stage from brain.opportunities where id = v_opp) <> 'won' then
    raise exception 'PT7 FALHOU: a oportunidade nao foi ganha (%)',
      (select stage from brain.opportunities where id = v_opp);
  end if;
  if (select status from brain.leads where id = v_lead) <> 'converted' then
    raise exception 'PT7 FALHOU: o lead nao foi convertido (%)',
      (select status from brain.leads where id = v_lead);
  end if;
  if (select count(*) from brain.events where payload ->> 'quote_id' = v_quote::text
        and event_name in ('quote.created','quote.sent','quote.approved')) <> 3 then
    raise exception 'PT7 FALHOU: faltou evento de orcamento no caminho';
  end if;

  raise notice ' PT7) OK: orcamento → pedido com total % = evento %; oportunidade ganha; lead convertido; 3 eventos de orcamento',
    v_total, v_evento;
end
$$;
rollback;

-- ── PT4: contenção de lock entre transações ─────────────────
-- Uma transação segura a linha da oportunidade; a ponte da outra tenta
-- atualizá-la. Com `lock_timeout` a espera vira cancelamento — e aqui
-- se mostra o que acontece com a venda.
\echo ' PT4/PT5) rodam em sessoes concorrentes: supabase/db-tests/pontes-concorrentes.sh'

reset role;
-- Os eventos NÃO se apagam — é essa a regra do barramento, e a suíte não
-- abre exceção para si mesma. O resto sai.
delete from brain.tasks;
delete from brain.interactions;
delete from brain.opportunities;
delete from brain.identities;
delete from brain.leads;
delete from public.quote_items where quote_id in (select id from public.quotes where customer_id = '28282828-0000-4000-8000-0000000000c1');
delete from public.quotes where customer_id = '28282828-0000-4000-8000-0000000000c1';
delete from public.customers where id = '28282828-0000-4000-8000-0000000000c1';
delete from auth.users where email like 'ponte.%@teste.local';
