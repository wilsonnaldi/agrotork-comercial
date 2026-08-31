-- ============================================================
-- 1900 · Link público do orçamento
--
-- Fase 5. A tabela `quote_share_tokens` já existia desde a migration
-- 0700, com token aleatório por default (`gen_random_bytes(24)` → 48
-- caracteres hex), `expires_at`, `revoked_at` e `view_count`. Foi
-- REAPROVEITADA inteira. O que faltava era o caminho de LEITURA.
--
-- O PROBLEMA
--
-- A página pública roda sem login, ou seja, como `anon`. O papel `anon`
-- não tem policy nenhuma em `quotes` nem em `quote_items` — de propósito,
-- desde a 0800. Abrir policies para `anon` seria a solução errada: bastaria
-- um erro de expressão para vazar a carteira inteira.
--
-- A SOLUÇÃO
--
-- Uma única função `security definer` que recebe o TOKEN, valida tudo e
-- devolve apenas os campos comerciais. O `anon` não ganha acesso a tabela
-- alguma: ganha acesso a uma função que só sabe responder sobre o
-- orçamento daquele token.
--
-- O que a função NUNCA devolve, por construção — as colunas nem são
-- selecionadas: `unit_cost_snapshot`, `internal_notes`, `owner_id`,
-- `customer_id`, ids internos, telefone e e-mail do cliente.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── 1. Índices de apoio ─────────────────────────────────────
-- A consulta pública é sempre "token válido, não revogado, não expirado".
create index if not exists idx_share_tokens_live
  on public.quote_share_tokens (quote_id, created_at desc)
  where revoked_at is null;

-- ── 2. Situações que podem ser compartilhadas ───────────────
-- Rascunho não circula: quem compartilha um rascunho está enviando a
-- proposta, e o sistema registra isso mudando o status (regra do ROADMAP,
-- aplicada no serviço). Cancelado e recusado não voltam a circular.
create or replace function public.quote_is_shareable(p_status public.quote_status)
returns boolean
language sql
immutable
as $$
  select p_status in ('sent', 'approved', 'expired');
$$;

comment on function public.quote_is_shareable(public.quote_status) is
  'Situações em que um orçamento pode ter link público. Rascunho vira "enviado" ao compartilhar; cancelado e recusado não circulam.';

-- ── 3. Leitura pública por token ────────────────────────────
create or replace function public.get_shared_quote(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_share public.quote_share_tokens%rowtype;
  v_quote public.quotes%rowtype;
  v_payload jsonb;
begin
  -- Token curto ou vazio nem chega ao banco de dados.
  if p_token is null or length(p_token) < 24 then
    return null;
  end if;

  select * into v_share from public.quote_share_tokens where token = p_token;
  if not found then return null; end if;
  if v_share.revoked_at is not null then return null; end if;
  if v_share.expires_at is not null and v_share.expires_at < now() then return null; end if;

  select * into v_quote from public.quotes where id = v_share.quote_id and deleted_at is null;
  if not found then return null; end if;
  if not public.quote_is_shareable(v_quote.status) then return null; end if;

  -- Contador de visualizações. É o único efeito colateral do acesso
  -- público: nada do conteúdo comercial é tocado.
  update public.quote_share_tokens
     set view_count = view_count + 1
   where id = v_share.id;

  select jsonb_build_object(
    'number',           v_quote.number,
    'status',           v_quote.status,
    'issue_date',       to_char(v_quote.issue_date, 'YYYY-MM-DD'),
    'valid_until',      to_char(v_quote.valid_until, 'YYYY-MM-DD'),
    'payment_terms',    v_quote.payment_terms,
    'delivery_terms',   v_quote.delivery_terms,
    'notes',            v_quote.notes,
    -- Dinheiro vai como TEXTO: `numeric` não sobrevive a um float de
    -- JavaScript, e o valor oficial do orçamento é o que está gravado.
    'subtotal',         v_quote.subtotal::text,
    'discount_percent', v_quote.discount_percent::text,
    'discount_amount',  v_quote.discount_amount::text,
    'shipping_amount',  v_quote.shipping_amount::text,
    'total',            v_quote.total::text,
    'owner_name',       (select full_name from public.profiles where id = v_quote.owner_id),
    'customer', (
      -- Só o que identifica o destinatário da proposta. Telefone e e-mail
      -- ficam de fora: um link público pode ser repassado a qualquer um.
      select jsonb_build_object(
        'name',     c.name,
        'document', c.document,
        'city',     c.city,
        'state',    c.state
      ) from public.customers c where c.id = v_quote.customer_id
    ),
    'items', coalesce((
      select jsonb_agg(item order by item_order)
      from (
        select qi.sort_order as item_order,
               jsonb_build_object(
                 'kind',              qi.kind,
                 'code',              qi.code_snapshot,
                 'name',              qi.name_snapshot,
                 'description',       qi.description_snapshot,
                 'unit',              qi.unit_snapshot,
                 'brand',             qi.brand_snapshot,
                 'image_url',         qi.image_url_snapshot,
                 'components',        qi.components_snapshot,
                 'quantity',          qi.quantity::text,
                 'unit_price',        qi.unit_price::text,
                 'discount_percent',  qi.discount_percent::text,
                 'line_total',        qi.line_total::text
               ) as item
        from public.quote_items qi
        where qi.quote_id = v_quote.id
      ) itens
    ), '[]'::jsonb),
    'company', coalesce((select value from public.app_settings where key = 'company'), '{}'::jsonb),
    -- Validade COMERCIAL vencida. É diferente do token expirado: o token
    -- expirado não abre; a proposta vencida abre com aviso.
    'commercially_expired',
      (v_quote.valid_until is not null and v_quote.valid_until < current_date)
  ) into v_payload;

  return v_payload;
end;
$$;

comment on function public.get_shared_quote(text) is
  'Leitura pública de orçamento por token. security definer para que `anon` não precise de policy em quotes/quote_items. Nunca devolve custo, observações internas nem ids.';

revoke execute on function public.get_shared_quote(text) from public;
grant  execute on function public.get_shared_quote(text) to anon, authenticated, service_role;

-- ── 4. Observações ──────────────────────────────────────────
--
-- A ESCRITA continua pela tabela, com o RLS de 0800
-- (`share_tokens_all`: administrador ou dono do orçamento). Gerar e
-- revogar link são operações de quem já está autenticado, então não
-- precisam de função privilegiada — e assim a policy continua sendo a
-- única autoridade sobre quem cria link para qual orçamento.
--
-- Revogar é `update ... set revoked_at = now()`: a linha continua visível
-- para o dono (a policy não filtra `revoked_at`), então não repete o
-- problema que a exclusão lógica de orçamento teve na migration 1800.
