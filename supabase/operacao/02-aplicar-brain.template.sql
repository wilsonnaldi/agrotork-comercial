-- ============================================================
-- APLICAR A FASE 1 DO BRAIN — projeto nedmdkdhchkadijtdnja
--
-- ⚠ ESTE ARQUIVO É GERADO. Não edite.
--   Fonte:  supabase/operacao/02-aplicar-brain.template.sql
--   Gerador: supabase/operacao/gerar-consolidado.sh
--   Conferência: supabase/db-tests/conferir-operacao.sh regera e compara.
--
-- ── CAMINHO DE EXECUÇÃO: UM SÓ ──────────────────────────────
--
-- **SQL Editor do Supabase.** Cole este arquivo inteiro, de uma vez, e
-- rode. É por isso que ele é gerado com as migrations JÁ EMBUTIDAS: o
-- `\i` do psql não existe no editor, e manter os dois caminhos era ter
-- dois roteiros divergindo em silêncio.
--
-- Não use `psql -f` neste arquivo, não rode em pedaços e não use
-- `supabase db push` para esta aplicação: nenhum dos três põe aplicação,
-- validações e registro na MESMA transação, que é a garantia inteira
-- deste roteiro.
--
-- ── PRÉ-REQUISITOS, conferidos aqui dentro ──────────────────
--   · PostgreSQL 17 (produção é 17.6);
--   · as nove migrations de 09/09 já reconciliadas (roteiro 01);
--   · `instagram_curator` presente e registrado;
--   · `public.audit_capture()` no md5 conhecido;
--   · o schema `brain` ainda não existe;
--   · nenhuma versão do BRAIN registrada.
--
-- ── MODO DESACOPLADO ────────────────────────────────────────
--
-- Este deploy entra com as TRÊS PONTES DESABILITADAS. Os gatilhos são
-- criados (o código está aplicado e testado) e em seguida desligados por
-- 20260911200000. Nenhum processamento do BRAIN acontece dentro da
-- transação de orçamento ou de pedido.
--
-- A sincronização é periódica, por `brain.reconciliar_erp()` chamada
-- pelo pg_cron a cada minuto. O passo de agendar o cron vem DEPOIS do
-- COMMIT — ver supabase/operacao/05-agendar-reconciliacao.sql.
--
-- ── PÓS-CONDIÇÕES, conferidas aqui dentro ───────────────────
--   · 9 tabelas, todas com RLS; view `journey_entries` security_invoker;
--   · toda função com `search_path` vazio, nenhuma executável por `anon`,
--     nenhuma `immutable` indevida;
--   · 3 gatilhos em `public`, todos AFTER e todos DESABILITADOS;
--   · `audit_capture()` no md5 esperado DEPOIS da mudança;
--   · nenhum dado comercial existente alterado;
--   · fumaça COMPLETA do fluxo DESACOPLADO — orçamento → pedido sem
--     nenhum evento, reconciliação reproduzindo o fato, relatório vazio
--     — e sem resíduo.
--
-- Falhou qualquer uma? A exceção aborta a transação, e o COMMIT lá
-- embaixo é executado como ROLLBACK. Não há resgate: este roteiro não
-- usa `savepoint`.
-- ============================================================

begin;

-- ── Pré-condições ───────────────────────────────────────────
do $$
declare v_md5 text; v_versao int;
begin
  v_versao := current_setting('server_version_num')::int;
  if v_versao < 170000 or v_versao >= 180000 then
    raise exception 'Este roteiro foi ensaiado em PostgreSQL 17; aqui e % — PARADO.',
      current_setting('server_version');
  end if;

  if exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain JA EXISTE. Este roteiro e de primeira aplicacao — PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations where version like '2026090914%') then
    raise exception 'As nove migrations de 09/09 ainda estao com a versao errada. Rode 01-reconciliar-registro.sql antes — PARADO.';
  end if;

  if not exists (select 1 from pg_namespace where nspname = 'instagram_curator')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151115')
  or not exists (select 1 from supabase_migrations.schema_migrations where version = '20260910151534') then
    raise exception 'instagram_curator ausente ou sem registro — o banco nao e o que a auditoria descreveu. PARADO.';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations where version like '20260911%') then
    raise exception 'Alguma versao do BRAIN ja esta registrada — PARADO.';
  end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from '24fd65a7eb791b2e2644abe1b2ba876b' then
    raise exception 'public.audit_capture() esta em md5 % e a auditoria conferiu 24fd65a7eb791b2e2644abe1b2ba876b. Alguem a mudou depois; o diff semantico precisa ser refeito antes de sobrescrever — PARADO.', coalesce(v_md5, '(inexistente)');
  end if;

  raise notice 'Pre-condicoes conferidas: PostgreSQL %, registro reconciliado, audit_capture no md5 esperado.',
    current_setting('server_version');
