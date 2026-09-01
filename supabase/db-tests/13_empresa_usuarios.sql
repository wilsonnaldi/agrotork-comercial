-- ============================================================
-- EMPRESA E USUÁRIOS (Fase 1, fechamento).
--
-- Duas telas novas, e as duas escrevem em lugares sensíveis:
-- `app_settings` (cabeçalho que vai ao cliente no PDF) e `profiles.role`
-- (quem enxerga custo e margem). A interface esconde os botões; quem
-- REALMENTE decide é o RLS, e é isso que se testa aqui.
--
-- Contexto herdado: admin 1111…, vendedor 2222… (criados em 01 e 02).
-- ============================================================
\set ON_ERROR_STOP on
reset role;

set role authenticated;
set request.jwt.claim.role = 'authenticated';

-- ── Dados da empresa ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

update public.app_settings
   set value = value || '{"legal_name":"AGROTORK LTDA","city":"Londrina"}'::jsonb
 where key = 'company';

select 'IA) admin grava os dados da empresa' as teste,
       case when value ->> 'legal_name' = 'AGROTORK LTDA' then 'OK' else 'FALHA' end as resultado
from public.app_settings where key = 'company';

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select 'IB) vendedor LÊ os dados da empresa' as teste,
       case when count(*) = 1 then 'OK: precisa disso para gerar o PDF' else 'FALHA' end as resultado
from public.app_settings where key = 'company';

do $$ declare afetadas int; begin
  update public.app_settings set value = '{"legal_name":"INVADIDO"}'::jsonb where key = 'company';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'IC) OK: vendedor nao altera os dados da empresa';
  else raise notice 'IC) FALHA DE SEGURANCA: vendedor alterou % linha(s)', afetadas; end if;
exception when others then
  raise notice 'IC) OK: vendedor nao altera os dados da empresa (recusado)';
end $$;

select 'ID) o cabeçalho continua intacto' as teste,
       case when value ->> 'legal_name' = 'AGROTORK LTDA' then 'OK' else 'FALHA: ' || (value ->> 'legal_name') end as resultado
from public.app_settings where key = 'company';

-- O vendedor também não enxerga outras chaves de configuração.
select 'IE) vendedor só enxerga a chave company' as teste,
       case when count(*) filter (where key <> 'company') = 0 then 'OK' else 'FALHA' end as resultado
from public.app_settings;

-- ── Papel de usuário ────────────────────────────────────────
do $$ declare afetadas int; begin
  update public.profiles set role = 'admin' where id = '22222222-2222-2222-2222-222222222222';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'IF) OK: vendedor nao se promove';
  else raise notice 'IF) FALHA DE SEGURANCA: vendedor se promoveu'; end if;
exception when others then
  raise notice 'IF) OK: vendedor nao se promove (recusado pelo RLS)';
end $$;

do $$ declare afetadas int; begin
  update public.profiles set is_active = false where id = '11111111-1111-1111-1111-111111111111';
  get diagnostics afetadas = row_count;
  if afetadas = 0 then raise notice 'IG) OK: vendedor nao desativa o administrador';
  else raise notice 'IG) FALHA DE SEGURANCA: vendedor desativou o administrador'; end if;
exception when others then
  raise notice 'IG) OK: vendedor nao desativa o administrador (recusado)';
end $$;

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

do $$ declare afetadas int; begin
  update public.profiles set role = 'admin' where id = '22222222-2222-2222-2222-222222222222';
  get diagnostics afetadas = row_count;
  if afetadas = 1 then raise notice 'IH) OK: administrador promove vendedor';
  else raise notice 'IH) FALHA: administrador nao conseguiu promover'; end if;
end $$;

do $$ declare afetadas int; begin
  update public.profiles set role = 'salesperson' where id = '22222222-2222-2222-2222-222222222222';
  get diagnostics afetadas = row_count;
  if afetadas = 1 then raise notice 'II) OK: administrador rebaixa de volta';
  else raise notice 'II) FALHA'; end if;
end $$;

-- ── A trava do último administrador é da aplicação ──────────
-- O banco PERMITE o admin se rebaixar: RLS não conta administradores.
-- Quem impede é `changeRole()` em src/modules/users/service.ts. Este
-- teste registra a fronteira, para ninguém supor proteção onde não há.
select 'IJ) quantos administradores ativos existem' as teste,
       count(*)::text || ' (a trava de "último admin" é da aplicação, não do RLS)' as resultado
from public.profiles where role = 'admin' and is_active;

reset role;
