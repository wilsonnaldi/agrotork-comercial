-- ============================================================
-- 0909110000 · Guardas da Onda 2 (correção de auditoria)
--
-- Auditoria de banco de 09/09/2026 sobre as sete migrations de
-- 20260903100000 a 20260903160000 (fornecedores, estoque, série,
-- compras, financeiro, NF-e), que ainda NÃO estão em produção. Nenhuma
-- delas foi alterada: este arquivo corrige por cima, para que as oito
-- subam juntas.
--
-- O que estava errado, em uma linha cada:
--
--   A5  item de nota mudava de nota por UPDATE, inclusive saindo de nota
--       já recebida — e a nota de origem ficava com o total antigo.
--   A7  `purchase_sequences` sem RLS e com ALL para anon/authenticated.
--   A8  nota recebida voltava a `draft` por UPDATE direto e era recebida
--       de novo: estoque e custo em dobro. E `status='received'` direto
--       criava conta a pagar sem passar pelo recebimento.
--   A9  `items_total`/`total` da nota e `amount`/`status` do título
--       eram escritos direto, sem recálculo e sem coerência com as baixas.
--   A13 `invoice_key` (chave de 44 dígitos da NF-e) não era única: a
--       mesma nota entrava duas vezes com o número grafado diferente.
--   A14 nenhuma tabela nova tinha trilha de auditoria.
--   A10 `next_purchase_number()`, `recalculate_purchase_totals()` e
--       `refresh_financial_status()` executáveis por `authenticated`.
--   A15 quinze funções `security definer` com `search_path = public`.
--   A16 `purchases_list`, `financial_position`, `product_stock` com
--       SELECT para anon.
--   A17 administrador inseria `sale`/`purchase` direto no livro, sem o
--       custo irmão; rateio de frete perdia um centavo por nota.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- A5 · Item de nota não muda de nota
-- ════════════════════════════════════════════════════════════
-- Não há caso de uso: linha errada se apaga e se lança na nota certa.
-- Barrar é mais simples e mais seguro do que recalcular os dois lados e
-- ainda decidir o que fazer quando a origem já foi recebida.
create or replace function public.block_purchase_item_move()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.purchase_id is distinct from old.purchase_id then
    raise exception 'Item de nota nao muda de nota. Apague e lance na nota certa.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke execute on function public.block_purchase_item_move() from public, anon, authenticated;

drop trigger if exists trg_purchase_items_no_move on public.purchase_items;
create trigger trg_purchase_items_no_move
  before update on public.purchase_items
  for each row execute function public.block_purchase_item_move();

-- ════════════════════════════════════════════════════════════
-- A7 · O contador de notas é interno
-- ════════════════════════════════════════════════════════════
-- Mesmo desenho de `order_sequences`: RLS ligado sem policy alguma, e
-- privilégio nenhum para os papéis de aplicação. Quem mexe é
-- `next_purchase_number()`, que é security definer.
alter table public.purchase_sequences enable row level security;
revoke all on public.purchase_sequences from anon, authenticated, public;

-- ════════════════════════════════════════════════════════════
-- A8 · A situação da nota só anda pelas funções
-- ════════════════════════════════════════════════════════════
-- `receive_purchase()` e `cancel_purchase()` abrem a marca
-- `agrotork.recebendo_nota` antes de escrever. Fora delas, `status`,
-- `deleted_at` e os carimbos não mudam — nem para o administrador. Com a
-- nota recebida, o documento do fornecedor (número, série, chave)
-- também congela: é por ele que o contador procura a nota.
create or replace function public.freeze_received_purchase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_liberado boolean :=
    coalesce(pg_catalog.current_setting('agrotork.recebendo_nota', true), 'off') = 'on';
begin
  if v_liberado then
    return coalesce(new, old);
  end if;

  if tg_table_name = 'purchase_items' then
    if exists (
      select 1 from public.purchases
       where id = coalesce(new.purchase_id, old.purchase_id)
         and status <> 'draft'
    ) then
      raise exception 'Nota já recebida não muda de conteúdo. Para corrigir, lance um ajuste de estoque.'
        using errcode = 'restrict_violation';
    end if;
    return coalesce(new, old);
  end if;

  if new.status       is distinct from old.status
  or new.deleted_at   is distinct from old.deleted_at
  or new.received_at  is distinct from old.received_at
  or new.cancelled_at is distinct from old.cancelled_at then
    raise exception 'A situacao da nota so muda por receive_purchase() ou cancel_purchase().'
      using errcode = 'restrict_violation';
  end if;

  if old.status = 'draft' then
    return new;
  end if;

  if new.supplier_id     is distinct from old.supplier_id
  or new.condition_id    is distinct from old.condition_id
  or new.freight_amount  is distinct from old.freight_amount
  or new.other_amount    is distinct from old.other_amount
  or new.discount_amount is distinct from old.discount_amount
  or new.issue_date      is distinct from old.issue_date
  or new.invoice_number  is distinct from old.invoice_number
  or new.invoice_series  is distinct from old.invoice_series
  or new.invoice_key     is distinct from old.invoice_key then
    raise exception 'Nota já recebida não muda de conteúdo. Para corrigir, lance um ajuste de estoque.'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A9 · Totais da nota: escrita direta vira recálculo
