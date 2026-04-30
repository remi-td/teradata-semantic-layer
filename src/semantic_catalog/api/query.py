"""Query builder + execution endpoints.

Thin transport layer over ``semantic_catalog.services.run_query`` —
that function is the single source of truth for the compile/execute
pipeline (also used by the MCP tool surface).
"""
from __future__ import annotations

import logging
from typing import List, Optional

from fastapi import APIRouter, Header, HTTPException

from ..db import get_pool
from .. import services
from .models import (
    ExplainRequest,
    ExplainResponse,
    QueryExecution,
    QueryRequest,
    QueryResponse,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/query", tags=["query"])


def _parse_groups(header: Optional[str]) -> List[str]:
    """Parse the X-Semantic-Groups header into a list of group names.

    Accepts a comma-separated string (trimmed, empties dropped). Absent
    header → empty list, which means 'only global (NULL group_name)
    policies apply'. Never raises: malformed input is silently dropped.
    """
    if not header:
        return []
    return [g.strip() for g in header.split(",") if g.strip()]


def _to_response(res: services.QueryResult) -> QueryResponse:
    execution = None
    if res.execution:
        execution = QueryExecution(
            columns=res.execution.columns,
            rows=res.execution.rows,
            row_count=res.execution.row_count,
            truncated=res.execution.truncated,
        )
    joined = ", ".join(res.joined_datasets) if res.joined_datasets else None
    return QueryResponse(
        compiled_sql=res.compiled_sql,
        is_valid=res.is_valid,
        validation_message=res.validation_message,
        anchor_dataset=res.anchor_dataset,
        joined_datasets=joined,
        execution=execution,
    )


# ---- endpoints ----

@router.post("/compile", response_model=QueryResponse)
def compile_query(req: QueryRequest,
                  x_semantic_groups: Optional[str] = Header(default=None)):
    res = services.run_query(
        request=req, execute=False, groups=_parse_groups(x_semantic_groups),
    )
    return _to_response(res)


@router.post("/execute", response_model=QueryResponse)
def execute_query(req: QueryRequest,
                  x_semantic_groups: Optional[str] = Header(default=None)):
    res = services.run_query(
        request=req, execute=True, groups=_parse_groups(x_semantic_groups),
    )
    return _to_response(res)


_EXPLAIN_LEAD = ("select", "with", "locking")
_EXPLAIN_FORBIDDEN = ("insert ", "update ", "delete ", "merge ",
                     "create ", "drop ", "alter ", "grant ", "revoke ",
                     "replace ", "call ", "exec ", "execute ")


@router.post("/explain", response_model=ExplainResponse)
def explain(req: ExplainRequest):
    """Run EXPLAIN on a read-only statement.

    Security posture: this endpoint executes EXPLAIN on caller-supplied
    SQL, so we gate it tightly — single statement, must start with a
    read-only verb, no DDL/DML keywords anywhere. Internal server errors
    are logged but not echoed back to the caller.
    """
    sql = (req.sql or "").strip()
    while sql.endswith(";"):
        sql = sql[:-1].rstrip()
    if not sql:
        raise HTTPException(400, "sql is required")
    # reject multi-statement submissions
    if ";" in sql:
        raise HTTPException(400, "only a single statement is allowed")
    normalised = sql.lower()
    if not normalised.startswith(_EXPLAIN_LEAD):
        raise HTTPException(
            400, "only SELECT / WITH / LOCKING statements may be EXPLAINed"
        )
    if any(kw in normalised for kw in _EXPLAIN_FORBIDDEN):
        raise HTTPException(400, "DDL/DML keywords are not permitted")

    lines: List[str] = []
    try:
        with get_pool().cursor() as cur:
            cur.execute(f"EXPLAIN {sql}")
            for r in cur.fetchall() or []:
                lines.append(str(r[0]))
    except Exception:  # noqa: BLE001
        log.exception("explain failed")
        return ExplainResponse(plan="", ok=False, message="EXPLAIN failed; see server log")
    return ExplainResponse(plan="\n".join(lines), ok=True, message=None)
