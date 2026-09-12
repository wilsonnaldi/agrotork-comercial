"""Acesso ao banco: só as funções da API de ingestão. Nada de SQL solto.

A URL vem de `BRAIN_DB_URL` (ou é passada). Nunca é impressa nem gravada.
O worker roda com uma conexão que consegue escrever no brain (postgres,
service_role ou um administrador autenticado); quem decide é o RLS.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

import psycopg
from psycopg.types.json import Jsonb


@dataclass
class ExternalPolicy:
    value: str | None      # allowed | approved_provider_only | forbidden | None (documento invisivel)

    @property
    def may_send(self) -> bool:
        return self.value == "allowed"

    @property
    def may_send_to_approved(self) -> bool:
        return self.value in ("allowed", "approved_provider_only")


class BrainDb:
    def __init__(self, dsn: str):
        self.conn = psycopg.connect(dsn, autocommit=False)

    def close(self):
        self.conn.close()

    # ── leitura ────────────────────────────────────────────
    def document_by_slug(self, slug: str) -> dict[str, Any] | None:
        with self.conn.cursor() as cur:
            cur.execute("select id, slug, source_key, title, access_level::text from brain.documents where slug = %s", (slug,))
            row = cur.fetchone()
        return None if row is None else {"id": row[0], "slug": row[1], "source_key": row[2], "title": row[3], "access_level": row[4]}

    def external_policy(self, document_id) -> ExternalPolicy:
        with self.conn.cursor() as cur:
            cur.execute("select brain.external_processing_for(%s)::text", (document_id,))
            (v,) = cur.fetchone()
        return ExternalPolicy(v)

    def caller_level(self) -> str | None:
        with self.conn.cursor() as cur:
            cur.execute("select brain.caller_access_level()::text")
            (v,) = cur.fetchone()
        return v

    # ── API de ingestao ────────────────────────────────────
    def register_version(self, document_id, label: str, sha256: str, filename: str, mime: str,
                         size: int, document_date=None, page_count: int | None = None, metadata: dict | None = None):
        with self.conn.cursor() as cur:
            cur.execute(
                "select brain.register_version(%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (document_id, label, sha256, filename, mime, size, document_date, page_count, Jsonb(metadata or {})),
            )
            (vid,) = cur.fetchone()
        return vid

    def version_has_content(self, version_id) -> bool:
        with self.conn.cursor() as cur:
            cur.execute("select exists (select 1 from brain.document_chunks where version_id = %s)", (version_id,))
            (v,) = cur.fetchone()
        return bool(v)

    def ingestion_start(self, version_id, method: str, parser: str, pipeline_version: str, executor: str | None,
                        needs_ocr: bool, pages_total: int | None, replace: bool):
        with self.conn.cursor() as cur:
            cur.execute(
                "select brain.ingestion_start(%s, %s, %s, %s, %s, %s, %s, %s)",
                (version_id, method, parser, pipeline_version, executor, needs_ocr, pages_total, replace),
            )
            (iid,) = cur.fetchone()
        return iid

    def add_page(self, ingestion_id, page_no: int, text: str, extraction: str, ocr: bool, layout: dict, metadata: dict):
        with self.conn.cursor() as cur:
            cur.execute("select brain.ingestion_add_page(%s, %s, %s, %s, %s, %s, %s)",
                        (ingestion_id, page_no, text, extraction, ocr, Jsonb(layout), Jsonb(metadata)))

    def add_chunk(self, ingestion_id, row: dict[str, Any]) -> int:
        with self.conn.cursor() as cur:
            cur.execute(
                "select brain.ingestion_add_chunk(%s, %s, %s::brain.chunk_kind, %s, %s, %s, %s, %s, %s, %s, %s)",
                (ingestion_id, row["ordinal"], row["kind"], row["page_from"], row["page_to"], row["content"],
                 row["heading_path"], Jsonb(row["table_data"]) if row.get("table_data") is not None else None,
                 row["codes"], row.get("token_count"), Jsonb(row.get("metadata") or {})),
            )
            (cid,) = cur.fetchone()
        return cid

    def finish(self, ingestion_id, status: str, error: str | None, warnings: list[str], metrics: dict) -> dict[str, Any]:
        with self.conn.cursor() as cur:
            cur.execute(
                "select to_jsonb(r) from brain.ingestion_finish(%s, %s::brain.ingestion_status, %s, %s, %s) r",
                (ingestion_id, status, error, Jsonb(warnings), Jsonb(metrics)),
            )
            (row,) = cur.fetchone()
        return row if isinstance(row, dict) else json.loads(row)

    def record_failure(self, version_id, method: str, parser: str, pipeline_version: str, executor: str | None,
                       error: str, warnings: list[str], replace_attempt: bool, started_at) -> dict[str, Any]:
        """Trilha de uma tentativa desfeita por rollback (a ingestao aberta ja nao existe)."""
        with self.conn.cursor() as cur:
            cur.execute(
                "select to_jsonb(r) from brain.ingestion_record_failure(%s, %s, %s, %s, %s, %s, %s, %s, %s) r",
                (version_id, method, parser, pipeline_version, executor, error, Jsonb(warnings), replace_attempt, started_at),
            )
            (row,) = cur.fetchone()
        return row if isinstance(row, dict) else json.loads(row)

    def commit(self):
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()
