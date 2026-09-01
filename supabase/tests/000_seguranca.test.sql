-- ============================================================
-- SUPERFÍCIE DE SEGURANÇA — pgTAP, contra o Supabase local.
--
--   npx supabase test db
--
-- O que este arquivo NÃO é: a suíte de comportamento. Aquela é uma
-- sequência encadeada (01 cria o usuário que 02 usa…) e roda em banco
-- descartável, com `npm run db:test` — ver supabase/db-tests/.
--
-- O que ele É: a conferência do que precisa estar VERDADEIRO no banco a
-- qualquer momento, sem depender de ordem nem de dado nenhum. Por isso é
-- idempotente por construção: só lê catálogo, não escreve linha alguma, e
-- pode rodar quantas vezes quiser sobre o banco local já povoado.
--
-- É aqui que vale rodar contra o Supabase de verdade: `storage` e `auth`
-- nativos, policies de verdade, privilégios de verdade.
-- ============================================================
begin;

-- pgTAP é o vocabulário deste arquivo. No Supabase local a extensão vem na
-- imagem mas nem sempre criada; criá-la aqui dentro é seguro porque a
-- transação inteira é desfeita no fim — nada fica no banco.
do $$
begin
  if to_regnamespace('extensions') is not null then
    execute 'create extension if not exists pgtap with schema extensions';
  else
    execute 'create extension if not exists pgtap';
  end if;
end $$;
set local search_path = public, extensions;

select plan(58);

-- ── 1. RLS ligado em toda tabela de negócio ─────────────────
-- Sem isto, qualquer policy vira decoração: o Postgres nem consulta.
select is(
  (select count(*)::int from pg_tables t
    where t.schemaname = 'public' and not t.rowsecurity
      and t.tablename in ('profiles','units','categories','brands','products','product_costs',
                          'customers','kits','kit_items','quotes','quote_items',
                          'quote_share_tokens','app_settings')),
  0,
  'RLS ligado em todas as 13 tabelas de negócio'
);

select ok(
  (select count(*)::int from pg_policies where schemaname = 'public'
     and tablename = t) > 0,
  format('tabela %s tem policy', t)
) from unnest(array['profiles','units','categories','brands','products','product_costs',
                    'customers','kits','kit_items','quotes','quote_items',
                    'quote_share_tokens','app_settings']) as t;

-- ── 2. Custo é dado de administrador ────────────────────────
-- A regra não pode depender da interface: TODA policy de product_costs
-- precisa passar por is_admin().
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='product_costs'
      and coalesce(qual,'') !~ 'is_admin' and coalesce(with_check,'') !~ 'is_admin'),
  0,
  'toda policy de product_costs exige is_admin()'
);

-- ── 3. Anônimo não alcança nada pelo RLS ────────────────────
-- O `grant` de tabela para `anon` é linha de base da plataforma Supabase e
-- não é o que protege — quem protege é a policy. Então é a policy que se
-- confere: no schema public NENHUMA alcança `anon`. O link do orçamento
-- não é exceção: ele passa por `get_shared_quote()` (security definer),
-- que decide pelo TOKEN, não por acesso direto à tabela.
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and roles::text[] && array['anon','public']),
  0,
  'nenhuma policy do schema public alcança anon — o link público passa por get_shared_quote()'
);

-- E o custo não tem policy alguma fora de is_admin(), nem para leitura.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='product_costs'
      and roles::text[] && array['anon','public']),
  0,
  'nenhuma policy de product_costs alcança anon'
);

-- ── 4. Funções privilegiadas ────────────────────────────────
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname = f limit 1),
  format('%s é security definer', f)
) from unnest(array['is_admin','is_active_user','owns_quote','quote_is_editable',
                    'discard_quote_draft','get_shared_quote','expire_quotes',
                    'next_quote_number','purge_test_products','auth_role']) as f;

