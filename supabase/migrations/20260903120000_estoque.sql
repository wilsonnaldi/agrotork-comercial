-- ============================================================
-- 0903120000 · Estoque (Onda 2B) — o livro-caixa da mercadoria
--
-- DESENHO: LIVRO, NÃO PLACAR
--
-- A tentação é guardar um número em `products.stock` e somar e subtrair
-- nele. Não fazemos isso. Um número que se sobrescreve não responde à
-- única pergunta que importa quando o saldo está errado: "por que está
-- errado?". Aqui cada entrada e cada saída viram uma LINHA, para sempre,
-- e o saldo é a soma delas. É o mesmo desenho de `audit_log`.
--
-- Consequências, todas deliberadas:
--   · o saldo nunca é digitado — é calculado;
--   · corrigir não é apagar: é lançar o ajuste contrário, e os dois
--     lançamentos continuam à vista;
--   · a linha não muda e não some, nem para o administrador (gatilho
--     `trg_stock_movements_immutable`).
--
-- SINAL NA QUANTIDADE
--
-- `quantity` positivo entra, negativo sai. Um livro com uma coluna só
-- torna o saldo um `sum()` e elimina a classe de bug em que alguém soma
-- o que devia subtrair. O motivo (`reason`) diz o que foi, e é ele que a
-- tela mostra — não o sinal.
--
-- DECISÕES COMERCIAIS (do Wilson, 03/09)
--
--   1. A baixa acontece ao FATURAR, não ao entregar. Estoque e nota
--      fiscal andam juntos; é o que o contador espera.
--   2. Sem saldo o sistema AVISA e deixa passar. Enquanto a contagem
--      inicial não estiver feita, barrar o faturamento pararia a
--      empresa. Saldo negativo vira a lista do que falta acertar — e a
--      tela de estoque mostra essa lista primeiro.
-- ============================================================

-- ── Motivos ─────────────────────────────────────────────────
-- Vocabulário fechado de propósito: "motivo" digitado à mão vira relatório
-- impossível de somar. O que falta aqui entra por migration, não por tela.
create type public.stock_reason as enum (
  'initial',     -- contagem inicial: o saldo que já existia no galpão
  'purchase',    -- entrada de mercadoria (a Onda 2C lança por aqui)
  'sale',        -- saída pelo faturamento do pedido — só o gatilho escreve
  'return_in',   -- cliente devolveu: volta para o estoque
  'return_out',  -- devolvemos ao fornecedor
  'adjustment',  -- acerto de contagem, para mais ou para menos
  'loss'         -- perda, quebra, furto
);

-- ── O livro ─────────────────────────────────────────────────
create table public.stock_movements (
  id            uuid primary key default gen_random_uuid(),

  -- `restrict`: produto com movimento não se apaga. O histórico do
  -- estoque não pode ficar apontando para o vazio.
  product_id    uuid not null references public.products(id) on delete restrict,
  reason        public.stock_reason not null,

  -- Positivo entra, negativo sai. Nunca zero: lançamento que não move
  -- nada é ruído no livro.
  quantity      numeric(14,3) not null check (quantity <> 0),

  -- De onde veio o lançamento. `set null` no pedido: pedido apagado pelo
  -- administrador não pode levar junto a linha do estoque.
  order_id      uuid references public.orders(id)      on delete set null,
  order_item_id uuid references public.order_items(id) on delete set null,

  notes         text,

  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
  -- Sem `updated_at` e sem `deleted_at`, de propósito: a linha não muda
  -- e não some. Ver o gatilho de imutabilidade logo abaixo.
);

create index idx_stock_movements_product on public.stock_movements (product_id, created_at desc);
create index idx_stock_movements_order   on public.stock_movements (order_id) where order_id is not null;
create index idx_stock_movements_reason  on public.stock_movements (reason, created_at desc);

comment on table public.stock_movements is
  'Livro append-only do estoque. Saldo = soma de quantity. Positivo entra, negativo sai. Linha nao muda e nao some.';

-- ── O custo do lançamento mora À PARTE ──────────────────────
-- Tabela irmã, e não uma coluna no livro, pelo mesmo motivo da migration
-- 1200: o custo saiu de `products` porque o PostgreSQL não filtra COLUNA
-- por papel de aplicação. Se `unit_cost` ficasse no livro, o vendedor —
-- que PRECISA ler o saldo — leria junto quanto a empresa paga em cada
-- peça. O desenho de `product_costs` já resolvia isso; aqui ele é
-- repetido de propósito.
--
-- Guardado no lançamento, e não lido de `product_costs` na hora do
-- relatório, porque o custo do catálogo muda: o valor do que saiu em
-- março não pode ser recalculado com o custo de setembro.
create table public.stock_movement_costs (
  movement_id uuid primary key references public.stock_movements(id) on delete cascade,
  unit_cost   numeric(14,2) not null default 0 check (unit_cost >= 0),
  created_at  timestamptz not null default now()
);

alter table public.stock_movement_costs enable row level security;

create policy stock_movement_costs_admin on public.stock_movement_costs
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

