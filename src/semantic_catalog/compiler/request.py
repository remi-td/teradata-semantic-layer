"""Compiler-owned request dataclasses.

The compiler must not depend on the HTTP layer. Prior to v0.4 the
resolver imported ``QueryRequest`` directly from ``semantic_catalog.api.models``
— that inverted the dependency direction (inner core → outer shell).
These dataclasses are the neutral shape. The API layer now converts
Pydantic ``QueryRequest`` / ``QueryFilter`` / ``QuerySort`` into them
before handing off to ``compile()``.

Keep these free of pydantic, fastapi, and any other transport concern.
"""
from __future__ import annotations

from dataclasses import dataclass, field as _dc_field
from typing import Any, List, Optional


@dataclass
class CompileFilter:
    """One WHERE or HAVING predicate in the compile request.

    ``field`` is set on WHERE filters, ``metric`` on HAVING filters.
    ``type`` hints the value encoder: STRING (default) / NUMBER / DATE /
    RAW. See resolver._encode_filter_rhs for the RAW allow-list.
    """
    field: Optional[str] = None
    metric: Optional[str] = None
    op: str = "="
    value: Any = None
    values: Optional[List[Any]] = None
    type: Optional[str] = None


@dataclass
class CompileSort:
    field: str
    direction: str = "ASC"


@dataclass
class CompileRequest:
    model: str
    metrics: List[str] = _dc_field(default_factory=list)
    dimensions: List[str] = _dc_field(default_factory=list)
    where: List[CompileFilter] = _dc_field(default_factory=list)
    having: List[CompileFilter] = _dc_field(default_factory=list)
    sort: List[CompileSort] = _dc_field(default_factory=list)
    limit: int = 0
    execute: bool = False


def from_mapping(payload: Any) -> CompileRequest:
    """Build a CompileRequest from a loosely-typed dict or pydantic model.

    Accepts:
      - a dict (e.g. JSON body at the MCP layer),
      - a pydantic ``QueryRequest`` (via ``.model_dump()``),
      - an already-built ``CompileRequest`` (returned as-is).

    Unknown keys are ignored. The function is intentionally lenient so
    MCP clients can pass the same JSON shape historically accepted by
    ``/api/query/*``.
    """
    if isinstance(payload, CompileRequest):
        return payload
    if hasattr(payload, "model_dump"):
        data = payload.model_dump()
    elif isinstance(payload, dict):
        data = payload
    else:
        raise TypeError(
            f"CompileRequest.from_mapping expected dict or pydantic model, "
            f"got {type(payload).__name__}"
        )

    def _filter(d: Any) -> CompileFilter:
        if isinstance(d, CompileFilter):
            return d
        if hasattr(d, "model_dump"):
            d = d.model_dump()
        return CompileFilter(
            field=d.get("field"),
            metric=d.get("metric"),
            op=d.get("op", "="),
            value=d.get("value"),
            values=d.get("values"),
            type=d.get("type"),
        )

    def _sort(d: Any) -> CompileSort:
        if isinstance(d, CompileSort):
            return d
        if hasattr(d, "model_dump"):
            d = d.model_dump()
        return CompileSort(
            field=d.get("field"),
            direction=d.get("direction", "ASC"),
        )

    return CompileRequest(
        model=data["model"],
        metrics=list(data.get("metrics") or []),
        dimensions=list(data.get("dimensions") or []),
        where=[_filter(x) for x in (data.get("where") or [])],
        having=[_filter(x) for x in (data.get("having") or [])],
        sort=[_sort(x) for x in (data.get("sort") or [])],
        limit=int(data.get("limit") or 0),
        execute=bool(data.get("execute") or False),
    )
