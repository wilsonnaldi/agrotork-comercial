"""Testes do worker sem banco: extração, tabela, códigos, chunking determinístico.

Rodar: `python -m pytest brain/worker/tests -q` (na raiz do repositório).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fixtures import COMMERCIAL_BLOCKS, FLOW_SPEEDS, SHEET_CODES, TABLE_ROWS, make_catalog_pdf, make_commercial_pdf, make_degraded_pdf, make_flow_pdf, make_price_xlsx, make_quote_xlsx, make_text  # noqa: E402
from brain_worker.chunking import CONFIG, MAX, PageInput, chunk_pages, is_heading  # noqa: E402
from brain_worker.codes import extract_codes, known_profiles, normalize_code  # noqa: E402
from brain_worker.extract import extract, mime_for, ocr_available, sniff_ok  # noqa: E402
from brain_worker.pipeline import plan, sha256_of  # noqa: E402
from brain_worker.tables import TechnicalTable, build_table, is_money, parse_number, split_side_by_side, split_stacked  # noqa: E402


@pytest.fixture(scope="module")
def catalog_pdf(tmp_path_factory):
    return make_catalog_pdf(tmp_path_factory.mktemp("w") / "catalogo_sintetico.pdf")


# ── W1 checksum e tipo ──────────────────────────────────────

def test_w1_sha256_and_mime(catalog_pdf, tmp_path):
    import hashlib
    assert sha256_of(catalog_pdf) == hashlib.sha256(catalog_pdf.read_bytes()).hexdigest()
    assert mime_for(catalog_pdf) == "application/pdf"
    assert sniff_ok(catalog_pdf)
    fake = tmp_path / "nao-e-pdf.pdf"
    fake.write_bytes(b"isto nao e um pdf")
    assert not sniff_ok(fake)
    with pytest.raises(ValueError):
        mime_for(tmp_path / "x.exe")


# ── W2 páginas e tabela técnica ─────────────────────────────

def test_w2_pdf_pages_and_table(catalog_pdf):
    ext = extract(catalog_pdf, ocr="never")
    assert ext.pages_total == 3 and [p.page_no for p in ext.pages] == [1, 2, 3]
    assert ext.method == "pdf_text" and not ext.needs_ocr
    p2 = ext.pages[1]
    assert len(p2.tables) == 1
    t = p2.tables[0]
    assert t.headers[:3] == ["Codigo", "Serie", "Gotas"]
    assert t.labels[3] == "Pressão (bar)"
    assert t.units["Pressao_bar"] == "bar" and t.units["Vazao_L/min"] == "L/min" and t.units["L/ha_a_12_km/h"] == "L/ha"
    assert len(t.rows) == len(TABLE_ROWS)
    row = t.rows[1]
    assert row[0] == "PS981CAP" and row[3] == 2.76 and row[4] == 40 and row[5] == 0.77 and row[6] == 77
    assert isinstance(row[5], float) and isinstance(row[6], int)
    # o texto da pagina NAO repete a tabela
    assert "0,77" not in p2.text and "PS981CAP" not in p2.text
    assert "MALHA 50" in p2.text


def test_w2b_numbers_ptbr():
    assert parse_number("2,76") == 2.76 and parse_number("1.234,56") == 1234.56
    assert parse_number("R$ 165.500,00") == 165500.0 and parse_number("40") == 40
    assert parse_number("UG") is None and parse_number("") is None and parse_number(True) is None
    t = build_table([["Item", "Faturado (R$)", "Cliente final mínimo (R$)"], ["X", "1.000,00", "2.000,00"]], page=1)
    assert t.units == {"Faturado_R": "BRL", "Cliente_final_minimo_R": "BRL"}   # 'm' de 'minimo' nao vira metro
    assert t.rows[0][1] == 1000.0


# ── W3 códigos ──────────────────────────────────────────────

def test_w3_codes():
    assert normalize_code("mj 981 cap") == "MJ981CAP"
    assert extract_codes("Ponta MJ981CAP (MUG-CV 02) e T70P, bateria DB1580; codigo Arag 4626215; preco 165500") == \
        ["4626215", "DB1580", "MJ981CAP", "MUG-CV02", "T70P"]
    assert "165500" not in extract_codes("preco 165500 a vista")


# ── W4 chunking determinístico ─────────────────────────────

def test_w4_deterministic(catalog_pdf):
    a = plan(catalog_pdf, ocr="never")
    b = plan(catalog_pdf, ocr="never")
    assert [c.as_row() for c in a.chunks] == [c.as_row() for c in b.chunks]
    assert json.dumps([c.as_row() for c in a.chunks], sort_keys=True) == json.dumps([c.as_row() for c in b.chunks], sort_keys=True)
    assert a.summary()["chunk_config"] == CONFIG


def test_w4b_chunks_never_cross_pages_and_table_is_own_chunk(catalog_pdf):
    p = plan(catalog_pdf, ocr="never")
    assert all(c.page == c.as_row()["page_to"] for c in p.chunks)
    ordinals = [c.ordinal for c in p.chunks]
    assert ordinals == list(range(len(ordinals)))
    tables = [c for c in p.chunks if c.kind == "table"]
    assert len(tables) == 1 and tables[0].page == 2
    td = tables[0].table_data
    assert td["rows"][1][5] == 0.77 and td["rows"][1][6] == 77
    assert "PS981CAP" in tables[0].codes
    assert "PS981CAP SOL-CV 02 UG 2,76 bar 40 psi 0,77 L/min 77 L/ha" in tables[0].content
    assert tables[0].content.startswith("Código Série Gotas Pressão (bar)")   # cabecalho pesquisavel
    # nenhum chunk de texto carrega a tabela
    assert not any("0,77" in c.content for c in p.chunks if c.kind == "text")
    # texto longo da p.3 fatiado com overlap e sem cortar palavra
    p3 = [c for c in p.chunks if c.page == 3 and c.kind == "text"]
    assert len(p3) >= 2 and all(len(c.content) <= MAX for c in p3)
    assert all(not c.content.endswith("-") for c in p3)
    assert p3[0].heading_path[-1].startswith("CAPÍTULO 3")


def test_w4c_heading_detection():
    assert is_heading("SOL ULTRA GROSSA CONE VAZIO")
    assert is_heading("2.1 CALIBRAÇÃO DO SENSOR")
    assert not is_heading("PS983CAP SOL-CV 03 UG 2,76 40 1,15 115")   # linha de tabela
    assert not is_heading("Uma frase normal que termina com ponto.")
    assert not is_heading("A" * 90)


def test_w4d_pages_are_isolated():
    pages = [PageInput(2, "TITULO B\nTexto da pagina dois."), PageInput(1, "TITULO A\nTexto da pagina um.")]
    chunks = chunk_pages(pages)
    # ordenado por pagina, nao pela lista; o titulo da pagina vira chunk `heading` proprio
    assert [(c.page, c.kind) for c in chunks] == [(1, "heading"), (1, "text"), (2, "heading"), (2, "text")]
    assert [c.ordinal for c in chunks] == [0, 1, 2, 3]
    # a pilha de titulos NAO atravessa pagina (reset por pagina, lote-b.2)
    assert chunks[1].heading_path == ["TITULO A"] and chunks[3].heading_path == ["TITULO B"]
    assert "dois" not in chunks[1].content and "um" not in chunks[3].content


# ── W5 planilha e texto ─────────────────────────────────────

def test_w5_xlsx_each_sheet_is_a_page(tmp_path):
    p = plan(make_price_xlsx(tmp_path / "precos.xlsx"))
    assert p.extraction.pages_total == 2 and p.extraction.method == "xlsx"
    assert [c.kind for c in p.chunks] == ["price_table", "price_table"]
    assert p.chunks[0].page == 1 and p.chunks[1].page == 2
    td = p.chunks[0].table_data
    assert td["units"]["Faturado_R"] == "BRL" and td["rows"][0][1] == 165500
    # proveniencia de planilha e aba + intervalo de linhas, nao numero de pagina
    assert any(n.startswith("aba: Revenda, linhas ") for n in td["notes"]), td["notes"]
    assert "C12000" in p.chunks[0].codes and "SB1580" in p.chunks[1].codes


def test_w5b_text_form_feed_pages(tmp_path):
    p = plan(make_text(tmp_path / "proc.txt"))
    assert p.extraction.pages_total == 2
    assert [c.page for c in p.chunks] == [1, 1, 2, 2] and "466113200" in p.chunks[3].codes


# ── W6 OCR ──────────────────────────────────────────────────

def test_w6_scanned_pdf_needs_ocr(tmp_path):
    scanned = make_catalog_pdf(tmp_path / "scan.pdf", scanned=True)
    ext = extract(scanned, ocr="never")
    assert ext.needs_ocr and ext.pages_total == 1
    ext2 = extract(scanned, ocr="auto")
    if ocr_available():
        assert ext2.method == "pdf_ocr" and ext2.pages[0].extraction in ("ocr", "none") and ext2.pages[0].ocr in (True, False)
    else:
        assert ext2.pages[0].extraction == "none" and any("tesseract ausente" in w for w in ext2.warnings)
    # com camada textual confiavel, OCR nao roda mesmo em 'auto'
    ext3 = extract(make_catalog_pdf(tmp_path / "texto.pdf"), ocr="auto")
    assert ext3.method == "pdf_text" and all(p.extraction == "text_layer" for p in ext3.pages)


# ── W7 tabela técnica por geometria (piloto Magnojet, em sintético) ──────────

def test_w7_spatial_reconstruction_fixes_merged_columns(tmp_path):
    """O detector por régua funde as 13 velocidades numa célula, deixa o cabeçalho
    km/h como linha e não propaga o código do grupo; a reconstrução espacial
    devolve uma coluna por velocidade, cabeçalho de dois níveis e código em
    todas as linhas do grupo — sem inventar nenhuma célula."""
    import pdfplumber
    from brain_worker.tables import audit_table, build_table
    pdf = make_flow_pdf(tmp_path / "vazao.pdf")
    with pdfplumber.open(str(pdf)) as doc:
        found = doc.pages[0].find_tables()[0]
        raw = build_table(found.extract(), page=1)
    issues = audit_table(raw)
    assert any("fundidos" in i for i in issues) and any("cabecalho" in i for i in issues)

    p = plan(pdf, profile="magnojet_catalog")
    assert p.summary()["tables_reconstructed"] == 1 and p.summary()["table_audit_issues"] == 0
    t = [c for c in p.chunks if c.kind == "table"][0]
    td = t.table_data
    assert td["headers"][:6] == ["CODIGO_PONTAS", "GOTAS", "BAR", "PSI", "kPa", "L/min"]
    assert td["headers"][6:] == [f"L_ha@{s}" for s in FLOW_SPEEDS]
    assert td["labels"][6:] == [f"{s} km/h" for s in FLOW_SPEEDS]
    assert set(g for g in td["groups"] if g) == {"LITROS POR HECTARE (ESPAÇAMENTO 50CM)"}
    assert td["units"]["L_ha@12"] == "L/ha" and td["units"]["L/min"] == "L/min" and td["units"]["PSI"] == "psi"
    # a linha PS981CAP a 40 psi: numeros em colunas individuais, valor a 12 km/h = 77
    row = [r for r in td["rows"] if r[0] == "PS981CAP SOL-CV 02 MALHA 50" and r[3] == 40][0]
    assert row[2:6] == [2.76, 40, 276, 0.77] and row[td["headers"].index("L_ha@12")] == 77
    assert all(isinstance(v, (int, float)) for v in row[2:])
    # codigo propagado a todas as linhas do grupo (pela regua do grupo, nao por chute)
    assert [r[0] for r in td["rows"]] == ["PS980CAP SOL-CV 015 MALHA 50"] * 3 + ["PS981CAP SOL-CV 02 MALHA 50"] * 3
    assert "reconstruction: spatial" in td["notes"] and not audit_table(TechnicalTable(td["headers"], td["rows"], td["units"], 1, [], td["labels"]))
    assert {"PS980CAP", "PS981CAP", "SOL-CV02", "SOL-CV015"} <= set(t.codes)
    # cabecalho vertical "GOTAS" lido pela rotacao; "SOLUÇÕES" da margem fora do corpo
    assert p.extraction.pages[0].layout["rotated_text"] == ["SOLUÇÕES", "GOTAS"]


def test_w7b_audit_never_passes_ambiguous_cells():
    from brain_worker.tables import audit_table
    t = TechnicalTable(["CODIGO", "PSI", "L_ha@12"], [["PS1", 40, "77 66 5"], [None, 50, 88]], {}, 1, [], ["CÓDIGO", "PSI", "12 km/h"])
    issues = audit_table(t)
    assert any("fundidos" in i for i in issues) and any("nao propagado" in i for i in issues)
    ok = TechnicalTable(["CODIGO", "PSI", "L_ha@12"], [["PS1", 40, 77], ["PS1", 50, 88]], {}, 1, [], ["CÓDIGO", "PSI", "12 km/h"])
    assert audit_table(ok) == []


# ── W8 títulos ───────────────────────────────────────────────

def test_w8_headings_page_reset_runs_and_vertical_art(tmp_path):
    p = plan(make_flow_pdf(tmp_path / "vazao.pdf"))
    kinds = [c.kind for c in p.chunks]
    assert kinds[0] == "heading"
    # titulos consecutivos entram inteiros: nenhum apaga o outro
    assert p.chunks[0].content == "APLICAÇÕES DE HERBICIDAS SISTÊMICOS\nSOL ULTRA GROSSA\nCONE VAZIO"
    assert p.chunks[1].heading_path == ["APLICAÇÕES DE HERBICIDAS SISTÊMICOS", "SOL ULTRA GROSSA", "CONE VAZIO"]
    # arte lateral ("SOLUÇÕES" girado) nao vira titulo nem entra no corpo
    assert not any("Õ E S" in h or h == "SOLUÇÕES" for c in p.chunks for h in c.heading_path)
    assert "SOLUÇÕES" not in p.chunks[1].content
    assert not is_heading("Õ E S") and not is_heading("O S C U")
    # reset por pagina: a segunda pagina nao herda titulo da primeira
    pages = [PageInput(1, "TITULO UM\nCorpo um."), PageInput(2, "Corpo dois sem titulo.")]
    chunks = chunk_pages(pages)
    assert [c.heading_path for c in chunks if c.page == 2] == [[]]


# ── W9 códigos ───────────────────────────────────────────────

def test_w9_codes_with_punctuation_slash_space_and_profile():
    assert extract_codes("catálogo da MJ983CAP?") == ["MJ983CAP"]
    assert extract_codes("vazão do MJ981CAP,") == ["MJ981CAP"]
    assert extract_codes("MJ059/1 MAG CH 0.5 MALHA 100") == ["MAGCH0.5", "MJ059/1"]
    assert extract_codes("MUG-CV 02 e SOL-CV 03") == ["MUG-CV02", "SOL-CV03"]
    assert extract_codes("M 714") == [] and extract_codes("M 714", "magnojet_catalog") == ["M714"]
    assert extract_codes("elemento M 691/1A malha 50", "magnojet_catalog") == ["M691/1A"]
    assert extract_codes("A 100 metros de distância", "magnojet_catalog") == []      # so a letra M
    assert extract_codes("R$ 165.500,00 em 2026 a 40 psi") == []
    assert extract_codes("sensor 466113200 e 4626215") == ["4626215", "466113200"]
    assert "magnojet_catalog" in known_profiles()


# ── W10 price_table só com evidência real de preço ───────────

def test_w10_price_table_needs_real_price_evidence():
    from brain_worker.chunking import _looks_like_prices
    prosa = TechnicalTable(["col_0", "demonstrar"], [["x", "y"]], {}, 5, [], ["", "o programa valoriza o atendimento"])
    assert not _looks_like_prices(prosa)
    valor = TechnicalTable(["Item", "Valor"], [["x", 10]], {}, 1, [], ["Item", "Valor"])
    assert _looks_like_prices(valor)
    vista = TechnicalTable(["Item", "A_vista"], [["x", 10]], {}, 1, [], ["Item", "Preço à vista"])
    assert _looks_like_prices(vista)
    brl = TechnicalTable(["Item", "Total"], [["x", 10]], {"Total": "BRL"}, 1, [], ["Item", "Total (R$)"])
    assert _looks_like_prices(brl)


# ── W11 microchunks agregados; W12 versão do pipeline e determinismo ─────────

def test_w11_short_fragments_are_aggregated():
    txt = "FILTRANTE\nØ 108,00\nESPECIFICAÇÕES\n100\nCONTÉM\n1 un\nDE SUCÇÃO\nR 3.\nM X8\n"
    chunks = chunk_pages([PageInput(100, txt)])
    texts = [c for c in chunks if c.kind == "text"]
    assert len(texts) == 1 and texts[0].content == "Ø 108,00\n100\n1 un\nR 3. M X8"
    assert [c.kind for c in chunks][0] == "heading"


def test_w12_pipeline_version_and_determinism(tmp_path):
    from brain_worker import PIPELINE_VERSION
    assert PIPELINE_VERSION == "lote-b.2"
    a = plan(make_flow_pdf(tmp_path / "a.pdf"), profile="magnojet_catalog")
    b = plan(make_flow_pdf(tmp_path / "b.pdf"), profile="magnojet_catalog")
    assert a.sha256 == b.sha256
    assert [(c.ordinal, c.kind, c.content, c.table_data, c.codes, c.heading_path) for c in a.chunks] == \
           [(c.ordinal, c.kind, c.content, c.table_data, c.codes, c.heading_path) for c in b.chunks]


# ── W13–W16 estado formal de qualidade (trusted / degraded) ──────────────

def test_w13_degraded_table_is_marked_and_never_invented(tmp_path):
    """Sinal fatal que a geometria não resolve → audit.quality = degraded,
    fatal = true; a representação original fica (célula "4181 3907 …" como
    string, nunca dividida por espaço); o chunk continua rastreável."""
    p = plan(make_degraded_pdf(tmp_path / "deg.pdf"))
    assert p.summary()["tables_degraded"] == 1 and p.summary()["tables_trusted"] == 0
    assert p.summary()["degraded_pages"] == [1]
    t = [c for c in p.chunks if c.kind == "table"][0]
    audit = t.table_data["audit"]
    assert audit["quality"] == "degraded" and audit["fatal"] is True
    assert any("fundidos" in i for i in audit["issues"])
    row = t.table_data["rows"][0]
    assert row[0] == "PSDEG55" and row[1] == 2.76 and row[2] == 40
    assert row[3] == "4181 3907 3200 2800 2400 2100"          # string ambigua, intacta
    assert not any(isinstance(v, (int, float)) and v in (4181, 3907) for v in row)
    assert "PSDEG55" in t.codes and t.page == 1 and t.content.startswith("CÓDIGO")
    # o texto confiavel da mesma pagina segue normal
    assert [c.kind for c in p.chunks] == ["heading", "text", "table"]


def test_w14_trusted_table_has_formal_state(tmp_path):
    p = plan(make_flow_pdf(tmp_path / "vazao.pdf"), profile="magnojet_catalog")
    t = [c for c in p.chunks if c.kind == "table"][0]
    assert t.table_data["audit"] == {"quality": "trusted", "fatal": False, "issues": []}
    assert p.summary()["tables_trusted"] == 1 and p.summary()["tables_degraded"] == 0 and p.summary()["degraded_pages"] == []
    td = t.table_data
    assert td["rows"][td["rows"].index([r for r in td["rows"] if r[3] == 40 and r[0].startswith("PS981CAP")][0])][td["headers"].index("L_ha@12")] == 77


def test_w15_non_fatal_warnings_stay_trusted():
    from brain_worker.tables import fatal_issues
    t = TechnicalTable(["CODIGO", "col_1", "col_2"], [["PS1", 40, 77], ["PS1", 50, 88]], {}, 1, [], ["CÓDIGO", "", ""])
    audit = t.stamp_audit()
    assert audit["quality"] == "trusted" and audit["fatal"] is False
    assert audit["issues"] and all(not fatal_issues([i]) for i in audit["issues"])   # so "colunas sem cabecalho"
    assert t.table_data()["audit"] == audit
    bad = TechnicalTable(["CODIGO", "PSI", "L_ha@12"], [["PS1", 40, "77 66"]], {}, 1, [], ["CÓDIGO", "PSI", "12 km/h"])
    assert bad.stamp_audit()["quality"] == "degraded" and bad.audit["fatal"] is True


def test_w16_tables_inherit_section_only_when_page_has_one_section():
    t1 = TechnicalTable(["A", "B"], [["x", 1]], {}, 1, [], ["A", "B"])
    t2 = TechnicalTable(["C", "D"], [["y", 2]], {}, 1, [], ["C", "D"])
    one = chunk_pages([PageInput(1, "TITULO\nCorpo.\nSECAO UNICA\nMais corpo.", [t1])])
    assert [c.heading_path for c in one if c.kind == "table"] == [["TITULO", "SECAO UNICA"]]
    two = chunk_pages([PageInput(2, "TITULO\nCorpo.\nSECAO UM\nCorpo um.\nSECAO DOIS\nCorpo dois.", [t1, t2])])
    # duas secoes: nenhuma tabela herda a ultima secao por adivinhacao — so o titulo da pagina
    assert [c.heading_path for c in two if c.kind == "table"] == [["TITULO"], ["TITULO"]]
    # (os corpos curtos se agregam num chunk com o caminho do primeiro fragmento — politica de fragmentos)
    assert [c.heading_path for c in two if c.kind == "text"] == [["TITULO"]]


# ── W17–W24 tabela comercial: título, blocos lado a lado, moeda, adversariais ──
#
# Os valores da fixture são inventados (11.111, 22.222, 33.333, 44.444). Nenhum
# preço real entra em teste: se entrasse, o teste passaria por coincidir com o
# documento em vez de por ler a estrutura, e amarrar o pipeline a um número de
# tabela é exatamente o que não pode acontecer.

@pytest.fixture(scope="module")
def commercial_pdf(tmp_path_factory):
    return make_commercial_pdf(tmp_path_factory.mktemp("c") / "subdealer_sintetico.pdf")


def _price_tables(pdf):
    return [c for c in plan(pdf).chunks if c.kind == "price_table"]


def test_w17_commercial_table_is_price_table_and_trusted(commercial_pdf):
    """Tabela de preço tem que ser reconhecida pelo CONTEÚDO (R$ na célula), não
    por bandeira na linha de comando, e sair confiável — os quatro blocos."""
    tabelas = _price_tables(commercial_pdf)
    assert len(tabelas) == len(COMMERCIAL_BLOCKS)
    for c in tabelas:
        assert c.table_data["audit"]["quality"] == "trusted", c.table_data["audit"]["issues"]


def test_w18_title_above_header_becomes_title_not_header(commercial_pdf):
    """O nome do produto está ACIMA do cabeçalho. Sem promover a segunda linha,
    ele vira o cabeçalho e as colunas de preço ficam col_1/col_2."""
    titulos = {c.table_data.get("title") for c in _price_tables(commercial_pdf)}
    assert titulos == {b[0] for b in COMMERCIAL_BLOCKS}
    for c in _price_tables(commercial_pdf):
        assert "Pgto_faturado" in c.table_data["headers"]
        assert "Pgto_a_vista" in c.table_data["headers"]


def test_w19_side_by_side_blocks_are_separate_tables(commercial_pdf):
    """Dois blocos lado a lado com calha vazia no meio são DUAS tabelas. Juntos,
    o preço da direita responderia pergunta da esquerda."""
    tabelas = _price_tables(commercial_pdf)
    por_titulo = {c.table_data["title"]: c.table_data["rows"] for c in tabelas}
    t25p = por_titulo["DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000"]
    t25 = por_titulo["DRONE AGRAS T25 + 3 BAT + CARREGADOR C8000"]
    assert t25p[0][1] == 11111.0 and t25[0][1] == 22222.0
    # a mesma tabela nunca carrega os dois produtos
    for c in tabelas:
        assert len([b for b in COMMERCIAL_BLOCKS if b[0] == c.table_data["title"]]) == 1


def test_w20_money_with_decorative_dashes_is_a_number():
    """"-R$ 33.333,00-" é 33333.0, não texto nem negativo. Negativo de verdade
    continua negativo, e número solto não é dinheiro."""
    assert parse_number("-R$ 33.333,00-") == 33333.0
    assert parse_number("R$ -33.333,00") == -33333.0
    assert parse_number("-33.333,00") == -33333.0
    assert is_money("-R$ 999,00-") and is_money("R$ 1.099,00")
    assert not is_money("1580") and not is_money("DB1580") and not is_money("2,76")


def test_w21_columns_keep_the_payment_condition(commercial_pdf):
    """À vista ≠ faturado ≠ cliente final mínimo: três valores diferentes que
    não podem colapsar em um. O da linha 'cliente final' não tem faturado."""
    por_titulo = {c.table_data["title"]: c.table_data for c in _price_tables(commercial_pdf)}
    td = por_titulo["DRONE AGRAS T55 + 3 BAT DB1050 + CARREGADOR C7000"]
    i_fat = td["headers"].index("Pgto_faturado")
    i_vista = td["headers"].index("Pgto_a_vista")
    revenda, cliente = td["rows"][0], td["rows"][1]
    assert revenda[i_fat] == 33333.0 and revenda[i_vista] == 30303.0
    assert cliente[i_fat] is None and cliente[i_vista] == 35353.0
    assert td["units"][td["headers"][i_fat]] == "BRL"


def test_w22_adversarial_codes_never_collapse(commercial_pdf):
    """T25P ≠ T25, DB1050 ≠ DB1580, C7000 ≠ C12000: cada bloco só declara os
    códigos que estão nele."""
    por_titulo = {c.table_data["title"]: set(c.codes) for c in _price_tables(commercial_pdf)}
    t25p = por_titulo["DRONE AGRAS T25P + 3 BAT + CARREGADOR C8000"]
    t25 = por_titulo["DRONE AGRAS T25 + 3 BAT + CARREGADOR C8000"]
    assert "T25P" in t25p and "T25" not in t25p
    assert "T25" in t25 and "T25P" not in t25
    db1050 = por_titulo["DRONE AGRAS T55 + 3 BAT DB1050 + CARREGADOR C7000"]
    db1580 = por_titulo["DRONE AGRAS T55 + 3 BAT DB1580 + CARREGADOR C12000"]
    assert "DB1050" in db1050 and "DB1580" not in db1050 and "C7000" in db1050
    assert "DB1580" in db1580 and "DB1050" not in db1580 and "C12000" in db1580


def test_w23_money_is_not_a_product_code_and_quantity_is_not_a_price():
    """Preço não vira código ("165.500,00" não é peça) e "3 BAT" não vira preço."""
    achados = extract_codes("SUBDEALER REVENDA R$ 165.500,00 R$ 159.000,00 -R$ 21.550,00-")
    assert achados == []
    assert parse_number("3 BAT") is None
    assert not is_money("3 BAT")
    # o código do produto continua saindo do mesmo texto
    assert "T100" in extract_codes("DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000 R$ 165.500,00")


def test_w24_split_only_when_unambiguous():
    """A separação lado a lado é conservadora: tabela estreita, sem coluna
    inteiramente vazia, ou com um lado de uma coluna só não se divide."""
    estreita = [["a", "", "b"], ["1", "", "2"]]
    assert len(split_side_by_side(estreita)) == 1
    sem_calha = [["a", "b", "c", "d", "e"], ["1", "2", "3", "4", "5"]]
    assert len(split_side_by_side(sem_calha)) == 1
    lado_de_uma_coluna = [["a", "b", "", "c", "d"], ["1", "2", "", "3", "4"]]
    assert len(split_side_by_side(lado_de_uma_coluna)) == 2
    um_lado_magro = [["a", "b", "c", "", "d"], ["1", "2", "3", "", "4"]]
    assert len(split_side_by_side(um_lado_magro)) == 1


# ── W25–W31 planilha comercial: blocos empilhados, coluna de código, adversariais ──
#
# Códigos inventados (519220100, 5192201, 519220101, 77T310X) de propósito:
# o teste tem que provar que o pipeline LÊ a estrutura, não que decorou uma
# planilha de fornecedor.

@pytest.fixture(scope="module")
def quote_xlsx(tmp_path_factory):
    return make_quote_xlsx(tmp_path_factory.mktemp("q") / "orcamento_sintetico.xlsx")


def _tables(pdf_or_xlsx):
    return [c for c in plan(pdf_or_xlsx).chunks if c.kind in ("table", "price_table")]


def test_w25_stacked_blocks_are_separate_tables(quote_xlsx):
    """Dois blocos empilhados na mesma aba, separados por linha vazia, são duas
    tabelas. Juntos, o título do primeiro passa a valer para as linhas do
    segundo — e o cabeçalho repetido vira linha de dados."""
    tabelas = _tables(quote_xlsx)
    titulos = [t.table_data.get("title") for t in tabelas]
    assert "SISTEMA DE TESTE ALFA" in titulos and "SISTEMA DE TESTE BETA" in titulos
    for t in tabelas:
        # nenhuma linha repete o cabeçalho
        rotulos = {str(h).strip().lower() for h in t.table_data["labels"] if h}
        for row in t.table_data["rows"]:
            texto = {str(c).strip().lower() for c in row if isinstance(c, str)}
            assert len(texto & rotulos) < 2, (t.table_data["title"], row)


def test_w26_spreadsheet_provenance_is_sheet_and_rows(quote_xlsx):
    """Planilha não tem página; a proveniência é aba + intervalo de linhas."""
    for t in _tables(quote_xlsx):
        assert any(n.startswith("aba: ") and ", linhas " in n for n in t.table_data["notes"]), t.table_data["notes"]


def test_w27_declared_code_column_is_read_as_code(quote_xlsx):
    """Coluna que se declara "COD" é código por declaração — não precisa que o
    valor caiba num padrão. É o que resgata código que começa por dígito."""
    por_titulo = {t.table_data["title"]: set(t.codes) for t in _tables(quote_xlsx)}
    assert set(SHEET_CODES["bloco1"]) <= por_titulo["SISTEMA DE TESTE ALFA"]
    assert set(SHEET_CODES["bloco2"]) <= por_titulo["SISTEMA DE TESTE BETA"]


def test_w28_similar_codes_never_collapse(quote_xlsx):
    """519220100 ≠ 519220101 ≠ 5192201: um bloco não empresta código ao outro."""
    por_titulo = {t.table_data["title"]: set(t.codes) for t in _tables(quote_xlsx)}
    alfa, beta = por_titulo["SISTEMA DE TESTE ALFA"], por_titulo["SISTEMA DE TESTE BETA"]
    assert "519220100" in alfa and "519220101" not in alfa
    assert "519220101" in beta and "519220100" not in beta
    assert "5192201" in alfa and "5192201" not in beta


def test_w29_price_phone_and_document_are_not_codes(quote_xlsx):
    """Preço, telefone e CNPJ não viram código de produto."""
    for t in _tables(quote_xlsx):
        for c in t.codes:
            assert c not in {"1234", "1098", "1099", "540", "123456780001", "4333334444"}
    contatos = [t for t in _tables(quote_xlsx) if "Contatos" in " ".join(t.table_data["notes"])]
    assert contatos and contatos[0].codes == []
    assert extract_codes("(43) 3333-4444 12.345.678/0001-90 R$ 1.234,56") == []


def test_w30_formula_without_value_never_leaks_as_text(quote_xlsx):
    """Célula de fórmula sem valor calculado fica vazia — nunca vira "=E3*A3"
    como se fosse dado."""
    for t in _tables(quote_xlsx):
        for row in t.table_data["rows"]:
            for c in row:
                assert not (isinstance(c, str) and c.startswith("=")), row


def test_w31_stacked_split_is_conservative():
    """Separação por linha vazia só quando é inequívoca: tabela curta, sem
    linha vazia, ou com um bloco de uma linha só não se divide."""
    curta = [["a", "b"], [], ["c", "d"]]
    assert len(split_stacked(curta)) == 1
    sem_vazia = [["a", "b"], ["1", "2"], ["3", "4"], ["5", "6"]]
    assert len(split_stacked(sem_vazia)) == 1
    bloco_de_uma = [["a", "b"], ["1", "2"], ["3", "4"], [], ["5", "6"]]
    assert len(split_stacked(bloco_de_uma)) == 1
    dois_blocos = [["a", "b"], ["1", "2"], [], ["c", "d"], ["3", "4"]]
    partes = split_stacked(dois_blocos)
    assert len(partes) == 2 and partes[0][0] == 0 and partes[1][0] == 3


# ── W32–W34 · cabeçalho que é, na verdade, uma linha de dados ──────────

def _tabela(headers, rows, labels=None, units=None):
    return TechnicalTable(headers, rows, units or {}, 1, [], labels or list(headers))


def test_w32_preco_no_cabecalho_denuncia_linha_engolida():
    """Um cabeçalho NOMEIA a coluna; ele nunca É um preço. Quando a tabela
    traz o cabeçalho uma vez só e os blocos seguintes são continuação visual,
    a reconstrução promove a primeira linha de produto a cabeçalho — e o
    produto some dos dados. O sinal genérico disso é dinheiro no rótulo."""
    from brain_worker.tables import audit_table, fatal_issues
    engolida = _tabela(
        ["col_0", "LINHA_LE", "1243", "84368000", "DRONE_MIX_130L", "R_5_600_00", "R_8_200_00", "col_7"],
        [[None, None, 1361, 84368000, "DRONE MIX 200L LE", "R$ 6 .200,00", "R$ 9 .500,00", None]],
        labels=["", 'LINHA "LE"', "1243", "84368000", "DRONE MIX 130L LE",
                "R$ 5 .600,00", "R$ 8 .200,00", ""])
    issues = audit_table(engolida)
    assert any("valor monetario" in i for i in issues), issues
    # e é FATAL: tabela com um produto faltando não pode ser evidência
    assert fatal_issues(issues)


def test_w33_preco_quebrado_por_espaco_tambem_e_pego():
    """O PDF da JR quebra "R$ 5.600,00" em "R$ 5 .600,00". Um teste que
    dependesse de parse numérico deixaria passar justamente o caso que
    motivou a regra — por isso o sinal é o símbolo da moeda."""
    from brain_worker.tables import audit_table
    assert not is_money("R$ 5 .600,00")          # o parse de fato falha
    t = _tabela(["a", "b"], [[1, 2]], labels=["CÓDIGO", "R$ 5 .600,00"])
    assert any("valor monetario" in i for i in audit_table(t))


def test_w34_cabecalho_comercial_legitimo_nao_e_falso_positivo():
    """"VALOR UNITARIO" e "Pgto à vista" nomeiam dinheiro sem carregar
    dinheiro. Nenhum dos três corpos reais pode virar degradado por isto."""
    from brain_worker.tables import audit_table
    arag = _tabela(
        ["QUANTIDADE", "DESCRICAO", "COD", "VALOR_UNITARIO", "VALOR_TOTAL"],
        [[1, "SENSOR PRESSAO", 466113200, 1098.0, 1098]],
        labels=["QUANTIDADE", "DESCRIÇÃO", "COD", "VALOR UNITARIO", "VALOR TOTAL"])
    dji = _tabela(
        ["col_0", "Pgto_faturado1", "Pgto_a_vista"],
        [["SUBDEALER REVENDA", 165500.0, 161900.0]],
        labels=["", "Pgto faturado¹", "Pgto à vista"])
    magnojet = _tabela(
        ["CODIGO_PONTAS", "BAR", "PSI", "L_ha@12"],
        [["MJ981CAP", 2.76, 40, 77]],
        labels=["CÓDIGO PONTAS", "BAR", "PSI", "12 km/h"])
    for t in (arag, dji, magnojet):
        assert not any("valor monetario" in i for i in audit_table(t)), t.labels


# ── W35–W37 · NCM é classificação fiscal, não código de peça ────────────


def test_w35_ncm_declarado_nao_vira_codigo_de_peca():
    """NCM é classificação fiscal compartilhada por dezenas de produtos. Se
    entrar em `codes`, perguntar pelo NCM devolve o catálogo inteiro pelo
    braço exato — e a resposta passa a ser sobre imposto, não sobre peça."""
    t = _tabela(
        ["CODIGO", "NCM", "PRODUTO", "REVENDAS"],
        [[2141, 84368000, "DRONE FEEDER 500 - 220Volts", 11700.0],
         [1243, 84368000, "DRONE MIX 130L LE", 5600.0]],
        labels=["CÓDIGO", "NCM", "PRODUTO", "REVENDAS"])
    codes = t.codes()
    assert "2141" in codes and "1243" in codes, codes
    assert "84368000" not in codes, codes


def test_w36_coluna_de_codigo_continua_mandando():
    """Se o mesmo valor for declarado nas DUAS colunas, quem diz "código"
    ganha: a exclusão fiscal não pode apagar um código de peça legítimo."""
    t = _tabela(
        ["CODIGO", "NCM", "PRODUTO"],
        [[84368000, 84368000, "PECA COM CODIGO IGUAL AO NCM"]],
        labels=["CÓDIGO", "NCM", "PRODUTO"])
    assert "84368000" in t.codes()


def test_w37_sem_coluna_fiscal_nada_muda():
    """Tabela sem coluna de NCM segue exatamente como antes — a regra nova
    não tira nada de quem não declarou classificação fiscal."""
    t = _tabela(
        ["COD", "DESCRICAO", "VALOR"],
        [["46202G", "FLUXOMETRO ORION 3", 2602.29],
         ["863T026S", "VALVULA PROPORCIONAL", 897.0]],
        labels=["COD", "DESCRIÇÃO", "VALOR"])
    codes = t.codes()
    assert "46202G" in codes and "863T026S" in codes, codes
