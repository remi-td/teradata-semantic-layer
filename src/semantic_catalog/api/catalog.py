"""Catalog exploration endpoints: models, graph, describe, search."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Query

from ..db import get_pool, rows_as_dicts
from .. import services
from .models import (
    DescribeAttribute,
    DescribeResponse,
    GraphEdge,
    GraphNode,
    GraphPayload,
    ModelSummary,
    RelationshipHint,
    SearchHit,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api", tags=["catalog"])


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


@router.get("/models", response_model=List[ModelSummary])
def list_models():
    """Return every model in the catalog with summary counts."""
    db = _db_name()
    sql = f"""
        SELECT m.model_id, m.model_name, m.description,
               (SELECT COUNT(*) FROM {db}.MODEL_DATASET md WHERE md.model_id=m.model_id) AS ds_count,
               (SELECT COUNT(*) FROM {db}.METRIC mt WHERE mt.model_id=m.model_id) AS mt_count,
               m.model_family, m.model_version, m.is_latest
          FROM {db}.SEMANTIC_MODEL m
         WHERE m.is_active = 1 AND m.is_deprecated = 0
         ORDER BY m.model_name
    """
    with get_pool().cursor() as cur:
        cur.execute(sql)
        out: List[ModelSummary] = []
        for r in cur.fetchall():
            out.append(ModelSummary(
                model_id=int(r[0]),
                model_name=str(r[1]).strip(),
                description=(r[2] or None),
                dataset_count=int(r[3] or 0),
                metric_count=int(r[4] or 0),
                model_family=(str(r[5]).strip() if r[5] else None),
                model_version=int(r[6] or 1),
                is_latest=bool(r[7] if r[7] is not None else 1),
            ))
        return out


@router.get("/models/{model_name}/graph", response_model=GraphPayload)
def get_graph(model_name: str):
    """Return a graph payload (nodes + edges) suitable for Cytoscape.js."""
    db = _db_name()
    with get_pool().cursor() as cur:
        # Resolve model_id
        cur.execute(f"SELECT model_id FROM {db}.SEMANTIC_MODEL WHERE model_name = ?", (model_name,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(404, f"Unknown semantic model: {model_name}")
        model_id = int(row[0])

        nodes: List[GraphNode] = []
        edges: List[GraphEdge] = []

        # Datasets — cube vs table distinction uses source_query presence.
        cur.execute(f"""
            SELECT d.dataset_id, d.dataset_name, d.description,
                   d.DataBaseName, d.TableName,
                   CASE WHEN d.source_query IS NOT NULL THEN 1 ELSE 0 END AS has_src,
                   (SELECT COUNT(*) FROM {db}.FIELD f WHERE f.dataset_id = d.dataset_id) AS field_count,
                   ac.display_name
              FROM {db}.DATASET d
              JOIN {db}.MODEL_DATASET md ON md.dataset_id = d.dataset_id
              LEFT JOIN {db}.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
             WHERE md.model_id = ?
             ORDER BY d.dataset_name
        """, (model_id,))
        dataset_ids: Dict[int, str] = {}
        for r in cur.fetchall():
            did = int(r[0])
            name = str(r[1]).strip()
            dataset_ids[did] = name
            sub_kind = "CUBE" if int(r[5]) == 1 else "TABLE"
            meta = {
                "physical": (
                    (str(r[3]).strip() + "." + str(r[4]).strip())
                    if r[3] and r[4] else None
                ),
                "has_source_query": bool(r[5]),
                "field_count": int(r[6] or 0),
                "display_name": (r[7] or None),
            }
            nodes.append(GraphNode(
                id=f"ds:{did}",
                label=name,
                kind="DATASET",
                sub_kind=sub_kind,
                description=(r[2] or None),
                meta=meta,
            ))

        # Metrics — attach to primary dataset via edge if known.
        cur.execute(f"""
            SELECT mt.metric_id, mt.metric_name, mt.description, mt.metric_type,
                   mt.primary_dataset_id, mt.is_certified
              FROM {db}.METRIC mt
             WHERE mt.model_id = ?
             ORDER BY mt.metric_name
        """, (model_id,))
        for r in cur.fetchall():
            mid = int(r[0])
            mname = str(r[1]).strip()
            primary_ds = int(r[4]) if r[4] is not None else None
            nodes.append(GraphNode(
                id=f"met:{mid}",
                label=mname,
                kind="METRIC",
                sub_kind=str(r[3]).strip() if r[3] else "SIMPLE",
                description=(r[2] or None),
                meta={
                    "primary_dataset_id": primary_ds,
                    "is_certified": bool(r[5] or 0),
                },
            ))
            if primary_ds is not None and primary_ds in dataset_ids:
                edges.append(GraphEdge(
                    id=f"e-met:{mid}-ds:{primary_ds}",
                    source=f"met:{mid}",
                    target=f"ds:{primary_ds}",
                    kind="METRIC_OF",
                ))

        # Relationships between datasets.
        cur.execute(f"""
            SELECT r.relationship_id, r.relationship_name,
                   r.from_dataset_id, r.to_dataset_id,
                   r.cardinality, r.join_type_hint, r.role_name
              FROM {db}.RELATIONSHIP r
              JOIN {db}.MODEL_DATASET md ON md.dataset_id = r.from_dataset_id
             WHERE md.model_id = ?
        """, (model_id,))
        for r in cur.fetchall():
            rid = int(r[0])
            frm = int(r[2])
            to  = int(r[3])
            if frm not in dataset_ids or to not in dataset_ids:
                continue
            edges.append(GraphEdge(
                id=f"rel:{rid}",
                source=f"ds:{frm}",
                target=f"ds:{to}",
                kind="RELATIONSHIP",
                label=str(r[1]).strip() if r[1] else None,
                cardinality=str(r[4]).strip() if r[4] else None,
                role_name=(str(r[6]).strip() if r[6] else None),
            ))

    return GraphPayload(model_name=model_name, nodes=nodes, edges=edges)


@router.get("/search", response_model=List[SearchHit])
def search(
    q: str = Query(..., min_length=1, description="Search term"),
    model: Optional[str] = Query(None, description="Restrict to a single model"),
    limit: int = Query(50, ge=1, le=500),
):
    hits = services.search_catalog(term=q, model=model, limit=limit)
    return [
        SearchHit(
            entity_type=h.entity_type,
            entity_name=h.entity_name,
            parent_name=h.parent_name,
            description=h.description,
            synonyms=h.synonyms,
            relevance=h.relevance,
        )
        for h in hits
    ]


@router.get("/describe", response_model=DescribeResponse)
def describe(
    entity_type: str = Query(..., description="MODEL|DATASET|FIELD|METRIC|VIEW"),
    entity_name: str = Query(...),
    model: Optional[str] = Query(None, description="Required for FIELD when name collides"),
):
    try:
        result = services.describe_entity(
            entity_type=entity_type, entity_name=entity_name, model=model,
        )
    except services.EntityNotFound as e:
        raise HTTPException(404, str(e))
    return DescribeResponse(
        entity_type=result.entity_type,
        entity_name=result.entity_name,
        model_name=result.model_name,
        attributes=[
            DescribeAttribute(
                attr_ordinal=a.attr_ordinal,
                attr_key=a.attr_key,
                attr_value=a.attr_value,
            )
            for a in result.attributes
        ],
        relationships=(
            [
                RelationshipHint(
                    prefix=h.prefix,
                    direction=h.direction,
                    other_dataset=h.other_dataset,
                    cardinality=h.cardinality,
                    role_name=h.role_name,
                    relationship_name=h.relationship_name,
                    relationship_id=h.relationship_id,
                )
                for h in result.relationships
            ]
            if result.relationships is not None
            else None
        ),
    )


@router.get("/models/{model_name}/tree")
def get_tree(model_name: str) -> Dict[str, Any]:
    """Hierarchical catalog for the left-pane tree widget.

    Structure:
        {
          "model": {"name": ..., "description": ...},
          "datasets": [{"name", "sub_kind", "fields":[{name, is_dim, is_time_dim, type}]}],
          "metrics":  [{"name", "type"}],
          "relationships": [{"name", "from", "to", "cardinality"}]
        }
    """
    db = _db_name()
    out: Dict[str, Any] = {}
    with get_pool().cursor() as cur:
        cur.execute(f"SELECT model_id, model_name, description FROM {db}.SEMANTIC_MODEL WHERE model_name = ?", (model_name,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(404, f"Unknown semantic model: {model_name}")
        model_id = int(row[0])
        out["model"] = {"name": str(row[1]).strip(), "description": (row[2] or None)}

        cur.execute(f"""
            SELECT d.dataset_id, d.dataset_name,
                   CASE WHEN d.source_query IS NOT NULL THEN 'CUBE' ELSE 'TABLE' END,
                   d.description
              FROM {db}.DATASET d
              JOIN {db}.MODEL_DATASET md ON md.dataset_id = d.dataset_id
             WHERE md.model_id = ? ORDER BY d.dataset_name
        """, (model_id,))
        datasets: List[Dict[str, Any]] = []
        ds_map: Dict[int, Dict[str, Any]] = {}
        for r in cur.fetchall():
            entry = {
                "id": int(r[0]),
                "name": str(r[1]).strip(),
                "sub_kind": str(r[2]).strip(),
                "description": (r[3] or None),
                "fields": [],
            }
            ds_map[int(r[0])] = entry
            datasets.append(entry)

        if ds_map:
            ids = ",".join(str(i) for i in ds_map)
            cur.execute(f"""
                SELECT f.dataset_id, f.field_name, f.field_type_code,
                       f.is_dimension, f.is_time_dimension, f.data_type
                  FROM {db}.FIELD f
                 WHERE f.dataset_id IN ({ids})
                 ORDER BY f.dataset_id, f.field_order, f.field_name
            """)
            for r in cur.fetchall():
                ds_map[int(r[0])]["fields"].append({
                    "name": str(r[1]).strip(),
                    "type": str(r[2]).strip(),
                    "is_dimension": bool(r[3] or 0),
                    "is_time_dimension": bool(r[4] or 0),
                    "data_type": (r[5] or None),
                })
        out["datasets"] = datasets

        cur.execute(f"""
            SELECT mt.metric_name, mt.metric_type, mt.description, d.dataset_name, mt.is_certified
              FROM {db}.METRIC mt
              LEFT JOIN {db}.DATASET d ON d.dataset_id = mt.primary_dataset_id
             WHERE mt.model_id = ?
             ORDER BY mt.metric_name
        """, (model_id,))
        out["metrics"] = [
            {
                "name": str(r[0]).strip(),
                "type": str(r[1]).strip(),
                "description": (r[2] or None),
                "primary_dataset": (str(r[3]).strip() if r[3] else None),
                "is_certified": bool(r[4] or 0),
            } for r in cur.fetchall()
        ]

        cur.execute(f"""
            SELECT r.relationship_id, r.relationship_name,
                   df.dataset_name, dt.dataset_name,
                   r.cardinality, r.join_type_hint, r.role_name
              FROM {db}.RELATIONSHIP r
              JOIN {db}.DATASET df ON df.dataset_id = r.from_dataset_id
              JOIN {db}.DATASET dt ON dt.dataset_id = r.to_dataset_id
              JOIN {db}.MODEL_DATASET md ON md.dataset_id = r.from_dataset_id
             WHERE md.model_id = ?
             ORDER BY r.relationship_name
        """, (model_id,))
        rel_rows = cur.fetchall()
        rel_list: List[Dict[str, Any]] = []
        for r in rel_rows:
            rid = int(r[0])
            cur.execute(f"""
                SELECT ff.field_name, tf.field_name
                  FROM {db}.REL_COLUMN_MAP rcm
                  JOIN {db}.FIELD ff ON ff.field_id = rcm.from_field_id
                  JOIN {db}.FIELD tf ON tf.field_id = rcm.to_field_id
                 WHERE rcm.relationship_id = ?
                 ORDER BY rcm.column_position
            """, (rid,))
            cols = cur.fetchall()
            rel_list.append({
                "id": rid,
                "name": (str(r[1]).strip() if r[1] else None),
                "from": str(r[2]).strip(),
                "to": str(r[3]).strip(),
                "cardinality": str(r[4]).strip() if r[4] else None,
                "join_type_hint": str(r[5]).strip() if r[5] else None,
                "role_name": (str(r[6]).strip() if r[6] else None),
                "from_columns": [str(c[0]).strip() for c in cols],
                "to_columns":   [str(c[1]).strip() for c in cols],
            })
        out["relationships"] = rel_list

    return out
