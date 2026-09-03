-- ============================================================
-- 0903140000 · Entrada de mercadoria (Onda 2C)
--
-- Fecha o ciclo: o fornecedor de 2A entrega, o livro de 2B recebe, e o
-- custo do produto — que sustenta a margem por setor da Fase 1 — passa a
-- vir de um documento, e não da digitação de alguém.
--
-- DECISÕES COMERCIAIS (do Wilson, 03/09)
--
--   1. UM documento, não dois. Não existe "pedido de compra" no sistema:
--      o pedido ao fornecedor é WhatsApp e e-mail, e inventar uma tela
--      para ele seria pedir que a AgroTork digitasse duas vezes o que
--      faz uma vez. O que o sistema registra é a NOTA QUE CHEGOU.
--
--   2. A entrada ATUALIZA o custo do produto, e mostra o que mudou. O
--      custo anterior não se perde: `product_costs` já é histórico com
--      vigência, e a entrada fecha a linha antiga e abre a nova. Nenhum
--      preço de VENDA muda sozinho — quem sugere preço é a margem por
--      setor, e ela continua sendo aplicada por decisão de alguém.
--
--   3. O frete da nota é RATEADO POR VALOR. O drone de R$ 12.000 absorve
--      mais frete que a hélice de R$ 60. Ratear por peça faria a hélice
--      carregar o mesmo frete do drone, e o custo dela ficaria absurdo.
--
-- RASCUNHO E RECEBIMENTO
--
-- A nota é digitada como RASCUNHO e só mexe em estoque e custo quando
-- alguém confirma o recebimento. É a mesma ideia do orçamento: enquanto
-- é rascunho, erra-se à vontade; depois de confirmado, o documento
-- congela e a correção é outro lançamento.
--
-- TUDO AQUI É DO ADMINISTRADOR
--
-- Uma nota de compra é custo da primeira à última linha. Não existe
-- "leitura para o vendedor" nesta tabela — seria o mesmo vazamento que a
-- migration 1200 fechou em `products` e que 2B evitou em
-- `stock_movements`. O vendedor vê o SALDO que a entrada gerou; não vê
-- quanto ela custou.
-- ============================================================

create type public.purchase_status as enum ('draft', 'received', 'cancelled');

-- ── Numeração própria ───────────────────────────────────────
create table public.purchase_sequences (
  year        integer primary key,
  last_number integer not null default 0
);

