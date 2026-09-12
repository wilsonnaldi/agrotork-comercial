"""Códigos de peça/modelo (MJ981CAP, MJ059/1, MUG-CV 02, T70P, DB1580, 4626215) no texto.

Espelha `brain.normalize_code()`: maiúsculas, sem espaço, sem acento. O
banco normaliza de novo ao gravar; aqui a normalização existe para o worker
deduplicar e para os testes serem legíveis. A forma original fica no
conteúdo/tabela; só `codes` recebe a forma normalizada.

Padrões genéricos (qualquer fabricante):
  · letras + dígitos, com hífen e sufixo "/n" opcionais: MJ981CAP, MJ059/1,
    T70P, DB1580, C12000, MUG-CV02;
  · série com espaço antes do número: "MUG-CV 02", "MAG CH 0.5" → MUG-CV02;
  · número puro de 7 a 9 dígitos (Arag 4626215, 466113200). Preço em reais
    tem até 6 dígitos inteiros e fica de fora de propósito.

Perfis de documento (`profile`) acrescentam padrões próprios de uma família
sem tocar nos genéricos. `magnojet_catalog`: linha de filtros e acessórios
"M 714", "M 691/1", "M 691/1A" — uma letra, espaço, 3–4 dígitos, sufixo
"/n[letra]" opcional. Só a letra M: "A 100" em prosa não é código.
"""
from __future__ import annotations

import re
import unicodedata

_GENERIC = [
    # letras + digitos (+ sufixo alfanumerico) (+ /n[letra])
    re.compile(r"(?<![A-Z0-9/-])([A-Z]{1,5}-?\d{2,7}[A-Z0-9-]*(?:/\d{1,3}[A-Z]?)?)(?![A-Z0-9/-])"),
    # serie + espaco + numero curto: MUG-CV 02, SOL-CV 03, MAG CH 0.5
    re.compile(r"(?<![A-Z0-9/-])([A-Z]{2,4}-[A-Z]{2,3}\s?\d{1,3}(?:[.,]\d)?)(?![A-Z0-9/-])"),
    re.compile(r"(?<![A-Z0-9/-])([A-Z]{3,4}\s[A-Z]{2,3}\s\d{1,2}(?:[.,]\d)?)(?![A-Z0-9/-])"),
    # numero puro de 7 a 9 digitos
    re.compile(r"(?<![\w-])(\d{7,9})(?![\w-])"),
]

_PROFILES: dict[str, list[re.Pattern[str]]] = {
    "magnojet_catalog": [
        re.compile(r"(?<![A-Z0-9/-])(M\s\d{3,4}(?:/\d{1,2}[A-Z]?)?)(?![A-Z0-9/-])"),
    ],
}

# Palavras comuns que casam o padrão mas não são código.
_STOP = {"COVID19"}


def normalize_code(raw: str) -> str | None:
    s = unicodedata.normalize("NFKD", raw or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = re.sub(r"\s+", "", s).upper()
    return s or None


def code_patterns(profile: str | None = None) -> list[re.Pattern[str]]:
    return _GENERIC + _PROFILES.get(profile or "", [])


def extract_codes(text: str, profile: str | None = None) -> list[str]:
    """Códigos distintos, normalizados, em ordem alfabética (determinismo).
    A pontuação ao redor não faz parte do código: "MJ983CAP?" e "MJ981CAP," rendem o código limpo."""
    up = text.upper()
    found: set[str] = set()
    for rx in code_patterns(profile):
        for m in rx.finditer(up):
            code = normalize_code(m.group(1))
            if not code or code in _STOP:
                continue
            found.add(code)
    return sorted(found)


def known_profiles() -> list[str]:
    return sorted(_PROFILES)
