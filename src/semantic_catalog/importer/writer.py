"""Pure-Python catalog writer.

One ``import_entity(cur, db, model_name, kind, payload)`` call per entity
— mirrors the SP contract. The writer resolves parent FKs via SELECTs on
the catalog, then INSERTs (or UPDATEs when the natural key exists).

Teradata has no ``RETURNING`` or ``SCOPE_IDENTITY()``, so after inserting
into an IDENTITY table we SELECT the new id by natural key.

Supported kinds:
  MODEL, DATASET, FIELD, METRIC, METRIC_EXPR, METRIC_FILTER,
  RELATIONSHIP, REL_COL, VIEW, VIEW_MEMBER, HIERARCHY, HIERARCHY_LEVEL,
  AI_CONTEXT.
"""
from __future__ import annotations

import json
from typing import Any, Dict, Optional, Tuple


class ImportError_(Exception):
    """Raised on recoverable per-entity errors. The caller maps this to
    status=ERROR and continues; ImportError_ must NOT escape the importer.
    """


Status = str
Message = str
EntityId = Optional[int]


KINDS = (
    "MODEL", "DATASET", "FIELD",
    "METRIC", "METRIC_EXPR", "METRIC_FILTER",
    "RELATIONSHIP", "REL_COL",
    "VIEW", "VIEW_MEMBER",
    "HIERARCHY", "HIERARCHY_LEVEL",
    "AI_CONTEXT",
)


# ---- helpers ---------------------------------------------------------

def _fetchone(cur, sql: str, *params: Any):
    cur.execute(sql, params if params else None)
    return cur.fetchone()


def _require(payload: Dict[str, Any], *keys: str) -> None:
    missing = [k for k in keys if payload.get(k) in (None, "")]
    if missing:
        raise ImportError_(f"missing required fields: {', '.join(missing)}")


def _scalar(cur, sql: str, *params: Any):
    row = _fetchone(cur, sql, *params)
    return row[0] if row else None


def _resolve_model_id(cur, db: str, model_name: str) -> Optional[int]:
    r = _fetchone(cur, f"SELECT model_id FROM {db}.SEMANTIC_MODEL WHERE model_name = ?",
                  model_name)
    return int(r[0]) if r else None


def _resolve_dataset_id(cur, db: str, model_id: int, dataset_name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"SELECT dataset_id FROM {db}.DATASET "
                  f"WHERE model_id = ? AND dataset_name = ?",
                  model_id, dataset_name)
    return int(r[0]) if r else None


def _resolve_field_id(cur, db: str, dataset_id: int, field_name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"SELECT field_id FROM {db}.FIELD "
                  f"WHERE dataset_id = ? AND field_name = ?",
                  dataset_id, field_name)
    return int(r[0]) if r else None


def _resolve_metric_id(cur, db: str, model_id: int, metric_name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"SELECT metric_id FROM {db}.METRIC "
                  f"WHERE model_id = ? AND metric_name = ?",
                  model_id, metric_name)
    return int(r[0]) if r else None


def _resolve_view_id(cur, db: str, model_id: int, view_name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"SELECT view_id FROM {db}.SEMANTIC_VIEW "
                  f"WHERE model_id = ? AND view_name = ?",
                  model_id, view_name)
    return int(r[0]) if r else None


def _resolve_hierarchy_id(cur, db: str, model_id: int, name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"SELECT hierarchy_id FROM {db}.FIELD_HIERARCHY "
                  f"WHERE model_id = ? AND hierarchy_name = ?",
                  model_id, name)
    return int(r[0]) if r else None


def _resolve_relationship_id(cur, db: str, model_id: int, rel_name: str) -> Optional[int]:
    r = _fetchone(cur,
                  f"""SELECT r.relationship_id
                        FROM {db}.RELATIONSHIP r
                        JOIN {db}.DATASET df ON df.dataset_id = r.from_dataset_id
                       WHERE df.model_id = ? AND r.relationship_name = ?""",
                  model_id, rel_name)
    return int(r[0]) if r else None


def _split_source_table(src: str) -> Tuple[Optional[str], Optional[str]]:
    if not src:
        return None, None
    if "." in src:
        db, tbl = src.split(".", 1)
        return db.strip(), tbl.strip()
    return None, src.strip()


