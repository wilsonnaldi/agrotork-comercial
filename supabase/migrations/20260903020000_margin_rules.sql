-- ============================================================
-- 20260903020000 · Margem por setor
--
-- Motivo: precificar 112 produtos um a um é inviável e, pior, é
-- irrepetível — quando o custo do fabricante muda, ninguém lembra
-- de qual regra usou. A margem passa a ser um CADASTRO, não uma
-- conta feita na mão.
--
-- Desenho: a regra SUGERE, não impõe. `products.sale_price` continua
-- sendo o preço real e é ele que o orçamento usa. A regra calcula o
-- preço sugerido e existe uma operação explícita para aplicar em lote.
-- Assim o preço nunca muda sozinho nas costas do vendedor, e a trilha
-- de auditoria registra quem aplicou e quando.
--
-- O "setor" é a CATEGORIA que já existe. Uma taxonomia só: se você
-- precifica drone diferente de bateria, então "Drones" e "Baterias"
-- são categorias. Não se cria uma segunda árvore paralela.
-- ============================================================

create table public.margin_rules (
  id          uuid primary key default gen_random_uuid(),
  -- NULL = regra padrão, vale para produto sem categoria.
  category_id uuid references public.categories(id) on delete cascade,
  mode        text not null default 'markup'
                check (mode in ('markup', 'margin')),
  percent     numeric(6,2) not null check (percent >= 0),
  cost_basis  text not null default 'maior'
                check (cost_basis in ('avista', 'faturado', 'maior')),
  rounding    text not null default 'none'
                check (rounding in ('none', 'ten', 'hundred', 'ninety')),
  is_active   boolean not null default true,
  notes       text,
  updated_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Margem sobre a venda de 100% seria divisão por zero: preço infinito.
  constraint margin_rules_percent_coerente
    check (mode = 'markup' or percent < 100)
);

comment on table public.margin_rules is
  'Margem de lucro por setor (categoria). Sugere o preço de venda; não o impõe.';
comment on column public.margin_rules.mode is
  'markup = percentual SOBRE O CUSTO (custo x 1,30). margin = percentual SOBRE A VENDA (custo / 0,70). Não são a mesma coisa.';
comment on column public.margin_rules.cost_basis is
  'maior = usa o custo mais alto entre as condições vigentes, para que nenhuma venda a prazo fique abaixo da margem.';

-- Uma regra por categoria, e uma única regra padrão.
create unique index idx_margin_rules_categoria
  on public.margin_rules (category_id) where category_id is not null;
create unique index idx_margin_rules_padrao
  on public.margin_rules ((category_id is null)) where category_id is null;

create trigger trg_margin_rules_updated_at
  before update on public.margin_rules
  for each row execute function public.set_updated_at();

create trigger trg_audit_margin_rules
  after insert or update or delete on public.margin_rules
  for each row execute function public.audit_capture('margin_rule', 'id', '', '', '');

-- ── RLS: só administrador ───────────────────────────────────
-- A regra de margem revela a estrutura de custo: quem sabe o preço e o
-- markup deduz o custo. Fica no mesmo nível de `product_costs`.
alter table public.margin_rules enable row level security;

create policy margin_rules_select on public.margin_rules
  for select to authenticated using ((select public.is_admin()));
create policy margin_rules_insert on public.margin_rules
  for insert to authenticated with check ((select public.is_admin()));
create policy margin_rules_update on public.margin_rules
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy margin_rules_delete on public.margin_rules
  for delete to authenticated using ((select public.is_admin()));

grant select, insert, update, delete on public.margin_rules to authenticated;
grant all on public.margin_rules to service_role;

-- ── Arredondamento comercial ────────────────────────────────
create or replace function public.round_commercial(p_value numeric, p_mode text)
returns numeric language sql immutable security invoker set search_path = ''
as $$
  select case p_mode
    when 'ten'     then ceil(p_value / 10)  * 10
    when 'hundred' then ceil(p_value / 100) * 100
    -- Termina em 90: 1.234 vira 1.290. Nunca arredonda para baixo.
    when 'ninety'  then ceil(p_value / 100) * 100 - 10
    else round(p_value, 2)
  end;
