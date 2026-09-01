-- ============================================================
-- 13 · Expiração automática de orçamentos (Fase 6.2)
--
-- A regra NÃO é inventada aqui: é a que `public.expire_quotes()` já
-- escrevia desde a migration 0600 e que `get_shared_quote()` repete —
-- `status = 'sent'`, `valid_until is not null`, `valid_until <
-- current_date`, `deleted_at is null`. Este arquivo transforma cada
-- palavra dessa regra em asserção, inclusive as negativas: o que o job
-- NÃO pode tocar é mais importante do que o que ele toca.
--
-- Prefixo de saída: I.
-- ============================================================
\set ON_ERROR_STOP on

-- ── Fixture isolada ─────────────────────────────────────────
-- Ids próprios: a suíte é encadeada e este arquivo não pode depender de
-- quantos orçamentos os anteriores deixaram, nem sujá-los.
insert into auth.users (id, email, raw_user_meta_data) values
 ('eeeeeeee-0000-4000-8000-00000000e001','exp.vend.a@teste.local','{"full_name":"Vendedor Expiracao A"}'::jsonb),
 ('eeeeeeee-0000-4000-8000-00000000e002','exp.vend.b@teste.local','{"full_name":"Vendedor Expiracao B"}'::jsonb);

insert into public.customers (id, name, document, city, state)
values ('eeeeeeee-0000-4000-8000-0000000000c1', 'Fazenda Expiracao', '11.222.333/0001-81', 'Londrina', 'PR');

-- Cada orçamento carrega o próprio caso em `notes`, para a asserção ser
-- legível e não depender de ordem de criação.
insert into public.quotes (customer_id, owner_id, valid_until, notes)
values
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date + 5,  'EXP-VALIDO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 1,  'EXP-VENCIDO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date,      'EXP-LIMITE'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-JA-EXPIRADO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-APROVADO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-REJEITADO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-CANCELADO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-RASCUNHO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', null,              'EXP-SEM-VALIDADE'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e001', current_date - 10, 'EXP-DESCARTADO'),
 ('eeeeeeee-0000-4000-8000-0000000000c1','eeeeeeee-0000-4000-8000-00000000e002', current_date - 1,  'EXP-VENDEDOR-B');

-- Um item em cada um, para conferir depois que o job não mexeu em total.
insert into public.quote_items (quote_id, kind, name_snapshot, quantity, unit_price)
select q.id, 'custom', 'Servico de teste', 1, 100.00
from public.quotes q where q.notes like 'EXP-%';

-- Status de partida. Sai de `draft` por UPDATE de propósito: é o que faz
-- `stamp_quote_status` carimbar sent_at/approved_at/rejected_at como
-- aconteceria em produção.
update public.quotes set status = 'sent'
 where notes in ('EXP-VALIDO','EXP-VENCIDO','EXP-LIMITE','EXP-JA-EXPIRADO',
                 'EXP-APROVADO','EXP-REJEITADO','EXP-CANCELADO',
                 'EXP-SEM-VALIDADE','EXP-DESCARTADO','EXP-VENDEDOR-B');

update public.quotes set status = 'expired'  where notes = 'EXP-JA-EXPIRADO';
update public.quotes set status = 'approved' where notes = 'EXP-APROVADO';
update public.quotes set status = 'rejected' where notes = 'EXP-REJEITADO';
update public.quotes set status = 'cancelled' where notes = 'EXP-CANCELADO';
update public.quotes set deleted_at = now()  where notes = 'EXP-DESCARTADO';

-- ── Retrato ANTES ───────────────────────────────────────────
create temporary table exp_antes as
select id, notes, status, updated_at, sent_at, approved_at, rejected_at, total, deleted_at
from public.quotes where notes like 'EXP-%';

-- ── IA) primeira execução ───────────────────────────────────
do $$
declare v_conta integer;
begin
  select public.expire_quotes() into v_conta;
  -- Só EXP-VENCIDO e EXP-VENDEDOR-B se encaixam na regra. Se este número
  -- mudar, o job passou a alcançar algo que não devia.
  if v_conta = 2 then
    raise notice 'IA) OK: expire_quotes() devolveu 2, exatamente os dois vencidos e enviados';
  else
    raise notice 'IA) FALHA: expire_quotes() devolveu %, esperado 2', v_conta;
  end if;
end $$;

-- ── IB..IK) o que mudou e o que não podia mudar ─────────────
do $$
declare
  r record;
  v_esperado text;
  v_prefixo  text;
