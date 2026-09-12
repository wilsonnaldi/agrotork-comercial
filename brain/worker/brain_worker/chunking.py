"""Chunking determinístico.

Regras (docs/brain/fase-2-lote-b.md §5):

  · a unidade é a PÁGINA: um chunk nunca atravessa página; `page_from ==
    page_to` sempre;
  · dentro da página, o texto vira blocos: título (linha curta em caixa
    alta ou numerada) ou parágrafo (separado por linha em branco);
  · parágrafos consecutivos sob o mesmo título se juntam até TARGET
    caracteres; um parágrafo maior que MAX é fatiado em frases, com OVERLAP
    caracteres repetidos entre fatias (só aí há repetição);
  · tabela é chunk próprio (`table`/`price_table`), nunca entra em chunk
    de texto, nunca é fatiada;
  · `heading_path` é a pilha de títulos vigente na página;
  · `ordinal` é sequencial no documento, na ordem página → bloco.

Mesmo texto + mesma configuração → mesmos chunks, byte a byte. Não há
aleatoriedade, relógio nem dependência de ambiente.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from .codes import extract_codes
from .tables import TechnicalTable

TARGET = 900      # tamanho alvo de um chunk de texto (caracteres)
MAX = 1400        # acima disto, fatiar
MIN_MERGE = 200   # parágrafo menor que isto se junta ao próximo
OVERLAP = 120     # repetição entre fatias de um parágrafo longo
CONFIG = {"target": TARGET, "max": MAX, "min_merge": MIN_MERGE, "overlap": OVERLAP, "unit": "page",
          "headings": "page-reset+runs", "fragments": "aggregate<min_merge"}

_HEADING = re.compile(r"^(?:\d+(?:\.\d+)*\s*[-–.)]?\s+)?[A-ZÁÉÍÓÚÂÊÔÃÕÇ0-9][A-ZÁÉÍÓÚÂÊÔÃÕÇ0-9 \-–/·,()]{2,78}$")
_SENTENCE = re.compile(r"(?<=[.!?;])\s+")


@dataclass
class PageInput:
    page_no: int
    text: str
    tables: list[TechnicalTable] = field(default_factory=list)


@dataclass
class Chunk:
    ordinal: int
    kind: str                 # text | heading | table | price_table | list
    page: int
    heading_path: list[str]
    content: str
    table_data: dict[str, Any] | None = None
    codes: list[str] = field(default_factory=list)

    def as_row(self) -> dict[str, Any]:
        return {
            "ordinal": self.ordinal, "kind": self.kind, "page_from": self.page, "page_to": self.page,
            "heading_path": self.heading_path, "content": self.content,
            "table_data": self.table_data, "codes": self.codes,
        }


def is_heading(line: str) -> bool:
    s = line.strip()
    if not s or len(s) > 80 or s.endswith((".", ",", ";")):
        return False
    letters = [c for c in s if c.isalpha()]
    digits = [c for c in s if c.isdigit()]
    if len(letters) < 3:
        return False
    # arte lateral / texto em curva chega como letras soltas ("Õ E S", "O S C U"):
    # nao e titulo, e nao pode contaminar o heading_path
    tokens = s.split()
    if len(tokens) >= 2 and sum(1 for t in tokens if len(t) == 1) > 0.5 * len(tokens):
        return False
    # linha de tabela ("PS983CAP SOL-CV 03 UG 2,76 40 1,15 115") nao e titulo
    if len(digits) > 0.25 * (len(letters) + len(digits)):
        return False
    return bool(_HEADING.match(s)) and all(c.isupper() for c in letters)


def _blocks(text: str) -> list[tuple[str, str]]:
    """Texto da página → [(tipo, texto)], tipo ∈ {heading, para, list}."""
    out: list[tuple[str, str]] = []
    buf: list[str] = []

    def flush():
        if buf:
            joined = " ".join(l.strip() for l in buf if l.strip())
            if joined:
                kind = "list" if all(re.match(r"^\s*([-•*·]|\d+[.)])\s+", l) for l in buf if l.strip()) else "para"
                out.append((kind, joined))
            buf.clear()

    for line in text.replace("\r\n", "\n").split("\n"):
        if not line.strip():
            flush()
            continue
        if is_heading(line):
            flush()
            out.append(("heading", line.strip()))
            continue
        buf.append(line)
    flush()
    return out


def _split_long(text: str) -> list[str]:
    """Parágrafo > MAX → fatias por frase com OVERLAP; nunca corta palavra."""
    if len(text) <= MAX:
        return [text]
    sentences = _SENTENCE.split(text)
    pieces: list[str] = []
    cur = ""
    for s in sentences:
        if cur and len(cur) + 1 + len(s) > TARGET:
            pieces.append(cur)
            # overlap: últimos OVERLAP caracteres, a partir de uma fronteira de palavra
            tail = cur[-OVERLAP:]
            cut = tail.find(" ")
            cur = (tail[cut + 1:] + " " if cut >= 0 else "") + s
        else:
            cur = f"{cur} {s}" if cur else s
    if cur:
        pieces.append(cur)
    # frase única maior que MAX: corte duro em palavra
    final: list[str] = []
    for p in pieces:
        while len(p) > MAX:
            cut = p.rfind(" ", 0, MAX)
            cut = cut if cut > 0 else MAX
            final.append(p[:cut])
            p = p[max(cut - OVERLAP, 0):].lstrip()
        final.append(p)
    return final


def chunk_pages(pages: list[PageInput], price_table_hint: bool = False, profile: str | None = None) -> list[Chunk]:
    """Páginas → chunks, determinístico.

    Títulos: a pilha é zerada a cada página (catálogo: cada página é uma
    unidade; um título só atravessaria página por adivinhação). Títulos
    consecutivos formam uma CORRIDA e entram inteiros na pilha — "MAGNO ULTRA
    GROSSA" + "CONE VAZIO" não se apagam um ao outro. A primeira corrida da
    página é o título da página (nível 1) e vira um chunk `heading` próprio;
    as corridas seguintes são a seção vigente (nível 2), substituída pela
    próxima. Fragmentos curtos (cotas, rótulos de desenho) se acumulam até
    MIN_MERGE caracteres antes de virar chunk, mesmo atravessando títulos.
    """
    chunks: list[Chunk] = []
    ordinal = 0
    heading_path: list[str] = []

    seen_in_page: set[tuple[int, str]] = set()

    def emit(kind: str, page: int, content: str, table_data=None, codes=None, path=None):
        nonlocal ordinal
        content = content.strip()
        if not content:
            return
        # O mesmo conteudo duas vezes NA MESMA pagina e duplicata (o banco
        # recusa); em paginas diferentes sao dois chunks, cada um com a sua
        # proveniencia.
        key = (page, content)
        if key in seen_in_page:
            return
        seen_in_page.add(key)
        chunks.append(Chunk(ordinal, kind, page, list(path if path is not None else heading_path), content, table_data,
                            codes if codes is not None else extract_codes(content, profile)))
        ordinal += 1

    for page in sorted(pages, key=lambda p: p.page_no):
        heading_path = []
        title_run: list[str] = []      # primeira corrida de títulos da página (nível 1)
        section_run: list[str] = []    # corrida vigente (nível 2)
        run_open = False               # ainda dentro de uma corrida de títulos
        title_closed = False           # a corrida de título da página já terminou
        body_seen = False
        pending: list[str] = []
        pending_kind = "text"
        pending_path: list[str] = []

        def current_path() -> list[str]:
            return title_run[:10] + section_run[:4]

        def flush_pending(force: bool = False):
            nonlocal pending, pending_kind, pending_path
            if not pending:
                return
            if not force and sum(len(p) for p in pending) < MIN_MERGE:
                return                  # fragmento curto: espera juntar com o proximo
            emit(pending_kind, page.page_no, "\n".join(pending), path=pending_path)
            pending = []
            pending_kind = "text"
            pending_path = []

        def close_run():
            nonlocal run_open, title_closed
            if run_open and not title_closed:
                # a primeira corrida da pagina e o titulo da pagina: fica pesquisavel por si
                if title_run:
                    emit("heading", page.page_no, "\n".join(title_run), path=list(title_run))
                title_closed = True
            run_open = False

        for kind, text in _blocks(page.text):
            if kind == "heading":
                if not run_open:
                    run_open = True
                    flush_pending()
                    if title_closed:
                        section_run = []          # nova secao substitui a anterior
                target = section_run if title_closed else title_run
                if target and target[-1] == text:
                    continue
                if len(target) < (10 if target is title_run else 4):
                    target.append(text)
                continue
            if run_open:
                close_run()
            body_seen = True
            heading_path = current_path()
            if kind == "list":
                flush_pending(force=True)
                for piece in _split_long(text):
                    emit("list", page.page_no, piece)
                continue
            for piece in _split_long(text):
                if pending and sum(len(p) for p in pending) + len(piece) > TARGET:
                    flush_pending(force=True)
                if not pending:
                    pending_path = list(heading_path)
                pending.append(piece)
                if sum(len(p) for p in pending) >= MIN_MERGE and len(piece) >= TARGET:
                    flush_pending(force=True)
        if run_open:
            close_run()
        flush_pending(force=True)

        heading_path = current_path()
        for table in page.tables:
            if not table.is_meaningful:
                continue
            text = table.render_text()
            kind = "price_table" if (price_table_hint or _looks_like_prices(table)) else "table"
            emit(kind, page.page_no, text, table.table_data(), table.codes(profile))
    return chunks


_PRICE_HEADER = re.compile(r"(?<![a-z0-9])(preco|preço|precos|preços|valor|valores|a vista|à vista|faturado|r\$|brl)(?![a-z0-9])", re.I)


def _looks_like_prices(table: TechnicalTable) -> bool:
    """So com evidencia real de preco: unidade BRL, R$ ou coluna cujo nome e a
    PALAVRA INTEIRA preco/valor/a vista/faturado. "valoriza" nao e "valor"."""
    if "BRL" in table.units.values():
        return True
    for h in (table.labels or table.headers):
        if _PRICE_HEADER.search(h.replace("_", " ")):
            return True
    return False
