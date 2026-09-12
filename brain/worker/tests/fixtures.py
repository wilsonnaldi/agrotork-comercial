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


# ── Catálogo com tabela de vazão "à Magnojet" (cabeçalho de dois níveis, sem régua vertical
#    entre as velocidades, código de grupo numa coluna com régua só nas fronteiras de grupo,
#    título vertical na margem, títulos consecutivos). Reproduz, em sintético, o que o piloto
#    real encontrou. Só desenho com coordenadas: reportlab canvas, invariant=1.
FLOW_SPEEDS = [4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25]
FLOW_GROUPS = [
    # (código, série, malha, [(bar, psi, kpa, l/min, [l/ha por velocidade])])
    ("PS980CAP", "SOL-CV 015", "MALHA 50", [
        ("2,07", "30", "207", "0,50", [149, 120, 100, 85, 75, 66, 60, 50, 43, 37, 33, 30, 24]),
        ("2,76", "40", "276", "0,58", [173, 138, 115, 99, 86, 77, 69, 58, 49, 43, 38, 35, 28]),
        ("3,45", "50", "345", "0,64", [193, 154, 129, 110, 96, 86, 77, 64, 55, 48, 43, 39, 31]),
    ]),
    ("PS981CAP", "SOL-CV 02", "MALHA 50", [
        ("2,07", "30", "207", "0,66", [199, 159, 133, 114, 100, 89, 80, 66, 57, 50, 44, 40, 32]),
        ("2,76", "40", "276", "0,77", [230, 184, 153, 131, 115, 102, 92, 77, 66, 58, 51, 46, 37]),
        ("3,45", "50", "345", "0,86", [257, 206, 172, 147, 129, 114, 103, 86, 73, 64, 57, 51, 41]),
    ]),
]


def make_flow_pdf(path: Path) -> Path:
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    c = canvas.Canvas(str(path), pagesize=A4, invariant=1)
    W, H = A4
    # titulo vertical na margem (como "SOLUÇÕES" no catalogo real): letras soltas se lidas no corpo
    c.saveState(); c.translate(30, 300); c.rotate(90); c.setFont("Helvetica-Bold", 14); c.drawString(0, 0, "SOLUÇÕES"); c.restoreState()
    # titulos consecutivos (sem paragrafo entre eles) + corpo
    c.setFont("Helvetica-Bold", 12)
    c.drawString(60, H - 60, "APLICAÇÕES DE HERBICIDAS SISTÊMICOS")
    c.drawString(60, H - 76, "SOL ULTRA GROSSA")
    c.drawString(60, H - 92, "CONE VAZIO")
    c.setFont("Helvetica", 9)
    c.drawString(60, H - 110, "Ponta de cerâmica com alta durabilidade. Recomendado para herbicidas sistêmicos.")
    # rotulos curtos de desenho (microchunks) e um paragrafo que "valoriza" (nao e tabela de preco)
    c.setFont("Helvetica", 8)
    for i, lab in enumerate(["Ø 108,00", "R 1/2", "100", "M 714", "M 691/1A"]):
        c.drawString(60, H - 130 - 10 * i, lab)
    c.drawString(60, H - 190, "O programa valoriza o atendimento do revendedor e traz recomendações assertivas ao produtor.")

    # ── tabela ─────────────────────────────────────────────
    left, top = 120, H - 230         # abaixo da prosa; y cresce para cima no PDF
    col_x = [left, left + 60, left + 78, left + 100, left + 122, left + 146, left + 170]   # bordas: codigo|gotas|bar|psi|kpa|lmin|velocidades...
    sp_x0 = left + 170
    sp_w = 22
    right = sp_x0 + sp_w * len(FLOW_SPEEDS)
    row_h = 9
    hdr_h = 30
    # cabecalho de grupo com caixa embaixo (so a regua horizontal), sobre as velocidades
    c.setFont("Helvetica-Bold", 6)
    c.drawCentredString((sp_x0 + right) / 2, top - 8, "LITROS POR HECTARE (ESPAÇAMENTO 50CM)")
    c.line(sp_x0, top - 11, right, top - 11)
    for i, s in enumerate(FLOW_SPEEDS):
        c.setFont("Helvetica-Bold", 6); c.drawCentredString(sp_x0 + sp_w * i + sp_w / 2, top - 19, str(s))
        c.setFont("Helvetica", 5); c.drawCentredString(sp_x0 + sp_w * i + sp_w / 2, top - 26, "km/h")
    c.setFont("Helvetica-Bold", 5)
    c.drawString(left + 3, top - 12, "CÓDIGO"); c.drawString(left + 3, top - 19, "PONTAS")
    for x, lab in zip(col_x[2:6], ["BAR", "PSI", "kPa", "L/min"]):
        c.drawString(x + 3, top - 26, lab)
    # "GOTAS" vertical (girado) sobre a coluna de gotas
    c.saveState(); c.translate(col_x[1] + 12, top - 27); c.rotate(90); c.setFont("Helvetica-Bold", 4); c.drawString(0, 0, "GOTAS"); c.restoreState()
    data_top = top - hdr_h
    # reguas verticais so nas primeiras colunas (entre as velocidades nao ha)
    n_rows = sum(len(g[3]) for g in FLOW_GROUPS)
    bottom = data_top - row_h * n_rows
    for x in col_x + [right]:
        c.line(x, top, x, bottom)
    c.line(left, top, right, top)
    y = data_top
    for code, serie, malha, rows in FLOW_GROUPS:
        g_top = y
        g_bottom = y - row_h * len(rows)
        # regua de grupo cruza a coluna de codigo; reguas de linha so na area numerica
        c.line(left, g_top, right, g_top)
        c.setFont("Helvetica-Bold", 5); c.drawString(left + 3, g_top - 8, code)
        c.setFont("Helvetica", 4.5); c.drawString(left + 3, g_top - 15, serie); c.drawString(left + 3, g_top - 22, malha)
        for bar, psi, kpa, lmin, lha in rows:
            c.setFont("Helvetica", 5.5)
            c.drawString(col_x[1] + 4, y - 7, "UG")
            for x, v in zip(col_x[2:6], (bar, psi, kpa, lmin)):
                c.drawString(x + 3, y - 7, v)
            for i, v in enumerate(lha):
                c.drawCentredString(sp_x0 + sp_w * i + sp_w / 2, y - 7, str(v))
            y -= row_h
            c.line(col_x[1], y, right, y)
    c.line(left, bottom, right, bottom)
    c.showPage()
    c.save()
    return path
