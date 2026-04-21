"""Python query compiler for the semantic catalog.

Two-phase architecture (MetricFlow-style):

    request JSON
        │
        ▼  resolver.py + joins.py (later tasks)
    LogicalPlan              <-- dialect-neutral
        │
        ▼  render.py
    compiled SQL string      <-- Teradata (or other) dialect

The skeleton in this commit only covers:
    - Typed errors (errors.py)
    - Plan dataclasses (logical.py)
    - Catalog DAO protocol (catalog.py)
    - Trivial render: anchor FROM + dim columns + limit via sqlglot

Resolver, joins, filters, metrics, grain wrapping, and EXPLAIN
validation arrive in subsequent tasks.
"""
from __future__ import annotations

from .errors import (
    CompileError,
    UnknownModelError,
    UnknownEntityError,
    AmbiguousPathError,
    ChasmTrapError,
    CycleError,
    UnresolvedJoinError,
)
from .logical import (
    DatasetRef,
    FieldRef,
    MetricRef,
    ResolvedDim,
    ResolvedFilter,
    JoinStep,
    LogicalPlan,
    SortKey,
)
from .render import render

__all__ = [
    "CompileError",
    "UnknownModelError",
    "UnknownEntityError",
    "AmbiguousPathError",
    "ChasmTrapError",
    "CycleError",
    "UnresolvedJoinError",
    "DatasetRef",
    "FieldRef",
    "MetricRef",
    "ResolvedDim",
    "ResolvedFilter",
    "JoinStep",
    "LogicalPlan",
    "SortKey",
    "render",
]