begin
  for r in
    select notes, status::text as status from public.quotes where notes like 'EXP-%' order by notes
  loop
    v_esperado := case r.notes
      when 'EXP-VALIDO'        then 'sent'       -- vence daqui a 5 dias
      when 'EXP-VENCIDO'       then 'expired'    -- venceu ontem
      when 'EXP-LIMITE'        then 'sent'       -- vence HOJE: ainda vale
      when 'EXP-JA-EXPIRADO'   then 'expired'
      when 'EXP-APROVADO'      then 'approved'
      when 'EXP-REJEITADO'     then 'rejected'
      when 'EXP-CANCELADO'     then 'cancelled'
      when 'EXP-RASCUNHO'      then 'draft'
      when 'EXP-SEM-VALIDADE'  then 'sent'       -- sem validade nao expira
      when 'EXP-DESCARTADO'    then 'sent'       -- descartado sai do alcance
      when 'EXP-VENDEDOR-B'    then 'expired'
    end;

    v_prefixo := case r.notes
      when 'EXP-VALIDO'       then 'IB'
      when 'EXP-VENCIDO'      then 'IC'
      when 'EXP-LIMITE'       then 'ID'
      when 'EXP-JA-EXPIRADO'  then 'IE'
      when 'EXP-APROVADO'     then 'IF'
      when 'EXP-REJEITADO'    then 'IG'
      when 'EXP-CANCELADO'    then 'IH'
      when 'EXP-RASCUNHO'     then 'II'
      when 'EXP-SEM-VALIDADE' then 'IJ'
      when 'EXP-DESCARTADO'   then 'IK'
      when 'EXP-VENDEDOR-B'   then 'IL'
    end;

    if r.status = v_esperado then
      raise notice '%) OK: % continua/virou %', v_prefixo, r.notes, r.status;
    else
      raise notice '%) FALHA: % ficou % (esperado %)', v_prefixo, r.notes, r.status, v_esperado;
    end if;
  end loop;
end $$;

-- ── IM) nada além do status foi tocado ──────────────────────
-- O job não pode carimbar data de envio/aprovação/recusa nem mexer em
-- valor. `updated_at` PODE mudar (é o trigger de auditoria) e só nas duas
-- linhas que realmente expiraram.
do $$
declare v_ruins integer;
begin
  select count(*) into v_ruins
  from exp_antes a join public.quotes q on q.id = a.id
  where a.sent_at     is distinct from q.sent_at
     or a.approved_at is distinct from q.approved_at
     or a.rejected_at is distinct from q.rejected_at
     or a.total       is distinct from q.total
     or a.deleted_at  is distinct from q.deleted_at;
  if v_ruins = 0 then raise notice 'IM) OK: carimbos, totais e descarte intactos';
  else raise notice 'IM) FALHA: % linha(s) com carimbo ou total alterado pelo job', v_ruins; end if;
end $$;

do $$
declare v_mexidas integer;
begin
  select count(*) into v_mexidas
  from exp_antes a join public.quotes q on q.id = a.id
  where a.updated_at is distinct from q.updated_at;
  if v_mexidas = 2 then raise notice 'IN) OK: apenas as 2 linhas expiradas tiveram updated_at renovado';
  else raise notice 'IN) FALHA: % linha(s) com updated_at renovado, esperado 2', v_mexidas; end if;
end $$;

-- ── IO/IP) idempotência ─────────────────────────────────────
create temporary table exp_depois as
select id, notes, status, updated_at, sent_at, approved_at, rejected_at, total, deleted_at
from public.quotes where notes like 'EXP-%';

do $$
declare v_conta integer;
begin
  select public.expire_quotes() into v_conta;
  if v_conta = 0 then raise notice 'IO) OK: segunda execucao devolveu 0';
  else raise notice 'IO) FALHA: segunda execucao devolveu %, esperado 0', v_conta; end if;
end $$;

do $$
declare v_conta integer; v_dif integer;
begin
  -- terceira, para o caso de o efeito colateral só aparecer depois
  select public.expire_quotes() into v_conta;
  select count(*) into v_dif
  from exp_depois d join public.quotes q on q.id = d.id
  where (d.status, d.updated_at, d.sent_at, d.approved_at, d.rejected_at, d.total, d.deleted_at)
        is distinct from
        (q.status, q.updated_at, q.sent_at, q.approved_at, q.rejected_at, q.total, q.deleted_at);
  if v_conta = 0 and v_dif = 0 then
    raise notice 'IP) OK: execucoes repetidas nao produzem nenhum efeito adicional';
  else
    raise notice 'IP) FALHA: terceira execucao devolveu % e alterou % linha(s)', v_conta, v_dif;
  end if;
end $$;

