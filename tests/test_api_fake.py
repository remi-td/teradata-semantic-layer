"""Endpoint smoke tests using the in-memory fake pool.

These tests don't validate DB behaviour — they validate that the FastAPI
routers wire up correctly, decode Teradata rows as expected, and respond
with the right JSON shapes for the GUI.
"""
from __future__ import annotations

import pytest


# NB: needles are matched case-insensitively as substrings of the SQL
# string the route executes. See ``tests/conftest.py``.
COMMON_RECIPES = [
    # list_models
    (
        "from demo_user.semantic_model",
        ["model_id", "model_name", "description", "ds_count", "mt_count",
         "model_family", "model_version", "is_latest"],
        [(1, "tpch_orders", "Orders model", 8, 4, None, 1, 1)],
    ),
    # /api/ping
    ("select 1", ["one"], [(1,)]),
    # describe macro
    (
        "exec demo_user.m_semantic_describe",
        ["attr_ordinal", "attr_key", "attr_value"],
        [
            (1, "entity_type", "METRIC"),
            (2, "name", "revenue"),
            (3, "description", "Line-level sales"),
            (10, "expr_teradata", "SUM(l_extendedprice * (1 - l_discount))"),
            (20, "ai_instructions", "Always additive across time."),
        ],
    ),
    # search macro
    (
        "exec demo_user.m_semantic_search",
        ["entity_type", "entity_name", "parent_name", "description", "synonyms", "relevance"],
        [
            ("METRIC",  "revenue",   "tpch_orders", "Line-level sales", "[\"sales\"]", 78),
            ("DATASET", "lineitem",  "tpch_orders", "Fact table", "",                  60),
        ],
    ),
]


@pytest.fixture
def fake_recipes():
    return COMMON_RECIPES


def test_health(client_fake):
    r = client_fake.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "version" in body


def test_ping_hits_pool(client_fake):
    r = client_fake.get("/api/ping")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_list_models(client_fake):
    r = client_fake.get("/api/models")
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list)
    assert body[0]["model_name"] == "tpch_orders"
    assert body[0]["dataset_count"] == 8


def test_search(client_fake):
    r = client_fake.get("/api/search", params={"q": "revenue"})
    assert r.status_code == 200
    body = r.json()
    assert any(h["entity_type"] == "METRIC" and h["entity_name"] == "revenue" for h in body)


def test_search_kind_filter_applies_after_db(client_fake):
    r = client_fake.get("/api/search", params={"q": "lineitem"})
    assert r.status_code == 200
    # Recipe returns both METRIC and DATASET — the GUI filters via ?kind.
    # The server itself returns both and lets the frontend filter.
    assert len(r.json()) == 2


def test_describe_returns_structured_attrs(client_fake):
    r = client_fake.get("/api/describe", params={
        "entity_type": "METRIC", "entity_name": "revenue",
    })
    assert r.status_code == 200
    body = r.json()
    assert body["entity_type"] == "METRIC"
    keys = [a["attr_key"] for a in body["attributes"]]
    assert "expr_teradata" in keys
    assert "ai_instructions" in keys


def test_describe_404_when_empty(client_fake, monkeypatch):
    # Force the describe recipe to return nothing by swapping in an empty pool.
    from conftest import FakePool
    from semantic_catalog import db
    monkeypatch.setattr(db, "_pool_singleton", FakePool([]))
    r = client_fake.get("/api/describe", params={
        "entity_type": "METRIC", "entity_name": "nope",
    })
    assert r.status_code == 404


