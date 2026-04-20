"""Thread-safe connection pool over the teradatasql driver.

The driver itself is synchronous, so we expose a blocking context manager
and leave async concerns to the FastAPI thread pool (fine for a laptop
server workload).
"""
from __future__ import annotations

import logging
import threading
from contextlib import contextmanager
from queue import Empty, Queue
from typing import Callable, Iterator, Optional

import teradatasql

from .config import Settings

log = logging.getLogger(__name__)


class ConnectionPool:
    """Minimal bounded pool. Reuses connections across requests."""

    def __init__(self, settings: Settings, size: int = 4):
        self._settings = settings
        self._size = size
        self._available: "Queue[teradatasql.TeradataConnection]" = Queue(maxsize=size)
        self._created = 0
        self._lock = threading.Lock()

    def _new_connection(self):
        log.info("opening teradatasql connection to %s", self._settings.host)
        return teradatasql.connect(**self._settings.driver_kwargs())

    def _borrow(self, timeout: Optional[float] = 30.0):
        # Prefer an idle connection.
        try:
            return self._available.get(block=False)
        except Empty:
            pass
        with self._lock:
            if self._created < self._size:
                conn = self._new_connection()
                self._created += 1
                return conn
        # Saturated — wait for one to come back.
        return self._available.get(block=True, timeout=timeout)

    def _return(self, conn, *, healthy: bool):
        if not healthy:
            with self._lock:
                self._created = max(0, self._created - 1)
            try:
                conn.close()
            except Exception:
                pass
            return
        try:
            self._available.put(conn, block=False)
        except Exception:
            with self._lock:
                self._created = max(0, self._created - 1)
            try:
                conn.close()
            except Exception:
                pass

    @contextmanager
    def connection(self) -> Iterator["teradatasql.TeradataConnection"]:
        conn = self._borrow()
        healthy = True
        try:
            yield conn
        except Exception:
            healthy = False
            raise
        finally:
            self._return(conn, healthy=healthy)

    @contextmanager
    def cursor(self) -> Iterator["teradatasql.TeradataCursor"]:
        with self.connection() as conn:
            cur = conn.cursor()
            try:
                yield cur
            finally:
                try:
                    cur.close()
                except Exception:
                    pass

    def close_all(self):
        while True:
            try:
                c = self._available.get(block=False)
            except Empty:
                break
            try:
                c.close()
            except Exception:
                pass
        with self._lock:
            self._created = 0


_pool_singleton: Optional[ConnectionPool] = None
_pool_lock = threading.Lock()


def get_pool(settings: Optional[Settings] = None) -> ConnectionPool:
    """Lazy, process-wide pool singleton."""
    global _pool_singleton
    if _pool_singleton is not None:
        return _pool_singleton
    with _pool_lock:
        if _pool_singleton is None:
            from .config import load_settings
            _pool_singleton = ConnectionPool(settings or load_settings())
    return _pool_singleton


def reset_pool() -> None:
    """For tests — close and forget the pool."""
    global _pool_singleton
    with _pool_lock:
        if _pool_singleton is not None:
            _pool_singleton.close_all()
            _pool_singleton = None


def rows_as_dicts(cur) -> list[dict]:
    """Return the current result set as a list of plain dicts."""
    cols = [d[0] for d in (cur.description or [])]
    out = []
    for row in cur.fetchall() or []:
        out.append({cols[i]: row[i] for i in range(len(cols))})
    return out


def scalar(cur, sql: str, *params) -> Optional[object]:
    cur.execute(sql, params if params else None)
    r = cur.fetchone()
    return r[0] if r else None


def run_with_retry(fn: Callable, retries: int = 1):
    """Execute ``fn`` with a single reconnect on a transport-level failure."""
    last_err = None
    for attempt in range(retries + 1):
        try:
            return fn()
        except Exception as e:  # noqa: BLE001
            last_err = e
            if attempt == retries:
                raise
            log.warning("db call failed (attempt %s/%s): %s", attempt + 1, retries + 1, e)
    raise last_err  # unreachable
