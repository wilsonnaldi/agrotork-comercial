-- ============================================================
-- instagram_curator — endurecimento do schema privado
--
-- Igual à anterior: recuperada de
-- `supabase_migrations.schema_migrations.statements` em 11/09/2026, byte
-- a byte, sem reescrita.
--
--   comprimento  632 caracteres
--   md5          b405e852576aff7c7eec6d7fc2dbf22d
--
-- Acrescenta o índice de `locks.run_id` e a policy de `service_role` nas
-- seis tabelas. Já aplicada em produção (version 20260910151534).
-- ============================================================

create index if not exists locks_run_id_idx
  on instagram_curator.locks (run_id)
  where run_id is not null;

do $$
declare
  t text;
begin
  foreach t in array array['references','artifacts','runs','events','editorial_rules','locks']
  loop
    if not exists (
      select 1
      from pg_policies
      where schemaname='instagram_curator'
        and tablename=t
        and policyname='service_role_full_access'
    ) then
      execute format(
        'create policy service_role_full_access on instagram_curator.%I for all to service_role using (true) with check (true)',
        t
      );
    end if;
  end loop;
end $$;
