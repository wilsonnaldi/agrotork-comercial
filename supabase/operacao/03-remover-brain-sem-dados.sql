-- ============================================================
-- REMOVER O BRAIN LOGO APÓS O DEPLOY — e só se não houver NADA dentro
--
-- Caminho de volta para a janela curta entre o COMMIT e o primeiro uso.
-- Ele APAGA o schema `brain` inteiro, então só roda se provar que não há
-- nada a perder.
--
-- ── O QUE MUDOU NA v5 ───────────────────────────────────────
--
-- A versão anterior tolerava eventos com `source = 'erp'`, tratando-os
-- como "reconstituíveis". Não são: um `order.created` é o registro de uma
-- venda que aconteceu, com total, número e horário. Agora **qualquer
-- linha** nas nove tabelas — evento do ERP incluído — barra a remoção. O
-- único conteúdo tolerado é a semente de 12 canais, que a própria
-- migration criou.
--
-- E a detecção de dependentes deixou de olhar só tabela. Agora usa
-- `brain.dependentes_externos()` (catálogo: view, FK, policy, default,
-- gatilho, função de corpo padrão) e `brain.funcoes_que_citam_brain()`
-- (texto: função clássica e plpgsql, que o catálogo não registra).
--
-- COMO RODAR: `psql -v ON_ERROR_STOP=1 -f` este arquivo. Ver
-- supabase/operacao/README.md.
-- ============================================================

-- Sem `\set ON_ERROR_STOP`: aquilo é meta-comando do psql e o SQL Editor
-- não entende. Não faz falta — este roteiro é UMA transação, e qualquer
-- exceção aborta tudo; o `commit` lá embaixo executa como `rollback`.
begin;

-- ── Só se não houver NADA a perder ──────────────────────────
do $$
declare
  v_leads int; v_inter int; v_opp int; v_tasks int; v_ident int;
  v_merges int; v_attr int; v_eventos int; v_canais int;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe — nada a remover. PARADO.';
  end if;
  -- A Fase 2 mora no mesmo schema. Se o Lote A (memoria corporativa) estiver
  -- aplicado, derrubar o schema levaria as sete tabelas dele junto, e este
  -- roteiro so confere as nove da Fase 1. Primeiro 06-remover-memoria-sem-dados.sql.
  if to_regclass('brain.document_chunks') is not null then
    raise exception 'A memoria corporativa (Fase 2, Lote A) esta aplicada neste schema. Rode 06-remover-memoria-sem-dados.sql antes. PARADO.';
  end if;

  select count(*) into v_leads   from brain.leads;
  select count(*) into v_inter   from brain.interactions;
  select count(*) into v_opp     from brain.opportunities;
  select count(*) into v_tasks   from brain.tasks;
  select count(*) into v_ident   from brain.identities;
  select count(*) into v_merges  from brain.lead_merges;
  select count(*) into v_attr    from brain.attributions;
  select count(*) into v_eventos from brain.events;
  select count(*) into v_canais  from brain.channels;

  if v_leads + v_inter + v_opp + v_tasks + v_ident + v_merges + v_attr + v_eventos > 0 then
    raise exception
      'O BRAIN TEM CONTEUDO: % lead(s), % interacao(oes), % oportunidade(s), % tarefa(s), % identidade(s), % fusao(oes), % atribuicao(oes), % EVENTO(S). Evento do ERP e o registro de uma venda que aconteceu — nao e descartavel. Use 04-incidente-com-dados.sql. PARADO.',
      v_leads, v_inter, v_opp, v_tasks, v_ident, v_merges, v_attr, v_eventos;
  end if;

  -- Os 12 canais são semente da própria migration, não uso.
  if v_canais <> 12 then
    raise exception 'brain.channels tem % linha(s) e a semente sao 12 — alguem mexeu. PARADO.', v_canais;
  end if;

  raise notice 'Nove tabelas vazias e os 12 canais de semente. Nada a perder.';
end
$$;

