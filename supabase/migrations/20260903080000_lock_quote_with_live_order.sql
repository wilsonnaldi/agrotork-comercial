-- ============================================================
-- 0903080000 · Orçamento que virou pedido para de ser editável
--
-- Achado da homologação de 03/09/2026 (FASE D, defeito 1).
--
-- O pedido congela — isso já estava garantido pelo gatilho
-- `trg_orders_freeze`. Faltava o outro lado: o ORÇAMENTO que originou o
-- pedido continuava editável pelo administrador, e "Marcar como
-- Rascunho" seguia oferecido mesmo com o pedido vivo.
--
-- O estrago não é no pedido, é no rastro. `orders.quote_id` aponta para
-- o orçamento como prova do que foi vendido. Se esse orçamento pode ser
-- alterado depois, a prova deixa de provar: o pedido diz uma coisa, a
-- origem dele diz outra, e nada no sistema denuncia a divergência.
--
-- A regra que falta é simples de dizer: **orçamento com pedido vivo é
-- histórico, não rascunho.** Quem precisa mudar o que foi vendido
-- renegocia — que é o caminho que já existe e que cria documento novo.
--
-- "Vivo" exclui o cancelado de propósito: se o pedido foi cancelado, o
-- negócio não aconteceu, e o orçamento volta a ser um documento comum.
-- ============================================================

-- ── Existe pedido vivo para este orçamento? ─────────────────
-- `security definer` pelo mesmo motivo de `quote_is_editable`: quem
-- pergunta pode não enxergar o pedido pela RLS (um administrador
-- olhando orçamento de vendedor, por exemplo), e a resposta não pode
-- depender do alcance de quem pergunta — senão a trava valeria para uns
-- e não para outros.
create or replace function public.quote_has_live_order(p_quote_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
     where o.quote_id = p_quote_id
       and o.deleted_at is null
       and o.status::text <> 'cancelled'
  );
$$;

comment on function public.quote_has_live_order(uuid) is
  'Orçamento já fechado em pedido não cancelado. Enquanto for verdade, o orçamento é histórico: não se edita nem se reabre.';

revoke execute on function public.quote_has_live_order(uuid) from public, anon;
grant  execute on function public.quote_has_live_order(uuid) to authenticated, service_role;

-- ── A trava dos ITENS ───────────────────────────────────────
-- `quote_is_editable` é o que as policies de `quote_items` consultam
-- para INSERT, UPDATE e DELETE. Acrescentar a condição aqui fecha os
-- três de uma vez, para vendedor E administrador — o `is_admin()` que
-- existia antes deixava o administrador passar por cima.
--
-- O resto da função fica como estava: aprovado e cancelado continuam
-- travados para o vendedor, e o administrador continua podendo corrigir
-- um aprovado que NÃO virou pedido (que era a intenção da migration
-- 1700 e segue valendo).
create or replace function public.quote_is_editable(p_quote_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.quotes q
    where q.id = p_quote_id
      and q.deleted_at is null
      and not public.quote_has_live_order(q.id)
      and (
        public.is_admin()
        or (q.owner_id = auth.uid() and q.status::text not in ('approved', 'cancelled'))
      )
  );
$$;

-- ── A trava do CABEÇALHO ────────────────────────────────────
-- Travar só os itens deixaria passar o que dói igual: reabrir para
-- rascunho, trocar o desconto, mudar o frete ou trocar o cliente. Um
-- gatilho é o lugar certo — a policy de UPDATE precisa continuar
-- existindo para `deleted_at` e para os carimbos.
--
-- O que continua livre: `notes`, `internal_notes` e os campos de texto
-- das condições. Anotar algo no orçamento depois de fechado não
-- reescreve o que foi vendido.
create or replace function public.freeze_quote_with_live_order()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- pg_trigger_depth() > 1 deixa passar recalculate_quote_totals(), que
  -- roda por gatilho e reescreve subtotal/total legitimamente.
  if pg_catalog.pg_trigger_depth() > 1 then
    return new;
  end if;

  if not public.quote_has_live_order(new.id) then
    return new;
  end if;

  if new.status           is distinct from old.status
     or new.customer_id      is distinct from old.customer_id
     or new.discount_percent is distinct from old.discount_percent
     or new.discount_amount  is distinct from old.discount_amount
     or new.shipping_amount  is distinct from old.shipping_amount
     or new.subtotal         is distinct from old.subtotal
     or new.total            is distinct from old.total
     or new.issue_date       is distinct from old.issue_date
  then
    raise exception 'Este orcamento ja virou pedido e nao muda mais. Para alterar o que foi vendido, renegocie a partir do pedido.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function public.freeze_quote_with_live_order() from public, anon;

create trigger trg_quotes_freeze_with_order
  before update on public.quotes
  for each row execute function public.freeze_quote_with_live_order();

comment on function public.freeze_quote_with_live_order() is
  'Orçamento com pedido vivo não muda de situação nem de conteúdo comercial. Observações continuam editáveis.';
