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

from .codes import extract_codes, normalize_code

# "2,76" → 2.76; "1.234,56" → 1234.56; "40" → 40; "R$ 165.500,00" → 165500.0
_NUM = re.compile(r"^\s*(?:R\$\s*)?([+-]?\d{1,3}(?:\.\d{3})+|[+-]?\d+)(?:,(\d+))?\s*%?\s*$")
_NUM_DOT = re.compile(r"^\s*([+-]?\d+)\.(\d+)\s*$")   # já em ponto decimal (xlsx)
# Célula monetária com traço decorativo dos dois lados: "-R$ 21.550,00-". Sai de
# exportação de planilha que preenche o resto da célula com hífen. O traço da
# FRENTE só é decoração quando existe o de TRÁS e a célula traz R$ — número
# negativo de verdade é "R$ -21.550,00" ou "-21.550,00", e esses continuam
# negativos. Sem isto, a mesma tabela guarda "165500" numa célula e
# "-R$ 21.550,00-" (texto) na de baixo: duas representações do mesmo dado.
_MONEY_DASHED = re.compile(r"^\s*-\s*(R\$\s*[\d.,]+)\s*-\s*$", re.I)
_HAS_CURRENCY = re.compile(r"R\$", re.I)

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
    if (dashed := _MONEY_DASHED.match(s)):
        s = dashed.group(1)
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


