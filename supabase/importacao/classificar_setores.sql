-- ============================================================
-- CLASSIFICAÇÃO DOS 112 PRODUTOS DA CARGA EM SETORES COMERCIAIS
--
-- Os 7 setores são o que a AGROTORK precifica de forma diferente,
-- e é por eles que a tela de margem se organiza.
--
-- A lista de códigos é EXPLÍCITA de propósito. Classificar por
-- palavra no nome erraria os 24 'DRONE MIX' da JR, que não são
-- aeronaves e sim misturadores e abastecedores de solo.
--
-- Escopo: SÓ os produtos vindos das duas tabelas de fabricante.
-- Produto cadastrado à mão depois não é tocado.
--
-- Idempotente: rodar duas vezes deixa o mesmo resultado.
-- Transacional: ou classifica os 112, ou não mexe em nada.
--
--   psql "$DATABASE_URL" -f supabase/importacao/classificar_setores.sql
-- ============================================================
begin;

-- ── Guarda: a carga tem de estar íntegra ────────────────────
do $$
declare v_carga int; v_sem int;
begin
  select count(*) into v_carga from public.products p
   where p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.deleted_at is null;
  if v_carga <> 112 then
    raise exception 'PARE: esperava 112 produtos das tabelas de fabricante, encontrei %.', v_carga;
  end if;
  select count(*) into v_sem from public.products p
   where p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.deleted_at is null and p.category_id is null;
  raise notice 'Antes: % dos 112 produtos da carga sem setor', v_sem;
end $$;

-- ── Renomeia o que já existe, em vez de duplicar ────────────
-- `Tecnologia`, `Peças` e `Acessórios` estão vazias e viram setor.
-- `Implementos` e `Serviços` ficam intactas, para Baldan e Kuhn.
update public.categories set name = 'Drones'
 where name = 'Tecnologia' and not exists (select 1 from public.categories where name = 'Drones');
update public.categories set name = 'Peças e acessórios'
 where name = 'Peças' and not exists (select 1 from public.categories where name = 'Peças e acessórios');
update public.categories set name = 'Acessórios de solo'
 where name = 'Acessórios' and not exists (select 1 from public.categories where name = 'Acessórios de solo');

-- ── Cria os setores que faltam e mantém a descrição em dia ──
insert into public.categories (name, description) values ('Drones', 'Aeronaves DJI e Mavic: combos, drones avulsos e multiespectral.') on conflict do nothing;
insert into public.categories (name, description) values ('Baterias e energia', 'Baterias, carregadores, geradores e fontes.') on conflict do nothing;
insert into public.categories (name, description) values ('Pulverização', 'Kit de pulverização, dispersor de sólidos, kit de bicos e lift.') on conflict do nothing;
insert into public.categories (name, description) values ('Agricultura de Precisão', 'RTK, relay e posicionamento.') on conflict do nothing;
insert into public.categories (name, description) values ('Peças e acessórios', 'Rádio controle, cabo, resfriador, tripé, bastão e base.') on conflict do nothing;
insert into public.categories (name, description) values ('Abastecimento e apoio de solo', 'DRONE MIX, feeder, tanques e incorporadores. Equipamento de solo, não aeronave.') on conflict do nothing;
insert into public.categories (name, description) values ('Acessórios de solo', 'Bico de abastecimento, medidor, aquecimento, carretel, rack e estrutura.') on conflict do nothing;
update public.categories set description = 'Aeronaves DJI e Mavic: combos, drones avulsos e multiespectral.' where name = 'Drones';
update public.categories set description = 'Baterias, carregadores, geradores e fontes.' where name = 'Baterias e energia';
update public.categories set description = 'Kit de pulverização, dispersor de sólidos, kit de bicos e lift.' where name = 'Pulverização';
update public.categories set description = 'RTK, relay e posicionamento.' where name = 'Agricultura de Precisão';
update public.categories set description = 'Rádio controle, cabo, resfriador, tripé, bastão e base.' where name = 'Peças e acessórios';
update public.categories set description = 'DRONE MIX, feeder, tanques e incorporadores. Equipamento de solo, não aeronave.' where name = 'Abastecimento e apoio de solo';
update public.categories set description = 'Bico de abastecimento, medidor, aquecimento, carretel, rack e estrutura.' where name = 'Acessórios de solo';

-- ── Classificação, setor por setor ──────────────────────────
-- Drones: 18 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Drones'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('DJI-001','DJI-002','DJI-003','DJI-004','DJI-005','DJI-006','DJI-007','DJI-008','DJI-009','DJI-010','DJI-011','DJI-012','DJI-040','DJI-041','DJI-042','DJI-043','DJI-044','DJI-065');

-- Baterias e energia: 21 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Baterias e energia'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('DJI-023','DJI-024','DJI-025','DJI-026','DJI-027','DJI-028','DJI-029','DJI-030','DJI-031','DJI-032','DJI-033','DJI-034','DJI-035','DJI-036','DJI-037','DJI-038','DJI-039','DJI-066','DJI-079','DJI-080','DJI-081');

-- Pulverização: 20 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Pulverização'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('DJI-045','DJI-046','DJI-047','DJI-048','DJI-049','DJI-050','DJI-051','DJI-052','DJI-053','DJI-055','DJI-056','DJI-057','DJI-058','DJI-059','DJI-060','DJI-061','DJI-062','DJI-063','DJI-064','DJI-087');

-- Agricultura de Precisão: 4 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Agricultura de Precisão'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('DJI-068','DJI-069','DJI-071','DJI-072');

-- Peças e acessórios: 11 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Peças e acessórios'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('DJI-070','DJI-073','DJI-074','DJI-075','DJI-076','DJI-077','DJI-078','DJI-082','DJI-083','DJI-084','DJI-085');

-- Abastecimento e apoio de solo: 30 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Abastecimento e apoio de solo'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('JR-001','JR-002','JR-003','JR-004','JR-005','JR-006','JR-007','JR-008','JR-009','JR-010','JR-011','JR-012','JR-013','JR-014','JR-017','JR-018','JR-019','JR-020','JR-021','JR-022','JR-023','JR-024','JR-025','JR-026','JR-027','JR-028','JR-029','JR-038','JR-039','JR-040');

-- Acessórios de solo: 8 produto(s)
update public.products p set category_id = c.id
  from public.categories c where c.name = 'Acessórios de solo'
  and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.code in ('JR-030','JR-031','JR-032','JR-033','JR-034','JR-035','JR-036','JR-037');

-- ── Verificação: ninguém da carga pode sobrar ───────────────
do $$
declare v_sem int; r record;
begin
  select count(*) into v_sem from public.products p
   where p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR') and p.deleted_at is null and p.category_id is null;
  if v_sem > 0 then raise exception 'PARE: % produto(s) da carga ficaram sem setor', v_sem; end if;
  for r in select c.name, count(p.id) n from public.categories c
            left join public.products p on p.category_id = c.id and p.deleted_at is null
           and p.source_catalog in ('TABELA SUBDEALER','TABELA REV JR')
           group by c.name order by 2 desc, 1 loop
    raise notice '  %  %', lpad(r.n::text, 4), r.name;
  end loop;
  raise notice 'Depois: 112/112 produtos da carga com setor definido';
end $$;

commit;
