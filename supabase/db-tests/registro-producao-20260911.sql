-- ============================================================
-- Retrato do registro de migrations de produção em 11/09/2026.
--
-- Lido do catálogo do projeto nedmdkdhchkadijtdnja (somente leitura) e
-- versionado aqui para que o ensaio da reconciliação rode contra o
-- estado REAL, não contra um estado imaginado. As nove linhas com
-- versão `2026090914…` são o defeito que o script vem corrigir.
--
-- `statements` entra como um TRECHO: o ensaio precisa dele para exercer a
-- conferência de conteúdo por marca, mas carregar os 200 KB de SQL real
-- não provaria nada a mais. Para as nove linhas defeituosas guarda-se a
-- marca de cada uma — o nome do objeto que só aquela migration cria, e
-- que foi conferido presente em produção em 11/09 (leitura).
-- ============================================================
create schema if not exists supabase_migrations;

create table supabase_migrations.schema_migrations (
  version         text primary key,
  statements      text[],
  name            text,
  created_by      text,
  idempotency_key text,
  rollback        text[]
);

insert into supabase_migrations.schema_migrations (version, name) values
 ('20260829000100', 'extensions'),
 ('20260829000200', 'enums_helpers'),
 ('20260829000300', 'profiles'),
 ('20260829000400', 'catalog'),
 ('20260829000500', 'kits'),
 ('20260829000600', 'quotes'),
 ('20260829000700', 'sharing_settings'),
 ('20260829000800', 'rls'),
 ('20260829000900', 'seed'),
 ('20260829001000', 'grants'),
 ('20260829001100', 'rls_hardening'),
 ('20260829001200', 'product_costs'),
 ('20260829001300', 'product_origin'),
 ('20260829001400', 'quote_item_reference'),
 ('20260829001500', 'catalog_registers'),
 ('20260829001600', 'kit_item_type'),
 ('20260829001700', 'quotes_workflow'),
 ('20260829001800', 'discard_draft'),
 ('20260829001900', 'quote_sharing'),
 ('20260829002000', 'storage'),
 ('20260831002100', 'signup_role_hardening'),
 ('20260901052518', 'revoke_trigger_function_execute'),
 ('20260901052525', 'expire_quotes_schedule'),
 ('20260901055000', 'reconciliar_comentarios_expiracao'),
 ('20260901060000', 'audit_log'),
 ('20260901190230', 'harden_function_search_path_and_rls_policies'),
 ('20260901190334', 'harden_remaining_function_search_paths'),
 ('20260901191225', 'harden_quote_sequence_access'),
 ('20260901193812', 'revoke_anon_public_table_access'),
 ('20260901193926', 'harden_remaining_security_definer_search_path'),
 ('20260901194546', 'move_extensions_out_of_public'),
 ('20260901195103', 'revoke_anon_trigger_function_execute'),
 ('20260901201459', 'enforce_quote_status_and_active_rls'),
 ('20260901211122', 'protect_quote_totals_from_direct_updates'),
 ('20260901211340', 'enforce_active_user_on_quote_items'),
 ('20260901214750', 'consolidate_permissive_rls_policies'),
 ('20260902120000', 'price_conditions'),
 ('20260902120100', 'sale_price_defined'),
 ('20260903020000', 'margin_rules'),
 ('20260903040000', 'fix_round_commercial_ninety'),
 ('20260903060000', 'orders'),
 ('20260903080000', 'lock_quote_with_live_order'),
 ('20260909143542', '20260903100000_suppliers'),
 ('20260909143713', '20260903110000_excluir_cliente'),
 ('20260909143758', '20260903120000_estoque'),
 ('20260909143830', '20260903130000_numeros_de_serie'),
 ('20260909143930', '20260903140000_compras'),
 ('20260909144028', '20260903150000_financeiro'),
 ('20260909144051', '20260903160000_importacao_nfe'),
 ('20260909144232', '20260909100000_guards_orcamentos_pedidos'),
 ('20260909144344', '20260909110000_guards_onda2'),
 ('20260910151115', 'create_private_instagram_curator'),
 ('20260910151534', 'harden_private_instagram_curator');

-- As nove linhas defeituosas, com a marca de conteúdo que o roteiro 01
-- confere. Conferido em produção (leitura) em 11/09/2026: a marca de cada
-- uma está presente no `statements` real.
update supabase_migrations.schema_migrations set statements = array['-- trecho de ensaio: ' || m.marca]
  from (values
    ('20260909143542','suppliers'),
    ('20260909143713','delete_customer'),
    ('20260909143758','stock_movements'),
    ('20260909143830','product_serials'),
    ('20260909143930','purchase_items'),
    ('20260909144028','financial_entries'),
    ('20260909144051','remember_supplier_product'),
    ('20260909144232','protect_quote_control_columns'),
    ('20260909144344','block_purchase_item_move')
  ) as m(v, marca)
 where supabase_migrations.schema_migrations.version = m.v;