-- O link público precisa funcionar sem login…
select ok(
  has_function_privilege('anon', 'public.get_shared_quote(text)', 'EXECUTE'),
  'anon pode executar get_shared_quote() — é o link público do orçamento'
);

-- …e nada além disso deve estar ao alcance de quem não é administrador.
select ok(
  not has_function_privilege('authenticated', 'public.expire_quotes()', 'EXECUTE'),
  'authenticated NÃO pode executar expire_quotes()'
);

-- ── Expiração automática (Fase 6.2) ─────────────────────────
-- O job roda como `postgres`, fora de qualquer sessão de usuário. O que
-- precisa continuar verdadeiro é o contorno dele: ninguém que venha do
-- navegador alcança a função, o `search_path` está preso, e o índice da
-- varredura diária existe.
select ok(
  not has_function_privilege('anon', 'public.expire_quotes()', 'EXECUTE'),
  'anon NÃO pode executar expire_quotes()'
);

select ok(
  not has_function_privilege('public', 'public.expire_quotes()', 'EXECUTE'),
  'PUBLIC NÃO pode executar expire_quotes()'
);

select ok(
  (select p.proconfig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='expire_quotes') @> array['search_path=public'],
  'expire_quotes() tem search_path fixo'
);

select ok(
  (select count(*)::int from pg_indexes
    where schemaname='public' and indexname='idx_quotes_expiration') = 1,
  'o índice parcial da expiração diária existe'
);
select ok(
  not has_function_privilege('authenticated', 'public.next_quote_number(integer)', 'EXECUTE'),
  'authenticated NÃO pode executar next_quote_number()'
);
select ok(
  not has_function_privilege('anon', 'public.purge_test_products()', 'EXECUTE'),
  'anon NÃO pode executar purge_test_products()'
);

-- ── 5. Numeração do orçamento é do banco ────────────────────
-- Se este trigger sumir, a aplicação passa a poder inventar número —
-- e a tipagem (TriggerOwned em src/types/db.ts) deixa de fazer sentido.
select ok(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.quotes'::regclass and not tgisinternal and tgname = 'trg_quotes_assign_number') = 1,
  'trg_quotes_assign_number existe em quotes'
);
select ok(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.quotes'::regclass and not tgisinternal and tgname = 'trg_quotes_stamp_status') = 1,
  'trg_quotes_stamp_status existe em quotes'
);
select ok(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.quote_items'::regclass and not tgisinternal and tgname = 'trg_quote_items_recalc') = 1,
  'trg_quote_items_recalc existe em quote_items'
);

-- Totais nunca negativos: a trava é do banco, não da tela.
select ok(
  (select count(*)::int from pg_constraint
    where conrelid='public.quotes'::regclass and contype='c'
      and conname in ('chk_quotes_subtotal_nonnegative','chk_quotes_total_nonnegative')) = 2,
  'quotes tem as duas travas de total não-negativo'
);

-- ── 6. Enums conforme as migrations ─────────────────────────
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname = 'quote_status'),
  array['draft','sent','approved','rejected','expired','cancelled'],
  'quote_status tem os seis valores, na ordem'
);
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname = 'kit_item_type'),
  array['required','optional'],
  'kit_item_type tem required e optional'
);
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname = 'user_role'),
  array['admin','salesperson'],
  'user_role tem admin e salesperson'
);

-- ── 7. Link compartilhado ───────────────────────────────────
select ok(
  (select count(*)::int from pg_indexes
    where schemaname='public' and tablename='quote_share_tokens'
      and indexdef ilike '%unique%' and indexdef ilike '%(token)%') >= 1,
  'token do link é único'
);
select ok(
  (select count(*)::int from pg_constraint
    where conrelid='public.quote_share_tokens'::regclass and contype='f' and confdeltype='c') >= 1,
  'token some junto com o orçamento (on delete cascade)'
);

