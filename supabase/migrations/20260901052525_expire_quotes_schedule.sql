-- ============================================================
-- 2200 · Fase 6.2 — Expiração automática de orçamentos
--
-- O QUE JÁ EXISTIA (e por isso NÃO foi reinventado)
--
-- A regra de validade do sistema é uma só, e já estava escrita em três
-- lugares que concordam entre si:
--
--   1. `public.expire_quotes()` (migration 0600):
--        status = 'sent' and valid_until is not null
--        and valid_until < current_date and deleted_at is null
--   2. `public.get_shared_quote()` (migration 1900):
--        commercially_expired := valid_until is not null
--                                and valid_until < current_date
--   3. `src/modules/quotes/share/service.ts`: a mesma comparação.
--
-- Ou seja: a coluna é `quotes.valid_until` (date). NÃO existe `expires_at`
-- em `quotes` — `expires_at` é do TOKEN de compartilhamento
-- (`quote_share_tokens`), que é outra coisa: prazo do link, não validade
-- comercial. E não existe "data de emissão + prazo": `valid_until` é
-- gravado direto e o domínio só exige `valid_until >= issue_date`
-- (`src/modules/quotes/service.ts`).
--
-- A comparação é `<`, e não `<=`: o orçamento vale ATÉ o dia
-- `valid_until`, inclusive. No próprio dia da validade ele continua
-- `sent`. Esta migration NÃO muda essa regra.
--
-- `valid_until is null` significa "sem validade definida" e nunca expira.
-- Também é regra existente, mantida.
--
-- O QUE FALTAVA
--
-- Só o agendamento: `expire_quotes()` existia desde a 0600 com o
-- comentário "será agendada via cron do Supabase na Fase 6", mas nada a
-- chamava. Hoje a expiração depende de alguém abrir o orçamento e mudar o
-- status na mão (`STATUS_TRANSITIONS.sent` inclui `expired`).
--
-- Esta migration, portanto:
--   1. cria o índice parcial que torna a varredura diária barata;
--   2. reafirma os privilégios da função (defesa contra deriva);
--   3. agenda o job no pg_cron — SE, E SOMENTE SE, a extensão já estiver
--      instalada no banco em que a migration for aplicada.
--
-- POR QUE O AGENDAMENTO É CONDICIONAL
--
-- `pg_cron` está DISPONÍVEL no projeto (versão 1.6.4) mas NÃO instalado.
-- Habilitar a extensão é operação de painel/superusuário e está fora do
-- que uma migration deve fazer por conta própria — e um
-- `create extension pg_cron` incondicional quebraria `npm run db:test`,
-- que aplica todas as migrations em um PostgreSQL puro e descartável,
-- onde a extensão nem existe no sistema de arquivos.
--
-- Então o bloco abaixo é um no-op silencioso onde não há pg_cron, e se
-- agenda sozinho onde há. Depois de habilitar a extensão no painel do
-- Supabase, rode `supabase/scripts/schedule-expire-quotes.sql` (mesmo
-- bloco, repetível) para criar o job sem precisar de nova migration.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

-- ── 1. Índice da varredura diária ───────────────────────────
-- O job pergunta sempre a mesma coisa: "quais orçamentos ENVIADOS, não
-- descartados, venceram?". Índice parcial exatamente sobre esse recorte —
-- fica minúsculo (só o que está em `sent`) e some do caminho de escrita
-- assim que o orçamento sai desse status.
create index if not exists idx_quotes_expiration
  on public.quotes (valid_until)
  where deleted_at is null and status = 'sent';

comment on index public.idx_quotes_expiration is
  'Apoia public.expire_quotes(). Parcial: só orçamentos enviados e não descartados.';

-- ── 2. Privilégios da função de expiração ───────────────────
-- A migration 1000 já revogou EXECUTE de public/anon/authenticated e
-- concedeu a service_role. Repetir aqui é barato e transforma em garantia
-- o que hoje é consequência da ordem das migrations: nenhum usuário
-- autenticado dispara a expiração, nem pela API REST (`/rest/v1/rpc/`),
-- nem por SQL. O navegador não tem caminho para chamar esta função — e
-- ela não recebe parâmetro nenhum, então não há o que injetar.
revoke execute on function public.expire_quotes() from public, anon, authenticated;
grant  execute on function public.expire_quotes() to service_role;

comment on function public.expire_quotes() is
  'Marca como expired os orçamentos SENT cuja validade (valid_until) já passou. '
  'Idempotente: só lê linhas em sent, então rodar de novo devolve 0 e não toca em nada. '
  'Nunca altera draft, approved, rejected, cancelled nem um já expired, e ignora descartados. '
  'Agendada no pg_cron como o job expirar-orcamentos. Sem parâmetros, sem acesso do frontend.';

-- ── 3. Agendamento no pg_cron ───────────────────────────────
-- Nome e horário são os que o SETUP.md §9 já documentava para este
-- projeto: job `expirar-orcamentos`, `5 3 * * *`. Esta migration só
-- transforma aquele procedimento manual em algo versionado — não escolhe
-- um horário novo.
--
-- 03:05 UTC = 00:05 em America/Sao_Paulo, e a escolha NÃO é estética: o
-- pg_cron do Supabase agenda em UTC e `current_date` também é avaliado em
-- UTC. Qualquer horário entre 03:00 e 23:59 UTC cai no MESMO dia
-- calendário de Londrina, então "venceu ontem" no banco é "venceu ontem"
-- para o vendedor — e às 00:05 locais o orçamento expira assim que o dia
-- vira. Rodar às 22:00 locais, por exemplo, expiraria três horas cedo
-- demais, porque em UTC já seria o dia seguinte.
--
-- `EXECUTE` dinâmico de propósito: sem a extensão instalada o schema
-- `cron` não existe, e uma referência direta a `cron.schedule` faria o
-- arquivo falhar já na análise, em qualquer ambiente sem pg_cron.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice
      'pg_cron nao instalado: expire_quotes() NAO foi agendada. '
      'Habilite a extensao no painel do Supabase e rode '
      'supabase/scripts/schedule-expire-quotes.sql.';
    return;
  end if;

  -- Idempotente: apagar antes de criar evita job duplicado se a migration
  -- for reaplicada em um banco que já tinha o agendamento.
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
