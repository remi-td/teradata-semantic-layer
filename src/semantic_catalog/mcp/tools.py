"""Pure-Python tool implementations.

Each function here is the actual semantic-catalog operation surfaced as
an MCP tool. They are independent of any transport: they take typed
arguments, talk to the connection pool, and return JSON-serialisable
dicts. The FastMCP server in ``server.py`` registers these directly
with ``@mcp.tool()`` so the same code path serves every MCP client.

Errors are raised as ``ValueError`` (validation) or propagate from the
underlying compiler/exporter. FastMCP turns these into proper JSON-RPC
error responses for the client.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from ..compiler import DbCatalog, compile as py_compile, render
from ..compiler.errors import CompileError
from ..compiler.request import from_mapping as _to_compile_request
from ..db import get_pool
from ..exporter import export_osi_yaml


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


def semantic_search(
    term: str,
    model: Optional[str] = None,
    limit: int = 50,
) -> Dict[str, Any]:
    """Full-text search across the catalog.

    Searches dataset / metric / view names, descriptions, and AI synonyms.
    Returns a ranked list of hits scoped to ``model`` when given.
    """
    if not term:
        raise ValueError("term is required")
    db = _db_name()
    with get_pool().cursor() as cur:
        if model:
            cur.execute(f"CALL {db}.sp_semantic_search(?, ?)", (term, model))
        else:
            cur.execute(f"CALL {db}.sp_semantic_search(?, NULL)", (term,))
        rows = cur.fetchall() or []
        cols = [d[0] for d in cur.description or []]
    hits = [dict(zip(cols, r)) for r in rows[:limit]]
    return {"hits": hits, "count": len(hits)}


def semantic_describe(
    entity_type: str,
    entity_name: str,
    model: Optional[str] = None,
) -> Dict[str, Any]:
    """Full metadata for one catalog entity.

    Returns ``(attr_ordinal, attr_key, attr_value)`` triples covering
    description, AI context, format spec, fields/expressions, etc.
    """
    if not entity_type or not entity_name:
        raise ValueError("entity_type and entity_name are required")
    db = _db_name()
    with get_pool().cursor() as cur:
        params = (entity_type, entity_name, model) if model else (entity_type, entity_name, None)
        cur.execute(f"CALL {db}.sp_semantic_describe(?, ?, ?)", params)
        rows = cur.fetchall() or []
        cols = [d[0] for d in cur.description or []]
    return {
        "entity_type": entity_type,
        "entity_name": entity_name,
        "attributes": [dict(zip(cols, r)) for r in rows],
    }


def semantic_compile(request: Dict[str, Any]) -> Dict[str, Any]:
    """Compile a structured query request to Teradata SQL.

    The ``request`` mapping mirrors the REST `/api/query/compile` body:
    ``{"model": ..., "metrics": [...], "dimensions": [...], "where": [...], "having": [...], "sort": [...], "limit": N}``.
    """
    if not isinstance(request, dict):
        raise ValueError("request must be a JSON object")
    req = _to_compile_request(request)
    db = _db_name()
    with get_pool().cursor() as cur:
        catalog = DbCatalog(cur, catalog_db=db)
        try:
            plan = py_compile(req, catalog)
        except CompileError as e:
            return {"ok": False, "code": e.code, "message": e.message,
                    "details": e.details}
        sql = render(plan)
    return {
        "ok": True,
        "sql": sql,
        "anchor": plan.anchor.dataset_name if plan.anchor else None,
        "joined_datasets": plan.joined_datasets,
        "is_valid": 0 if plan.chasm_warning or plan.unresolved else 1,
        "warning": plan.chasm_warning,
        "unresolved": plan.unresolved,
    }


def semantic_execute(request: Dict[str, Any]) -> Dict[str, Any]:
    """Compile and execute a query request, returning up to 500 rows."""
    if not isinstance(request, dict):
        raise ValueError("request must be a JSON object")
    req = _to_compile_request(request)
    db = _db_name()
    with get_pool().cursor() as cur:
        catalog = DbCatalog(cur, catalog_db=db)
        try:
            plan = py_compile(req, catalog)
        except CompileError as e:
            return {"ok": False, "code": e.code, "message": e.message}
        if plan.unresolved:
            return {"ok": False, "code": "UNRESOLVED_JOIN",
                    "message": f"Unresolved datasets: {plan.unresolved}"}
        if plan.chasm_warning:
            return {"ok": False, "code": "CHASM_TRAP",
                    "message": plan.chasm_warning}
        sql = render(plan)
        cur.execute(sql)
        cols = [d[0] for d in (cur.description or [])]
        rows = [list(r) for r in (cur.fetchall() or [])[:500]]
    return {
        "ok": True,
        "sql": sql,
        "columns": cols,
        "rows": rows,
        "row_count": len(rows),
    }


def semantic_export_osi(model: str) -> Dict[str, Any]:
    """Export a semantic model as OSI 0.1.x YAML."""
    if not model:
        raise ValueError("model is required")
    db = _db_name()
    with get_pool().cursor() as cur:
        text = export_osi_yaml(cur, db, model)
    if text is None:
        raise ValueError(f"Unknown model: {model}")
    return {"model": model, "yaml": text}


__all__ = [
    "semantic_search",
    "semantic_describe",
    "semantic_compile",
    "semantic_execute",
    "semantic_export_osi",
]