def _upsert(cur, exists: bool, insert_sql: str, insert_params: tuple,
            update_sql: Optional[str] = None,
            update_params: Optional[tuple] = None) -> None:
    if exists and update_sql:
        cur.execute(update_sql, update_params)
    elif not exists:
        cur.execute(insert_sql, insert_params)


# ---- per-kind writers ------------------------------------------------

def _write_model(cur, db: str, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "name")
    name = p["name"]
    existing = _resolve_model_id(cur, db, name)
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.SEMANTIC_MODEL "
            f"SET description = ?, owner_user = ?, owner_group = ?, "
            f"updated_ts = CURRENT_TIMESTAMP(6) WHERE model_id = ?",
            (p.get("description"), p.get("owner_user"), p.get("owner_group"), existing),
        )
        return "OK", f"updated model {name}", existing
    cur.execute(
        f"INSERT INTO {db}.SEMANTIC_MODEL "
        f"(model_name, description, owner_user, owner_group) VALUES (?, ?, ?, ?)",
        (name, p.get("description"), p.get("owner_user"), p.get("owner_group")),
    )
    new_id = _resolve_model_id(cur, db, name)
    return "OK", f"inserted model {name}", new_id


def _write_dataset(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "name")
    name = p["name"]
    dbn, tbl = _split_source_table(p.get("source_table") or "")
    existing = _resolve_dataset_id(cur, db, model_id, name)
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.DATASET "
            f"SET description = ?, granularity_desc = ?, "
            f"    DataBaseName = ?, TableName = ?, source_query = ?, "
            f"    updated_ts = CURRENT_TIMESTAMP(6) WHERE dataset_id = ?",
            (p.get("description"), p.get("granularity"), dbn, tbl,
             p.get("source_query"), existing),
        )
        return "OK", f"updated dataset {name}", existing
    cur.execute(
        f"INSERT INTO {db}.DATASET "
        f"(model_id, dataset_name, description, granularity_desc, "
        f" DataBaseName, TableName, source_query) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?)",
        (model_id, name, p.get("description"), p.get("granularity"),
         dbn, tbl, p.get("source_query")),
    )
    new_id = _resolve_dataset_id(cur, db, model_id, name)
    return "OK", f"inserted dataset {name}", new_id


def _write_field(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "dataset", "name")
    ds_id = _resolve_dataset_id(cur, db, model_id, p["dataset"])
    if ds_id is None:
        raise ImportError_(f"unknown dataset '{p['dataset']}'")
    name = p["name"]
    existing = _resolve_field_id(cur, db, ds_id, name)
    type_code = str(p.get("type") or "A").upper()[:1]
    if type_code not in ("A", "K"):
        raise ImportError_(f"field '{name}': type must be 'A' (attribute) or 'K' (key)")
    is_dim = int(p.get("is_dimension", 1))
    is_tdim = int(p.get("is_time_dimension", 0))
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.FIELD "
            f"SET field_type_code = ?, expression = ?, description = ?, label = ?, "
            f"    is_dimension = ?, is_time_dimension = ?, data_type = ?, "
            f"    ColumnName = ?, field_order = ? WHERE field_id = ?",
            (type_code, p.get("expression"), p.get("description"), p.get("label"),
             is_dim, is_tdim, p.get("data_type"), p.get("column_name"),
             int(p.get("field_order") or 0), existing),
        )
        return "OK", f"updated field {p['dataset']}.{name}", existing
    cur.execute(
        f"INSERT INTO {db}.FIELD "
        f"(dataset_id, field_name, field_type_code, expression, description, "
        f" label, is_dimension, is_time_dimension, data_type, ColumnName, field_order) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (ds_id, name, type_code, p.get("expression"), p.get("description"),
         p.get("label"), is_dim, is_tdim, p.get("data_type"),
         p.get("column_name"), int(p.get("field_order") or 0)),
    )
    new_id = _resolve_field_id(cur, db, ds_id, name)
    return "OK", f"inserted field {p['dataset']}.{name}", new_id


