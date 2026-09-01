-- ============================================================
-- Agendamento do job de expiração — passo MANUAL, pós-painel.
--
-- QUANDO RODAR
--
-- A migration `20260901030000_expire_quotes_schedule.sql` agenda o job
-- sozinha SE o pg_cron já estiver instalado quando ela for aplicada. Como
-- no projeto `Agrotork system` a extensão ainda não está instalada, a
-- migration passa como no-op e o agendamento fica pendente.
--
-- Sequência correta:
--
--   1. Supabase → Database → Extensions → habilitar `pg_cron`
--      (é operação de painel: precisa de superusuário e não cabe em
--      migration).
--   2. Supabase → SQL Editor → colar e rodar ESTE arquivo.
--   3. Conferir com:
--        select jobid, jobname, schedule, command, active from cron.job;
--        select d.runid, j.jobname, d.status, d.return_message, d.start_time
--          from cron.job_run_details d
--          join cron.job j on j.jobid = d.jobid
--         where j.jobname = 'expirar-orcamentos'
--         order by d.runid desc limit 10;
--      (`cron.job_run_details` NÃO tem coluna `jobname` — o nome vem do
--       join com `cron.job`.)
--
-- O arquivo é repetível: rodar duas vezes não cria job duplicado.
--
-- HORÁRIO
--
-- 03:05 UTC = 00:05 em America/Sao_Paulo — o mesmo horário que o SETUP.md
-- §9 já documentava. O pg_cron agenda em UTC e `current_date` também é
-- avaliado em UTC; qualquer horário entre 03:00 e 23:59 UTC cai no mesmo
-- dia calendário de Londrina, então "venceu ontem" no banco é "venceu
-- ontem" para o vendedor. Ver o comentário longo na migration.
--
-- PARA DESLIGAR
--
--   select cron.unschedule('expirar-orcamentos');
-- ============================================================

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception
      'pg_cron nao esta instalado. Habilite a extensao no painel do Supabase antes de rodar este arquivo.';
  end if;

  execute $cron$
    select cron.unschedule(jobid)
      from cron.job
     where jobname = 'expirar-orcamentos'
  $cron$;

  execute $cron$
    select cron.schedule(
      'expirar-orcamentos',
      '5 3 * * *',
      $job$select public.expire_quotes();$job$
    )
  $cron$;

  raise notice 'expirar-orcamentos agendado para 03:05 UTC (00:05 America/Sao_Paulo).';
end $$;
