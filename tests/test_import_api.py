"""/api/import endpoint — dispatches each entity to sp_semantic_import.

These tests verify topological dispatch order, payload encoding, commit/
rollback semantics and the user-facing result shape. They do not exercise
the stored procedure itself — see ``tests/test_import_live.py`` for that.
"""
from __future__ import annotations

import pytest


class RecordingCursor:
    """Captures every (sql, params) pair and returns scripted OUT rows."""

    def __init__(self, out_rows):
        self._out_rows = list(out_rows)
        self.calls = []
        self.description = []
        self._result = []

    def execute(self, sql, params=None):
        self.calls.append((sql, params))
        if "sp_semantic_import" in sql.lower():
            self.description = [("model",), ("kind",), ("payload",),
                                ("p_status",), ("p_message",), ("p_entity_id",)]
            self._result = [self._out_rows.pop(0)]
        else:
            self.description = [("x",)]
            self._result = [(1,)]

    def fetchall(self):
        out, self._result = self._result, []
        return out

    def fetchone(self):
        if not self._result: return None
        return self._result.pop(0)

    def close(self): pass


class RecordingConn:
    def __init__(self, out_rows):
        self.cur = RecordingCursor(out_rows)
        self.autocommit = True
        self.commits = 0
        self.rollbacks = 0
    def cursor(self): return self.cur
    def commit(self): self.commits += 1
    def rollback(self): self.rollbacks += 1
    def __enter__(self): return self
    def __exit__(self, *a): pass


class RecordingPool:
    def __init__(self, out_rows):
        self.conn = RecordingConn(out_rows)
    def connection(self): return self.conn
    class _CC:
        def __init__(self, c): self.c = c
        def __enter__(self): return self.c
        def __exit__(self, *a): pass
    def cursor(self): return RecordingPool._CC(self.conn.cur)


@pytest.fixture
def import_pool(monkeypatch):
    # Six items in the example payload: MODEL(sample), DATASET, FIELD, FIELD,
    # METRIC, METRIC_EXPR, AI_CONTEXT — scripted by the test itself.
    from semantic_catalog import db
    def _install(out_rows):
        pool = RecordingPool(out_rows)
        monkeypatch.setattr(db, "_pool_singleton", pool)
        return pool
    return _install


def _apply_client(client_fake, import_pool, out_rows):
    """Convenience wrapper: install a RecordingPool, issue the request."""
    pool = import_pool(out_rows)
    return pool


def test_ordered_dispatch_and_commit(client_fake, import_pool):
    # Five items: DATASET, FIELD, METRIC, METRIC_EXPR, AI_CONTEXT
    # all report OK → with dry_run=False we should see one commit().
    pool = _apply_client(client_fake, import_pool, [
        ("m","DATASET","{}","OK","Created dataset", 10),
        ("m","FIELD","{}","OK","Created field", 20),
        ("m","METRIC","{}","OK","Created metric", 30),
        ("m","METRIC_EXPR","{}","OK","Added expr", 30),
        ("m","AI_CONTEXT","{}","OK","Set", 30),
    ])
    text = """\
datasets:
  - name: ds
    fields:
      - name: f1
metrics:
  - name: m1
    primary_dataset: ds
    expressions: {TERADATA: "1"}
ai_context:
  - entity_type: METRIC
    entity_name: m1
    synonyms: [a]
"""
    r = client_fake.post("/api/import?legacy=true", json={
        "model": "m", "text": text, "dry_run": False,
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok_count"] == 5
    assert body["error_count"] == 0
    assert body["applied"] is True
    assert pool.conn.commits == 1
    assert pool.conn.rollbacks == 0
    # First call is DATASET, second FIELD, ... (topological order).
    call_kinds = [c[1][1] for c in pool.conn.cur.calls if "sp_semantic_import" in c[0].lower()]
    assert call_kinds == ["DATASET", "FIELD", "METRIC", "METRIC_EXPR", "AI_CONTEXT"]


def test_dry_run_rolls_back_even_on_success(client_fake, import_pool):
    pool = _apply_client(client_fake, import_pool, [
        ("m","METRIC","{}","OK","ok", 1),
    ])
    r = client_fake.post("/api/import?legacy=true", json={
        "model": "m",
        "text": "metrics:\n  - name: x\n    primary_dataset: y\n    expressions: {TERADATA: '1'}\n",
        "dry_run": True,
    })
    assert r.status_code == 200
    assert r.json()["applied"] is False
    assert pool.conn.rollbacks == 1
    assert pool.conn.commits == 0


def test_any_error_rolls_back(client_fake, import_pool):
    pool = _apply_client(client_fake, import_pool, [
        ("m","DATASET","{}","OK","created", 1),
        ("m","FIELD","{}","ERROR","Unknown dataset \"missing\"", None),
    ])
    text = """\
datasets:
  - name: d
    fields:
      - name: bad
        dataset: missing    # triggers the scripted error
"""
    r = client_fake.post("/api/import?legacy=true", json={
        "model": "m", "text": text, "dry_run": False,
    })
    body = r.json()
    assert body["error_count"] == 1
    assert body["applied"] is False
    assert pool.conn.rollbacks == 1
    assert pool.conn.commits == 0


def test_template_endpoint(client_fake):
    r = client_fake.get("/api/import/template")
    assert r.status_code == 200
    assert "my_new_metric" in r.json()["yaml"]


def test_empty_payload_rejected(client_fake):
    r = client_fake.post("/api/import", json={"model":"m","text":""})
    assert r.status_code == 400
