-- ============================================================
-- BRAIN — uma policy permissiva por ação em `brain.channels`
-- ============================================================
-- O advisor de desempenho do Supabase, rodado logo depois do deploy da
-- Fase 1 em produção (11/09/2026), acusou o ÚNICO aviso novo do BRAIN:
--
--   multiple_permissive_policies em brain.channels, papel authenticated,
--   ação SELECT: {channels_admin_write, channels_select}
--
-- `channels_admin_write` era `for all`, e `for all` inclui SELECT — então
-- todo SELECT de um usuário autenticado avaliava DUAS policies, sendo
-- que `is_admin()` já implica `is_active_user()`. Semanticamente nada
-- vazava; era só trabalho repetido numa tabela de 12 linhas.
--
-- A correção separa a escrita em três policies, uma por ação, e deixa a
-- leitura com uma só. Quem lê continua lendo; quem escreve continua
-- precisando ser administrador.

drop policy if exists channels_admin_write on brain.channels;

create policy channels_admin_insert on brain.channels for insert to authenticated
  with check ((select public.is_admin()));
create policy channels_admin_update on brain.channels for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy channels_admin_delete on brain.channels for delete to authenticated
  using ((select public.is_admin()));

-- Guarda: nenhuma tabela do brain pode ter mais de uma policy permissiva
-- para (papel, ação) — é isso que o advisor mede.
do $$
declare r record;
begin
  for r in
    select tablename, roles, cmd, count(*) as n
      from pg_policies
     where schemaname = 'brain' and permissive = 'PERMISSIVE'
     group by tablename, roles, cmd
    having count(*) > 1
  loop
    raise exception 'brain.% tem % policies permissivas para % em % — o advisor vai acusar', r.tablename, r.n, r.roles, r.cmd;
  end loop;
end
$$;
