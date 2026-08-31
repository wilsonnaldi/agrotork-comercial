-- ============================================================
-- 0600 · Orçamentos (módulo principal)
-- ============================================================

-- ── Numeração sequencial por ano: ORC-2026-0001 ──────────────
create table public.quote_sequences (
  year        integer primary key,
  last_number integer not null default 0
);

create or replace function public.next_quote_number(p_year integer default null)
returns table (seq_year integer, seq_number integer, formatted text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year integer := coalesce(p_year, extract(year from current_date)::int);
  v_num  integer;
begin
  insert into public.quote_sequences (year, last_number)
  values (v_year, 1)
  on conflict (year) do update set last_number = public.quote_sequences.last_number + 1
  returning last_number into v_num;

  return query select v_year, v_num, 'ORC-' || v_year || '-' || lpad(v_num::text, 4, '0');
end;
$$;

-- ── Orçamentos ───────────────────────────────────────────────
create table public.quotes (
  id                uuid primary key default gen_random_uuid(),
  number            text not null,
  sequence_year     integer not null,
  sequence_number   integer not null,

  customer_id       uuid not null references public.customers(id) on delete restrict,
  owner_id          uuid not null references public.profiles(id)  on delete restrict,
  status            public.quote_status not null default 'draft',

  issue_date        date not null default current_date,
  valid_until       date,
  payment_terms     text,

  discount_percent  numeric(7,4)  not null default 0 check (discount_percent >= 0 and discount_percent <= 100),
  discount_amount   numeric(14,2) not null default 0 check (discount_amount >= 0),
  shipping_amount   numeric(14,2) not null default 0 check (shipping_amount >= 0),
  subtotal          numeric(14,2) not null default 0,
  total             numeric(14,2) not null default 0,

  notes             text,
  internal_notes    text,   -- nunca sai no PDF

  sent_at           timestamptz,
  approved_at       timestamptz,
  rejected_at       timestamptz,

  created_by        uuid references public.profiles(id) on delete set null,
  updated_by        uuid references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create unique index idx_quotes_number on public.quotes (number);
create index idx_quotes_customer   on public.quotes (customer_id) where deleted_at is null;
create index idx_quotes_owner      on public.quotes (owner_id)    where deleted_at is null;
create index idx_quotes_status     on public.quotes (status)      where deleted_at is null;
create index idx_quotes_issue_date on public.quotes (issue_date desc);

create trigger trg_quotes_updated_at before update on public.quotes
  for each row execute function public.set_updated_at();

-- Preenche número/ano/sequência automaticamente na criação.
create or replace function public.assign_quote_number()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.number is null or new.number = '' then
    select * into r from public.next_quote_number(extract(year from coalesce(new.issue_date, current_date))::int);
    new.number          := r.formatted;
    new.sequence_year   := r.seq_year;
    new.sequence_number := r.seq_number;
  end if;
  return new;
end;
$$;

create trigger trg_quotes_assign_number
  before insert on public.quotes
  for each row execute function public.assign_quote_number();

-- ── Itens do orçamento — PREÇOS CONGELADOS ───────────────────
-- Cada item guarda uma cópia dos dados do produto/kit no momento
-- do orçamento. Se o preço mudar depois, este orçamento NÃO muda.
create table public.quote_items (
  id                    uuid primary key default gen_random_uuid(),
  quote_id              uuid not null references public.quotes(id) on delete cascade,
  kind                  public.item_kind not null default 'product',

  -- Referências históricas (podem ficar nulas se o cadastro sumir)
  product_id            uuid references public.products(id) on delete set null,
  kit_id                uuid references public.kits(id)     on delete set null,

  -- Cópias congeladas
  code_snapshot         text,
  name_snapshot         text not null,
  description_snapshot  text,
  unit_snapshot         text,
  brand_snapshot        text,
  image_url_snapshot    text,
  components_snapshot   jsonb,      -- composição do kit na data

  quantity              numeric(14,3) not null default 1 check (quantity > 0),
  unit_price            numeric(14,2) not null default 0 check (unit_price >= 0),
  unit_cost_snapshot    numeric(14,2),
  discount_percent      numeric(7,4) not null default 0 check (discount_percent >= 0 and discount_percent <= 100),

  line_total            numeric(14,2) generated always as (
    round(quantity * unit_price * (1 - discount_percent / 100), 2)
  ) stored,

  sort_order            integer not null default 0,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint chk_quote_item_reference check (
    (kind = 'product' and product_id is not null) or
    (kind = 'kit'     and kit_id     is not null) or
    (kind = 'custom')
  )
);

create index idx_quote_items_quote on public.quote_items (quote_id, sort_order);
create trigger trg_quote_items_updated_at before update on public.quote_items
  for each row execute function public.set_updated_at();

-- ── Totais recalculados no banco (o front nunca decide o total) ──
create or replace function public.recalculate_quote_totals(p_quote_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_subtotal numeric(14,2);
  v_quote    public.quotes%rowtype;
begin
  select * into v_quote from public.quotes where id = p_quote_id;
  if not found then return; end if;

  select coalesce(sum(line_total), 0) into v_subtotal
  from public.quote_items where quote_id = p_quote_id;

  update public.quotes
     set subtotal = v_subtotal,
         total = greatest(
           round(
             v_subtotal
             - round(v_subtotal * v_quote.discount_percent / 100, 2)
             - v_quote.discount_amount
             + v_quote.shipping_amount
           , 2), 0)
   where id = p_quote_id;
end;
$$;

create or replace function public.trg_recalc_from_item()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recalculate_quote_totals(coalesce(new.quote_id, old.quote_id));
  return coalesce(new, old);
end;
$$;

create trigger trg_quote_items_recalc
  after insert or update or delete on public.quote_items
  for each row execute function public.trg_recalc_from_item();

create or replace function public.trg_recalc_from_quote()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.discount_percent is distinct from old.discount_percent
     or new.discount_amount is distinct from old.discount_amount
     or new.shipping_amount is distinct from old.shipping_amount then
    perform public.recalculate_quote_totals(new.id);
  end if;
  return new;
end;
$$;

create trigger trg_quotes_recalc
  after update on public.quotes
  for each row execute function public.trg_recalc_from_quote();

-- Marca automaticamente as datas de mudança de status.
create or replace function public.stamp_quote_status()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'sent'     and new.sent_at     is null then new.sent_at     := now(); end if;
    if new.status = 'approved' and new.approved_at is null then new.approved_at := now(); end if;
    if new.status = 'rejected' and new.rejected_at is null then new.rejected_at := now(); end if;
  end if;
  return new;
end;
$$;

create trigger trg_quotes_stamp_status
  before update on public.quotes
  for each row execute function public.stamp_quote_status();

-- Expiração (será agendada via cron do Supabase na Fase 6).
create or replace function public.expire_quotes()
returns integer language sql security definer set search_path = public as $$
  with updated as (
    update public.quotes
       set status = 'expired'
     where status = 'sent'
       and valid_until is not null
       and valid_until < current_date
       and deleted_at is null
    returning 1
  )
  select count(*)::int from updated;
$$;

-- Ajuda o dashboard e a listagem sem N+1.
create view public.quotes_list
with (security_invoker = true) as
select q.id, q.number, q.status, q.issue_date, q.valid_until,
       q.subtotal, q.total, q.created_at, q.updated_at,
       q.customer_id, c.name as customer_name, c.city as customer_city,
       q.owner_id, pr.full_name as owner_name,
       (select count(*) from public.quote_items qi where qi.quote_id = q.id)::int as items_count
from public.quotes q
join public.customers c on c.id = q.customer_id
join public.profiles pr on pr.id = q.owner_id
where q.deleted_at is null;
