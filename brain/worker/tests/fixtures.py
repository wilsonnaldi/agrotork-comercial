"""Documentos SINTÉTICOS para os testes do worker. Nenhum arquivo real.

`catalogo_sintetico.pdf` imita a estrutura do Catálogo Magnojet V41 —
página institucional, página com tabela técnica (a "p. 20": cabeçalho com
unidades, códigos, pressão, vazão, L/ha) e uma página de texto longo — com
nomes e números inventados (fabricante "Pontas Sol", código PS981CAP). O
formato é o que importa; o conteúdo é de mentira.
"""
from __future__ import annotations

from pathlib import Path

LOREM = (
    "A ponta de pulverização deve ser escolhida conforme a calda, a pressão de trabalho e o alvo. "
    "Pontas de jato plano são indicadas para herbicidas em pré e pós-emergência; pontas de cone vazio, "
    "para fungicidas e inseticidas que exigem cobertura. A vazão nominal é medida a 3 bar e a 40 psi; "
    "verifique a tabela de cada família antes de calibrar. "
)

TABLE_HEADERS = ["Código", "Série", "Gotas", "Pressão (bar)", "Pressão (psi)", "Vazão (L/min)", "L/ha a 12 km/h"]
TABLE_ROWS = [
    ["PS981CAP", "SOL-CV 02", "UG", "2,07", "30", "0,66", "66"],
    ["PS981CAP", "SOL-CV 02", "UG", "2,76", "40", "0,77", "77"],
    ["PS982CAP", "SOL-CV 025", "UG", "2,07", "30", "0,83", "83"],
    ["PS983CAP", "SOL-CV 03", "UG", "2,76", "40", "1,15", "115"],
]


def make_catalog_pdf(path: Path, pages_long_text: int = 1, scanned: bool = False) -> Path:
    """PDF com camada textual (ou, com scanned=True, só imagem: dispara a rota de OCR)."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib import colors

    if scanned:
        c = canvas.Canvas(str(path), pagesize=A4, invariant=1)   # bytes iguais a cada geracao
        # um retângulo e nada de texto: pdfplumber não acha caracteres
        c.setFillColor(colors.lightgrey)
        c.rect(20 * mm, 20 * mm, 170 * mm, 250 * mm, fill=1, stroke=0)
        c.showPage()
        c.save()
        return path

    styles = getSampleStyleSheet()
    story = []
    # p.1 institucional
    story.append(Paragraph("PONTAS SOL", styles["Title"]))
    story.append(Paragraph("INSTITUCIONAL", styles["Heading2"]))
    story.append(Paragraph("Fundada em 1985, a Pontas Sol desenvolve pontas de pulverização com núcleo de cerâmica, "
                           "elevando os padrões de precisão e durabilidade no campo.", styles["BodyText"]))
    story.append(PageBreak())
    # p.2 tabela técnica ("p. 20")
    story.append(Paragraph("PONTAS", styles["Heading1"]))
    story.append(Paragraph("SOL ULTRA GROSSA CONE VAZIO", styles["Heading2"]))
    story.append(Paragraph("Aplicações de herbicidas sistêmicos em pré e pós-emergência.", styles["BodyText"]))
    story.append(Spacer(1, 6))
    t = Table([TABLE_HEADERS] + TABLE_ROWS)
    t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.5, colors.black), ("FONTSIZE", (0, 0), (-1, -1), 8)]))
    story.append(t)
    story.append(Spacer(1, 6))
    story.append(Paragraph("MALHA 50. Espaçamento entre bicos de 50 cm.", styles["BodyText"]))
    # p.3.. texto longo
    for i in range(pages_long_text):
        story.append(PageBreak())
        story.append(Paragraph(f"CAPÍTULO {i + 3} CALIBRAÇÃO", styles["Heading1"]))
        story.append(Paragraph(LOREM * 6, styles["BodyText"]))
        story.append(Spacer(1, 6))
        story.append(Paragraph(LOREM * 2, styles["BodyText"]))
    # invariant=1: sem data/hora nos metadados → o mesmo conteudo gera os mesmos bytes (mesmo sha256)
    SimpleDocTemplate(str(path), pagesize=A4, invariant=1).build(story)
    return path


def make_price_xlsx(path: Path) -> Path:
    import openpyxl

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Revenda"
    ws.append(["Item", "Faturado (R$)", "À vista (R$)", "Cliente final mínimo (R$)"])
    ws.append(["DRONE SOL S100 + 3 BAT + CARREGADOR C12000", 165500, 161900, 225000])
    ws.append(["DRONE SOL S25 + 3 BAT + CARREGADOR C8000", 64250, 61789, 87000])
    ws2 = wb.create_sheet("Baterias")
    ws2.append(["Código", "Modelo", "À vista (R$)"])
    ws2.append(["SB1580", "Bateria S55 / S70P", 9800])
    wb.save(str(path))
    return path


def make_text(path: Path) -> Path:
    path.write_text("PROCEDIMENTO\nPasso 1: zerar o sensor.\nPasso 2: aplicar pressão de referência.\f"
                    "ANEXO\nCódigo do sensor: 466113200, faixa 0-20 bar.", encoding="utf-8")
    return path