end
$$;

-- @incluir supabase/migrations/20260911130000_brain_foundation.sql
-- @incluir supabase/migrations/20260911140000_brain_exclusoes.sql
-- @incluir supabase/migrations/20260911150000_brain_pontes.sql
-- @incluir supabase/migrations/20260911160000_brain_volatilidade.sql
-- @incluir supabase/migrations/20260911170000_brain_reconciliacao.sql
-- @incluir supabase/migrations/20260911180000_brain_dependentes.sql
-- @incluir supabase/migrations/20260911190000_brain_janela.sql
-- @incluir supabase/migrations/20260911200000_brain_desacoplado.sql
-- @incluir supabase/migrations/20260911210000_brain_fidelidade.sql

-- ── Fim de linha: CRLF vira LF antes de qualquer conferência ─
--
-- Este roteiro é COLADO no SQL Editor, de um arquivo que veio para uma
-- máquina Windows. O editor do navegador normaliza a quebra de linha para
-- CRLF, e como toda função aqui é definida dentro de `$$ … $$`, o `\r`
-- entra no CORPO da função. Não quebra nada — o parser trata `\r` como
-- espaço em branco — mas muda o texto, e com ele todo md5.
--
-- Medido em 11/09/2026, PostgreSQL 17.6: o mesmo `audit_capture()` dá
-- `ee2f5cd5…e2d9e` com LF e `54ffdb93…c0379` com CRLF. Foi exatamente
-- essa diferença que abortou a primeira tentativa em produção — a trava
-- funcionou, e pegou o que `.gitattributes` já avisava que pegaria.
--
-- A resposta certa NÃO é afrouxar a trava: é fazer o banco guardar o
-- texto auditado. `pg_get_functiondef()` devolve o `create or replace`
-- inteiro, com todos os atributos (volatilidade, security, search_path,
-- owner de execução); reexecutá-lo sem os `\r` reescreve a função
-- exatamente como ela seria se o arquivo tivesse chegado com LF. As
-- concessões e revogações sobrevivem: `create or replace` preserva ACL.
--
-- Se o roteiro chegou com LF, este bloco não encontra nada e não faz nada.
do $$
declare r record; v_n int := 0;
begin
  for r in
    select p.oid, n.nspname, p.proname
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where (n.nspname = 'brain'
            or (n.nspname = 'public' and p.proname = 'audit_capture'))
       and pg_catalog.strpos(p.prosrc, pg_catalog.chr(13)) > 0
     order by n.nspname, p.proname
  loop
    execute pg_catalog.replace(pg_catalog.pg_get_functiondef(r.oid), pg_catalog.chr(13), '');
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    raise notice 'Fim de linha: o roteiro chegou com CRLF (editor do Windows) e % funcao(oes) foram reescritas com LF, para o texto em producao ser o texto auditado.', v_n;
  else
    raise notice 'Fim de linha: LF, como no repositorio. Nada a normalizar.';
  end if;

  -- Nao pode sobrar nenhuma.
  if exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where (n.nspname = 'brain'
            or (n.nspname = 'public' and p.proname = 'audit_capture'))
       and pg_catalog.strpos(p.prosrc, pg_catalog.chr(13)) > 0
  ) then
    raise exception 'Sobrou CRLF no corpo de alguma funcao depois da normalizacao — PARADO.';
  end if;
end
$$;

