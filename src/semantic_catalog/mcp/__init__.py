"""Embedded MCP server.

Exposes the semantic-catalog tools to AI agents via the Model Context
Protocol's Streamable-HTTP transport, co-located with the FastAPI
server so MCP clients hit the same process they already authenticate
against. The five tools map 1:1 to public compiler / exporter /
describe operations and are also surfaced individually as ``/api/*``
REST endpoints.
"""
from __future__ import annotations

from .server import build_mcp_server, mcp_app

__all__ = ["build_mcp_server", "mcp_app"]
