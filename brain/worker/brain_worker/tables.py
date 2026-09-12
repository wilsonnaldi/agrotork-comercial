"""Tabela técnica → `table_data` (JSONB) + texto pesquisável.

Regra do Lote A (docs/brain/fase-2-lote-a.md §8): tabela nunca vira só
texto corrido. `table_data` guarda cabeçalhos, unidades e linhas com NÚMEROS
numéricos; `content` guarda a mesma tabela renderizada linha a linha para
FTS/trigram. Uma tabela nunca atravessa página nem se mistura com outra.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from typing import Any

from .codes import extract_codes

# "2,76" → 2.76; "1.234,56" → 1234.56; "40" → 40; "R$ 165.500,00" → 165500.0
_NUM = re.compile(r"^\s*(?:R\$\s*)?([+-]?\d{1,3}(?:\.\d{3})+|[+-]?\d+)(?:,(\d+))?\s*%?\s*$")
_NUM_DOT = re.compile(r"^\s*([+-]?\d+)\.(\d+)\s*$")   # já em ponto decimal (xlsx)

_UNIT_HINTS = {
    "bar": "bar", "psi": "psi", "kpa": "kPa", "l/min": "L/min", "l/ha": "L/ha",
    "km/h": "km/h", "ml": "mL", "mm": "mm", "cm": "cm", "m": "m", "kg": "kg", "g": "g",
    "v": "V", "a": "A", "w": "W", "ma": "mA", "r$": "BRL", "brl": "BRL", "%": "%",
}


def parse_number(cell: Any) -> int | float | None:
    """Número pt-BR (vírgula decimal, ponto de milhar) ou já numérico. None se não for número."""
    if isinstance(cell, bool):
        return None
    if isinstance(cell, (int, float)):
        return cell
    if cell is None:
        return None
    s = str(cell).strip()
    m = _NUM.match(s)
    if m:
        inteiro = m.group(1).replace(".", "")
        if m.group(2) is not None:
            return float(f"{inteiro}.{m.group(2)}")
        return int(inteiro)
    m = _NUM_DOT.match(s)
    if m:
        return float(s)
    return None


def _clean(cell: Any) -> str:
    if cell is None:
        return ""
    return re.sub(r"\s+", " ", str(cell)).strip()


def _unaccent(s: str) -> str:
    return "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))


def _header_key(h: str, i: int) -> str:
    key = re.sub(r"[^A-Za-z0-9@/]+", "_", _unaccent(h.strip())).strip("_")
    return key or f"col_{i}"


def _unit_of(header: str) -> str | None:
    """Unidade declarada no cabeçalho: prefere o que está entre parênteses ("Pressão (bar)"),
    depois qualquer token inteiro ("L/min", "psi"). 'm' de 'mínimo' não é metro: só token inteiro."""
    h = _unaccent(header).lower()
    candidates = re.findall(r"\(([^)]*)\)", h) or [h]
    for cand in candidates + [h]:
        for token in re.findall(r"(?<![a-z0-9])([a-z$%/]+)(?![a-z0-9])", cand):
            if token in _UNIT_HINTS:
                return _UNIT_HINTS[token]
    return None


@dataclass
class TechnicalTable:
    headers: list[str]                       # chaves estáveis (sem acento/espaço)
    rows: list[list[Any]]
    units: dict[str, str] = field(default_factory=dict)
    page: int | None = None
    notes: list[str] = field(default_factory=list)
    labels: list[str] = field(default_factory=list)   # cabeçalhos como estão no documento
    groups: list[str | None] = field(default_factory=list)   # rótulo de grupo acima de cada coluna (ou None)

    @property
    def is_meaningful(self) -> bool:
        return len(self.headers) >= 2 and len(self.rows) >= 1

    def table_data(self) -> dict[str, Any]:
        return {
            "page": self.page,
            "headers": self.headers,
            "labels": self.labels,
            "units": self.units,
            "rows": self.rows,
            "notes": self.notes,
            "groups": self.groups if any(self.groups) else [],
        }

    def render_text(self) -> str:
        """Cabecalho como esta no documento, depois uma linha por registro:
        'Código Série ... Vazão (L/min) ...' / 'MJ981CAP MUG-CV 02 UG 2,76 bar 40 psi 0,77 L/min'.
        O cabecalho entra no texto pesquisavel de proposito: "vazao" so existe ali."""
        group_line = " ".join(dict.fromkeys(g for g in self.groups if g))
        lines = ([group_line] if group_line else []) + [" ".join(h for h in (self.labels or self.headers) if h)]
        for row in self.rows:
            parts = []
            for h, v in zip(self.headers, row):
                if v is None or v == "":
                    continue
                if isinstance(v, float):
                    txt = f"{v:.4f}".rstrip("0").rstrip(".").replace(".", ",")
                elif isinstance(v, int):
                    txt = str(v)
                else:
                    txt = str(v)
                unit = self.units.get(h)
                parts.append(f"{txt} {unit}" if unit and unit != "BRL" else txt)
            lines.append(" ".join(parts))
        return "\n".join(lines)

    def codes(self, profile: str | None = None) -> list[str]:
        return extract_codes(self.render_text(), profile)


def build_table(raw: list[list[Any]], page: int | None = None) -> TechnicalTable | None:
    """Tabela crua (lista de linhas) → TechnicalTable. Primeira linha não vazia = cabeçalho.

    Linhas vazias saem; células numéricas viram número; cabeçalhos ganham
    chave estável e unidade quando o próprio cabeçalho a declara.
    """
    rows = [[_clean(c) for c in r] for r in raw if r and any(_clean(c) for c in r)]
    if len(rows) < 2:
        return None
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    raw_headers = rows[0]
    headers = [_header_key(h, i) for i, h in enumerate(raw_headers)]
    # cabeçalhos duplicados ganham sufixo — sem isso a linha vira ambígua
    seen: dict[str, int] = {}
    for i, h in enumerate(headers):
        if h in seen:
            seen[h] += 1
            headers[i] = f"{h}_{seen[h]}"
        else:
            seen[h] = 1
    units = {headers[i]: u for i, h in enumerate(raw_headers) if (u := _unit_of(h))}
    body: list[list[Any]] = []
    for r in rows[1:]:
        conv: list[Any] = []
        for c in r:
            n = parse_number(c)
            conv.append(n if n is not None else (c if c != "" else None))
        body.append(conv)
    return TechnicalTable(headers=headers, rows=body, units=units, page=page, labels=raw_headers)


# ── Auditor automático ─────────────────────────────────────────
_MULTI_NUM = re.compile(r"^\s*[\d.,]+(?:\s+[\d.,]+)+\s*$")
_UNIT_TOKEN = re.compile(r"^(km/h|bar|psi|kpa|l/min|l/ha|mm|cm|ml|%)$", re.I)


def audit_table(t: TechnicalTable) -> list[str]:
    """Sinais de que a tabela NÃO virou dado confiável. Lista vazia = passou.

    - célula com dois ou mais números onde deveria haver um valor;
    - linha de dados feita só de unidades/cabeçalho ("km/h km/h …");
    - coluna sem cabeçalho (col_N) quando a maioria das colunas não tem nome;
    - linhas com largura diferente do cabeçalho;
    - coluna de rótulo (texto) com valor só na primeira linha de um grupo
      (código não propagado).
    """
    issues: list[str] = []
    width = len(t.headers)
    multi = 0
    header_rows = 0
    bad_width = 0
    for r in t.rows:
        if len(r) != width:
            bad_width += 1
        strs = [c for c in r if isinstance(c, str)]
        multi += sum(1 for c in strs if _MULTI_NUM.match(c))
        tokens = [tok for c in strs for tok in c.split()]
        # linha sem nenhuma celula numerica, mas com unidade escrita ("km/h", "psi"):
        # e um cabecalho que o detector deixou cair no corpo
        if tokens and sum(1 for c in r if isinstance(c, (int, float))) == 0 \
                and any(_UNIT_TOKEN.match(tok) for tok in tokens):
            header_rows += 1
    if multi:
        issues.append(f"{multi} celula(s) com numeros fundidos")
    if header_rows:
        issues.append(f"{header_rows} linha(s) de cabecalho caida(s) como dados")
    # cabecalho feito de numeros: a primeira linha de dados foi engolida como cabecalho
    numeric_labels = sum(1 for h in (t.labels or t.headers) if parse_number(h) is not None)
    if width and numeric_labels >= width / 2:
        issues.append(f"{numeric_labels} de {width} cabecalhos sao numeros (linha de dados engolida)")
    generic = sum(1 for h in t.headers if re.fullmatch(r"col_\d+(?:_\d+)?", h))
    if width and generic > width / 2:
        issues.append(f"{generic} de {width} colunas sem cabecalho")
    if bad_width:
        issues.append(f"{bad_width} linha(s) com largura diferente do cabecalho")
    # propagação de rótulo: coluna de texto onde valores aparecem e somem
    for j in range(width):
        col = [r[j] if j < len(r) else None for r in t.rows]
        texts = [c for c in col if isinstance(c, str)]
        if len(texts) >= 1 and all(isinstance(c, str) or c is None for c in col) and any(c is None for c in col) \
                and len(texts) < len(col) and len(col) >= 2 and any(isinstance(c, (int, float)) for r in t.rows for c in r):
            # so e problema quando a mesma coluna carrega texto identificador (contem letra+digito)
            if any(re.search(r"[A-Za-z]", x) and re.search(r"\d", x) for x in texts):
                issues.append(f"coluna '{t.headers[j]}' com rotulo nao propagado ({len(col) - len(texts)} linha(s) sem valor)")
    return issues


FATAL_MARKERS = ("fundidos", "caida", "engolida")


def fatal_issues(issues: list[str]) -> list[str]:
    """Sinais que significam dado errado (nao so incompleto): numeros fundidos,
    cabecalho caido como dados, linha de dados engolida como cabecalho."""
    return [i for i in issues if any(m in i for m in FATAL_MARKERS)]