-- ── Pós-condições estruturais ───────────────────────────────
do $$
declare
  v_tab int; v_rls int; v_pol int; v_fun int; v_sem_sp int; v_anon int;
  v_imut text; v_trig int; v_after int; v_ligados int; v_view text; v_md5 text; v_canais int;
begin
  select count(*) into v_tab from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'r';
  select count(*) into v_rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'r' and c.relrowsecurity;
  select count(*) into v_pol from pg_policies where schemaname = 'brain';
  select count(*) into v_fun from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain';
  select count(*) into v_sem_sp from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain'
     and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%';
  select count(*) into v_anon from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and has_function_privilege('anon', p.oid, 'execute');
  select string_agg(p.proname, ', ') into v_imut from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  select array_to_string(c.reloptions, ',') into v_view from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'brain' and c.relkind = 'v' and c.relname = 'journey_entries';
  select count(*) into v_trig from pg_trigger where tgname like 'trg_brain%';
  select count(*) into v_after from pg_trigger
   where tgname like 'trg_brain%' and (tgtype::int & 2) = 0;
  select count(*) into v_ligados from pg_trigger
   where tgname like 'trg_brain%' and tgenabled <> 'D';
  select count(*) into v_canais from brain.channels;

  if v_tab <> 9     then raise exception 'Esperava 9 tabelas no brain, vieram % — PARADO.', v_tab; end if;
  if v_rls <> 9     then raise exception 'Apenas % das 9 tabelas com RLS — PARADO.', v_rls; end if;
  if v_pol < 27     then raise exception 'Esperava ao menos 27 policies, vieram % — PARADO.', v_pol; end if;
  if v_sem_sp <> 0  then raise exception '% funcao(oes) do brain sem search_path fixo — PARADO.', v_sem_sp; end if;
  if v_anon <> 0    then raise exception '% funcao(oes) do brain executaveis por anon — PARADO.', v_anon; end if;
  if v_imut is not null then
    raise exception 'Funcao(oes) do brain declarada(s) IMMUTABLE sem ser: % — PARADO.', v_imut;
  end if;
  if has_schema_privilege('anon', 'brain', 'usage') then
    raise exception 'anon tem USAGE no schema brain — PARADO.';
  end if;
  if v_view is distinct from 'security_invoker=true' then
    raise exception 'A view journey_entries esta com reloptions "%" — PARADO.', coalesce(v_view, '(nenhuma)');
  end if;
  if v_trig <> 3    then raise exception 'Esperava 3 gatilhos do brain em public, vieram % — PARADO.', v_trig; end if;
  if v_after <> 3   then raise exception 'Algum gatilho do brain em public nao e AFTER — PARADO.'; end if;
  -- MODO DESACOPLADO: existem, e estao desligados.
  if v_ligados <> 0 then
    raise exception 'MODO DESACOPLADO violado: % ponte(s) HABILITADA(S). Nenhum codigo do BRAIN pode rodar dentro da transacao comercial — PARADO.', v_ligados;
  end if;
  if v_canais <> 12 then raise exception 'Esperava 12 canais semeados, vieram % — PARADO.', v_canais; end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from 'ee2f5cd583295c30fbe64eb81eec2d9e' then
    raise exception 'audit_capture() ficou em md5 % e o ensaio em PostgreSQL 17.6 deu ee2f5cd583295c30fbe64eb81eec2d9e — PARADO.', v_md5;
  end if;

  raise notice 'Estrutura conferida: 9 tabelas com RLS, % policies, % funcoes, 3 gatilhos AFTER e DESABILITADOS, 12 canais, audit_capture no md5 do ensaio.',
    v_pol, v_fun;
end
$$;

-- ── Fotografia do comercial, ANTES ──────────────────────────
-- Nenhum dado comercial existente pode ser alterado por este deploy. A
-- prova é o md5 do conteúdo das tabelas de negócio, tirado agora e
-- conferido no fim.
create temporary table deploy_comercial_antes on commit drop as
select 'customers'         as tabela, md5(coalesce(string_agg(t::text, '|' order by t::text), '')) as retrato from public.customers t
union all select 'products',          md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.products t
union all select 'quotes',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quotes t
union all select 'quote_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quote_items t
union all select 'orders',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.orders t
union all select 'order_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.order_items t
union all select 'stock_movements',   md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.stock_movements t
union all select 'financial_entries', md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.financial_entries t
union all select 'purchases',         md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.purchases t;

