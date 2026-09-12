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
from brain_worker.pipeline import InjectedFailure, ingest  # noqa: E402

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


# ── D7 replace atomico: falha forcada DEPOIS da remocao do antigo ─────

def _snapshot(db, version_id):
    pages = _q(db, "select page_no, text_sha256, ingestion_id::text from brain.document_pages where version_id = %s order by page_no", version_id)
    chunks = _q(db, "select id, ordinal, content_sha256, kind::text, page_from, ingestion_id::text from brain.document_chunks where version_id = %s order by ordinal", version_id)
    ingestions = _q(db, "select id::text, status::text, pages_done, chunks_created, metadata ? 'replaced_by' from brain.knowledge_ingestions where version_id = %s order by created_at", version_id)
    return pages, chunks, ingestions


def test_d7_failed_replace_leaves_previous_content_intact(db, tmp_path):
    """A (V1 já ingerida) fica exatamente igual quando o replace por B falha em cada ponto da T2."""
    pdf_a = make_catalog_pdf(tmp_path / "catalogo_sintetico.pdf")
    pdf_b = make_catalog_pdf(tmp_path / "catalogo_b.pdf", pages_long_text=2)   # conteudo B, sha diferente
    vid = _q(db, "select v.id from brain.document_versions v join brain.documents d on d.id = v.document_id where d.slug = %s and v.version_label = 'V1'", DOC_PUB)[0][0]
    before = _snapshot(db, vid)
    assert before[1], "V1 precisa estar ingerida (d1/d2)"
    hits_before = _q(db, "select chunk_id, score from brain.search_knowledge('ps981cap')")
    assert hits_before
    prov_before = _q(db, "select brain.chunk_provenance(%s)", hits_before[0][0])[0][0]

    for point in ("after_start", "after_pages", "mid_chunks", "before_finish"):
        # B tem o MESMO sha? nao: e outro arquivo → seria outra versao. Para forcar o replace da V1
        # com conteudo B usamos o mesmo arquivo A com falha injetada: o que importa e o ponto de falha.
        r = ingest(db, pdf_a, DOC_PUB, "V1", ocr="never", replace=True, fail_at=point)
        assert r.status == "failed" and "falha injetada" in (r.error or ""), (point, r)
        after = _snapshot(db, vid)
        # paginas, chunks (ids, ordinais, hashes, paginas, ingestion_id) identicos
        assert after[0] == before[0], point
        assert after[1] == before[1], point
        # ingestoes: as anteriores intactas (sem replaced_by novo) + UMA linha failed por tentativa
        assert [i for i in after[2] if i[1] != "failed"] == [i for i in before[2] if i[1] != "failed"], point
        failed = [i for i in after[2] if i[1] == "failed"]
        assert failed and failed[-1][2] == 0 and failed[-1][3] == 0, point
        # busca e proveniencia continuam iguais
        assert _q(db, "select chunk_id, score from brain.search_knowledge('ps981cap')") == hits_before, point
        assert _q(db, "select brain.chunk_provenance(%s)", hits_before[0][0])[0][0] == prov_before, point
        # nenhuma pagina/chunk pertence a uma ingestao failed (nada parcial ficou)
        (n_orfaos,) = _q(db, "select count(*) from brain.document_chunks c join brain.knowledge_ingestions i on i.id = c.ingestion_id "
                             "where c.version_id = %s and i.status = 'failed'", vid)[0]
        assert n_orfaos == 0, point
    (n_failed,) = _q(db, "select count(*) from brain.knowledge_ingestions where version_id = %s and status = 'failed' and (metadata->>'replace_attempt')::boolean and (metadata->>'rolled_back')::boolean", vid)[0]
    assert n_failed >= 4

    # replace bem-sucedido com conteudo B de verdade: A some inteiro, B entra inteiro, sem mistura
    # (B e outro arquivo; para trocar o conteudo da MESMA versao, ingerimos B "como" V1 forcando o sha:
    #  aqui o teste usa a API direta para simular um parser novo que produz outros chunks)
    with db.conn.cursor() as cur:
        cur.execute("select brain.ingestion_start(%s, 'pdf_text', 'parser-novo', 'lote-b.1', 'teste', false, 1, true)", (vid,))
        (iid,) = cur.fetchone()
        cur.execute("select brain.ingestion_add_page(%s, 1, 'CONTEUDO B', 'text_layer')", (iid,))
        cur.execute("select brain.ingestion_add_chunk(%s, 0, 'text', 1, 1, 'Conteudo B: bico ZETA9000 de cerâmica.', '{}', null, '{ZETA9000}')", (iid,))
        cur.execute("select brain.ingestion_finish(%s, 'completed')", (iid,))
    db.commit()
    after = _snapshot(db, vid)
    assert [p[0] for p in after[0]] == [1] and len(after[1]) == 1 and after[1][0][2] != before[1][0][2]
    assert all(c[5] == str(iid) for c in after[1]) and all(p[2] == str(iid) for p in after[0])   # nada de A sobrou
    assert not _q(db, "select 1 from brain.search_knowledge('ps981cap')")
    assert _q(db, "select chunk_id from brain.search_knowledge('ZETA9000')")
    last = [i for i in after[2] if i[0] == str(iid)][0]
    assert last[1] == "completed" and last[2] == 1 and last[3] == 1
    # historico coerente: as ingestoes completed anteriores apontam replaced_by; as failed nao
    assert all(i[4] for i in after[2] if i[1] == "completed" and i[0] != str(iid))
    # restaura A para os testes seguintes (mesmo arquivo → mesma versao)
    r = ingest(db, pdf_a, DOC_PUB, "V1", ocr="never", replace=True)
    assert r.status == "completed"
    assert _q(db, "select ordinal, content_sha256 from brain.document_chunks where version_id = %s order by ordinal", vid) == [(c[1], c[2]) for c in before[1]]