revoke all on public.stock_movement_costs from anon;
grant select, insert on public.stock_movement_costs to authenticated;

comment on table public.stock_movement_costs is
  'Custo unitario congelado de cada lancamento. Tabela separada porque o vendedor le o livro e NAO pode ler custo.';

-- ── Imutabilidade ───────────────────────────────────────────
-- A RLS já não tem policy de update nem de delete, o que basta para
-- `authenticated`. Este gatilho vale para TODO MUNDO — inclusive para
-- quem entrar pelo painel do Supabase com a chave de serviço. Um livro
-- que o dono pode reescrever não é livro.
create or replace function public.block_stock_movement_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Lançamento de estoque não se altera nem se apaga. Para corrigir, lance um ajuste.'
    using errcode = 'restrict_violation';
end;
$$;

revoke execute on function public.block_stock_movement_change() from public, anon;

create trigger trg_stock_movements_immutable
  before update or delete on public.stock_movements
  for each row execute function public.block_stock_movement_change();

-- ── O saldo ─────────────────────────────────────────────────
-- `security_invoker`: o RLS de quem consulta vale aqui dentro. Produto
-- que a pessoa não pode ver não aparece com saldo.
--
-- `left join` e não `join`: produto sem nenhum movimento precisa aparecer
-- com saldo zero. Sumir da lista seria pior do que mostrar zero — some
-- justamente o que ninguém contou ainda.
create view public.product_stock
with (security_invoker = true) as
select p.id                                as product_id,
       p.code,
       p.name,
       p.unit_id,
       p.category_id,
       p.brand_id,
       p.is_active,
       coalesce(sum(m.quantity), 0)::numeric(14,3) as quantity,
       max(m.created_at)                            as last_movement_at
  from public.products p
  left join public.stock_movements m on m.product_id = p.id
 where p.deleted_at is null
 group by p.id;

comment on view public.product_stock is
  'Saldo por produto: soma do livro. Produto sem movimento aparece com zero, de proposito.';

-- ── RLS ─────────────────────────────────────────────────────
-- Ler: os dois papéis. O vendedor PRECISA saber se tem a peça antes de
-- prometer prazo ao cliente — negar isso a ele é empurrar a pergunta
-- para o WhatsApp.
--
-- Escrever: o lançamento manual é do administrador. A saída do
-- faturamento não passa por policy nenhuma: quem escreve é o gatilho,
-- que é `security definer`. O vendedor fatura o próprio pedido e o
-- estoque baixa sozinho, sem que ele possa lançar nada à mão.
--
-- Não existe policy de UPDATE nem de DELETE. A ausência é a regra.
alter table public.stock_movements enable row level security;

create policy stock_movements_select on public.stock_movements
  for select to authenticated
  using ((select public.is_active_user()));

create policy stock_movements_insert on public.stock_movements
  for insert to authenticated
  with check ((select public.is_admin()));

revoke all on public.stock_movements from anon;
grant select, insert on public.stock_movements to authenticated;

-- ── Lançamento manual ───────────────────────────────────────
-- Entrada, ajuste, perda e devolução entram por aqui. `sale` não: saída
-- de venda nasce do pedido faturado, e deixar a tela lançar 'sale' à mão
-- abriria a porta para o estoque discordar da nota fiscal — exatamente o
-- que a decisão nº 1 quis evitar.
create or replace function public.register_stock_movement(
  p_product_id uuid,
  p_reason     public.stock_reason,
  p_quantity   numeric,
  p_notes      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_custo  numeric(14,2);
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode lançar movimento de estoque'
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason = 'sale' then
    raise exception 'Saída de venda nasce do pedido faturado, não do lançamento manual'
      using errcode = 'check_violation';
  end if;

  if p_quantity is null or p_quantity = 0 then
    raise exception 'Informe uma quantidade diferente de zero'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.products where id = p_product_id and deleted_at is null) then
    raise exception 'Produto não encontrado' using errcode = 'no_data_found';
  end if;

  -- `product_costs` é de administrador; esta função é `security definer` e
  -- só administrador chega aqui, então a leitura é legítima. O valor não
  -- volta para quem chamou: ele vai direto para a tabela irmã.
  select cost_price into v_custo from public.product_costs where product_id = p_product_id;

  -- Motivos que só fazem sentido saindo têm o sinal corrigido aqui, e não
  -- na tela: quem digita "perdi 3" quer dizer −3, e errar o sinal de uma
  -- perda infla o estoque em silêncio.
  if p_reason in ('loss', 'return_out') then
    p_quantity := -abs(p_quantity);
  elsif p_reason in ('initial', 'purchase', 'return_in') then
    p_quantity := abs(p_quantity);
  end if;
  -- 'adjustment' mantém o sinal de propósito: acerto de contagem vai para
  -- os dois lados.

  insert into public.stock_movements (product_id, reason, quantity, notes, created_by)
  values (p_product_id, p_reason, p_quantity, nullif(btrim(p_notes), ''), auth.uid())
  returning id into v_id;

  insert into public.stock_movement_costs (movement_id, unit_cost)
  values (v_id, coalesce(v_custo, 0));

  return v_id;
