-- ============================================================
-- 0903060000 · Pedido de venda (Onda 1)
--
-- O orçamento negocia; o pedido registra o negócio fechado. São dois
-- documentos, não três: a "venda" é o pedido chegando ao fim, e o
-- "pedido" informal do cliente já é o rascunho do orçamento.
--
-- A conversão vale nos dois sentidos, e são coisas diferentes:
--
--   orçamento --aprovado--> PEDIDO        (fechar: copia e congela)
--   pedido    --renegociar-> ORÇAMENTO v2 (reabrir: nasce documento novo)
--
-- Reabrir NÃO edita o pedido. Gera um orçamento novo a partir dele; se
-- esse orçamento fechar de novo, nasce outro pedido, e a corrente
-- pedido → orçamento → pedido é o histórico da renegociação.
--
-- O que congela no pedido é o CONTEÚDO COMERCIAL — itens, quantidades,
-- preços, descontos, totais. O que continua se movendo é a SITUAÇÃO
-- (confirmado → em separação → faturado → entregue) e o operacional
-- (observações, previsão de entrega). Congelar tudo tornaria impossível
-- marcar um pedido como entregue.
--
-- Estrutura espelhada em `quotes`/`quote_items` de propósito: mesma
-- numeração por ano, mesmos snapshots, mesmo `line_total` gerado, mesmo
-- recálculo no banco. Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── Situações do pedido ─────────────────────────────────────
-- `create type` (e não `alter type ... add value`) porque o enum nasce
-- aqui: pode ser usado livremente na mesma transação.
create type public.order_status as enum (
  'confirmed',   -- fechado, aguardando separação
  'picking',     -- em separação
  'invoiced',    -- faturado
  'delivered',   -- entregue
  'cancelled'    -- cancelado antes do faturamento
);

comment on type public.order_status is
  'Situação do pedido. Depois de faturado não há cancelamento: o caminho é devolução, que é assunto da onda fiscal.';

-- ── Numeração sequencial por ano: PED-2026-0001 ─────────────
-- Sequência PRÓPRIA, separada do orçamento de propósito: o número do
-- pedido é o que o cliente e a nota fiscal citam, e não pode andar
-- quando alguém cria um orçamento.
create table public.order_sequences (
  year        integer primary key,
  last_number integer not null default 0
);

create or replace function public.next_order_number(p_year integer default null)
returns table (seq_year integer, seq_number integer, formatted text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year integer := coalesce(p_year, extract(year from current_date)::int);
  v_num  integer;
begin
  insert into public.order_sequences (year, last_number)
  values (v_year, 1)
  on conflict (year) do update set last_number = public.order_sequences.last_number + 1
  returning last_number into v_num;

  return query select v_year, v_num, 'PED-' || v_year || '-' || lpad(v_num::text, 4, '0');
end;
$$;

-- ── Pedidos ─────────────────────────────────────────────────
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  number            text not null,
  sequence_year     integer not null,
  sequence_number   integer not null,

  customer_id       uuid not null references public.customers(id) on delete restrict,
  owner_id          uuid not null references public.profiles(id)  on delete restrict,
  status            public.order_status not null default 'confirmed',

  -- De onde veio. `set null` porque um orçamento pode ser apagado pelo
  -- administrador e o pedido NÃO pode desaparecer junto: ele é o
  -- documento do negócio fechado.
  quote_id          uuid references public.quotes(id) on delete set null,

  -- Corrente de renegociação: este pedido substitui aquele.
  supersedes_order_id uuid references public.orders(id) on delete set null,

  issue_date        date not null default current_date,
  delivery_forecast date,
  payment_terms     text,
  delivery_terms    text,

  discount_percent  numeric(7,4)  not null default 0 check (discount_percent >= 0 and discount_percent <= 100),
  discount_amount   numeric(14,2) not null default 0 check (discount_amount >= 0),
  shipping_amount   numeric(14,2) not null default 0 check (shipping_amount >= 0),
  subtotal          numeric(14,2) not null default 0 check (subtotal >= 0),
  total             numeric(14,2) not null default 0 check (total    >= 0),

  notes             text,
  internal_notes    text,   -- nunca sai em documento do cliente

  confirmed_at      timestamptz not null default now(),
  picking_at        timestamptz,
  invoiced_at       timestamptz,
  delivered_at      timestamptz,
  cancelled_at      timestamptz,

  created_by        uuid references public.profiles(id) on delete set null,
  updated_by        uuid references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,

  constraint chk_orders_not_self_superseding check (supersedes_order_id is distinct from id)
);

