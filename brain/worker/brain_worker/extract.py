"""Extração de texto por página.

Formatos:
  · PDF  — pdfplumber: texto da camada textual e tabelas por página. Se a
           página não tem camada textual confiável (razão texto/área baixa),
           é marcada `needs_ocr`; o OCR local (tesseract, se instalado) roda
           só nessas páginas. `extraction` fica `text_layer` ou `ocr`.
  · XLSX — openpyxl: cada ABA é uma "página" (unidade equivalente,
           documentada), o conteúdo é uma tabela. `extraction = spreadsheet`.
  · CSV  — uma página, uma tabela. `extraction = spreadsheet`.
  · TXT/MD — páginas separadas por form-feed (\\f); sem form-feed, uma página.
           `extraction = text_layer`.

Nada aqui sai da máquina: OCR é local. Provedor externo (se um dia existir)
passa pelo `ExternalGate` (gate.py) e nunca por aqui.
"""
from __future__ import annotations

import csv
import io
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .spatial import _rotated_words, reconstruct_table
from .tables import TechnicalTable, audit_table, build_table, fatal_issues

SUPPORTED = {
    ".pdf": "application/pdf",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".csv": "text/csv",
    ".txt": "text/plain",
    ".md": "text/markdown",
}

# Abaixo disto de caracteres por página (média) o PDF é tratado como
# digitalizado: Albuz e o Catálogo Digital JR ficam aqui (inventário Etapa 0).
OCR_MIN_CHARS_PER_PAGE = 40


@dataclass
class ExtractedPage:
    page_no: int
    text: str
    extraction: str            # text_layer | ocr | spreadsheet | manual | none
    ocr: bool = False
    tables: list[TechnicalTable] = field(default_factory=list)
    layout: dict[str, Any] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


@dataclass
class Extraction:
    pages: list[ExtractedPage]
    method: str                # pdf_text | pdf_ocr | xlsx | other
    parser: str
    needs_ocr: bool
    text_ratio: float | None
    warnings: list[str] = field(default_factory=list)

    @property
    def pages_total(self) -> int:
        return len(self.pages)


def mime_for(path: Path) -> str:
    ext = path.suffix.lower()
    if ext not in SUPPORTED:
        raise ValueError(f"Tipo nao suportado: {ext or '(sem extensao)'}. Aceitos: {', '.join(sorted(SUPPORTED))}")
    return SUPPORTED[ext]


def sniff_ok(path: Path) -> bool:
    """Assinatura mínima: PDF começa com %PDF, XLSX é ZIP (PK). Texto: qualquer coisa."""
    ext = path.suffix.lower()
    head = path.open("rb").read(4)
    if ext == ".pdf":
        return head.startswith(b"%PDF")
    if ext == ".xlsx":
        return head.startswith(b"PK")
    return True


def ocr_available() -> bool:
    return shutil.which("tesseract") is not None


# ── PDF ─────────────────────────────────────────────────────

def _pdf_ocr_page(page) -> str:
    """OCR local de uma página (tesseract via pytesseract). Nunca externo."""
    import pytesseract  # import tardio: opcional

    img = page.to_image(resolution=200).original
    langs = "por+eng" if "por" in pytesseract.get_languages() else "eng"
    return pytesseract.image_to_string(img, lang=langs)


def _table_regions(page):
    """Regiões de tabela da página: o que `find_tables` achou, com regiões
    verticalmente adjacentes e alinhadas (cabeçalho numa caixa, corpo na outra)
    fundidas numa só. Devolve [(bbox, tabela_ou_None)] — None quando a região
    é a fusão de duas (só a reconstrução geométrica a lê)."""
    found = list(page.find_tables() or [])
    found.sort(key=lambda t: (t.bbox[1], t.bbox[0]))
    regions: list[tuple[tuple[float, float, float, float], object | None]] = []
    for t in found:
        x0, top, x1, bottom = t.bbox
        merged = False
        for k, ((px0, ptop, px1, pbottom), _) in enumerate(regions):
            overlap = min(x1, px1) - max(x0, px0)
            width = min(x1 - x0, px1 - px0)
            if width > 0 and overlap / width >= 0.8 and 0 <= top - pbottom <= 6:
                regions[k] = ((min(x0, px0), ptop, max(x1, px1), bottom), None)
                merged = True
                break
        if not merged:
            regions.append(((x0, top, x1, bottom), t))
    return regions