create or replace function public.next_purchase_number(p_year integer default null)
returns table (seq_year integer, seq_number integer, formatted text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year integer := coalesce(p_year, extract(year from current_date)::int);
  v_num  integer;
begin
  insert into public.purchase_sequences (year, last_number)
  values (v_year, 1)
  on conflict (year) do update set last_number = public.purchase_sequences.last_number + 1
  returning last_number into v_num;

  return query select v_year, v_num, 'ENT-' || v_year || '-' || lpad(v_num::text, 4, '0');
end;
$$;

revoke execute on function public.next_purchase_number(integer) from public, anon;

-- ── A nota ──────────────────────────────────────────────────
create table public.purchases (
  id              uuid primary key default gen_random_uuid(),
  number          text not null,
  sequence_year   integer not null,
  sequence_number integer not null,

  supplier_id     uuid not null references public.suppliers(id) on delete restrict,
  status          public.purchase_status not null default 'draft',

  -- Sob qual condição a mercadoria foi comprada. É o que decide em QUAL
  -- custo do produto esta entrada mexe: à vista e faturado têm preços
  -- diferentes, e misturá-los estragaria os dois.
  condition_id    uuid not null references public.price_conditions(id) on delete restrict,

  -- O documento do fornecedor. Não é a nossa numeração: é a dele, e é
  -- por ela que a nota é procurada quando o contador pergunta.
  invoice_number  text,
  invoice_series  text,
  invoice_key     text,          -- chave de 44 dígitos da NF-e, quando houver
  issue_date      date not null default current_date,
  received_date   date,

  freight_amount  numeric(14,2) not null default 0 check (freight_amount  >= 0),
  other_amount    numeric(14,2) not null default 0 check (other_amount    >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),

  -- Soma das linhas, e o total da nota. Calculados pelo banco.
  items_total     numeric(14,2) not null default 0 check (items_total >= 0),
  total           numeric(14,2) not null default 0 check (total       >= 0),

  notes           text,

  received_at     timestamptz,
  cancelled_at    timestamptz,

  created_by      uuid references public.profiles(id) on delete set null,
  updated_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

create unique index idx_purchases_number   on public.purchases (number);
create index idx_purchases_supplier on public.purchases (supplier_id) where deleted_at is null;
create index idx_purchases_status   on public.purchases (status)      where deleted_at is null;
create index idx_purchases_issue    on public.purchases (issue_date desc);

-- A mesma nota do mesmo fornecedor não se lança duas vezes. Índice
-- PARCIAL: nota sem número informado continua permitida — entrada de
-- peça avulsa, brinde, garantia.
create unique index idx_purchases_invoice
  on public.purchases (supplier_id, upper(invoice_number), coalesce(upper(invoice_series), ''))
  where invoice_number is not null and invoice_number <> '' and deleted_at is null;

create trigger trg_purchases_updated_at before update on public.purchases
  for each row execute function public.set_updated_at();

-- ── As linhas ───────────────────────────────────────────────
create table public.purchase_items (
  id                uuid primary key default gen_random_uuid(),
  purchase_id       uuid not null references public.purchases(id) on delete cascade,
  product_id        uuid not null references public.products(id)  on delete restrict,

  quantity          numeric(14,3) not null check (quantity > 0),
  -- O que o fornecedor cobrou pela peça, antes do frete.
  unit_cost         numeric(14,2) not null default 0 check (unit_cost >= 0),

  line_total        numeric(14,2) generated always as (round(quantity * unit_cost, 2)) stored,

  -- Preenchidos no RECEBIMENTO, não na digitação:
  --   · `freight_share` é a fatia do frete que coube a esta linha;
  --   · `landed_cost` é o custo unitário final — é ELE que vai para
  --     `product_costs`, e não `unit_cost`;
  --   · `previous_cost` é o que valia antes, guardado aqui para a tela
  --     poder dizer "subiu de X para Y" sem refazer a conta.
  freight_share     numeric(14,2) not null default 0 check (freight_share >= 0),
  landed_cost       numeric(14,4),
  previous_cost     numeric(14,2),

  sort_order        integer not null default 0,
  notes             text,
  created_at        timestamptz not null default now()
);

create index idx_purchase_items_purchase on public.purchase_items (purchase_id, sort_order);
create index idx_purchase_items_product  on public.purchase_items (product_id);

-- O mesmo produto duas vezes na mesma nota quase sempre é digitação
-- repetida. Quando for legítimo (lotes diferentes), some as quantidades.
create unique index idx_purchase_items_unico
  on public.purchase_items (purchase_id, product_id);

-- ── Totais: quem soma é o banco ─────────────────────────────
-- Mesmo desenho de `recalculate_order_totals`. Somar na tela dá um
-- número diferente do que o banco entende por total da nota.
create or replace function public.recalculate_purchase_totals(p_purchase_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_itens numeric(14,2);
begin
  select coalesce(sum(line_total), 0) into v_itens
    from public.purchase_items where purchase_id = p_purchase_id;

  update public.purchases
     set items_total = v_itens,
         total       = greatest(v_itens + freight_amount + other_amount - discount_amount, 0)
   where id = p_purchase_id;
end;
$$;

revoke execute on function public.recalculate_purchase_totals(uuid) from public, anon;

create or replace function public.touch_purchase_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recalculate_purchase_totals(coalesce(new.purchase_id, old.purchase_id));
  return coalesce(new, old);
end;
$$;

revoke execute on function public.touch_purchase_totals() from public, anon;

create trigger trg_purchase_items_totals
  after insert or update or delete on public.purchase_items
  for each row execute function public.touch_purchase_totals();

-- Frete, despesa e desconto também mexem no total.
create or replace function public.touch_purchase_own_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.freight_amount  is distinct from old.freight_amount
  or new.other_amount    is distinct from old.other_amount
  or new.discount_amount is distinct from old.discount_amount then
    perform public.recalculate_purchase_totals(new.id);
  end if;
  return new;
end;
$$;

revoke execute on function public.touch_purchase_own_totals() from public, anon;

create trigger trg_purchases_own_totals
  after update on public.purchases
  for each row execute function public.touch_purchase_own_totals();

-- ── Numeração no nascimento ─────────────────────────────────
create or replace function public.set_purchase_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ano integer; v_num integer; v_txt text;
begin
  if new.number is not null and new.number <> '' then
    return new;
  end if;

  select seq_year, seq_number, formatted into v_ano, v_num, v_txt
    from public.next_purchase_number(extract(year from coalesce(new.issue_date, current_date))::int);

  new.number          := v_txt;
  new.sequence_year   := v_ano;
  new.sequence_number := v_num;
  return new;
end;
$$;

revoke execute on function public.set_purchase_number() from public, anon;

create trigger trg_purchases_number
  before insert on public.purchases
  for each row execute function public.set_purchase_number();

-- ── Congelamento depois do recebimento ──────────────────────
-- Nota recebida não muda de conteúdo: ela já virou estoque e já virou
-- custo. Corrigir é outro lançamento, não uma reescrita — a mesma regra
-- do pedido de venda.
create or replace function public.freeze_received_purchase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- O próprio recebimento precisa escrever. A marca é transaction-local,
  -- e não `pg_trigger_depth()`: a função chama o UPDATE por `perform`, e
  -- a profundidade continuaria 1. Foi assim que este mesmo erro apareceu
  -- em `freeze_order_commercials` (migration 0903060000).
  if coalesce(pg_catalog.current_setting('agrotork.recebendo_nota', true), 'off') = 'on' then
    return new;
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

  if old.status = 'draft' then
    return new;
  end if;

  if new.supplier_id     is distinct from old.supplier_id
  or new.condition_id    is distinct from old.condition_id
  or new.freight_amount  is distinct from old.freight_amount
  or new.other_amount    is distinct from old.other_amount
  or new.discount_amount is distinct from old.discount_amount
  or new.issue_date      is distinct from old.issue_date
  or new.invoice_number  is distinct from old.invoice_number then
    raise exception 'Nota já recebida não muda de conteúdo. Para corrigir, lance um ajuste de estoque.'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

revoke execute on function public.freeze_received_purchase() from public, anon;

create trigger trg_purchases_freeze
  before update on public.purchases
  for each row execute function public.freeze_received_purchase();

create trigger trg_purchase_items_freeze
  before insert or update or delete on public.purchase_items
  for each row execute function public.freeze_received_purchase();

-- ── RLS: só administrador, do começo ao fim ─────────────────
alter table public.purchases      enable row level security;
alter table public.purchase_items enable row level security;

create policy purchases_admin on public.purchases
  for all to authenticated
  using ((select public.is_admin()) and deleted_at is null)
  with check ((select public.is_admin()));

create policy purchase_items_admin on public.purchase_items
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

revoke all on public.purchases      from anon;
revoke all on public.purchase_items from anon;
grant select, insert, update, delete on public.purchases      to authenticated;
grant select, insert, update, delete on public.purchase_items to authenticated;

-- ── O recebimento ───────────────────────────────────────────
-- É aqui que a nota vira estoque e vira custo. Tudo em UMA transação:
-- ou os três acontecem, ou nenhum acontece. Uma entrada que movimentou o
-- estoque mas não atualizou o custo seria pior do que não ter entrado.
create or replace function public.receive_purchase(p_purchase_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nota      public.purchases%rowtype;
  v_rateio    numeric(14,2);
  v_itens     int := 0;
  r_item      record;
  v_movimento uuid;
  v_anterior  numeric(14,2);
  v_vigente   public.product_costs%rowtype;
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

  if not exists (select 1 from public.purchase_items where purchase_id = p_purchase_id) then
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

revoke execute on function public.receive_purchase(uuid) from public, anon;
grant execute on function public.receive_purchase(uuid) to authenticated;

-- ── Cancelar ────────────────────────────────────────────────
-- Só rascunho se cancela. Nota já recebida virou estoque e virou custo:
-- desfazer isso em silêncio deixaria o saldo mentindo. O caminho é a
-- devolução ao fornecedor, na tela de estoque, que lança `return_out` e
-- deixa os dois movimentos à vista.
create or replace function public.cancel_purchase(p_purchase_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.purchase_status;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode cancelar nota'
      using errcode = 'insufficient_privilege';
  end if;

  select status into v_status from public.purchases
   where id = p_purchase_id and deleted_at is null;
  if not found then
    raise exception 'Nota não encontrada' using errcode = 'no_data_found';
  end if;

  if v_status <> 'draft' then
    raise exception 'Nota já recebida não se cancela. Registre a devolução ao fornecedor no estoque.'
      using errcode = 'check_violation';
  end if;

  perform pg_catalog.set_config('agrotork.recebendo_nota', 'on', true);
  update public.purchases
     set status = 'cancelled', cancelled_at = now(), updated_by = auth.uid()
   where id = p_purchase_id;
  perform pg_catalog.set_config('agrotork.recebendo_nota', 'off', true);

  return true;
end;
$$;

revoke execute on function public.cancel_purchase(uuid) from public, anon;
grant execute on function public.cancel_purchase(uuid) to authenticated;

-- ── Listagem ────────────────────────────────────────────────
create view public.purchases_list
with (security_invoker = true) as
select p.id,
       p.number,
       p.status,
       p.issue_date,
       p.received_date,
       p.invoice_number,
       p.items_total,
       p.total,
       p.created_at,
       p.updated_at,
       p.supplier_id,
       s.name                     as supplier_name,
       s.city                     as supplier_city,
       c.name                     as condition_name,
       (select count(*)::integer from public.purchase_items pi where pi.purchase_id = p.id)
                                  as items_count
  from public.purchases p
  join public.suppliers       s on s.id = p.supplier_id
  join public.price_conditions c on c.id = p.condition_id
 where p.deleted_at is null;

comment on table public.purchases is
  'Nota de entrada de mercadoria. Rascunho ate o recebimento; depois congela. Tudo aqui e custo: somente administrador.';
comment on column public.purchase_items.landed_cost is
  'Custo unitario final, ja com a fatia do frete. E ele que vai para product_costs, nao unit_cost.';
