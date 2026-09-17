"""CLI do worker.

  python -m brain_worker ingest ARQUIVO --document SLUG --label V41 [--replace] [--ocr auto|never|force] [--pages 1,3-5]
  python -m brain_worker plan   ARQUIVO [--json] [--pages 1]   # so extrai e fatia; nao toca no banco

`--pages` recorta um PDF por pagina fisica: '1', '1,3', '2-4', '1,3-5'. O
numero da pagina no BRAIN continua sendo o do arquivo original, e
`page_count` continua sendo o total do arquivo — o recorte fica no metadata
da versao. So vale para PDF.

Conexão: variável de ambiente BRAIN_DB_URL (nunca em argumento, nunca em log).
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .db import BrainDb
from .extract import parse_pages
from .pipeline import ingest, plan, plan_to_json


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="brain_worker")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_plan = sub.add_parser("plan", help="extrai e fatia sem gravar")
    p_plan.add_argument("file", type=Path)
    p_plan.add_argument("--ocr", choices=["auto", "never", "force"], default="auto")
    p_plan.add_argument("--price-table", action="store_true")
    p_plan.add_argument("--json", action="store_true")
    p_plan.add_argument("--profile", default=None, help="perfil de codigos (ex.: magnojet_catalog)")
    p_plan.add_argument("--pages", default=None, help="paginas do PDF a ingerir: '1', '1,3', '2-4', '1,3-5'. A numeracao no BRAIN continua a do arquivo original")

    p_ing = sub.add_parser("ingest", help="grava versao, paginas e chunks")
    p_ing.add_argument("file", type=Path)
    p_ing.add_argument("--document", required=True, help="slug em brain.documents")
    p_ing.add_argument("--label", required=True, help="rotulo da versao (V41, 2026-09)")
    p_ing.add_argument("--date", default=None, help="data do documento (AAAA-MM-DD)")
    p_ing.add_argument("--ocr", choices=["auto", "never", "force"], default="auto")
    p_ing.add_argument("--price-table", action="store_true")
    p_ing.add_argument("--replace", action="store_true", help="reprocessar versao que ja tem conteudo")
    p_ing.add_argument("--dry-run", action="store_true")
    p_ing.add_argument("--profile", default=None, help="perfil de codigos; padrao: pela fonte do documento")
    p_ing.add_argument("--pages", default=None, help="paginas do PDF a ingerir: '1', '1,3', '2-4', '1,3-5'. A numeracao no BRAIN continua a do arquivo original")

    a = ap.parse_args(argv)
    # Selecao invalida e erro de operador: para antes de abrir arquivo ou banco,
    # com a mensagem do parser, em vez de virar excecao la dentro.
    if a.pages is not None:
        try:
            parse_pages(a.pages)
        except ValueError as exc:
            print(f"--pages: {exc}", file=sys.stderr)
            return 2
    if a.cmd == "plan":
        try:
            p = plan(a.file, ocr=a.ocr, price_table=a.price_table, profile=a.profile, pages=a.pages)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        print(plan_to_json(p) if a.json else _fmt(p.summary()))
        return 0

    dsn = os.environ.get("BRAIN_DB_URL")
    if not dsn:
        print("BRAIN_DB_URL nao definida", file=sys.stderr)
        return 2
    db = BrainDb(dsn)
    try:
        r = ingest(db, a.file, a.document, a.label, ocr=a.ocr, replace=a.replace,
                   price_table=a.price_table, document_date=a.date, dry_run=a.dry_run, profile=a.profile,
                   pages=a.pages)
    finally:
        db.close()
    print(_fmt({"version_id": str(r.version_id), "ingestion_id": str(r.ingestion_id), "status": r.status,
                "pages": r.pages, "chunks": r.chunks, "tables": r.tables,
                "already_ingested": r.already_ingested, "error": r.error}))
    return 0 if r.status in ("completed", "partial", "skipped", "dry-run") else 1


def _fmt(d: dict) -> str:
    return "\n".join(f"{k}: {v}" for k, v in d.items())


if __name__ == "__main__":
    raise SystemExit(main())
