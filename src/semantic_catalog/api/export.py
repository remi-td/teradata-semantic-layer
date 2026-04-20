"""Export endpoints: OSI YAML."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

import yaml
from fastapi import APIRouter, HTTPException, Response

from ..db import get_pool

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/export", tags=["export"])


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


@router.get("/osi/{model_name}", response_class=Response)
def export_osi(model_name: str) -> Response:
    """Projection to OSI 0.1.x YAML."""
    db = _db_name()
    with get_pool().cursor() as cur:
        cur.execute(f"""
            SELECT model_id, model_name, description
              FROM {db}.SEMANTIC_MODEL WHERE model_name = ?
        """, (model_name,))
        r = cur.fetchone()
        if not r:
            raise HTTPException(404, f"Unknown model: {model_name}")
        model_id = int(r[0])

        # Datasets + fields
        cur.execute(f"""
            SELECT d.dataset_id, d.dataset_name, d.description, d.granularity_desc,
                   d.DataBaseName, d.TableName, d.source_query
              FROM {db}.DATASET d WHERE d.model_id = ? ORDER BY d.dataset_name
        """, (model_id,))
        datasets_raw = cur.fetchall()

        datasets: List[Dict[str, Any]] = []
        ds_name_by_id: Dict[int, str] = {}
        for ds in datasets_raw:
            did = int(ds[0])
            dname = str(ds[1]).strip()
            ds_name_by_id[did] = dname
            # source
            src = None
            if ds[4] and ds[5]:
                src = f"{str(ds[4]).strip()}.{str(ds[5]).strip()}"
            ds_entry: Dict[str, Any] = {
                "name": dname,
                "description": (ds[2] or None),
            }
            if ds[3]:
                ds_entry["granularity"] = str(ds[3])
            if src:
                ds_entry["source"] = src
            if ds[6]:
                ds_entry["source_query"] = str(ds[6])

            # fields
            cur.execute(f"""
                SELECT f.field_id, f.field_name, f.field_type_code, f.expression,
                       f.description, f.label, f.is_dimension, f.is_time_dimension,
                       f.data_type, f.ColumnName
                  FROM {db}.FIELD f WHERE f.dataset_id = ?
                 ORDER BY f.field_order, f.field_name
            """, (did,))
            fields_out: List[Dict[str, Any]] = []
            for fr in cur.fetchall():
                f_entry: Dict[str, Any] = {
                    "name": str(fr[1]).strip(),
                }
                if fr[3]:
                    f_entry["expression"] = {
                        "dialects": [{"dialect": "ANSI_SQL", "expression": str(fr[3])}]
                    }
                if fr[6]:
                    dim: Dict[str, Any] = {}
                    if fr[7]:
                        dim["is_time"] = True
                    f_entry["dimension"] = dim
                if fr[2] == "K":
                    f_entry["key"] = True
                if fr[8]:
                    f_entry["data_type"] = str(fr[8]).strip()
                if fr[4]:
                    f_entry["description"] = str(fr[4])
                fields_out.append(f_entry)
            if fields_out:
                ds_entry["fields"] = fields_out

            # primary key
            cur.execute(f"""
                SELECT f.field_name FROM {db}.DATASET_KEY k
                  JOIN {db}.FIELD f ON f.field_id = k.field_id
                 WHERE k.dataset_id = ? AND k.key_type = 'PK'
                 ORDER BY k.column_position
            """, (did,))
            pk_fields = [str(r[0]).strip() for r in cur.fetchall()]
            if pk_fields:
                ds_entry["primary_key"] = pk_fields

            # ai context
            cur.execute(f"""
                SELECT instructions, CAST(synonyms AS VARCHAR(4000)) AS syn,
                       CAST(examples AS VARCHAR(4000)) AS ex, display_name
                  FROM {db}.AI_CONTEXT WHERE entity_type='DATASET' AND entity_id=?
            """, (did,))
            ac = cur.fetchone()
            if ac:
                ctx: Dict[str, Any] = {}
                if ac[0]: ctx["instructions"] = str(ac[0])
                if ac[1]:
                    try: ctx["synonyms"] = yaml.safe_load(str(ac[1]))
                    except Exception: ctx["synonyms"] = str(ac[1])
                if ac[3]: ctx["display_name"] = str(ac[3])
                if ctx:
                    ds_entry["ai_context"] = ctx

            datasets.append(ds_entry)

        # Relationships
        cur.execute(f"""
            SELECT r.relationship_id, r.relationship_name,
                   r.from_dataset_id, r.to_dataset_id, r.cardinality, r.join_type_hint
              FROM {db}.RELATIONSHIP r
              JOIN {db}.DATASET df ON df.dataset_id = r.from_dataset_id
             WHERE df.model_id = ?
        """, (model_id,))
        rels_raw = cur.fetchall()
        relationships: List[Dict[str, Any]] = []
        for rr in rels_raw:
            rid = int(rr[0])
            frm = ds_name_by_id.get(int(rr[2]))
            to  = ds_name_by_id.get(int(rr[3]))
            if not (frm and to):
                continue
            cur.execute(f"""
                SELECT ff.field_name, tf.field_name
                  FROM {db}.REL_COLUMN_MAP rcm
                  JOIN {db}.FIELD ff ON ff.field_id = rcm.from_field_id
                  JOIN {db}.FIELD tf ON tf.field_id = rcm.to_field_id
                 WHERE rcm.relationship_id = ? ORDER BY rcm.column_position
            """, (rid,))
            cols = cur.fetchall()
            relationships.append({
                "name": (str(rr[1]).strip() if rr[1] else None),
                "from": frm,
                "to":   to,
                "from_columns": [str(c[0]).strip() for c in cols],
                "to_columns":   [str(c[1]).strip() for c in cols],
                "cardinality":  (str(rr[4]).strip() if rr[4] else None),
                "join_type":    (str(rr[5]).strip() if rr[5] else None),
            })

        # Metrics
        cur.execute(f"""
            SELECT mt.metric_id, mt.metric_name, mt.description, mt.metric_type
              FROM {db}.METRIC mt WHERE mt.model_id = ? ORDER BY mt.metric_name
        """, (model_id,))
        metrics_out: List[Dict[str, Any]] = []
        for mr in cur.fetchall():
            mid = int(mr[0])
            mname = str(mr[1]).strip()
            mentry: Dict[str, Any] = {
                "name": mname,
                "type": (str(mr[3]).strip() if mr[3] else "SIMPLE"),
            }
            if mr[2]: mentry["description"] = str(mr[2])
            cur.execute(f"""
                SELECT dialect, expression FROM {db}.METRIC_EXPRESSION
                 WHERE metric_id = ?
            """, (mid,))
            dialects = [
                {"dialect": str(r[0]).strip(), "expression": str(r[1])}
                for r in cur.fetchall()
            ]
            if dialects:
                mentry["expression"] = {"dialects": dialects}
            # AI context
            cur.execute(f"""
                SELECT instructions, CAST(synonyms AS VARCHAR(4000)), display_name
                  FROM {db}.AI_CONTEXT WHERE entity_type='METRIC' AND entity_id=?
            """, (mid,))
            ac = cur.fetchone()
            if ac:
                ctx: Dict[str, Any] = {}
                if ac[0]: ctx["instructions"] = str(ac[0])
                if ac[1]:
                    try: ctx["synonyms"] = yaml.safe_load(str(ac[1]))
                    except Exception: pass
                if ac[2]: ctx["display_name"] = str(ac[2])
                if ctx: mentry["ai_context"] = ctx
            metrics_out.append(mentry)

        # Model-level AI context
        cur.execute(f"""
            SELECT instructions, CAST(synonyms AS VARCHAR(4000)), display_name
              FROM {db}.AI_CONTEXT WHERE entity_type='MODEL' AND entity_id=?
        """, (model_id,))
        model_ac = cur.fetchone()

    doc: Dict[str, Any] = {
        "version": "0.1.1",
        "semantic_model": [{
            "name": str(r[1]).strip(),
            "description": (r[2] or None),
            "datasets": datasets,
            "relationships": relationships,
            "metrics": metrics_out,
        }],
    }
    if model_ac:
        ctx: Dict[str, Any] = {}
        if model_ac[0]: ctx["instructions"] = str(model_ac[0])
        if model_ac[1]:
            try: ctx["synonyms"] = yaml.safe_load(str(model_ac[1]))
            except Exception: pass
        if model_ac[2]: ctx["display_name"] = str(model_ac[2])
        if ctx:
            doc["semantic_model"][0]["ai_context"] = ctx

    text = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=120)
    return Response(content=text, media_type="text/yaml")