-- ════════════════════════════════════════════════════════════
-- Mesmo desenho de `trg_recalc_from_quote` (20260901211122): quem grava
-- `items_total`/`total` pela API não erra o total — o gatilho refaz a
-- conta a partir das linhas. `pg_trigger_depth() = 1` evita a recursão
-- quando é o próprio recálculo escrevendo.
create or replace function public.touch_purchase_own_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.pg_trigger_depth() = 1 and (
     new.freight_amount  is distinct from old.freight_amount
  or new.other_amount    is distinct from old.other_amount
  or new.discount_amount is distinct from old.discount_amount
  or new.items_total     is distinct from old.items_total
  or new.total           is distinct from old.total) then
    perform public.recalculate_purchase_totals(new.id);
  end if;
  return new;
end;
$$;

-- ── Financeiro: status e cancelamento só pelas funções; valor congela
--    depois da primeira baixa ──────────────────────────────────
-- `refresh_financial_status()` e `cancel_financial_entry()` abrem a marca
-- `agrotork.financeiro`. Fora delas, `status` e `cancelled_at` não
-- mudam. `amount` muda enquanto não houver baixa; depois, o caminho é
-- estorno + título novo (a decisão comercial sobre desconto pós-baixa
-- fica em aberto e, até lá, o banco não deixa o saldo ficar negativo).
create or replace function public.protect_financial_entry()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if coalesce(pg_catalog.current_setting('agrotork.financeiro', true), 'off') = 'on' then
    return new;
  end if;

  if new.status       is distinct from old.status
  or new.cancelled_at is distinct from old.cancelled_at then
    raise exception 'Situacao do titulo e derivada das baixas; cancelamento so por cancel_financial_entry().'
      using errcode = 'check_violation';
  end if;

  if new.amount is distinct from old.amount
     and exists (select 1 from public.financial_payments where entry_id = old.id) then
    raise exception 'Titulo com baixa nao muda de valor. Estorne a baixa e lance outro titulo.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function public.protect_financial_entry() from public, anon, authenticated;

drop trigger if exists trg_financial_entries_protect on public.financial_entries;
create trigger trg_financial_entries_protect
  before update on public.financial_entries
  for each row execute function public.protect_financial_entry();

