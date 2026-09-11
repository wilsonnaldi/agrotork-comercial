-- ============================================================
-- BRAIN — `keep_authorship` não é IMMUTABLE
--
-- O defeito: `brain.keep_authorship()` foi declarada `immutable` em
-- 20260911140000. Ela não é: chama `brain.profile_missing()`, que LÊ
-- `public.profiles`. Uma função que lê tabela é `stable`, no máximo.
--
-- Por que isso importa, medido e não suposto
-- (supabase/db-tests/29_brain_volatilidade.sql, VL1):
--
--   insert  perfil
--   prepare fixa as select brain.keep_authorship(null::uuid, '<perfil>'::uuid);
--   execute fixa;        -- devolve o uuid  (certo: o perfil existe)
--   ... 4 execuções, o plano genérico entra ...
--   delete  perfil
--   execute fixa;        -- AINDA devolve o uuid  ← ERRADO
--   select brain.profile_missing('<perfil>');  -- t: o perfil sumiu
--
-- `immutable` autoriza o planejador a AVALIAR a chamada com argumento
-- constante e congelar o resultado dentro do plano. O plano em cache
-- passa a mentir sobre um dado que mudou.
--
-- A consequência prática é exatamente o defeito que 20260911140000 veio
-- consertar: `check_links()` chamaria `keep_authorship` e receberia o
-- valor velho, restaurando a autoria que a FK acabou de anular — e a
-- exclusão do perfil voltaria a falhar. O gatilho passa parâmetros, não
-- constantes, o que esconde o problema no caminho comum; mas a
-- declaração continua errada, e o dia em que alguém chamar a função com
-- constante — numa view, num `check`, num índice de expressão — o erro
-- aparece calado.
--
-- A correção é uma palavra: `stable`.
-- ============================================================

-- `create or replace` não muda volatilidade de uma função SQL já
-- existente? Muda — mas só se a nova definição a declarar. Aqui declara.
create or replace function brain.keep_authorship(p_new uuid, p_old uuid)
returns uuid language sql stable security invoker set search_path = '' as $$
  select case
    when p_new is not distinct from p_old then p_old
    when p_new is null and p_old is not null and brain.profile_missing(p_old) then null
    else p_old        -- qualquer outra troca é falsificação: ignora-se
  end;
$$;

revoke execute on function brain.keep_authorship(uuid, uuid) from public, anon;
grant  execute on function brain.keep_authorship(uuid, uuid) to authenticated, service_role;

-- Guarda: nenhuma função do BRAIN que leia tabela pode voltar a ser
-- `immutable`. As únicas imutáveis legítimas são as que só fazem conta
-- sobre o argumento — normalização de telefone, de identidade.
do $$
declare v_errada text;
begin
  select string_agg(p.proname, ', ') into v_errada
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain'
     and p.provolatile = 'i'
     and p.proname not in ('normalize_phone', 'normalize_identity');
  if v_errada is not null then
    raise exception 'Funcao(oes) do brain declarada(s) IMMUTABLE sem ser: %', v_errada;
  end if;
end
$$;
