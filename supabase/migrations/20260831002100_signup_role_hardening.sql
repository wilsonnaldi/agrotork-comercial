-- ============================================================
-- 2100 · Papel de administrador não se concede no cadastro
--
-- PROBLEMA
-- `handle_new_user` (migration 0300) montava o perfil assim:
--
--   coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'salesperson')
--
-- `raw_user_meta_data` é o campo `data` do signup: quem se cadastra escreve
-- o conteúdo. A URL do projeto e a chave `anon` viajam no navegador — como
-- devem, o RLS é que protege. Mas o trigger é `security definer` e roda
-- FORA do RLS: um `signup` com `data: {"role": "admin"}` nascia
-- administrador, e administrador enxerga custo, margem e todo orçamento.
--
-- O RLS nunca foi o furo: `profiles_update_self` (migrations 0800 e 1100)
-- já recusa promoção depois, com `role = public.auth_role()`. O furo era o
-- INSERT, no único ponto do sistema que escreve em `profiles` sem passar
-- por policy.
--
-- CORREÇÃO
-- O trigger deixa de ler `role`. Todo usuário criado pelo Auth nasce
-- `salesperson`, venha o metadata que vier. Promover é operação separada e
-- deliberada — `update public.profiles set role = 'admin'`, que só um
-- administrador consegue fazer (policy `profiles_admin_all`) ou quem tem
-- acesso ao SQL Editor do projeto. É exatamente o que o SETUP.md §5.3 já
-- manda fazer, então nenhum procedimento documentado muda.
--
-- `full_name` continua vindo do metadata: é rótulo de exibição, não
-- privilégio. `is_active` continua no default da tabela (true), e o
-- `on conflict (id) do nothing` continua protegendo reprocessamento.
--
-- Nenhuma migration anterior foi alterada. Nenhum perfil existente é
-- tocado: quem já é administrador continua administrador.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `role` é gravado como literal de propósito. Não existe caminho, aqui,
  -- para um valor vindo do usuário virar papel — nem por metadata, nem por
  -- payload de signup, nem por claim de JWT.
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'salesperson'::public.user_role
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Cria o perfil do usuário do Auth. SEMPRE como salesperson: papel não se '
  'concede por metadata de cadastro. Promoção é operação de administrador.';

-- O trigger de 0300 continua o mesmo e passa a executar esta versão.