def _write_metric(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "name")
    name = p["name"]
    primary_ds_id: Optional[int] = None
    if p.get("primary_dataset"):
        primary_ds_id = _resolve_dataset_id(cur, db, model_id, p["primary_dataset"])
        if primary_ds_id is None:
            raise ImportError_(f"metric '{name}': unknown primary_dataset '{p['primary_dataset']}'")
    base_id: Optional[int] = None
    if p.get("base_metric"):
        base_id = _resolve_metric_id(cur, db, model_id, p["base_metric"])
        if base_id is None:
            raise ImportError_(f"metric '{name}': unknown base_metric '{p['base_metric']}'")
    existing = _resolve_metric_id(cur, db, model_id, name)
    mtype = p.get("metric_type") or "SIMPLE"
    is_add = int(p.get("is_additive", 1))
    is_cert = int(p.get("is_certified", 0))
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.METRIC "
            f"SET description = ?, primary_dataset_id = ?, metric_type = ?, "
            f"    is_additive = ?, is_certified = ?, owner_team = ?, "
            f"    default_time_grain = ?, base_metric_id = ?, "
            f"    aggregate_fn = ?, aggregate_arg = ?, "
            f"    updated_ts = CURRENT_TIMESTAMP(6) WHERE metric_id = ?",
            (p.get("description"), primary_ds_id, mtype, is_add, is_cert,
             p.get("owner_team"), p.get("default_time_grain"),
             base_id, p.get("aggregate_fn"), p.get("aggregate_arg"), existing),
        )
        return "OK", f"updated metric {name}", existing
    cur.execute(
        f"INSERT INTO {db}.METRIC "
        f"(model_id, metric_name, description, primary_dataset_id, metric_type, "
        f" is_additive, is_certified, owner_team, default_time_grain, "
        f" base_metric_id, aggregate_fn, aggregate_arg) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (model_id, name, p.get("description"), primary_ds_id, mtype,
         is_add, is_cert, p.get("owner_team"), p.get("default_time_grain"),
         base_id, p.get("aggregate_fn"), p.get("aggregate_arg")),
    )
    new_id = _resolve_metric_id(cur, db, model_id, name)
    return "OK", f"inserted metric {name}", new_id


def _write_metric_expr(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "metric", "dialect", "expression")
    met_id = _resolve_metric_id(cur, db, model_id, p["metric"])
    if met_id is None:
        raise ImportError_(f"unknown metric '{p['metric']}'")
    dialect = str(p["dialect"]).upper()
    # upsert on (metric_id, dialect)
    r = _fetchone(cur,
                  f"SELECT 1 FROM {db}.METRIC_EXPRESSION "
                  f"WHERE metric_id = ? AND dialect = ?",
                  met_id, dialect)
    if r:
        cur.execute(
            f"UPDATE {db}.METRIC_EXPRESSION SET expression = ? "
            f"WHERE metric_id = ? AND dialect = ?",
            (p["expression"], met_id, dialect),
        )
        return "OK", f"updated expression {p['metric']}[{dialect}]", met_id
    cur.execute(
        f"INSERT INTO {db}.METRIC_EXPRESSION (metric_id, dialect, expression) "
        f"VALUES (?, ?, ?)",
        (met_id, dialect, p["expression"]),
    )
    return "OK", f"inserted expression {p['metric']}[{dialect}]", met_id


def _write_metric_filter(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "metric", "field", "op", "filter_value")
    met_id = _resolve_metric_id(cur, db, model_id, p["metric"])
    if met_id is None:
        raise ImportError_(f"unknown metric '{p['metric']}'")
    # Field reference: "dataset.field_name" or {dataset: x, field: y}
    ds_name = p.get("dataset")
    field_name = p.get("field") or ""
    if "." in field_name and ds_name is None:
        ds_name, field_name = field_name.split(".", 1)
    _require({"dataset": ds_name, "field": field_name}, "dataset", "field")
    ds_id = _resolve_dataset_id(cur, db, model_id, ds_name)
    if ds_id is None:
        raise ImportError_(f"unknown dataset '{ds_name}' on metric filter")
    fld_id = _resolve_field_id(cur, db, ds_id, field_name)
    if fld_id is None:
        raise ImportError_(f"unknown field '{ds_name}.{field_name}'")
    ord_ = int(p.get("filter_ord") or 1)
    # Upsert on (metric_id, filter_ord)
    r = _fetchone(cur,
                  f"SELECT 1 FROM {db}.METRIC_FILTER "
                  f"WHERE metric_id = ? AND filter_ord = ?",
                  met_id, ord_)
    if r:
        cur.execute(
            f"UPDATE {db}.METRIC_FILTER "
            f"SET field_id = ?, op = ?, filter_value = ? "
            f"WHERE metric_id = ? AND filter_ord = ?",
            (fld_id, p["op"], str(p["filter_value"]), met_id, ord_),
        )
        return "OK", f"updated metric_filter {p['metric']}[{ord_}]", met_id
    cur.execute(
        f"INSERT INTO {db}.METRIC_FILTER "
        f"(metric_id, filter_ord, field_id, op, filter_value) "
        f"VALUES (?, ?, ?, ?, ?)",
        (met_id, ord_, fld_id, p["op"], str(p["filter_value"])),
    )
    return "OK", f"inserted metric_filter {p['metric']}[{ord_}]", met_id


