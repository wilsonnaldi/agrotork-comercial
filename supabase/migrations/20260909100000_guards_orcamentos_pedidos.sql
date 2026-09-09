-- ============================================================
-- 0909100000 · Guardas de orçamento e pedido (correção de auditoria)
--
-- Auditoria de banco de 09/09/2026 sobre objetos JÁ EM PRODUÇÃO
-- (migrations até 20260903080000). Nenhuma migration anterior foi
-- alterada: tudo aqui é redefinição por cima, com o texto integral.
--
-- O que estava errado, em uma linha cada:
--
--   A1  vendedor INSERIA orçamento já `approved`, com número, carimbos e
--       total escolhidos, sem item — o recálculo é AFTER UPDATE, e
--       `assign_quote_number` só numerava quando `number` vinha vazio.
--   A2  vendedor reescrevia `number`, `sequence_*`, `sent_at`,
--       `approved_at`, `created_*` do próprio orçamento por UPDATE.
--   A3  dois cliques em "fechar pedido" geravam DOIS pedidos vivos para o
--       mesmo orçamento: a unicidade era só um `exists` dentro da função.
--   A4  `trg_orders_freeze` deixava o dono reescrever `invoiced_at`,
--       `delivered_at`, `confirmed_at`, `created_at`, `created_by`.
--   A5  mover item de um orçamento para outro deixava o total do
--       orçamento antigo inflado: só o destino era recalculado.
--   A6  `quote_is_editable` perdeu `is_active_user()` na 0903080000:
--       usuário desativado editava itens do próprio rascunho.
--   A10 `next_order_number()` e `recalculate_order_totals()` eram
--       executáveis por `authenticated` (o default do Supabase concede
--       EXECUTE direto; `revoke from public` não alcança).
--   A11 `authenticated` tinha TRUNCATE em todas as tabelas de `public`
--       — TRUNCATE ignora RLS e os gatilhos de imutabilidade.
--   A14 `orders`/`order_items`/`price_conditions` sem trilha de auditoria.
--   A16 `margin_rules`, `price_conditions`, `products_list` e as funções
--       de margem alcançáveis por `anon` (grant de PUBLIC).
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- A1 · O orçamento nasce numerado pelo banco, em rascunho, zerado
-- ════════════════════════════════════════════════════════════
-- Para quem não é administrador, o INSERT não escolhe nada de controle:
-- número vem da sequência SEMPRE (um número inventado colide com o
-- próximo legítimo e trava a numeração de todo mundo), situação é
-- `draft`, carimbos e exclusão lógica ficam nulos, autor é quem está
-- logado. Totais zeram para todos — orçamento novo não tem item, e o
-- valor só pode nascer do item. `issue_date` continua livre: é campo do
-- formulário.
create or replace function public.assign_quote_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r        record;
  -- Sem JWT (`auth.uid()` nulo) é o próprio banco escrevendo: migration,
  -- pg_cron, script de carga. Esses não passam pelo formulário e não
  -- são o problema que esta guarda resolve.
  v_admin  boolean := coalesce((select public.is_admin()), false)
                      or (select auth.uid()) is null;
begin
  if not v_admin or new.number is null or new.number = '' then
    select * into r
      from public.next_quote_number(extract(year from coalesce(new.issue_date, current_date))::int);
    new.number          := r.formatted;
    new.sequence_year   := r.seq_year;
    new.sequence_number := r.seq_number;
  end if;

  if not v_admin then
    new.status      := 'draft';
    new.sent_at     := null;
    new.approved_at := null;
    new.rejected_at := null;
    new.deleted_at  := null;
    new.created_at  := now();
    new.created_by  := (select auth.uid());
  end if;

  new.subtotal := 0;
  new.total    := 0;
  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A2 · Colunas de controle do orçamento não são do vendedor
