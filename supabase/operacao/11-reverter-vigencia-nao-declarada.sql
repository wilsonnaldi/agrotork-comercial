-- ============================================================
-- 11 · Rollback de 20260917030427_brain_vigencia_nao_declarada
-- ============================================================
-- Restaura brain.stamp_version() na definicao de
-- 20260912010000_brain_memoria_esquema.sql — byte a byte, incluindo
-- comentarios e espacos: o corpo abaixo foi extraido daquele arquivo sem
-- nenhuma edicao.
--
-- Efeito de rodar isto: ao ativar uma versao sem inicio de vigencia
-- declarado, o banco volta a CARIMBAR `coalesce(document_date, current_date)`
-- em `valid_from`. Ou seja, isto reintroduz o defeito de proposito — a data
-- tecnica do arquivo volta a virar vigencia comercial, e a versao sem data
-- nenhuma volta a declarar que comecou no dia em que alguem a ativou.
-- Volta tambem o encerramento da versao anterior no proprio dia em que ela
-- comecou, quando a sucessora nao declara inicio.
--
-- So se usa se a correcao quebrar algo pior em producao.
--
-- NAO desfaz dado: linhas ja gravadas ficam como estao, com ou sem
-- `valid_from`. O gatilho e BEFORE e so age em gravacao nova.
--
-- Guard: a funcao tem de existir antes de trocar; no fim confere que o
-- fallback voltou e que ninguem ficou com EXECUTE indevido. Transacional.
--
-- Rodar:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/operacao/11-reverter-vigencia-nao-declarada.sql
-- ============================================================
begin;

do $guard$
begin
  if to_regprocedure('brain.stamp_version()') is null then
    raise exception 'ABORTADO: brain.stamp_version() nao existe neste banco';
  end if;
  if not exists (
    select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'brain' and p.proname = 'stamp_version' and not t.tgisinternal) then
    raise exception 'ABORTADO: nenhum gatilho usa brain.stamp_version() — banco nao e o que a auditoria descreve';
  end if;
end
$guard$;

-- ── definicao original (20260912010000), byte a byte ────────
create or replace function brain.stamp_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  select d.access_level into new.access_level from brain.documents d where d.id = new.document_id;
  if new.access_level is null then
    raise exception 'Versao sem documento: %', new.document_id using errcode = 'foreign_key_violation';
  end if;

  if tg_op = 'UPDATE' then
    if new.file_sha256 is distinct from old.file_sha256
    or new.storage_path is distinct from old.storage_path
    or new.storage_bucket is distinct from old.storage_bucket
    or new.file_size is distinct from old.file_size
    or new.mime_type is distinct from old.mime_type
    or new.original_filename is distinct from old.original_filename
    or new.document_id is distinct from old.document_id then
      raise exception 'O arquivo de uma versao e imutavel (sha256, caminho, tamanho, tipo, nome). Arquivo diferente e versao nova.'
        using errcode = 'restrict_violation';
    end if;
  end if;

  -- Ao ativar, a vigente anterior passa a superseded e as duas se apontam.
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    update brain.document_versions v
       set status = 'superseded',
           superseded_by_id = new.id,
           -- Nunca antes do proprio inicio: ativar uma edicao com data mais antiga
           -- que a vigente e raro, mas nao pode virar excecao de constraint.
           valid_to = coalesce(v.valid_to, greatest(new.valid_from - 1, v.valid_from), current_date)
     where v.document_id = new.document_id and v.status = 'active' and v.id <> new.id;
    if new.supersedes_id is null then
      select v.id into new.supersedes_id from brain.document_versions v
       where v.document_id = new.document_id and v.superseded_by_id = new.id
       order by v.imported_at desc limit 1;
    end if;
    new.valid_from := coalesce(new.valid_from, new.document_date, current_date);
    -- Reativar uma edicao (superseded/withdrawn → active) reabre a vigencia,
    -- a menos que o mesmo UPDATE tenha fixado um valid_to de proposito.
    if tg_op = 'UPDATE' and new.valid_to is not distinct from old.valid_to then
      new.valid_to := null;
    end if;
  end if;

  -- Estados sem ambiguidade (auditoria pre-publicacao):
  --   · ativar e um ato de HOJE: `valid_from` no futuro nao existe — a edicao
  --     que ainda nao vale fica `draft` ate o dia, e so entao e ativada. Sem
  --     isso, o documento ficaria sem edicao vigente entre a ativacao e a data;
  --   · `superseded` sempre tem fim de vigencia: sem `valid_to` seria uma
  --     "antiga" que nunca terminou.
  if new.status = 'active' and new.valid_from > current_date then
    raise exception 'Nao se ativa uma versao com valid_from no futuro (%). Deixe em draft ate la.', new.valid_from
      using errcode = 'check_violation';
  end if;
  if new.status = 'superseded' then
    new.valid_to := coalesce(new.valid_to, current_date);
  end if;
  return new;
end;
$$;

revoke execute on function brain.stamp_version() from public, anon, authenticated;

comment on function brain.stamp_version() is null;
comment on column brain.document_versions.valid_from is null;
comment on column brain.document_versions.valid_to is null;

do $conf$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'brain' and p.proname = 'stamp_version';
  if v_src not like '%coalesce(new.valid_from, new.document_date, current_date)%' then
    raise exception 'ABORTADO: o fallback de data nao voltou — a definicao restaurada nao e a original';
  end if;
  if has_function_privilege('anon', 'brain.stamp_version()', 'execute')
  or has_function_privilege('authenticated', 'brain.stamp_version()', 'execute') then
    raise exception 'ABORTADO: anon ou authenticated ficou com EXECUTE em stamp_version()';
  end if;
  raise notice 'ROLLBACK 11 aplicado: valid_from volta a receber coalesce(document_date, current_date) na ativacao';
end
$conf$;

commit;
