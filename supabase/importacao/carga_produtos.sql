-- ============================================================
-- CARGA DE CATÁLOGO — 112 PRODUTOS (DJI + JR SOLUÇÕES)
--
-- GERADO por supabase/importacao/gerar-sql.mjs a partir de
-- supabase/importacao/dados/integrar_supabase.csv. NÃO EDITE À MÃO:
-- corrija a planilha, reexporte o CSV e gere de novo.
--
-- NÃO É UMA MIGRATION. Migrations mudam o schema; isto insere dados
-- comerciais e roda quando a AGROTORK mandar, não no `db push`.
--
-- O QUE ESTE SCRIPT GARANTE
--   1. Transação única: ou entram os 112, ou não entra nenhum.
--   2. Idempotente: casa por upper(code). Rodar duas vezes não duplica.
--   3. Produto que JÁ EXISTE tem só o cadastro atualizado. Preço de
--      venda, sale_price_set_at e is_active NÃO são tocados — seriam
--      decisões comerciais sobrescritas por uma tabela de fabricante.
--   4. Produto NOVO entra com sale_price = 0, sale_price_set_at NULO
--      (preço nunca definido) e is_active = false.
--   5. manufacturer_code nunca fica com brand_id nulo: a marca que
--      faltar é criada aqui, antes, e a ausência vira erro.
--   6. Custo por condição: AVISTA e/ou FATURADO, uma linha cada.
--      PRECO_REVENDA_JR não é lido — duplicaria o custo à vista.
--   7. Relatório ao final, com o que entrou, o que foi atualizado e o
--      que ficou sem custo.
--
-- COMO RODAR (fora daqui, com autorização):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/importacao/carga_produtos.sql
-- ============================================================

begin;

-- ── 0. Marcas que a carga exige e o seed não tem ────────────
insert into public.brands (name, sort_order)
select v.nome, 100 + row_number() over (order by v.nome)
from (values
    ('JR SOLUCOES')
) as v(nome)
where not exists (
  select 1 from public.brands b
   where upper(b.name) = upper(v.nome) and b.deleted_at is null
);

-- ── 1. A carga, tal como saiu da planilha ───────────────────
create temporary table _carga (
  code             text primary key,
  name             text not null,
  manufacturer_code text,
  marca            text,
  categoria        text,
  unidade          text not null,
  custo_avista     numeric(14,2),
  custo_faturado   numeric(14,2),
  vigencia         date not null,
  observacao       text,
  source_type      text not null,
  source_brand     text,
  source_catalog   text,
  source_version   text,
  source_reference text,
  ncm              text
) on commit drop;

