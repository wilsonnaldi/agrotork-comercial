-- ============================================================
-- 1700 · Orçamentos: cancelamento, prazo de entrega e travas
--
-- Fase 4. A estrutura de `quotes` e `quote_items` já existia desde a
-- migration 0600 e foi REAPROVEITADA inteira — numeração automática,
-- snapshots, `line_total` gerado, recálculo por trigger. Faltavam três
-- coisas para o módulo funcionar de ponta a ponta.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── 1. Status `cancelled` ───────────────────────────────────
-- `rejected` é "o cliente disse não". `cancelled` é "nós desistimos" —
-- desistência interna, engano, cliente sumiu. São coisas diferentes e
-- viram relatório diferente. Precisa ser o primeiro comando do arquivo:
-- um valor novo de enum não pode ser usado na mesma transação em que
-- foi criado.
alter type public.quote_status add value if not exists 'cancelled';

-- ATENÇÃO ao comparar `quote_status` daqui para baixo: o PostgreSQL recusa
-- usar um valor de enum recém-adicionado dentro da MESMA transação em que
-- o `alter type` rodou ("unsafe use of new value of enum type"). O
-- `supabase db push` aplica cada migration em uma transação, então as
-- comparações abaixo convertem para texto (`status::text`) de propósito.
-- Não "limpe" esses casts: eles são o que faz esta migration aplicar.

-- ── 2. Prazo de entrega ─────────────────────────────────────
-- `payment_terms` já existia; a condição comercial completa também
-- precisa do prazo. Texto livre de propósito: "15 dias", "imediato",
-- "conforme disponibilidade" — não é campo calculável.
alter table public.quotes add column if not exists delivery_terms text;

comment on column public.quotes.delivery_terms is
  'Prazo de entrega combinado. Texto livre, sai no orçamento junto com payment_terms.';

-- ── 3. Totais nunca negativos ───────────────────────────────
-- `recalculate_quote_totals` já usa `greatest(..., 0)`, e cada
-- `line_total` é gerado a partir de quantidade > 0, preço >= 0 e
-- desconto entre 0 e 100 — então subtotal e total já não podem ficar
-- negativos. As restrições abaixo transformam isso em garantia do
-- banco, em vez de consequência de três cálculos que precisam continuar
-- certos para sempre.
alter table public.quotes
  add constraint chk_quotes_subtotal_nonnegative check (subtotal >= 0),
  add constraint chk_quotes_total_nonnegative    check (total    >= 0);

-- ── 4. Itens de orçamento cancelado também congelam ─────────
-- `quote_is_editable` (migration 1100) travava os itens do orçamento
-- APROVADO para o vendedor. Cancelado precisa da mesma trava: enquanto
-- estiver cancelado, a composição não muda. Reabrir para rascunho
-- devolve a edição — o que é operação sobre `quotes`, não sobre os itens.
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
      and (
        public.is_admin()
        or (q.owner_id = auth.uid() and q.status::text not in ('approved', 'cancelled'))
      )
  );
$$;

revoke execute on function public.quote_is_editable(uuid) from public;
grant  execute on function public.quote_is_editable(uuid) to authenticated, service_role;

-- ── 5. O dono pode reabrir um orçamento cancelado ───────────
-- A policy de 0800 listava os status em que o vendedor podia mexer no
-- próprio orçamento. `cancelled` não existia então; sem isto, cancelar
-- seria irreversível para quem não é administrador.
drop policy if exists quotes_update on public.quotes;

create policy quotes_update on public.quotes
  for update to authenticated
  using (
    deleted_at is null and (
      public.is_admin()
      or (owner_id = auth.uid() and status::text in ('draft','sent','rejected','expired','cancelled'))
    )
  )
  with check (
    public.is_admin() or (owner_id = auth.uid())
  );

comment on policy quotes_update on public.quotes is
  'Aprovado só o administrador altera. O dono mexe nos demais status, inclusive para reabrir um cancelado.';

-- ── 6. Índice da listagem ───────────────────────────────────
-- A tela do vendedor é sempre "meus orçamentos, mais recentes primeiro".
create index if not exists idx_quotes_owner_issue
  on public.quotes (owner_id, issue_date desc) where deleted_at is null;

-- ── Observações sobre o que NÃO mudou ───────────────────────
--
-- `unit_cost_snapshot` continua sendo gravado como NULO. Preencher o
-- custo do item exporia o custo ao vendedor: `quote_items` é legível por
-- quem é dono do orçamento, e o PostgreSQL não filtra COLUNA por papel de
-- aplicação — foi exatamente o motivo de o custo ter ido para
-- `product_costs` na migration 1200. Capturar custo histórico para
-- relatório de margem exigirá o mesmo tratamento (tabela própria, RLS de
-- admin) e é decisão da fase de relatórios, não desta.
--
-- Os totais continuam sendo calculados pelo BANCO:
-- `line_total` é coluna gerada, e `recalculate_quote_totals` roda por
-- trigger a cada mudança de item ou de desconto. A aplicação nunca envia
-- subtotal nem total — não existe caminho para o navegador decidir preço.