def test_graph_structure(client_fake, monkeypatch):
    """Build a graph from recipes that cover DATASET / METRIC / RELATIONSHIP."""
    from conftest import FakePool
    from semantic_catalog import db

    recipes = [
        ("from demo_user.semantic_model where model_name",
         ["model_id"], [(1,)]),
        ("from demo_user.dataset d",
         ["dataset_id","dataset_name","description","DataBaseName","TableName",
          "has_src","field_count","display_name"],
         [(1,"lineitem","Fact","tpch","lineitem",0,10,"Line items"),
          (2,"customer","Dim","tpch","customer",0,8,None),
          (3,"sales_cube","Pre-canned","","",1,5,None)]),
        ("from demo_user.metric mt",
         ["metric_id","metric_name","description","metric_type",
          "primary_dataset_id","is_certified"],
         [(10,"revenue","Sales","SIMPLE",1,1)]),
        ("from demo_user.relationship r",
         ["rid","rname","from_id","to_id","card","jth","role"],
         [(100,"li_to_cust",1,2,"MANY_TO_ONE","INNER",None)]),
    ]
    monkeypatch.setattr(db, "_pool_singleton", FakePool(recipes))

    r = client_fake.get("/api/models/tpch_orders/graph")
    assert r.status_code == 200
    g = r.json()
    kinds = [n["kind"] for n in g["nodes"]]
    assert kinds.count("DATASET") == 3
    assert kinds.count("METRIC") == 1
    assert kinds.count("VIEW") == 0
    sub_kinds = {n["label"]: n["sub_kind"] for n in g["nodes"] if n["kind"] == "DATASET"}
    assert sub_kinds["sales_cube"] == "CUBE"
    assert sub_kinds["lineitem"] == "TABLE"

    # edges: metric_of + relationship
    e_kinds = [e["kind"] for e in g["edges"]]
    assert "METRIC_OF" in e_kinds
    assert "RELATIONSHIP" in e_kinds
    assert "VIEW_OF" not in e_kinds


def test_tree_endpoint(client_fake, monkeypatch):
    from conftest import FakePool
    from semantic_catalog import db

    recipes = [
        ("from demo_user.semantic_model where model_name",
         ["model_id","model_name","description"], [(1,"tpch_orders","Orders")]),
        ("from demo_user.dataset d",
         ["dataset_id","dataset_name","sub","desc"],
         [(1,"lineitem","TABLE","Fact")]),
        ("from demo_user.field f",
         ["dataset_id","field_name","type","is_dim","is_t","dt"],
         [(1,"l_orderkey","K",0,0,"INTEGER"),
          (1,"l_extendedprice","A",0,0,"DECIMAL(12,2)")]),
        ("from demo_user.metric mt",
         ["n","t","d","ds","cert"],
         [("revenue","SIMPLE","Sales","lineitem",1)]),
        ("from demo_user.relationship r",
         ["n","f","t","c","j"], []),
    ]
    monkeypatch.setattr(db, "_pool_singleton", FakePool(recipes))

    r = client_fake.get("/api/models/tpch_orders/tree")
    assert r.status_code == 200
    body = r.json()
    assert body["model"]["name"] == "tpch_orders"
    assert body["datasets"][0]["name"] == "lineitem"
    assert {f["name"] for f in body["datasets"][0]["fields"]} == {"l_orderkey", "l_extendedprice"}
    assert body["metrics"][0]["name"] == "revenue"
    assert "views" not in body


def test_describe_dataset_includes_relationships(client_fake, monkeypatch):
    """REST /api/describe must surface relationships[] for DATASET entities
    so the GUI can render edge hints alongside the attribute list.
    """
    from conftest import FakePool
    from semantic_catalog import db

    recipes = [
        # m_semantic_describe → flat attribute pack
        (
            "exec demo_user.m_semantic_describe",
            ["attr_ordinal", "attr_key", "attr_value"],
            [(1, "name", "part"), (2, "type", "DIM")],
        ),
        # _load_dataset_relationships joins RELATIONSHIP twice to DATASET
        (
            "from demo_user.dataset d",
            ["relationship_id", "relationship_name", "role_name",
             "cardinality", "direction", "other_dataset"],
            [
                (101, "lineitem_to_part", None, "MANY_TO_ONE",
                 "incoming", "lineitem"),
                (102, "partsupp_to_part", None, "MANY_TO_ONE",
                 "incoming", "partsupp"),
            ],
        ),
    ]
    monkeypatch.setattr(db, "_pool_singleton", FakePool(recipes))
    r = client_fake.get("/api/describe", params={
        "entity_type": "DATASET", "entity_name": "part",
    })
    assert r.status_code == 200, r.text
    body = r.json()
    rels = body["relationships"]
    assert rels is not None and len(rels) == 2
    prefixes = {h["prefix"] for h in rels}
    assert prefixes == {"lineitem_to_part", "partsupp_to_part"}
    assert all(h["direction"] == "incoming" for h in rels)
    assert all(h["cardinality"] == "MANY_TO_ONE" for h in rels)