-- Reconciliar o ERP real antes da fumaca e preservar seu retrato integral.
-- O teste deve deixar zero residuo, sem apagar fatos comerciais reais.
select * from brain.reconciliar_erp();
do $$
begin
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'Reconciliação inicial deixou divergencias — PARADO.';
  end if;
  if exists (select 1 from brain.reconciliar_erp() where corrigidas <> 0) then
    raise exception 'Reconciliação inicial nao foi idempotente — PARADO.';
  end if;
end
$$;
create temporary table deploy_eventos_reais_antes on commit drop as
select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb) as retrato,
       count(*) as quantidade
from brain.events e;

-- ── Fumaça do fluxo DESACOPLADO, e sem resíduo ──────────────
-- Exercita o caminho que produção vai usar de verdade:
--
--   1. o ERP faz a venda inteira — orçamento, itens, enviado, aprovado,
--      pedido — e o BRAIN NÃO é tocado: zero eventos novos, oportunidade
--      parada, lead não convertido. É isso que "desacoplado" significa;
--   2. `divergencias_erp()` enxerga o que ficou para trás;
--   3. `reconciliar_erp()` reproduz o fato: evento, vínculo, venda
--      ganha, lead convertido;
--   4. `divergencias_erp()` volta VAZIO;
--   5. remove os dados do teste e prova que os eventos reais ficaram intactos.
--
-- Num bloco só, sem `savepoint`: `rollback to savepoint` RESGATA uma
-- transação abortada, e uma fumaça que falhasse deixaria de impedir o
-- COMMIT. Aqui, qualquer assertiva que falhe aborta e o COMMIT lá
-- embaixo é executado como ROLLBACK.
--
-- Permanecem os eventos do ERP real reconciliados antes do teste e as linhas de
-- `public.audit_log` que ela gerou. É append-only por projeto — e é
-- correto que o log registre que a fumaça aconteceu.
do $$
declare
  v_cli uuid; v_admin uuid; v_unidade uuid;
  v_lead uuid; v_quote uuid; v_order uuid; v_prod uuid; v_opp uuid;
  v_total numeric; v_evento numeric;
  v_div int; v_sobrou int; r record; v_corrigidas int := 0;