def extract_pdf(path: Path, ocr: str = "auto") -> Extraction:
    """ocr: 'auto' (só páginas sem camada textual), 'never', 'force'."""
    import pdfplumber

    pages: list[ExtractedPage] = []
    warnings: list[str] = []
    total_chars = 0
    with pdfplumber.open(str(path)) as pdf:
        for i, page in enumerate(pdf.pages, start=1):
            tables: list[TechnicalTable] = []
            bboxes = []
            reconstructed = 0
            try:
                for bbox, found in _table_regions(page):
                    t = build_table(found.extract(), page=i) if found is not None else None
                    issues = audit_table(t) if (t and t.is_meaningful) else ["regiao sem tabela pelo detector padrao"]
                    if issues:
                        # O detector por régua não virou dado confiável: refaz pela geometria.
                        rec, _w = reconstruct_table(page, bbox, page_no=i)
                        rec_issues = audit_table(rec) if (rec is not None and rec.is_meaningful) else None
                        # entra se nao tem sinal FATAL e (a original tinha, ou ficou com menos sinais)
                        if rec_issues is not None and not fatal_issues(rec_issues) \
                                and (fatal_issues(issues) or len(rec_issues) < len(issues)):
                            t = rec
                            reconstructed += 1
                        elif t is not None:
                            t.notes.extend(issues)
                            warnings.append(f"p.{i}: tabela com {len(issues)} sinal(is) de estrutura ruim nao reconstruida: " + "; ".join(issues))
                    if t is None or not t.is_meaningful:
                        continue
                    tables.append(t)
                    bboxes.append(bbox)
            except Exception as exc:  # tabela mal formada não derruba a página
                warnings.append(f"p.{i}: tabela ignorada ({exc.__class__.__name__})")
            # O texto da página NÃO inclui o que está dentro das tabelas: a tabela
            # é chunk próprio, e o mesmo dado não pode aparecer duas vezes.
            # Texto rotacionado (arte lateral, títulos verticais) também fica fora
            # do corpo: vai para o layout como `rotated_text`, legível.
            body = page.filter(lambda obj: obj.get("upright", True))
            for (x0, top, x1, bottom) in bboxes:
                body = body.filter(lambda obj, x0=x0, top=top, x1=x1, bottom=bottom:
                                   not (obj.get("x0", 0) >= x0 - 1 and obj.get("x1", 0) <= x1 + 1
                                        and obj.get("top", 0) >= top - 1 and obj.get("bottom", 0) <= bottom + 1))
            text = body.extract_text() or ""
            rotated = [w.text for w in _rotated_words(page.chars, page.bbox[1], page.bbox[3])]
            total_chars += len(text.strip()) + sum(len(t.render_text()) for t in tables)
            layout = {"width": float(page.width), "height": float(page.height), "tables": len(tables),
                      "tables_reconstructed": reconstructed}
            if rotated:
                layout["rotated_text"] = rotated
            pages.append(ExtractedPage(i, text, "text_layer", False, tables, layout))
            # pdfplumber guarda todos os objetos de cada pagina ja lida; num catalogo
            # de 170+ paginas cheias de vetores isso passa de 6 GB e o processo morre.
            # Cada pagina e independente: solta o cache assim que ela foi extraida.
            page.flush_cache()
            page.close()
    n = max(len(pages), 1)
    ratio = total_chars / n
    needs_ocr = ratio < OCR_MIN_CHARS_PER_PAGE
    method = "pdf_text"

    if ocr != "never" and (needs_ocr or ocr == "force"):
        if ocr_available():
            for p in pages:
                if ocr == "force" or len(p.text.strip()) < OCR_MIN_CHARS_PER_PAGE:
                    try:
                        with pdfplumber.open(str(path)) as pdf:
                            p.text = _pdf_ocr_page(pdf.pages[p.page_no - 1])
                        p.extraction, p.ocr = "ocr", True
                    except Exception as exc:
                        p.extraction = "none"
                        p.warnings.append(f"OCR falhou: {exc.__class__.__name__}: {exc}")
            method = "pdf_ocr"
        else:
            warnings.append("PDF sem camada textual e tesseract ausente: paginas ficam extraction=none")
            for p in pages:
                if len(p.text.strip()) < OCR_MIN_CHARS_PER_PAGE:
                    p.extraction = "none"
    return Extraction(pages, method, "pdfplumber " + pdfplumber.__version__, needs_ocr, round(ratio, 4), warnings)


# ── XLSX / CSV ──────────────────────────────────────────────

def _cell(c: Any) -> str:
    return "" if c is None else str(c).strip()


def extract_xlsx(path: Path) -> Extraction:
    import openpyxl

    wb = openpyxl.load_workbook(str(path), read_only=True, data_only=True)
    pages: list[ExtractedPage] = []
    for i, ws in enumerate(wb.worksheets, start=1):
        rows = [list(r) for r in ws.iter_rows(values_only=True)]
        table = build_table(rows, page=i)
        if table and table.is_meaningful:
            # A aba inteira e a tabela: nenhum texto solto, o nome da aba vai na nota.
            table.notes.append(f"aba: {ws.title}")
            pages.append(ExtractedPage(i, "", "spreadsheet", False, [table], {"sheet": ws.title, "rows": len(rows)}))
        else:
            text = "\n".join(" ".join(_cell(c) for c in r) for r in rows if any(_cell(c) for c in r))
            pages.append(ExtractedPage(i, f"{ws.title}\n{text}".strip(), "spreadsheet", False, [], {"sheet": ws.title, "rows": len(rows)}))
    return Extraction(pages, "xlsx", "openpyxl " + openpyxl.__version__, False, None,
                      ["planilha: cada aba e uma pagina"])


def extract_csv(path: Path) -> Extraction:
    raw = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8-sig")), delimiter=";" if ";" in path.read_text(encoding="utf-8-sig").splitlines()[0] else ","))
    table = build_table(raw, page=1)
    text = "" if (table and table.is_meaningful) else "\n".join(" ".join(r) for r in raw)
    return Extraction([ExtractedPage(1, text, "spreadsheet", False, [table] if table and table.is_meaningful else [], {"rows": len(raw)})],
                      "other", "csv", False, None, ["csv: uma pagina, uma tabela"])


def extract_text(path: Path) -> Extraction:
    content = path.read_text(encoding="utf-8")
    parts = content.split("\f") if "\f" in content else [content]
    pages = [ExtractedPage(i, p, "text_layer", False, [], {}) for i, p in enumerate(parts, start=1)]
    return Extraction(pages, "other", "text", False, None, ["texto: form-feed separa paginas"] if "\f" in content else ["texto: uma pagina"])


def extract(path: Path, ocr: str = "auto") -> Extraction:
    ext = path.suffix.lower()
    if ext == ".pdf":
        return extract_pdf(path, ocr)
    if ext == ".xlsx":
        return extract_xlsx(path)
    if ext == ".csv":
        return extract_csv(path)
    if ext in (".txt", ".md"):
        return extract_text(path)
    raise ValueError(f"Tipo nao suportado: {ext}")
