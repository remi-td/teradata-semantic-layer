"""Embedded MCP-compatible HTTP layer.

Exposes the semantic-catalog tools as HTTP+JSON endpoints co-located
with the FastAPI server so MCP clients can speak to the same process
they already authenticate against. The surface area is intentionally
small — five tools map 1:1 to public compiler/exporter/describe
functions.
"""
from __future__ import annotations

from .server import router, TOOL_SCHEMAS

__all__ = ["router", "TOOL_SCHEMAS"]