end;
$$;

revoke execute on function public.register_stock_movement(uuid, public.stock_reason, numeric, text) from public, anon;
grant execute on function public.register_stock_movement(uuid, public.stock_reason, numeric, text) to authenticated;

-- ── A baixa do faturamento ──────────────────────────────────
-- Dispara quando o pedido ENTRA em `invoiced`, e só nessa transição.
--
-- Kit não tem estoque: quem tem é o componente. O que sai é o que está
-- congelado em `components_snapshot`, e só o que foi de fato levado
-- (`selected`) — kit com opcional não escolhido não pode baixar o
-- opcional. Item avulso (`custom`) não mexe em estoque nenhum: ele não
-- veio do catálogo.
--
-- Não barra por falta de saldo (decisão nº 2). O aviso é da tela; o livro
-- registra o que aconteceu de verdade, inclusive quando dá negativo.
create or replace function public.write_sale_stock_movements()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r_item      record;
  r_component record;
  v_movimento uuid;
begin
  if new.status <> 'invoiced' or old.status is not distinct from 'invoiced' then
    return new;
  end if;

  -- Cinto de segurança: se por qualquer caminho o pedido voltar a
  -- `invoiced`, a mercadoria não sai duas vezes.
  if exists (
    select 1 from public.stock_movements
     where order_id = new.id and reason = 'sale'
  ) then
    return new;
  end if;

  for r_item in
    select oi.id, oi.kind, oi.product_id, oi.quantity, oi.components_snapshot
      from public.order_items oi
     where oi.order_id = new.id
  loop
    if r_item.kind = 'product' and r_item.product_id is not null then
      insert into public.stock_movements
        (product_id, reason, quantity, order_id, order_item_id, created_by)
      values (r_item.product_id, 'sale', -r_item.quantity, new.id, r_item.id, auth.uid())
      returning id into v_movimento;

      insert into public.stock_movement_costs (movement_id, unit_cost)
      select v_movimento, coalesce(c.cost_price, 0)
        from (select 1) z
        left join public.product_costs c on c.product_id = r_item.product_id;

    elsif r_item.kind = 'kit' and r_item.components_snapshot is not null then
      for r_component in
        select (c ->> 'product_id')::uuid                as product_id,
               (c ->> 'quantity_milli')::numeric / 1000  as quantity
          from jsonb_array_elements(r_item.components_snapshot) as c
         where c ->> 'product_id' is not null
           and coalesce((c ->> 'selected')::boolean, true)
      loop
        if r_component.quantity > 0 then
          insert into public.stock_movements
            (product_id, reason, quantity, order_id, order_item_id, created_by)
          values (r_component.product_id, 'sale',
                  -(r_component.quantity * r_item.quantity), new.id, r_item.id, auth.uid())
          returning id into v_movimento;

          insert into public.stock_movement_costs (movement_id, unit_cost)
          select v_movimento, coalesce(c.cost_price, 0)
            from (select 1) z
            left join public.product_costs c on c.product_id = r_component.product_id;
        end if;
      end loop;
    end if;
  end loop;

  return new;
end;
$$;

revoke execute on function public.write_sale_stock_movements() from public, anon;

create trigger trg_orders_write_stock
  after update of status on public.orders
  for each row execute function public.write_sale_stock_movements();

-- ── Devolução: o caminho de volta ───────────────────────────
-- Pedido faturado não vira cancelado (o gatilho de transição já barra) —
-- o caminho é a devolução. Ela estorna o que aquele pedido tirou, item a
-- item, sem apagar nada: os dois lançamentos ficam à vista.
create or replace function public.return_order_stock(p_order_id uuid, p_notes text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quantos int := 0;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador pode registrar devolução de estoque'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.orders where id = p_order_id and deleted_at is null) then
    raise exception 'Pedido não encontrado' using errcode = 'no_data_found';
  end if;

  if exists (
    select 1 from public.stock_movements
     where order_id = p_order_id and reason = 'return_in'
  ) then
    raise exception 'Este pedido já teve a devolução registrada'
      using errcode = 'unique_violation';
  end if;

  with estorno as (
    insert into public.stock_movements
      (product_id, reason, quantity, order_id, order_item_id, notes, created_by)
    select m.product_id, 'return_in', -m.quantity, m.order_id, m.order_item_id,
           nullif(btrim(p_notes), ''), auth.uid()
      from public.stock_movements m
     where m.order_id = p_order_id and m.reason = 'sale'
    returning id, product_id
  )
  insert into public.stock_movement_costs (movement_id, unit_cost)
  select e.id, coalesce(c.cost_price, 0)
    from estorno e
    left join public.product_costs c on c.product_id = e.product_id;

  get diagnostics v_quantos = row_count;

  if v_quantos = 0 then
    raise exception 'Este pedido não tirou nada do estoque'
      using errcode = 'no_data_found';
  end if;

  return v_quantos;
end;
$$;

revoke execute on function public.return_order_stock(uuid, text) from public, anon;
grant execute on function public.return_order_stock(uuid, text) to authenticated;