-- ── Quem depende do schema, pelas duas peneiras ─────────────
do $$
declare v_estranho text; v_texto text; v_trig int;
begin
  select string_agg(dependente, E'\n    ' order by dependente) into v_estranho
    from brain.dependentes_externos()
   where dependente not in ('trigger trg_brain_quotes on table public.quotes',
                            'trigger trg_brain_orders on table public.orders',
                            'trigger trg_brain_orders_created on table public.orders');
  if v_estranho is not null then
    raise exception E'Dependente fora do brain, alem dos 3 gatilhos conhecidos:\n    %\nNao se derruba o schema as cegas — resolva a mao. PARADO.', v_estranho;
  end if;

  select string_agg(funcao || ' [' || linguagem || ']', E'\n    ' order by funcao) into v_texto
    from brain.funcoes_que_citam_brain();
  if v_texto is not null then
    raise exception E'Funcao fora do brain que CITA brain. no texto (o catalogo nao registra essa dependencia):\n    %\nEla quebraria em silencio depois do drop. PARADO.', v_texto;
  end if;

  select count(*) into v_trig from pg_trigger
   where tgname in ('trg_brain_quotes','trg_brain_orders','trg_brain_orders_created');
  if v_trig <> 3 then
    raise exception 'Esperava exatamente os 3 gatilhos conhecidos, achei % — PARADO.', v_trig;
  end if;

  raise notice 'Dependencias: so os 3 gatilhos da ponte, e nenhuma funcao citando brain no texto.';
end
$$;

-- ── Concorrência: falhar rápido em vez de travar a fila ─────
-- `drop trigger` pede ACCESS EXCLUSIVE em `quotes` e `orders`. Numa base
-- com movimento, esperar por esse lock enfileira TODO MUNDO atrás. Com
-- `lock_timeout` a espera vira erro em 3s, a transação aborta e nada fica
-- pela metade — é só tentar de novo num momento mais calmo.
set local lock_timeout = '3s';

drop trigger if exists trg_brain_quotes         on public.quotes;
drop trigger if exists trg_brain_orders         on public.orders;
drop trigger if exists trg_brain_orders_created on public.orders;

-- O CASCADE aqui só alcança o que é do próprio `brain` — foi isso que os
-- dois blocos acima acabaram de provar.
drop schema brain cascade;

-- ── `audit_capture()` volta ao texto anterior ao BRAIN ──────
do $$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from 'ee2f5cd583295c30fbe64eb81eec2d9e' then
    raise exception
      'audit_capture() esta em md5 % e o BRAIN a deixou em ee2f5cd583295c30fbe64eb81eec2d9e. Alguem a mudou depois: restaurar a copia historica APAGARIA esse trabalho. Resolva a mao — PARADO.', v_md5;
  end if;
end
$$;


-- ────────────────────────────────────────────────────────────
-- INCLUIDO DE: supabase/operacao/audit_capture-antes-do-brain.sql
-- (gerado por supabase/operacao/gerar-consolidado.sh — nao edite aqui)
-- ────────────────────────────────────────────────────────────
-- ============================================================
-- `public.audit_capture()` ANTES do BRAIN.
--
-- Texto integral da migration 20260909100000, que é o que está em
-- produção hoje (md5 24fd65a7eb791b2e2644abe1b2ba876b, conferido no
-- catálogo em 11/09/2026 e reproduzido byte a byte pelo ensaio em
-- PostgreSQL 17.6).
--
-- Este arquivo é APENAS para a reversão, e os roteiros que o usam
-- conferem o md5 corrente antes de aplicá-lo: nunca se sobrescreve
-- uma versão mais nova com esta cópia histórica.
-- ============================================================
create or replace function public.audit_capture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity      text := tg_argv[0];
  v_pk          text := tg_argv[1];
  v_label_col   text := nullif(tg_argv[2], '');
  v_parent_type text := nullif(tg_argv[3], '');
  v_parent_col  text := nullif(tg_argv[4], '');

  v_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  v_new jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_row jsonb;

  -- Ruído de auditoria: `updated_at`/`updated_by` mudam em toda escrita e
  -- não contam nada que o log já não diga (ator e horário são colunas
  -- próprias). As demais são DERIVADAS — ver o comentário do bloco.
  v_ignore  text[] := array['updated_at', 'updated_by'];
  v_secret  text[] := array[]::text[];

  v_changed  text[];
  v_old_diff jsonb := '{}'::jsonb;
  v_new_diff jsonb := '{}'::jsonb;
  v_campo    text;

  v_uid   uuid := auth.uid();
  v_kind  text;
  v_email text;
  v_name  text;
  v_role  public.user_role;

  -- CUIDADO: dentro de uma função `security definer`, `current_user` é o
  -- DONO da função (postgres), não quem disparou a escrita — usá-lo aqui
  -- classificaria todo mundo como sistema. O que sobrevive ao
  -- `security definer` é o GUC `role`, que é exatamente o que o PostgREST
  -- define (`set local role authenticated` / `anon`). Sem SET ROLE ele vale
  -- 'none', e aí o papel real é o do login — o caso do pg_cron.
  v_db_role text := coalesce(nullif(current_setting('role', true), 'none'), session_user);

  v_action    text;
  v_entity_id text;
  v_label     text;
  v_parent_id text;
