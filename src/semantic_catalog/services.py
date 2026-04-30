"""Single source of truth for catalog operations.

Both the REST API (``api/*``) and the MCP tool surface (``mcp/tools.py``)
delegate to the functions here, so search, describe, compile, execute,
and OSI export are implemented exactly once. Each transport is a thin
adapter — Pydantic + HTTPException for REST, plain dicts + ValueError
for MCP — but the database access, RLS resolution, error mapping, and
result normalisation all live in this module.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from typing import Any, List, Mapping, Optional, Sequence, Union

from .compiler import DbCatalog, compile as py_compile, render
from .compiler.errors import CompileError
from .compiler.request import from_mapping as _to_compile_request
from .db import get_pool
from .exporter import export_osi_yaml

log = logging.getLogger(__name__)


class EntityNotFound(LookupError):
    """Raised by describe/export services when the target does not exist."""


@dataclass
class SearchHit:
    entity_type: str
    entity_name: str
    parent_name: Optional[str]
    description: Optional[str]
    synonyms: Optional[str]
    relevance: int


@dataclass
class DescribeAttr:
    attr_ordinal: int
    attr_key: str
    attr_value: str


@dataclass
class DescribeResult:
    entity_type: str
    entity_name: str
    model_name: Optional[str]
    attributes: List[DescribeAttr]


@dataclass
class ExecutionPayload:
    columns: List[str]
    rows: List[List[Any]]
    row_count: int
    truncated: bool


@dataclass
class QueryResult:
    compiled_sql: Optional[str] = None
    is_valid: int = 0
    validation_message: Optional[str] = None
    anchor_dataset: Optional[str] = None
    joined_datasets: Optional[List[str]] = None
    execution: Optional[ExecutionPayload] = None
    # Extras for callers that surface error codes (MCP).
    error_code: Optional[str] = None
    error_details: Optional[Any] = None
    unresolved: List[str] = field(default_factory=list)


def _db_name() -> str:
    from .config import load_settings
    return load_settings().catalog_db


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


def _short_err(e: BaseException, *, limit: int = 240) -> str:
    msg = str(e).strip() or e.__class__.__name__
    msg = " ".join(msg.split())
    if len(msg) > limit:
        msg = msg[: limit - 1] + "…"
    return f"{e.__class__.__name__}: {msg}"


# --- search ----------------------------------------------------------------


def search_catalog(
    *,
    term: str,
    model: Optional[str] = None,
    limit: int = 50,
) -> List[SearchHit]:
    if not term:
        raise ValueError("term is required")
    db = _db_name()
    out: List[SearchHit] = []
    with get_pool().cursor() as cur:
        cur.execute(f"EXEC {db}.m_semantic_search(?, ?)", (term, model))
        for r in (cur.fetchall() or [])[:limit]:
            out.append(SearchHit(
                entity_type=str(r[0]).strip(),
                entity_name=str(r[1]).strip(),
                parent_name=(str(r[2]).strip() if r[2] else None),
                description=(r[3] or None),
                synonyms=(str(r[4]) if r[4] else None),
                relevance=int(r[5] or 0),
            ))
    return out


# --- describe --------------------------------------------------------------


def describe_entity(
    *,
    entity_type: str,
    entity_name: str,
    model: Optional[str] = None,
) -> DescribeResult:
    if not entity_type or not entity_name:
        raise ValueError("entity_type and entity_name are required")
    db = _db_name()
    with get_pool().cursor() as cur:
        cur.execute(
            f"EXEC {db}.m_semantic_describe(?, ?, ?)",
            (entity_type.upper(), entity_name, model),
        )
        rows = cur.fetchall() or []
    attrs = [
        DescribeAttr(
            attr_ordinal=int(r[0]),
            attr_key=str(r[1]).strip(),
            attr_value=(str(r[2]) if r[2] is not None else ""),
        )
        for r in rows
    ]
    if not attrs:
        raise EntityNotFound(f"Unknown {entity_type} '{entity_name}'")
    return DescribeResult(
        entity_type=entity_type.upper(),
        entity_name=entity_name,
        model_name=model,
        attributes=attrs,
    )


# --- compile / execute -----------------------------------------------------


def run_query(
    *,
    request: Union[Mapping[str, Any], "QueryRequest"],  # noqa: F821 (forward)
    execute: bool,
    groups: Sequence[str] = (),
) -> QueryResult:
    """Compile (and optionally execute) a structured query.

    Mirrors the contract of ``/api/query/{compile,execute}``: takes either
    a raw mapping (the MCP transport) or a Pydantic ``QueryRequest`` (the
    REST transport), threads ``X-Semantic-Groups`` through the catalog's
    row-filter resolution, and returns a transport-neutral ``QueryResult``.
    """
    db = _db_name()
    try:
        compile_req = _to_compile_request(request)
    except (ValueError, KeyError, TypeError) as e:
        return QueryResult(
            is_valid=0,
            validation_message=f"INVALID_REQUEST: {e}",
            error_code="INVALID_REQUEST",
        )
    groups = list(groups)

    with get_pool().cursor() as cur:
        catalog = DbCatalog(cur, catalog_db=db)
        # Resolve RLS first so we can attach policy fragments before the
        # compiler sees the request. Failures are logged but never block —
        # the compiler will surface UNKNOWN_MODEL with a consistent shape
        # if the model itself is missing.
        try:
            model_id = catalog.resolve_model_id(compile_req.model)
        except Exception:  # noqa: BLE001
            model_id = None
        if model_id is not None:
            try:
                fragments = catalog.load_row_filters(model_id, groups)
            except Exception:  # noqa: BLE001
                log.exception("load_row_filters failed — proceeding without RLS")
                fragments = []
            if fragments:
                compile_req.policy_fragments = list(fragments)

        try:
            plan = py_compile(compile_req, catalog)
        except CompileError as e:
            return QueryResult(
                is_valid=0,
                validation_message=f"{e.code}: {e.message}",
                error_code=e.code,
                error_details=e.details,
            )
        except Exception as e:  # noqa: BLE001
            log.exception("compile failed unexpectedly")
            return QueryResult(
                is_valid=0,
                validation_message=f"INTERNAL: {_short_err(e)}",
                error_code="INTERNAL",
            )

        try:
            sql = render(plan)
        except Exception as e:  # noqa: BLE001
            log.exception("render failed for plan on model=%s", compile_req.model)
            return QueryResult(
                is_valid=0,
                validation_message=f"RENDER_ERROR: {_short_err(e)}",
                anchor_dataset=plan.anchor.dataset_name if plan.anchor else None,
                error_code="RENDER_ERROR",
            )

        anchor = plan.anchor.dataset_name if plan.anchor else None
        joined = list(plan.joined_datasets or []) or None
        unresolved = list(plan.unresolved or [])
        validation: Optional[str] = plan.chasm_warning or None
        if unresolved:
            validation = (
                f"Could not resolve join path for datasets: {', '.join(unresolved)}"
            )
            is_valid = 0
        elif plan.chasm_warning:
            is_valid = 0
        else:
            is_valid = 1

        execution: Optional[ExecutionPayload] = None
        if execute and is_valid == 1:
            try:
                cur.execute(sql)
                cols = [d[0] for d in (cur.description or [])]
                all_rows = cur.fetchall() or []
                cap = 500
                truncated = len(all_rows) > cap
                norm_rows = [[_normalise(v) for v in row] for row in all_rows[:cap]]
                execution = ExecutionPayload(
                    columns=cols, rows=norm_rows,
                    row_count=len(all_rows), truncated=truncated,
                )
            except Exception as e:  # noqa: BLE001
                validation = f"{validation or ''} | EXECUTE_ERROR: {e}".strip(" |")
                is_valid = 0

    return QueryResult(
        compiled_sql=sql,
        is_valid=is_valid,
        validation_message=validation,
        anchor_dataset=anchor,
        joined_datasets=joined,
        execution=execution,
        unresolved=unresolved,
    )


# --- export ----------------------------------------------------------------


def export_osi_for_model(*, model_name: str) -> str:
    if not model_name:
        raise ValueError("model is required")
    db = _db_name()
    with get_pool().cursor() as cur:
        text = export_osi_yaml(cur, db, model_name)
    if text is None:
        raise EntityNotFound(f"Unknown model: {model_name}")
    return text


__all__ = [
    "EntityNotFound",
    "SearchHit",
    "DescribeAttr",
    "DescribeResult",
    "ExecutionPayload",
    "QueryResult",
    "search_catalog",
    "describe_entity",
    "run_query",
    "export_osi_for_model",
]