def _write_relationship(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "from", "to")
    from_id = _resolve_dataset_id(cur, db, model_id, p["from"])
    to_id   = _resolve_dataset_id(cur, db, model_id, p["to"])
    if from_id is None or to_id is None:
        raise ImportError_(f"relationship endpoints not found "
                           f"(from={p['from']}, to={p['to']})")
    name = p.get("name") or f"{p['from']}_to_{p['to']}"
    card = (p.get("cardinality") or "MANY_TO_ONE").upper()
    join_hint = p.get("join_type") or "INNER"
    role = p.get("role_name") or p.get("role")
    existing = _resolve_relationship_id(cur, db, model_id, name)
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.RELATIONSHIP "
            f"SET from_dataset_id = ?, to_dataset_id = ?, cardinality = ?, "
            f"    join_type_hint = ?, role_name = ?, description = ? "
            f"WHERE relationship_id = ?",
            (from_id, to_id, card, join_hint, role, p.get("description"), existing),
        )
        return "OK", f"updated relationship {name}", existing
    cur.execute(
        f"INSERT INTO {db}.RELATIONSHIP "
        f"(relationship_name, from_dataset_id, to_dataset_id, cardinality, "
        f" join_type_hint, role_name, description) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?)",
        (name, from_id, to_id, card, join_hint, role, p.get("description")),
    )
    new_id = _resolve_relationship_id(cur, db, model_id, name)
    return "OK", f"inserted relationship {name}", new_id


def _write_rel_col(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "relationship", "from_dataset", "to_dataset", "from_field", "to_field")
    rel_id = _resolve_relationship_id(cur, db, model_id, p["relationship"])
    if rel_id is None:
        raise ImportError_(f"unknown relationship '{p['relationship']}'")
    from_ds_id = _resolve_dataset_id(cur, db, model_id, p["from_dataset"])
    to_ds_id   = _resolve_dataset_id(cur, db, model_id, p["to_dataset"])
    if from_ds_id is None or to_ds_id is None:
        raise ImportError_(f"rel_col endpoint datasets not found")
    from_fid = _resolve_field_id(cur, db, from_ds_id, p["from_field"])
    to_fid   = _resolve_field_id(cur, db, to_ds_id, p["to_field"])
    if from_fid is None or to_fid is None:
        raise ImportError_(f"rel_col endpoint fields not found")
    pos = int(p.get("position") or p.get("column_position") or 1)
    # Delete + insert for simplicity (rare upsert case).
    cur.execute(
        f"DELETE FROM {db}.REL_COLUMN_MAP "
        f"WHERE relationship_id = ? AND column_position = ?",
        (rel_id, pos),
    )
    cur.execute(
        f"INSERT INTO {db}.REL_COLUMN_MAP "
        f"(relationship_id, from_field_id, to_field_id, column_position) "
        f"VALUES (?, ?, ?, ?)",
        (rel_id, from_fid, to_fid, pos),
    )
    return "OK", f"inserted rel_col {p['relationship']}[{pos}]", rel_id


def _write_view(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "name")
    name = p["name"]
    pds_id: Optional[int] = None
    if p.get("primary_dataset"):
        pds_id = _resolve_dataset_id(cur, db, model_id, p["primary_dataset"])
        if pds_id is None:
            raise ImportError_(f"view '{name}': unknown primary_dataset")
    existing = _resolve_view_id(cur, db, model_id, name)
    is_cert = int(p.get("is_certified", 0))
    is_pub  = int(p.get("is_public", 1))
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.SEMANTIC_VIEW SET description = ?, primary_dataset_id = ?, "
            f"   timeseries_field = ?, is_certified = ?, is_public = ?, "
            f"   owner_user = ? WHERE view_id = ?",
            (p.get("description"), pds_id, p.get("timeseries_field"),
             is_cert, is_pub, p.get("owner_user"), existing),
        )
        return "OK", f"updated view {name}", existing
    cur.execute(
        f"INSERT INTO {db}.SEMANTIC_VIEW "
        f"(model_id, view_name, description, primary_dataset_id, "
        f" timeseries_field, is_certified, is_public, owner_user) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (model_id, name, p.get("description"), pds_id,
         p.get("timeseries_field"), is_cert, is_pub, p.get("owner_user")),
    )
    new_id = _resolve_view_id(cur, db, model_id, name)
    return "OK", f"inserted view {name}", new_id


