"""Reconstrução espacial de tabelas técnicas.

O detector padrão do pdfplumber (`page.find_tables()`) depende de linhas de
régua. Em catálogos com colunas estreitas sem régua vertical ele funde
colunas ("77 66 5" / "8 51 46"), deixa o cabeçalho de velocidades cair como
linha de dados e não propaga o código do grupo. Este módulo reconstrói a
tabela a partir da GEOMETRIA real do PDF — coordenadas x/y de cada palavra —
sem nenhuma heurística de texto:

  1. linhas = palavras agrupadas pela coordenada vertical;
  2. linhas de dados = linhas com maioria de tokens numéricos e a mesma
     assinatura (quantidade de números) da moda da tabela;
  3. colunas = centros horizontais recorrentes nas linhas de dados;
  4. cada palavra de uma linha de dados vai para a coluna cujo centro está
     mais perto; duas palavras na mesma célula → célula NULA + warning
     (nunca se fabrica um valor);
  5. cabeçalho = zona acima da primeira linha de dados; uma corrida de
     palavras que cobre 2+ colunas é rótulo de GRUPO ("LITROS POR
     HECTARE"), uma que cobre 1 coluna é rótulo da coluna ("12" + "km/h",
     empilhados em y → "12 km/h");
  6. coluna de rótulo (código/modelo) = palavras fora das linhas de dados;
     seus grupos são delimitados pelas réguas horizontais que cruzam essa
     coluna — o rótulo vale para todas as linhas de dados dentro do mesmo
     intervalo. Sem régua, o rótulo fica só na linha mais próxima.

Texto rotacionado (cabeçalho vertical "GOTAS") é remontado pela matriz do
caractere. Nada aqui conhece página, produto ou valor de nenhum catálogo.
"""
from __future__ import annotations

import re
import statistics
from dataclasses import dataclass, field
from typing import Any

from .tables import TechnicalTable, _header_key, _unaccent, _unit_of, parse_number

_UNIT_WORDS = {"km/h", "bar", "psi", "kpa", "l/min", "l/ha", "mm", "cm", "ml", "l", "%"}
# Unidades escritas por extenso num rótulo de grupo. Genérico (português técnico),
# não é conhecimento de catálogo específico.
_SPELLED_UNITS = [
    (re.compile(r"litros?\s+por\s+hectare|l\s*/\s*ha"), "L/ha"),
    (re.compile(r"litros?\s+por\s+minuto|l\s*/\s*min"), "L/min"),
    (re.compile(r"\bkpa\b"), "kPa"),
    (re.compile(r"\bpsi\b"), "psi"),
    (re.compile(r"\bbar\b"), "bar"),
    (re.compile(r"\bkm\s*/\s*h\b"), "km/h"),
]


@dataclass
class Word:
    text: str
    x0: float
    x1: float
    top: float
    bottom: float

    @property
    def xc(self) -> float:
        return (self.x0 + self.x1) / 2

    @property
    def yc(self) -> float:
        return (self.top + self.bottom) / 2

    @property
    def h(self) -> float:
        return self.bottom - self.top


@dataclass
class Column:
    center: float
    x0: float
    x1: float
    kind: str = "data"           # data | label
    header_parts: list[str] = field(default_factory=list)
    group_parts: list[str] = field(default_factory=list)
    spans: list[tuple[float, float, str]] = field(default_factory=list)   # só label: (top, bottom, rótulo)


