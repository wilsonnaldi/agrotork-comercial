-- ============================================================
-- 1400 · Correção: referência do item de orçamento vs. exclusão
--
-- Defeito encontrado pelo teste `06_origem_produto.sql`.
--
-- `quote_items.product_id` é `on delete set null` — de propósito: o item
-- guarda cópia congelada do nome, do código e do preço, então o orçamento
-- sobrevive ao desaparecimento do produto. Só que a constraint original
-- exigia o contrário:
--
--   check ((kind = 'product' and product_id is not null) or ...)
--
-- Resultado: apagar um produto referenciado por qualquer orçamento
-- falhava com violação de check, porque o `set null` da FK esbarrava
-- nela. Isso valia para a limpeza da massa de teste e valeria para
-- qualquer exclusão futura.
--
-- A invariante que realmente importa não é "item de produto tem
-- product_id" — o `name_snapshot` já é `not null` e é o que aparece no
-- PDF. O que precisa ser garantido é que o item não aponte para a coisa
-- errada: um item de produto não pode referenciar um kit, e vice-versa.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

alter table public.quote_items
  drop constraint if exists chk_quote_item_reference;

alter table public.quote_items
  add constraint chk_quote_item_reference check (
    (kind = 'product' and kit_id is null)
    or (kind = 'kit'   and product_id is null)
    or (kind = 'custom' and product_id is null and kit_id is null)
  );

comment on constraint chk_quote_item_reference on public.quote_items is
  'Impede referência cruzada (item de produto apontando para kit e vice-versa). A referência pode ficar nula quando o cadastro de origem é excluído — o snapshot é a fonte de verdade do orçamento.';
