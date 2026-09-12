"""arquivo → sha256 → versão → páginas → chunks → fechamento.

Duas transações, e só duas:

  T1  `register_version` — a versão (draft) existe mesmo que a ingestão
      falhe: "registrada, sem conteúdo" é um estado legítimo e reexecutável.
  T2  `ingestion_start` (com ou sem replace) + páginas + chunks +
      `ingestion_finish`. NADA é confirmado no meio: com replace, a remoção
      do conteúdo antigo e o conteúdo novo entram ou saem juntos. Se
      qualquer passo falhar, o rollback devolve páginas e chunks anteriores
      exatamente como estavam, e a tentativa é registrada por
      `ingestion_record_failure` numa transação própria (T3, só nesse caso).

Crash do processo no meio de T2: o servidor desfaz a transação; o conteúdo
anterior fica; a trilha não recebe a linha de falha (não há quem a escreva)
— o operador vê "sem ingestão nova" e reexecuta.
"""
from __future__ import annotations

import hashlib
import json
import socket
import time
from datetime import datetime, timezone
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import PIPELINE_VERSION
from .chunking import CONFIG as CHUNK_CONFIG
from .chunking import Chunk, PageInput, chunk_pages
from .db import BrainDb
from .extract import Extraction, extract, mime_for, sniff_ok
from .tables import audit_table


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
            "profile": self.metrics.get("profile"), "tables_reconstructed": self.metrics.get("tables_reconstructed"),
            "table_audit_issues": self.metrics.get("table_audit_issues"),
        }


PROFILE_BY_SOURCE = {"magnojet": "magnojet_catalog"}   # perfil de codigos por fonte (particularidades isoladas em codes.py)


def plan(path: Path, ocr: str = "auto", price_table: bool = False, profile: str | None = None) -> Plan:
    if not path.is_file():
        raise FileNotFoundError(str(path))
    mime = mime_for(path)
    if not sniff_ok(path):
        raise ValueError(f"{path.name}: conteudo nao bate com a extensao")
    t0 = time.perf_counter()
    ext = extract(path, ocr=ocr)
    t1 = time.perf_counter()
    chunks = chunk_pages([PageInput(p.page_no, p.text, p.tables) for p in ext.pages], price_table_hint=price_table, profile=profile)
    t2 = time.perf_counter()
    metrics = {"extract_ms": round((t1 - t0) * 1000), "chunk_ms": round((t2 - t1) * 1000), "profile": profile,
               "tables_reconstructed": sum(int(p.layout.get("tables_reconstructed", 0)) for p in ext.pages),
               "table_audit_issues": sum(len(audit_table(t)) for p in ext.pages for t in p.tables)}
    return Plan(sha256_of(path), mime, path.stat().st_size, ext, chunks, metrics)


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


class InjectedFailure(RuntimeError):
    """Falha provocada pelos testes num ponto escolhido da T2 (nunca pela CLI)."""


def ingest(db: BrainDb, path: Path, document_slug: str, version_label: str, *,
           ocr: str = "auto", replace: bool = False, price_table: bool = False,
           document_date=None, executor: str | None = None, dry_run: bool = False,
           fail_at: str | None = None, profile: str | None = None) -> Result:
    """`fail_at` (so testes): 'after_start' | 'after_pages' | 'mid_chunks' | 'before_finish' —
    levanta InjectedFailure naquele ponto da T2, DEPOIS de o conteudo antigo ter sido removido
    dentro da transacao. Serve para provar que o rollback devolve tudo."""
    doc = db.document_by_slug(document_slug)
    if doc is None:
        raise LookupError(f"documento '{document_slug}' nao existe ou nao e visivel para esta conexao")
    profile = profile or PROFILE_BY_SOURCE.get(doc["source_key"])
    p = plan(path, ocr=ocr, price_table=price_table, profile=profile)
    if dry_run:
        return Result(None, None, "dry-run", p.extraction.pages_total, len(p.chunks),
                      sum(1 for c in p.chunks if c.kind in ("table", "price_table")))

    executor = executor or f"brain_worker@{socket.gethostname()}"
    # T1: a versao. Confirmada sozinha — e um registro, nao conteudo.
    version_id = db.register_version(doc["id"], version_label, p.sha256, path.name, p.mime, p.size,
                                     document_date, p.extraction.pages_total,
                                     {"pipeline_version": PIPELINE_VERSION, "text_ratio": p.extraction.text_ratio})
    db.commit()
    if db.version_has_content(version_id) and not replace:
        db.rollback()
        return Result(version_id, None, "skipped", 0, 0, 0, already_ingested=True)
    db.rollback()   # fecha a transacao de leitura antes de abrir a T2

    warnings = p.summary()["warnings"]
    started_at = datetime.now(timezone.utc)
    ingestion_id = None
    # T2: start (remove o antigo se replace) + paginas + chunks + finish. Sem commit no meio.
    try:
        ingestion_id = db.ingestion_start(version_id, p.extraction.method, p.extraction.parser, PIPELINE_VERSION,
                                          executor, p.extraction.needs_ocr, p.extraction.pages_total, replace)
        if fail_at == "after_start":
            raise InjectedFailure("falha injetada depois de ingestion_start")
        for page in p.extraction.pages:
            db.add_page(ingestion_id, page.page_no, page.text, page.extraction, page.ocr, page.layout,
                        {"warnings": page.warnings} if page.warnings else {})
        if fail_at == "after_pages":
            raise InjectedFailure("falha injetada depois das paginas")
        for n, c in enumerate(p.chunks):
            if fail_at == "mid_chunks" and n == max(1, len(p.chunks) // 2):
                raise InjectedFailure(f"falha injetada no chunk {n} de {len(p.chunks)}")
            row = c.as_row()
            row["token_count"] = max(1, len(c.content) // 4)   # estimativa; o Lote C mede de verdade
            row["metadata"] = {"chunk_config": CHUNK_CONFIG}
            db.add_chunk(ingestion_id, row)
        if fail_at == "before_finish":
            raise InjectedFailure("falha injetada antes de ingestion_finish")
        status = "completed" if all(pg.extraction != "none" for pg in p.extraction.pages) else "partial"
        if status == "partial":
            warnings.append("paginas sem texto (extraction=none): ingestao parcial")
        row = db.finish(ingestion_id, status, None, warnings, {**p.metrics, "chunk_config": CHUNK_CONFIG})
        db.commit()
        return Result(version_id, ingestion_id, row["status"], row["pages_done"], row["chunks_created"], row["tables_created"])
    except Exception as exc:
        # Tudo da T2 sai — inclusive a remocao do conteudo antigo. O anterior fica intacto.
        db.rollback()
        # T3: a trilha da tentativa. Se ate isto falhar (banco fora), o erro sobe.
        rec = db.record_failure(version_id, p.extraction.method, p.extraction.parser, PIPELINE_VERSION, executor,
                                f"{exc.__class__.__name__}: {exc}", warnings, replace, started_at)
        db.commit()
        return Result(version_id, rec["id"], "failed", 0, 0, 0, error=str(exc))


def plan_to_json(p: Plan) -> str:
    return json.dumps({"summary": p.summary(), "chunks": [c.as_row() for c in p.chunks]}, ensure_ascii=False, indent=2, default=str)
