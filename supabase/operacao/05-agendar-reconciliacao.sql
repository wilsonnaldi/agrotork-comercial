-- ============================================================
-- AGENDAR A RECONCILIAÇÃO PERIÓDICA — depois do COMMIT do roteiro 02
--
-- No modo desacoplado é isto que liga o ERP ao BRAIN: a cada minuto o
-- pg_cron chama `brain.reconciliar_erp_periodico()`, que roda na sessão
-- do cron, fora de qualquer transação comercial.
--
-- Uma falha aqui não tem como tocar num orçamento: não há código do
-- BRAIN dentro da transação de venda — os três gatilhos estão
-- desabilitados. A função ainda engole a própria exceção, registra
-- `warning` e devolve -1, para o job não ficar em erro permanente nem
-- poluir o log a cada minuto; o minuto seguinte tenta de novo.
--
-- COMO RODAR: SQL Editor do Supabase, colado inteiro. Ver
-- supabase/operacao/README.md.
-- ============================================================

begin;

do $$
declare v_ligados int; v_existe int;
begin
  if not exists (select 1 from pg_namespace where nspname = 'brain') then
    raise exception 'O schema brain nao existe — rode 02-aplicar-brain.sql antes. PARADO.';
  end if;
  -- Em produção é a extensão que responde. No ensaio local o schema
  -- `cron` é um stub (ver 00_supabase_stub.sql) e a extensão não existe;
  -- por isso a condição aceita as duas formas, e avisa qual delas achou.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron: extensao presente.';
  elsif to_regclass('cron.job') is not null then
    raise warning 'pg_cron: extensao AUSENTE, usando o schema cron existente. Em producao isto tem de ser a extensao de verdade.';
  else
    raise exception 'pg_cron nao esta habilitado e nao ha schema cron — PARADO.';
  end if;

  select count(*) into v_ligados from pg_trigger
   where tgname like 'trg_brain%' and tgenabled <> 'D';
  if v_ligados <> 0 then
    raise exception 'MODO DESACOPLADO violado: % ponte(s) habilitada(s). O agendamento e para o modo desacoplado — PARADO.', v_ligados;
  end if;

  select count(*) into v_existe from pg_trigger where tgname like 'trg_brain%';
  if v_existe <> 3 then
    raise exception 'Esperava os 3 gatilhos existindo (desligados), achei % — PARADO.', v_existe;
  end if;

  raise notice 'Pre-condicoes: brain aplicado, pg_cron habilitado, 3 pontes existindo e desligadas.';
end
$$;

-- Se já houver um agendamento com este nome, ele sai antes: o roteiro
-- pode ser rodado de novo sem criar job duplicado.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'brain-reconciliar') then
    perform cron.unschedule('brain-reconciliar');
    raise notice 'Agendamento anterior removido.';
  end if;
end
$$;

select cron.schedule(
  'brain-reconciliar',
  '* * * * *',
  $job$ select brain.reconciliar_erp_periodico(); $job$
) as jobid;

do $$
declare v_job record;
begin
  select * into v_job from cron.job where jobname = 'brain-reconciliar';
  if v_job is null then
    raise exception 'O agendamento nao foi criado — PARADO.';
  end if;
  if v_job.schedule <> '* * * * *' then
    raise exception 'O agendamento ficou em "%" e o combinado e a cada minuto — PARADO.', v_job.schedule;
  end if;
  if not v_job.active then
    raise exception 'O agendamento foi criado inativo — PARADO.';
  end if;
  raise notice 'Agendado: job % "%", a cada minuto, ativo, como %.',
    v_job.jobid, v_job.jobname, v_job.username;
end
$$;

commit;

-- Conferir depois de um ou dois minutos:
--
--   select jobid, runid, status, return_message, start_time, end_time
--     from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'brain-reconciliar')
--    order by start_time desc limit 5;
--
--   select * from brain.divergencias_erp();   -- tem de vir VAZIO
--
-- Para desligar o agendamento:  select cron.unschedule('brain-reconciliar');
