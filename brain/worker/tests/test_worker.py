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

from fixtures import FLOW_SPEEDS, TABLE_ROWS, make_catalog_pdf, make_flow_pdf, make_price_xlsx, make_text  # noqa: E402
from brain_worker.chunking import CONFIG, MAX, PageInput, chunk_pages, is_heading  # noqa: E402
from brain_worker.codes import extract_codes, known_profiles, normalize_code  # noqa: E402
from brain_worker.extract import extract, mime_for, ocr_available, sniff_ok  # noqa: E402
from brain_worker.pipeline import plan, sha256_of  # noqa: E402
from brain_worker.tables import TechnicalTable, build_table, parse_number  # noqa: E402


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
    assert td["units"]["Faturado_R"] == "BRL" and td["rows"][0][1] == 165500 and "aba: Revenda" in td["notes"]
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
