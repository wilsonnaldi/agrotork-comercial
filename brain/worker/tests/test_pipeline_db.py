"""Ingestão de ponta a ponta contra um PostgreSQL local com as migrations.

Pula se `BRAIN_TEST_DB_URL` não estiver definida. O banco precisa ter todas
as migrations aplicadas (o ensaio `supabase/db-tests/ensaiar-ingestao.sh`
monta um e exporta a variável). A conexão é como `postgres` (o worker em
produção conecta com credencial de serviço; a regra de quem pode escrever é
o RLS, testado nas suítes 33/34/35).

Nenhum documento real: o PDF é gerado na hora (fixtures.py).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fixtures import make_catalog_pdf, make_price_xlsx  # noqa: E402
from brain_worker.db import BrainDb  # noqa: E402
from brain_worker.gate import ExternalGate, ExternalProcessingDenied  # noqa: E402
from brain_worker.pipeline import ingest  # noqa: E402

DSN = os.environ.get("BRAIN_TEST_DB_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="BRAIN_TEST_DB_URL nao definida")

SRC = "wk_sol"
DOC_PUB = "wk-catalogo-sol"
DOC_COM = "wk-tabela-sol"


@pytest.fixture(scope="module")
def db():
    d = BrainDb(DSN)
    with d.conn.cursor() as cur:
        cur.execute("delete from brain.documents where slug in (%s, %s)", (DOC_PUB, DOC_COM))
        cur.execute("delete from brain.knowledge_sources where key = %s", (SRC,))
        cur.execute("insert into brain.knowledge_sources (key, name, kind, default_access_level, external_processing) "
                    "values (%s, 'Pontas Sol (teste)', 'manufacturer', 'public', 'allowed')", (SRC,))
        cur.execute("insert into brain.documents (source_key, slug, title, document_type, access_level) values "
                    "(%s, %s, 'Catálogo Sol (teste)', 'catalog', 'public'), (%s, %s, 'Tabela Sol revenda (teste)', 'price_list', 'commercial')",
                    (SRC, DOC_PUB, SRC, DOC_COM))
    d.commit()
    yield d
    with d.conn.cursor() as cur:
        cur.execute("delete from brain.documents where slug in (%s, %s)", (DOC_PUB, DOC_COM))
        cur.execute("delete from brain.knowledge_sources where key = %s", (SRC,))
    d.commit()
    d.close()


def _q(db, sql, *args):
    try:
        with db.conn.cursor() as cur:
            cur.execute(sql, args)
            rows = cur.fetchall()
        db.conn.commit()
        return rows
    except Exception:
        db.conn.rollback()
        raise


def test_d1_full_ingestion(db, tmp_path):
    pdf = make_catalog_pdf(tmp_path / "catalogo_sintetico.pdf")
    r = ingest(db, pdf, DOC_PUB, "V1", ocr="never")
    assert r.status == "completed" and r.pages == 3 and r.tables == 1 and r.chunks >= 6, r
    (row,) = _q(db, "select status::text, method, parser, pipeline_version, pages_total, pages_done, chunks_created, tables_created, "
                    "started_at is not null, finished_at is not null, error from brain.knowledge_ingestions where id = %s", r.ingestion_id)
    assert row[0] == "completed" and row[1] == "pdf_text" and row[2].startswith("pdfplumber") and row[3] == "lote-b.1"
    assert row[4] == 3 and row[5] == 3 and row[6] == r.chunks and row[7] == 1 and row[8] and row[9] and row[10] is None
    # versao: draft, sha correto, caminho canonico
    (v,) = _q(db, "select status::text, file_sha256, storage_path, page_count from brain.document_versions where id = %s", r.version_id)
    assert v[0] == "draft" and len(v[1]) == 64 and v[2] == f"{SRC}/{DOC_PUB}/V1/{v[1]}.pdf" and v[3] == 3
    # todo chunk aponta para pagina existente da mesma versao (FK composta) e nao cruza pagina
    (n_bad,) = _q(db, "select count(*) from brain.document_chunks c where c.version_id = %s and (c.page_from <> c.page_to "
                      "or not exists (select 1 from brain.document_pages p where p.version_id = c.version_id and p.page_no = c.page_from))", r.version_id)[0]
    assert n_bad == 0
    # tabela tecnica: JSONB numerico
    (td,) = _q(db, "select table_data from brain.document_chunks where version_id = %s and kind = 'table'", r.version_id)[0]
    assert td["rows"][1][5] == 0.77 and td["rows"][1][6] == 77 and td["units"]["Vazao_L/min"] == "L/min"
    # codigos normalizados pelo gatilho
    (codes,) = _q(db, "select codes from brain.document_chunks where version_id = %s and kind = 'table'", r.version_id)[0]
    assert "PS981CAP" in codes and "SOL-CV02" in codes


def test_d2_rerun_is_idempotent_and_replace_works(db, tmp_path):
    pdf = make_catalog_pdf(tmp_path / "catalogo_sintetico.pdf")
    first = _q(db, "select v.id from brain.document_versions v join brain.documents d on d.id = v.document_id where d.slug = %s", DOC_PUB)[0][0]
    r = ingest(db, pdf, DOC_PUB, "V1", ocr="never")
    assert r.status == "skipped" and r.already_ingested and r.version_id == first
    (n_versions,) = _q(db, "select count(*) from brain.document_versions where document_id = (select id from brain.documents where slug = %s)", DOC_PUB)[0]
    assert n_versions == 1
    (n_ing,) = _q(db, "select count(*) from brain.knowledge_ingestions where version_id = %s", first)[0]
    assert n_ing == 1
    # reprocessar: chunks identicos (determinismo), ingestao antiga fica como historico
    before = _q(db, "select ordinal, content_sha256, kind, page_from from brain.document_chunks where version_id = %s order by ordinal", first)
    r2 = ingest(db, pdf, DOC_PUB, "V1", ocr="never", replace=True)
    assert r2.status == "completed" and r2.ingestion_id != r.ingestion_id
    after = _q(db, "select ordinal, content_sha256, kind, page_from from brain.document_chunks where version_id = %s order by ordinal", first)
    assert before == after
    (n_ing, replaced) = _q(db, "select count(*), count(*) filter (where metadata ? 'replaced_by') from brain.knowledge_ingestions where version_id = %s", first)[0]
    assert n_ing == 2 and replaced == 1


def test_d3_different_file_new_version(db, tmp_path):
    pdf2 = make_catalog_pdf(tmp_path / "catalogo_v2.pdf", pages_long_text=2)
    r = ingest(db, pdf2, DOC_PUB, "V2", ocr="never")
    assert r.status == "completed" and r.pages == 4
    (n,) = _q(db, "select count(*) from brain.document_versions where document_id = (select id from brain.documents where slug = %s)", DOC_PUB)[0]
    assert n == 2
    # mesmo arquivo com OUTRO rotulo: nao duplica (o sha manda)
    r3 = ingest(db, pdf2, DOC_PUB, "V2-copia", ocr="never")
    assert r3.status == "skipped" and r3.version_id == r.version_id


def test_d4_search_and_provenance_after_activation(db):
    vid = _q(db, "select v.id from brain.document_versions v join brain.documents d on d.id = v.document_id where d.slug = %s and v.version_label = 'V1'", DOC_PUB)[0][0]
    with db.conn.cursor() as cur:
        cur.execute("update brain.document_versions set status = 'active', valid_from = current_date where id = %s", (vid,))
    db.commit()
    hits = _q(db, "select chunk_id, kind::text, page_from, rank_exact, version_label from brain.search_knowledge('ps981cap')")
    assert hits and hits[0][1] == "table" and hits[0][2] == 2 and hits[0][3] == 1 and hits[0][4] == "V1"
    (prov,) = _q(db, "select brain.chunk_provenance(%s)", hits[0][0])[0]
    assert prov["citation"] == "Pontas Sol (teste) — Catálogo Sol (teste) V1, p. 2"
    assert prov["file"]["sha256"] == prov["file"]["path"].split("/")[-1].split(".")[0]
    assert prov["ingestion"]["pipeline_version"] == "lote-b.1" and prov["page"]["extraction"] == "text_layer"
    # pergunta em portugues acha a pagina institucional
    hits = _q(db, "select page_from from brain.search_knowledge('núcleo de cerâmica')")
    assert hits and hits[0][0] == 1


def test_d5_external_gate(db):
    pub = _q(db, "select id from brain.documents where slug = %s", DOC_PUB)[0][0]
    com = _q(db, "select id from brain.documents where slug = %s", DOC_COM)[0][0]
    gate = ExternalGate(db, approved_providers=frozenset({"ocr-aprovado"}))
    assert gate.decision(pub) == "allowed" and gate.allow(pub, "qualquer")
    assert gate.decision(com) == "forbidden" and not gate.allow(com, "ocr-aprovado")
    with pytest.raises(ExternalProcessingDenied):
        gate.require(com, "ocr-aprovado")
    # documento inexistente: negado (None → forbidden)
    assert gate.decision("00000000-0000-0000-0000-000000000000") == "forbidden"


def test_d6_failure_is_recorded(db, tmp_path):
    xlsx = make_price_xlsx(tmp_path / "precos.xlsx")
    # commercial: ingere normalmente (o worker so grava; a politica externa e para provedores)
    r = ingest(db, xlsx, DOC_COM, "2026-09", ocr="never", price_table=True)
    assert r.status == "completed" and r.pages == 2 and r.tables == 2
    (lvl,) = _q(db, "select access_level::text from brain.document_chunks where version_id = %s limit 1", r.version_id)[0]
    assert lvl == "commercial"
    # falha: documento inexistente
    with pytest.raises(LookupError):
        ingest(db, xlsx, "nao-existe", "x")
    # falha no meio: ingestion_finish sem paginas → status failed com erro coerente
    with db.conn.cursor() as cur:
        cur.execute("select brain.ingestion_start(%s, 'xlsx', 'teste', 'lote-b.1', 'teste', false, 1, true)", (r.version_id,))
        (iid,) = cur.fetchone()
        db.commit()
        with pytest.raises(Exception):
            cur.execute("select brain.ingestion_finish(%s, 'completed')", (iid,))
        db.rollback()
        cur.execute("select brain.ingestion_fail(%s, 'teste: falha simulada')", (iid,))
        db.commit()
        cur.execute("select status::text, error, finished_at is not null from brain.knowledge_ingestions where id = %s", (iid,))
        row = cur.fetchone()
    assert row[0] == "failed" and "falha simulada" in row[1] and row[2]
    # o ERP nao foi tocado pelo worker: nenhuma linha em products com o codigo sintetico
    (n,) = _q(db, "select count(*) from public.products where code like 'PS98%%' or code like 'S100%%'")[0]
    assert n == 0
