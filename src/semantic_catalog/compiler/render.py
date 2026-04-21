"""Render a LogicalPlan into dialect SQL via sqlglot.

Skeleton in this commit: anchor FROM + dim columns + metric columns
(pre-composed strings) + TOP/LIMIT. Later tasks add WHERE, GROUP BY,
HAVING, ORDER BY, grain wrapping, and the Teradata-specific
``LOCKING ROW FOR ACCESS`` prefix.

The renderer itself is dialect-neutral: sqlglot handles ``TOP`` vs
``LIMIT`` and ``||`` vs ``CONCAT`` based on the ``dialect`` argument.
"""
from __future__ import annotations

from typing import List

import sqlglot
from sqlglot import exp

from .logical import LogicalPlan, ResolvedDim, MetricRef


# --------------------------------------------------------------- helpers

def _anchor_from(plan: LogicalPlan) -> str:
    """Pre-rendered FROM source for the anchor dataset.

    Three cases:
      - physical table:  ``db.table AS alias``
      - cube/derived:    ``(source_query) AS alias``
      - catalog-only:    ``dataset_name AS alias``  (no physical mapping)

    When ``plan.join_steps`` already carries a step_ordinal=0 entry we use
    its rendered ``join_sql`` verbatim so that resolver-driven plans stay
    authoritative; otherwise we synthesise one from the anchor DatasetRef.
    """
    for step in plan.join_steps:
        if step.step_ordinal == 0:
            sql = step.join_sql.strip()
            return sql[5:].lstrip() if sql.upper().startswith("FROM ") else sql

    a = plan.anchor
    if a.source_query and not a.database_name:
        return f"({a.source_query}) AS {a.alias}"
    if a.database_name and a.table_name:
        return f"{a.database_name.strip()}.{a.table_name.strip()} AS {a.alias}"
    return f"{a.dataset_name} AS {a.alias}"


def _dim_select_expr(d: ResolvedDim) -> str:
    """One entry of the SELECT list for a dimension.

    Grain wrapping and role-prefixed aliases are added here so the sqlglot
    parser sees fully-formed column expressions with aliases.
    """
    expr = d.field.expression
    qualified = expr if expr != d.field.field_name else f"{d.dataset_alias}.{d.field.field_name}"

    if d.grain:
        g = d.grain.upper()
        trunc_unit = {
            "DAY": "'DDD'",
            "WEEK": "'DAY'",
            "MONTH": "'MM'",
            "QUARTER": "'Q'",
            "YEAR": "'Y'",
        }.get(g)
        if trunc_unit:
            qualified = f"TRUNC({qualified}, {trunc_unit})"

    alias = d.column_alias or (
        f"{d.field.field_name}_{d.grain.lower()}" if d.grain else d.field.field_name
    )
    return f"{qualified} AS {alias}"


def _metric_select_expr(m: MetricRef) -> str:
    return f"{m.expression} AS {m.metric_name}"


# --------------------------------------------------------------- main

def render(plan: LogicalPlan, *, dialect: str = "teradata", pretty: bool = True) -> str:
    """Render the plan to SQL for the requested dialect.

    For now: dim columns, metric columns, anchor FROM, additional join
    steps (pre-rendered), TOP via plan.limit. Later tasks wire WHERE,
    GROUP BY, HAVING, ORDER BY.
    """
    dim_cols = [_dim_select_expr(d) for d in plan.dimensions]
    met_cols = [_metric_select_expr(m) for m in plan.metrics]
    select_cols = dim_cols + met_cols or ["1"]  # avoid empty SELECT

    q = sqlglot.select(*select_cols, dialect=dialect).from_(_anchor_from(plan), dialect=dialect)

    for step in plan.join_steps:
        if step.step_ordinal == 0:
            continue
        # Parse the pre-rendered "INNER JOIN ... ON ..." fragment and attach
        # it as a Join node. This gives us dialect-correct pretty-printing.
        join_node = sqlglot.parse_one(step.join_sql, dialect=dialect, into=exp.Join)
        q = q.join(join_node, dialect=dialect)

    if plan.limit and plan.limit > 0:
        q = q.limit(plan.limit, dialect=dialect)

    return q.sql(dialect=dialect, pretty=pretty)