def is_money(cell: Any) -> bool:
    """A célula é dinheiro? Só com marca de moeda no próprio texto ("R$ 9.502,00",
    "-R$ 999,00-"). Número solto NÃO é dinheiro: 1580 pode ser um modelo de bateria."""
    if cell is None or isinstance(cell, (int, float, bool)):
        return False
    s = str(cell)
    return bool(_HAS_CURRENCY.search(s)) and parse_number(s) is not None


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
    depois qualquer token inteiro ("L/min", "psi"). 'm' de 'mínimo' não é metro: só token inteiro.

    Unidade de UMA letra ("A", "V", "W", "G", "M") só vale DENTRO de parênteses:
    solta no meio da frase ela quase sempre é palavra — o "à vista" de
    "Pgto à vista" virava ampere e o preço saía "159000 A"."""
    h = _unaccent(header).lower()
    entre_parenteses = re.findall(r"\(([^)]*)\)", h)
    for cand in entre_parenteses:
        for token in re.findall(r"(?<![a-z0-9])([a-z$%/]+)(?![a-z0-9])", cand):
            if token in _UNIT_HINTS:
                return _UNIT_HINTS[token]
    for token in re.findall(r"(?<![a-z0-9])([a-z$%/]+)(?![a-z0-9])", h):
        if len(token) >= 2 and token in _UNIT_HINTS:
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
    title: str | None = None                 # linha de título acima do cabeçalho, quando houver
    groups: list[str | None] = field(default_factory=list)   # rótulo de grupo acima de cada coluna (ou None)
    # Estado formal de qualidade, gravado no table_data (nunca derivado de `notes`):
    #   {"quality": "trusted" | "degraded", "fatal": bool, "issues": [...]}
    # `degraded` = ficou pelo menos um sinal FATAL (numero fundido, cabecalho
    # caido, linha engolida) que a reconstrucao espacial nao resolveu. Sinais
    # nao fatais (coluna sem nome, rotulo nao propagado) ficam registrados em
    # `issues`, mas a tabela continua `trusted`.
    audit: dict[str, Any] = field(default_factory=lambda: {"quality": "trusted", "fatal": False, "issues": []})

    def stamp_audit(self) -> dict[str, Any]:
        """Recalcula e grava o estado de qualidade a partir do auditor. Determinístico."""
        issues = audit_table(self)
        fatal = fatal_issues(issues)
        self.audit = {"quality": "degraded" if fatal else "trusted", "fatal": bool(fatal), "issues": issues}
        return self.audit

    @property
    def is_trusted(self) -> bool:
        return self.audit.get("quality") == "trusted" and not self.audit.get("fatal")

    @property
    def is_meaningful(self) -> bool:
        return len(self.headers) >= 2 and len(self.rows) >= 1

    def table_data(self) -> dict[str, Any]:
        return {
            "page": self.page,
            "title": self.title,
            "headers": self.headers,
            "labels": self.labels,
            "units": self.units,
            "rows": self.rows,
            "notes": self.notes,
            "groups": self.groups if any(self.groups) else [],
            "audit": {"quality": self.audit.get("quality", "trusted"), "fatal": bool(self.audit.get("fatal", False)),
                      "issues": list(self.audit.get("issues", []))},
        }

    def render_text(self) -> str:
        """Cabecalho como esta no documento, depois uma linha por registro:
        'Código Série ... Vazão (L/min) ...' / 'MJ981CAP MUG-CV 02 UG 2,76 bar 40 psi 0,77 L/min'.
        O cabecalho entra no texto pesquisavel de proposito: "vazao" so existe ali."""
        group_line = " ".join(dict.fromkeys(g for g in self.groups if g))
        lines = ([self.title] if self.title else []) \
            + ([group_line] if group_line else []) \
            + [" ".join(h for h in (self.labels or self.headers) if h)]
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
        """Códigos do texto da tabela MAIS o conteúdo de uma coluna que se
        declara de código ("COD", "CÓDIGO", "REF", "SKU").

        Numa coluna assim o código não precisa ser adivinhado por padrão: o
        documento já disse que aquilo é código. É o que resgata `46202G`,
        `863T026S` e `5538/2L1/94A`, que começam por dígito e por isso nenhum
        padrão genérico alcança sem inventar falso positivo em "4-20MAH"."""
        achados = set(extract_codes(self.render_text(), profile))
        for j, h in enumerate(self.labels or self.headers):
            if not _CODE_HEADER.fullmatch(_unaccent(str(h)).strip().lower()):
                continue
            for row in self.rows:
                if j >= len(row):
                    continue
                v = row[j]
                if v is None or isinstance(v, bool):
                    continue
                if isinstance(v, float) and v.is_integer():
                    v = int(v)
                bruto = str(v).strip()
                # rótulo de "não se aplica" não é código
                if not bruto or len(bruto) < 3 or bruto.upper() in {"X", "N/A", "NA", "-", "--"}:
                    continue
                if (code := normalize_code(bruto)):
                    achados.add(code)
        return sorted(achados)


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
    # Título acima do cabeçalho — padrão de tabela comercial: a primeira linha
    # traz só o nome do produto ("DRONE AGRAS T100 + 3 BAT + CARREGADOR C12000")
    # e o cabeçalho de verdade vem na segunda ("Pgto faturado / Pgto à vista").
    # Sem isto o nome do produto vira o cabeçalho, as colunas de preço ficam
    # `col_1`/`col_2`, e o valor deixa de dizer a que condição pertence.
    title: str | None = None
    if len(rows) >= 3:
        cheias_0 = [c for c in rows[0] if c]
        cheias_1 = [c for c in rows[1] if c]
        if len(cheias_0) == 1 and len(cheias_1) >= 2 \
                and all(parse_number(c) is None for c in rows[1]):
            title = cheias_0[0]
            rows = rows[1:]
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
    money_hits = [0] * width
    for r in rows[1:]:
        conv: list[Any] = []
        for i, c in enumerate(r):
            if is_money(c) and i < width:
                money_hits[i] += 1
            n = parse_number(c)
            conv.append(n if n is not None else (c if c != "" else None))
        body.append(conv)
    # A moeda quase nunca está no cabeçalho de uma tabela comercial — está em
    # cada célula ("R$ 9.502,00"). Uma coluna com marca de moeda no corpo é
    # coluna de dinheiro, e é isso que faz a tabela ser reconhecida como preço.
    for i, hits in enumerate(money_hits):
        if hits and headers[i] not in units:
            units[headers[i]] = "BRL"
    return TechnicalTable(headers=headers, rows=body, units=units, page=page,
                          labels=raw_headers, title=title)


def split_side_by_side(raw: list[list[Any]]) -> list[list[list[Any]]]:
    """Duas tabelas lado a lado que o detector devolveu como uma só.

    Tabela comercial impressa em duas colunas visuais ("T55 + C7000" à esquerda,
    "T55 + D8000" à direita) chega com uma COLUNA VAZIA no meio — a calha entre
    os dois blocos. Sem separar, o cabeçalho de um bloco vira coluna do outro e
    o preço da direita responde pergunta da esquerda.

    Só separa quando a divisão é inequívoca: coluna completamente vazia em TODAS
    as linhas, tabela larga (5+ colunas) e cada lado sobrando com 2+ colunas.
    Fora disso devolve a tabela inteira, como veio.
    """
    rows = [r for r in raw if r and any(_clean(c) for c in r)]
    if len(rows) < 2:
        return [raw]
    width = max(len(r) for r in rows)
    if width < 5:
        return [raw]
    rows = [list(r) + [""] * (width - len(r)) for r in rows]
    vazias = {j for j in range(width) if all(not _clean(r[j]) for r in rows)}
    if not vazias:
        return [raw]
    blocos: list[list[int]] = []
    atual: list[int] = []
    for j in range(width):
        if j in vazias:
            if atual:
                blocos.append(atual)
            atual = []
        else:
            atual.append(j)
    if atual:
        blocos.append(atual)
    blocos = [b for b in blocos if len(b) >= 2]
    if len(blocos) < 2:
        return [raw]
    return [[[r[j] for j in bloco] for r in rows] for bloco in blocos]


def split_stacked(raw: list[list[Any]]) -> list[tuple[int, list[list[Any]]]]:
    """Blocos empilhados na mesma aba ou região, separados por LINHA vazia.

    Uma planilha comercial costuma trazer vários blocos um embaixo do outro —
    "SISTEMA PARA BICOS HIDRÁULICOS" com seus itens, linha em branco,
    "SISTEMA PARA BICOS ROTATIVOS" com os dele. Lidos como uma tabela só, o
    título do primeiro fica valendo para as linhas do segundo e o cabeçalho
    repetido vira linha de dados: pergunta sobre um sistema responde com o
    outro.

    Devolve (índice da primeira linha do bloco no original, linhas do bloco).
    Conservador: só separa com 4+ linhas úteis, bloco de 2+ linhas e 2+ blocos.
    """
    if not raw:
        return [(0, raw)]
    cheia = [bool(r) and any(_clean(c) for c in r) for r in raw]
    if sum(cheia) < 4:
        return [(0, raw)]
    blocos: list[tuple[int, list[list[Any]]]] = []
    inicio: int | None = None
    for i, tem in enumerate(cheia):
        if tem and inicio is None:
            inicio = i
        elif not tem and inicio is not None:
            blocos.append((inicio, raw[inicio:i]))
            inicio = None
    if inicio is not None:
        blocos.append((inicio, raw[inicio:]))
    blocos = [b for b in blocos if len(b[1]) >= 2]
    if len(blocos) < 2:
        return [(0, raw)]
    return blocos


def build_tables(raw: list[list[Any]], page: int | None = None,
                 origin: str | None = None) -> list[TechnicalTable]:
    """Uma tabela por bloco: primeiro os empilhados, depois os lado a lado.
    `origin` ("aba 'Página1'") vira nota com o intervalo de linhas do bloco —
    é a proveniência que uma planilha tem no lugar de número de página."""
    out: list[TechnicalTable] = []
    for inicio, bloco in split_stacked(raw):
        for sub in split_side_by_side(bloco):
            t = build_table(sub, page=page)
            if t is None:
                continue
            if origin:
                t.notes.append(f"{origin}, linhas {inicio + 1}–{inicio + len(bloco)}")
            out.append(t)
    return out


# Cabecalho que DECLARA a coluna como de codigo. Palavra inteira, sem acento,
# em minuscula — "codigo do fabricante" tambem conta, "codificacao" nao.
_CODE_HEADER = re.compile(r"(cod|codigo|code|ref|referencia|sku|part|part_number|partnumber)"
                          r"([ _-](do|de|da)?[ _-]?(fabricante|produto|peca|item|barras))?")


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
    rotulos = [_unaccent(str(h)).strip().lower() for h in (t.labels or t.headers)]
    multi = 0
    header_rows = 0
    bad_width = 0
    for r in t.rows:
        if len(r) != width:
            bad_width += 1
        strs = [c for c in r if isinstance(c, str)]
        # dois números na mesma célula — soltos ("2,76 40") ou com moeda
        # ("-R$ 7.100,00--R$ 6.800,00-", duas colunas que viraram uma)
        multi += sum(1 for c in strs if _MULTI_NUM.match(c) or len(_HAS_CURRENCY.findall(c)) >= 2)
        tokens = [tok for c in strs for tok in c.split()]
        # linha sem nenhuma celula numerica, mas com unidade escrita ("km/h", "psi"):
        # e um cabecalho que o detector deixou cair no corpo
        if tokens and sum(1 for c in r if isinstance(c, (int, float))) == 0 \
                and any(_UNIT_TOKEN.match(tok) for tok in tokens):
            header_rows += 1
        # ou uma linha que REPETE o proprio cabecalho: duas tabelas coladas numa
        # so. Sem isto a segunda passa a ser lida sob o titulo da primeira.
        elif rotulos and sum(1 for j, c in enumerate(r)
                             if j < len(rotulos) and rotulos[j]
                             and isinstance(c, str) and _unaccent(c).strip().lower() == rotulos[j]) >= 2:
            header_rows += 1
    if multi:
        issues.append(f"{multi} celula(s) com numeros fundidos")
    if header_rows:
        issues.append(f"{header_rows} linha(s) de cabecalho caida(s) como dados")
    # cabecalho feito de numeros: a primeira linha de dados foi engolida como cabecalho
    rotulos_crus = list(t.labels or t.headers)
    numeric_labels = sum(1 for h in rotulos_crus if parse_number(h) is not None)
    if width and numeric_labels >= width / 2:
        issues.append(f"{numeric_labels} de {width} cabecalhos sao numeros (linha de dados engolida)")
    # ...e a versao que a contagem de numeros nao pega: cabecalho que carrega
    # DINHEIRO. Um cabecalho NOMEIA a coluna ("VALOR UNITARIO", "Pgto a
    # vista"); ele nunca E um preco. Quando "R$ 5.600,00" aparece como rotulo,
    # o que esta ali e uma linha de produto que a reconstrucao promoveu a
    # cabecalho — tipico de tabela comercial cujo cabecalho aparece uma vez so
    # e cujos blocos seguintes sao continuacao visual sem cabecalho proprio.
    # Basta UM: preco em rotulo nao acontece por acaso.
    #
    # O teste e o SIMBOLO, nao o parse: ha PDF que quebra "R$ 5.600,00" em
    # "R$ 5 .600,00", e um parse estrito deixaria passar justamente o caso que
    # motivou a regra.
    dinheiro_no_cabecalho = [h for h in rotulos_crus
                             if isinstance(h, str) and _HAS_CURRENCY.search(h)]
    if dinheiro_no_cabecalho:
        issues.append(f"{len(dinheiro_no_cabecalho)} cabecalho(s) com valor monetario "
                      f"(linha de dados engolida como cabecalho)")
    generic = sum(1 for h in t.headers if re.fullmatch(r"col_\d+(?:_\d+)?", h))
    if width and generic > width / 2:
        issues.append(f"{generic} de {width} colunas sem cabecalho")
    if bad_width:
        issues.append(f"{bad_width} linha(s) com largura diferente do cabecalho")
    # Dinheiro em coluna sem nome: o valor existe, mas não dá para dizer a QUE
    # condição pertence — à vista, faturado, cliente final. Preço sem condição
    # não é dado incompleto, é dado errado esperando para ser citado; por isso
    # é FATAL e a tabela fica `degraded`.
    anonimas = [h for h in t.headers
                if t.units.get(h) == "BRL" and re.fullmatch(r"col_\d+(?:_\d+)?", h)]
    if anonimas:
        issues.append(f"{len(anonimas)} coluna(s) com preco sem condicao (cabecalho generico)")
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


FATAL_MARKERS = ("fundidos", "caida", "engolida", "preco sem condicao")


def fatal_issues(issues: list[str]) -> list[str]:
    """Sinais que significam dado errado (nao so incompleto): numeros fundidos,
    cabecalho caido como dados, linha de dados engolida como cabecalho, preco
    que nao diz a que condicao pertence."""
    return [i for i in issues if any(m in i for m in FATAL_MARKERS)]
