"""Top-level ``compile`` — resolver + join resolver + (later) metric-in-metric.

Public entry point for the API layer and MCP tools. Accepts a
CompileRequest and a CatalogDAO, returns a LogicalPlan ready for
``render``.
"""
from __future__ import annotations

from .catalog import CatalogDAO
from .joins import JoinResolver
from .logical import LogicalPlan
from .request import CompileRequest
from .resolver import Resolver


def compile(req: CompileRequest, catalog: CatalogDAO) -> LogicalPlan:
    """Compile a request into a LogicalPlan against the given catalog.

    Two phases:
        1. Resolver — model, metrics, dims, filters, required datasets.
        2. JoinResolver — BFS + bridging to connect requireds to anchor,
           emitting join_steps that the renderer consumes verbatim.

    Raises ``CompileError`` subclasses on catalog-level errors.
    """
    plan = Resolver(catalog).resolve(req)
    JoinResolver(catalog, plan.model_id).resolve(plan)
    return plan