def _write_view_member(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "view", "name", "member_type")
    view_id = _resolve_view_id(cur, db, model_id, p["view"])
    if view_id is None:
        raise ImportError_(f"unknown view '{p['view']}'")
    field_id: Optional[int] = None
    if p.get("field"):
        parent = p.get("parent_dataset") or p.get("dataset")
        if not parent:
            raise ImportError_("view_member: field reference needs parent_dataset")
        ds_id = _resolve_dataset_id(cur, db, model_id, parent)
        if ds_id is None:
            raise ImportError_(f"view_member: unknown dataset '{parent}'")
        field_id = _resolve_field_id(cur, db, ds_id, p["field"])
        if field_id is None:
            raise ImportError_(f"view_member: unknown field '{parent}.{p['field']}'")
    metric_id: Optional[int] = None
    if p.get("metric"):
        metric_id = _resolve_metric_id(cur, db, model_id, p["metric"])
        if metric_id is None:
            raise ImportError_(f"view_member: unknown metric '{p['metric']}'")
    ord_ = int(p.get("ordinal") or 1)
    # Upsert on (view_id, member_ordinal)
    cur.execute(
        f"DELETE FROM {db}.VIEW_MEMBER "
        f"WHERE view_id = ? AND member_ordinal = ?",
        (view_id, ord_),
    )
    cur.execute(
        f"INSERT INTO {db}.VIEW_MEMBER "
        f"(view_id, member_ordinal, member_name, member_type, field_id, "
        f" metric_id, inline_expression, display_name, is_public, member_order) "
        f"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (view_id, ord_, p["name"], str(p["member_type"]).upper(),
         field_id, metric_id, p.get("inline_expression"),
         p.get("display_name"), int(p.get("is_public", 1)),
         int(p.get("member_order") or p.get("ordinal") or 0)),
    )
    return "OK", f"inserted view_member {p['view']}.{p['name']}", view_id


def _write_hierarchy(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "name")
    name = p["name"]
    existing = _resolve_hierarchy_id(cur, db, model_id, name)
    if existing is not None:
        cur.execute(
            f"UPDATE {db}.FIELD_HIERARCHY SET description = ? WHERE hierarchy_id = ?",
            (p.get("description"), existing),
        )
        return "OK", f"updated hierarchy {name}", existing
    cur.execute(
        f"INSERT INTO {db}.FIELD_HIERARCHY (model_id, hierarchy_name, description) "
        f"VALUES (?, ?, ?)",
        (model_id, name, p.get("description")),
    )
    new_id = _resolve_hierarchy_id(cur, db, model_id, name)
    return "OK", f"inserted hierarchy {name}", new_id


def _write_hierarchy_level(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "hierarchy", "level_ord", "field")
    h_id = _resolve_hierarchy_id(cur, db, model_id, p["hierarchy"])
    if h_id is None:
        raise ImportError_(f"unknown hierarchy '{p['hierarchy']}'")
    ds_name = p.get("dataset")
    field_name = p["field"]
    if "." in field_name and ds_name is None:
        ds_name, field_name = field_name.split(".", 1)
    if not ds_name:
        raise ImportError_("hierarchy_level: field must be prefixed with dataset")
    ds_id = _resolve_dataset_id(cur, db, model_id, ds_name)
    fid = _resolve_field_id(cur, db, ds_id, field_name) if ds_id else None
    if fid is None:
        raise ImportError_(f"unknown field '{ds_name}.{field_name}'")
    ord_ = int(p["level_ord"])
    cur.execute(
        f"DELETE FROM {db}.FIELD_HIERARCHY_LEVEL "
        f"WHERE hierarchy_id = ? AND level_ord = ?",
        (h_id, ord_),
    )
    cur.execute(
        f"INSERT INTO {db}.FIELD_HIERARCHY_LEVEL "
        f"(hierarchy_id, level_ord, field_id, level_name) VALUES (?, ?, ?, ?)",
        (h_id, ord_, fid, p.get("level_name")),
    )
    return "OK", f"inserted hierarchy_level {p['hierarchy']}[{ord_}]", h_id