insert into _carga values
  ('DJI-001', 'DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000', null, 'DJI', null, 'UN', 161900, 165500, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-001', null),
  ('DJI-002', 'DRONE AGRAS T100 + 3 BAT + GERADOR D14000', null, 'DJI', null, 'UN', 170050, 173700, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-002', null),
  ('DJI-003', 'DRONE AGRAS T70P + 3 BAT + CARREGADOR C12000', null, 'DJI', null, 'UN', 128300, 131000, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-003', null),
  ('DJI-004', 'DRONE AGRAS T70P + 3 BAT + GERADOR D14000', null, 'DJI', null, 'UN', 136440, 139400, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-004', null),
  ('DJI-005', 'DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000', null, 'DJI', null, 'UN', 61789, 64250, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-005', null),
  ('DJI-006', 'DRONE AGRAS T25P + 3 BAT + GERADOR D6000', null, 'DJI', null, 'UN', 65292, 67900, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-006', null),
  ('DJI-007', 'DRONE AGRAS T55 + 3 BAT DB1050 + CARREGADOR C7000', null, 'DJI', null, 'UN', 96483, 101401, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-007', null),
  ('DJI-008', 'DRONE AGRAS T55 + 3 BAT DB1050 + GERADOR D8000', null, 'DJI', null, 'UN', 107364, 112825, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-008', null),
  ('DJI-009', 'DRONE AGRAS T55 + 3 BAT DB1580 + CARREGADOR C12000', null, 'DJI', null, 'UN', 113789, 119400, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-009', null),
  ('DJI-010', 'DRONE AGRAS T55 + 3 BAT DB1580 + GERADOR D14000', null, 'DJI', null, 'UN', 121069, 127200, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-010', null),
  ('DJI-011', 'DRONE AGRAS T100 + 6 BAT + 2 CARREGADORES C12000 + KIT DUAL BATTERY + 2 DC55', null, 'DJI', null, 'UN', 231321, 240600, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-011', null),
  ('DJI-012', 'DRONE AGRAS T100 + 6 BAT + 2 GERADORES D14000 + KIT DUAL BATTERY', null, 'DJI', null, 'UN', 247621, 257500, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-012', null),
  ('DJI-023', 'BATERIA T100 / T70P (DB2160)', 'DB2160', 'DJI', null, 'UN', 18330, 18750, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-023', null),
  ('DJI-024', 'BATERIA T25P / T25 (DB800)', 'DB800', 'DJI', null, 'UN', 7457, 7830, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-024', null),
  ('DJI-025', 'BATERIA T55 / T70P (DB1580)', 'DB1580', 'DJI', null, 'UN', 13225, 13886, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-025', null),
  ('DJI-026', 'BATERIA T55 (DB1050)', 'DB1050', 'DJI', null, 'UN', 9050, 9502, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-026', null),
  ('DJI-027', 'BATERIA T50 / T40 (DB1560)', 'DB1560', 'DJI', null, 'UN', 11500, 12000, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-027', null),
  ('DJI-028', 'BATERIA T20P', null, 'DJI', null, 'UN', 6950, 7230, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-028', null),
  ('DJI-029', 'BATERIA T30', null, 'DJI', null, 'UN', 13200, 13900, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-029', null),
  ('DJI-030', 'BATERIA T10', null, 'DJI', null, 'UN', 6800, 7100, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-030', null),
  ('DJI-031', 'CARREGADOR T100 / T70P (C12000)', 'C12000', 'DJI', null, 'UN', 12220, 12500, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-031', null),
  ('DJI-032', 'CARREGADOR T55 (C7000)', 'C7000', 'DJI', null, 'UN', 7052, 7405, '2026-09-01', 'confianca ALTA - provado: a diferenca entre os kits T55 DB1050 com C7000 e com D8000 bate exatamente nas duas colunas', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-032', null),
  ('DJI-033', 'CARREGADOR T50 / T40 (C10000)', 'C10000', 'DJI', null, 'UN', 10250, 11000, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-033', null),
  ('DJI-034', 'CARREGADOR T25P / T25 (C8000)', 'C8000', 'DJI', null, 'UN', 8100, 8500, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-034', null),
  ('DJI-035', 'CARREGADOR T10', null, 'DJI', null, 'UN', 7100, 7500, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-035', null),
  ('DJI-036', 'GERADOR T100 / T70P (D14000)', 'D14000', 'DJI', null, 'UN', 20370, 21000, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-036', null),
  ('DJI-037', 'GERADOR T55 (D8000)', 'D8000', 'DJI', null, 'UN', 17933, 18829, '2026-09-01', 'confianca ALTA - provado: a diferenca entre os kits T55 DB1050 com C7000 e com D8000 bate exatamente nas duas colunas', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-037', null),
  ('DJI-038', 'GERADOR T50 / T40 (D12000)', 'D12000', 'DJI', null, 'UN', 19500, 20300, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-038', null),
  ('DJI-039', 'GERADOR T25P / T25 (D6000)', 'D6000', 'DJI', null, 'UN', 11500, 12000, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-039', null),
  ('DJI-040', 'DRONE AVULSO T100', null, 'DJI', null, 'UN', 94700, 96750, '2026-09-01', 'confianca MEDIA - nao inclui kit WB37 | PROMOCAO DE CONFIANCA: As duas metades do T100 no Excel 2026 (47.350 + 47.350) somam exatamente 94.700, o preco a vista do DRONE AVULSO T100 na DJI. Confirmacao independente, mesmo criterio usado pela planilha para promover outros itens', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-040', null),
  ('DJI-041', 'DRONE AVULSO T70P', null, 'DJI', null, 'UN', 61100, 62500, '2026-09-01', 'confianca MEDIA - nao inclui kit WB37 | PROMOCAO DE CONFIANCA: As duas metades do T70P no Excel 2026 (30.550 + 30.550) somam exatamente 61.100, o preco a vista do DRONE AVULSO T70P na DJI. Confirmacao independente', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-041', null),
  ('DJI-042', 'DRONE AVULSO T25P', null, 'DJI', null, 'UN', 31961, 32888, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-042', null),
  ('DJI-043', 'DRONE AVULSO T100 (SEM KIT PULVERIZACAO)', null, 'DJI', null, 'UN', 78200, 79760, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-043', null),
  ('DJI-044', 'DRONE AVULSO T55', null, 'DJI', null, 'UN', 60591, 63620, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-044', null),
  ('DJI-045', 'KIT DE PULV. T100 DUAL BATTERY + CABO', null, 'DJI', 'Pulverização', 'UN', 20580, 21550, '2026-09-01', 'confianca ALTA - mesmo valor usado nos kits upgrade', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-045', null),
  ('DJI-046', 'KIT DE PULVERIZACAO DJI T100', null, 'DJI', 'Pulverização', 'UN', 16500, 16990, '2026-09-01', 'CORRECAO V4: os valores 16.500/16.990 pertencem ao KIT DE PULVERIZACAO DJI T100, linha imediatamente anterior ao bloco DISPERSOR DE SOLIDOS no PDF.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PDF DJI V16.2 | DRONE AVULSO | KIT DE PULVERIZACAO DJI T100', null),
  ('DJI-047', 'DISPERSOR DE SOLIDOS T70P', null, 'DJI', null, 'UN', 7030, 7200, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-047', null),
  ('DJI-048', 'DISPERSOR DE SOLIDOS T25P', null, 'DJI', null, 'UN', 6310, 6450, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-048', null),
  ('DJI-049', 'DISPERSOR DE SOLIDOS T55', null, 'DJI', null, 'UN', 8511, 8936, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-049', null),
  ('DJI-050', 'DISPERSOR DE SOLIDOS T50', null, 'DJI', null, 'UN', 4690, 4990, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-050', null),
  ('DJI-051', 'DISPERSOR DE SOLIDOS T25', null, 'DJI', null, 'UN', 4190, 4490, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-051', null),
  ('DJI-052', 'DISPERSOR DE SOLIDOS T40', null, 'DJI', null, 'UN', 5700, 5900, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-052', null),
  ('DJI-053', 'DISPERSOR DE SOLIDOS T20P', null, 'DJI', null, 'UN', 5500, 6000, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-053', null),
  ('DJI-055', 'DISPERSOR DE SOLIDOS T10', null, 'DJI', null, 'UN', 5500, 6000, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-055', null),
  ('DJI-056', 'KIT BICOS T100 (BICO DE NEVOA)', null, 'DJI', 'Pulverização', 'UN', 8000, 8320, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-056', null),
  ('DJI-057', 'KIT BICOS T70P (BICO DE NEVOA)', null, 'DJI', 'Pulverização', 'UN', 6000, 6240, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-057', null),
  ('DJI-058', 'KIT BICOS T25P', null, 'DJI', 'Pulverização', 'UN', 3670, 3750, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-058', null),
  ('DJI-059', 'KIT BICOS T55', null, 'DJI', 'Pulverização', 'UN', 7856, 8248, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-059', null),
  ('DJI-060', 'KIT BICOS T50', null, 'DJI', 'Pulverização', 'UN', 4000, 4160, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-060', null),
  ('DJI-061', 'KIT BICOS T25', null, 'DJI', 'Pulverização', 'UN', 3600, 3750, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-061', null),
  ('DJI-062', 'LIFT T100 (DUAL BATTERY)', null, 'DJI', null, 'UN', 9000, 9360, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-062', null),
  ('DJI-063', 'LIFT T70P', null, 'DJI', null, 'UN', 3100, 3250, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-063', null),
  ('DJI-064', 'LIFT T55 (DL100)', 'DL100', 'DJI', null, 'UN', 3785, 3974, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-064', null),
  ('DJI-065', 'DRONE MAVIC 3 MULTIS', null, 'DJI', null, 'UN', 28320, 29600, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-065', null),
  ('DJI-066', 'KIT 03 BATS MAVIC 3 MULT', null, 'DJI', null, 'UN', 4680, 4900, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-066', null),
  ('DJI-068', 'GNSS DJI BASE RTK DRTK3 AG', null, 'DJI', null, 'UN', 7200, 7500, '2026-09-01', 'confianca CONFERIR - o par 12.500/12.220 na mesma linha pode pertencer a este item | PROMOCAO DE CONFIANCA: O motivo do CONFERIR era o par orfao 12.500/12.220 poder pertencer a este item. A planilha Excel 2026 registra, para o proprio D-RTK 3 AG, o valor alternativo 7.200 - identico ao a vista da DJI. Duas fontes independentes no mesmo numero dissolvem a duvida: o par 12.500/12.220 e do CARREGADOR C12000, ja provado', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-068', null),
  ('DJI-069', 'GNSS DJI RTK DRTK3 MULTIFUNCIONAL', null, 'DJI', null, 'UN', 12890, 13490, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: nome e ambos os valores estao legiveis na tabela original.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-069', null),
  ('DJI-070', 'BASE/HUB DJI P/ MAVIC 3 MULT (4288)', '4288', 'DJI', null, 'UN', 750, 790, '2026-09-01', 'CONFERIDO VISUALMENTE NO PDF DJI SUBDEALER V16.2: BASE/HUB DJI P/ MAVIC 3 MULT (4288), R$ 750 a vista e R$ 790 faturado.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PDF DJI V16.2 | DEMAIS ITENS DJI AGRICULTURE | BASE/HUB DJI P/ MAVIC 3 MULT (4288)', null),
  ('DJI-071', 'RELAY O3 (MODELO ANTIGO)', null, 'DJI', null, 'UN', 6500, 6800, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-071', null),
  ('DJI-072', 'RELAY O4 (MODELO NOVO)', null, 'DJI', null, 'UN', 6500, 6800, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-072', null),
  ('DJI-073', 'BASTAO P/ RELAY 4 METROS (1982)', '1982', 'DJI', null, 'UN', 449, 499, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-073', null),
  ('DJI-074', 'BASTAO P/ RELAY 8 METROS (5218)', '5218', 'DJI', null, 'UN', 1499, 1569, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-074', null),
  ('DJI-075', 'BIPE P/ BASTAO (1626)', '1626', 'DJI', null, 'UN', 399, 449, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-075', null),
  ('DJI-076', 'TRIPE P/ RELAY E RTK (1980)', '1980', 'DJI', null, 'UN', 899, 935, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-076', null),
  ('DJI-077', 'TRIPE + BASTAO ORIGINAL DJI D-RTK 3', null, 'DJI', null, 'UN', 2500, 2600, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026 (TRIPE D-RTK 2.500)', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-077', null),
  ('DJI-078', 'TRIPE ORIGINAL DJI PARA D-RTK 2', null, 'DJI', null, 'UN', 1250, 1300, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-078', null),
  ('DJI-079', 'CARREGADOR P/ BATERIA WB37', null, 'DJI', null, 'UN', 670, 750, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-079', null),
  ('DJI-080', 'FONTE 65W P/ WB37', null, 'DJI', null, 'UN', 390, 450, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-080', null),
  ('DJI-081', 'BATERIA CONTROLE WB37', null, 'DJI', null, 'UN', 630, 670, '2026-09-01', 'confianca ALTA - confere com a planilha Excel 2026', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-081', null),
  ('DJI-082', 'RADIO CONTROLE T40/T50/T20P/T25', null, 'DJI', null, 'UN', 11300, 11700, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-082', null),
  ('DJI-083', 'RADIO CONTROLE T25P/T70P/T100', null, 'DJI', null, 'UN', 14700, 15200, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-083', null),
  ('DJI-084', 'CABO DJI ADAP DO CARREG C10000', null, 'DJI', null, 'UN', 950, 988, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-084', null),
  ('DJI-085', 'RESFRIADOR DE BATERIAS T100/T70P', null, 'DJI', null, 'UN', 999, 1099, '2026-09-01', 'confianca ALTA', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PRODUTOS!DJI-085', null),
  ('DJI-087', 'DISPERSOR DE SOLIDOS T100', null, 'DJI', null, 'UN', 12220, 12500, '2026-09-01', 'REGISTRO CANONICO V4: conferido visualmente no bloco DISPERSOR DE SOLIDOS do PDF DJI. Corrige a associacao anterior de 16.500/16.990, que pertence ao KIT DE PULVERIZACAO DJI T100.', 'price_list', 'DJI', 'TABELA SUBDEALER', 'V16.2', 'PDF DJI V16.2 | DISPERSOR DE SOLIDOS | T100', null),
  ('JR-001', 'DRONE MIX 130L LT NEW 2x18lpm 12volts', '1296', 'JR SOLUCOES', 'Pulverização', 'UN', 5600, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-001', '84368000'),
  ('JR-002', 'DRONE MIX 200L LT NEW 2x26lpm 12volts', '1363', 'JR SOLUCOES', 'Pulverização', 'UN', 6900, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-002', '84368000'),
  ('JR-003', 'DRONE FEEDER 500 - 220Volts', '2141', 'JR SOLUCOES', null, 'UN', 11700, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-003', '84368000'),
  ('JR-004', 'DRONE MIX 130L LE Agitacao Hidraulica 220Volts', '1243', 'JR SOLUCOES', 'Pulverização', 'UN', 5600, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-004', '84368000'),
  ('JR-005', 'DRONE MIX 200L LE Agitacao Hidraulica 220Volts', '1361', 'JR SOLUCOES', 'Pulverização', 'UN', 6200, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-005', '84368000'),
  ('JR-006', 'DRONE MIX 320L LE Agitacao Hidraulica 220Volts', '1240', 'JR SOLUCOES', 'Pulverização', 'UN', 6800, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-006', '84368000'),
  ('JR-007', 'DRONE MIX 320L XT VERTICAL Agitacao Hid + Rotor Superior 220Volts', '1273', 'JR SOLUCOES', 'Pulverização', 'UN', 8400, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-007', '84368000'),
  ('JR-008', 'DRONE MIX 320L XT VERTICAL Agitacao Hid + Rotor Superior TRIFASICO 380Volts', '1809', 'JR SOLUCOES', 'Pulverização', 'UN', 9400, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-008', '84368000'),
  ('JR-009', 'DRONE MIX 600L XT VERTICAL Agitacao Hid + Rotor Superior 220Volts', '1275', 'JR SOLUCOES', 'Pulverização', 'UN', 9700, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-009', '84368000'),
  ('JR-010', 'DRONE MIX 600L XT VERTICAL Agitacao Hid + Rotor Superior TRIFASICO 380Volts', '2223', 'JR SOLUCOES', 'Pulverização', 'UN', 10700, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-010', '84368000'),
  ('JR-011', 'DRONE MIX 320L LE PICKUP Agitacao Hidraulica 220Volts', '2350', 'JR SOLUCOES', 'Pulverização', 'UN', 6800, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-011', '84368000'),
  ('JR-012', 'DRONE MIX 320L XT PICKUP Agitacao Hid + Rotor Superior 220Volts', '2324', 'JR SOLUCOES', 'Pulverização', 'UN', 8400, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-012', '84368000'),
  ('JR-013', 'DRONE MIX 600L LE 1.5 PICKUP Agitacao Hidraulica 220Volts', '2362', 'JR SOLUCOES', 'Pulverização', 'UN', 8900, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-013', '84368000'),
  ('JR-014', 'DRONE MIX 600L XT 1.5 PICKUP Agitacao Hid + Rotor Superior 220Volts', '2353', 'JR SOLUCOES', 'Pulverização', 'UN', 10700, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-014', '84368000'),
  ('JR-017', 'DRONE MIX 600L LE 1.5 PICKUP Agitacao Hid TRIFASICO 380V', '2363', 'JR SOLUCOES', 'Pulverização', 'UN', 10700, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-017', '84368000'),
  ('JR-018', 'DRONE MIX 600L XT 1.5 PICKUP Agitacao Hid + Rotacao TRIFASICO 380V', '2354', 'JR SOLUCOES', 'Pulverização', 'UN', 12900, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-018', '84368000'),
  ('JR-019', 'DRONE MIX 320L GT Agitacao por MotoBomba a Gasolina INOX', '1426', 'JR SOLUCOES', 'Pulverização', 'UN', 11000, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-019', '84368000'),
  ('JR-020', 'DRONE MIX 600L GT Agitacao por MotoBomba a Gasolina INOX', '1427', 'JR SOLUCOES', 'Pulverização', 'UN', 12300, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-020', '84368000'),
  ('JR-021', 'DRONE MIX 1.200L GT Agitacao por MotoBomba a Gasolina INOX', '2380', 'JR SOLUCOES', 'Pulverização', 'UN', 15900, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-021', '84368000'),
  ('JR-022', 'DRONE MIX 320L DTE Agitacao por MotoBomba a Diesel INOX com Partida', '1497', 'JR SOLUCOES', 'Pulverização', 'UN', 15900, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-022', '84368000'),
  ('JR-023', 'DRONE MIX 600L DTE Agitacao por MotoBomba a Diesel INOX com Partida', '1498', 'JR SOLUCOES', 'Pulverização', 'UN', 17000, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-023', '84368000'),
  ('JR-024', 'DRONE MIX 1.200L DTE Agitacao por MotoBomba a Diesel INOX com Partida', null, 'JR SOLUCOES', 'Pulverização', 'UN', 20800, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-024', '84368000'),
  ('JR-025', 'DRONE MIX 1.200 XP 2.0 Agitacao Hidraulica 220Volts', '2375', 'JR SOLUCOES', 'Pulverização', 'UN', 14000, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-025', '84368000'),
  ('JR-026', 'DRONE MIX 1.200 XP 2.0 Agitacao Hidraulica 220Volts TRIFASICO 380V', '2364', 'JR SOLUCOES', 'Pulverização', 'UN', 15500, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-026', '84368000'),
  ('JR-027', 'INCORPORADOR DE DEFENSIVOS JET DRONE 20', '1616', 'JR SOLUCOES', 'Pulverização', 'UN', 3400, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-027', '84368000'),
  ('JR-028', 'TANQUE DE AGUA LIMPA 270L com 8lts de Potavel PickUp', '1781', 'JR SOLUCOES', 'Pulverização', 'UN', 1050, null, '2026-09-01', 'NCM 84369000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-028', '84369000'),
  ('JR-029', 'TANQUE DE AGUA LIMPA 410L com 8lts de Potavel PickUp', '2189', 'JR SOLUCOES', 'Pulverização', 'UN', 1450, null, '2026-09-01', 'NCM 84369000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-029', '84369000'),
  ('JR-030', 'BICO DE ABASTECIMENTO TIPO POSTO DE GASOLINA', '1738', 'JR SOLUCOES', 'Acessórios', 'UN', 220, null, '2026-09-01', 'NCM 84818099 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-030', '84818099'),
  ('JR-031', 'BICO DE ABASTECIMENTO TIPO POSTO DE GASOLINA COM FLUXOMETRO', '1739', 'JR SOLUCOES', 'Acessórios', 'UN', 360, null, '2026-09-01', 'NCM 84818099 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-031', '84818099'),
  ('JR-032', 'MEDIDOR DE FLUXO DIGITAL', '879', 'JR SOLUCOES', 'Acessórios', 'UN', 300, null, '2026-09-01', 'NCM 90282010 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-032', '90282010'),
  ('JR-033', 'SISTEMA DE AQUECIMENTO PARA OS AGUA LIMPA DE 270 OU 410L', '2211', 'JR SOLUCOES', 'Acessórios', 'UN', 750, null, '2026-09-01', 'NCM não informado na tabela | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte. | CORRECAO V5: NCM nao informado na tabela JR; campo fiscal fica vazio (vazio = nao informado).', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-033', null),
  ('JR-034', 'BASE COM CARRETEL RETRATIL 15 METROS MANGUEIRA DE 3/4"', null, 'JR SOLUCOES', 'Acessórios', 'UN', 6425, null, '2026-09-01', 'NCM não informado na tabela | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte. | CORRECAO V5: NCM nao informado na tabela JR; campo fiscal fica vazio (vazio = nao informado).', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-034', null),
  ('JR-035', 'RACK PARA TRANSPORTE DE DRONE (SAVEIRO 1867 OU STRADA 1957)', null, 'JR SOLUCOES', 'Acessórios', 'UN', 2300, null, '2026-09-01', 'NCM 84329000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-035', '84329000'),
  ('JR-036', 'Estrutura de Trabalho DroneMix PickUp com uma prat (BASE OPERACIONAL)', '1866', 'JR SOLUCOES', 'Acessórios', 'UN', 6450, null, '2026-09-01', 'NCM 84329000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-036', '84329000'),
  ('JR-037', 'Prateleira Lateral extra (PARA BASE DE OPERACAO PICK UP)', '1831', 'JR SOLUCOES', 'Acessórios', 'UN', 550, null, '2026-09-01', 'NCM 84329000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-037', '84329000'),
  ('JR-038', 'TANQUE PRE MIX 200 CONEXOES EM 2"', '2338', 'JR SOLUCOES', 'Pulverização', 'UN', 5100, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-038', '84368000'),
  ('JR-039', 'TANQUE PRE MIX 320 CONEXOES EM 2"', '2008', 'JR SOLUCOES', 'Pulverização', 'UN', 5600, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-039', '84368000'),
  ('JR-040', 'TANQUE PRE MIX 600 CONEXOES EM 2"', '2237', 'JR SOLUCOES', 'Pulverização', 'UN', 7000, null, '2026-09-01', 'NCM 84368000 | PDF JR rotula este valor como REVENDAS; a condicao de pagamento nao e declarada pela fonte.', 'price_list', 'JR SOLUCOES', 'TABELA REV JR', 'JAN/26', 'PRODUTOS!JR-040', '84368000');

-- ── 2. Recusa estrutural: nada entra com referência quebrada ─
do $$
declare
  v_n integer;
  v_lista text;
begin
  if (select count(*) from _carga) <> 112 then
    raise exception 'A carga deveria ter 112 linhas e tem %', (select count(*) from _carga);
  end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.unidade is null
      or not exists (select 1 from public.units u where upper(u.code) = upper(c.unidade));
  if v_n > 0 then raise exception 'Unidade inexistente em % linha(s): %', v_n, v_lista; end if;

  -- A trava que quebraria a carga inteira lá no meio.
  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.manufacturer_code is not null
     and not exists (select 1 from public.brands b
                      where upper(b.name) = upper(c.marca) and b.deleted_at is null);
  if v_n > 0 then
    raise exception 'Codigo de fabricante sem marca cadastrada em % linha(s): % — chk_products_manufacturer_brand recusaria', v_n, v_lista;
  end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga c
   where c.categoria is not null
     and not exists (select 1 from public.categories k
                      where k.name = c.categoria and k.deleted_at is null);
  if v_n > 0 then raise exception 'Categoria inexistente em % linha(s): %', v_n, v_lista; end if;

  select count(*), string_agg(code, ', ') into v_n, v_lista
    from _carga where ncm is not null and ncm !~ '^[0-9]{8}$';
  if v_n > 0 then raise exception 'NCM fora do formato em % linha(s): %', v_n, v_lista; end if;

  if not exists (select 1 from public.price_conditions where upper(code) = 'AVISTA')
     or not exists (select 1 from public.price_conditions where upper(code) = 'FATURADO') then
    raise exception 'price_conditions sem AVISTA/FATURADO: aplique a migration 20260902120000 antes da carga';
  end if;
end $$;

-- ── 3. Produtos ─────────────────────────────────────────────
create temporary table _resultado (code text, acao text) on commit drop;

with resolvido as (
  select
    c.*,
    b.id as brand_id,
    k.id as category_id,
    u.id as unit_id
  from _carga c
  left join public.brands     b on upper(b.name) = upper(c.marca)   and b.deleted_at is null
  left join public.categories k on k.name        = c.categoria      and k.deleted_at is null
  join      public.units      u on upper(u.code) = upper(c.unidade)
),
gravado as (
  insert into public.products (
    code, name, manufacturer_code, brand_id, category_id, unit_id,
    sale_price, is_active, notes,
    source_type, source_brand, source_catalog, source_version,
    source_reference, source_imported_at, technical_data
  )
  select
    r.code, r.name, r.manufacturer_code, r.brand_id, r.category_id, r.unit_id,
    0,                       -- preço de venda ainda não definido…
    false,                   -- …e por isso o produto entra inativo
    r.observacao,
    r.source_type::public.product_source_type,
    r.source_brand, r.source_catalog, r.source_version,
    r.source_reference, now(),
    case when r.ncm is null then '{}'::jsonb else jsonb_build_object('ncm', r.ncm) end
  from resolvido r
  on conflict (upper(code)) where deleted_at is null
  do update set
    name              = excluded.name,
    manufacturer_code = excluded.manufacturer_code,
    brand_id          = excluded.brand_id,
    category_id       = excluded.category_id,
    unit_id           = excluded.unit_id,
    notes             = excluded.notes,
    source_type       = excluded.source_type,
    source_brand      = excluded.source_brand,
    source_catalog    = excluded.source_catalog,
    source_version    = excluded.source_version,
    source_reference  = excluded.source_reference,
    source_imported_at = excluded.source_imported_at,
    technical_data    = public.products.technical_data || excluded.technical_data
    -- sale_price, sale_price_set_at e is_active ficam como estão:
    -- tabela de fabricante não decide preço nem ativação.
  returning code, (xmax = 0) as inserido
)
insert into _resultado select code, case when inserido then 'inserido' else 'atualizado' end from gravado;

-- ── 4. Custo por condição ───────────────────────────────────
-- Uma linha por produto E condição. É exatamente isto que a PK antiga
-- de product_costs (em product_id) impedia.
insert into public.product_costs (
  product_id, condition_id, cost_price, valid_from,
  source_catalog, source_version, source_reference
)
select p.id, pc.id, v.valor, c.vigencia, c.source_catalog, c.source_version, c.source_reference
from _carga c
join public.products p on upper(p.code) = upper(c.code) and p.deleted_at is null
cross join lateral (values
  ('AVISTA',   c.custo_avista),
  ('FATURADO', c.custo_faturado)
) as v(cond, valor)
join public.price_conditions pc on upper(pc.code) = v.cond
where v.valor is not null
on conflict (product_id, condition_id) where valid_to is null
do update set
  cost_price       = excluded.cost_price,
  valid_from       = excluded.valid_from,
  source_catalog   = excluded.source_catalog,
  source_version   = excluded.source_version,
  source_reference = excluded.source_reference;

-- ── 5. Relatório ────────────────────────────────────────────
do $$
declare
  v_ins integer; v_upd integer; v_avista integer; v_fat integer; v_sem integer; v_ativos integer; v_precos integer;
begin
  select count(*) filter (where acao = 'inserido'),
         count(*) filter (where acao = 'atualizado')
    into v_ins, v_upd from _resultado;

  select count(*) filter (where upper(pc.code) = 'AVISTA'),
         count(*) filter (where upper(pc.code) = 'FATURADO')
    into v_avista, v_fat
    from public.product_costs c
    join public.price_conditions pc on pc.id = c.condition_id
    join public.products p on p.id = c.product_id
   where upper(p.code) in (select upper(code) from _carga) and c.valid_to is null;

  select count(*) into v_sem
    from _carga c join public.products p on upper(p.code) = upper(c.code)
   where not exists (select 1 from public.product_costs pk where pk.product_id = p.id);

  select count(*) filter (where p.is_active),
         count(*) filter (where p.sale_price_set_at is not null)
    into v_ativos, v_precos
    from _carga c join public.products p on upper(p.code) = upper(c.code);

  raise notice '──────────── RELATORIO DA CARGA ────────────';
  raise notice 'produtos inseridos.............. %', v_ins;
  raise notice 'produtos atualizados............ %', v_upd;
  raise notice 'linhas de custo AVISTA.......... %', v_avista;
  raise notice 'linhas de custo FATURADO........ %', v_fat;
  raise notice 'produtos sem nenhum custo....... %', v_sem;
  raise notice 'produtos ATIVOS apos a carga.... %  (esperado 0 numa base limpa)', v_ativos;
  raise notice 'produtos COM preco definido..... %  (esperado 0 numa base limpa)', v_precos;
  raise notice '────────────────────────────────────────────';

  if v_ins + v_upd <> 112 then
    raise exception 'A carga gravou % produtos, e deveria gravar 112', v_ins + v_upd;
  end if;
end $$;

commit;