-- ════════════════════════════════════════════════════════════
-- A policy de UPDATE decide QUEM escreve; não decide O QUÊ. Um gatilho
-- BEFORE com nome `_a_` para rodar antes de `trg_quotes_stamp_status`
-- (ordem alfabética): assim o carimbo que o gatilho de status grava não
-- é confundido com um carimbo digitado.
--
-- `issue_date`, condições e observações ficam livres — são formulário.
create or replace function public.protect_quote_control_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- A guarda é para o usuário comum logado. Administrador corrige; quem
  -- não é usuário ativo (migration, pg_cron, script de carga: sem JWT)
  -- opera. `is_active_user()` é definer de propósito — um gatilho
  -- invoker chamando `auth.uid()` direto depende de USAGE em `auth`.
  if coalesce((select public.is_admin()), false)
     or not coalesce((select public.is_active_user()), false) then
    return new;
  end if;

  if new.number              is distinct from old.number
     or new.sequence_year       is distinct from old.sequence_year
     or new.sequence_number     is distinct from old.sequence_number
     or new.created_at          is distinct from old.created_at
     or new.created_by          is distinct from old.created_by
     or new.owner_id            is distinct from old.owner_id
     or new.sent_at             is distinct from old.sent_at
     or new.approved_at         is distinct from old.approved_at
     or new.rejected_at         is distinct from old.rejected_at
     or new.revision            is distinct from old.revision
     or new.origin_order_id     is distinct from old.origin_order_id
     or new.supersedes_quote_id is distinct from old.supersedes_quote_id
  then
    raise exception 'Numero, carimbos e origem do orcamento sao do sistema, nao do formulario.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function public.protect_quote_control_columns() from public, anon, authenticated;

drop trigger if exists trg_quotes_a_control on public.quotes;
create trigger trg_quotes_a_control
  before update on public.quotes
  for each row execute function public.protect_quote_control_columns();

-- ════════════════════════════════════════════════════════════
-- A3 · Um pedido vivo por orçamento — garantido pelo índice, não pelo if
-- ════════════════════════════════════════════════════════════
-- O `exists` da função continua (mensagem decente); o índice é quem
-- segura a segunda transação. E o orçamento é travado com `for update`
-- para que dois cliques simultâneos se enfileirem em vez de os dois
-- lerem "ainda não tem pedido".
create unique index if not exists idx_orders_one_live_per_quote
  on public.orders (quote_id)
  where quote_id is not null and deleted_at is null and status <> 'cancelled';

