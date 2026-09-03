-- ============================================================
-- 0903130000 · Números de série (Onda 2B, segunda metade)
--
-- POR QUE UMA TABELA, E NÃO UM CAMPO
--
-- Um campo de texto no item do pedido responde "qual era a série do que
-- vendi". Não responde a pergunta que o pós-venda faz todo dia: "onde
-- está o drone com esta série, e para quem foi?". Só uma linha por
-- APARELHO responde isso — e é o que a garantia exige quando o cliente
-- liga com o número na mão.
--
-- Nem todo produto merece isso. Drone e pulverizador têm série; parafuso
-- e mangueira não, e pedir série de parafuso é o jeito mais rápido de o
-- estoque parar de ser preenchido. Daí a chave `tracks_serial` no
-- produto: quem controla, controla; o resto anda por quantidade.
--
-- O QUE ESTA MIGRATION NÃO FAZ, DE PROPÓSITO
--
-- Não barra o faturamento por falta de série. É a mesma decisão nº 2 do
-- estoque: avisar, não travar. O pedido fatura, o livro baixa a
-- quantidade, e a ficha do pedido mostra quais aparelhos ainda estão sem
-- série informada. Travar aqui seria parar a venda por causa de um
-- cadastro que quase sempre é feito no galpão, depois.
-- ============================================================

alter table public.products
  add column if not exists tracks_serial boolean not null default false;

comment on column public.products.tracks_serial is
  'Este produto e controlado aparelho a aparelho (drone, pulverizador). Falso = anda so por quantidade.';

-- ── Situação do aparelho ────────────────────────────────────
create type public.serial_status as enum (
  'in_stock',   -- no galpão, disponível
  'sold',       -- saiu com um pedido faturado
  'returned',   -- voltou do cliente e ainda não foi triado
  'defective',  -- com defeito: existe, mas não se vende
  'written_off' -- baixado: perda, sinistro, sucata
);

create table public.product_serials (
  id            uuid primary key default gen_random_uuid(),

  product_id    uuid not null references public.products(id) on delete restrict,
  serial        text not null,
  status        public.serial_status not null default 'in_stock',

  -- Para quem foi, quando saiu. `set null` no pedido, como no livro do
  -- estoque: pedido apagado não pode levar junto a história do aparelho.
  order_id      uuid references public.orders(id)      on delete set null,
  order_item_id uuid references public.order_items(id) on delete set null,
  sold_at       timestamptz,

  notes         text,

  created_by    uuid references public.profiles(id) on delete set null,
  updated_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Aparelho vendido tem que dizer para qual pedido foi. Sem isso a
  -- tabela responde "vendido" e não responde "para quem".
  constraint chk_serial_sold_has_order check (
    status <> 'sold' or order_id is not null
  )
);

-- Série repetida no MESMO produto é digitação em duplicata. Entre
-- produtos diferentes não travamos: fabricantes distintos usam formatos
-- que podem coincidir, e barrar isso rejeitaria cadastro legítimo.
-- `upper()` porque série de drone se lê da etiqueta, e a etiqueta não
-- combina com a caixa de texto sobre maiúscula.
create unique index idx_product_serials_unique
  on public.product_serials (product_id, upper(serial));

create index idx_product_serials_status  on public.product_serials (product_id, status);
create index idx_product_serials_order   on public.product_serials (order_id) where order_id is not null;
create index idx_product_serials_busca   on public.product_serials (upper(serial));

create trigger trg_product_serials_updated_at before update on public.product_serials
  for each row execute function public.set_updated_at();

-- ── Normalização ────────────────────────────────────────────
-- Espaço sobrando e maiúscula inconsistente são o que faz a busca por
-- série falhar justamente no dia da garantia.
create or replace function public.normalize_product_serial()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.serial := upper(btrim(new.serial));
  if new.serial = '' then
    raise exception 'Informe o número de série' using errcode = 'check_violation';
  end if;

  -- Carimba a data da venda quando o aparelho passa a vendido, e limpa
  -- quando volta. A data não é digitada: ela é consequência do status.
  if new.status = 'sold' and (tg_op = 'INSERT' or old.status is distinct from 'sold') then
    new.sold_at := coalesce(new.sold_at, now());
  elsif new.status <> 'sold' then
    new.sold_at := null;
  end if;

  return new;
end;
$$;

revoke execute on function public.normalize_product_serial() from public, anon;

create trigger trg_product_serials_normalize
  before insert or update on public.product_serials
  for each row execute function public.normalize_product_serial();

