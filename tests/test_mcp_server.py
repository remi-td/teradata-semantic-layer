"""MCP server tests — JSON-RPC over Streamable HTTP.

Exercises the embedded MCP transport via FastAPI's TestClient: full
``initialize`` handshake, ``tools/list``, ``tools/call`` for each of the
five catalog tools, plus the bearer-token gate. DB-touching tools are
served by an in-memory fake pool (:class:`_Pool`) — no live DB needed.

The Streamable-HTTP transport returns single-shot tool responses as
text/event-stream frames, so each test pulls the JSON payload out of
the ``data:`` line.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional, Tuple

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------- fakes


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


# ---------------------------------------------------------------- helpers


_HEADERS = {
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
}


def _parse_sse(body: str) -> Dict[str, Any]:
    """Pull the JSON payload out of a Streamable-HTTP SSE frame."""
    m = re.search(r"data:\s*(.*)", body)
    if not m:
        raise AssertionError(f"no data: line in body: {body!r}")
    return json.loads(m.group(1))


class _MCPClient:
    """Thin wrapper that runs the JSON-RPC handshake once and exposes
    a ``call(method, params)`` method that handles SSE parsing."""

    def __init__(self, http: TestClient) -> None:
        self._http = http
        # 1. initialize
        r = http.post("/mcp/", json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "0.0"},
            },
        }, headers=_HEADERS)
        assert r.status_code == 200, f"initialize failed: {r.status_code} {r.text}"
        self._sid = r.headers.get("mcp-session-id")
        self._headers = dict(_HEADERS)
        if self._sid:
            self._headers["mcp-session-id"] = self._sid
        # 2. notifications/initialized — required by the protocol
        http.post("/mcp/", json={
            "jsonrpc": "2.0", "method": "notifications/initialized",
        }, headers=self._headers)
        self._next_id = 2

    def call(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        rid = self._next_id
        self._next_id += 1
        body: Dict[str, Any] = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            body["params"] = params
        r = self._http.post("/mcp/", json=body, headers=self._headers)
        assert r.status_code == 200, f"{method} failed: {r.status_code} {r.text}"
        return _parse_sse(r.text)

    def call_tool(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        return self.call("tools/call", {"name": name, "arguments": arguments})


# ---------------------------------------------------------------- fixtures


@pytest.fixture
def fake_pool(monkeypatch):
    """Install a FakePool and bypass FastMCP's DNS-rebinding host check.

    Yields the raw _Pool so tests can script its cursor.
    """
    monkeypatch.setenv(
        "DATABASE_URI",
        "teradata://demo_user:demo_user@localhost:1025/demo_user",
    )
    monkeypatch.setenv("SEMANTIC_MCP_DISABLE_HOST_CHECK", "1")
    from semantic_catalog import db as db_module
    pool = _Pool()
    monkeypatch.setattr(db_module, "_pool_singleton", pool)
    return pool


@pytest.fixture
def mcp(fake_pool):
    """Spin up the FastAPI app + a connected MCPClient."""
    from semantic_catalog.server import create_app
    app = create_app()
    with TestClient(app) as http:
        yield _MCPClient(http), fake_pool


# ---------------------------------------------------------------- tests


def test_initialize_returns_server_info(fake_pool):
    from semantic_catalog.server import create_app
    app = create_app()
    with TestClient(app) as http:
        r = http.post("/mcp/", json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "t", "version": "0"},
            },
        }, headers=_HEADERS)
        assert r.status_code == 200
        body = _parse_sse(r.text)
        assert body["result"]["serverInfo"]["name"] == "semantic-catalog"
        assert "tools" in body["result"]["capabilities"]


def test_tools_list_returns_five_named_tools(mcp):
    client, _ = mcp
    body = client.call("tools/list")
    names = {t["name"] for t in body["result"]["tools"]}
    assert names == {
        "semantic_search", "semantic_describe", "semantic_compile",
        "semantic_execute", "semantic_export_osi",
    }


def test_search_tool_calls_m_semantic_search(mcp):
    client, pool = mcp
    pool.cur.script(
        [("METRIC", "revenue", "tpch", "sum of price", None, 5)],
        cols=["entity_type", "entity_name", "parent_name",
              "description", "synonyms", "relevance"],
    )
    body = client.call_tool("semantic_search", {"term": "revenue"})
    inner = body["result"]["structuredContent"]["result"]
    assert inner["count"] == 1
    assert inner["hits"][0]["entity_name"] == "revenue"
    assert any("m_semantic_search" in sql for sql, _ in pool.cur.calls)


def test_search_tool_rejects_missing_term(mcp):
    client, _ = mcp
    body = client.call_tool("semantic_search", {})
    # Missing required arg → MCP returns isError + content describing the
    # validation failure (Pydantic error from FastMCP arg parsing).
    assert body["result"]["isError"] is True


def test_describe_tool_round_trip(mcp):
    client, pool = mcp
    pool.cur.script(
        [(1, "name", "revenue"), (2, "type", "SIMPLE")],
        cols=["attr_ordinal", "attr_key", "attr_value"],
    )
    body = client.call_tool("semantic_describe", {
        "entity_type": "METRIC", "entity_name": "revenue",
    })
    inner = body["result"]["structuredContent"]["result"]
    assert inner["entity_name"] == "revenue"
    assert len(inner["attributes"]) == 2


def test_export_osi_tool_passthrough(mcp, monkeypatch):
    client, _ = mcp
    called: Dict[str, Any] = {}

    def _fake(cur, db, model_name):
        called["db"], called["model"] = db, model_name
        return "version: '0.1.1'\nsemantic_model:\n- name: x\n"

    monkeypatch.setattr("semantic_catalog.services.export_osi_yaml", _fake)
    body = client.call_tool("semantic_export_osi", {"model": "x"})
    inner = body["result"]["structuredContent"]["result"]
    assert "version" in inner["yaml"]
    assert called["model"] == "x"


def test_compile_tool_surfaces_compile_errors(mcp):
    client, pool = mcp
    # Simulate UnknownModel: model lookup returns no rows.
    pool.cur.script([], cols=["model_id"])
    body = client.call_tool("semantic_compile", {
        "request": {"model": "ghost", "metrics": ["x"]},
    })
    inner = body["result"]["structuredContent"]["result"]
    assert inner["ok"] is False
    assert inner["code"] == "UNKNOWN_MODEL"


def test_unknown_model_returns_structured_suggestions(mcp):
    """UNKNOWN_MODEL must include available_models + suggestions in details
    so the agent can recover without re-prompting the user."""
    client, pool = mcp
    # Three scripted result sets in order:
    # 1. services.run_query → catalog.resolve_model_id (returns None)
    # 2. resolver.resolve   → catalog.resolve_model_id (still None → raises)
    # 3. resolver           → catalog.list_model_names (suggestions)
    pool.cur.script([], cols=["model_id"])
    pool.cur.script([], cols=["model_id"])
    pool.cur.script(
        [("tpch_orders",), ("tpcds_retail",)], cols=["model_name"],
    )
    body = client.call_tool("semantic_compile", {
        "request": {"model": "tpch_order", "metrics": ["x"]},  # near-miss
    })
    inner = body["result"]["structuredContent"]["result"]
    assert inner["ok"] is False
    assert inner["code"] == "UNKNOWN_MODEL"
    details = inner["details"] or {}
    assert details.get("available_models") == ["tpch_orders", "tpcds_retail"]
    # Levenshtein-style fuzzy: "tpch_order" → "tpch_orders"
    assert "tpch_orders" in (details.get("suggestions") or [])


def test_describe_dataset_includes_relationship_hints(mcp):
    """For DATASET entities, describe must surface a structured
    relationships[] array with the canonical disambiguation prefix."""
    client, pool = mcp
    # m_semantic_describe → text attributes
    pool.cur.script(
        [(1, "name", "part"), (2, "type", "DIM")],
        cols=["attr_ordinal", "attr_key", "attr_value"],
    )
    # _load_dataset_relationships → two incoming edges to part
    pool.cur.script(
        [
            (101, "lineitem_to_part",  None, "MANY_TO_ONE", "incoming", "lineitem"),
            (102, "partsupp_to_part",  None, "MANY_TO_ONE", "incoming", "partsupp"),
        ],
        cols=["relationship_id", "relationship_name", "role_name",
              "cardinality", "direction", "other_dataset"],
    )
    body = client.call_tool("semantic_describe", {
        "entity_type": "DATASET", "entity_name": "part",
    })
    inner = body["result"]["structuredContent"]["result"]
    rels = inner["relationships"]
    assert rels is not None and len(rels) == 2
    # `prefix` is what the parser will accept; with no role_name set,
    # falls back to relationship_name — exactly what AMBIGUOUS_PATH
    # advertises.
    prefixes = [r["prefix"] for r in rels]
    assert "lineitem_to_part" in prefixes
    assert "partsupp_to_part" in prefixes
    # All other fields populated.
    rel = rels[0]
    assert rel["direction"] in {"incoming", "outgoing"}
    assert rel["other_dataset"] in {"lineitem", "partsupp"}
    assert rel["cardinality"] == "MANY_TO_ONE"
    assert rel["relationship_id"] in {101, 102}


def test_describe_non_dataset_omits_relationships(mcp):
    """METRIC / VIEW / FIELD describes don't run the relationship query."""
    client, pool = mcp
    pool.cur.script(
        [(1, "name", "revenue")],
        cols=["attr_ordinal", "attr_key", "attr_value"],
    )
    body = client.call_tool("semantic_describe", {
        "entity_type": "METRIC", "entity_name": "revenue",
    })
    inner = body["result"]["structuredContent"]["result"]
    assert inner["relationships"] is None


