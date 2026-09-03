-- ============================================================
-- 0903110000 · Excluir cliente (correção de defeito)
--
-- DEFEITO ENCONTRADO AO CONSTRUIR FORNECEDORES
--
-- `src/modules/customers/repository.ts` fazia a exclusão lógica com
-- `update customers set deleted_at = now()`. Isso NUNCA funcionou: a
-- policy `customers_select` exige `deleted_at is null`, e o PostgreSQL
-- aplica as policies de SELECT também sobre a LINHA RESULTANTE de um
-- UPDATE. A linha nova ficaria invisível para quem a alterou, então o
-- banco recusa com "new row violates row-level security policy" — para
-- qualquer usuário, administrador incluído.
--
-- É exatamente o mesmo problema que a migration 1800 já tinha resolvido
-- para o descarte de rascunho de orçamento. O cliente ficou de fora
-- porque ninguém tinha exercitado o botão "Excluir" da ficha do cliente
-- contra o banco real: o teste de cadastro cobria criar, editar e
-- desativar, não excluir. A suíte 20 fecha essa lacuna.
--
-- O que o usuário via: uma mensagem crua do PostgreSQL, em inglês, e o
-- cliente continuava na listagem.
--
-- SOLUÇÃO
--
-- A mesma da 1800: função `security definer` com a verificação de
-- permissão dentro. E, de quebra, a regra de negócio que só existia em
-- `service.ts` passa a valer também no banco — cliente com orçamento OU
-- com pedido não se exclui, se desativa. Uma regra escrita só na
-- aplicação não é uma regra: é uma sugestão.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

create or replace function public.delete_customer(p_customer_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer public.customers%rowtype;
  v_orcamentos int;
  v_pedidos    int;
begin
  select * into v_customer
    from public.customers
   where id = p_customer_id and deleted_at is null;

  if not found then
    raise exception 'Cliente não encontrado' using errcode = 'no_data_found';
  end if;

  -- `customers.delete` é do administrador (ver src/config/permissions.ts).
  if not public.is_admin() then
    raise exception 'Somente administrador pode excluir cliente'
      using errcode = 'insufficient_privilege';
  end if;

  -- Histórico comercial não some junto com o cadastro. Conta orçamento e
  -- pedido sem passar pelo RLS de propósito: o administrador precisa ser
  -- barrado pelo histórico do vendedor também, que ele nem sempre lê.
  select count(*)::int into v_orcamentos
    from public.quotes where customer_id = p_customer_id and deleted_at is null;

  select count(*)::int into v_pedidos
    from public.orders where customer_id = p_customer_id and deleted_at is null;

  if v_orcamentos > 0 or v_pedidos > 0 then
    raise exception
      'Este cliente tem % orçamento(s) e % pedido(s) registrados. Desative-o em vez de excluir, para preservar o histórico.',
      v_orcamentos, v_pedidos
      using errcode = 'foreign_key_violation';
  end if;

  update public.customers
     set deleted_at = now(),
         updated_by = auth.uid()
   where id = p_customer_id;

  return true;
end;
$$;

revoke execute on function public.delete_customer(uuid) from public, anon;
grant execute on function public.delete_customer(uuid) to authenticated;

comment on function public.delete_customer(uuid) is
  'Exclusao logica de cliente. Somente administrador; recusa se houver orcamento ou pedido. Existe porque UPDATE direto em deleted_at e recusado pela policy de SELECT.';
