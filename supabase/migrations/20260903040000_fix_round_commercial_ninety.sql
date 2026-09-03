-- ============================================================
-- 20260903040000 · Corrige o arredondamento "terminar em 90"
--
-- A migration 20260903020000 prometeu, no próprio comentário, que este
-- modo "nunca arredonda para baixo". A fórmula não cumpria:
--
--     ceil(v / 100) * 100 - 10
--
-- Para todo v na faixa (X00-10, X00] o `ceil` já está no patamar certo,
-- e o `- 10` derruba o resultado ABAIXO da entrada:
--
--       100  ->   90      191  ->  190
--      1291  -> 1290     1295  -> 1290     1300  -> 1290
--
-- São 10 valores em cada 100 — 10% do domínio. Numa varredura de 1 a
-- 5.000, 500 casos saíam abaixo do preço calculado. Não é canto raro:
-- preço fechado em centena redonda é justamente o caso comum.
--
-- A regra correta é o MENOR número terminado em 90 que seja maior ou
-- igual ao valor. Escrita como a intenção, não como um ajuste:
--
--     greatest(0, ceil((v - 90) / 100)) * 100 + 90
--
-- O `greatest(0, ...)` cobre v abaixo de 90, onde o `ceil` daria
-- negativo e o preço sairia menor que zero.
--
-- Nada precisa ser recalculado: a função é `immutable` e só é chamada
-- no momento de sugerir preço. Nenhum produto tinha preço definido por
-- ela quando esta correção foi escrita.
-- ============================================================

create or replace function public.round_commercial(p_value numeric, p_mode text)
returns numeric language sql immutable security invoker set search_path = ''
as $fn$
  select case p_mode
    when 'ten'     then ceil(p_value / 10)  * 10
    when 'hundred' then ceil(p_value / 100) * 100
    -- Menor valor terminado em 90 que seja >= p_value. Nunca abaixo.
    when 'ninety'  then greatest(0, ceil((p_value - 90) / 100)) * 100 + 90
    else round(p_value, 2)
  end;
$fn$;

revoke all on function public.round_commercial(numeric, text) from anon;

comment on function public.round_commercial(numeric, text) is
  'Arredondamento comercial. Os modos ten, hundred e ninety NUNCA devolvem valor abaixo da entrada — conferido por varredura em 16_margens.sql.';