create unique index idx_orders_number      on public.orders (number);
create index idx_orders_customer   on public.orders (customer_id) where deleted_at is null;
create index idx_orders_owner      on public.orders (owner_id)    where deleted_at is null;
create index idx_orders_status     on public.orders (status)      where deleted_at is null;
create index idx_orders_issue_date on public.orders (issue_date desc);
create index idx_orders_quote      on public.orders (quote_id)    where quote_id is not null;
-- A tela do vendedor é sempre "meus pedidos, mais recentes primeiro".
create index idx_orders_owner_issue on public.orders (owner_id, issue_date desc) where deleted_at is null;

create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

comment on column public.orders.delivery_forecast is
  'Previsão de entrega. Operacional: muda com o pedido já fechado, ao contrário de preço e itens.';
comment on column public.orders.supersedes_order_id is
  'Pedido que este substitui, quando nasceu de uma renegociação. A corrente conta quantas vezes o negócio foi refeito.';

-- ── O caminho de volta, registrado no orçamento ─────────────
-- Três colunas aditivas em `quotes`. Nenhuma é obrigatória e nenhuma
-- muda o comportamento do que já existe: orçamento criado do jeito
-- antigo continua sendo revisão 1, sem origem e sem antecessor.
alter table public.quotes
  add column if not exists origin_order_id     uuid references public.orders(id) on delete set null,
  add column if not exists supersedes_quote_id uuid references public.quotes(id) on delete set null,
  add column if not exists revision            integer not null default 1 check (revision > 0);

create index if not exists idx_quotes_origin_order on public.quotes (origin_order_id)
  where origin_order_id is not null;

comment on column public.quotes.origin_order_id is
  'Pedido que originou esta renegociacao. Nulo no orcamento que nasce do zero.';
comment on column public.quotes.revision is
  'Quantas vezes o negocio foi refeito. v1 e o original; cada renegociacao soma 1 — e o "foi editado tantas vezes" da tela.';

-- ── Itens do pedido — CÓPIA CONGELADA ───────────────────────
-- Mesmo padrão de `quote_items`: cada linha guarda a fotografia do
-- produto/kit no momento do fechamento. Mudar o catálogo depois não
-- altera pedido nenhum.
create table public.order_items (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null references public.orders(id) on delete cascade,
  kind                  public.item_kind not null default 'product',

  product_id            uuid references public.products(id) on delete set null,
  kit_id                uuid references public.kits(id)     on delete set null,

  code_snapshot         text,
  name_snapshot         text not null,
  description_snapshot  text,
  unit_snapshot         text,
  brand_snapshot        text,
  image_url_snapshot    text,
  components_snapshot   jsonb,

  quantity              numeric(14,3) not null default 1 check (quantity > 0),
  unit_price            numeric(14,2) not null default 0 check (unit_price >= 0),
  discount_percent      numeric(7,4) not null default 0 check (discount_percent >= 0 and discount_percent <= 100),

  line_total            numeric(14,2) generated always as (
    round(quantity * unit_price * (1 - discount_percent / 100), 2)
  ) stored,

  sort_order            integer not null default 0,
  notes                 text,
  created_at            timestamptz not null default now(),

  constraint chk_order_item_reference check (
    (kind = 'product' and product_id is not null) or
    (kind = 'kit'     and kit_id     is not null) or
    (kind = 'custom')
  )
);

create index idx_order_items_order on public.order_items (order_id, sort_order);

-- `unit_cost_snapshot` NÃO existe aqui, pelo mesmo motivo documentado na
-- migration 1700: `order_items` é legível pelo dono do pedido, e o
-- PostgreSQL não filtra coluna por papel de aplicação. Custo histórico
-- para relatório de margem é decisão da fase de relatórios.

