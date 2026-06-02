"""Pure-Python importer tests — FakeCursor-driven.

The FakeCursor records every (sql, params) pair the importer issues and
serves scripted results for SELECTs. Tests assert both the DML sequence
and the resolved-id accounting that would run against a real Teradata.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

import pytest

from semantic_catalog.importer import (
    import_entity,
    ordered_items,
    synthesize_filtered_expressions,
)


class FakeCursor:
    """Records executed SQL and serves fetchone results from a scripted
    queue keyed by (sql_prefix, params) matched in order."""

    def __init__(self) -> None:
        self.calls: List[Tuple[str, Optional[Tuple[Any, ...]]]] = []
        # Scripted results — consumed in FIFO for matching SELECTs.
        self.scripted: List[Any] = []
        # Default returns for INSERT/UPDATE/DELETE: None for fetchone.
        self._last_fetch: Any = None

    def script(self, *rows: Any) -> None:
        self.scripted.extend(rows)

    def execute(self, sql: str, params: Any = None) -> None:
        self.calls.append((sql.strip(), tuple(params) if params else None))
        # SELECT returns next scripted value
        norm = sql.strip().upper()
        if norm.startswith("SELECT"):
            self._last_fetch = self.scripted.pop(0) if self.scripted else None
        else:
            self._last_fetch = None

    def fetchone(self) -> Any:
        return self._last_fetch

    def fetchall(self) -> Any:
        # Tests that drive a multi-row result script a list-of-tuples
        # explicitly; tests that don't call fetchall stay unaffected.
        if self._last_fetch is None:
            return []
        return self._last_fetch

    def close(self) -> None:
        pass


DB = "demo_user"


# --------- parser tests ----------------------------------------------

def test_parser_orders_dataset_then_fields_then_metric_with_filters() -> None:
    doc = {
        "models": [{"name": "m", "description": "x"}],
        "datasets": [{
            "name": "fact", "source_table": "db.fact",
            "fields": [{"name": "amt"}, {"name": "cat"}],
        }],
        "metrics": [{
            "name": "total", "primary_dataset": "fact",
            "aggregate_fn": "SUM", "aggregate_arg": "fact.amt",
            "expressions": {"TERADATA": "SUM(fact.amt)"},
            "filters": [{"field": "fact.cat", "op": "=", "filter_value": "'A'",
                         "filter_ord": 1}],
        }],
    }
    items = ordered_items(doc)
    kinds = [k for k, _ in items]
    assert kinds == [
        "MODEL",
        "DATASET", "FIELD", "FIELD",
        "METRIC", "METRIC_EXPR", "METRIC_FILTER",
    ]


def test_parser_handles_hierarchies() -> None:
    doc = {
        "hierarchies": [{
            "name": "customer_geo", "description": "country > city",
            "levels": [
                {"level_ord": 1, "field": "country"},
                {"level_ord": 2, "field": "city"},
            ],
        }],
    }
    items = ordered_items(doc)
    assert [k for k, _ in items] == ["HIERARCHY", "HIERARCHY_LEVEL", "HIERARCHY_LEVEL"]


# --------- writer tests — direct DML inspection ----------------------

def test_model_insert_then_upsert() -> None:
    cur = FakeCursor()
    # First call: _resolve_model_id returns None → INSERT + re-resolve
    cur.script(None)              # existing check
    cur.script([42])              # post-insert id lookup
    status, msg, eid = import_entity(cur, DB, "m", "MODEL",
                                     {"name": "m", "description": "hi"})
    assert status == "OK" and eid == 42 and "inserted" in msg
    # Second call: existing → UPDATE
    cur = FakeCursor()
    cur.script([42])              # existing check returns id
    status, _, eid = import_entity(cur, DB, "m", "MODEL", {"name": "m"})
    assert status == "OK" and eid == 42
    # Second call must have emitted an UPDATE
    assert any("UPDATE demo_user.SEMANTIC_MODEL" in sql for sql, _ in cur.calls)


def test_dataset_splits_source_table() -> None:
    cur = FakeCursor()
    cur.script([1])               # model_id
    cur.script(None)              # existing dataset check (global by name)
    cur.script([7])               # post-insert id lookup
    cur.script(None)              # MODEL_DATASET link check (no existing link)
    status, _, eid = import_entity(cur, DB, "m", "DATASET",
                                   {"name": "fact", "source_table": "raw.fact_tbl"})
    assert status == "OK" and eid == 7
    insert = next(sql for sql, _ in cur.calls if "INSERT INTO demo_user.DATASET" in sql)
    # params: 0: dataset_name, 3: DataBaseName, 4: TableName
    params = next(p for sql, p in cur.calls if sql == insert)
    assert params[3] == "raw" and params[4] == "fact_tbl"


def test_field_requires_known_dataset() -> None:
    cur = FakeCursor()
    cur.script([1])               # model_id
    cur.script(None)              # dataset lookup misses
    status, msg, _ = import_entity(cur, DB, "m", "FIELD",
                                   {"dataset": "ghost", "name": "x"})
    assert status == "ERROR" and "ghost" in msg


def test_field_insert_then_update() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id
    cur.script([3])              # dataset_id
    cur.script(None)             # existing field
    cur.script([99])             # post-insert field id
    status, _, eid = import_entity(cur, DB, "m", "FIELD",
                                   {"dataset": "fact", "name": "amt",
                                    "type": "A", "is_dimension": True})
    assert status == "OK" and eid == 99
    # Second pass: field exists → UPDATE
    cur = FakeCursor()
    cur.script([1])
    cur.script([3])
    cur.script([99])
    status, _, eid = import_entity(cur, DB, "m", "FIELD",
                                   {"dataset": "fact", "name": "amt"})
    assert any(sql.startswith("UPDATE demo_user.FIELD") for sql, _ in cur.calls)


def test_metric_with_base_and_aggregate_fields() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id
    cur.script([5])              # primary_dataset lookup
    cur.script([10])             # base_metric lookup
    cur.script(None)             # existing metric
    cur.script([77])             # post-insert metric id
    status, _, eid = import_entity(
        cur, DB, "m", "METRIC",
        {"name": "x_total", "primary_dataset": "fact",
         "base_metric": "x_total_base", "aggregate_fn": "SUM",
         "aggregate_arg": "fact.amt"},
    )
    assert status == "OK" and eid == 77
    insert_params = next(p for sql, p in cur.calls if "INSERT INTO demo_user.METRIC" in sql)
    # (model_id, metric_name, desc, primary_dataset_id, metric_type,
    #  is_additive, is_certified, owner_team, default_time_grain,
    #  base_metric_id, aggregate_fn, aggregate_arg)
    assert insert_params[0] == 1
    assert insert_params[3] == 5      # primary_dataset_id
    assert insert_params[9] == 10     # base_metric_id
    assert insert_params[10] == "SUM"
    assert insert_params[11] == "fact.amt"


def test_metric_filter_requires_field_resolution() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id
    cur.script([77])             # metric id
    cur.script([5])              # dataset_id for filter ds
    cur.script([88])             # field_id
    cur.script(None)             # existing (metric_id, filter_ord)
    status, msg, eid = import_entity(
        cur, DB, "m", "METRIC_FILTER",
        {"metric": "x_total", "field": "fact.cat", "op": "=",
         "filter_value": "'A'", "filter_ord": 1},
    )
    assert status == "OK" and eid == 77
    ins = next(p for sql, p in cur.calls if "INSERT INTO demo_user.METRIC_FILTER" in sql)
    # (metric_id, filter_ord, field_id, op, filter_value)
    assert ins == (77, 1, 88, "=", "'A'")


def test_relationship_with_role_name() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id
    cur.script([5])              # from dataset id
    cur.script([6])              # to dataset id
    cur.script(None)             # existing relationship
    cur.script([21])             # post-insert id
    status, _, eid = import_entity(
        cur, DB, "m", "RELATIONSHIP",
        {"from": "fact", "to": "date_dim",
         "cardinality": "MANY_TO_ONE", "role_name": "sold_date"},
    )
    assert status == "OK" and eid == 21
    ins_p = next(p for sql, p in cur.calls if "INSERT INTO demo_user.RELATIONSHIP" in sql)
    # role_name is the 6th column in our INSERT (0-indexed pos 5)
    # (relationship_name, from_dataset_id, to_dataset_id, cardinality,
    #  join_type_hint, role_name, description)
    assert ins_p[5] == "sold_date"
    assert ins_p[0] == "fact_to_date_dim"  # default name


def test_rel_col_resolves_both_sides() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id
    cur.script([21])             # relationship id
    cur.script([5])              # from dataset id
    cur.script([6])              # to dataset id
    cur.script([100])            # from field id
    cur.script([200])            # to field id
    status, _, eid = import_entity(
        cur, DB, "m", "REL_COL",
        {"relationship": "fact_to_date_dim",
         "from_dataset": "fact", "to_dataset": "date_dim",
         "from_field": "ss_sold_date_sk", "to_field": "d_date_sk",
         "position": 1},
    )
    assert status == "OK" and eid == 21
    # DELETE then INSERT
    assert any("DELETE FROM demo_user.REL_COLUMN_MAP" in sql for sql, _ in cur.calls)
    assert any("INSERT INTO demo_user.REL_COLUMN_MAP" in sql for sql, _ in cur.calls)


def test_ai_context_model_level() -> None:
    cur = FakeCursor()
    cur.script([1])              # model_id (initial)
    cur.script([1])              # model_id inside ai_context for entity resolution
    status, _, eid = import_entity(
        cur, DB, "m", "AI_CONTEXT",
        {"entity_type": "MODEL", "entity_name": "m",
         "instructions": "hello", "synonyms": ["a", "b"]},
    )
    assert status == "OK" and eid == 1
    # JSON serialisation of synonyms
    ins_p = next(p for sql, p in cur.calls if "INSERT INTO demo_user.AI_CONTEXT" in sql)
    # (entity_type, entity_id, instructions, synonyms, examples, display_name)
    import json as _json
    assert ins_p[0] == "MODEL"
    assert ins_p[1] == 1
    assert _json.loads(ins_p[3]) == ["a", "b"]


def test_unknown_kind_rejected() -> None:
    cur = FakeCursor()
    status, msg, _ = import_entity(cur, DB, "m", "UNKNOWN", {})
    assert status == "ERROR" and "unsupported" in msg.lower()


def test_unknown_model_rejected_for_dependent_kinds() -> None:
    cur = FakeCursor()
    cur.script(None)              # model lookup → None
    status, msg, _ = import_entity(cur, DB, "ghost", "DATASET", {"name": "x"})
    assert status == "ERROR" and "unknown model" in msg.lower()


# --------- synthesize_filtered_expressions --------------------------

def test_synthesize_writes_both_dialects_for_filtered_simple_metric() -> None:
    cur = FakeCursor()
    # _resolve_model_id
    cur.script([42])
    # SELECT filtered metrics: one row → metric `nii` with base `amount_sum`
    cur.script([(
        100,        # m.metric_id
        "nii",
        "SIMPLE",
        7,          # primary_dataset_id
        9,          # base_metric_id
        "amount_sum",
        "SUM",
        "events.VO_AMOUNT_EUR",
    )])
    # SELECT filter rows for metric_id=100
    cur.script([
        (1, 50, 3, "value_type", "CO_VALUE_TYPE_P360_LVL1", "=", "'1NII'"),
        (2, 51, 7, "events",     "FL_SEGMENT",              "=", "'Y'"),
    ])
    # Existence check for TERADATA dialect → None (insert path)
    cur.script(None)
    # Existence check for ANSI_SQL dialect → None (insert path)
    cur.script(None)

    n = synthesize_filtered_expressions(cur, DB, "p360")
    assert n == 1

    # Pull both INSERTs and inspect the SQL strings
    inserts = [
        (sql, p) for sql, p in cur.calls
        if sql.startswith(f"INSERT INTO {DB}.METRIC_EXPRESSION")
    ]
    assert len(inserts) == 2
    dialects = {p[1] for _, p in inserts}
    assert dialects == {"TERADATA", "ANSI_SQL"}
    expr = inserts[0][1][2]
    assert expr.startswith("SUM(CASE WHEN ")
    assert "value_type.CO_VALUE_TYPE_P360_LVL1 = '1NII'" in expr
    assert "events.FL_SEGMENT = 'Y'" in expr
    assert "events.VO_AMOUNT_EUR" in expr


def test_synthesize_skips_unknown_model() -> None:
    cur = FakeCursor()
    cur.script(None)              # _resolve_model_id → None
    n = synthesize_filtered_expressions(cur, DB, "ghost")
    assert n == 0


def test_synthesize_updates_existing_dialect_rows() -> None:
    cur = FakeCursor()
    cur.script([1])               # _resolve_model_id
    cur.script([(50, "fees", "SIMPLE", 2, 3, "amount_sum", "SUM", "events.amt")])
    cur.script([(1, 11, 2, "value_type", "lvl1", "=", "'1NFC'")])
    # Existence checks return a row → UPDATE path for both dialects
    cur.script([1])
    cur.script([1])

    n = synthesize_filtered_expressions(cur, DB, "m")
    assert n == 1
    updates = [
        (sql, p) for sql, p in cur.calls
        if sql.startswith(f"UPDATE {DB}.METRIC_EXPRESSION")
    ]
    assert len(updates) == 2
    assert {p[2] for _, p in updates} == {"TERADATA", "ANSI_SQL"}


def test_synthesize_skips_metric_with_no_filters() -> None:
    cur = FakeCursor()
    cur.script([1])               # model_id
    # One filtered metric returned, but its filter set is empty (orphan
    # base reference). The runtime compiler would reject; the synth must
    # not block import.
    cur.script([(20, "broken", "SIMPLE", 2, 3, "amount_sum", "SUM", "events.amt")])
    cur.script([])                # no METRIC_FILTER rows

    n = synthesize_filtered_expressions(cur, DB, "m")
    assert n == 0
    assert not any("METRIC_EXPRESSION" in sql for sql, _ in cur.calls)
