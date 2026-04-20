"""Shared pytest fixtures.

The fixture set lets each test choose its connectivity level:

* ``fake_pool`` / ``client_fake``  — FastAPI TestClient with the DB pool
  replaced by an in-memory fake. No Teradata required. These tests run in
  CI and on a developer laptop without a cluster.

* ``live_pool`` / ``live_client`` — real Teradata connection via the same
  environment contract as the GUI server. Skipped when unreachable.
"""
from __future__ import annotations

import os
from typing import Any, Dict, Iterable, List, Tuple
from urllib.error import URLError

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------- fake pool

class FakeCursor:
    """In-memory cursor that replays scripted (sql-substring → rows) recipes."""

    def __init__(self, recipes: List[Tuple[str, List[Any], List[Tuple]]]):
        self._recipes = recipes
        self._result: List[Tuple] = []
        self._columns: List[str] = []
        self.description: List[Tuple] = []

    def execute(self, sql: str, params=None):
        s = " ".join((sql or "").split()).lower()
        for needle, columns, rows in self._recipes:
            if needle.lower() in s:
                self._result = list(rows)
                self._columns = list(columns)
                self.description = [(c,) for c in columns]
                return
        self._result = []
        self._columns = []
        self.description = []

    def fetchall(self):
        out, self._result = self._result, []
        return out

    def fetchone(self):
        if not self._result:
            return None
        r = self._result.pop(0)
        return r

    def close(self): pass


class FakePool:
    def __init__(self, recipes: List[Tuple[str, List[Any], List[Tuple]]]):
        self._recipes = recipes

    class _CtxCursor:
        def __init__(self, cur): self.cur = cur
        def __enter__(self): return self.cur
        def __exit__(self, *a): self.cur.close()

    class _CtxConn:
        def __init__(self, cur):
            self.cur = cur
            self.autocommit = True
        def cursor(self): return self.cur
        def commit(self): pass
        def rollback(self): pass
        def close(self): pass
        def __enter__(self): return self
        def __exit__(self, *a): pass

    def cursor(self):
        return FakePool._CtxCursor(FakeCursor(self._recipes))

    def connection(self):
        return FakePool._CtxConn(FakeCursor(self._recipes))

    def close_all(self): pass


@pytest.fixture
def fake_recipes() -> List[Tuple[str, List[str], List[Tuple]]]:
    """Default recipe list; tests may override by parametrisation."""
    return []


@pytest.fixture
def fake_pool(monkeypatch, fake_recipes):
    """Install a FakePool as the module-level singleton.

    Both ``semantic_catalog.db._pool_singleton`` and ``get_pool`` are
    overridden so tests can also call ``monkeypatch.setattr(db,
    "_pool_singleton", ...)`` to swap in a different fake at runtime.
    """
    from semantic_catalog import db
    pool = FakePool(fake_recipes)
    monkeypatch.setattr(db, "_pool_singleton", pool)
    # get_pool reads the singleton each call — keep the original logic.
    yield pool


@pytest.fixture
def settings_env(monkeypatch):
    monkeypatch.setenv(
        "DATABASE_URI",
        "teradata://demo_user:demo_user@localhost:1025/demo_user",
    )
    # The fake pool doesn't actually connect, so no real socket is required.
    yield


@pytest.fixture
def client_fake(fake_pool, settings_env):
    from semantic_catalog.server import create_app
    app = create_app()
    return TestClient(app)


# ---------------------------------------------------------- live fixtures

def _live_available() -> bool:
    try:
        import teradatasql
    except Exception:
        return False
    uri = os.environ.get("DATABASE_URI") or ""
    host = os.environ.get("TERADATA_HOST")
    if not (uri or host):
        return False
    # Guard with a socket-level probe so we fail fast when the host is down,
    # without depending on teradatasql's connect_timeout (which has proven
    # unreliable across driver versions).
    import socket
    try:
        from semantic_catalog.config import load_settings
        settings = load_settings()
        s = socket.create_connection((settings.host, settings.port), timeout=5)
        s.close()
        conn = teradatasql.connect(**settings.driver_kwargs())
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
        cur.close()
        conn.close()
        return True
    except Exception:
        return False


@pytest.fixture(scope="session")
def live_available() -> bool:
    return _live_available()


@pytest.fixture
def live_client(live_available):
    if not live_available:
        pytest.skip("no reachable Teradata (DATABASE_URI unset or host unreachable)")
    from semantic_catalog.db import reset_pool
    reset_pool()
    from semantic_catalog.server import create_app
    app = create_app()
    return TestClient(app)
