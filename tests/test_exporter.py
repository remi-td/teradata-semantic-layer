"""Unit tests for the OSI exporter — FakeCursor-driven, no DB required."""
from __future__ import annotations

from typing import Any, List, Optional, Tuple

import yaml

from semantic_catalog.exporter import build_osi_document, export_osi_yaml


class ScriptedCursor:
    """FIFO-matched cursor. Each ``execute`` dequeues the next scripted
    result; ``fetchone`` / ``fetchall`` return it."""

    def __init__(self) -> None:
        self.calls: List[Tuple[str, Optional[Tuple[Any, ...]]]] = []
        self._script: List[List[Tuple[Any, ...]]] = []
        self._current: List[Tuple[Any, ...]] = []

    def script(self, rows: List[Tuple[Any, ...]]) -> None:
        self._script.append(rows)

    def execute(self, sql: str, params: Any = None) -> None:
        self.calls.append((sql.strip(), tuple(params) if params else None))
        self._current = self._script.pop(0) if self._script else []

    def fetchone(self) -> Any:
        return self._current[0] if self._current else None

    def fetchall(self) -> List[Tuple[Any, ...]]:
        out, self._current = self._current, []
        return out


DB = "demo_user"


def test_unknown_model_returns_none() -> None:
    cur = ScriptedCursor()
    cur.script([])  # SEMANTIC_MODEL lookup misses
    assert build_osi_document(cur, DB, "missing") is None
    assert export_osi_yaml(cur, DB, "missing") is None


def test_minimal_model_exports_shape() -> None:
    cur = ScriptedCursor()
    # Model lookup
    cur.script([(1, "tpch", "Orders example")])
    # Datasets
    cur.script([(10, "lineitem", "Line items", None, "tpch", "lineitem", None)])
    # Fields (ordered by field_order, field_name)
    cur.script([
        (100, "l_orderkey", "K", "l_orderkey", None, None, 0, 0, "INTEGER", "l_orderkey"),
        (101, "l_quantity", "A", "l_quantity", None, None, 1, 0, "DECIMAL", "l_quantity"),
    ])
    # DATASET_KEY PK
    cur.script([("l_orderkey",)])
    # AI_CONTEXT DATASET — none
    cur.script([])
    # DATASET re-query for name_by_id in _build_relationships
    cur.script([(10, "lineitem")])
    # RELATIONSHIPS
    cur.script([])
    # METRICS
    cur.script([(50, "revenue", "Sum of price", "SIMPLE")])
    # METRIC_EXPRESSION
    cur.script([("TERADATA", "SUM(lineitem.l_extendedprice)")])
    # AI_CONTEXT METRIC
    cur.script([])
    # AI_CONTEXT MODEL
    cur.script([])

    doc = build_osi_document(cur, DB, "tpch")
    assert doc is not None
    assert doc["version"] == "0.1.1"
    sm = doc["semantic_model"][0]
    assert sm["name"] == "tpch"
    assert sm["description"] == "Orders example"
    ds = sm["datasets"][0]
    assert ds["name"] == "lineitem"
    assert ds["source"] == "tpch.lineitem"
    assert ds["primary_key"] == ["l_orderkey"]
    fields = ds["fields"]
    assert {f["name"] for f in fields} == {"l_orderkey", "l_quantity"}
    # key flag only on l_orderkey
    assert next(f for f in fields if f["name"] == "l_orderkey").get("key") is True
    assert next(f for f in fields if f["name"] == "l_quantity").get("key") is None
    met = sm["metrics"][0]
    assert met["name"] == "revenue"
    assert met["expression"]["dialects"][0]["dialect"] == "TERADATA"


def test_exported_yaml_is_parseable_and_round_trips() -> None:
    cur = ScriptedCursor()
    cur.script([(1, "m", None)])
    cur.script([])           # no datasets
    cur.script([])           # no datasets (relationships' re-query)
    cur.script([])           # no relationships
    cur.script([])           # no metrics
    cur.script([])           # no model-level AI context
    text = export_osi_yaml(cur, DB, "m")
    assert text is not None
    reloaded = yaml.safe_load(text)
    assert reloaded["version"] == "0.1.1"
    assert reloaded["semantic_model"][0]["name"] == "m"


def test_relationship_rendering_includes_cols() -> None:
    cur = ScriptedCursor()
    cur.script([(1, "m", None)])
    # Datasets
    cur.script([
        (1, "orders",   None, None, "tpch", "orders",   None),
        (2, "customer", None, None, "tpch", "customer", None),
    ])
    # Fields for dataset 1 (orders) + PK + AI
    cur.script([(10, "o_custkey", "K", "o_custkey", None, None, 0, 0, "INTEGER", "o_custkey")])
    cur.script([("o_custkey",)])       # PK
    cur.script([])                      # DATASET AI ctx
    # Fields for dataset 2 (customer) + PK + AI
    cur.script([(20, "c_custkey", "K", "c_custkey", None, None, 0, 0, "INTEGER", "c_custkey")])
    cur.script([("c_custkey",)])
    cur.script([])
    # Relationship section: DATASET re-query for name map
    cur.script([(1, "orders"), (2, "customer")])
    # RELATIONSHIPS
    cur.script([(77, "order_to_customer", 1, 2, "MANY_TO_ONE", None)])
    # REL_COLUMN_MAP cols for 77
    cur.script([("o_custkey", "c_custkey")])
    # METRICS (none)
    cur.script([])
    # model AI ctx
    cur.script([])

    doc = build_osi_document(cur, DB, "m")
    rels = doc["semantic_model"][0]["relationships"]
    assert len(rels) == 1
    r = rels[0]
    assert r["from"] == "orders" and r["to"] == "customer"
    assert r["from_columns"] == ["o_custkey"] and r["to_columns"] == ["c_custkey"]
    assert r["cardinality"] == "MANY_TO_ONE"


def test_ai_context_synonyms_parsed_from_json_string() -> None:
    cur = ScriptedCursor()
    cur.script([(1, "m", None)])
    cur.script([])            # datasets
    cur.script([])            # relationships re-query
    cur.script([])            # relationships
    cur.script([])            # metrics
    cur.script([("hello there", '["sales", "revenue"]', None, "Revenue")])  # model AI ctx
    doc = build_osi_document(cur, DB, "m")
    ac = doc["semantic_model"][0]["ai_context"]
    assert ac["instructions"] == "hello there"
    assert ac["synonyms"] == ["sales", "revenue"]
    assert ac["display_name"] == "Revenue"