def _cluster_1d(values: list[float], tol: float) -> list[list[int]]:
    """Índices agrupados por proximidade (ordem crescente do valor)."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    groups: list[list[int]] = []
    for i in order:
        if groups and values[i] - values[groups[-1][-1]] <= tol:
            groups[-1].append(i)
        else:
            groups.append([i])
    return groups


def _lines(words: list[Word], tol: float) -> list[list[Word]]:
    if not words:
        return []
    groups = _cluster_1d([w.yc for w in words], tol)
    return [sorted((words[i] for i in g), key=lambda w: w.x0) for g in groups]


def _runs(line: list[Word], gap: float) -> list[list[Word]]:
    """Palavras de uma linha separadas em corridas contíguas (gap horizontal pequeno)."""
    runs: list[list[Word]] = []
    for w in line:
        if runs and w.x0 - runs[-1][-1].x1 <= gap:
            runs[-1].append(w)
        else:
            runs.append([w])
    return runs


def _is_numeric(w: Word) -> bool:
    return parse_number(w.text) is not None


def _rotated_words(chars: list[dict], header_top: float, header_bottom: float) -> list[Word]:
    """Caracteres não 'upright' → palavras verticais, lidas na direção da rotação."""
    rot = [c for c in chars if not c.get("upright", True) and header_top - 1 <= c["top"] <= header_bottom + 1]
    if not rot:
        return []
    groups = _cluster_1d([(c["x0"] + c["x1"]) / 2 for c in rot], 3.0)
    out: list[Word] = []
    for g in groups:
        cs = [rot[i] for i in g]
        m = cs[0].get("matrix") or (1, 0, 0, 1, 0, 0)
        # rotação anti-horária (lê de baixo para cima) quando b > 0; horária lê de cima para baixo
        cs.sort(key=lambda c: c["top"], reverse=(m[1] > 0))
        text = "".join(c["text"] for c in cs).strip()
        if len(text) >= 2:
            out.append(Word(text, min(c["x0"] for c in cs), max(c["x1"] for c in cs),
                            min(c["top"] for c in cs), max(c["bottom"] for c in cs)))
    return out


def reconstruct_table(page, bbox: tuple[float, float, float, float], page_no: int | None = None
                      ) -> tuple[TechnicalTable | None, list[str]]:
    """Tabela reconstruída pela geometria, ou (None, motivos) quando a região não tem
    estrutura tabular suficiente. `page` é uma página do pdfplumber."""
    warnings: list[str] = []
    px0, ptop, px1, pbottom = page.bbox
    x0, top, x1, bottom = (max(bbox[0], px0), max(bbox[1], ptop), min(bbox[2], px1), min(bbox[3], pbottom))
    if x1 - x0 < 20 or bottom - top < 10:
        return None, ["regiao pequena demais"]
    crop = page.within_bbox((x0, top, x1, bottom))
    raw_words = crop.extract_words(x_tolerance=1.5, y_tolerance=2, keep_blank_chars=False, extra_attrs=["upright"])
    upright = [Word(w["text"], w["x0"], w["x1"], w["top"], w["bottom"]) for w in raw_words if w.get("upright", True)]
    if len(upright) < 6:
        return None, ["poucas palavras na regiao"]

    med_h = statistics.median(w.h for w in upright)
    # O detector as vezes corta o rotulo de grupo que fica logo acima da caixa
    # ("LITROS POR HECTARE" a uma linha do topo). Palavras ate 1,8 linha acima,
    # dentro da largura da tabela, entram na zona de cabecalho.
    ext_top = max(ptop, top - 1.8 * med_h)
    if ext_top < top:
        above = page.within_bbox((x0, ext_top, x1, top)).extract_words(x_tolerance=1.5, y_tolerance=2, extra_attrs=["upright"])
        upright += [Word(w["text"], w["x0"], w["x1"], w["top"], w["bottom"]) for w in above
                    if w.get("upright", True) and w["bottom"] <= top + 0.5]
        top = ext_top
    line_tol = max(1.5, 0.45 * med_h)
    lines = _lines(upright, line_tol)

    # ── linhas de dados ──────────────────────────────────────
    def n_num(line: list[Word]) -> int:
        return sum(1 for w in line if _is_numeric(w))

    numeric_idx = [i for i, ln in enumerate(lines) if n_num(ln) >= 2 and n_num(ln) >= 0.5 * len(ln)]
    if len(numeric_idx) < 1:
        return None, ["nenhuma linha numerica"]
    counts = [n_num(lines[i]) for i in numeric_idx]
    modal = statistics.mode(counts)
    # linhas numericas iniciais com assinatura diferente da moda sao cabecalho
    # (ex.: "4 5 6 7 8 9 10 12 14 16 18 20 25" acima das linhas de vazao)
    data_idx: list[int] = []
    started = False
    numeric_set = set(numeric_idx)
    for i in numeric_idx:
        c = n_num(lines[i])
        if not started:
            all_int = all(isinstance(parse_number(w.text), int) for w in lines[i] if _is_numeric(w))
            next_non_numeric = (i + 1 < len(lines)) and (i + 1 not in numeric_set)
            # antes dos dados, uma linha numerica com assinatura diferente da moda e
            # so de inteiros (velocidades, pressoes), ou seguida de linha de texto
            # ("GOTAS MF MF"), e cabecalho — nao linha de dados
            if c != modal and (all_int or next_non_numeric):
                continue
            started = True
        data_idx.append(i)
    if len(data_idx) < 2 or len(data_idx) < 0.4 * len(lines):
        # matriz de texto com uma linha numerica solta nao e tabela numerica:
        # a reconstrucao geometrica nao a representa melhor que o detector padrao
        return None, ["poucas linhas de dados para reconstruir"]
    first_data_top = min(w.top for w in lines[data_idx[0]])
    data_lines = [lines[i] for i in data_idx]

    # ── colunas a partir das linhas de dados ──────────────────
    # Uma coluna de dados precisa de suporte: número na maioria das linhas, ou o
    # mesmo tipo de token curto de texto em quase todas (classificação "UG").
    # Rótulos de grupo (código, série, malha) aparecem só em algumas linhas e
    # ficam de fora — vão para a coluna de rótulo.
    all_words = [w for ln in data_lines for w in ln]
    col_tol = max(3.0, 0.6 * med_h)
    clusters = _cluster_1d([w.xc for w in all_words], col_tol)
    columns: list[Column] = []
    unassigned: list[Word] = []
    n_lines = len(data_lines)
    for g in clusters:
        ws = [all_words[i] for i in g]
        num_support = len({round(w.yc, 1) for w in ws if _is_numeric(w)})
        txt_support = len({round(w.yc, 1) for w in ws if not _is_numeric(w)})
        if num_support >= 0.5 * n_lines or txt_support >= 0.8 * n_lines:
            columns.append(Column(statistics.median(w.xc for w in ws), min(w.x0 for w in ws), max(w.x1 for w in ws)))
        else:
            unassigned.extend(ws)
    columns.sort(key=lambda c: c.center)
    if len(columns) < 2:
        return None, ["menos de duas colunas recorrentes"]
    pitches = [b.center - a.center for a, b in zip(columns, columns[1:])]
    half_pitch = 0.5 * statistics.median(pitches)
    column_ids = {id(c) for c in columns}

    def nearest_col(w: Word) -> Column | None:
        best = min(columns, key=lambda c: abs(c.center - w.xc))
        return best if abs(best.center - w.xc) <= max(half_pitch, col_tol) else None

    # ── colunas de rótulo (palavras fora das linhas de dados, abaixo do cabeçalho) ──
    pool = [w for i, ln in enumerate(lines) if i not in data_idx for w in ln if w.top >= first_data_top - line_tol]
    pool += unassigned
    label_cols: list[Column] = []
    if pool:
        # agrupa por sobreposição horizontal (intervalos que se tocam formam uma coluna)
        pool.sort(key=lambda w: w.x0)
        groups: list[list[Word]] = []
        for w in pool:
            if groups and w.x0 <= max(x.x1 for x in groups[-1]) + 3.0:
                groups[-1].append(w)
            else:
                groups.append([w])
        for ws in groups:
            lc = Column(statistics.median(w.xc for w in ws), min(w.x0 for w in ws), max(w.x1 for w in ws), kind="label")
            # regua horizontal que cruza a coluna = fronteira de grupo
            edges = sorted({round(e["top"], 1) for e in page.edges
                            if e.get("orientation") == "h" and top - 1 <= e["top"] <= bottom + 1
                            and e["x0"] <= lc.x0 + 1 and e["x1"] >= lc.x1 - 1 and e["top"] >= first_data_top - line_tol})
            bounds = sorted({first_data_top - line_tol, bottom, *edges})
            for a, b in zip(bounds, bounds[1:]):
                inside = [w for w in ws if a <= w.yc < b]
                if inside:
                    inside.sort(key=lambda w: (round(w.top, 0), w.x0))
                    lc.spans.append((a, b, " ".join(w.text for w in inside)))
            if not edges:
                warnings.append("coluna de rotulo sem regua horizontal: rotulo so na linha mais proxima")
                lc.spans = []
                for w in sorted(ws, key=lambda w: w.top):
                    lc.spans.append((w.yc - line_tol, w.yc + line_tol, w.text))
            label_cols.append(lc)
    # rótulos ficam onde estão no eixo x
    ordered: list[Column] = sorted(columns + label_cols, key=lambda c: c.center)

    # ── cabeçalho ─────────────────────────────────────────────
    header_words = [w for i, ln in enumerate(lines) for w in ln if i not in data_idx and w.bottom <= first_data_top + 0.5]
    header_words += _rotated_words(crop.chars, top, first_data_top)
    header_lines = _lines(header_words, max(2.0, 0.6 * med_h))
    med_cw = statistics.median((w.x1 - w.x0) / max(len(w.text), 1) for w in upright)

    def cols_covered(a: float, b: float) -> list[Column]:
        return [c for c in ordered if a - 0.6 * med_cw <= c.center <= b + 0.6 * med_cw]

    h_edges = [e for e in page.edges if e.get("orientation") == "h" and top - 1 <= e["top"] <= first_data_top + 1
               and e["x1"] - e["x0"] > 2 * half_pitch]
    for hl in header_lines:
        for run in _runs(hl, 2.5 * med_cw):
            text = " ".join(w.text for w in run)
            r_x0, r_x1 = run[0].x0, run[-1].x1
            r_bottom = max(w.bottom for w in run)
            covered = cols_covered(r_x0, r_x1)
            # caixa de grupo: régua logo abaixo da corrida que a contém e cobre 2+ colunas
            # caixa de grupo: régua logo abaixo da corrida, que a contém, cobre 2+ colunas
            # e ainda tem pelo menos uma linha de cabeçalho abaixo dela (não é a régua dos dados)
            box = [e for e in h_edges if e["x0"] <= r_x0 + 1 and e["x1"] >= r_x1 - 1
                   and r_bottom - 1 <= e["top"] <= r_bottom + 1.5 * med_h
                   and e["top"] < first_data_top - med_h
                   and len(cols_covered(e["x0"], e["x1"])) >= 2]
            box_cols = cols_covered(min(box, key=lambda e: e["top"])["x0"], min(box, key=lambda e: e["top"])["x1"]) if box else []
            if len(covered) >= 2 and (len(run) < len(covered) or len(run) < len(box_cols)):
                # rótulo de grupo: a caixa diz até onde ele vale
                for c in (box_cols or covered):
                    c.group_parts.append(text)
            else:
                for w in run:
                    c = min(ordered, key=lambda c: abs(c.center - w.xc))
                    if abs(c.center - w.xc) <= max(2 * half_pitch, (c.x1 - c.x0) / 2 + col_tol):
                        c.header_parts.append(w.text)

    # ── monta a tabela ────────────────────────────────────────
    labels: list[str] = []
    headers: list[str] = []
    units: dict[str, str] = {}
    groups: list[str | None] = []
    seen: dict[str, int] = {}
    for i, c in enumerate(ordered):
        label = " ".join(c.header_parts).strip()
        group = " ".join(dict.fromkeys(c.group_parts)).strip() or None
        unit = None
        key = None
        if group:
            gl = _unaccent(group).lower()
            for rx, u in _SPELLED_UNITS:
                if rx.search(gl):
                    unit = u
                    break
            if unit:
                sub = re.sub(r"[^A-Za-z0-9]+", "", re.sub(r"\b(km/h|bar|psi|kpa)\b", "", _unaccent(label), flags=re.I)) or f"c{i}"
                key = f"{re.sub(r'[^A-Za-z0-9]+', '_', unit)}@{sub}"
        if key is None:
            key = _header_key(label, i)
            unit = _unit_of(label) if label else None
        if key in seen:
            seen[key] += 1
            key = f"{key}_{seen[key]}"
        else:
            seen[key] = 1
        headers.append(key)
        labels.append(label)
        groups.append(group)
        if unit:
            units[key] = unit

    rows: list[list[Any]] = []
    collisions = 0
    for ln in data_lines:
        cells: list[Any] = [None] * len(ordered)
        yc = statistics.median(w.yc for w in ln)
        for w in ln:
            c = nearest_col(w)
            if c is None or id(c) not in column_ids:
                continue
            j = ordered.index(c)
            if cells[j] is not None:
                cells[j] = None       # duas palavras na mesma célula: ambíguo → nulo
                collisions += 1
                continue
            n = parse_number(w.text)
            cells[j] = n if n is not None else w.text
        for lc in label_cols:
            j = ordered.index(lc)
            for a, b, text in lc.spans:
                if a <= yc < b:
                    cells[j] = text
                    break
        rows.append(cells)
    if collisions:
        warnings.append(f"{collisions} celula(s) ambigua(s) (duas palavras na mesma coluna) deixadas nulas")

    table = TechnicalTable(headers=headers, rows=rows, units=units, page=page_no, labels=labels)
    table.groups = groups
    table.notes.append("reconstruction: spatial")
    table.notes.extend(warnings)
    return table, warnings