-- ── Totais calculados pelo banco ────────────────────────────
create or replace function public.recalculate_order_totals(p_order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_subtotal numeric(14,2);
  v_order    public.orders%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then return; end if;

  select coalesce(sum(line_total), 0) into v_subtotal
  from public.order_items where order_id = p_order_id;

  -- Abre a trava do congelamento SÓ para esta escrita e SÓ dentro desta
  -- transação (o terceiro argumento `true` é o que a limita). É a única
  -- porta por onde subtotal e total podem ser escritos, e ela não fica
  -- aberta: fecha logo abaixo, ainda dentro da função.
  perform pg_catalog.set_config('agrotork.recalculando_pedido', 'on', true);

  update public.orders
     set subtotal = v_subtotal,
         total = greatest(
           round(
             v_subtotal
             - round(v_subtotal * v_order.discount_percent / 100, 2)
             - v_order.discount_amount
             + v_order.shipping_amount
           , 2), 0)
   where id = p_order_id;

  perform pg_catalog.set_config('agrotork.recalculando_pedido', 'off', true);
end;
$$;

-- ── A trava: o conteúdo comercial não muda, nunca ───────────
-- O pedido nasce fechado. Não existe "rascunho de pedido" — para isso
-- serve o orçamento. Então a trava não olha o status: vale desde o
-- primeiro instante, para o vendedor E para o administrador.
--
-- O caminho para mudar o que foi vendido é renegociar: gerar orçamento
-- novo a partir deste pedido e fechar outro pedido.
create or replace function public.freeze_order_commercials()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  -- A única exceção: a escrita dos totais feita por
  -- recalculate_order_totals(), que abre esta marca e a fecha em
  -- seguida, dentro da mesma transação. `pg_trigger_depth()` NÃO serve
  -- aqui — o recálculo é chamado direto pela função de criação, não a
  -- partir de outro gatilho, então a profundidade é 1 igual à de uma
  -- tentativa vinda da API.
  if coalesce(pg_catalog.current_setting('agrotork.recalculando_pedido', true), 'off') = 'on' then
    return new;
  end if;

  if new.customer_id       is distinct from old.customer_id
     or new.quote_id          is distinct from old.quote_id
     or new.number            is distinct from old.number
     or new.sequence_year     is distinct from old.sequence_year
     or new.sequence_number   is distinct from old.sequence_number
     or new.discount_percent  is distinct from old.discount_percent
     or new.discount_amount   is distinct from old.discount_amount
     or new.shipping_amount   is distinct from old.shipping_amount
     or new.subtotal          is distinct from old.subtotal
     or new.total             is distinct from old.total
     or new.issue_date        is distinct from old.issue_date
  then
    raise exception 'Pedido fechado nao muda de conteudo comercial. Para alterar o que foi vendido, renegocie: gere um orcamento a partir deste pedido.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger trg_orders_freeze
  before update on public.orders
  for each row execute function public.freeze_order_commercials();

-- ── Situações: só as transições que existem no mundo real ───
create or replace function public.validate_order_status_transition()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_old text := old.status::text;
  v_new text := new.status::text;
begin
  if v_new = v_old then return new; end if;

  if not (
       (v_old = 'confirmed' and v_new in ('picking', 'invoiced', 'cancelled'))
    or (v_old = 'picking'   and v_new in ('invoiced', 'cancelled'))
    or (v_old = 'invoiced'  and v_new in ('delivered'))
  ) then
    raise exception 'Transicao de situacao invalida no pedido: % -> %', v_old, v_new
      using errcode = 'check_violation';
  end if;

  -- Carimba a data da situação nova, uma vez só.
  if v_new = 'picking'   and new.picking_at   is null then new.picking_at   := now(); end if;
  if v_new = 'invoiced'  and new.invoiced_at  is null then new.invoiced_at  := now(); end if;
  if v_new = 'delivered' and new.delivered_at is null then new.delivered_at := now(); end if;
  if v_new = 'cancelled' and new.cancelled_at is null then new.cancelled_at := now(); end if;

  return new;
end;
$$;

create trigger trg_orders_status
  before update on public.orders
  for each row execute function public.validate_order_status_transition();

-- ── Quem é dono do pedido (espelha owns_quote) ──────────────
create or replace function public.owns_order(p_order_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.orders o
     where o.id = p_order_id
       and o.deleted_at is null
       and o.owner_id = (select auth.uid())
  );
$$;

-- ============================================================
-- Conversões
-- ============================================================

-- ── Orçamento aprovado vira pedido ──────────────────────────
-- `security definer` porque escreve em `order_items`, onde NENHUM papel
-- de aplicação tem INSERT — é o que garante que a composição do pedido
-- só nasce por este caminho, com a cópia integral do orçamento.
create or replace function public.create_order_from_quote(p_quote_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_quote public.quotes%rowtype;
  v_order_id uuid;
  r record;
begin
  select * into v_quote from public.quotes
   where id = p_quote_id and deleted_at is null;
  if not found then
    raise exception 'Orcamento nao encontrado';
  end if;

  -- A autorização é a mesma da leitura do orçamento: administrador, ou
  -- o vendedor dono. Sem isto, o `security definer` viraria porta aberta.
  if not (public.is_admin() or v_quote.owner_id = (select auth.uid())) then
    raise exception 'Sem permissao para faturar este orcamento';
  end if;

  if v_quote.status::text <> 'approved' then
    raise exception 'So orcamento aprovado vira pedido. Situacao atual: %', v_quote.status::text;
  end if;

  if exists (select 1 from public.orders o
              where o.quote_id = p_quote_id and o.deleted_at is null
                and o.status::text <> 'cancelled') then
    raise exception 'Este orcamento ja gerou pedido';
  end if;

  insert into public.orders (
    number, sequence_year, sequence_number,
    customer_id, owner_id, quote_id,
    issue_date, payment_terms, delivery_terms,
    discount_percent, discount_amount, shipping_amount,
    notes, internal_notes, created_by, updated_by
  )
  select n.formatted, n.seq_year, n.seq_number,
         v_quote.customer_id, v_quote.owner_id, v_quote.id,
         current_date, v_quote.payment_terms, v_quote.delivery_terms,
         v_quote.discount_percent, v_quote.discount_amount, v_quote.shipping_amount,
         v_quote.notes, v_quote.internal_notes,
         (select auth.uid()), (select auth.uid())
    from public.next_order_number(extract(year from current_date)::int) n
  returning id into v_order_id;

  for r in
    select * from public.quote_items where quote_id = p_quote_id order by sort_order, id
  loop
    insert into public.order_items (
      order_id, kind, product_id, kit_id,
      code_snapshot, name_snapshot, description_snapshot, unit_snapshot,
      brand_snapshot, image_url_snapshot, components_snapshot,
      quantity, unit_price, discount_percent, sort_order, notes
    ) values (
      v_order_id, r.kind, r.product_id, r.kit_id,
      r.code_snapshot, r.name_snapshot, r.description_snapshot, r.unit_snapshot,
      r.brand_snapshot, r.image_url_snapshot, r.components_snapshot,
      r.quantity, r.unit_price, r.discount_percent, r.sort_order, r.notes
    );
  end loop;

  perform public.recalculate_order_totals(v_order_id);
  return v_order_id;
end;
$$;

-- ── Pedido vira orçamento novo (renegociação) ───────────────
-- O caminho de volta. NÃO altera o pedido: cria um orçamento em
-- rascunho com a mesma composição, ligado à origem. Quem cancela o
-- pedido antigo é uma decisão de quem está renegociando, não desta
-- função — pode ser que a renegociação não vingue.
create or replace function public.create_quote_from_order(p_order_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders%rowtype;
  v_quote_id uuid;
  r record;
begin
  select * into v_order from public.orders
   where id = p_order_id and deleted_at is null;
  if not found then
    raise exception 'Pedido nao encontrado';
  end if;

  if not (public.is_admin() or v_order.owner_id = (select auth.uid())) then
    raise exception 'Sem permissao para renegociar este pedido';
  end if;

  insert into public.quotes (
    customer_id, owner_id, status, issue_date,
    payment_terms, delivery_terms,
    discount_percent, discount_amount, shipping_amount,
    notes, internal_notes, origin_order_id, revision, supersedes_quote_id,
    created_by, updated_by
  )
  values (
    v_order.customer_id, v_order.owner_id, 'draft', current_date,
    v_order.payment_terms, v_order.delivery_terms,
    v_order.discount_percent, v_order.discount_amount, v_order.shipping_amount,
    v_order.notes, v_order.internal_notes, v_order.id,
    coalesce((select q.revision + 1 from public.quotes q where q.id = v_order.quote_id), 1),
    v_order.quote_id,
    (select auth.uid()), (select auth.uid())
  )
  returning id into v_quote_id;

  for r in
    select * from public.order_items where order_id = p_order_id order by sort_order, id
  loop
    insert into public.quote_items (
      quote_id, kind, product_id, kit_id,
      code_snapshot, name_snapshot, description_snapshot, unit_snapshot,
      brand_snapshot, image_url_snapshot, components_snapshot,
      quantity, unit_price, discount_percent, sort_order, notes
    ) values (
      v_quote_id, r.kind, r.product_id, r.kit_id,
      r.code_snapshot, r.name_snapshot, r.description_snapshot, r.unit_snapshot,
      r.brand_snapshot, r.image_url_snapshot, r.components_snapshot,
      r.quantity, r.unit_price, r.discount_percent, r.sort_order, r.notes
    );
  end loop;

  return v_quote_id;
end;
$$;

-- ── Listagem sem N+1, espelhando quotes_list ────────────────
create view public.orders_list
with (security_invoker = true) as
select o.id, o.number, o.status, o.issue_date, o.delivery_forecast,
       o.subtotal, o.total, o.created_at, o.updated_at,
       o.customer_id, c.name as customer_name, c.city as customer_city,
       o.owner_id, pr.full_name as owner_name,
       o.quote_id, q.number as quote_number,
       (select count(*) from public.order_items oi where oi.order_id = o.id)::int as items_count
from public.orders o
join public.customers c on c.id = o.customer_id
join public.profiles pr on pr.id = o.owner_id
left join public.quotes q on q.id = o.quote_id
where o.deleted_at is null;

-- ============================================================
-- RLS — quem barra é o banco
-- ============================================================
alter table public.orders          enable row level security;
alter table public.order_items     enable row level security;
alter table public.order_sequences enable row level security;

-- Pedido: vendedor enxerga o próprio, administrador enxerga tudo.
create policy orders_select on public.orders
  for select to authenticated
  using (
    (select public.is_active_user())
    and deleted_at is null
    and ((select public.is_admin()) or owner_id = (select auth.uid()))
  );

-- Sem policy de INSERT: pedido nasce SÓ por create_order_from_quote().
-- É o que impede um pedido "solto", sem orçamento aprovado por trás.

-- UPDATE existe para mover a situação e o operacional. Que colunas
-- podem mudar é decidido pelo trigger de congelamento, não aqui.
create policy orders_update on public.orders
  for update to authenticated
  using (
    (select public.is_active_user())
    and deleted_at is null
    and ((select public.is_admin()) or owner_id = (select auth.uid()))
  )
  with check (
    (select public.is_active_user())
    and ((select public.is_admin()) or owner_id = (select auth.uid()))
  );

create policy orders_delete_admin on public.orders
  for delete to authenticated
  using ((select public.is_admin()));

comment on policy orders_update on public.orders is
  'Move situacao e campos operacionais. O conteudo comercial e barrado pelo trigger trg_orders_freeze, para vendedor e administrador.';

-- Itens: leitura acompanha o pedido. Nenhum papel escreve — nem
-- administrador. A composição nasce com o pedido e não muda.
create policy order_items_select on public.order_items
  for select to authenticated
  using ((select public.is_admin()) or public.owns_order(order_id));

-- `order_sequences` sem policy alguma: ninguém lê nem escreve pela API.
-- Quem mexe é next_order_number(), que é security definer.

-- ============================================================
-- Privilégios — o default do Supabase concede; aqui tira
-- ============================================================
revoke all on public.orders          from anon;
revoke all on public.order_items     from anon;
revoke all on public.order_sequences from anon;
revoke all on public.orders_list     from anon;

grant select, update, delete on public.orders      to authenticated;
grant select                 on public.order_items to authenticated;
grant select                 on public.orders_list to authenticated;

revoke execute on function public.next_order_number(integer)        from public, anon;
revoke execute on function public.recalculate_order_totals(uuid)    from public, anon;
revoke execute on function public.freeze_order_commercials()        from public, anon;
revoke execute on function public.validate_order_status_transition() from public, anon;
revoke execute on function public.owns_order(uuid)                  from public, anon;
revoke execute on function public.create_order_from_quote(uuid)     from public, anon;
revoke execute on function public.create_quote_from_order(uuid)     from public, anon;

grant execute on function public.owns_order(uuid)              to authenticated, service_role;
grant execute on function public.create_order_from_quote(uuid) to authenticated, service_role;
grant execute on function public.create_quote_from_order(uuid) to authenticated, service_role;
grant execute on function public.next_order_number(integer)    to service_role;
grant execute on function public.recalculate_order_totals(uuid) to service_role;
