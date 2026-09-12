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

from fixtures import TABLE_ROWS, make_catalog_pdf, make_price_xlsx, make_text  # noqa: E402
from brain_worker.chunking import CONFIG, MAX, PageInput, chunk_pages, is_heading  # noqa: E402
from brain_worker.codes import extract_codes, normalize_code  # noqa: E402
from brain_worker.extract import extract, mime_for, ocr_available, sniff_ok  # noqa: E402
from brain_worker.pipeline import plan, sha256_of  # noqa: E402
from brain_worker.tables import build_table, parse_number  # noqa: E402


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
    assert [c.page for c in chunks] == [1, 2]                  # ordenado por pagina, nao pela lista
    assert [c.ordinal for c in chunks] == [0, 1]
    assert chunks[0].heading_path == ["TITULO A"] and chunks[1].heading_path == ["TITULO A", "TITULO B"]
    assert "dois" not in chunks[0].content and "um" not in chunks[1].content


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
    assert [c.page for c in p.chunks] == [1, 2] and "466113200" in p.chunks[1].codes


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
