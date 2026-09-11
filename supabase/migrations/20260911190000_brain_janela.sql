-- ============================================================
-- BRAIN — encolher a janela em que a ponte pode derrubar uma venda
--
-- O que está em jogo: `exception when others` NÃO captura
-- `query_canceled` (57014). Enquanto a ponte roda dentro da transação
-- comercial, um `statement_timeout` que estoure LÁ DENTRO derruba a
-- venda. Isso não some com esta migration — e não se promete que suma.
-- O que dá para fazer é encolher a janela, e é o que ela faz.
--
-- ── A MEDIDA ────────────────────────────────────────────────
--
-- A janela tem dois pedaços:
--
--   (a) o tempo que a ponte gasta fazendo o trabalho dela —
--       meia dúzia de consultas com índice;
--   (b) o tempo que ela passa ESPERANDO um bloqueio de linha, quando
--       outra transação está mexendo na mesma oportunidade.
--
-- (b) é o que dominava, e é justamente o pedaço perigoso: esperar não
-- consome nada, só relógio, e o relógio é o `statement_timeout` de 8s
-- que o Supabase põe em `authenticated`. Quem espera 8s num lock leva
-- 57014 — o código que escapa do `OTHERS`.
--
-- ── A CORREÇÃO ──────────────────────────────────────────────
--
-- `lock_timeout` local de 250ms dentro do bloco protegido. Espera de
-- bloqueio passa a levantar `lock_not_available` (55P03) — que o
-- `OTHERS` CAPTURA. O pedaço (b) sai da faixa perigosa e entra na faixa
-- isolada: a venda passa, o evento se perde, e
-- `brain.divergencias_erp()` acusa depois.
--
-- Medido em PT5 e PT5b: `lock_timeout` → 55P03, capturado, venda passa;
-- `statement_timeout` → 57014, escapa, venda cai. Esta migration faz o
-- caso comum cair sempre no primeiro.
--
-- O valor da sessão é salvo e devolvido nos dois caminhos — sucesso e
-- exceção. A ponte não deixa herança de configuração.
--
-- ── O QUE SOBRA ─────────────────────────────────────────────
--
-- Sobra (a): o tempo de execução da própria ponte. Se o
-- `statement_timeout` da venda estourar exatamente dentro desses
-- milissegundos, a venda cai. É risco residual declarado, com a medida
-- ao lado — ver o relatório, seção do acoplamento.
-- ============================================================

create or replace function brain.on_quote_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_lead  uuid;
  v_opp   uuid;
  v_lock  text;
begin
  begin
    if tg_op = 'INSERT' then
      v_event := 'quote.created';
    elsif new.status is distinct from old.status then
      v_event := 'quote.' || new.status::text;
    else
      return null;
    end if;

    -- Esperar bloqueio é o pedaço perigoso: 250ms e desiste, no codigo
    -- que o OTHERS captura. O valor da sessao volta ao que era.
    v_lock := pg_catalog.current_setting('lock_timeout', true);
    perform pg_catalog.set_config('lock_timeout', '250ms', true);
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
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
  exception when others then
    -- `OTHERS` não cobre cancelamento nem timeout de statement — ver o
    -- cabeçalho de 20260911150000.
    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
    raise warning '[brain-ponte] orcamento % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;

create or replace function brain.on_order_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event text;
  v_order public.orders%rowtype;
  r       record;
  v_lock  text;
begin
  begin
    v_lock := pg_catalog.current_setting('lock_timeout', true);
    perform pg_catalog.set_config('lock_timeout', '250ms', true);

    -- No INSERT este gatilho é DEFERRED: dispara no commit, quando os
    -- itens já entraram e o total já foi recalculado.
    select * into v_order from public.orders where id = new.id;
    if not found then
      perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
      return null;
    end if;

    if tg_op = 'INSERT' then
      v_event := 'order.created';
    elsif new.status is distinct from old.status then
      v_event := 'order.' || new.status::text;
    else
      perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
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
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
  exception when others then
    perform pg_catalog.set_config('brain.internal', 'off', true);
    perform pg_catalog.set_config('lock_timeout', coalesce(v_lock, '0'), true);
    raise warning '[brain-ponte] pedido % evento %: %', new.id, coalesce(v_event, '?'), sqlerrm;
  end;

  return null;
end;
$$;
