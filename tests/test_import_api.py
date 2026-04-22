"""/api/import endpoint — smoke tests for payload parsing and the
"unhappy path" (empty payload).

The commit/rollback + topological-dispatch semantics used to be tested
here against the legacy ``sp_semantic_import`` SP path. That path was
removed in v0.4 (the writer in ``semantic_catalog.importer.writer`` is
now the single source of truth). Its transaction contract is covered by
``test_py_importer.py`` — the tests here only assert the HTTP router's
framing around it.
"""
from __future__ import annotations


def test_template_endpoint(client_fake):
    r = client_fake.get("/api/import/template")
    assert r.status_code == 200
    assert "my_new_metric" in r.json()["yaml"]


def test_empty_payload_rejected(client_fake):
    r = client_fake.post("/api/import", json={"model": "m", "text": ""})
    assert r.status_code == 400
