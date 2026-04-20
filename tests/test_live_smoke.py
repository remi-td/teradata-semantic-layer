"""Live smoke tests against a running Teradata instance.

Skipped automatically when ``DATABASE_URI`` is unset or the host is
unreachable. Set ``DATABASE_URI=teradata://user:pw@host/db`` to run them.

These tests also deploy the bundled ``60_sp_semantic_import.sql`` so the
import tests have something to call.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest


pytestmark = pytest.mark.live


@pytest.fixture(scope="module")
def deployed_import_sp(live_available):
    """Deploy sp_semantic_import if it is not already present.

    The procedure body must be submitted as a single statement; we rely on
    the semicolon terminator being left in place (the Teradata driver is
    tolerant there). If the SP is already deployed, this is a no-op.
    """
    if not live_available:
        pytest.skip("live DB not available")
    import teradatasql
    from semantic_catalog.config import load_settings
    settings = load_settings()
    conn = teradatasql.connect(**settings.driver_kwargs())
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) FROM DBC.TablesV "
            "WHERE DatabaseName=? AND TableName=? AND TableKind='P'",
            (settings.catalog_db, "sp_semantic_import"),
        )
        present = cur.fetchone()[0] > 0
        if not present:
            sql_path = (Path(__file__).resolve().parent.parent
                        / "src/semantic_catalog/sql_bundle/60_sp_semantic_import.sql")
            text = sql_path.read_text()
            # Strip leading pure-comment/blank lines so the driver sees only the
            # CREATE/REPLACE statement.
            lines = text.splitlines()
            while lines and (not lines[0].strip() or lines[0].lstrip().startswith("--")):
                lines.pop(0)
            body = "\n".join(lines).rstrip()
            cur.execute(body)
        cur.close()
    finally:
        conn.close()
    yield


def test_live_health(live_client):
    r = live_client.get("/api/ping")
    assert r.status_code == 200


def test_live_models(live_client):
    r = live_client.get("/api/models")
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list)
    # Seeded scenarios include tpch_orders and exec_dashboard; at least one model should exist.
    assert len(body) >= 1


def test_live_search(live_client):
    r = live_client.get("/api/search", params={"q": "revenue"})
    assert r.status_code == 200
    # At least one hit across our sample scenarios.
    assert len(r.json()) >= 1


def test_live_graph_shape(live_client):
    r = live_client.get("/api/models")
    assert r.status_code == 200
    if not r.json():
        pytest.skip("no models seeded")
    name = r.json()[0]["model_name"]
    g = live_client.get(f"/api/models/{name}/graph").json()
    assert "nodes" in g and "edges" in g


def test_live_compile_roundtrip(live_client):
    """Happy-path compile of a trivial request (no execute)."""
    r = live_client.get("/api/models")
    models = r.json()
    if not any(m["model_name"] == "tpch_orders" for m in models):
        pytest.skip("tpch_orders not deployed")
    # Grab any metric + dimension from the model.
    tree = live_client.get("/api/models/tpch_orders/tree").json()
    metric = tree["metrics"][0]["name"] if tree.get("metrics") else None
    dim = None
    for ds in tree.get("datasets", []):
        for f in ds.get("fields", []):
            if f.get("is_dimension"):
                dim = f"{ds['name']}.{f['name']}"
                break
        if dim: break
    if not (metric and dim):
        pytest.skip("could not pick metric+dimension from tpch_orders")
    body = {
        "model": "tpch_orders",
        "metrics": [metric],
        "dimensions": [dim],
        "limit": 5,
    }
    r = live_client.post("/api/query/compile", json=body)
    assert r.status_code == 200
    out = r.json()
    assert out["compiled_sql"], "no SQL produced"


def test_live_import_metric_and_rollback(live_client, deployed_import_sp):
    """Dry-run import: a brand new metric should validate and then roll back."""
    r = live_client.get("/api/models")
    models = [m["model_name"] for m in r.json()]
    if "tpch_orders" not in models:
        pytest.skip("tpch_orders not deployed")
    text = """\
metrics:
  - name: __gui_test_metric_dry_run__
    description: ephemeral, never committed
    primary_dataset: lineitem
    metric_type: SIMPLE
    is_additive: 1
    expressions:
      TERADATA: "COUNT(*)"
      ANSI_SQL: "COUNT(*)"
"""
    r = live_client.post("/api/import", json={
        "model": "tpch_orders", "text": text, "dry_run": True,
    })
    body = r.json()
    assert body["total"] == 3        # METRIC + 2 expressions
    # A fresh run should validate cleanly:
    assert body["error_count"] == 0, body
    assert body["applied"] is False
