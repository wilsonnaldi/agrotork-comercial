-- ============================================================
-- 0903160000 · Importação de NF-e (Fase 8)
--
-- O QUE ESTA MIGRATION RESOLVE — E O QUE ELA NÃO FAZ
--
-- Ela não lê XML. Ler XML é trabalho da aplicação, e fica lá. O que o
-- banco precisa ganhar é a MEMÓRIA que faz a importação valer a pena na
-- segunda vez.
--
-- O PROBLEMA DO DE-PARA
--
-- O fornecedor chama a peça de "BAT-6000S". A AgroTork chama de
-- "AGT-0042". O XML traz o código DELE, e nenhuma esperteza de texto
-- resolve isso de forma confiável: "BATERIA 6000" e "Bateria 6.000 mAh"
-- são a mesma coisa para uma pessoa e coisas diferentes para um
-- algoritmo. Tentar adivinhar aqui erraria o estoque e erraria o custo.
--
-- A solução é não adivinhar duas vezes: na primeira nota daquele
-- fornecedor a pessoa aponta o produto, e o sistema GUARDA a
-- correspondência. Da segunda nota em diante aquele item entra sozinho.
-- A importação fica mais inteligente a cada nota, sem nunca ter chutado.
--
-- Por que a chave é (fornecedor, código) e não só o código: dois
-- fornecedores usam o mesmo "1001" para coisas diferentes, e isso é
-- comum. O código só identifica alguma coisa dentro do catálogo de quem
-- o emitiu.
-- ============================================================

-- ── GTIN/EAN: o código que é do PRODUTO, não de quem vende ──
-- Quando o XML traz o EAN, ele vale mais que qualquer de-para: é o mesmo
-- número em qualquer nota, de qualquer fornecedor. Nem todo produto tem
-- (peça de fabricação própria não tem), por isso o índice é parcial.
alter table public.products
  add column if not exists gtin text;

comment on column public.products.gtin is
  'Codigo de barras (EAN/GTIN). Identifica o produto em qualquer nota, de qualquer fornecedor. Nem todo produto tem.';

create unique index if not exists idx_products_gtin
  on public.products (gtin)
  where gtin is not null and gtin <> '' and deleted_at is null;

-- ── A memória do de-para ────────────────────────────────────
create table public.supplier_products (
  id            uuid primary key default gen_random_uuid(),

  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  -- Como ELE chama. Vem do `cProd` do XML.
  supplier_code text not null,
  product_id    uuid not null references public.products(id) on delete cascade,

  -- Como ele descreveu na nota em que a correspondência foi feita.
  -- Guardado para a tela poder mostrar "você ligou 'BAT-6000S — BATERIA
  -- 6000MAH' a este produto" quando alguém for conferir.
  supplier_description text,

  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Um código do fornecedor aponta para UM produto. Se ele mudar de ideia,
-- a correspondência é sobrescrita, não duplicada.
create unique index idx_supplier_products_codigo
  on public.supplier_products (supplier_id, upper(supplier_code));

create index idx_supplier_products_product on public.supplier_products (product_id);

create trigger trg_supplier_products_updated_at before update on public.supplier_products
  for each row execute function public.set_updated_at();

-- Espaço sobrando e maiúscula inconsistente são o que faz a
-- correspondência falhar na nota seguinte.
create or replace function public.normalize_supplier_product()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.supplier_code := upper(btrim(new.supplier_code));
  if new.supplier_code = '' then
    raise exception 'Código do fornecedor vazio' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke execute on function public.normalize_supplier_product() from public, anon;

create trigger trg_supplier_products_normalize
  before insert or update on public.supplier_products
  for each row execute function public.normalize_supplier_product();

-- ── RLS: administrador ──────────────────────────────────────
-- É parte da compra, e compra é do administrador — como tudo em 2C.
alter table public.supplier_products enable row level security;

create policy supplier_products_admin on public.supplier_products
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

revoke all on public.supplier_products from anon;
grant select, insert, update, delete on public.supplier_products to authenticated;

-- ── Guardar a correspondência ───────────────────────────────
-- `on conflict` porque corrigir um de-para errado é normal: a pessoa
-- apontou o produto errado na nota passada e conserta agora. A linha é
-- sobrescrita; não existe histórico de de-para, e não faz falta.
create or replace function public.remember_supplier_product(
  p_supplier_id uuid,
  p_code        text,
  p_product_id  uuid,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Somente administrador trabalha com entrada de mercadoria'
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(btrim(p_code), '') = '' then
    return null;
  end if;

  insert into public.supplier_products
    (supplier_id, supplier_code, product_id, supplier_description, created_by)
  values (p_supplier_id, p_code, p_product_id, nullif(btrim(p_description), ''), auth.uid())
  on conflict (supplier_id, upper(supplier_code))
  do update set product_id           = excluded.product_id,
                supplier_description = coalesce(excluded.supplier_description,
                                               public.supplier_products.supplier_description)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.remember_supplier_product(uuid, text, uuid, text) from public, anon;
grant execute on function public.remember_supplier_product(uuid, text, uuid, text) to authenticated;

-- ── O que a importação já conhece deste fornecedor ──────────
-- Uma consulta só devolve tudo que a tela precisa para pré-preencher a
-- nota: o de-para do fornecedor mais o GTIN de cada produto. Sem isto,
-- a tela faria uma consulta por item da nota.
create or replace function public.known_supplier_products(p_supplier_id uuid)
returns table (
  supplier_code text,
  product_id    uuid,
  product_code  text,
  product_name  text,
  gtin          text
)
language sql
stable
security invoker
set search_path = public
as $$
  select sp.supplier_code, p.id, p.code, p.name, p.gtin
    from public.supplier_products sp
    join public.products p on p.id = sp.product_id
   where sp.supplier_id = p_supplier_id
     and p.deleted_at is null;
$$;

revoke execute on function public.known_supplier_products(uuid) from public, anon;
grant execute on function public.known_supplier_products(uuid) to authenticated;

comment on table public.supplier_products is
  'De-para entre o codigo do fornecedor (cProd da NF-e) e o produto da AgroTork. A importacao fica mais inteligente a cada nota, sem nunca chutar.';
