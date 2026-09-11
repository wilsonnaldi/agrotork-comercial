-- ============================================================
-- INCIDENTE COM O BRAIN JÁ EM USO — parar o sangramento, não apagar
--
-- Aqui o BRAIN já tem lead, interação, oportunidade ou tarefa de
-- verdade. Apagar isso é perder trabalho de vendedor, e não existe
-- desfazer. Então este roteiro NÃO APAGA NADA.
--
-- O que ele faz, em três passos e uma transação só:
--
--   1. COPIA o conteúdo das nove tabelas para o schema `brain_arquivo`,
--      e confere linha a linha (md5 por tabela) que a cópia bate;
--   2. DESLIGA a ponte: tira os três gatilhos de `public.quotes` e
--      `public.orders`. O ERP volta a não saber que o BRAIN existe, e
--      para de escrever nele. É isto que estanca;
--   3. DEIXA o schema `brain` de pé, para análise.
--
-- O que ele NÃO faz:
--   · não derruba o schema;
--   · não restaura `audit_capture()`. Com a ponte desligada, os verbos
--     a mais (`lead.*`, `opportunity.*`, `task.*`) ficam inertes: sem
--     tabela sendo escrita, nenhum deles é alcançado. Trocar a função
--     agora seria mexer em código do ERP durante um incidente, sem
--     necessidade;
--   · não mexe no registro de migrations — o BRAIN CONTINUA aplicado, e
--     dizer o contrário seria mentir para o `supabase db push`.
--
-- ── CONCORRÊNCIA: como desligar sem travar a fila ───────────
--
-- `drop trigger` pede ACCESS EXCLUSIVE em `public.quotes` e
-- `public.orders`. Durante um incidente há movimento, e esperar por esse
-- lock enfileira TODO MUNDO atrás — o remédio viraria a doença.
--
-- A estratégia é esta, e é deliberada:
--
--   1. a CÓPIA vem primeiro, e ela não pede lock exclusivo de nada em
--      `public` — a janela em que este roteiro segura `quotes`/`orders`
--      é só a dos três `drop trigger`;
--   2. `lock_timeout = 3s`: se a espera passar disso, a transação aborta
--      inteira e NADA fica pela metade. Melhor tentar de novo do que
--      parar o comercial;
--   3. ordem fixa `quotes` → `orders`, a mesma que o ERP usa em
--      `create_order_from_quote()`. Ordem igual não faz impasse;
--   4. se o `lock_timeout` estourar: olhe quem está segurando
--
--        select pid, state, wait_event_type, left(query, 60)
--          from pg_stat_activity
--         where state <> 'idle' and pid <> pg_backend_pid()
--         order by xact_start;
--
--      e rode de novo. Não se derruba sessão de vendedor por conta deste
--      roteiro: quem decide isso é gente.
--
-- Depois de estancar e entender, há duas saídas:
--   · consertar e religar a ponte (o SQL está no rodapé);
--   · remover de vez, e aí o `brain_arquivo` é o que sobra — só então
--     `drop schema brain cascade` faz sentido, com a mesma conferência
--     de dependentes do roteiro 03.
-- ============================================================

begin;

do $$
declare v_n int;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe — nada a estancar. PARADO.';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'brain_arquivo') then
    raise exception 'brain_arquivo JA EXISTE. Renomeie a copia anterior antes de fazer outra — PARADO.'
      using errcode = 'duplicate_schema';
  end if;
  select count(*) into v_n from pg_trigger
   where tgname in ('trg_brain_quotes','trg_brain_orders','trg_brain_orders_created');
  if v_n = 0 then
    raise exception 'A ponte JA esta desligada (0 gatilhos). Se o objetivo e outro, este nao e o roteiro — PARADO.';
  end if;
  raise notice 'Ponte ligada com % gatilho(s). Copiando o conteudo antes de desligar.', v_n;

  -- Aviso, não impedimento: aqui o schema FICA de pé, então um
  -- dependente externo não quebra nada. Mas quem for decidir o passo
  -- seguinte precisa saber que ele existe.
  if exists (select 1 from brain.dependentes_externos()
              where dependente not like 'trigger trg_brain%') then
    raise warning 'Ha dependente externo alem dos gatilhos: %',
      (select string_agg(dependente, ', ') from brain.dependentes_externos()
        where dependente not like 'trigger trg_brain%');
  end if;
  if exists (select 1 from brain.funcoes_que_citam_brain()) then
    raise warning 'Ha funcao fora do brain citando brain. no texto: %',
      (select string_agg(funcao, ', ') from brain.funcoes_que_citam_brain());
  end if;
