-- ============================================================
-- Fornecedores (migration 20260903100000).
--
-- O que este arquivo prova:
--   · a normalização de documento e CEP acontece no BANCO, não na tela;
--   · CNPJ repetido é recusado, mesmo digitado com pontuação diferente;
--   · fornecedor sem documento continua permitido, e mais de um;
--   · o vendedor LÊ mas não escreve — comprar é da administração;
--   · desativar preserva o cadastro; excluído some da listagem.
-- ============================================================
reset role;

insert into auth.users (id, email, raw_user_meta_data) values
 ('dddddddd-0000-4000-8000-00000000d001','forn.admin@teste.local','{"full_name":"Admin Fornecedor","role":"admin"}'),
 ('dddddddd-0000-4000-8000-00000000d002','forn.vend@teste.local','{"full_name":"Vendedor Fornecedor","role":"salesperson"}');

update public.profiles set role = 'admin'
 where id = 'dddddddd-0000-4000-8000-00000000d001';

set role authenticated;
set request.jwt.claim.role = 'authenticated';
select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d001', false);

-- ── FN1: administrador cadastra, e o banco normaliza ────────
do $$
declare v_doc text; v_cep text; v_uf text;
begin
  insert into public.suppliers (name, document, zip_code, state, contact_name)
  values ('DJI Brasil Teste', '12.345.678/0001-90', '86.000-000', 'pr', 'Representante Teste');

  select document, zip_code, state into v_doc, v_cep, v_uf
    from public.suppliers where name = 'DJI Brasil Teste';

  if v_doc = '12345678000190' and v_cep = '86000000' and v_uf = 'PR'
    then raise notice 'FN1) OK: documento, CEP e UF normalizados pelo banco — % / % / %', v_doc, v_cep, v_uf;
    else raise notice 'FN1) FALHA: % / % / %', v_doc, v_cep, v_uf; end if;
end $$;

-- ── FN2: o mesmo CNPJ com outra pontuação é recusado ────────
-- É o teste que dá sentido à normalização: sem ela, o índice único não
-- perceberia que é o mesmo fornecedor.
do $$
declare v_erro text; v_quantos int;
begin
  begin
    insert into public.suppliers (name, document)
    values ('DJI Brasil Duplicada', '12345678/0001-90');
    raise notice 'FN2) FALHA: aceitou o mesmo CNPJ com outra pontuacao';
  exception when unique_violation then
    select count(*)::int into v_quantos from public.suppliers where document = '12345678000190';
    raise notice 'FN2) OK: duplicata barrada, segue % cadastro(s) com esse CNPJ', v_quantos;
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'FN2) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

-- ── FN3: sem documento pode, e mais de um ───────────────────
-- Oficina pequena, autônomo, fornecedor eventual: exigir CNPJ travaria
-- cadastro legítimo. O índice é parcial de propósito.
do $$
declare v_sem int;
begin
  insert into public.suppliers (name) values ('Oficina Sem Documento A');
  insert into public.suppliers (name) values ('Oficina Sem Documento B');
  select count(*)::int into v_sem from public.suppliers where document is null;
  if v_sem >= 2
    then raise notice 'FN3) OK: % fornecedores sem documento convivem', v_sem;
    else raise notice 'FN3) FALHA: so % sem documento', v_sem; end if;
end $$;

-- ── FN4: o vendedor LÊ ──────────────────────────────────────
select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d002', false);

do $$
declare v_vistos int;
begin
  select count(*)::int into v_vistos from public.suppliers;
  if v_vistos >= 3
    then raise notice 'FN4) OK: vendedor enxerga os % fornecedores', v_vistos;
    else raise notice 'FN4) FALHA: vendedor viu % (esperado 3 ou mais)', v_vistos; end if;
end $$;

-- ── FN5: mas não cadastra, não altera e não apaga ───────────
-- Quem decide de quem a empresa compra é a administração.
do $$
declare v_falhas text := ''; v_antes int; v_depois int;
begin
  select count(*)::int into v_antes from public.suppliers;

  begin insert into public.suppliers (name) values ('Fornecedor do Vendedor');
        v_falhas := v_falhas || ' cadastrou'; exception when others then null; end;
  begin update public.suppliers set name = 'Nome trocado pelo vendedor';
        if found then v_falhas := v_falhas || ' alterou'; end if;
        exception when others then null; end;
  begin delete from public.suppliers;
        if found then v_falhas := v_falhas || ' apagou'; end if;
        exception when others then null; end;

  select count(*)::int into v_depois from public.suppliers;

  if v_falhas = '' and v_antes = v_depois
    then raise notice 'FN5) OK: vendedor nao cadastra, nao altera e nao apaga fornecedor';
    else raise notice 'FN5) FALHA: passou em ->% (antes % / depois %)', v_falhas, v_antes, v_depois; end if;
