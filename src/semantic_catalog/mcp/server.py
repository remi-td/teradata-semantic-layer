"""MCP-compatible tool endpoints.

Protocol shape:

    GET  /mcp/tools                    → list tool schemas
    POST /mcp/tools/{name}             → invoke tool, args in JSON body

Auth: when the ``SEMANTIC_MCP_TOKEN`` environment variable is set, every
request must carry ``Authorization: Bearer <token>``. When unset, no
auth is applied (dev default — safe because localhost-only in the
default uvicorn bind).

We deliberately don't pull the ``mcp`` SDK as a hard dependency. The
endpoints speak plain JSON so an MCP bridge can wrap them, and they
also stand on their own as a REST API for agents that aren't MCP-aware.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException

from ..api.models import QueryRequest
from ..auth import require_token
from ..compiler import DbCatalog, compile as py_compile, render
from ..compiler.errors import CompileError
from ..db import get_pool
from ..exporter import export_osi_yaml

log = logging.getLogger(__name__)


# -- tool schemas -----------------------------------------------------

TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {
        "name": "semantic.search",
        "description": (
            "Full-text search across the catalog: dataset/metric/view "
            "names, descriptions, AI synonyms. Returns ranked hits."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "term":  {"type": "string"},
                "model": {"type": ["string", "null"]},
                "limit": {"type": "integer", "default": 50},
            },
            "required": ["term"],
        },
    },
    {
        "name": "semantic.describe",
        "description": (
            "Full metadata for one entity: dataset / metric / view / field. "
            "Returns (attr_ordinal, attr_key, attr_value) triples."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "entity_type": {"type": "string",
                                "enum": ["DATASET", "METRIC", "VIEW", "FIELD", "MODEL"]},
                "entity_name": {"type": "string"},
                "model":       {"type": ["string", "null"]},
            },
            "required": ["entity_type", "entity_name"],
        },
    },
    {
        "name": "semantic.compile",
        "description": (
            "Compile a structured query request to Teradata SQL. Returns "
            "the compiled SQL plus anchor/joined datasets and validity."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "request": {"type": "object"},
            },
            "required": ["request"],
        },
    },
    {
        "name": "semantic.execute",
        "description": (
            "Compile and execute a query request, returning up to 500 rows."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "request": {"type": "object"},
            },
            "required": ["request"],
        },
    },
    {
        "name": "semantic.export_osi",
        "description": "Export a semantic model as OSI 0.1.x YAML.",
        "input_schema": {
            "type": "object",
            "properties": {
                "model": {"type": "string"},
            },
            "required": ["model"],
        },
    },
]


router = APIRouter(prefix="/mcp", tags=["mcp"], dependencies=[Depends(require_token)])


# -- helpers ----------------------------------------------------------

def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


# -- endpoints --------------------------------------------------------

@router.get("/tools")
def list_tools() -> Dict[str, Any]:
    return {"tools": TOOL_SCHEMAS}


@router.post("/tools/semantic.search")
def tool_search(args: Dict[str, Any]) -> Dict[str, Any]:
    term = (args or {}).get("term")
    if not term:
        raise HTTPException(400, "term is required")
    model = (args or {}).get("model")
    limit = int((args or {}).get("limit") or 50)
    db = _db_name()
    with get_pool().cursor() as cur:
        if model:
            cur.execute(
                f"CALL {db}.sp_semantic_search(?, ?)",
                (term, model),
            )
        else:
            cur.execute(
                f"CALL {db}.sp_semantic_search(?, NULL)",
                (term,),
            )
        rows = cur.fetchall() or []
        cols = [d[0] for d in cur.description or []]
    hits = [dict(zip(cols, r)) for r in rows[:limit]]
    return {"hits": hits, "count": len(hits)}


@router.post("/tools/semantic.describe")
def tool_describe(args: Dict[str, Any]) -> Dict[str, Any]:
    et = (args or {}).get("entity_type")
    en = (args or {}).get("entity_name")
    model = (args or {}).get("model")
    if not (et and en):
        raise HTTPException(400, "entity_type and entity_name are required")
    db = _db_name()
    with get_pool().cursor() as cur:
        params = (et, en, model) if model else (et, en, None)
        cur.execute(f"CALL {db}.sp_semantic_describe(?, ?, ?)", params)
        rows = cur.fetchall() or []
        cols = [d[0] for d in cur.description or []]
    return {
        "entity_type": et,
        "entity_name": en,
        "attributes": [dict(zip(cols, r)) for r in rows],
    }


@router.post("/tools/semantic.compile")
def tool_compile(args: Dict[str, Any]) -> Dict[str, Any]:
    request_payload = (args or {}).get("request")
    if not isinstance(request_payload, dict):
        raise HTTPException(400, "request must be a mapping")
    req = QueryRequest.model_validate(request_payload)
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


@router.post("/tools/semantic.execute")
def tool_execute(args: Dict[str, Any]) -> Dict[str, Any]:
    request_payload = (args or {}).get("request")
    if not isinstance(request_payload, dict):
        raise HTTPException(400, "request must be a mapping")
    req = QueryRequest.model_validate(request_payload)
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


@router.post("/tools/semantic.export_osi")
def tool_export_osi(args: Dict[str, Any]) -> Dict[str, Any]:
    model = (args or {}).get("model")
    if not model:
        raise HTTPException(400, "model is required")
    db = _db_name()
    with get_pool().cursor() as cur:
        text = export_osi_yaml(cur, db, model)
    if text is None:
        raise HTTPException(404, f"Unknown model: {model}")
    return {"model": model, "yaml": text}