-- ── 8. Storage ──────────────────────────────────────────────
-- Roda contra o Storage nativo quando ele existe; onde não existe (a
-- migration 2000 não faz nada num banco sem Storage), os testes se
-- declaram pulados em vez de reprovar.
select ok(
  to_regclass('storage.buckets') is null
    or (select public from storage.buckets where id = 'public-assets'),
  'bucket public-assets é público'
);
select ok(
  to_regclass('storage.buckets') is null
    or not (select public from storage.buckets where id = 'private-docs'),
  'bucket private-docs NÃO é público'
);
select ok(
  to_regclass('storage.buckets') is null
    or (select file_size_limit from storage.buckets where id='public-assets') = 5242880,
  'public-assets limita o arquivo a 5 MB'
);
select ok(
  to_regclass('storage.buckets') is null
    or (select bool_and(m like 'image/%')
          from storage.buckets b, unnest(b.allowed_mime_types) m where b.id='public-assets'),
  'public-assets só aceita imagem'
);
select ok(
  to_regclass('storage.objects') is null
    or (select count(*)::int from pg_policies
         where schemaname='storage' and tablename='objects'
           and policyname in ('public_assets_read','public_assets_write',
                              'public_assets_update','public_assets_delete',
                              'private_docs_read','private_docs_write')) = 6,
  'as seis policies de storage.objects existem'
);
-- Escrever no bucket público é coisa de administrador — em qualquer verbo.
select ok(
  to_regclass('storage.objects') is null
    or (select count(*)::int from pg_policies
         where schemaname='storage' and tablename='objects'
           and policyname in ('public_assets_write','public_assets_update','public_assets_delete')
           and coalesce(qual,'') !~ 'is_admin' and coalesce(with_check,'') !~ 'is_admin') = 0,
  'toda escrita em public-assets exige is_admin()'
);
select ok(
  to_regclass('storage.objects') is null
    or (select count(*)::int from pg_policies
         where schemaname='storage' and tablename='objects'
           and policyname like 'private_docs%'
           and coalesce(qual,'') !~ 'is_admin' and coalesce(with_check,'') !~ 'is_admin') = 0,
  'todo acesso a private-docs exige is_admin()'
);

-- ── 9. Nada de exclusão física por descuido ─────────────────
select ok(
  (select count(*)::int from information_schema.columns
    where table_schema='public' and column_name='deleted_at'
      and table_name in ('products','customers','kits','quotes','brands','categories')) = 6,
  'as seis tabelas com histórico têm deleted_at (exclusão lógica)'
);
select ok(
  (select confdeltype from pg_constraint
    where conrelid='public.quote_items'::regclass and contype='f'
      and conname like '%kit_id%' limit 1) = 'r',
  'quote_items.kit_id é on delete restrict — orçamento antigo não perde o kit'
);

-- ── 10. Cadastro não concede administrador ──────────────────
-- O trigger de `auth.users` é o único ponto que escreve em `profiles` sem
-- passar por RLS. Se ele voltar a ler o papel do metadata do cadastro,
-- qualquer signup vira administrador — ver migration 2100.
select ok(
  (select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='handle_new_user') !~ 'raw_user_meta_data\s*->>\s*''role''',
  'handle_new_user() NÃO lê ->>''role'' de raw_user_meta_data'
);
select ok(
  (select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='handle_new_user') ~ '''salesperson''',
  'handle_new_user() grava salesperson como literal'
);
select ok(
  (select count(*)::int from pg_trigger
    where tgrelid = 'auth.users'::regclass and not tgisinternal
      and tgname = 'trg_on_auth_user_created') = 1,
  'o trigger de criação de perfil continua instalado'
);
select is(
  (select column_default from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='role'),
  '''salesperson''::user_role',
  'profiles.role tem default salesperson'
);
-- A promoção continua barrada pelo RLS depois do cadastro.
select ok(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='profiles' and policyname='profiles_update_self'
      and coalesce(with_check,'') ~ 'auth_role') = 1,
  'profiles_update_self impede o usuário de mudar o próprio papel'
);

select * from finish();
rollback;
