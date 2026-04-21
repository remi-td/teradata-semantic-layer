"""Query builder + execution endpoints.

Two compile engines are available:

* ``engine=python`` (default from v0.3) — the pure-Python compiler in
  ``semantic_catalog.compiler``. Uses sqlglot for dialect rendering,
  does resolution + joins + metric-in-metric composition in-process,
  then executes against Teradata via the pooled teradatasql cursor.

* ``engine=sql`` — the legacy ``sp_semantic_request`` stored procedure.
  Retained for one release (v0.3) for parity testing and rollback;
  **scheduled for removal in v0.4.** A deprecation header is attached
  when this path is taken.
"""
from __future__ import annotations

import logging
from decimal import Decimal
from datetime import date, datetime
from typing import Any, List, Literal, Optional

from fastapi import APIRouter, HTTPException, Query

from ..db import get_pool
from ..compiler import DbCatalog, compile as py_compile, render
from ..compiler.errors import CompileError
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


Engine = Literal["python", "sql"]


# ---- legacy SP path: value encoding for the packed-string params ----

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
            if f.type and f.type.upper() == "RAW" and f.value is not None:
                rhs = str(f.value)
            elif f.values:
                rhs = _encode_in(f.values)
            else:
                raise HTTPException(400, f"IN filter on {f.field!r} missing 'values'")
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
def compile_query(req: QueryRequest, engine: Engine = Query("python")):
    return _compile_and_maybe_execute(req, execute=False, engine=engine)


@router.post("/execute", response_model=QueryResponse)
def execute_query(req: QueryRequest, engine: Engine = Query("python")):
    return _compile_and_maybe_execute(req, execute=True, engine=engine)


def _compile_and_maybe_execute(req: QueryRequest, *, execute: bool,
                               engine: Engine) -> QueryResponse:
    if engine == "python":
        return _compile_python(req, execute=execute)
    return _compile_sql(req, execute=execute)


def _compile_python(req: QueryRequest, *, execute: bool) -> QueryResponse:
    """Default engine — Python compiler over DbCatalog."""
    db = _db_name()
    compile_sql: Optional[str] = None
    is_valid: Optional[int] = None
    validation_msg: Optional[str] = None
    anchor: Optional[str] = None
    joined: Optional[str] = None
    execution: Optional[QueryExecution] = None

    with get_pool().cursor() as cur:
        catalog = DbCatalog(cur, catalog_db=db)
        try:
            plan = py_compile(req, catalog)
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


def _compile_sql(req: QueryRequest, *, execute: bool) -> QueryResponse:
    """Legacy engine — sp_semantic_request stored procedure.

    DEPRECATED: scheduled for removal in v0.4. Use engine=python (default).
    """
    db = _db_name()
    p_metrics = ",".join(req.metrics)
    p_dims    = ",".join(req.dimensions)
    p_where   = _pack_where(req.where)
    p_having  = _pack_having(req.having)
    p_sort    = _pack_sort(req.sort)
    p_limit   = int(req.limit or 0)

    compile_sql = None
    is_valid = None
    validation_msg: Optional[str] = "[DEPRECATED engine=sql; use engine=python]"
    anchor = None
    joined = None
    execution: Optional[QueryExecution] = None

    with get_pool().cursor() as cur:
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
            extra          = r[2] or ""
            validation_msg = (validation_msg + (" | " + extra if extra else "")).strip(" |")
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


@router.post("/explain", response_model=ExplainResponse)
def explain(req: ExplainRequest):
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
