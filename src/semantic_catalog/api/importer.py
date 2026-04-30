"""Import endpoint — writes one entity at a time through the pure-Python
importer.

Legacy reminder: earlier versions also dispatched to
``sp_semantic_import`` via ``?legacy=true``. The SQL importer is no
longer deployed at install time, so that query-parameter no longer has
a functioning backend and has been removed.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

import yaml
from fastapi import APIRouter, HTTPException

from ..db import get_pool
from ..importer import (
    import_entity as py_import_entity,
    ordered_items,
    synthesize_filtered_expressions as py_synthesize_filtered_expressions,
)
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


def _flatten(model: str, text: Optional[str],
             items: Optional[List[ImportItem]]) -> List[Tuple[str, Dict[str, Any]]]:
    if items:
        return [(it.kind.upper(), dict(it.payload)) for it in items]
    if not text:
        return []
    try:
        doc = yaml.safe_load(text.strip())
    except yaml.YAMLError as e:
        raise HTTPException(400, f"Could not parse YAML/JSON: {e}")
    try:
        return ordered_items(doc or {})
    except ValueError as e:
        raise HTTPException(400, str(e))


def _display_name(kind: str, payload: Dict[str, Any]) -> Optional[str]:
    k = kind.upper()
    if k in ("MODEL", "DATASET", "METRIC", "RELATIONSHIP", "VIEW", "HIERARCHY"):
        return payload.get("name")
    if k == "FIELD":
        return f"{payload.get('dataset')}.{payload.get('name')}"
    if k == "METRIC_EXPR":
        return f"{payload.get('metric')} [{payload.get('dialect')}]"
    if k == "METRIC_FILTER":
        return f"{payload.get('metric')}[{payload.get('filter_ord', 1)}]"
    if k == "REL_COL":
        return f"{payload.get('relationship')}: {payload.get('from_field')} -> {payload.get('to_field')}"
    if k == "VIEW_MEMBER":
        return f"{payload.get('view')}.{payload.get('name')}"
    if k == "HIERARCHY_LEVEL":
        return f"{payload.get('hierarchy')}[{payload.get('level_ord')}]"
    if k == "AI_CONTEXT":
        return f"{payload.get('entity_type')}:{payload.get('entity_name')}"
    return None


@router.post("", response_model=ImportResponse)
def run_import(req: ImportRequest):
    """Parse YAML/JSON and write each entity through the Python importer."""
    db = _db_name()
    items = _flatten(req.model, req.text, req.items)
    if not items:
        raise HTTPException(400, "Import payload is empty")
    return _run_python(req, db, items)


def _run_python(req: ImportRequest, db: str,
                items: List[Tuple[str, Dict[str, Any]]]) -> ImportResponse:
    results: List[ImportResultRow] = []
    ok_count = 0
    err_count = 0
    pool = get_pool()
    with pool.connection() as conn:
        try:
            conn.autocommit = False
        except Exception:
            pass
        cur = conn.cursor()
        try:
            for idx, (kind, payload) in enumerate(items, start=1):
                try:
                    status, message, entity_id = py_import_entity(
                        cur, db, req.model, kind, payload,
                    )
                except Exception as e:  # noqa: BLE001
                    status, message, entity_id = "ERROR", f"crash: {e}", None
                results.append(ImportResultRow(
                    ord=idx, kind=kind, name=_display_name(kind, payload),
                    status=status, message=str(message).strip(),
                    entity_id=entity_id,
                ))
                if status == "OK":
                    ok_count += 1
                else:
                    err_count += 1

            applied = False
            if err_count == 0 and not req.dry_run:
                py_synthesize_filtered_expressions(cur, db, req.model)
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
        model=req.model, dry_run=req.dry_run, total=len(items),
        ok_count=ok_count, error_count=err_count,
        results=results, applied=applied,
    )


@router.get("/template")
def import_template() -> Dict[str, Any]:
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
