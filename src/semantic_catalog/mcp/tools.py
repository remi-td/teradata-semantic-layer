"""MCP tool adapters.

Every tool here is a thin wrapper that delegates to
``semantic_catalog.services``. The service layer is shared with the
REST API (``api/*``) so search, describe, compile, execute, and OSI
export run through exactly one code path regardless of transport.

Validation errors raise ``ValueError``; FastMCP turns these into
JSON-RPC error responses for the client.
"""
from __future__ import annotations

from dataclasses import asdict
from typing import Any, Dict, Optional

from .. import services


def semantic_search(
    term: str,
    model: Optional[str] = None,
    limit: int = 50,
) -> Dict[str, Any]:
    """Full-text search across the catalog."""
    hits = services.search_catalog(term=term, model=model, limit=limit)
    return {
        "hits": [asdict(h) for h in hits],
        "count": len(hits),
    }


def semantic_describe(
    entity_type: str,
    entity_name: str,
    model: Optional[str] = None,
) -> Dict[str, Any]:
    """Full metadata pack for one catalog entity."""
    try:
        result = services.describe_entity(
            entity_type=entity_type, entity_name=entity_name, model=model,
        )
    except services.EntityNotFound as e:
        raise ValueError(str(e))
    return {
        "entity_type": result.entity_type,
        "entity_name": result.entity_name,
        "model_name": result.model_name,
        "attributes": [asdict(a) for a in result.attributes],
        "relationships": (
            [asdict(h) for h in result.relationships]
            if result.relationships is not None
            else None
        ),
    }


def semantic_compile(request: Dict[str, Any]) -> Dict[str, Any]:
    """Compile a structured query request to Teradata SQL."""
    if not isinstance(request, dict):
        raise ValueError("request must be a JSON object")
    res = services.run_query(request=request, execute=False)
    if res.error_code:
        return {
            "ok": False,
            "code": res.error_code,
            "message": res.validation_message,
            "details": res.error_details,
        }
    return {
        "ok": True,
        "sql": res.compiled_sql,
        "anchor": res.anchor_dataset,
        "joined_datasets": res.joined_datasets or [],
        "is_valid": res.is_valid,
        "warning": res.validation_message if res.is_valid == 0 else None,
        "unresolved": res.unresolved,
    }


def semantic_execute(request: Dict[str, Any]) -> Dict[str, Any]:
    """Compile and execute a query request, returning up to 500 rows."""
    if not isinstance(request, dict):
        raise ValueError("request must be a JSON object")
    res = services.run_query(request=request, execute=True)
    if res.error_code:
        return {
            "ok": False,
            "code": res.error_code,
            "message": res.validation_message,
        }
    if res.unresolved:
        return {
            "ok": False,
            "code": "UNRESOLVED_JOIN",
            "message": res.validation_message,
        }
    if res.is_valid == 0:
        return {
            "ok": False,
            "code": "CHASM_TRAP",
            "message": res.validation_message,
        }
    exe = res.execution
    return {
        "ok": True,
        "sql": res.compiled_sql,
        "columns": exe.columns if exe else [],
        "rows": exe.rows if exe else [],
        "row_count": exe.row_count if exe else 0,
    }


def semantic_export_osi(model: str) -> Dict[str, Any]:
    """Export a semantic model as OSI 0.1.x YAML."""
    try:
        text = services.export_osi_for_model(model_name=model)
    except services.EntityNotFound as e:
        raise ValueError(str(e))
    return {"model": model, "yaml": text}


__all__ = [
    "semantic_search",
    "semantic_describe",
    "semantic_compile",
    "semantic_execute",
    "semantic_export_osi",
]