begin
  select id into v_cli   from public.customers where deleted_at is null order by created_at limit 1;
  select id into v_admin from public.profiles  where role = 'admin'     order by created_at limit 1;
  select id into v_unidade from public.units   where code = 'UN';
  if v_cli is null or v_admin is null or v_unidade is null then
    raise exception 'Fumaca sem cliente, administrador ou unidade UN cadastrados — PARADO.';
  end if;

  insert into public.products (code, name, unit_id, sale_price)
   values ('FUMACA-DEPLOY', 'Produto da fumaca (sera apagado)', v_unidade, 1000.00)
   returning id into v_prod;

  -- O lead e a oportunidade são do CRM, não do ERP: entram direto.
  select lead_id into v_lead
    from brain.find_or_create_lead('Fumaca do deploy (sera apagada)', null, null, null, 'other');
  if v_lead is null then raise exception 'find_or_create_lead nao devolveu lead — PARADO.'; end if;

  insert into public.quotes (customer_id, owner_id) values (v_cli, v_admin) returning id into v_quote;

  insert into brain.opportunities (lead_id, quote_id, title, channel_key, customer_id)
   values (v_lead, v_quote, 'Fumaca do deploy', 'other', v_cli) returning id into v_opp;

  insert into public.quote_items (quote_id, product_id, name_snapshot, code_snapshot,
                                  quantity, unit_price, sort_order)
   values (v_quote, v_prod, 'Produto da fumaca (sera apagado)', 'FUMACA-DEPLOY', 2, 1000.00, 1);

  update public.quotes set status = 'sent'     where id = v_quote;
  update public.quotes set status = 'approved' where id = v_quote;

  v_order := public.create_order_from_quote(v_quote);

  -- ── 1. Com as pontes desligadas, o BRAIN não soube de nada ─
  -- `set constraints` continua aqui de propósito: se alguém religar a
  -- ponte do pedido, o gatilho diferido dispararia AQUI e a assertiva
  -- abaixo pegaria — é a rede de segurança do modo desacoplado.
  execute 'set constraints public.trg_brain_orders_created immediate';

  select total into v_total from public.orders where id = v_order;
  if (select count(*) from brain.events) <> (select quantidade from deploy_eventos_reais_antes) then
    raise exception 'MODO DESACOPLADO violado: a ponte publicou % evento(s) dentro da transacao comercial — PARADO.',
      (select count(*) from brain.events) - (select quantidade from deploy_eventos_reais_antes);
  end if;
  if (select stage from brain.opportunities where id = v_opp) <> 'prospecting' then
    raise exception 'MODO DESACOPLADO violado: a oportunidade mudou de estagio dentro da transacao comercial — PARADO.';
  end if;
  if (select status from brain.leads where id = v_lead) = 'converted' then
    raise exception 'MODO DESACOPLADO violado: o lead foi convertido dentro da transacao comercial — PARADO.';
  end if;

  raise notice 'Fumaca 1/4: venda concluida (pedido %, total %) SEM nenhum evento novo no BRAIN — as pontes estao mesmo desligadas.',
    (select number from public.orders where id = v_order), v_total;

  -- ── 2. O relatório enxerga o que ficou para trás ───────────
  select count(*) into v_div from brain.divergencias_erp();
  if v_div = 0 then
    raise exception 'A reconciliacao nao viu a venda que acabou de acontecer — PARADO.';
  end if;
  raise notice 'Fumaca 2/4: divergencias_erp() acusou % pendencia(s).', v_div;

  -- ── 3. A reconciliação reproduz o fato ────────────────────
  for r in select * from brain.reconciliar_erp() loop
    v_corrigidas := v_corrigidas + r.corrigidas;
  end loop;

  select (payload ->> 'total')::numeric into v_evento
    from brain.events where event_name = 'order.created' and payload ->> 'order_id' = v_order::text;

  if v_evento is null then
    raise exception 'A reconciliacao nao publicou order.created — PARADO.';
  end if;
  if v_evento <> v_total then
    raise exception 'Evento com total % e pedido com total % — PARADO.', v_evento, v_total;
  end if;
  if (select stage from brain.opportunities where id = v_opp) <> 'won' then
    raise exception 'A reconciliacao nao marcou a venda como ganha (%) — PARADO.',
      (select stage from brain.opportunities where id = v_opp);
  end if;
  if (select status from brain.leads where id = v_lead) <> 'converted' then
    raise exception 'A reconciliacao nao converteu o lead (%) — PARADO.',
      (select status from brain.leads where id = v_lead);
  end if;
  if (select order_id from brain.opportunities where id = v_opp) is distinct from v_order then
    raise exception 'A reconciliacao nao ligou o pedido a oportunidade — PARADO.';
  end if;

  raise notice 'Fumaca 3/4: reconciliacao corrigiu % coisa(s) — evento com total % = pedido, venda ganha, lead convertido, pedido ligado.',
    v_corrigidas, v_evento;

  -- ── 4. O relatório volta vazio ────────────────────────────
  select count(*) into v_div from brain.divergencias_erp();
  if v_div <> 0 then
    raise exception 'Depois de reconciliar ainda sobraram % divergencia(s) — PARADO.', v_div;
  end if;
  raise notice 'Fumaca 4/4: divergencias_erp() vazio.';

  -- ── Desfazer, tudo ────────────────────────────────────────
  alter table brain.events disable trigger trg_events_immutable;
  delete from brain.events
   where payload ->> 'quote_id' = v_quote::text or payload ->> 'order_id' = v_order::text;
  alter table brain.events enable trigger trg_events_immutable;

  delete from public.order_items where order_id = v_order;
  delete from public.orders      where id = v_order;
  delete from public.quote_items where quote_id = v_quote;
  delete from public.quotes      where id = v_quote;
  delete from brain.opportunities where id = v_opp;
  delete from brain.leads         where id = v_lead;
  delete from public.products     where id = v_prod;

  select (select count(*) from brain.leads)
       + (select count(*) from brain.identities)
       + (select count(*) from brain.interactions)
       + (select count(*) from brain.opportunities)
       + (select count(*) from brain.tasks)
       + (select count(*) from brain.events where payload ->> 'quote_id' = v_quote::text or payload ->> 'order_id' = v_order::text)
       + (select count(*) from brain.lead_merges)
       + (select count(*) from brain.attributions)
    into v_sobrou;
  if (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb) from brain.events e)
     is distinct from (select retrato from deploy_eventos_reais_antes) then
    raise exception 'A fumaca alterou os eventos reais ou deixou eventos adicionais — PARADO.';
  end if;
  if v_sobrou <> 0 then
    raise exception 'A fumaca deixou % linha(s) no BRAIN — PARADO.', v_sobrou;
  end if;
  if exists (select 1 from public.quotes where id = v_quote)
  or exists (select 1 from public.orders where id = v_order)
  or exists (select 1 from public.products where code = 'FUMACA-DEPLOY') then
    raise exception 'A fumaca deixou orcamento, pedido ou produto de teste em producao — PARADO.';
  end if;
  if (select count(*) from brain.channels) <> 12 then
    raise exception 'A fumaca mexeu na semente de canais — PARADO.';
  end if;

  raise notice 'Fumaca desfeita: zero residuo de teste, eventos reais preservados integralmente, 12 canais intactos.';
