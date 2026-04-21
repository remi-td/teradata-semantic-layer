"""Import endpoint — v0.3 default path uses the pure-Python importer.

Previous versions dispatched each entity to ``sp_semantic_import`` over
the Teradata driver. From v0.3 the default path calls
``semantic_catalog.importer.import_entity`` in-process, which keeps FK
resolution and INSERT/UPDATE logic in Python (and thus shared with the
compiler's CatalogDAO). The legacy SP remains callable via
``?legacy=true`` for one release and is scheduled for removal in v0.4.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

import yaml
from fastapi import APIRouter, HTTPException, Query

from ..db import get_pool
from ..importer import import_entity as py_import_entity, ordered_items
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
def run_import(req: ImportRequest, legacy: bool = Query(False)):
    """Parse YAML/JSON, write entities through the Python importer
    (default) or via ``sp_semantic_import`` when ``?legacy=true``.
    """
    db = _db_name()
    items = _flatten(req.model, req.text, req.items)
    if not items:
        raise HTTPException(400, "Import payload is empty")

    if legacy:
        return _run_legacy(req, db, items)
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


def _run_legacy(req: ImportRequest, db: str,
                items: List[Tuple[str, Dict[str, Any]]]) -> ImportResponse:
    """Legacy SP path — DEPRECATED in v0.3; removed in v0.4."""
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
            call_sql = f"CALL {db}.sp_semantic_import(?, ?, ?, ?, ?, ?)"
            for idx, (kind, payload) in enumerate(items, start=1):
                p_json = json.dumps(payload, ensure_ascii=False, default=str)
                if len(p_json) > 16000:
                    results.append(ImportResultRow(
                        ord=idx, kind=kind, name=_display_name(kind, payload),
                        status="ERROR",
                        message=f"payload JSON too large ({len(p_json)} bytes)",
                    ))
                    err_count += 1
                    continue
                try:
                    cur.execute(call_sql, (req.model, kind, p_json, None, None, None))
                    try:
                        out_row = cur.fetchone()
                    except Exception:
                        out_row = None
                    status = "ERROR"
                    message = "no result"
                    entity_id: Optional[int] = None
                    if out_row and len(out_row) >= 6:
                        status = (out_row[3] or "ERROR")
                        message = (out_row[4] or "")
                        entity_id = (int(out_row[5]) if out_row[5] is not None else None)
                except Exception as e:  # noqa: BLE001
                    status = "ERROR"
                    message = f"SP call failed: {e}"
                    entity_id = None
                results.append(ImportResultRow(
                    ord=idx, kind=kind, name=_display_name(kind, payload),
                    status=status,
                    message="[legacy SP] " + str(message).strip(),
                    entity_id=entity_id,
                ))
                if status == "OK":
                    ok_count += 1
                else:
                    err_count += 1
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
