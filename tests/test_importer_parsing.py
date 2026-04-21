"""Payload-parsing and topological ordering for the import endpoint.

These tests exercise the pure-Python side of the importer without touching
the DB. Each test feeds a YAML/JSON document to ``_ordered_items`` and
asserts the resulting entity stream is in a valid dependency order.
"""
from __future__ import annotations

import pytest

from semantic_catalog.importer.parser import (
    ordered_items as _ordered_items_impl,
    _norm_bool,
    _payload_for,
)


def _ordered_items(model, text, items):
    """Shim matching the pre-refactor signature used by these tests.

    Accepts both Pydantic ImportItem instances and raw dicts for the
    ``items`` argument, mirroring the endpoint's own tolerance.
    """
    if items:
        out = []
        for it in items:
            if hasattr(it, "kind"):
                kind, payload = it.kind, it.payload
            else:
                kind, payload = it["kind"], it["payload"]
            out.append((kind.upper(), _payload_for(kind, payload)))
        return out
    if not text:
        return []
    import yaml as _yaml
    try:
        doc = _yaml.safe_load(text)
    except _yaml.YAMLError as e:
        from fastapi import HTTPException
        raise HTTPException(400, f"Could not parse YAML/JSON: {e}")
    if doc is None:
        return []
    if not isinstance(doc, dict):
        from fastapi import HTTPException
        raise HTTPException(400, "Import payload must be a mapping at the top level")
    return _ordered_items_impl(doc)


def test_norm_bool_accepts_common_forms():
    assert _norm_bool(True) == 1
    assert _norm_bool("true") == 1
    assert _norm_bool("YES") == 1
    assert _norm_bool(1) == 1
    assert _norm_bool(0) == 0
    assert _norm_bool("no") == 0
    assert _norm_bool(None) == 0


def test_payload_coerces_booleans():
    out = _payload_for("FIELD", {"name":"x","dataset":"y","is_dimension": True,
                                 "is_time_dimension":"1"})
    assert out["is_dimension"] == 1
    assert out["is_time_dimension"] == 1


def test_orders_dataset_then_fields():
    text = """\
model: m
datasets:
  - name: customer
    source_table: db.customer
    fields:
      - name: c_custkey
        type: K
      - name: c_name
metrics:
  - name: customer_count
    primary_dataset: customer
    expressions:
      TERADATA: "COUNT(*)"
"""
    items = _ordered_items("m", text, None)
    kinds = [k for k, _ in items]
    assert kinds == ["DATASET", "FIELD", "FIELD", "METRIC", "METRIC_EXPR"]
    # check payloads are linked correctly
    assert items[1][1]["dataset"] == "customer"
    assert items[3][1]["name"] == "customer_count"
    assert items[4][1]["dialect"] == "TERADATA"


def test_relationships_emit_rel_col_after_relationship():
    text = """\
relationships:
  - name: order_to_customer
    from: orders
    to: customer
    cardinality: MANY_TO_ONE
    columns:
      - {from_field: o_custkey, to_field: c_custkey, position: 1}
"""
    items = _ordered_items("m", text, None)
    kinds = [k for k, _ in items]
    assert kinds == ["RELATIONSHIP", "REL_COL"]
    rel_col = items[1][1]
    assert rel_col["relationship"] == "order_to_customer"
    assert rel_col["from_dataset"] == "orders"
    assert rel_col["to_dataset"] == "customer"


def test_ai_context_last():
    text = """\
metrics:
  - name: m1
    primary_dataset: d
    expressions: {TERADATA: "1"}
ai_context:
  - entity_type: METRIC
    entity_name: m1
    synonyms: [a, b]
"""
    items = _ordered_items("m", text, None)
    assert items[0][0] == "METRIC"
    assert items[-1][0] == "AI_CONTEXT"


def test_items_passthrough():
    from semantic_catalog.api.models import ImportItem
    items_in = [ImportItem(kind="MODEL", payload={"name":"new_model"})]
    out = _ordered_items("new_model", None, items_in)
    assert out == [("MODEL", {"name": "new_model"})]


def test_empty_payload_is_empty_stream():
    assert _ordered_items("m", "", None) == []
    assert _ordered_items("m", "---\n", None) == []


def test_non_object_raises():
    from fastapi import HTTPException
    with pytest.raises(HTTPException):
        _ordered_items("m", "- just a list", None)
