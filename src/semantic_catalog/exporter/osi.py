"""OSI YAML export.

Reads a model from the catalog via a DB-API cursor and renders the
OSI 0.1.x document shape. Kept as plain functions (not a class) because
there is no state beyond the cursor — tests pass in a FakeCursor with
scripted result sets.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

import yaml


def _fetchone(cur, sql: str, *params: Any):
    cur.execute(sql, params if params else None)
    return cur.fetchone()


def _fetchall(cur, sql: str, *params: Any):
    cur.execute(sql, params if params else None)
    return cur.fetchall() or []


def _parse_yaml_scalar(raw: Any) -> Any:
    """Catalog JSON columns come back as strings. Parse them for inclusion
    in the YAML doc so they render as proper lists / maps."""
    if raw is None:
        return None
    try:
        return yaml.safe_load(str(raw))
    except Exception:
        return str(raw)


def build_osi_document(cur, db: str, model_name: str) -> Optional[Dict[str, Any]]:
    """Build the OSI document (as a Python dict) for ``model_name``.

    Returns None when the model is not found — caller decides how to
    surface that (typically a 404 on the HTTP layer).
    """
    r = _fetchone(cur,
                  f"SELECT model_id, model_name, description "
                  f"FROM {db}.SEMANTIC_MODEL WHERE model_name = ?",
                  model_name)
    if not r:
        return None
    model_id = int(r[0])
    model_name_norm = str(r[1]).strip()
    model_desc = (r[2] or None)

    datasets = _build_datasets(cur, db, model_id)
    relationships = _build_relationships(cur, db, model_id, datasets)
    metrics = _build_metrics(cur, db, model_id)

    doc: Dict[str, Any] = {
        "version": "0.1.1",
        "semantic_model": [{
            "name": model_name_norm,
            "description": model_desc,
            "datasets": datasets,
            "relationships": relationships,
            "metrics": metrics,
        }],
    }
    ac = _load_ai_context(cur, db, "MODEL", model_id)
    if ac:
        doc["semantic_model"][0]["ai_context"] = ac
    return doc


def export_osi_yaml(cur, db: str, model_name: str) -> Optional[str]:
    doc = build_osi_document(cur, db, model_name)
    if doc is None:
        return None
    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=120)


# --- helpers ---------------------------------------------------------

def _load_ai_context(cur, db: str, entity_type: str,
                     entity_id: int) -> Optional[Dict[str, Any]]:
    r = _fetchone(cur,
                  f"SELECT instructions, CAST(synonyms AS VARCHAR(4000)), "
                  f"       CAST(examples AS VARCHAR(4000)), display_name "
                  f"  FROM {db}.AI_CONTEXT "
                  f" WHERE entity_type = ? AND entity_id = ?",
                  entity_type, entity_id)
    if not r:
        return None
    ctx: Dict[str, Any] = {}
    if r[0]:
        ctx["instructions"] = str(r[0])
    if r[1]:
        ctx["synonyms"] = _parse_yaml_scalar(r[1])
    if r[2]:
        ctx["examples"] = _parse_yaml_scalar(r[2])
    if r[3]:
        ctx["display_name"] = str(r[3])
    return ctx or None


def _build_datasets(cur, db: str, model_id: int) -> List[Dict[str, Any]]:
    rows = _fetchall(cur,
                     f"""SELECT dataset_id, dataset_name, description,
                                granularity_desc, DataBaseName, TableName,
                                CAST(source_query AS VARCHAR(8000))
                           FROM {db}.DATASET WHERE model_id = ?
                          ORDER BY dataset_name""",
                     model_id)
    out: List[Dict[str, Any]] = []
    for row in rows:
        did = int(row[0])
        entry: Dict[str, Any] = {
            "name": str(row[1]).strip(),
            "description": (row[2] or None),
        }
        if row[3]:
            entry["granularity"] = str(row[3])
        if row[4] and row[5]:
            entry["source"] = f"{str(row[4]).strip()}.{str(row[5]).strip()}"
        if row[6]:
            entry["source_query"] = str(row[6])

        fields = _build_fields(cur, db, did)
        if fields:
            entry["fields"] = fields

        pk = _build_primary_key(cur, db, did)
        if pk:
            entry["primary_key"] = pk

        ac = _load_ai_context(cur, db, "DATASET", did)
        if ac:
            entry["ai_context"] = ac

        out.append(entry)
    return out


def _build_fields(cur, db: str, dataset_id: int) -> List[Dict[str, Any]]:
    rows = _fetchall(cur,
                     f"""SELECT field_id, field_name, field_type_code,
                                CAST(expression AS VARCHAR(2000)),
                                description, label, is_dimension,
                                is_time_dimension, data_type, ColumnName
                           FROM {db}.FIELD WHERE dataset_id = ?
                          ORDER BY field_order, field_name""",
                     dataset_id)
    out: List[Dict[str, Any]] = []
    for row in rows:
        entry: Dict[str, Any] = {"name": str(row[1]).strip()}
        if row[3]:
            entry["expression"] = {
                "dialects": [{"dialect": "ANSI_SQL", "expression": str(row[3])}]
            }
        if row[6]:
            dim: Dict[str, Any] = {}
            if row[7]:
                dim["is_time"] = True
            entry["dimension"] = dim
        if row[2] == "K":
            entry["key"] = True
        if row[8]:
            entry["data_type"] = str(row[8]).strip()
        if row[4]:
            entry["description"] = str(row[4])
        out.append(entry)
    return out


def _build_primary_key(cur, db: str, dataset_id: int) -> List[str]:
    rows = _fetchall(cur,
                     f"""SELECT f.field_name
                           FROM {db}.DATASET_KEY k
                           JOIN {db}.FIELD f ON f.field_id = k.field_id
                          WHERE k.dataset_id = ? AND k.key_type = 'PK'
                          ORDER BY k.column_position""",
                     dataset_id)
    return [str(r[0]).strip() for r in rows]


def _build_relationships(cur, db: str, model_id: int,
                         datasets: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    # Build dataset_id -> dataset_name mapping for edge rendering. We
    # re-query to avoid coupling with the datasets list shape above.
    ds_rows = _fetchall(cur,
                        f"SELECT dataset_id, dataset_name FROM {db}.DATASET "
                        f"WHERE model_id = ?",
                        model_id)
    name_by_id = {int(r[0]): str(r[1]).strip() for r in ds_rows}

    rows = _fetchall(cur,
                     f"""SELECT r.relationship_id, r.relationship_name,
                                r.from_dataset_id, r.to_dataset_id,
                                r.cardinality, r.join_type_hint
                           FROM {db}.RELATIONSHIP r
                           JOIN {db}.DATASET df ON df.dataset_id = r.from_dataset_id
                          WHERE df.model_id = ?""",
                     model_id)
    out: List[Dict[str, Any]] = []
    for row in rows:
        rid = int(row[0])
        frm = name_by_id.get(int(row[2]))
        to  = name_by_id.get(int(row[3]))
        if not (frm and to):
            continue
        cols = _fetchall(cur,
                         f"""SELECT ff.field_name, tf.field_name
                               FROM {db}.REL_COLUMN_MAP rcm
                               JOIN {db}.FIELD ff ON ff.field_id = rcm.from_field_id
                               JOIN {db}.FIELD tf ON tf.field_id = rcm.to_field_id
                              WHERE rcm.relationship_id = ?
                              ORDER BY rcm.column_position""",
                         rid)
        out.append({
            "name": (str(row[1]).strip() if row[1] else None),
            "from": frm,
            "to":   to,
            "from_columns": [str(c[0]).strip() for c in cols],
            "to_columns":   [str(c[1]).strip() for c in cols],
            "cardinality":  (str(row[4]).strip() if row[4] else None),
            "join_type":    (str(row[5]).strip() if row[5] else None),
        })
    return out


def _build_metrics(cur, db: str, model_id: int) -> List[Dict[str, Any]]:
    rows = _fetchall(cur,
                     f"""SELECT metric_id, metric_name, description, metric_type
                           FROM {db}.METRIC WHERE model_id = ?
                          ORDER BY metric_name""",
                     model_id)
    out: List[Dict[str, Any]] = []
    for row in rows:
        mid = int(row[0])
        mname = str(row[1]).strip()
        entry: Dict[str, Any] = {
            "name": mname,
            "type": (str(row[3]).strip() if row[3] else "SIMPLE"),
        }
        if row[2]:
            entry["description"] = str(row[2])

        dialect_rows = _fetchall(cur,
                                 f"SELECT dialect, expression "
                                 f"FROM {db}.METRIC_EXPRESSION WHERE metric_id = ?",
                                 mid)
        dialects = [{"dialect": str(r[0]).strip(), "expression": str(r[1])}
                    for r in dialect_rows]
        if dialects:
            entry["expression"] = {"dialects": dialects}

        ac = _load_ai_context(cur, db, "METRIC", mid)
        if ac:
            entry["ai_context"] = ac
        out.append(entry)
    return out