def test_tools_list_publishes_typed_compile_schema(mcp):
    """semantic_compile.inputSchema must declare the QueryRequest fields
    so agents see the exact shape (model, metrics, dimensions, ...) and
    don't have to guess."""
    client, _ = mcp
    body = client.call("tools/list")
    by_name = {t["name"]: t for t in body["result"]["tools"]}
    schema = by_name["semantic_compile"]["inputSchema"]
    # The argument is a single ``request`` parameter typed as QueryRequest.
    props = schema.get("properties", {})
    assert "request" in props
    # Pydantic schemas live under $defs and are referenced via $ref.
    defs = schema.get("$defs", {}) or schema.get("definitions", {})
    assert "QueryRequest" in defs
    qr_props = defs["QueryRequest"]["properties"]
    for required_field in ("model", "metrics", "dimensions",
                           "where", "having", "sort", "limit"):
        assert required_field in qr_props, f"missing {required_field}"
    # Same for execute tool — same schema.
    assert "QueryRequest" in (
        by_name["semantic_execute"].get("inputSchema", {}).get("$defs", {})
        or by_name["semantic_execute"].get("inputSchema", {}).get("definitions", {})
    )


def test_bearer_token_enforced_when_env_set(monkeypatch):
    """When SEMANTIC_API_TOKEN is set, /mcp/* needs the right bearer."""
    monkeypatch.setenv(
        "DATABASE_URI",
        "teradata://demo_user:demo_user@localhost:1025/demo_user",
    )
    monkeypatch.setenv("SEMANTIC_MCP_DISABLE_HOST_CHECK", "1")
    monkeypatch.setenv("SEMANTIC_MCP_TOKEN", "s3cret")
    from semantic_catalog import db as db_module
    monkeypatch.setattr(db_module, "_pool_singleton", _Pool())
    from semantic_catalog.server import create_app
    app = create_app()
    init = {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "t", "version": "0"},
        },
    }
    with TestClient(app) as http:
        # Missing header → 401
        r = http.post("/mcp/", json=init, headers=_HEADERS)
        assert r.status_code == 401, r.text
        # Wrong token → 403
        r = http.post("/mcp/", json=init,
                      headers={**_HEADERS, "Authorization": "Bearer wrong"})
        assert r.status_code == 403, r.text
        # Correct token → 200
        r = http.post("/mcp/", json=init,
                      headers={**_HEADERS, "Authorization": "Bearer s3cret"})
        assert r.status_code == 200, r.text
