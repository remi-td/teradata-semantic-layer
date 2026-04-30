"""MCP server — Streamable HTTP JSON-RPC transport.

This is the real Model Context Protocol surface. We register the five
catalog tools with ``FastMCP`` and expose them as a Streamable-HTTP
ASGI app, mounted at ``/mcp`` on the main FastAPI application
(see :mod:`semantic_catalog.server`).

Clients that work today:
- Claude Code (``"url": "http://localhost:8080/mcp"``)
- Cursor / Continue (same shape)
- Claude Desktop via the ``mcp-remote`` stdio bridge:
  ``npx mcp-remote http://localhost:8080/mcp/ --header "Authorization: Bearer $TOKEN"``

Auth is enforced by an ASGI middleware in ``server.py`` that gates the
mount with the same ``SEMANTIC_API_TOKEN`` bearer-token contract as the
REST ``/api/*`` endpoints.

The tool implementations live in :mod:`.tools`; this module is purely
a transport adapter.
"""
from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

from . import tools as _tools

log = logging.getLogger(__name__)


def _transport_security() -> TransportSecuritySettings:
    """Build the FastMCP transport-security settings.

    Defaults to localhost-only (the FastMCP default), which protects
    browser-resident attackers from DNS-rebinding their way into a
    locally-bound MCP server. Operators behind a reverse proxy or
    listening on non-localhost can extend the allowlist via:

    - ``SEMANTIC_MCP_ALLOWED_HOSTS``   — comma-separated host:port patterns
    - ``SEMANTIC_MCP_ALLOWED_ORIGINS`` — comma-separated ``http(s)://`` URIs
    - ``SEMANTIC_MCP_DISABLE_HOST_CHECK=1`` — turn off the check entirely

    Tests use ``SEMANTIC_MCP_DISABLE_HOST_CHECK=1`` because Starlette's
    TestClient sends ``Host: testserver``.
    """
    if os.environ.get("SEMANTIC_MCP_DISABLE_HOST_CHECK") in {"1", "true", "TRUE"}:
        return TransportSecuritySettings(enable_dns_rebinding_protection=False)
    base_hosts = ["127.0.0.1:*", "localhost:*", "[::1]:*"]
    base_origins = ["http://127.0.0.1:*", "http://localhost:*", "http://[::1]:*"]
    extra_hosts = [h.strip() for h in os.environ.get("SEMANTIC_MCP_ALLOWED_HOSTS", "").split(",") if h.strip()]
    extra_origins = [o.strip() for o in os.environ.get("SEMANTIC_MCP_ALLOWED_ORIGINS", "").split(",") if o.strip()]
    return TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=base_hosts + extra_hosts,
        allowed_origins=base_origins + extra_origins,
    )


def build_mcp_server() -> FastMCP:
    """Construct a fresh FastMCP server with all five tools registered.

    A fresh instance is built per ``create_app()`` call so tests can
    spin up isolated servers without leftover state.

    ``streamable_http_path='/'`` makes the JSON-RPC endpoint the root of
    the returned Starlette app; we then mount that app at ``/mcp`` in
    FastAPI so the public endpoint is ``http://host:port/mcp``.
    """
    mcp = FastMCP(
        name="semantic-catalog",
        instructions=(
            "Teradata Semantic Catalog — search, describe, compile, "
            "execute, and export governed metric/dimension models."
        ),
        stateless_http=True,
        streamable_http_path="/",
        transport_security=_transport_security(),
    )

    @mcp.tool(
        name="semantic_search",
        description=(
            "Full-text search across the catalog: dataset / metric / "
            "view names, descriptions, AI synonyms. Returns ranked hits."
        ),
    )
    def semantic_search(
        term: str,
        model: Optional[str] = None,
        limit: int = 50,
    ) -> Dict[str, Any]:
        return _tools.semantic_search(term=term, model=model, limit=limit)

    @mcp.tool(
        name="semantic_describe",
        description=(
            "Full metadata for one entity: dataset / metric / view / "
            "field / model. Returns (attr_ordinal, attr_key, attr_value) "
            "triples covering description, AI context, format spec, and "
            "structural metadata."
        ),
    )
    def semantic_describe(
        entity_type: str,
        entity_name: str,
        model: Optional[str] = None,
    ) -> Dict[str, Any]:
        return _tools.semantic_describe(
            entity_type=entity_type, entity_name=entity_name, model=model
        )

    @mcp.tool(
        name="semantic_compile",
        description=(
            "Compile a structured query request to Teradata SQL. "
            "Returns the compiled SQL plus anchor/joined datasets and "
            "validity flags."
        ),
    )
    def semantic_compile(request: Dict[str, Any]) -> Dict[str, Any]:
        return _tools.semantic_compile(request=request)

    @mcp.tool(
        name="semantic_execute",
        description=(
            "Compile and execute a query request, returning up to 500 "
            "rows along with the SQL that was run."
        ),
    )
    def semantic_execute(request: Dict[str, Any]) -> Dict[str, Any]:
        return _tools.semantic_execute(request=request)

    @mcp.tool(
        name="semantic_export_osi",
        description="Export a semantic model as OSI 0.1.x YAML.",
    )
    def semantic_export_osi(model: str) -> Dict[str, Any]:
        return _tools.semantic_export_osi(model=model)

    return mcp


def mcp_app():
    """Return the ASGI app that handles MCP Streamable-HTTP traffic."""
    return build_mcp_server().streamable_http_app()


__all__ = ["build_mcp_server", "mcp_app"]
