-- ============================================================
-- 0903150000 · Financeiro (Fase 7) — o que entra e o que sai
--
-- O PROBLEMA QUE ISTO RESOLVE
--
-- Hoje o sistema sabe que a AgroTork vendeu R$ 10.576,50 e sabe que
-- comprou R$ 1.400 de mercadoria. Não sabe se algum dos dois foi pago.
-- Essa é a pergunta que a empresa faz todo dia — "quanto tenho a
-- receber, quanto tenho a pagar" — e é a única do ciclo comercial que o
-- app ainda não respondia.
--
-- DESENHO: TÍTULO E BAIXA, DUAS COISAS DIFERENTES
--
-- Um `financial_entry` é o TÍTULO: uma promessa de dinheiro com data e
-- valor. Um `financial_payment` é a BAIXA: dinheiro que de fato mudou de
-- mão. São tabelas separadas de propósito, e por três motivos:
--
--   1. baixa PARCIAL existe. Cliente que paga metade não é exceção, é
--      terça-feira. Com um campo `pago boolean` no título, metade não
--      cabe;
--   2. o histórico de recebimento é tão importante quanto o saldo — "ele
--      pagou em três vezes, atrasando" é informação comercial;
--   3. baixa errada se estorna lançando o contrário, como no estoque. O
--      livro nunca é reescrito.
--
-- O `status` do título é DERIVADO da soma das baixas, por gatilho. Ele
-- existe como coluna só para a listagem poder filtrar sem recalcular —
-- nunca é escrito pela aplicação.
--
-- DECISÕES (03/09/2026)
--
--   1. O título nasce ao FATURAR o pedido — a mesma regra do estoque.
--      Nota fiscal, mercadoria e dinheiro andam juntos. Pedido
--      confirmado ou em separação ainda não é dinheiro.
--   2. Baixa parcial é permitida.
--   3. Financeiro é do ADMINISTRADOR. O vendedor enxerga o pedido dele;
--      não enxerga o caixa da empresa nem quanto o colega vendeu.
--
-- PARCELAMENTO
--
-- `orders.payment_terms` é texto livre ("28/56/84 dias"): não dá para
-- deduzir parcelas dali sem adivinhar, e adivinhar errado em dinheiro é
-- pior do que não adivinhar. Então o faturamento cria UM título com
-- vencimento no dia, e a tela parcela em um clique enquanto o título
-- está aberto. Parcelar é um ato de quem fatura, não uma dedução de
-- texto.
-- ============================================================

create type public.financial_kind   as enum ('receivable', 'payable');
create type public.financial_status as enum ('open', 'partial', 'settled', 'cancelled');

-- ── O título ────────────────────────────────────────────────
create table public.financial_entries (
  id             uuid primary key default gen_random_uuid(),

  kind           public.financial_kind not null,
  status         public.financial_status not null default 'open',

  -- De quem se recebe, ou a quem se paga. Exatamente um dos dois, e o
  -- lado tem que combinar com o tipo: não se recebe de fornecedor.
  customer_id    uuid references public.customers(id) on delete restrict,
  supplier_id    uuid references public.suppliers(id) on delete restrict,

  -- De onde nasceu. `set null` nos dois: documento apagado pelo
  -- administrador não pode levar junto o dinheiro que ele gerou.
  order_id       uuid references public.orders(id)    on delete set null,
  purchase_id    uuid references public.purchases(id) on delete set null,

  description    text not null,
  due_date       date not null,
  amount         numeric(14,2) not null check (amount > 0),

  -- Parcela n de N. Título não parcelado é 1 de 1 — assim a tela não
  -- precisa de um caso especial para o que é maioria.
  installment    integer not null default 1 check (installment >= 1),
  installments   integer not null default 1 check (installments >= 1),

  notes          text,
  cancelled_at   timestamptz,

  created_by     uuid references public.profiles(id) on delete set null,
  updated_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint chk_financial_lado check (
    (kind = 'receivable' and customer_id is not null and supplier_id is null) or
    (kind = 'payable'    and supplier_id is not null and customer_id is null)
  ),
  constraint chk_financial_parcela check (installment <= installments)
);