-- ── RLS ─────────────────────────────────────────────────────
-- Mesmo desenho do livro do estoque: os dois papéis leem — o vendedor
-- precisa dizer ao cliente qual aparelho é o dele —, e só o
-- administrador cadastra e mexe.
alter table public.product_serials enable row level security;

create policy product_serials_select on public.product_serials
  for select to authenticated
  using ((select public.is_active_user()));

create policy product_serials_insert on public.product_serials
  for insert to authenticated
  with check ((select public.is_admin()));

create policy product_serials_update on public.product_serials
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Sem policy de DELETE: aparelho que existiu não some do sistema. O que
-- saiu de circulação vira `written_off`, e continua respondendo "onde
-- foi parar".
revoke all on public.product_serials from anon;
grant select, insert, update on public.product_serials to authenticated;

-- ── O saldo passa a dizer se o produto tem série ────────────
create or replace view public.product_stock
with (security_invoker = true) as
select p.id                                        as product_id,
       p.code,
       p.name,
       p.unit_id,
       p.category_id,
       p.brand_id,
       p.is_active,
       coalesce(sum(m.quantity), 0)::numeric(14,3) as quantity,
       max(m.created_at)                           as last_movement_at,
       p.tracks_serial
  from public.products p
  left join public.stock_movements m on m.product_id = p.id
 where p.deleted_at is null
 group by p.id;

-- ── Vincular o aparelho ao pedido ───────────────────────────
-- Uma função em vez de um `update` solto porque três coisas precisam
-- acontecer juntas: o aparelho tem que estar disponível, tem que ser do
-- produto que o pedido levou, e o pedido tem que estar faturado. Fora da
-- transação, cada uma dessas seria uma checagem de tela — e checagem de
-- tela não impede duas pessoas de vincularem o mesmo aparelho ao mesmo
-- tempo.
create or replace function public.assign_serial_to_order(
  p_serial_id     uuid,
  p_order_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_serial public.product_serials%rowtype;
  v_item   public.order_items%rowtype;
  v_status public.order_status;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode vincular número de série'
      using errcode = 'insufficient_privilege';
  end if;

  -- `for update`: dois usuários na mesma tela não vinculam o mesmo
  -- aparelho a dois pedidos diferentes.
  select * into v_serial from public.product_serials where id = p_serial_id for update;
  if not found then
    raise exception 'Número de série não encontrado' using errcode = 'no_data_found';
  end if;

  if v_serial.status <> 'in_stock' then
    raise exception 'Este aparelho não está disponível (situação: %)', v_serial.status
      using errcode = 'check_violation';
  end if;

  select * into v_item from public.order_items where id = p_order_item_id;
  if not found then
    raise exception 'Item do pedido não encontrado' using errcode = 'no_data_found';
  end if;

  if v_item.product_id is distinct from v_serial.product_id then
    raise exception 'Este aparelho não é do produto vendido neste item'
      using errcode = 'check_violation';
  end if;

  select status into v_status from public.orders where id = v_item.order_id;
  if v_status not in ('invoiced', 'delivered') then
    raise exception 'O aparelho se vincula ao faturar. Situação atual do pedido: %', v_status
      using errcode = 'check_violation';
  end if;

  update public.product_serials
     set status        = 'sold',
         order_id      = v_item.order_id,
         order_item_id = v_item.id,
         updated_by    = auth.uid()
   where id = p_serial_id;

  return true;
end;
$$;

revoke execute on function public.assign_serial_to_order(uuid, uuid) from public, anon;
grant execute on function public.assign_serial_to_order(uuid, uuid) to authenticated;

-- ── Desvincular ─────────────────────────────────────────────
-- Errar o aparelho na hora da entrega acontece. Desfazer devolve o
-- aparelho ao galpão e apaga o vínculo — mas o pedido continua faturado
-- e o livro do estoque continua intacto: são coisas diferentes.
create or replace function public.release_serial(p_serial_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode desvincular número de série'
      using errcode = 'insufficient_privilege';
  end if;

  update public.product_serials
     set status        = 'in_stock',
         order_id      = null,
         order_item_id = null,
         updated_by    = auth.uid()
   where id = p_serial_id and status = 'sold';

  if not found then
    raise exception 'Este aparelho não está vinculado a um pedido'
      using errcode = 'no_data_found';
  end if;

  return true;
end;
$$;

revoke execute on function public.release_serial(uuid) from public, anon;
grant execute on function public.release_serial(uuid) to authenticated;

comment on table public.product_serials is
  'Um aparelho por linha, para produtos com tracks_serial. Responde onde esta e para quem foi. Nao se apaga: sai de circulacao como written_off.';
