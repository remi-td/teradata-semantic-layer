"""Query builder + execution endpoints.

The compiler is pure Python — resolution, join planning, and sqlglot
rendering all run in-process in ``semantic_catalog.compiler``. The
legacy ``engine=sql`` path (stored-procedure ``sp_semantic_request``)
was removed in v0.4; the macro is no longer deployed.
"""
from __future__ import annotations

import logging
from decimal import Decimal
from datetime import date, datetime
from typing import Any, List, Optional

from fastapi import APIRouter, HTTPException

from ..db import get_pool
from ..compiler import DbCatalog, compile as py_compile, render
from ..compiler.errors import CompileError
from ..compiler.request import from_mapping as _to_compile_request
from .models import (
    ExplainRequest,
    ExplainResponse,
    QueryExecution,
    QueryRequest,
    QueryResponse,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/query", tags=["query"])


# ---- result normalisation ----

def _normalise(v: Any) -> Any:
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


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


# ---- endpoints ----

@router.post("/compile", response_model=QueryResponse)
def compile_query(req: QueryRequest):
    return _compile_and_maybe_execute(req, execute=False)


@router.post("/execute", response_model=QueryResponse)
def execute_query(req: QueryRequest):
    return _compile_and_maybe_execute(req, execute=True)


def _compile_and_maybe_execute(req: QueryRequest, *, execute: bool) -> QueryResponse:
    """Default engine — Python compiler over DbCatalog."""
    db = _db_name()
    compile_sql: Optional[str] = None
    is_valid: Optional[int] = None
    validation_msg: Optional[str] = None
    anchor: Optional[str] = None
    joined: Optional[str] = None
    execution: Optional[QueryExecution] = None

    compile_req = _to_compile_request(req)

    with get_pool().cursor() as cur:
        catalog = DbCatalog(cur, catalog_db=db)
        try:
            plan = py_compile(compile_req, catalog)
        except CompileError as e:
            return QueryResponse(
                compiled_sql=None, is_valid=0,
                validation_message=f"{e.code}: {e.message}",
                anchor_dataset=None, joined_datasets=None, execution=None,
            )

        compile_sql = render(plan)
        anchor = plan.anchor.dataset_name if plan.anchor else None
        joined = ", ".join(plan.joined_datasets) if plan.joined_datasets else None
        validation_msg = plan.chasm_warning or None

        # Plan-level validity: if something is unresolved or chasm warns,
        # mark invalid so the caller is forced to acknowledge.
        if plan.unresolved:
            validation_msg = (
                f"Could not resolve join path for datasets: "
                f"{', '.join(plan.unresolved)}"
            )
            is_valid = 0
        elif plan.chasm_warning:
            is_valid = 0
        else:
            is_valid = 1

        if execute and compile_sql and is_valid == 1:
            try:
                cur.execute(compile_sql)
                cols = [d[0] for d in (cur.description or [])]
                all_rows = cur.fetchall() or []
                cap = 500
                trunc = len(all_rows) > cap
                rows = [[_normalise(v) for v in row] for row in all_rows[:cap]]
                execution = QueryExecution(
                    columns=cols, rows=rows, row_count=len(all_rows), truncated=trunc,
                )
            except Exception as e:  # noqa: BLE001
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
