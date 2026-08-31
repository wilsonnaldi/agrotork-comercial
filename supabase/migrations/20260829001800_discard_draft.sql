-- ============================================================
-- 1800 · Descartar rascunho de orçamento
--
-- PROBLEMA ENCONTRADO NA FASE 4
--
-- A policy `quotes_select` filtra `deleted_at is null` — é o que faz um
-- orçamento descartado sumir para todo mundo. Só que o PostgreSQL aplica
-- as policies de SELECT também sobre a LINHA RESULTANTE de um UPDATE: a
-- linha nova precisa continuar visível para quem a alterou.
--
-- Consequência: `update quotes set deleted_at = now()` era recusado com
-- "new row violates row-level security policy" para QUALQUER usuário,
-- administrador incluído. Não é limitação do duplê de teste — o mesmo
-- acontece no Supabase real. Ninguém tinha esbarrado nisso porque nenhum
-- módulo anterior fazia exclusão lógica de orçamento.
--
-- SOLUÇÃO
--
-- Uma função `security definer` que faz a verificação de permissão por
-- conta própria e então grava. Assim a policy de SELECT continua estrita
-- (o descartado some mesmo) e a exclusão lógica passa por um caminho
-- único, auditável, com a regra "só rascunho" dentro do banco — não só
-- na aplicação.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

create or replace function public.discard_quote_draft(p_quote_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quotes%rowtype;
begin
  select * into v_quote from public.quotes where id = p_quote_id and deleted_at is null;
  if not found then
    raise exception 'Orçamento não encontrado' using errcode = 'no_data_found';
  end if;

  -- A mesma regra da policy: administrador, ou o dono do orçamento.
  if not (public.is_admin() or v_quote.owner_id = auth.uid()) then
    raise exception 'Sem permissão para descartar este orçamento' using errcode = 'insufficient_privilege';
  end if;

  -- Só rascunho se descarta. O que já circulou vira `cancelled`, que
  -- preserva o histórico e continua visível.
  if v_quote.status <> 'draft' then
    raise exception 'Só rascunho pode ser descartado' using errcode = 'check_violation';
  end if;

  update public.quotes
     set deleted_at = now(),
         updated_by = auth.uid()
   where id = p_quote_id;

  return true;
end;
$$;

comment on function public.discard_quote_draft(uuid) is
  'Exclusão lógica de rascunho. Existe como security definer porque a policy de SELECT filtra deleted_at, e o PostgreSQL exige que a linha resultante de um UPDATE continue visível.';

revoke execute on function public.discard_quote_draft(uuid) from public, anon;
grant  execute on function public.discard_quote_draft(uuid) to authenticated, service_role;
