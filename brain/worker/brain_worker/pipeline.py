"""arquivo → sha256 → versão → páginas → chunks → fechamento.

Uma ingestão = uma transação. Se qualquer passo falhar depois de
`ingestion_start`, o que entrou é descartado (rollback) e a falha é
registrada numa transação própria (`ingestion_fail`), para a trilha dizer
o que aconteceu.
"""
from __future__ import annotations

import hashlib
import json
import socket
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import PIPELINE_VERSION
from .chunking import CONFIG as CHUNK_CONFIG
from .chunking import Chunk, PageInput, chunk_pages
from .db import BrainDb
from .extract import Extraction, extract, mime_for, sniff_ok


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


@dataclass
class Plan:
    """Tudo que o worker vai gravar, ANTES de gravar. Serve para --dry-run e para os testes."""
    sha256: str
    mime: str
    size: int
    extraction: Extraction
    chunks: list[Chunk]
    metrics: dict[str, Any] = field(default_factory=dict)

    def summary(self) -> dict[str, Any]:
        return {
            "sha256": self.sha256, "mime": self.mime, "size": self.size,
            "method": self.extraction.method, "parser": self.extraction.parser,
            "needs_ocr": self.extraction.needs_ocr, "text_ratio": self.extraction.text_ratio,
            "pages": self.extraction.pages_total, "chunks": len(self.chunks),
            "tables": sum(1 for c in self.chunks if c.kind in ("table", "price_table")),
            "warnings": list(self.extraction.warnings) + [w for p in self.extraction.pages for w in p.warnings],
            "pipeline_version": PIPELINE_VERSION, "chunk_config": CHUNK_CONFIG,
        }


def plan(path: Path, ocr: str = "auto", price_table: bool = False) -> Plan:
    if not path.is_file():
        raise FileNotFoundError(str(path))
    mime = mime_for(path)
    if not sniff_ok(path):
        raise ValueError(f"{path.name}: conteudo nao bate com a extensao")
    t0 = time.perf_counter()
    ext = extract(path, ocr=ocr)
    t1 = time.perf_counter()
    chunks = chunk_pages([PageInput(p.page_no, p.text, p.tables) for p in ext.pages], price_table_hint=price_table)
    t2 = time.perf_counter()
    return Plan(sha256_of(path), mime, path.stat().st_size, ext, chunks,
                {"extract_ms": round((t1 - t0) * 1000), "chunk_ms": round((t2 - t1) * 1000)})


@dataclass
class Result:
    version_id: Any
    ingestion_id: Any
    status: str
    pages: int
    chunks: int
    tables: int
    already_ingested: bool = False
    error: str | None = None


def ingest(db: BrainDb, path: Path, document_slug: str, version_label: str, *,
           ocr: str = "auto", replace: bool = False, price_table: bool = False,
           document_date=None, executor: str | None = None, dry_run: bool = False) -> Result:
    doc = db.document_by_slug(document_slug)
    if doc is None:
        raise LookupError(f"documento '{document_slug}' nao existe ou nao e visivel para esta conexao")
    p = plan(path, ocr=ocr, price_table=price_table)
    if dry_run:
        return Result(None, None, "dry-run", p.extraction.pages_total, len(p.chunks),
                      sum(1 for c in p.chunks if c.kind in ("table", "price_table")))

    executor = executor or f"brain_worker@{socket.gethostname()}"
    version_id = db.register_version(doc["id"], version_label, p.sha256, path.name, p.mime, p.size,
                                     document_date, p.extraction.pages_total,
                                     {"pipeline_version": PIPELINE_VERSION, "text_ratio": p.extraction.text_ratio})
    if db.version_has_content(version_id) and not replace:
        db.commit()
        return Result(version_id, None, "skipped", 0, 0, 0, already_ingested=True)

    ingestion_id = db.ingestion_start(version_id, p.extraction.method, p.extraction.parser, PIPELINE_VERSION,
                                      executor, p.extraction.needs_ocr, p.extraction.pages_total, replace)
    db.commit()   # a ingestao "aberta" fica visivel mesmo se o resto falhar

    warnings = p.summary()["warnings"]
    try:
        for page in p.extraction.pages:
            db.add_page(ingestion_id, page.page_no, page.text, page.extraction, page.ocr, page.layout,
                        {"warnings": page.warnings} if page.warnings else {})
        for c in p.chunks:
            row = c.as_row()
            row["token_count"] = max(1, len(c.content) // 4)   # estimativa; o Lote C mede de verdade
            row["metadata"] = {"chunk_config": CHUNK_CONFIG}
            db.add_chunk(ingestion_id, row)
        status = "completed" if all(pg.extraction != "none" for pg in p.extraction.pages) else "partial"
        if status == "partial":
            warnings.append("paginas sem texto (extraction=none): ingestao parcial")
        row = db.finish(ingestion_id, status, None, warnings, {**p.metrics, "chunk_config": CHUNK_CONFIG})
        db.commit()
        return Result(version_id, ingestion_id, row["status"], row["pages_done"], row["chunks_created"], row["tables_created"])
    except Exception as exc:
        db.rollback()
        db.fail(ingestion_id, f"{exc.__class__.__name__}: {exc}", warnings)
        db.commit()
        return Result(version_id, ingestion_id, "failed", 0, 0, 0, error=str(exc))


def plan_to_json(p: Plan) -> str:
    return json.dumps({"summary": p.summary(), "chunks": [c.as_row() for c in p.chunks]}, ensure_ascii=False, indent=2, default=str)
