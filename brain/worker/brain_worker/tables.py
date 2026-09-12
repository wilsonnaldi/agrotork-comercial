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
        }

    def render_text(self) -> str:
        """Cabecalho como esta no documento, depois uma linha por registro:
        'Código Série ... Vazão (L/min) ...' / 'MJ981CAP MUG-CV 02 UG 2,76 bar 40 psi 0,77 L/min'.
        O cabecalho entra no texto pesquisavel de proposito: "vazao" so existe ali."""
        lines = [" ".join(h for h in (self.labels or self.headers) if h)]
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

    def codes(self) -> list[str]:
        return extract_codes(self.render_text())


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