end
$$;

-- ── 1. Cópia integral, conferida ────────────────────────────
create schema brain_arquivo;
revoke all on schema brain_arquivo from public, anon, authenticated;

create table brain_arquivo.leads         as select * from brain.leads;
create table brain_arquivo.identities    as select * from brain.identities;
create table brain_arquivo.interactions  as select * from brain.interactions;
create table brain_arquivo.opportunities as select * from brain.opportunities;
create table brain_arquivo.tasks         as select * from brain.tasks;
create table brain_arquivo.events        as select * from brain.events;
create table brain_arquivo.attributions  as select * from brain.attributions;
create table brain_arquivo.channels      as select * from brain.channels;
create table brain_arquivo.lead_merges   as select * from brain.lead_merges;

do $$
declare
  r record;
  v_orig text; v_copia text;
  v_dif text := null;
  v_linhas bigint := 0;
begin
  for r in select unnest(array['leads','identities','interactions','opportunities',
                               'tasks','events','attributions','channels','lead_merges']) as t
  loop
    execute format('select md5(coalesce(string_agg(x::text, %L order by x::text), %L)) from brain.%I x', '|', '', r.t)
      into v_orig;
    execute format('select md5(coalesce(string_agg(x::text, %L order by x::text), %L)) from brain_arquivo.%I x', '|', '', r.t)
      into v_copia;
    if v_orig is distinct from v_copia then
      v_dif := coalesce(v_dif || ', ', '') || r.t;
    end if;
    execute format('select count(*) from brain_arquivo.%I', r.t) into strict v_linhas;
  end loop;

  if v_dif is not null then
    raise exception 'A copia NAO bate em: %. Nada foi desligado — PARADO.', v_dif;
  end if;

  raise notice 'Copia conferida: as 9 tabelas batem por md5 de conteudo ordenado.';
end
$$;

-- ── 2. Desligar a ponte ─────────────────────────────────────
-- Daqui até o COMMIT é a única janela em que `quotes` e `orders` ficam
-- em ACCESS EXCLUSIVE. Tudo o que dava para fazer antes já foi feito.
set local lock_timeout = '3s';

drop trigger if exists trg_brain_quotes         on public.quotes;
drop trigger if exists trg_brain_orders         on public.orders;
drop trigger if exists trg_brain_orders_created on public.orders;

-- ── 3. Conferências finais ──────────────────────────────────
do $$
declare v_n int; v_leads int;
begin
  select count(*) into v_n from pg_trigger where tgname like 'trg_brain%';
  if v_n <> 0 then
    raise exception 'Sobraram % gatilho(s) da ponte — o sangramento nao parou. PARADO.', v_n;
  end if;

  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain sumiu, e este roteiro nao apaga nada — PARADO.';
  end if;

  select count(*) into v_leads from brain_arquivo.leads;
  if v_leads is distinct from (select count(*) from brain.leads) then
    raise exception 'A copia de leads divergiu depois do desligamento — PARADO.';
  end if;

  -- O ERP tem de continuar operando sem a ponte.
  perform 1 from public.quotes limit 1;
  perform 1 from public.orders limit 1;

  raise notice 'Ponte desligada, brain intacto, copia em brain_arquivo com % lead(s). Pronto para COMMIT.', v_leads;
end
$$;

commit;

-- ============================================================
-- RELIGAR A PONTE, depois de entender e consertar:
--
--   begin;
--   create trigger trg_brain_quotes after insert or update of status
--     on public.quotes for each row execute function brain.on_quote_change();
--   create constraint trigger trg_brain_orders_created after insert
--     on public.orders deferrable initially deferred
--     for each row execute function brain.on_order_change();
--   create trigger trg_brain_orders after update of status
--     on public.orders for each row execute function brain.on_order_change();
--   -- o que passou enquanto a ponte esteve fora:
--   select * from brain.divergencias_erp();
--   select * from brain.reconciliar_erp();
--   select * from brain.divergencias_erp();   -- tem de vir VAZIO
--   commit;
--
-- É `brain.reconciliar_erp()` que fecha o buraco do período desligado —
-- e ela não repõe só o evento: põe a oportunidade no estágio certo, liga
-- o pedido, marca a venda ganha, converte o lead e desfaz a venda que
-- foi cancelada no escuro. O critério de sucesso é
-- `divergencias_erp()` voltar vazio, não "zero eventos faltantes".
-- ============================================================
