-- ============================================================
-- Reconciliação documental da Fase 6.2 — somente COMMENT
--
-- O QUE ACONTECEU
--
-- A Fase 6.2 foi aplicada no projeto remoto com um SQL REESCRITO à mão, e
-- não com os arquivos deste repositório. O histórico
-- (`supabase_migrations.schema_migrations`) guarda o texto aplicado, e a
-- comparação mostrou duas divergências — ambas de comentário, nenhuma de
-- comportamento:
--
--   1. `comment on function public.expire_quotes()` foi aplicado em
--      INGLÊS ("Expires sent quotes whose valid_until date is before the
--      current date. Scheduled daily by pg_cron."), enquanto o
--      repositório documenta a função em português, descrevendo a
--      idempotência e o que ela nunca altera.
--   2. `comment on index public.idx_quotes_expiration` NÃO foi aplicado:
--      o comentário do índice está nulo no banco.
--
-- O que É igual, conferido no catálogo do projeto remoto: o predicado do
-- índice (`deleted_at is null and status = 'sent'`), os privilégios de
-- `expire_quotes()` (revogados de public/anon/authenticated, concedidos a
-- service_role), e o job do pg_cron — nome `expirar-orcamentos`,
-- agendamento `5 3 * * *`, comando `select public.expire_quotes();`, dono
-- `postgres`, banco `postgres`. Nenhum comportamento divergiu.
--
-- POR QUE ESTA MIGRATION EXISTE
--
-- Os arquivos locais da 6.2 foram renomeados para os timestamps que o
-- remoto realmente registrou (`20260901052518` e `20260901052525`), para
-- que o histórico case sem tocar em produção — sem `migration repair`,
-- sem escrever no remoto. A consequência é que aqueles dois arquivos
-- nunca mais serão executados lá: já constam como aplicados. Então os
-- dois `COMMENT` do repositório jamais chegariam ao banco, e o Git
-- deixaria de descrever o que está em produção.
--
-- Esta migration fecha essa lacuna, e só ela.
--
-- O QUE ELA NÃO FAZ
--
-- Não redefine função nenhuma. Não recria nem reagenda o job. Não cria
-- nem altera índice. Não mexe em grants, RLS, policies, triggers nem em
-- dado nenhum. Não toca na Fase 6.3. Dois `COMMENT`, e nada além disso.
--
-- Em um banco criado do zero é um no-op: a migration `20260901052525` já
-- aplica exatamente estes mesmos textos alguns segundos antes.
-- ============================================================

comment on function public.expire_quotes() is
  'Marca como expired os orçamentos SENT cuja validade (valid_until) já passou. '
  'Idempotente: só lê linhas em sent, então rodar de novo devolve 0 e não toca em nada. '
  'Nunca altera draft, approved, rejected, cancelled nem um já expired, e ignora descartados. '
  'Agendada no pg_cron como o job expirar-orcamentos. Sem parâmetros, sem acesso do frontend.';

comment on index public.idx_quotes_expiration is
  'Apoia public.expire_quotes(). Parcial: só orçamentos enviados e não descartados.';
