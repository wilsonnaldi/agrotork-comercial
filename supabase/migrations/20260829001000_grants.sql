-- ============================================================
-- 1000 · Privilégios explícitos
--
-- O Supabase concede privilégios a anon/authenticated por default
-- privileges. Declarar explicitamente evita depender desse padrão e
-- deixa claro no repositório quem alcança o quê.
--
-- Privilégio (GRANT) diz "pode tentar"; a policy de RLS diz "pode de fato".
-- As duas camadas atuam juntas.
-- ============================================================

grant usage on schema public to anon, authenticated, service_role;

-- Tabelas e views: o acesso real continua sendo decidido pelo RLS.
grant select, insert, update, delete on all tables in schema public
  to authenticated;
grant select on all tables in schema public to anon;
grant all on all tables in schema public to service_role;

-- `anon` não tem policy em nenhuma tabela — logo, enxerga zero linhas.
-- O grant acima existe só para que rotas públicas futuras (link de
-- orçamento compartilhado) possam ser liberadas por policy, sem
-- precisar mexer em privilégio.

-- Sequências (nenhuma em uso hoje; garante o futuro).
grant usage, select on all sequences in schema public to authenticated, service_role;

-- Mesmas regras valem para o que for criado daqui em diante.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant select on tables to anon;
alter default privileges in schema public
  grant all on tables to service_role;

-- ── Funções de manutenção: fora do alcance do usuário final ──
-- São chamadas por triggers (que rodam como o dono, por serem
-- security definer) ou por rotina administrativa.
revoke execute on function public.expire_quotes()                from public, anon, authenticated;
revoke execute on function public.next_quote_number(integer)     from public, anon, authenticated;
revoke execute on function public.recalculate_quote_totals(uuid) from public, anon, authenticated;

grant execute on function public.expire_quotes() to service_role;
