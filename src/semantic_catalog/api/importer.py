"""Import endpoint.

Accepts YAML or JSON text pasted in the GUI and dispatches entities to the
``sp_semantic_import`` procedure in topological order. Validation and FK
resolution run inside Teradata — Python only handles parsing + ordering.

Supported payload shapes (all top-level keys optional):

    model: tpch_orders            # (string) target model for all entities below
    models:                       # optional — create new models
      - name: ...
        description: ...
    datasets:
      - name: customer
        source_table: db.customer
        description: ...
        granularity: "one row per customer"
    fields:
      - dataset: customer
        name: c_custkey
        type: K
        expression: c_custkey
        data_type: INTEGER
    metrics:
      - name: revenue
        primary_dataset: lineitem
        metric_type: SIMPLE
        description: ...
        expressions:
          TERADATA: "SUM(l_extendedprice * (1 - l_discount))"
          ANSI_SQL: "SUM(l_extendedprice * (1 - l_discount))"
    relationships:
      - name: order_to_customer
        from: orders
        to: customer
        cardinality: MANY_TO_ONE
        columns:
          - {from_field: o_custkey, to_field: c_custkey, position: 1}
    views:
      - name: order_dashboard
        primary_dataset: orders
    view_members:
      - view: order_dashboard
        ordinal: 1
        name: total_revenue
        member_type: MEASURE
        metric: revenue
    ai_context:
      - entity_type: DATASET
        entity_name: customer
        instructions: ...
        synonyms: [clients, buyers]

Any item may also be expressed as a bare ``{kind, payload}`` pair via the
programmatic ``items`` list for power users who already know the exact
``sp_semantic_import`` kind codes.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

import yaml
from fastapi import APIRouter, HTTPException

from ..db import get_pool
from .models import (
    ImportItem,
    ImportRequest,
    ImportResponse,
    ImportResultRow,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/import", tags=["import"])


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


def _norm_bool(v: Any) -> int:
    """Normalise YAML booleans / 0|1 / "true" / "yes" → 0 | 1."""
    if v is None:
        return 0
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        return 1 if int(v) else 0
    s = str(v).strip().lower()
    return 1 if s in ("1", "true", "yes", "y", "t") else 0


def _payload_for(kind: str, raw: Dict[str, Any]) -> Dict[str, Any]:
    """Normalise a user-supplied payload for a given kind (coerce bools, etc)."""
    out = dict(raw)
    for b in ("is_dimension", "is_time_dimension",
              "is_additive", "is_certified", "is_public"):
        if b in out:
            out[b] = _norm_bool(out[b])
    return out


def _ordered_items(model: str, text: Optional[str],
                   items: Optional[List[ImportItem]]) -> List[Tuple[str, Dict[str, Any]]]:
    """Flatten a YAML/JSON payload (or raw ``items``) into a topologically
    ordered (kind, payload) stream suitable for ``sp_semantic_import``."""
    if items:
        return [(it.kind.upper(), _payload_for(it.kind, it.payload)) for it in items]

    if not text:
        return []

    text = text.strip()
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as e:
        raise HTTPException(400, f"Could not parse YAML/JSON: {e}")
    if doc is None:
        return []
    if not isinstance(doc, dict):
        raise HTTPException(400, "Import payload must be a YAML/JSON object")

    ordered: List[Tuple[str, Dict[str, Any]]] = []

    # New models first.
    for m in (doc.get("models") or []):
        ordered.append(("MODEL", _payload_for("MODEL", m)))

    # Datasets, then fields.
    for d in (doc.get("datasets") or []):
        ordered.append(("DATASET", _payload_for("DATASET", d)))
        for f in (d.get("fields") or []):
            f2 = dict(f)
            f2.setdefault("dataset", d.get("name"))
            ordered.append(("FIELD", _payload_for("FIELD", f2)))

    # Stand-alone fields (dataset referenced by name).
    for f in (doc.get("fields") or []):
        ordered.append(("FIELD", _payload_for("FIELD", f)))

    # Metrics + their dialect expressions.
    for m in (doc.get("metrics") or []):
        ordered.append(("METRIC", _payload_for("METRIC", m)))
        exprs = m.get("expressions") or {}
        if isinstance(exprs, dict):
            for dialect, expr in exprs.items():
                ordered.append(("METRIC_EXPR", {
                    "metric": m.get("name"),
                    "dialect": str(dialect).upper(),
                    "expression": expr,
                }))
        elif isinstance(exprs, list):
            for e in exprs:
                ordered.append(("METRIC_EXPR", {
                    "metric": m.get("name"),
                    "dialect": str(e.get("dialect", "TERADATA")).upper(),
                    "expression": e.get("expression"),
                }))

    # Stand-alone metric expressions.
    for e in (doc.get("metric_expressions") or []):
        ordered.append(("METRIC_EXPR", _payload_for("METRIC_EXPR", e)))

    # Relationships + column mappings.
    for r in (doc.get("relationships") or []):
        ordered.append(("RELATIONSHIP", _payload_for("RELATIONSHIP", r)))
        for col in (r.get("columns") or []):
            c2 = dict(col)
            c2.setdefault("relationship", r.get("name"))
            c2.setdefault("from_dataset", r.get("from"))
            c2.setdefault("to_dataset", r.get("to"))
            ordered.append(("REL_COL", _payload_for("REL_COL", c2)))

    # Views + members.
    for v in (doc.get("views") or []):
        ordered.append(("VIEW", _payload_for("VIEW", v)))
        for mem in (v.get("members") or []):
            m2 = dict(mem)
            m2.setdefault("view", v.get("name"))
            ordered.append(("VIEW_MEMBER", _payload_for("VIEW_MEMBER", m2)))

    for m in (doc.get("view_members") or []):
        ordered.append(("VIEW_MEMBER", _payload_for("VIEW_MEMBER", m)))

    # AI context last.
    for ac in (doc.get("ai_context") or []):
        ordered.append(("AI_CONTEXT", _payload_for("AI_CONTEXT", ac)))

    return ordered


def _display_name(kind: str, payload: Dict[str, Any]) -> Optional[str]:
    if kind == "MODEL":
        return payload.get("name")
    if kind == "DATASET":
        return payload.get("name")
    if kind == "FIELD":
        return f"{payload.get('dataset')}.{payload.get('name')}"
    if kind == "METRIC":
        return payload.get("name")
    if kind == "METRIC_EXPR":
        return f"{payload.get('metric')} [{payload.get('dialect')}]"
    if kind == "RELATIONSHIP":
        return payload.get("name")
    if kind == "REL_COL":
        return (f"{payload.get('relationship')}: {payload.get('from_field')} → "
                f"{payload.get('to_field')}")
    if kind == "VIEW":
        return payload.get("name")
    if kind == "VIEW_MEMBER":
        return f"{payload.get('view')}.{payload.get('name')}"
    if kind == "AI_CONTEXT":
        return f"{payload.get('entity_type')}:{payload.get('entity_name')}"
    return None


@router.post("", response_model=ImportResponse)
def run_import(req: ImportRequest):
    """Parse YAML/JSON, dispatch entities to ``sp_semantic_import`` in order."""
    db = _db_name()
    items = _ordered_items(req.model, req.text, req.items)
    if not items:
        raise HTTPException(400, "Import payload is empty")

    results: List[ImportResultRow] = []
    ok_count = 0
    err_count = 0

    # Run the entire batch inside a single transaction so we can roll back
    # on dry-run or on any error.
    pool = get_pool()
    with pool.connection() as conn:
        # Switch off auto-commit for the duration of this request.
        try:
            conn.autocommit = False
        except Exception:
            pass
        cur = conn.cursor()
        try:
            call_sql = f"CALL {db}.sp_semantic_import(?, ?, ?, ?, ?, ?)"
            for idx, (kind, payload) in enumerate(items, start=1):
                p_json = json.dumps(payload, ensure_ascii=False, default=str)
                if len(p_json) > 16000:
                    results.append(ImportResultRow(
                        ord=idx, kind=kind, name=_display_name(kind, payload),
                        status="ERROR",
                        message=f"payload JSON too large ({len(p_json)} bytes, max 16000)",
                    ))
                    err_count += 1
                    continue
                try:
                    # The SP uses OUT params; the driver returns them via fetchone()
                    # after the CALL completes.
                    cur.execute(call_sql, (req.model, kind, p_json, None, None, None))
                    # Fetch OUT values.
                    try:
                        out_row = cur.fetchone()
                    except Exception:
                        out_row = None
                    status = "ERROR"
                    message = "no result"
                    entity_id: Optional[int] = None
                    if out_row and len(out_row) >= 6:
                        # positional args order ours: model, kind, payload, status, message, entity_id
                        status = (out_row[3] or "ERROR")
                        message = (out_row[4] or "")
                        entity_id = (int(out_row[5]) if out_row[5] is not None else None)
                    elif out_row and len(out_row) >= 3:
                        # some drivers return only OUT columns
                        status  = (out_row[0] or "ERROR")
                        message = (out_row[1] or "")
                        entity_id = (int(out_row[2]) if out_row[2] is not None else None)
                except Exception as e:
                    status = "ERROR"
                    message = f"SP call failed: {e}"
                    entity_id = None
                results.append(ImportResultRow(
                    ord=idx, kind=kind, name=_display_name(kind, payload),
                    status=status, message=str(message).strip(),
                    entity_id=entity_id,
                ))
                if status == "OK":
                    ok_count += 1
                else:
                    err_count += 1

            # Commit only if no errors and not a dry-run.
            applied = False
            if err_count == 0 and not req.dry_run:
                conn.commit()
                applied = True
            else:
                conn.rollback()

        finally:
            try:
                cur.close()
            except Exception:
                pass
            try:
                conn.autocommit = True
            except Exception:
                pass

    return ImportResponse(
        model=req.model,
        dry_run=req.dry_run,
        total=len(items),
        ok_count=ok_count,
        error_count=err_count,
        results=results,
        applied=applied,
    )


@router.get("/template")
def import_template() -> Dict[str, Any]:
    """Return a minimal, copy-pasteable example payload."""
    return {
        "yaml": (
            "# Minimal import example — paste and edit in the GUI\n"
            "model: tpch_orders\n"
            "metrics:\n"
            "  - name: my_new_metric\n"
            "    description: Example measure, copy me\n"
            "    primary_dataset: lineitem\n"
            "    metric_type: SIMPLE\n"
            "    expressions:\n"
            "      TERADATA: \"SUM(lineitem.l_quantity)\"\n"
            "      ANSI_SQL: \"SUM(l_quantity)\"\n"
            "ai_context:\n"
            "  - entity_type: METRIC\n"
            "    entity_name: my_new_metric\n"
            "    instructions: \"Total units sold across line items.\"\n"
            "    synonyms: [\"volume\", \"unit count\"]\n"
        ),
    }