create index idx_financial_status   on public.financial_entries (status, due_date);
create index idx_financial_kind     on public.financial_entries (kind, status, due_date);
create index idx_financial_customer on public.financial_entries (customer_id) where customer_id is not null;
create index idx_financial_supplier on public.financial_entries (supplier_id) where supplier_id is not null;
create index idx_financial_order    on public.financial_entries (order_id)    where order_id    is not null;
create index idx_financial_purchase on public.financial_entries (purchase_id) where purchase_id is not null;

create trigger trg_financial_entries_updated_at before update on public.financial_entries
  for each row execute function public.set_updated_at();

-- ── A baixa ─────────────────────────────────────────────────
-- Append-only, como o livro do estoque. Baixa errada se estorna com uma
-- baixa negativa; nenhuma linha some.
create table public.financial_payments (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.financial_entries(id) on delete cascade,

  -- Positivo recebe/paga; negativo estorna. Nunca zero.
  amount     numeric(14,2) not null check (amount <> 0),
  paid_on    date not null default current_date,
  method     text,
  notes      text,

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index idx_financial_payments_entry on public.financial_payments (entry_id, paid_on);

create or replace function public.block_financial_payment_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Baixa não se altera nem se apaga. Para corrigir, lance um estorno.'
    using errcode = 'restrict_violation';
end;
$$;

revoke execute on function public.block_financial_payment_change() from public, anon;

create trigger trg_financial_payments_immutable
  before update or delete on public.financial_payments
  for each row execute function public.block_financial_payment_change();

-- ── O status é derivado, nunca digitado ─────────────────────
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

  update public.financial_entries
     set status = (case
                     when v_pago <= 0       then 'open'
                     when v_pago >= v_valor then 'settled'
                     else 'partial'
                   end)::public.financial_status
   where id = p_entry_id;
end;
$$;

revoke execute on function public.refresh_financial_status(uuid) from public, anon;

create or replace function public.touch_financial_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_financial_status(coalesce(new.entry_id, old.entry_id));
  return coalesce(new, old);
end;
$$;

revoke execute on function public.touch_financial_status() from public, anon;

create trigger trg_financial_payments_status
  after insert on public.financial_payments
  for each row execute function public.touch_financial_status();

-- ── A posição ───────────────────────────────────────────────
-- Uma linha por título, com o que já foi pago, o que falta e há quantos
-- dias está vencido. `security_invoker`: a RLS de quem consulta vale.
create view public.financial_position
with (security_invoker = true) as
select e.id,
       e.kind,
       e.status,
       e.description,
       e.due_date,
       e.amount,
       e.installment,
       e.installments,
       e.customer_id,
       e.supplier_id,
       e.order_id,
       e.purchase_id,
       e.created_at,
       coalesce(c.name, s.name)                            as party_name,
       o.number                                            as order_number,
       p.number                                            as purchase_number,
       coalesce(pg.pago, 0)::numeric(14,2)                 as paid_amount,
       (e.amount - coalesce(pg.pago, 0))::numeric(14,2)    as open_amount,
       -- Vencido é só o que ainda deve. Título quitado ontem não é
       -- atraso: é história.
       (e.status in ('open', 'partial') and e.due_date < current_date)  as is_overdue,
       case when e.status in ('open', 'partial') and e.due_date < current_date
            then (current_date - e.due_date) else 0 end::integer        as days_overdue
  from public.financial_entries e
  left join public.customers c on c.id = e.customer_id
  left join public.suppliers s on s.id = e.supplier_id
  left join public.orders    o on o.id = e.order_id
  left join public.purchases p on p.id = e.purchase_id
  left join lateral (
    select sum(amount) as pago from public.financial_payments fp where fp.entry_id = e.id
  ) pg on true;

comment on view public.financial_position is
  'Titulo + quanto ja foi pago + quanto falta + atraso. Vencido conta so o que ainda deve.';

-- ── RLS: administrador ──────────────────────────────────────
-- O vendedor enxerga o pedido dele; não enxerga o caixa da empresa nem
-- quanto o colega vendeu. É a mesma linha que separou custo de saldo em
-- 2B e nota de compra de estoque em 2C.
alter table public.financial_entries  enable row level security;
alter table public.financial_payments enable row level security;

create policy financial_entries_admin on public.financial_entries
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy financial_payments_select on public.financial_payments
  for select to authenticated
  using ((select public.is_admin()));

create policy financial_payments_insert on public.financial_payments
  for insert to authenticated
  with check ((select public.is_admin()));

revoke all on public.financial_entries  from anon;
revoke all on public.financial_payments from anon;
grant select, insert, update, delete on public.financial_entries  to authenticated;
grant select, insert                 on public.financial_payments to authenticated;

-- ── O título nasce do pedido faturado ───────────────────────
-- Um título, vencendo no dia do faturamento. Parcelar é o passo
-- seguinte, e é de quem fatura — ver a nota sobre parcelamento no topo.
create or replace function public.write_receivable_from_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'invoiced' or old.status is not distinct from 'invoiced' then
    return new;
  end if;

  -- Cinto de segurança, igual ao do estoque: o pedido não gera o título
  -- duas vezes se voltar a `invoiced` por qualquer caminho.
  if exists (select 1 from public.financial_entries where order_id = new.id) then
    return new;
  end if;

  if new.total <= 0 then
    return new;
  end if;

  insert into public.financial_entries
    (kind, customer_id, order_id, description, due_date, amount, created_by, updated_by)
  values ('receivable', new.customer_id, new.id,
          'Pedido ' || new.number, current_date, new.total, auth.uid(), auth.uid());

  return new;
end;
$$;

revoke execute on function public.write_receivable_from_order() from public, anon;

create trigger trg_orders_write_receivable
  after update of status on public.orders
  for each row execute function public.write_receivable_from_order();

-- ── E do lado de lá: a nota recebida vira conta a pagar ─────
-- O vencimento vem da condição de pagamento da nota, que TEM prazo em
-- dias — ao contrário do pedido, onde a condição é texto livre.
create or replace function public.write_payable_from_purchase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prazo integer;
begin
  if new.status <> 'received' or old.status is not distinct from 'received' then
    return new;
  end if;

  if exists (select 1 from public.financial_entries where purchase_id = new.id) then
    return new;
  end if;

  if new.total <= 0 then
    return new;
  end if;

  select payment_days into v_prazo
    from public.price_conditions where id = new.condition_id;

  insert into public.financial_entries
    (kind, supplier_id, purchase_id, description, due_date, amount, created_by, updated_by)
  values ('payable', new.supplier_id, new.id,
          'Entrada ' || new.number ||
            coalesce(' · NF ' || nullif(new.invoice_number, ''), ''),
          current_date + coalesce(v_prazo, 0),
          new.total, auth.uid(), auth.uid());

  return new;
end;
$$;

revoke execute on function public.write_payable_from_purchase() from public, anon;

create trigger trg_purchases_write_payable
  after update of status on public.purchases
  for each row execute function public.write_payable_from_purchase();

-- ── Parcelar ────────────────────────────────────────────────
-- Troca UM título aberto por N títulos. O original é apagado, e não
-- cancelado: ele nunca foi uma promessa de verdade — foi o lugar onde o
-- valor ficou até alguém dizer como seria pago. Título que já recebeu
-- baixa não se parcela: aí o dinheiro já começou a andar.
create or replace function public.split_financial_entry(
  p_entry_id     uuid,
  p_installments integer,
  p_first_due    date default null,
  p_interval     integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry     public.financial_entries%rowtype;
  v_base      numeric(14,2);
  v_resto     numeric(14,2);
  v_valor     numeric(14,2);
  v_primeira  date;
  i           integer;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador mexe no financeiro'
      using errcode = 'insufficient_privilege';
  end if;

  if p_installments is null or p_installments < 2 or p_installments > 60 then
    raise exception 'O parcelamento vai de 2 a 60 vezes' using errcode = 'check_violation';
  end if;

  select * into v_entry from public.financial_entries where id = p_entry_id for update;
  if not found then
    raise exception 'Título não encontrado' using errcode = 'no_data_found';
  end if;

  if v_entry.status <> 'open' then
    raise exception 'Só título aberto e sem baixa se parcela'
      using errcode = 'check_violation';
  end if;

  if v_entry.installments > 1 then
    raise exception 'Este título já é uma parcela' using errcode = 'check_violation';
  end if;

  v_primeira := coalesce(p_first_due, v_entry.due_date);

  -- A sobra dos centavos vai para a PRIMEIRA parcela, não para a última:
  -- quem paga prefere que a diferença apareça no começo, e a soma das
  -- parcelas fecha exatamente com o total.
  v_base  := trunc(v_entry.amount / p_installments, 2);
  v_resto := v_entry.amount - (v_base * p_installments);

  for i in 1..p_installments loop
    v_valor := v_base + case when i = 1 then v_resto else 0 end;

    insert into public.financial_entries
      (kind, customer_id, supplier_id, order_id, purchase_id, description,
       due_date, amount, installment, installments, notes, created_by, updated_by)
    values (v_entry.kind, v_entry.customer_id, v_entry.supplier_id,
            v_entry.order_id, v_entry.purchase_id, v_entry.description,
            v_primeira + ((i - 1) * coalesce(p_interval, 30)),
            v_valor, i, p_installments, v_entry.notes, auth.uid(), auth.uid());
  end loop;

  delete from public.financial_entries where id = p_entry_id;

  return p_installments;
end;
$$;

revoke execute on function public.split_financial_entry(uuid, integer, date, integer) from public, anon;
grant execute on function public.split_financial_entry(uuid, integer, date, integer) to authenticated;

-- ── Baixar ──────────────────────────────────────────────────
create or replace function public.register_financial_payment(
  p_entry_id uuid,
  p_amount   numeric,
  p_paid_on  date default null,
  p_method   text default null,
  p_notes    text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry public.financial_entries%rowtype;
  v_pago  numeric(14,2);
  v_id    uuid;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador mexe no financeiro'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_entry from public.financial_entries where id = p_entry_id for update;
  if not found then
    raise exception 'Título não encontrado' using errcode = 'no_data_found';
  end if;

  if v_entry.cancelled_at is not null then
    raise exception 'Título cancelado não recebe baixa' using errcode = 'check_violation';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception 'Informe um valor diferente de zero' using errcode = 'check_violation';
  end if;

  select coalesce(sum(amount), 0) into v_pago
    from public.financial_payments where entry_id = p_entry_id;

  -- Pagar mais do que se deve é quase sempre digitação errada. O estorno
  -- (valor negativo) continua livre, e é assim que se conserta.
  if p_amount > 0 and v_pago + p_amount > v_entry.amount then
    raise exception 'A baixa de % passa do que falta (%)',
      p_amount, v_entry.amount - v_pago
      using errcode = 'check_violation';
  end if;

  if p_amount < 0 and v_pago + p_amount < 0 then
    raise exception 'O estorno passa do que já foi baixado' using errcode = 'check_violation';
  end if;

  insert into public.financial_payments (entry_id, amount, paid_on, method, notes, created_by)
  values (p_entry_id, p_amount, coalesce(p_paid_on, current_date),
          nullif(btrim(p_method), ''), nullif(btrim(p_notes), ''), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.register_financial_payment(uuid, numeric, date, text, text) from public, anon;
grant execute on function public.register_financial_payment(uuid, numeric, date, text, text) to authenticated;

-- ── Cancelar título ─────────────────────────────────────────
-- Só sem baixa. Depois que o dinheiro andou, o caminho é o estorno.
create or replace function public.cancel_financial_entry(p_entry_id uuid, p_notes text default null)
returns boolean
language plpgsql
security definer
set search_path = public
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

  update public.financial_entries
     set status = 'cancelled', cancelled_at = now(),
         notes = coalesce(nullif(btrim(p_notes), ''), notes),
         updated_by = auth.uid()
   where id = p_entry_id and cancelled_at is null;

  if not found then
    raise exception 'Título não encontrado ou já cancelado' using errcode = 'no_data_found';
  end if;

  return true;
end;
$$;

revoke execute on function public.cancel_financial_entry(uuid, text) from public, anon;
grant execute on function public.cancel_financial_entry(uuid, text) to authenticated;

comment on table public.financial_entries is
  'Titulo a receber ou a pagar. Status e DERIVADO da soma das baixas, nunca digitado. Somente administrador.';
comment on table public.financial_payments is
  'Baixas. Append-only: baixa errada se estorna com valor negativo, nunca se apaga.';