create or replace function public.refresh_financial_status(p_entry_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_valor numeric(14,2);
  v_pago  numeric(14,2);
  v_cancelado timestamptz;
begin
  select amount, cancelled_at into v_valor, v_cancelado
    from public.financial_entries where id = p_entry_id;
  if not found then return; end if;

  -- Cancelado é decisão de pessoa, não consequência de conta: a soma das
  -- baixas não pode tirar um título desse estado.
  if v_cancelado is not null then return; end if;

  select coalesce(sum(amount), 0) into v_pago
    from public.financial_payments where entry_id = p_entry_id;

  perform pg_catalog.set_config('agrotork.financeiro', 'on', true);
  update public.financial_entries
     set status = (case
                     when v_pago <= 0       then 'open'
                     when v_pago >= v_valor then 'settled'
                     else 'partial'
                   end)::public.financial_status
   where id = p_entry_id;
  perform pg_catalog.set_config('agrotork.financeiro', 'off', true);
end;
$$;

-- Valor que muda (sem baixa) reavalia o status: um título de 0 → 100
-- continua `open`, mas a regra passa a valer por gatilho, não por sorte.
create or replace function public.touch_financial_status_from_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.pg_trigger_depth() = 1 and new.amount is distinct from old.amount then
    perform public.refresh_financial_status(new.id);
  end if;
  return new;
end;
$$;

revoke execute on function public.touch_financial_status_from_entry() from public, anon, authenticated;

drop trigger if exists trg_financial_entries_amount on public.financial_entries;
create trigger trg_financial_entries_amount
  after update of amount on public.financial_entries
  for each row execute function public.touch_financial_status_from_entry();

create or replace function public.cancel_financial_entry(p_entry_id uuid, p_notes text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_pago numeric(14,2);
begin
  if not public.is_admin() then
    raise exception 'Somente administrador mexe no financeiro'
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(amount), 0) into v_pago
    from public.financial_payments where entry_id = p_entry_id;

  if v_pago <> 0 then
    raise exception 'Título com baixa não se cancela. Estorne a baixa primeiro.'
      using errcode = 'check_violation';
  end if;

  perform pg_catalog.set_config('agrotork.financeiro', 'on', true);
  update public.financial_entries
     set status = 'cancelled', cancelled_at = now(),
         notes = coalesce(nullif(btrim(p_notes), ''), notes),
         updated_by = auth.uid()
   where id = p_entry_id and cancelled_at is null;
  perform pg_catalog.set_config('agrotork.financeiro', 'off', true);

  if not found then
    raise exception 'Título não encontrado ou já cancelado' using errcode = 'no_data_found';
  end if;

  return true;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A13 · A chave da NF-e identifica a nota, em qualquer grafia do número
-- ════════════════════════════════════════════════════════════
-- Só dígitos (o XML traz 44; a tela pode trazer com espaço) e 44 exatos:
-- a aplicação já exige isso, e o banco passa a exigir também.
create or replace function public.normalize_purchase()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.invoice_key := public.only_digits(new.invoice_key);
  if new.invoice_key is not null and length(new.invoice_key) <> 44 then
    raise exception 'A chave da NF-e tem 44 digitos' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke execute on function public.normalize_purchase() from public, anon, authenticated;

drop trigger if exists trg_purchases_normalize on public.purchases;
create trigger trg_purchases_normalize
  before insert or update on public.purchases
  for each row execute function public.normalize_purchase();

-- Cancelada e excluída saem do índice: a mesma NF-e pode ser relançada
-- depois de um rascunho cancelado por engano.
create unique index if not exists idx_purchases_invoice_key
  on public.purchases (invoice_key)
  where invoice_key is not null and deleted_at is null and status <> 'cancelled';

-- ════════════════════════════════════════════════════════════
-- A17 · O livro do estoque só recebe lançamento pelas funções
-- ════════════════════════════════════════════════════════════
-- `register_stock_movement()` recusa `sale` e grava o custo irmão; o
-- INSERT direto (que a aplicação não usa — `src/modules/stock` chama a
-- RPC) fazia nenhuma das duas coisas. Sem a policy, `authenticated` não
-- insere linha nenhuma por conta própria; os gatilhos e as funções são
-- security definer e continuam escrevendo.
drop policy if exists stock_movements_insert on public.stock_movements;
revoke insert on public.stock_movements from authenticated;

-- E o rateio do frete fecha o centavo na última linha.
create or replace function public.receive_purchase(p_purchase_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nota      public.purchases%rowtype;
  v_rateio    numeric(14,2);
  v_itens     int := 0;
  r_item      record;
  v_movimento uuid;
  v_anterior  numeric(14,2);
  v_vigente   public.product_costs%rowtype;
  v_linhas    int;
  v_rateado   numeric(14,2) := 0;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode receber mercadoria'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_nota from public.purchases
   where id = p_purchase_id and deleted_at is null;
  if not found then
    raise exception 'Nota não encontrada' using errcode = 'no_data_found';
  end if;

  if v_nota.status <> 'draft' then
    raise exception 'Esta nota já foi %', case v_nota.status
      when 'received' then 'recebida' else 'cancelada' end
      using errcode = 'check_violation';
  end if;

  select count(*) into v_linhas from public.purchase_items where purchase_id = p_purchase_id;
  if v_linhas = 0 then
    raise exception 'Nota sem itens não entra no estoque' using errcode = 'check_violation';
  end if;

  -- O que será rateado: frete + outras despesas − desconto. Pode dar
  -- negativo se o desconto for maior que o frete; nesse caso o rateio
  -- BARATEIA a mercadoria, que é exatamente o certo.
  v_rateio := v_nota.freight_amount + v_nota.other_amount - v_nota.discount_amount;

  perform pg_catalog.set_config('agrotork.recebendo_nota', 'on', true);

  for r_item in
    select pi.*, pc.cost_price as custo_atual
      from public.purchase_items pi
      left join public.product_costs pc
             on pc.product_id   = pi.product_id
            and pc.condition_id = v_nota.condition_id
            and pc.valid_to is null
     where pi.purchase_id = p_purchase_id
     order by pi.sort_order, pi.id
  loop
    -- Rateio POR VALOR: a fatia de cada linha é proporcional ao que ela
    -- representa na nota. `items_total` zero (nota de brinde) não divide
    -- por zero: o rateio simplesmente não acontece.
    declare
      v_fatia  numeric(14,2) := 0;
      v_landed numeric(14,4);
    begin
      if v_nota.items_total > 0 and v_rateio <> 0 then
        v_fatia := round(v_rateio * (r_item.line_total / v_nota.items_total), 2);
        -- A última linha fecha a conta: arredondar linha a linha deixava
        -- o rateio somando 99,99 para um frete de 100,00, e o centavo
        -- perdido virava custo que nenhuma nota explicava.
        if v_itens = v_linhas - 1 then
          v_fatia := v_rateio - v_rateado;
        end if;
        v_rateado := v_rateado + v_fatia;
      end if;

      v_landed := round((r_item.line_total + v_fatia) / r_item.quantity, 4);
      if v_landed < 0 then v_landed := 0; end if;

      v_anterior := r_item.custo_atual;

      update public.purchase_items
         set freight_share = greatest(v_fatia, 0),
             landed_cost   = v_landed,
             previous_cost = v_anterior
       where id = r_item.id;

      -- 1. O livro do estoque recebe a entrada.
      insert into public.stock_movements
        (product_id, reason, quantity, notes, created_by)
      values (r_item.product_id, 'purchase', r_item.quantity,
              'Entrada ' || v_nota.number, auth.uid())
      returning id into v_movimento;

      insert into public.stock_movement_costs (movement_id, unit_cost)
      values (v_movimento, round(v_landed, 2));

      -- 2. O custo do produto passa a ser o desta nota.
      --
      -- `product_costs` é histórico com vigência: a linha antiga FECHA,
      -- e uma nova abre hoje. O caso de borda é a segunda nota do mesmo
      -- dia — aí não há histórico a preservar entre as duas, e a linha
      -- de hoje é atualizada no lugar (o índice de vigência não
      -- permitiria duas com o mesmo `valid_from`).
      select * into v_vigente from public.product_costs
       where product_id   = r_item.product_id
         and condition_id = v_nota.condition_id
         and valid_to is null;

      if found and v_vigente.valid_from = current_date then
        update public.product_costs
           set cost_price = round(v_landed, 2), updated_by = auth.uid()
         where id = v_vigente.id;
      else
        if found then
          update public.product_costs
             set valid_to = current_date - 1
           where id = v_vigente.id;
        end if;

        insert into public.product_costs
          (product_id, condition_id, cost_price, valid_from, updated_by, source_reference)
        values (r_item.product_id, v_nota.condition_id, round(v_landed, 2),
                current_date, auth.uid(), v_nota.number);
      end if;

      v_itens := v_itens + 1;
    end;
  end loop;

  update public.purchases
     set status        = 'received',
         received_at   = now(),
         received_date = coalesce(received_date, current_date),
         updated_by    = auth.uid()
   where id = p_purchase_id;

  perform pg_catalog.set_config('agrotork.recebendo_nota', 'off', true);

  return v_itens;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A15 · `search_path = ''` nas security definer que nasceram com `public`
-- ════════════════════════════════════════════════════════════
-- Todas já qualificam `public.` e `auth.`; só a declaração estava fora
-- do padrão que o CLAUDE.md exige. (`quote_is_editable` foi tratada na
-- migration anterior; `receive_purchase`, `cancel_financial_entry` e
-- `freeze_received_purchase` foram redefinidas acima já com ''.)
alter function public.assign_serial_to_order(uuid, uuid)                       set search_path = '';
alter function public.cancel_purchase(uuid)                                    set search_path = '';
alter function public.delete_customer(uuid)                                    set search_path = '';
alter function public.delete_supplier(uuid)                                    set search_path = '';
alter function public.register_financial_payment(uuid, numeric, date, text, text) set search_path = '';
alter function public.register_stock_movement(uuid, public.stock_reason, numeric, text) set search_path = '';
alter function public.release_serial(uuid)                                     set search_path = '';
alter function public.remember_supplier_product(uuid, text, uuid, text)        set search_path = '';
alter function public.return_order_stock(uuid, text)                           set search_path = '';
alter function public.split_financial_entry(uuid, integer, date, integer)      set search_path = '';
alter function public.write_payable_from_purchase()                            set search_path = '';
alter function public.write_receivable_from_order()                            set search_path = '';
alter function public.write_sale_stock_movements()                             set search_path = '';
alter function public.known_supplier_products(uuid)                            set search_path = '';

-- ════════════════════════════════════════════════════════════
-- A10 · Contadores, recálculos e gatilhos da Onda 2 não são RPC
-- ════════════════════════════════════════════════════════════
-- Mesmo achado da migration anterior: `revoke from public, anon` não
-- tira o EXECUTE que o default privilege do Supabase concede nominalmente
-- a `authenticated`. Vendedor queimava ENT-2026-nnnn à vontade.
revoke execute on function public.next_purchase_number(integer)      from public, anon, authenticated;
revoke execute on function public.recalculate_purchase_totals(uuid)  from public, anon, authenticated;
revoke execute on function public.refresh_financial_status(uuid)     from public, anon, authenticated;
revoke execute on function public.normalize_supplier()               from public, anon, authenticated;
revoke execute on function public.block_stock_movement_change()      from public, anon, authenticated;
revoke execute on function public.write_sale_stock_movements()       from public, anon, authenticated;
revoke execute on function public.normalize_product_serial()         from public, anon, authenticated;
revoke execute on function public.touch_purchase_totals()            from public, anon, authenticated;
revoke execute on function public.touch_purchase_own_totals()        from public, anon, authenticated;
revoke execute on function public.set_purchase_number()              from public, anon, authenticated;
revoke execute on function public.freeze_received_purchase()         from public, anon, authenticated;
revoke execute on function public.block_financial_payment_change()   from public, anon, authenticated;
revoke execute on function public.touch_financial_status()           from public, anon, authenticated;
revoke execute on function public.write_receivable_from_order()      from public, anon, authenticated;
revoke execute on function public.write_payable_from_purchase()      from public, anon, authenticated;
revoke execute on function public.normalize_supplier_product()       from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- A16 · Views novas fora do alcance de anon
-- ════════════════════════════════════════════════════════════
-- São `security_invoker`, então anon já batia em "permission denied" na
-- tabela de baixo — mas a regra é a tabela (e a view) nascer revogada.
revoke all on public.purchases_list     from anon;
revoke all on public.financial_position from anon;
revoke all on public.product_stock      from anon;

-- ════════════════════════════════════════════════════════════
-- A14 · Trilha de auditoria nas tabelas da Onda 2
-- ════════════════════════════════════════════════════════════
-- `audit_capture` já ignora as colunas derivadas destas tabelas (ver
-- 20260909100000). `stock_movement_costs` e `purchase_sequences` ficam
-- de fora: o custo do lançamento é consequência do lançamento, que já é
-- evento; o contador é interno.
drop trigger if exists trg_audit_suppliers on public.suppliers;
create trigger trg_audit_suppliers after insert or update or delete on public.suppliers
  for each row execute function public.audit_capture('supplier', 'id', 'name', '', '');

drop trigger if exists trg_audit_stock_movements on public.stock_movements;
create trigger trg_audit_stock_movements after insert or update or delete on public.stock_movements
  for each row execute function public.audit_capture('stock_movement', 'id', 'reason', 'product', 'product_id');

drop trigger if exists trg_audit_product_serials on public.product_serials;
create trigger trg_audit_product_serials after insert or update or delete on public.product_serials
  for each row execute function public.audit_capture('product_serial', 'id', 'serial', 'product', 'product_id');

drop trigger if exists trg_audit_purchases on public.purchases;
create trigger trg_audit_purchases after insert or update or delete on public.purchases
  for each row execute function public.audit_capture('purchase', 'id', 'number', '', '');

drop trigger if exists trg_audit_purchase_items on public.purchase_items;
create trigger trg_audit_purchase_items after insert or update or delete on public.purchase_items
  for each row execute function public.audit_capture('purchase_item', 'id', '', 'purchase', 'purchase_id');

drop trigger if exists trg_audit_financial_entries on public.financial_entries;
create trigger trg_audit_financial_entries after insert or update or delete on public.financial_entries
  for each row execute function public.audit_capture('financial_entry', 'id', 'description', '', '');

drop trigger if exists trg_audit_financial_payments on public.financial_payments;
create trigger trg_audit_financial_payments after insert or update or delete on public.financial_payments
  for each row execute function public.audit_capture('financial_payment', 'id', '', 'financial_entry', 'entry_id');

drop trigger if exists trg_audit_supplier_products on public.supplier_products;
create trigger trg_audit_supplier_products after insert or update or delete on public.supplier_products
  for each row execute function public.audit_capture('supplier_product', 'id', 'supplier_code', 'supplier', 'supplier_id');