create or replace function public.create_order_from_quote(p_quote_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_quote public.quotes%rowtype;
  v_order_id uuid;
  r record;
begin
  -- `for update`: serializa conversões concorrentes do mesmo orçamento.
  select * into v_quote from public.quotes
   where id = p_quote_id and deleted_at is null
   for update;
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

-- ════════════════════════════════════════════════════════════
-- A4 · O pedido também congela o que prova QUANDO e POR QUEM
-- ════════════════════════════════════════════════════════════
-- `confirmed_at`, `created_at`, `created_by` e a corrente de
-- renegociação são fatos, não campos: ninguém reescreve. Os carimbos de
-- situação e o dono continuam livres para o administrador (transferir
-- pedido e corrigir uma data é decisão dele); para o vendedor, o carimbo
-- nasce do gatilho de status e só dele.
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

  if new.confirmed_at          is distinct from old.confirmed_at
     or new.created_at          is distinct from old.created_at
     or new.created_by          is distinct from old.created_by
     or new.supersedes_order_id is distinct from old.supersedes_order_id
  then
    raise exception 'Origem e data de criacao do pedido nao mudam.'
      using errcode = 'check_violation';
  end if;

  -- Usuário ativo que não é administrador: o vendedor. Sem JWT (migration,
  -- pg_cron) `is_active_user()` é falso e a guarda não se aplica.
  if coalesce((select public.is_active_user()), false)
     and not coalesce((select public.is_admin()), false) and (
        new.owner_id     is distinct from old.owner_id
     or new.picking_at   is distinct from old.picking_at
     or new.invoiced_at  is distinct from old.invoiced_at
     or new.delivered_at is distinct from old.delivered_at
     or new.cancelled_at is distinct from old.cancelled_at
  ) then
    raise exception 'Carimbos de situacao e dono do pedido sao do sistema, nao do formulario.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- O carimbo é SEMPRE a hora da transição. Antes, um `coalesce` mantinha
-- o valor que já estivesse na coluna — e o dono podia pré-escrever uma
-- data antiga que o faturamento depois "confirmava".
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

  if v_new = 'picking'   then new.picking_at   := now(); end if;
  if v_new = 'invoiced'  then new.invoiced_at  := now(); end if;
  if v_new = 'delivered' then new.delivered_at := now(); end if;
  if v_new = 'cancelled' then new.cancelled_at := now(); end if;

  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A5 · Item que muda de orçamento recalcula os DOIS orçamentos
-- ════════════════════════════════════════════════════════════
create or replace function public.trg_recalc_from_item()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- O orçamento de ORIGEM perdia o item e ficava com o total antigo.
  if tg_op = 'UPDATE' and new.quote_id is distinct from old.quote_id then
    perform public.recalculate_quote_totals(old.quote_id);
  end if;
  perform public.recalculate_quote_totals(coalesce(new.quote_id, old.quote_id));
  return coalesce(new, old);
end;
$$;

-- ════════════════════════════════════════════════════════════
-- A6 · quote_is_editable volta a exigir usuário ativo
-- ════════════════════════════════════════════════════════════
-- Texto da 0903080000 (trava do pedido vivo) mais o `is_active_user()`
-- que a 20260901211340 tinha posto e que a redefinição perdeu, e o
-- `search_path = ''` da mesma migration.
create or replace function public.quote_is_editable(p_quote_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select public.is_active_user()) and exists (
    select 1 from public.quotes q
    where q.id = p_quote_id
      and q.deleted_at is null
      and not public.quote_has_live_order(q.id)
      and (
        (select public.is_admin())
        or (q.owner_id = (select auth.uid()) and q.status::text not in ('approved', 'cancelled'))
      )
  );
$$;

-- ════════════════════════════════════════════════════════════
-- A10 · Contador e recálculo do pedido não são RPC do vendedor
-- ════════════════════════════════════════════════════════════
-- A 0903060000 revogou de `public` e `anon`, mas o default privilege do
-- Supabase concede EXECUTE a `authenticated` DIRETAMENTE — e revogar de
-- PUBLIC não tira um grant nominal. Vendedor queimava PED-2026-nnnn à
-- vontade. As funções de gatilho vão junto, pela regra da 20260901052518.
revoke execute on function public.next_order_number(integer)         from public, anon, authenticated;
revoke execute on function public.recalculate_order_totals(uuid)     from public, anon, authenticated;
revoke execute on function public.freeze_order_commercials()         from public, anon, authenticated;
revoke execute on function public.validate_order_status_transition() from public, anon, authenticated;
revoke execute on function public.freeze_quote_with_live_order()     from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- A11 · TRUNCATE fora do alcance da API; anon sem default em tabela
-- ════════════════════════════════════════════════════════════
-- TRUNCATE não passa por RLS nem pelos gatilhos BEFORE UPDATE/DELETE que
-- tornam o livro do estoque e as baixas imutáveis. O PostgREST não
-- expõe TRUNCATE hoje; a camada existe para quando isso deixar de ser a
-- única defesa.
revoke truncate on all tables in schema public from anon, authenticated, public;
alter default privileges in schema public revoke truncate on tables from anon, authenticated;
-- `anon` nunca teve policy em tabela nenhuma; o default que a 1000
-- declarou só servia para a tabela nova nascer com SELECT concedido.
alter default privileges in schema public revoke all on tables from anon;

-- ════════════════════════════════════════════════════════════
-- A16 · Margem e condição de preço: fora do alcance de anon
-- ════════════════════════════════════════════════════════════
-- As funções são `security invoker` — anon batia em "permission denied"
-- na primeira tabela —, mas o EXECUTE via PUBLIC continuava lá e o
-- `revoke from anon` da 0903020000 não o alcançava. Revogar de PUBLIC e
-- devolver nominalmente a quem usa.
revoke all on public.margin_rules     from anon;
revoke all on public.price_conditions from anon;
revoke all on public.products_list    from anon;

revoke execute on function public.suggested_sale_price(uuid)               from public, anon;
revoke execute on function public.apply_margin_rules(uuid, boolean, boolean) from public, anon;
revoke execute on function public.round_commercial(numeric, text)          from public, anon;
grant  execute on function public.suggested_sale_price(uuid)               to authenticated, service_role;
grant  execute on function public.apply_margin_rules(uuid, boolean, boolean) to authenticated, service_role;
grant  execute on function public.round_commercial(numeric, text)          to authenticated, service_role;

-- ════════════════════════════════════════════════════════════
-- A14 · Trilha de auditoria: pedido, itens do pedido, condições de preço
-- ════════════════════════════════════════════════════════════
-- Texto integral de `audit_capture` (20260901060000), com o
-- `search_path = ''` da 20260901193926, mais:
--   · colunas derivadas ignoradas nas tabelas novas (sem isto, todo
--     pedido nasceria com um `order.updated` fantasma do recálculo);
--   · verbos `order.*`, `purchase.*` e `financial.*`.
-- Os gatilhos das tabelas da Onda 2 ficam na migration seguinte: esta
-- só toca no que já está em produção.
create or replace function public.audit_capture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity      text := tg_argv[0];
  v_pk          text := tg_argv[1];
  v_label_col   text := nullif(tg_argv[2], '');
  v_parent_type text := nullif(tg_argv[3], '');
  v_parent_col  text := nullif(tg_argv[4], '');

  v_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  v_new jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_row jsonb;

  -- Ruído de auditoria: `updated_at`/`updated_by` mudam em toda escrita e
  -- não contam nada que o log já não diga (ator e horário são colunas
  -- próprias). As demais são DERIVADAS — ver o comentário do bloco.
  v_ignore  text[] := array['updated_at', 'updated_by'];
  v_secret  text[] := array[]::text[];

  v_changed  text[];
  v_old_diff jsonb := '{}'::jsonb;
  v_new_diff jsonb := '{}'::jsonb;
  v_campo    text;

  v_uid   uuid := auth.uid();
  v_kind  text;
  v_email text;
  v_name  text;
  v_role  public.user_role;

  -- CUIDADO: dentro de uma função `security definer`, `current_user` é o
  -- DONO da função (postgres), não quem disparou a escrita — usá-lo aqui
  -- classificaria todo mundo como sistema. O que sobrevive ao
  -- `security definer` é o GUC `role`, que é exatamente o que o PostgREST
  -- define (`set local role authenticated` / `anon`). Sem SET ROLE ele vale
  -- 'none', e aí o papel real é o do login — o caso do pg_cron.
  v_db_role text := coalesce(nullif(current_setting('role', true), 'none'), session_user);

  v_action    text;
  v_entity_id text;
  v_label     text;
  v_parent_id text;
begin
  v_row := coalesce(v_new, v_old);

  -- ── Colunas derivadas e segredos, por tabela ──────────────
  -- `subtotal`/`total` de `quotes` são recalculados por
  -- `recalculate_quote_totals()` a cada mudança de item: sem esta exceção,
  -- adicionar um item ao orçamento geraria DOIS eventos — o do item e um
  -- `quote.updated` fantasma. `line_total` é coluna gerada.
  -- `view_count` sobe a cada visita anônima ao link público: seriam
  -- centenas de linhas sem ator e sem decisão.
  if tg_table_name = 'quotes' then
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'quote_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'orders' then
    -- `recalculate_order_totals()` reescreve subtotal/total logo depois do
    -- INSERT do pedido: sem isto, todo pedido nasceria com um
    -- `order.updated` fantasma colado ao `order.created`.
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'order_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'purchases' then
    v_ignore := v_ignore || array['items_total', 'total'];
  elsif tg_table_name = 'purchase_items' then
    -- Rateio e custo final são escritos pelo recebimento, linha a linha;
    -- o evento que importa é o `purchase.received`, não N `item_changed`.
    v_ignore := v_ignore || array['line_total', 'freight_share', 'landed_cost', 'previous_cost'];
  elsif tg_table_name = 'financial_entries' then
    -- `status` é derivado da soma das baixas; a baixa em si já é evento.
    v_ignore := v_ignore || array['status'];
  elsif tg_table_name = 'quote_share_tokens' then
    v_ignore := v_ignore || array['view_count'];
    -- O token é credencial de capacidade: quem o tem abre o orçamento sem
    -- login. É o único segredo que existe em `public`. Redigido AQUI, na
    -- escrita — filtrar só na leitura se contorna.
    v_secret := array['token'];
  end if;

  -- ── Antes e depois ────────────────────────────────────────
  if tg_op = 'UPDATE' then
    for v_campo in select k from jsonb_object_keys(v_new) as k loop
      continue when v_campo = any (v_ignore);
      if v_new -> v_campo is distinct from v_old -> v_campo then
        v_changed  := coalesce(v_changed, array[]::text[]) || v_campo;
        v_old_diff := v_old_diff || jsonb_build_object(v_campo, v_old -> v_campo);
        v_new_diff := v_new_diff || jsonb_build_object(v_campo, v_new -> v_campo);
      end if;
    end loop;

    -- Nada relevante mudou: não existe evento. É isto que mantém o log
    -- legível quando o recálculo de totais dispara o trigger.
    if v_changed is null then
      return null;
    end if;
  else
    v_old_diff := v_old;   -- nulo no INSERT
    v_new_diff := v_new;   -- nulo no DELETE
  end if;

  foreach v_campo in array v_secret loop
    if v_old_diff ? v_campo then
      v_old_diff := jsonb_set(v_old_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
    if v_new_diff ? v_campo then
      v_new_diff := jsonb_set(v_new_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
  end loop;

  -- ── Quem ──────────────────────────────────────────────────
  -- `auth.uid()` primeiro: ele sobrevive a funções `security definer`
  -- (lê o claim do JWT), então `discard_quote_draft()` continua sendo
  -- atribuída ao usuário de verdade, e não a `postgres`.
  if v_uid is not null then
    v_kind := 'user';
    select p.email, p.full_name, p.role
      into v_email, v_name, v_role
      from public.profiles p
     where p.id = v_uid;
  elsif v_db_role in ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role') then
    v_kind := 'system';        -- pg_cron, migration, SQL Editor, GoTrue
  elsif v_db_role = 'anon' then
    v_kind := 'anonymous';     -- link público
  else
    v_kind := 'unknown';
  end if;

  -- ── O verbo de negócio ────────────────────────────────────
  -- Derivado do diff, porque a aplicação não consegue informá-lo. Quando
  -- mais de uma coisa muda na mesma escrita, o evento mais específico
  -- vence — mas `changed_fields` continua listando tudo.
  if tg_op = 'DELETE' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_removed'
      when 'order_item'        then 'order.item_removed'
      when 'purchase_item'     then 'purchase.item_removed'
      when 'kit_item'          then 'kit.item_removed'
      when 'quote_share_token' then 'quote.link_deleted'
      when 'product_cost'      then 'product.cost_removed'
      else v_entity || '.deleted'
    end;

  elsif tg_op = 'INSERT' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_added'
      when 'order_item'        then 'order.item_added'
      when 'purchase_item'     then 'purchase.item_added'
      when 'financial_payment' then 'financial.payment_registered'
      when 'kit_item'          then 'kit.item_added'
      when 'quote_share_token' then 'quote.link_created'
      when 'product_cost'      then 'product.cost_changed'
      else v_entity || '.created'
    end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is not null then
    -- Exclusão lógica é o evento mais forte da escrita, venha ela de onde vier.
    v_action := case v_entity when 'quote' then 'quote.discarded'
                              else v_entity || '.deleted' end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is null then
    v_action := v_entity || '.restored';

  elsif v_entity = 'user' and 'role' = any (v_changed) then
    v_action := 'user.role_changed';

  elsif 'is_active' = any (v_changed) then
    v_action := v_entity || case when (v_new ->> 'is_active')::boolean
                                 then '.activated' else '.deactivated' end;

  elsif v_entity = 'quote' and 'status' = any (v_changed) then
    v_action := case v_new ->> 'status'
      when 'approved'  then 'quote.approved'
      when 'rejected'  then 'quote.rejected'
      when 'cancelled' then 'quote.cancelled'
      when 'expired'   then 'quote.expired'
      else 'quote.status_changed'
    end;

  elsif v_entity = 'order' and 'status' = any (v_changed) then
    -- picking / invoiced / delivered / cancelled: o verbo é a situação nova.
    v_action := 'order.' || (v_new ->> 'status');

  elsif v_entity = 'purchase' and 'status' = any (v_changed) then
    v_action := 'purchase.' || (v_new ->> 'status');

  elsif v_entity = 'financial_entry' and 'cancelled_at' = any (v_changed)
        and (v_new ->> 'cancelled_at') is not null then
    v_action := 'financial.cancelled';

  elsif v_entity = 'quote_share_token' and 'revoked_at' = any (v_changed)
        and (v_new ->> 'revoked_at') is not null then
    v_action := 'quote.link_revoked';

  elsif v_entity = 'product_cost' then
    v_action := 'product.cost_changed';

  elsif v_entity = 'product' and 'sale_price' = any (v_changed) then
    v_action := 'product.price_changed';

  elsif v_entity = 'kit' and 'discount_percent' = any (v_changed) then
    v_action := 'kit.discount_changed';

  elsif v_entity = 'kit_item' and 'item_type' = any (v_changed) then
    v_action := 'kit.item_type_changed';

  elsif v_entity = 'kit_item' and 'quantity' = any (v_changed) then
    v_action := 'kit.item_quantity_changed';

  elsif v_entity = 'quote_item'        then v_action := 'quote.item_changed';
  elsif v_entity = 'order_item'        then v_action := 'order.item_changed';
  elsif v_entity = 'purchase_item'     then v_action := 'purchase.item_changed';
  elsif v_entity = 'kit_item'          then v_action := 'kit.item_changed';
  elsif v_entity = 'quote_share_token' then v_action := 'quote.link_changed';
  elsif v_entity = 'user'              then v_action := 'user.profile_updated';
  else                                      v_action := v_entity || '.updated';
  end if;

  -- ── Onde ──────────────────────────────────────────────────
  v_entity_id := v_row ->> v_pk;
  v_label     := case when v_label_col  is null then null else v_row ->> v_label_col  end;
  v_parent_id := case when v_parent_col is null then null else v_row ->> v_parent_col end;

  insert into public.audit_log (
    actor_kind, actor_user_id, actor_email, actor_name, actor_role, actor_db_role,
    action, operation,
    entity_type, entity_id, entity_label, parent_type, parent_id,
    changed_fields, old_data, new_data, metadata
  ) values (
    v_kind, v_uid, v_email, v_name, v_role, v_db_role,
    v_action, tg_op,
    v_entity, v_entity_id, v_label, v_parent_type, v_parent_id,
    v_changed, v_old_diff, v_new_diff,
    jsonb_build_object('txid', txid_current(), 'table', tg_table_name)
  );

  return null;   -- trigger AFTER: o retorno é ignorado
end;
$$;

revoke execute on function public.audit_capture() from public, anon, authenticated;

drop trigger if exists trg_audit_orders on public.orders;
create trigger trg_audit_orders after insert or update or delete on public.orders
  for each row execute function public.audit_capture('order', 'id', 'number', '', '');

drop trigger if exists trg_audit_order_items on public.order_items;
create trigger trg_audit_order_items after insert or update or delete on public.order_items
  for each row execute function public.audit_capture('order_item', 'id', 'name_snapshot', 'order', 'order_id');

drop trigger if exists trg_audit_price_conditions on public.price_conditions;
create trigger trg_audit_price_conditions after insert or update or delete on public.price_conditions
  for each row execute function public.audit_capture('price_condition', 'id', 'code', '', '');
