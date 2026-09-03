-- ============================================================
-- 0903100000 · Fornecedores (Onda 2A)
--
-- Quem vende PARA a AgroTork: DJI, JR, distribuidores, oficinas.
-- Não confundir com `brands`, que é a marca comercial estampada no
-- produto — a distinção já estava registrada na Fase 1 e continua
-- valendo: a mesma marca pode vir de mais de um fornecedor, e o mesmo
-- fornecedor entrega marcas diferentes.
--
-- Espelha `customers` de propósito: mesmos campos de identificação,
-- contato e endereço, mesma normalização de documento, mesmas regras de
-- desativação. Quem já sabe cadastrar cliente sabe cadastrar fornecedor.
--
-- Esta tabela sozinha não faz nada — ela existe para a entrada de
-- mercadoria (2C) ter de onde pendurar a nota de compra. É a primeira
-- peça da Onda 2, e a mais simples de propósito.
-- ============================================================

create table public.suppliers (
  id                 uuid primary key default gen_random_uuid(),
  person_type        public.person_type not null default 'company',
  name               text not null,
  trade_name         text,
  document           text,                     -- CPF/CNPJ, somente dígitos
  state_registration text,

  phone              text,
  whatsapp           text,
  email              text,
  website            text,

  address            text,
  address_number     text,
  address_complement text,
  district           text,
  city               text,
  state              char(2),
  zip_code           text,

  -- Quem atende a AgroTork nesse fornecedor. Texto livre: representante
  -- não é usuário do sistema e não merece tabela própria.
  contact_name       text,
  -- Prazo/condição que ELE dá para nós. O espelho de `payment_terms` do
  -- orçamento, do outro lado do balcão.
  payment_terms      text,

  notes              text,
  is_active          boolean not null default true,

  created_by         uuid references public.profiles(id) on delete set null,
  updated_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

-- Documento repetido é quase sempre cadastro em duplicata. Índice
-- PARCIAL: só vale para quem informou documento e não está excluído —
-- fornecedor sem CNPJ continua permitido, como no cliente.
create unique index idx_suppliers_document
  on public.suppliers (document)
  where document is not null and document <> '' and deleted_at is null;

create index idx_suppliers_name   on public.suppliers (name)   where deleted_at is null;
create index idx_suppliers_active on public.suppliers (is_active) where deleted_at is null;

create trigger trg_suppliers_updated_at before update on public.suppliers
  for each row execute function public.set_updated_at();

-- ── Normalização, igual à do cliente ────────────────────────
-- Documento e CEP só com dígitos, UF em maiúscula. Sem isto, o mesmo
-- CNPJ digitado com e sem pontuação viraria dois fornecedores e o índice
-- único acima não perceberia.
create or replace function public.normalize_supplier()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.document := public.only_digits(new.document);
  new.zip_code := public.only_digits(new.zip_code);
  new.state    := upper(nullif(new.state, ''));
  return new;
end;
$$;

revoke execute on function public.normalize_supplier() from public, anon;

create trigger trg_suppliers_normalize
  before insert or update on public.suppliers
  for each row execute function public.normalize_supplier();

-- ── RLS ─────────────────────────────────────────────────────
-- Quem compra é a administração, não o vendedor. Mas o vendedor PRECISA
-- ler: para saber de quem vem a peça que ele prometeu ao cliente, e
-- porque a tela de estoque (2B) vai mostrar a origem da entrada.
--
-- Então: leitura para os dois papéis, escrita só do administrador. É o
-- mesmo desenho de `brands` e `categories`, não o de `customers` — o
-- vendedor cadastra cliente, mas não escolhe de quem a empresa compra.
alter table public.suppliers enable row level security;

create policy suppliers_select on public.suppliers
  for select to authenticated
  using ((select public.is_active_user()) and deleted_at is null);

create policy suppliers_insert on public.suppliers
  for insert to authenticated
  with check ((select public.is_admin()));

create policy suppliers_update on public.suppliers
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy suppliers_delete on public.suppliers
  for delete to authenticated
  using ((select public.is_admin()));

comment on table public.suppliers is
  'Quem vende para a AgroTork. Leitura dos dois papéis; escrita só do administrador. Nao confundir com brands (marca comercial do produto).';

-- ── Privilégios — o default do Supabase concede; aqui tira ──
revoke all on public.suppliers from anon;
grant select, insert, update, delete on public.suppliers to authenticated;

-- ── Exclusão lógica ─────────────────────────────────────────
-- O mesmo problema já documentado na migration 1800 (descartar rascunho):
-- o PostgreSQL aplica as policies de SELECT também sobre a LINHA
-- RESULTANTE de um UPDATE. Como `suppliers_select` exige
-- `deleted_at is null`, um `update ... set deleted_at = now()` é recusado
-- com "new row violates row-level security policy" — para qualquer
-- usuário, administrador incluído.
--
-- A saída é a mesma de lá: uma função `security definer` que confere a
-- permissão por conta própria e grava. A policy de leitura continua
-- estrita (o excluído some mesmo) e a exclusão passa por um caminho
-- único, auditável, com a regra dentro do banco.
create or replace function public.delete_supplier(p_supplier_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supplier public.suppliers%rowtype;
begin
  select * into v_supplier
    from public.suppliers
   where id = p_supplier_id and deleted_at is null;

  if not found then
    raise exception 'Fornecedor não encontrado' using errcode = 'no_data_found';
  end if;

  -- A mesma regra da policy de escrita: quem decide de quem a empresa
  -- compra é a administração.
  if not public.is_admin() then
    raise exception 'Somente administrador pode excluir fornecedor'
      using errcode = 'insufficient_privilege';
  end if;

  -- Quando a entrada de mercadoria existir (2C), a checagem de compras
  -- vinculadas entra AQUI, e não na tela: é o mesmo desenho do cliente
  -- com orçamento, logo abaixo na migration seguinte.
  update public.suppliers
     set deleted_at = now(),
         updated_by = auth.uid()
   where id = p_supplier_id;

  return true;
end;
$$;

revoke execute on function public.delete_supplier(uuid) from public, anon;
grant execute on function public.delete_supplier(uuid) to authenticated;
