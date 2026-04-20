"""Query builder + execution endpoints.

Wraps ``demo_user.sp_semantic_request`` and the ``request_result`` staging
table, then optionally runs the compiled SQL and returns rows. EXPLAIN is
exposed separately for dry-plan inspection.
"""
from __future__ import annotations

import logging
from decimal import Decimal
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException

from ..db import get_pool
from .models import (
    ExplainRequest,
    ExplainResponse,
    QueryExecution,
    QueryFilter,
    QueryRequest,
    QueryResponse,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/query", tags=["query"])


# --------------------------------------------------------- value encoding

def _quote_string(s: str) -> str:
    return "'" + str(s).replace("'", "''") + "'"


def _encode_value(value: Any, type_hint: Optional[str] = None) -> str:
    if type_hint:
        th = type_hint.upper()
        if th == "DATE":
            return "DATE " + _quote_string(str(value))
        if th == "NUMBER":
            return str(value)
        if th == "RAW":
            return str(value)
        return _quote_string(str(value))
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float, Decimal)):
        return str(value)
    return _quote_string(str(value))


def _encode_in(values: List[Any]) -> str:
    return "(" + ",".join(_encode_value(v) for v in values) + ")"


def _pack_where(filters: List[QueryFilter]) -> str:
    parts: List[str] = []
    for f in filters:
        if f.field is None:
            raise HTTPException(400, "where filter missing 'field'")
        if f.op.upper() == "IN":
            if not f.values:
                raise HTTPException(400, f"IN filter on {f.field!r} missing 'values'")
            rhs = _encode_in(f.values)
        else:
            rhs = _encode_value(f.value, f.type)
        parts.append(f"{f.field}|{f.op}|{rhs}")
    return ";".join(parts)


def _pack_having(filters: List[QueryFilter]) -> str:
    parts: List[str] = []
    for f in filters:
        if f.metric is None:
            raise HTTPException(400, "having filter missing 'metric'")
        rhs = _encode_value(f.value, f.type)
        parts.append(f"{f.metric}|{f.op}|{rhs}")
    return ";".join(parts)


def _pack_sort(items) -> str:
    return ",".join(f"{s.field} {s.direction.upper()}" for s in items)


# -------------------------------------------------------------- normalisation

def _normalise(v: Any) -> Any:
    """Convert Teradata scalar types to JSON-friendly values."""
    if v is None:
        return None
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (date, datetime)):
        return v.isoformat()
    if isinstance(v, bytes):
        try:
            return v.decode("utf-8", errors="replace")
        except Exception:
            return v.hex()
    if isinstance(v, str):
        return v.rstrip() if v.endswith(" ") else v
    return v


# ------------------------------------------------------------ endpoints

def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


@router.post("/compile", response_model=QueryResponse)
def compile_query(req: QueryRequest):
    return _compile_and_maybe_execute(req, execute=False)


@router.post("/execute", response_model=QueryResponse)
def execute_query(req: QueryRequest):
    return _compile_and_maybe_execute(req, execute=True)


def _compile_and_maybe_execute(req: QueryRequest, *, execute: bool) -> QueryResponse:
    db = _db_name()
    p_metrics = ",".join(req.metrics)
    p_dims    = ",".join(req.dimensions)
    p_where   = _pack_where(req.where)
    p_having  = _pack_having(req.having)
    p_sort    = _pack_sort(req.sort)
    p_limit   = int(req.limit or 0)

    compile_sql = None
    is_valid = None
    validation_msg = None
    anchor = None
    joined = None
    execution: Optional[QueryExecution] = None

    with get_pool().cursor() as cur:
        # CALL with OUT params returns a single-row result set containing
        # just the OUT values (not the IN echoes).
        cur.execute(
            f"CALL {db}.sp_semantic_request(?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                req.model, p_metrics, p_dims, p_where, p_having, p_sort, p_limit,
                None, None, None, None, None,
            ),
        )
        r = cur.fetchone()
        if r:
            compile_sql    = r[0]
            is_valid       = int(r[1]) if r[1] is not None else None
            validation_msg = r[2]
            anchor         = (str(r[3]).strip() if r[3] else None)
            joined         = (str(r[4]) if r[4] else None)

        if execute and compile_sql and is_valid == 1:
            try:
                cur.execute(compile_sql)
                cols = [d[0] for d in (cur.description or [])]
                all_rows = cur.fetchall() or []
                cap = 500
                trunc = len(all_rows) > cap
                rows = [[_normalise(v) for v in row] for row in all_rows[:cap]]
                execution = QueryExecution(
                    columns=cols, rows=rows, row_count=len(all_rows), truncated=trunc
                )
            except Exception as e:
                validation_msg = f"{validation_msg or ''} | EXECUTE_ERROR: {e}".strip(" |")
                is_valid = 0

    return QueryResponse(
        compiled_sql=compile_sql,
        is_valid=is_valid,
        validation_message=validation_msg,
        anchor_dataset=anchor,
        joined_datasets=joined,
        execution=execution,
    )


@router.post("/explain", response_model=ExplainResponse)
def explain(req: ExplainRequest):
    """Run EXPLAIN on arbitrary SQL and return the plan text."""
    sql = (req.sql or "").strip().rstrip(";")
    if not sql:
        raise HTTPException(400, "sql is required")
    lines: List[str] = []
    ok = True
    err: Optional[str] = None
    try:
        with get_pool().cursor() as cur:
            cur.execute(f"EXPLAIN {sql}")
            for r in cur.fetchall() or []:
                lines.append(str(r[0]))
    except Exception as e:
        ok = False
        err = str(e)
    return ExplainResponse(plan="\n".join(lines), ok=ok, message=err)
