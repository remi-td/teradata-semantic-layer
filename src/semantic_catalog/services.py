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
class RelationshipHint:
    """One edge surfaced on a DATASET describe.

    ``prefix`` is the disambiguation token a caller prepends to a field
    name in a compile request (``prefix.field_name``). It is the
    relationship's ``role_name`` when set, otherwise its
    ``relationship_name`` — both forms are accepted by the parser.
    """
    prefix: str
    direction: str           # 'incoming' | 'outgoing'
    other_dataset: str
    cardinality: Optional[str]
    role_name: Optional[str]
    relationship_name: Optional[str]
    relationship_id: int


@dataclass
class DescribeResult:
    entity_type: str
    entity_name: str
    model_name: Optional[str]
    attributes: List[DescribeAttr]
    relationships: Optional[List[RelationshipHint]] = None


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
    et = entity_type.upper()
    with get_pool().cursor() as cur:
        cur.execute(
            f"EXEC {db}.m_semantic_describe(?, ?, ?)",
            (et, entity_name, model),
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
        # For DATASETs, surface every relationship as a structured edge so
        # callers can pick a disambiguation prefix without parsing the
        # macro's text output. Failures here are non-fatal — the textual
        # attributes are still returned.
        relationships: Optional[List[RelationshipHint]] = None
        if et == "DATASET":
            try:
                relationships = _load_dataset_relationships(
                    cur, db, entity_name=entity_name, model=model,
                )
            except Exception:  # noqa: BLE001
                log.exception("describe: relationship enrichment failed")
                relationships = None
    return DescribeResult(
        entity_type=et,
        entity_name=entity_name,
        model_name=model,
        attributes=attrs,
        relationships=relationships,
    )


def _load_dataset_relationships(
    cur: Any, db: str, *, entity_name: str, model: Optional[str],
) -> List[RelationshipHint]:
    """Return every edge incident to ``entity_name`` as a structured list.

    Joins RELATIONSHIP twice to the DATASET table to look up the dataset
    name on each side, then computes ``prefix`` (role_name OR
    relationship_name) and ``direction`` relative to ``entity_name``.
    """
    cur.execute(
        f"""SELECT r.relationship_id,
                   r.relationship_name,
                   r.role_name,
                   r.cardinality,
                   CASE WHEN r.from_dataset_id = d.dataset_id
                        THEN 'outgoing' ELSE 'incoming' END,
                   CASE WHEN r.from_dataset_id = d.dataset_id
                        THEN to_d.dataset_name
                        ELSE from_d.dataset_name END
              FROM {db}.DATASET d
              JOIN {db}.MODEL_DATASET md ON md.dataset_id = d.dataset_id
              JOIN {db}.SEMANTIC_MODEL sm ON sm.model_id = md.model_id
              JOIN {db}.RELATIONSHIP  r
                ON r.from_dataset_id = d.dataset_id
                OR r.to_dataset_id   = d.dataset_id
              JOIN {db}.DATASET from_d ON from_d.dataset_id = r.from_dataset_id
              JOIN {db}.DATASET to_d   ON to_d.dataset_id   = r.to_dataset_id
             WHERE d.dataset_name = ?
               AND (? IS NULL OR sm.model_name = ?)
             ORDER BY 5, 6""",
        (entity_name, model, model),
    )
    out: List[RelationshipHint] = []
    for r in cur.fetchall() or []:
        rel_id = int(r[0])
        rel_name = (str(r[1]).strip() if r[1] is not None else None)
        role_name = (str(r[2]).strip() if r[2] is not None else None)
        cardinality = (str(r[3]).strip() if r[3] is not None else None)
        direction = str(r[4]).strip()
        other = str(r[5]).strip()
        prefix = role_name or rel_name or str(rel_id)
        out.append(RelationshipHint(
            prefix=prefix,
            direction=direction,
            other_dataset=other,
            cardinality=cardinality,
            role_name=role_name,
            relationship_name=rel_name,
            relationship_id=rel_id,
        ))
    return out


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
    "RelationshipHint",
    "ExecutionPayload",
    "QueryResult",
    "search_catalog",
    "describe_entity",
    "run_query",
    "export_osi_for_model",
]