end
$$;

-- ── O comercial não mudou ───────────────────────────────────
do $$
declare v_dif text;
begin
  with agora as (
    select 'customers' as tabela, md5(coalesce(string_agg(t::text, '|' order by t::text), '')) as retrato from public.customers t
    union all select 'products',          md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.products t
    union all select 'quotes',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quotes t
    union all select 'quote_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.quote_items t
    union all select 'orders',            md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.orders t
    union all select 'order_items',       md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.order_items t
    union all select 'stock_movements',   md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.stock_movements t
    union all select 'financial_entries', md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.financial_entries t
    union all select 'purchases',         md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from public.purchases t
  )
  select string_agg(a.tabela, ', ') into v_dif
    from deploy_comercial_antes a join agora g on g.tabela = a.tabela
   where a.retrato is distinct from g.retrato;

  if v_dif is not null then
    raise exception 'O deploy ALTEROU dado comercial em: % — PARADO.', v_dif;
  end if;
  raise notice 'Dado comercial intacto: as 9 tabelas de negocio com o mesmo retrato de antes do deploy.';
end
$$;

-- ── Registro, no mesmo COMMIT da aplicação ──────────────────
insert into supabase_migrations.schema_migrations (version, name) values
 ('20260911130000', 'brain_foundation'),
 ('20260911140000', 'brain_exclusoes'),
 ('20260911150000', 'brain_pontes'),
 ('20260911160000', 'brain_volatilidade'),
 ('20260911170000', 'brain_reconciliacao'),
 ('20260911180000', 'brain_dependentes'),
 ('20260911190000', 'brain_janela'),
 ('20260911200000', 'brain_desacoplado'),
 ('20260911210000', 'brain_fidelidade');

do $$
begin
  -- Lista explícita: `like '202609111%'` não pegava 20260911200000 nem
  -- 20260911210000, e o número conferido seria sempre o errado.
  if (select count(*) from supabase_migrations.schema_migrations
       where version in ('20260911130000','20260911140000','20260911150000',
                         '20260911160000','20260911170000','20260911180000',
                         '20260911190000','20260911200000','20260911210000')) <> 9 then
    raise exception 'O registro das nove versoes do BRAIN nao fechou — PARADO.';
  end if;
  if exists (select 1 from brain.divergencias_erp()) then
    raise exception 'O relatorio de divergencias ja nasce com pendencia — PARADO.';
  end if;
  raise notice 'Registro gravado e relatorio de divergencias vazio. Pronto para COMMIT.';
end
$$;

commit;

-- Depois do COMMIT: rode os advisors de seguranca e de desempenho e
-- compare com a lista de antes. Caminho de volta: 03 (logo apos, sem
-- nada dentro) ou 04 (com dado real).