def test_d8_first_ingestion_failure_semantics(db, tmp_path):
    """Versao nova cuja PRIMEIRA ingestao falha: a versao existe (draft, sem conteudo), a falha esta na
    trilha, e reexecutar sem --replace ingere normalmente."""
    pdf = make_catalog_pdf(tmp_path / "catalogo_c.pdf", pages_long_text=3)
    r = ingest(db, pdf, DOC_PUB, "V3", ocr="never", fail_at="mid_chunks")
    assert r.status == "failed"
    (st, n_pages, n_chunks) = _q(db, "select v.status::text, (select count(*) from brain.document_pages p where p.version_id = v.id), "
                                     "(select count(*) from brain.document_chunks c where c.version_id = v.id) from brain.document_versions v where v.id = %s", r.version_id)[0]
    assert st == "draft" and n_pages == 0 and n_chunks == 0
    rows = _q(db, "select status::text, metadata->>'replace_attempt' from brain.knowledge_ingestions where version_id = %s", r.version_id)
    assert rows == [("failed", "false")]
    r2 = ingest(db, pdf, DOC_PUB, "V3", ocr="never")          # sem replace: a versao nao tinha conteudo
    assert r2.status == "completed" and r2.pages == 5
    rows = _q(db, "select status::text from brain.knowledge_ingestions where version_id = %s order by created_at", r.version_id)
    assert rows == [("failed",), ("completed",)]


def test_d9_concurrent_ingestions_serialize(db, tmp_path):
    """Duas conexoes na mesma versao: a segunda espera a primeira e e recusada sem replace."""
    import threading
    pdf = make_catalog_pdf(tmp_path / "catalogo_sintetico.pdf")
    vid = _q(db, "select v.id from brain.document_versions v join brain.documents d on d.id = v.document_id where d.slug = %s and v.version_label = 'V1'", DOC_PUB)[0][0]
    other = BrainDb(DSN)
    try:
        # conexao 1 abre um replace e NAO confirma (segura o lock da versao)
        with db.conn.cursor() as cur:
            cur.execute("select brain.ingestion_start(%s, 'pdf_text', 'x', 'lote-b.1', 'c1', false, 3, true)", (vid,))
        result: dict = {}

        def second():
            try:
                with other.conn.cursor() as cur:
                    cur.execute("set local lock_timeout = '3s'")
                    cur.execute("select brain.ingestion_start(%s, 'pdf_text', 'x', 'lote-b.1', 'c2', false, 3, false)", (vid,))
                result["ok"] = True
            except Exception as exc:  # noqa: BLE001
                result["err"] = exc.__class__.__name__ + ": " + str(exc)
            finally:
                other.conn.rollback()

        t = threading.Thread(target=second)
        t.start()
        t.join(timeout=2)
        assert t.is_alive(), "a segunda conexao deveria estar ESPERANDO o lock"
        db.conn.rollback()      # conexao 1 desiste: o conteudo antigo volta e o lock cai
        t.join(timeout=10)
        assert not t.is_alive()
        # a segunda acordou, viu o conteudo (intacto) e foi recusada por falta de replace
        assert "err" in result and "ja tem conteudo" in result["err"], result
    finally:
        other.close()
    (n,) = _q(db, "select count(*) from brain.document_chunks where version_id = %s", vid)[0]
    assert n > 0
