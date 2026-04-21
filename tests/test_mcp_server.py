"""MCP sub-app tests.

Exercises the HTTP surface of the embedded MCP layer via FastAPI's
TestClient. DB-touching tools (search / describe / execute) need the
pool monkey-patched to a fake; compile and export_osi also read via the
cursor so we fake that too. No live DB required.
"""
from __future__ import annotations

import os
from typing import Any, List, Optional, Tuple

import pytest
from fastapi.testclient import TestClient


class _Cur:
    """Minimal cursor that serves pre-scripted result sets."""

    def __init__(self) -> None:
        self.calls: List[Tuple[str, Any]] = []
        self._script: List[Tuple[List[Tuple[Any, ...]], List[str]]] = []
        self._rows: List[Tuple[Any, ...]] = []
        self.description: List[Tuple[str, ...]] = []

    def script(self, rows: List[Tuple[Any, ...]], cols: Optional[List[str]] = None) -> None:
        self._script.append((rows, cols or []))

    def execute(self, sql: str, params: Any = None) -> None:
        self.calls.append((sql.strip(), params))
        rows, cols = (self._script.pop(0) if self._script else ([], []))
        self._rows = list(rows)
        self.description = [(c,) for c in cols]

    def fetchone(self) -> Any:
        return self._rows[0] if self._rows else None

    def fetchall(self) -> List[Tuple[Any, ...]]:
        out, self._rows = self._rows, []
        return out

    def close(self) -> None:
        pass


class _Conn:
    def __init__(self, cur: _Cur) -> None:
        self.cur = cur

    def cursor(self) -> _Cur:
        return self.cur

    def __enter__(self) -> "_Conn":
        return self

    def __exit__(self, *_: Any) -> None:
        pass


class _Pool:
    def __init__(self) -> None:
        self.cur = _Cur()

    class _CurCtx:
        def __init__(self, cur: _Cur) -> None:
            self._cur = cur

        def __enter__(self) -> _Cur:
            return self._cur

        def __exit__(self, *_: Any) -> None:
            pass

    def cursor(self) -> "_Pool._CurCtx":
        return _Pool._CurCtx(self.cur)

    def connection(self) -> _Conn:
        return _Conn(self.cur)


@pytest.fixture
def client(monkeypatch):
    """Install a fake pool and return a TestClient."""
    monkeypatch.setenv(
        "DATABASE_URI",
        "teradata://demo_user:demo_user@localhost:1025/demo_user",
    )
    from semantic_catalog import db as db_module
    pool = _Pool()
    monkeypatch.setattr(db_module, "_pool_singleton", pool)
    from semantic_catalog.server import create_app
    app = create_app()
    return TestClient(app), pool


def test_tools_endpoint_lists_five_tools(client) -> None:
    c, _ = client
    r = c.get("/mcp/tools")
    assert r.status_code == 200
    names = [t["name"] for t in r.json()["tools"]]
    assert set(names) == {
        "semantic.search", "semantic.describe", "semantic.compile",
        "semantic.execute", "semantic.export_osi",
    }


def test_search_tool_calls_sp_semantic_search(client) -> None:
    c, pool = client
    pool.cur.script([("METRIC", "revenue", "tpch", "sum of price", None, 5)],
                    cols=["entity_type", "entity_name", "parent_name",
                          "description", "synonyms", "relevance"])
    r = c.post("/mcp/tools/semantic.search", json={"term": "revenue"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == 1
    assert body["hits"][0]["entity_name"] == "revenue"
    # verified that the tool actually CALL'd the SP
    assert any("sp_semantic_search" in sql for sql, _ in pool.cur.calls)


def test_search_tool_rejects_missing_term(client) -> None:
    c, _ = client
    r = c.post("/mcp/tools/semantic.search", json={})
    assert r.status_code == 400


def test_describe_tool_round_trip(client) -> None:
    c, pool = client
    pool.cur.script(
        [(1, "name", "revenue"), (2, "type", "SIMPLE")],
        cols=["attr_ordinal", "attr_key", "attr_value"],
    )
    r = c.post("/mcp/tools/semantic.describe",
               json={"entity_type": "METRIC", "entity_name": "revenue"})
    assert r.status_code == 200
    body = r.json()
    assert body["entity_name"] == "revenue"
    assert len(body["attributes"]) == 2


def test_export_osi_tool_passthrough(client, monkeypatch) -> None:
    c, _pool = client
    called = {}

    def _fake(cur, db, model_name):
        called["db"], called["model"] = db, model_name
        return "version: '0.1.1'\nsemantic_model:\n- name: x\n"

    monkeypatch.setattr("semantic_catalog.mcp.server.export_osi_yaml", _fake)
    r = c.post("/mcp/tools/semantic.export_osi", json={"model": "x"})
    assert r.status_code == 200
    assert "version" in r.json()["yaml"]
    assert called["model"] == "x"


def test_bearer_token_enforced_when_env_set(monkeypatch) -> None:
    monkeypatch.setenv(
        "DATABASE_URI",
        "teradata://demo_user:demo_user@localhost:1025/demo_user",
    )
    from semantic_catalog import db as db_module
    pool = _Pool()
    monkeypatch.setattr(db_module, "_pool_singleton", pool)
    monkeypatch.setenv("SEMANTIC_MCP_TOKEN", "s3cret")
    from semantic_catalog.server import create_app
    app = create_app()
    c = TestClient(app)
    # Missing header → 401
    r = c.get("/mcp/tools")
    assert r.status_code == 401
    # Wrong token → 403
    r = c.get("/mcp/tools", headers={"Authorization": "Bearer wrong"})
    assert r.status_code == 403
    # Correct token → 200
    r = c.get("/mcp/tools", headers={"Authorization": "Bearer s3cret"})
    assert r.status_code == 200


def test_compile_tool_surfaces_compile_errors(client) -> None:
    c, pool = client
    # Simulate UnknownModel: model lookup returns None
    pool.cur.script([], cols=["model_id"])  # resolve_model_id None
    r = c.post("/mcp/tools/semantic.compile",
               json={"request": {"model": "ghost", "metrics": ["x"]}})
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is False
    assert body["code"] == "UNKNOWN_MODEL"
