"""Códigos de peça/modelo (MJ981CAP, T70P, DB1580, 4626215) no texto.

Espelha `brain.normalize_code()`: maiúsculas, sem espaço, sem acento. O
banco normaliza de novo ao gravar; aqui a normalização existe para o worker
deduplicar e para os testes serem legíveis.
"""
from __future__ import annotations

import re
import unicodedata

# Letras + dígitos (MJ981CAP, T70P, DB1580, C12000, MUG-CV02) ou número puro
# de 7 a 9 dígitos (código Arag 4626215, 466113200). Preço em reais costuma
# ter até 6 dígitos inteiros (165500) e fica de fora de propósito. Aceita
# hífen interno.
_CODE = re.compile(r"(?<![\w-])((?:[A-Z]{1,5}-?\d{2,7}[A-Z0-9-]*)|(?:\d{7,9})|(?:[A-Z]{2,4}-[A-Z]{2,3}\s?\d{1,3}))(?![\w-])")
# Palavras comuns que casam o padrão mas não são código.
_STOP = {"COVID19"}


def normalize_code(raw: str) -> str | None:
    s = unicodedata.normalize("NFKD", raw or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = re.sub(r"\s+", "", s).upper()
    return s or None


def extract_codes(text: str) -> list[str]:
    """Códigos distintos, normalizados, em ordem alfabética (determinismo)."""
    found: set[str] = set()
    for m in _CODE.finditer(text.upper()):
        code = normalize_code(m.group(1))
        if not code or code in _STOP:
            continue
        found.add(code)
    return sorted(found)