begin
  v_row := coalesce(v_new, v_old);

  -- ── Colunas derivadas e segredos, por tabela ──────────────
  -- `subtotal`/`total` de `quotes` são recalculados por
  -- `recalculate_quote_totals()` a cada mudança de item: sem esta exceção,
  -- adicionar um item ao orçamento geraria DOIS eventos — o do item e um
  -- `quote.updated` fantasma. `line_total` é coluna gerada.
  -- `view_count` sobe a cada visita anônima ao link público: seriam
  -- centenas de linhas sem ator e sem decisão.
  if tg_table_name = 'quotes' then
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'quote_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'orders' then
    -- `recalculate_order_totals()` reescreve subtotal/total logo depois do
    -- INSERT do pedido: sem isto, todo pedido nasceria com um
    -- `order.updated` fantasma colado ao `order.created`.
    v_ignore := v_ignore || array['subtotal', 'total'];
  elsif tg_table_name = 'order_items' then
    v_ignore := v_ignore || array['line_total'];
  elsif tg_table_name = 'purchases' then
    v_ignore := v_ignore || array['items_total', 'total'];
  elsif tg_table_name = 'purchase_items' then
    -- Rateio e custo final são escritos pelo recebimento, linha a linha;
    -- o evento que importa é o `purchase.received`, não N `item_changed`.
    v_ignore := v_ignore || array['line_total', 'freight_share', 'landed_cost', 'previous_cost'];
  elsif tg_table_name = 'financial_entries' then
    -- `status` é derivado da soma das baixas; a baixa em si já é evento.
    v_ignore := v_ignore || array['status'];
  elsif tg_table_name = 'quote_share_tokens' then
    v_ignore := v_ignore || array['view_count'];
    -- O token é credencial de capacidade: quem o tem abre o orçamento sem
    -- login. É o único segredo que existe em `public`. Redigido AQUI, na
    -- escrita — filtrar só na leitura se contorna.
    v_secret := array['token'];
  end if;

  -- ── Antes e depois ────────────────────────────────────────
  if tg_op = 'UPDATE' then
    for v_campo in select k from jsonb_object_keys(v_new) as k loop
      continue when v_campo = any (v_ignore);
      if v_new -> v_campo is distinct from v_old -> v_campo then
        v_changed  := coalesce(v_changed, array[]::text[]) || v_campo;
        v_old_diff := v_old_diff || jsonb_build_object(v_campo, v_old -> v_campo);
        v_new_diff := v_new_diff || jsonb_build_object(v_campo, v_new -> v_campo);
      end if;
    end loop;

    -- Nada relevante mudou: não existe evento. É isto que mantém o log
    -- legível quando o recálculo de totais dispara o trigger.
    if v_changed is null then
      return null;
    end if;
  else
    v_old_diff := v_old;   -- nulo no INSERT
    v_new_diff := v_new;   -- nulo no DELETE
  end if;

  foreach v_campo in array v_secret loop
    if v_old_diff ? v_campo then
      v_old_diff := jsonb_set(v_old_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
    if v_new_diff ? v_campo then
      v_new_diff := jsonb_set(v_new_diff, array[v_campo], '"[REDIGIDO]"'::jsonb);
    end if;
  end loop;

  -- ── Quem ──────────────────────────────────────────────────
  -- `auth.uid()` primeiro: ele sobrevive a funções `security definer`
  -- (lê o claim do JWT), então `discard_quote_draft()` continua sendo
  -- atribuída ao usuário de verdade, e não a `postgres`.
  if v_uid is not null then
    v_kind := 'user';
    select p.email, p.full_name, p.role
      into v_email, v_name, v_role
      from public.profiles p
     where p.id = v_uid;
  elsif v_db_role in ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role') then
    v_kind := 'system';        -- pg_cron, migration, SQL Editor, GoTrue
  elsif v_db_role = 'anon' then
    v_kind := 'anonymous';     -- link público
  else
    v_kind := 'unknown';
  end if;

  -- ── O verbo de negócio ────────────────────────────────────
  -- Derivado do diff, porque a aplicação não consegue informá-lo. Quando
  -- mais de uma coisa muda na mesma escrita, o evento mais específico
  -- vence — mas `changed_fields` continua listando tudo.
  if tg_op = 'DELETE' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_removed'
      when 'order_item'        then 'order.item_removed'
      when 'purchase_item'     then 'purchase.item_removed'
      when 'kit_item'          then 'kit.item_removed'
      when 'quote_share_token' then 'quote.link_deleted'
      when 'product_cost'      then 'product.cost_removed'
      else v_entity || '.deleted'
    end;

  elsif tg_op = 'INSERT' then
    v_action := case v_entity
      when 'quote_item'        then 'quote.item_added'
      when 'order_item'        then 'order.item_added'
      when 'purchase_item'     then 'purchase.item_added'
      when 'financial_payment' then 'financial.payment_registered'
      when 'kit_item'          then 'kit.item_added'
      when 'quote_share_token' then 'quote.link_created'
      when 'product_cost'      then 'product.cost_changed'
      else v_entity || '.created'
    end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is not null then
    -- Exclusão lógica é o evento mais forte da escrita, venha ela de onde vier.
    v_action := case v_entity when 'quote' then 'quote.discarded'
                              else v_entity || '.deleted' end;

  elsif 'deleted_at' = any (v_changed) and (v_new ->> 'deleted_at') is null then
    v_action := v_entity || '.restored';

  elsif v_entity = 'user' and 'role' = any (v_changed) then
    v_action := 'user.role_changed';

  elsif 'is_active' = any (v_changed) then
    v_action := v_entity || case when (v_new ->> 'is_active')::boolean
                                 then '.activated' else '.deactivated' end;

  elsif v_entity = 'quote' and 'status' = any (v_changed) then
    v_action := case v_new ->> 'status'
      when 'approved'  then 'quote.approved'
      when 'rejected'  then 'quote.rejected'
      when 'cancelled' then 'quote.cancelled'
      when 'expired'   then 'quote.expired'
      else 'quote.status_changed'
    end;

  elsif v_entity = 'order' and 'status' = any (v_changed) then
    -- picking / invoiced / delivered / cancelled: o verbo é a situação nova.
    v_action := 'order.' || (v_new ->> 'status');

  elsif v_entity = 'purchase' and 'status' = any (v_changed) then
    v_action := 'purchase.' || (v_new ->> 'status');

  elsif v_entity = 'financial_entry' and 'cancelled_at' = any (v_changed)
        and (v_new ->> 'cancelled_at') is not null then
    v_action := 'financial.cancelled';

  elsif v_entity = 'quote_share_token' and 'revoked_at' = any (v_changed)
        and (v_new ->> 'revoked_at') is not null then
    v_action := 'quote.link_revoked';

  elsif v_entity = 'product_cost' then
    v_action := 'product.cost_changed';

  elsif v_entity = 'product' and 'sale_price' = any (v_changed) then
    v_action := 'product.price_changed';

  elsif v_entity = 'kit' and 'discount_percent' = any (v_changed) then
    v_action := 'kit.discount_changed';

  elsif v_entity = 'kit_item' and 'item_type' = any (v_changed) then
    v_action := 'kit.item_type_changed';

  elsif v_entity = 'kit_item' and 'quantity' = any (v_changed) then
    v_action := 'kit.item_quantity_changed';

  elsif v_entity = 'quote_item'        then v_action := 'quote.item_changed';
  elsif v_entity = 'order_item'        then v_action := 'order.item_changed';
  elsif v_entity = 'purchase_item'     then v_action := 'purchase.item_changed';
  elsif v_entity = 'kit_item'          then v_action := 'kit.item_changed';
  elsif v_entity = 'quote_share_token' then v_action := 'quote.link_changed';
  elsif v_entity = 'user'              then v_action := 'user.profile_updated';
  else                                      v_action := v_entity || '.updated';
  end if;

  -- ── Onde ──────────────────────────────────────────────────
  v_entity_id := v_row ->> v_pk;
  v_label     := case when v_label_col  is null then null else v_row ->> v_label_col  end;
  v_parent_id := case when v_parent_col is null then null else v_row ->> v_parent_col end;

  insert into public.audit_log (
    actor_kind, actor_user_id, actor_email, actor_name, actor_role, actor_db_role,
    action, operation,
    entity_type, entity_id, entity_label, parent_type, parent_id,
    changed_fields, old_data, new_data, metadata
  ) values (
    v_kind, v_uid, v_email, v_name, v_role, v_db_role,
    v_action, tg_op,
    v_entity, v_entity_id, v_label, v_parent_type, v_parent_id,
    v_changed, v_old_diff, v_new_diff,
    jsonb_build_object('txid', txid_current(), 'table', tg_table_name)
  );

  return null;   -- trigger AFTER: o retorno é ignorado
end;
$$;


revoke execute on function public.audit_capture() from public, anon, authenticated;

delete from supabase_migrations.schema_migrations
 where version in ('20260911130000','20260911140000','20260911150000',
                   '20260911160000','20260911170000','20260911180000',
                   '20260911190000','20260911200000','20260911210000',
                   '20260911220000');

-- ── Fim de linha: CRLF vira LF antes de conferir o md5 ──────
-- Mesmo motivo do roteiro 02: este arquivo é colado no SQL Editor e o
-- editor do navegador normaliza a quebra de linha para CRLF. Como
-- `audit_capture()` é definida dentro de `$$ … $$`, o `\r` entraria no
-- corpo e mudaria o md5 — a pós-condição abaixo reprovaria uma restauração
-- que está semanticamente certa. Reescreve-se a função sem os `\r`, para
-- o texto em produção ser o texto auditado.
do $$
declare v_oid oid;
begin
  select p.oid into v_oid
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture'
     and pg_catalog.strpos(p.prosrc, pg_catalog.chr(13)) > 0;
  if v_oid is not null then
    execute pg_catalog.replace(pg_catalog.pg_get_functiondef(v_oid), pg_catalog.chr(13), '');
    raise notice 'Fim de linha: o roteiro chegou com CRLF e audit_capture() foi reescrita com LF.';
  end if;
end
$$;

-- ── Pós-condições ───────────────────────────────────────────
do $$
declare v_md5 text; v_n int;
begin
  if exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain continua existindo — PARADO.';
  end if;
  select count(*) into v_n from pg_trigger where tgname like 'trg_brain%';
  if v_n <> 0 then raise exception 'Sobraram % gatilho(s) do brain — PARADO.', v_n; end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_capture';
  if v_md5 is distinct from '24fd65a7eb791b2e2644abe1b2ba876b' then
    raise exception 'audit_capture() ficou em md5 % e o esperado era 24fd65a7eb791b2e2644abe1b2ba876b — PARADO.', v_md5;
  end if;

  select count(*) into v_n from supabase_migrations.schema_migrations
   where version like '20260911%';
  if v_n <> 0 then raise exception 'O registro do BRAIN nao saiu — PARADO.'; end if;

  perform 1 from public.quotes limit 1;
  perform 1 from public.orders limit 1;

  raise notice 'BRAIN removido, audit_capture restaurada, registro limpo. Pronto para COMMIT.';
end
$$;

commit;
