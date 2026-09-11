-- ============================================================
-- BRAIN — as pontes do ERP, com a garantia que elas de fato dão
--
-- O relatório de 11/09 afirmou que `exception when others` protege a
-- venda de QUALQUER falha do BRAIN. Está errado, e a prova é de uma
-- linha (supabase/db-tests/28_brain_pontes.sql, PT1):
--
--   set statement_timeout = '250ms';
--   do $$ begin
--     begin perform pg_sleep(2);
--     exception when others then raise notice 'capturado'; end;
--   end $$;
--   → ERROR: canceling statement due to statement timeout
--
-- O manual do PostgreSQL diz literalmente que `OTHERS` casa com tudo
-- MENOS `query_canceled` e `assert_failure`. E `statement_timeout` levanta
-- justamente `query_canceled`.
--
-- Capturar `query_canceled` de propósito seria pior do que o problema: o
-- pedido de cancelamento continua pendente e volta no próximo ponto de
-- interrupção, e engolir um `statement_timeout` quebra o limite que o
-- Supabase impõe por papel. Então não se engole.
--
-- ── O QUE A PONTE GARANTE, sem retórica ─────────────────────
--
-- ISOLADO — o BRAIN falha, a venda é salva do mesmo jeito:
--   · qualquer erro SQL comum dentro do bloco protegido — unique, check,
--     FK, RLS, tipo, divisão por zero, deadlock detectado, disco cheio
--     numa tabela do BRAIN;
--   · `lock_timeout` estourado esperando uma linha do BRAIN. Medido, não
--     suposto: `lock_timeout` levanta `lock_not_available` (55P03), e
--     esse OTHERS captura. É o PT5 de pontes-concorrentes.sh.
--
-- NÃO ISOLADO — a transação comercial cai junto:
--   · `query_canceled` (57014): `statement_timeout` da sessão, ou alguém
--     cancelando a consulta. O Supabase põe 8s em `authenticated`, então
--     este caso é real, não teórico — PT5b;
--   · `assert_failure`;
--   · o que é FATAL e derruba a conexão (queda do servidor, fim do backend).
--
-- ── O QUE ESTA MIGRATION MUDA ───────────────────────────────
--
-- 1. Não sobra NENHUMA instrução fora do bloco protegido. Em
--    `on_order_change()` a releitura de `public.orders` estava fora dele:
--    um deadlock ali derrubava a venda por um motivo que era do BRAIN.
--    Agora o bloco começa na primeira instrução e termina na última.
--
-- 2. A janela de exposição ao cancelamento encolhe ao mínimo: a ponte
--    faz consultas com índice e nada mais.
--
-- 3. Existe como DESCOBRIR o que faltou. Quando a ponte falha ela só
--    escreve `warning` no log do Postgres — que ninguém lê. Agora
--    `brain.erp_events_faltando()` responde a pergunta certa ("que venda
--    não chegou no barramento?") e `brain.repor_eventos_erp()` repõe,
--    sem duplicar o que já existe.
--
-- ── O LIMITE QUE NÃO SE RESOLVE AQUI ────────────────────────
--
-- Isolamento absoluto exige que a ponte NÃO rode dentro da transação
-- comercial. A menor solução adequada é uma fila durável (`pgmq`, que o
-- projeto já tem disponível e desligado): o gatilho enfileira uma linha
-- e um processador publica depois, fora da transação. Isso é mudança de
-- arquitetura, fica proposta para a Fase 1.1 — e não se promete aqui o
-- que só ela entrega.
-- ============================================================

-- ── 1. Índices para a reconciliação ─────────────────────────
-- Sem eles, procurar "que pedido não tem evento" varre o barramento
-- inteiro. Parciais: só eventos do ERP interessam.

create index if not exists idx_events_erp_quote
  on brain.events ((payload ->> 'quote_id'), (payload ->> 'status'))
  where source = 'erp' and payload ? 'quote_id';

create index if not exists idx_events_erp_order
  on brain.events ((payload ->> 'order_id'), (payload ->> 'status'))
  where source = 'erp' and payload ? 'order_id';

-- ── 2. A ponte do orçamento ─────────────────────────────────

create or replace function brain.on_quote_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_lead  uuid;
  v_opp   uuid;
begin
  -- TUDO daqui para baixo está dentro do bloco protegido. Não sobra
  -- instrução nenhuma fora: erro do BRAIN não é motivo para perder um
  -- orçamento, nem quando acontece na primeira linha.
  begin
    if tg_op = 'INSERT' then
      v_event := 'quote.created';
    elsif new.status is distinct from old.status then
      v_event := 'quote.' || new.status::text;
    else
      return null;
    end if;

    perform pg_catalog.set_config('brain.internal', 'on', true);

    select id, lead_id into v_opp, v_lead from brain.opportunities
     where quote_id = new.id order by created_at limit 1;
    if v_lead is null then
      select id into v_lead from brain.leads
       where customer_id = new.customer_id and merged_into_lead_id is null
       order by created_at limit 1;
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('quote_id', new.id, 'number', new.number, 'status', new.status,
                         'total', new.total, 'owner_id', new.owner_id),
      'quote:' || new.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson', v_lead, new.customer_id, v_opp, null, null, null, null, 1, '{}'::jsonb);

    if v_opp is not null and new.status = 'approved' then
      update brain.opportunities set stage = 'negotiation'
       where id = v_opp and stage in ('prospecting', 'qualified', 'proposal');
    elsif v_opp is not null and new.status = 'sent' then
      update brain.opportunities set stage = 'proposal'
       where id = v_opp and stage in ('prospecting', 'qualified');
    end if;

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    -- `OTHERS` não cobre cancelamento nem timeout — ver o cabeçalho.
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning '[brain-ponte] orcamento % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

-- ── 3. A ponte do pedido ────────────────────────────────────

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_order public.orders%rowtype;
  r       record;
begin
  begin
    -- No INSERT este gatilho é DEFERRED: dispara no commit, quando os
    -- itens já entraram e o total já foi recalculado. A releitura vive
    -- AQUI DENTRO — antes ela estava fora do bloco, e um deadlock nela
    -- derrubava a venda.
    select * into v_order from public.orders where id = new.id;
    if not found then return null; end if;

    if tg_op = 'INSERT' then
      v_event := 'order.created';
    elsif new.status is distinct from old.status then
      v_event := 'order.' || new.status::text;
    else
      return null;
    end if;

    perform pg_catalog.set_config('brain.internal', 'on', true);

    if tg_op = 'INSERT' and v_order.quote_id is not null then
      for r in
        update brain.opportunities
           set order_id = v_order.id, stage = 'won',
               customer_id = coalesce(customer_id, v_order.customer_id)
         where quote_id = v_order.quote_id and stage not in ('won', 'lost')
         returning id, lead_id
      loop
        if r.lead_id is not null then
          update brain.leads
             set status = 'converted',
                 converted_at = coalesce(converted_at, now()),
                 customer_id = coalesce(customer_id, v_order.customer_id)
           where id = r.lead_id;
        end if;
      end loop;
    elsif v_event = 'order.cancelled' then
      update brain.opportunities set stage = 'negotiation'
       where order_id = v_order.id and stage = 'won';
    end if;

    perform brain.ingest_event(
      v_event, 'erp',
      jsonb_build_object('order_id', v_order.id, 'number', v_order.number, 'status', v_order.status,
                         'total', v_order.total, 'quote_id', v_order.quote_id, 'owner_id', v_order.owner_id),
      'order:' || v_order.id::text || ':' || v_event || ':' || pg_catalog.txid_current()::text,
      now(), 'salesperson',
      (select o.lead_id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      v_order.customer_id,
      (select o.id from brain.opportunities o where o.order_id = v_order.id order by o.created_at limit 1),
      null, null, null, null, 1, '{}'::jsonb);

    perform pg_catalog.set_config('brain.internal', 'off', true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    raise warning '[brain-ponte] pedido % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

-- ── 4. Descobrir o que a ponte deixou passar ────────────────
-- A pergunta prática é "que venda não chegou ao barramento?". A resposta
-- não depende da chave de deduplicação (que carrega o txid e por isso
-- não se recalcula): compara-se o ESTADO ATUAL da venda com o que existe
-- publicado para ela.

create or replace function brain.erp_events_faltando()
returns table (
  entidade      text,
  id            uuid,
  numero        text,
  status        text,
  atualizado_em timestamptz
)
language sql stable security definer set search_path = '' as $$
  select 'quote'::text, q.id, q.number::text, q.status::text, q.updated_at
    from public.quotes q
   where q.deleted_at is null
     and (select public.is_admin())
     and not exists (
       select 1 from brain.events e
        where e.source = 'erp'
          and e.payload ->> 'quote_id' = q.id::text
          and e.payload ->> 'status'   = q.status::text)
  union all
  select 'order'::text, o.id, o.number::text, o.status::text, o.updated_at
    from public.orders o
   where o.deleted_at is null
     and (select public.is_admin())
     and not exists (
       select 1 from brain.events e
        where e.source = 'erp'
          and e.payload ->> 'order_id' = o.id::text
          and e.payload ->> 'status'   = o.status::text)
  order by 5 desc;
$$;

revoke execute on function brain.erp_events_faltando() from public, anon;
grant  execute on function brain.erp_events_faltando() to authenticated, service_role;

comment on function brain.erp_events_faltando() is
  'Orcamentos e pedidos cujo estado atual nunca foi publicado no barramento. E o antidoto do `raise warning`, que so vive no log do Postgres. So administrador enxerga.';

-- ── 5. Repor o que faltou ───────────────────────────────────
-- Idempotente por construção: republica só o que `erp_events_faltando()`
-- ainda acusa, e cada evento reposto carrega `reposto_em` no metadata —
-- reposição é fato administrativo e fica registrada como tal.

create or replace function brain.repor_eventos_erp(p_limite integer default 500)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  r      record;
  v_n    integer := 0;
begin
  if not (select public.is_admin()) then
    raise exception 'Somente administrador repoe evento do barramento'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 5000 then
    raise exception 'Limite de reposicao fora da faixa (1 a 5000)';
  end if;

  perform pg_catalog.set_config('brain.internal', 'on', true);

  for r in select * from brain.erp_events_faltando() limit p_limite loop
    if r.entidade = 'quote' then
      perform brain.ingest_event(
        case when r.status = 'draft' then 'quote.created' else 'quote.' || r.status end,
        'erp',
        (select jsonb_build_object('quote_id', q.id, 'number', q.number, 'status', q.status,
                                   'total', q.total, 'owner_id', q.owner_id)
           from public.quotes q where q.id = r.id),
        'quote:' || r.id::text || ':reposicao:' || r.atualizado_em::text,
        r.atualizado_em, 'salesperson', null,
        (select q.customer_id from public.quotes q where q.id = r.id),
        null, null, null, null, null, 1,
        jsonb_build_object('reposto_em', now(), 'reposto_por', (select auth.uid())));
    else
      perform brain.ingest_event(
        case when r.status = 'draft' then 'order.created' else 'order.' || r.status end,
        'erp',
        (select jsonb_build_object('order_id', o.id, 'number', o.number, 'status', o.status,
                                   'total', o.total, 'quote_id', o.quote_id, 'owner_id', o.owner_id)
           from public.orders o where o.id = r.id),
        'order:' || r.id::text || ':reposicao:' || r.atualizado_em::text,
        r.atualizado_em, 'salesperson', null,
        (select o.customer_id from public.orders o where o.id = r.id),
        null, null, null, null, null, 1,
        jsonb_build_object('reposto_em', now(), 'reposto_por', (select auth.uid())));
    end if;
    v_n := v_n + 1;
  end loop;

  perform pg_catalog.set_config('brain.internal', 'off', true);
  return v_n;
exception when others then
  perform pg_catalog.set_config('brain.internal', 'off', true);
  raise;
end;
$$;

revoke execute on function brain.repor_eventos_erp(integer) from public, anon;
grant  execute on function brain.repor_eventos_erp(integer) to authenticated, service_role;

comment on function brain.repor_eventos_erp(integer) is
  'Republica no barramento o estado atual das vendas que `erp_events_faltando()` acusa. Idempotente: rodar duas vezes nao duplica.';