def _write_ai_context(cur, db: str, model_id: int, p: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    _require(p, "entity_type", "entity_name")
    et = str(p["entity_type"]).upper()
    en = p["entity_name"]
    entity_id: Optional[int] = None
    if et == "MODEL":
        entity_id = _resolve_model_id(cur, db, en)
    elif et == "DATASET":
        entity_id = _resolve_dataset_id(cur, db, model_id, en)
    elif et == "FIELD":
        parent = p.get("parent")
        if not parent or "." not in (parent or en):
            # accept "dataset.field" as entity_name
            if "." in en:
                parent, en = en.split(".", 1)
        if parent:
            ds_id = _resolve_dataset_id(cur, db, model_id, parent)
            if ds_id:
                entity_id = _resolve_field_id(cur, db, ds_id, en)
    elif et == "METRIC":
        entity_id = _resolve_metric_id(cur, db, model_id, en)
    elif et == "VIEW":
        entity_id = _resolve_view_id(cur, db, model_id, en)
    else:
        raise ImportError_(f"unsupported ai_context entity_type '{et}'")
    if entity_id is None:
        raise ImportError_(f"ai_context: could not resolve {et} '{en}'")

    synonyms = p.get("synonyms")
    examples = p.get("examples")
    syn_json = json.dumps(synonyms) if synonyms is not None else None
    ex_json  = json.dumps(examples) if examples is not None else None

    # Upsert on (entity_type, entity_id)
    cur.execute(
        f"DELETE FROM {db}.AI_CONTEXT WHERE entity_type = ? AND entity_id = ?",
        (et, entity_id),
    )
    cur.execute(
        f"INSERT INTO {db}.AI_CONTEXT "
        f"(entity_type, entity_id, instructions, synonyms, examples, display_name) "
        f"VALUES (?, ?, ?, ?, ?, ?)",
        (et, entity_id, p.get("instructions"), syn_json, ex_json, p.get("display_name")),
    )
    return "OK", f"inserted ai_context {et}:{en}", entity_id


# ---- top-level dispatch ---------------------------------------------

def import_entity(cur, db: str, model_name: str,
                  kind: str, payload: Dict[str, Any]) -> Tuple[Status, Message, EntityId]:
    """Import one entity. Returns (status, message, entity_id).

    On a recoverable failure (bad FK, missing field, etc.) this returns
    status="ERROR" rather than raising; the caller decides whether to
    roll back the batch. Only truly unexpected exceptions escape.
    """
    kind = (kind or "").upper()
    if kind not in KINDS:
        return "ERROR", f"unsupported kind '{kind}'", None

    try:
        if kind == "MODEL":
            return _write_model(cur, db, payload)

        # All other kinds need an existing model.
        model_id = _resolve_model_id(cur, db, model_name)
        if model_id is None:
            return "ERROR", f"unknown model '{model_name}'", None

        if kind == "DATASET":
            return _write_dataset(cur, db, model_id, payload)
        if kind == "FIELD":
            return _write_field(cur, db, model_id, payload)
        if kind == "METRIC":
            return _write_metric(cur, db, model_id, payload)
        if kind == "METRIC_EXPR":
            return _write_metric_expr(cur, db, model_id, payload)
        if kind == "METRIC_FILTER":
            return _write_metric_filter(cur, db, model_id, payload)
        if kind == "RELATIONSHIP":
            return _write_relationship(cur, db, model_id, payload)
        if kind == "REL_COL":
            return _write_rel_col(cur, db, model_id, payload)
        if kind == "VIEW":
            return _write_view(cur, db, model_id, payload)
        if kind == "VIEW_MEMBER":
            return _write_view_member(cur, db, model_id, payload)
        if kind == "HIERARCHY":
            return _write_hierarchy(cur, db, model_id, payload)
        if kind == "HIERARCHY_LEVEL":
            return _write_hierarchy_level(cur, db, model_id, payload)
        if kind == "AI_CONTEXT":
            return _write_ai_context(cur, db, model_id, payload)
        return "ERROR", f"no writer for kind '{kind}'", None
    except ImportError_ as e:
        return "ERROR", str(e), None