-- ── IQ) relatórios continuam batendo ────────────────────────
-- `quotes_list` é a view que a listagem e qualquer relatório consomem.
-- Depois da expiração ela precisa refletir o status novo, continuar
-- escondendo o descartado e não ter perdido nenhum valor.
do $$
declare v_expirados integer; v_total integer; v_soma numeric;
begin
  select count(*) filter (where status::text = 'expired'),
         count(*),
         coalesce(sum(total), 0)
    into v_expirados, v_total, v_soma
  from public.quotes_list
  where id in (select id from exp_antes);

  -- 11 orçamentos criados, 1 descartado não aparece = 10.
  -- Expirados: EXP-VENCIDO, EXP-VENDEDOR-B e EXP-JA-EXPIRADO = 3.
  if v_total = 10 and v_expirados = 3 and v_soma = 1000.00 then
    raise notice 'IQ) OK: relatorio ve 10 orcamentos, 3 expirados, R$ % em valor', v_soma;
  else
    raise notice 'IQ) FALHA: relatorio viu % orcamentos, % expirados, soma %', v_total, v_expirados, v_soma;
  end if;
end $$;

-- ── IR) o job atravessa vendedores sem confundi-los ─────────
do $$
declare v_a text; v_b text;
begin
  select status::text into v_a from public.quotes where notes = 'EXP-VENCIDO';
  select status::text into v_b from public.quotes where notes = 'EXP-VENDEDOR-B';
  if v_a = 'expired' and v_b = 'expired' then
    raise notice 'IR) OK: vencidos dos dois vendedores expiraram, cada um no proprio orcamento';
  else
    raise notice 'IR) FALHA: A=% B=%', v_a, v_b;
  end if;
end $$;

-- ── IS..IU) superfície de segurança ─────────────────────────
do $$
begin
  if has_function_privilege('authenticated', 'public.expire_quotes()', 'execute')
     or has_function_privilege('anon', 'public.expire_quotes()', 'execute')
     or has_function_privilege('public', 'public.expire_quotes()', 'execute') then
    raise notice 'IS) FALHA: expire_quotes() alcancavel por anon/authenticated/PUBLIC';
  else
    raise notice 'IS) OK: expire_quotes() fora do alcance de anon, authenticated e PUBLIC';
  end if;
end $$;

do $$
declare v_secdef boolean; v_config text[]; v_dono text;
begin
  select p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner)
    into v_secdef, v_config, v_dono
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'expire_quotes';

  if v_secdef and v_config @> array['search_path=public'] then
    raise notice 'IT) OK: security definer com search_path fixo (dono: %)', v_dono;
  else
    raise notice 'IT) FALHA: secdef=% config=% dono=%', v_secdef, v_config, v_dono;
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_quotes_expiration') then
    raise notice 'IU) OK: indice parcial idx_quotes_expiration existe';
  else
    raise notice 'IU) FALHA: indice idx_quotes_expiration ausente';
  end if;
end $$;

-- ── IV..IX) do lado do vendedor ─────────────────────────────
set role authenticated;
set request.jwt.claim.sub = 'eeeeeeee-0000-4000-8000-00000000e001';
set request.jwt.claim.role = 'authenticated';

do $$ begin
  perform public.expire_quotes();
  raise notice 'IV) FALHA: vendedor executou expire_quotes()';
exception
  when insufficient_privilege then raise notice 'IV) OK: expire_quotes() negada ao vendedor';
end $$;

do $$
declare v_linhas integer;
begin
  update public.quotes set status = 'draft' where notes = 'EXP-VENDEDOR-B';
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then raise notice 'IW) OK: vendedor A nao altera o status do orcamento do vendedor B';
  else raise notice 'IW) FALHA DE SEGURANCA: vendedor A alterou % orcamento(s) alheio(s)', v_linhas; end if;
exception when others then
  raise notice 'IW) OK: vendedor A bloqueado ao mexer em orcamento alheio (%)', sqlerrm;
end $$;

do $$
declare v_vistos integer;
begin
  select count(*) into v_vistos from public.quotes where notes = 'EXP-VENDEDOR-B';
  if v_vistos = 0 then raise notice 'IX) OK: vendedor A nem enxerga o orcamento do vendedor B';
  else raise notice 'IX) FALHA: vendedor A enxerga % orcamento(s) do vendedor B', v_vistos; end if;
end $$;

reset role;

-- ── IY) agendamento ─────────────────────────────────────────
-- Em PostgreSQL puro o pg_cron não existe, e a migration precisa ter
-- passado assim mesmo — é justamente o que este teste confirma.
do $$
declare v_jobs integer;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'IY) OK: sem pg_cron, a migration aplicou como no-op (agendamento pendente de habilitar a extensao)';
    return;
  end if;
  execute 'select count(*) from cron.job where jobname = ''expirar-orcamentos''' into v_jobs;
  if v_jobs = 1 then raise notice 'IY) OK: job expirar-orcamentos agendado uma unica vez';
  else raise notice 'IY) FALHA: % job(s) expirar-orcamentos', v_jobs; end if;
end $$;