$$;

-- ── Preço sugerido de um produto ────────────────────────────
-- SECURITY INVOKER de propósito: quem não enxerga `product_costs` pela
-- RLS recebe NULL, exatamente como já acontece com custo e margem.
create or replace function public.suggested_sale_price(p_product_id uuid)
returns numeric language plpgsql stable security invoker set search_path = ''
as $$
declare
  v_cat    uuid;
  v_rule   public.margin_rules%rowtype;
  v_cost   numeric(14,2);
begin
  select category_id into v_cat from public.products where id = p_product_id;

  select * into v_rule from public.margin_rules
   where is_active and category_id is not distinct from v_cat;

  if not found then
    select * into v_rule from public.margin_rules
     where is_active and category_id is null;
    if not found then return null; end if;
  end if;

  select case v_rule.cost_basis
           when 'avista'   then max(c.cost_price) filter (where p.code = 'AVISTA')
           when 'faturado' then coalesce(
                                  max(c.cost_price) filter (where p.code = 'FATURADO'),
                                  max(c.cost_price) filter (where p.code = 'AVISTA'))
           else max(c.cost_price)
         end
    into v_cost
    from public.product_costs c
    join public.price_conditions p on p.id = c.condition_id
   where c.product_id = p_product_id and c.valid_to is null;

  if v_cost is null or v_cost <= 0 then return null; end if;

  return public.round_commercial(
    case when v_rule.mode = 'markup'
         then v_cost * (1 + v_rule.percent / 100)
         else v_cost / (1 - v_rule.percent / 100)
    end, v_rule.rounding);
end;
$$;

-- ── Aplicar em lote ─────────────────────────────────────────
-- Ensaio por padrão: devolve o que MUDARIA sem escrever nada. Só grava
-- quando p_dry_run é explicitamente false. `sale_price_set_at` é
-- carimbado pelo trigger que já existe desde 20260902120100.
create or replace function public.apply_margin_rules(
  p_category_id uuid default null,
  p_todas       boolean default false,
  p_dry_run     boolean default true
)
returns table (
  product_id     uuid,
  code           text,
  name           text,
  categoria      text,
  preco_atual    numeric,
  preco_sugerido numeric,
  aplicado       boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  if not (select public.is_admin()) then
    raise exception 'Somente administrador pode aplicar margem';
  end if;

  return query
  with alvo as (
    select p.id, p.code, p.name, c.name as categoria,
           p.sale_price, public.suggested_sale_price(p.id) as sugerido
      from public.products p
      left join public.categories c on c.id = p.category_id
     where p.deleted_at is null
       and (p_todas or p.category_id is not distinct from p_category_id)
  ),
  mudanca as (
    select * from alvo
     where sugerido is not null and sugerido <> sale_price
  ),
  escrita as (
    update public.products p
       set sale_price = m.sugerido
      from mudanca m
     where p.id = m.id and not p_dry_run
    returning p.id
  )
  select m.id, m.code, m.name, m.categoria, m.sale_price, m.sugerido,
         (not p_dry_run) and exists (select 1 from escrita e where e.id = m.id)
    from mudanca m
   order by m.categoria nulls first, m.code;
end;
$$;

revoke all on function public.apply_margin_rules(uuid, boolean, boolean) from anon;
revoke all on function public.suggested_sale_price(uuid) from anon;
revoke all on function public.round_commercial(numeric, text) from anon;

-- ── Regra padrão, desligada ─────────────────────────────────
-- Entra inativa de propósito: ninguém precifica nada sem alguém decidir.
insert into public.margin_rules (category_id, mode, percent, cost_basis, rounding, is_active, notes)
values (null, 'markup', 0, 'maior', 'none', false,
        'Regra padrão para produto sem categoria. Ajuste o percentual e ative.');