end $$;

-- ── FN6: desativar preserva; excluir some da listagem ───────
select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d001', false);

do $$
declare v_ativo boolean; v_ainda int; v_apos int;
begin
  update public.suppliers set is_active = false where name = 'Oficina Sem Documento A';
  select is_active into v_ativo from public.suppliers where name = 'Oficina Sem Documento A';
  select count(*)::int into v_ainda from public.suppliers where name = 'Oficina Sem Documento A';

  if v_ativo = false and v_ainda = 1
    then raise notice 'FN6) OK: desativado continua cadastrado e visivel para o admin';
    else raise notice 'FN6) FALHA: ativo % / encontrado %', v_ativo, v_ainda; end if;

  -- Exclusão lógica: some da listagem, mas a linha continua no banco
  -- para o histórico de compras não ficar órfão.
  --
  -- Vai pela função, e não por UPDATE: a policy de SELECT exige
  -- `deleted_at is null`, e o PostgreSQL aplica as policies de SELECT
  -- sobre a linha RESULTANTE do UPDATE. O update direto é recusado até
  -- para o administrador. FN7b prova isso.
  perform public.delete_supplier(
    (select id from public.suppliers where name = 'Oficina Sem Documento B'));
  select count(*)::int into v_apos from public.suppliers where name = 'Oficina Sem Documento B';
  if v_apos = 0
    then raise notice 'FN7) OK: excluido sai da listagem pela RLS, sem apagar a linha';
    else raise notice 'FN7) FALHA: excluido ainda aparece'; end if;
end $$;

-- ── FN7b: e a linha continua no banco, não foi apagada ──────
-- Sem esta conferência, FN7 passaria igual se a função tivesse feito
-- DELETE de verdade — e o histórico de compras ficaria órfão.
do $$
declare v_linhas int;
begin
  reset role;
  select count(*)::int into v_linhas
    from public.suppliers where name = 'Oficina Sem Documento B' and deleted_at is not null;
  if v_linhas = 1
    then raise notice 'FN7b) OK: a linha continua no banco, marcada como excluida';
    else raise notice 'FN7b) FALHA: encontrei % linha(s) excluidas', v_linhas; end if;
end $$;

-- ── FN7c: o UPDATE direto continua recusado, de propósito ───
-- É o defeito que a migration 20260903110000 documenta. Este teste
-- existe para ninguém "simplificar" a função de volta para um UPDATE.
set role authenticated;
select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d001', false);

do $$
declare v_erro text;
begin
  begin
    update public.suppliers set deleted_at = now() where name = 'Oficina Sem Documento A';
    raise notice 'FN7c) FALHA: o UPDATE direto passou — a policy de SELECT afrouxou';
  exception when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'FN7c) OK: UPDATE direto recusado — %', left(v_erro, 50);
  end;
end $$;

-- ── FN7d: o vendedor não exclui nem pela função ─────────────
select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d002', false);

do $$
declare v_erro text; v_id uuid;
begin
  select id into v_id from public.suppliers where name = 'DJI Brasil Teste';
  begin
    perform public.delete_supplier(v_id);
    raise notice 'FN7d) FALHA: vendedor excluiu fornecedor pela funcao';
  exception when insufficient_privilege then
    raise notice 'FN7d) OK: vendedor barrado na funcao de exclusao';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'FN7d) FALHA: recusou pelo motivo errado — %', v_erro;
  end;
end $$;

select set_config('request.jwt.claim.sub', 'dddddddd-0000-4000-8000-00000000d001', false);

-- ── FN8: anônimo não alcança ────────────────────────────────
do $$
declare v_erro text;
begin
  reset role;
  set local role anon;
  begin
    perform 1 from public.suppliers;
    raise notice 'FN8) FALHA: anonimo alcancou suppliers';
  exception when insufficient_privilege then
    raise notice 'FN8) OK: anonimo sem privilegio em suppliers';
  when others then
    get stacked diagnostics v_erro = message_text;
    raise notice 'FN8) OK: anonimo barrado — %', left(v_erro, 45);
  end;
end $$;

reset role;
