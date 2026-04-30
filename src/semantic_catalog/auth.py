"""Shared bearer-token authentication for every protected route.

The semantic catalog has one auth mechanism: ``SEMANTIC_API_TOKEN`` in
the environment (or the legacy alias ``SEMANTIC_MCP_TOKEN``). When the
token is set, every ``/api/*`` and ``/mcp/*`` request must carry
``Authorization: Bearer <token>``. When unset, no auth is applied — the
dev-localhost default.

We compare in constant time (``hmac.compare_digest``) to avoid a timing
side-channel on short tokens.
"""
from __future__ import annotations

import hmac
import os
from typing import Optional

from fastapi import Header, HTTPException


def _expected_token() -> Optional[str]:
    # Prefer the new name; fall back to the original so existing deployments
    # don't break.
    return os.environ.get("SEMANTIC_API_TOKEN") or os.environ.get("SEMANTIC_MCP_TOKEN")


def check_token(authorization: Optional[str]) -> Optional[tuple[int, str]]:
    """Pure-Python bearer-token check.

    Returns ``None`` on success (or when no token env var is set). On
    failure, returns ``(status_code, error_message)`` so the caller can
    surface it through whichever framework — FastAPI, ASGI middleware,
    a CLI tool — without coupling to ``fastapi.HTTPException``.
    """
    expected = _expected_token()
    if not expected:
        return None
    if not authorization or not authorization.lower().startswith("bearer "):
        return (401, "missing bearer token")
    token = authorization.split(None, 1)[1].strip()
    if not hmac.compare_digest(token, expected):
        return (403, "invalid bearer token")
    return None


def require_token(authorization: Optional[str] = Header(None)) -> None:
    """FastAPI dependency. Raises 401/403 on auth failure.

    No-ops when no token env var is set (local dev). When set, requires
    ``Authorization: Bearer <token>`` with a constant-time match.
    """
    err = check_token(authorization)
    if err is not None:
        raise HTTPException(err[0], err[1])