def test_describe_metric_has_no_relationships(client_fake):
    """METRIC describes don't trigger the relationship enrichment."""
    r = client_fake.get("/api/describe", params={
        "entity_type": "METRIC", "entity_name": "revenue",
    })
    assert r.status_code == 200
    assert r.json()["relationships"] is None


def test_compile_unknown_model_validation_message(client_fake, monkeypatch):
    """REST /api/query/compile surfaces UNKNOWN_MODEL via validation_message
    when the model isn't in the catalog. The wire format keeps the
    structured details server-side, but the agent-readable error code +
    message must reach the caller.
    """
    from conftest import FakePool
    from semantic_catalog import db

    recipes = [
        # services.run_query: catalog.resolve_model_id returns nothing
        ("from demo_user.semantic_model where model_name",
         ["model_id"], []),
        # resolver: list_model_names enumeration for suggestions
        ("from demo_user.semantic_model",
         ["model_name"], [("tpch_orders",), ("tpcds_retail",)]),
    ]
    monkeypatch.setattr(db, "_pool_singleton", FakePool(recipes))

    r = client_fake.post("/api/query/compile", json={
        "model": "tpch_order",  # near-miss spelling
        "metrics": ["revenue"],
        "dimensions": [],
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["is_valid"] == 0
    assert body["compiled_sql"] is None
    assert "UNKNOWN_MODEL" in (body["validation_message"] or "")


def test_compile_returns_graceful_error_when_catalog_raises(client_fake, monkeypatch):
    """Regression: an unexpected exception in the DB catalog layer must
    not become a bare HTTP 500. The compile endpoint should return 200
    with ``is_valid=0`` and a structured ``validation_message`` so the
    GUI / agent can surface the failure reason instead of a naked
    'Internal Server Error'.
    """
    from conftest import FakeCursor, FakePool
    from semantic_catalog import db

    class ExplodingCursor(FakeCursor):
        def execute(self, sql: str, params=None):
            # Let the RLS/model-id lookups succeed, then detonate on the
            # first METRIC read so we're inside ``py_compile`` when the
            # exception fires — the exact codepath the 500 came from.
            s = (sql or "").lower()
            if "from demo_user.metric" in s:
                raise RuntimeError("simulated driver blow-up")
            if "from demo_user.semantic_model" in s:
                self._result = [(1,)]
                self._columns = ["model_id"]
                self.description = [("model_id",)]
                return
            return super().execute(sql, params)

    class ExplodingPool(FakePool):
        def cursor(self):
            return FakePool._CtxCursor(ExplodingCursor([]))

    monkeypatch.setattr(db, "_pool_singleton", ExplodingPool([]))

    r = client_fake.post("/api/query/compile", json={
        "model": "tpch_orders",
        "metrics": ["revenue"],
        "dimensions": [],
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["is_valid"] == 0
    assert body["compiled_sql"] is None
    msg = body["validation_message"] or ""
    # Surface the exception class + message so the caller can act on it.
    assert "INTERNAL" in msg or "RuntimeError" in msg
    assert "simulated driver blow-up" in msg
