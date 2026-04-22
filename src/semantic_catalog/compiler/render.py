"""Render a LogicalPlan into dialect SQL via sqlglot.

Pipeline:

    LogicalPlan
      │
      ├── SELECT list: dims (with grain wrap, role-prefixed alias) + metrics
      ├── FROM: anchor + join_steps (each pre-rendered by JoinResolver)
      ├── WHERE:  ResolvedFilter(kind=WHERE) AND-joined
      ├── GROUP BY: dims when metrics are present
      ├── HAVING: ResolvedFilter(kind=HAVING) with metric name → expression
      ├── ORDER BY: plan.sort
      └── TOP N: plan.limit

Dialect handling is delegated to sqlglot (``dialect='teradata'`` turns
LIMIT into TOP, rewrites CONCAT ↔ ||, etc). The Teradata-only
``LOCKING ROW FOR ACCESS`` modifier is prepended as a raw string because
sqlglot has no first-class node for it, but the emitted output is still
re-parseable by sqlglot (confirmed in research).

Dim-only requests emit ``SELECT DISTINCT`` (matches sp_semantic_request F3).
"""
from __future__ import annotations

from typing import List

import sqlglot
from sqlglot import exp

from .logical import LogicalPlan, ResolvedDim, ResolvedFilter, MetricRef


# ---- helpers -----------------------------------------------------------

def _anchor_from(plan: LogicalPlan) -> str:
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


def _dim_expr(d: ResolvedDim) -> str:
    """Column-side expression for a dim — with grain wrap when present.

    This is used in *both* SELECT and GROUP BY so the two stay in sync.
    """
    expr = d.field.expression
    qualified = expr if expr != d.field.field_name else f"{d.dataset_alias}.{d.field.field_name}"
    if not d.grain:
        return qualified
    trunc_unit = {
        "DAY": "'DDD'",
        "WEEK": "'DAY'",
        "MONTH": "'MM'",
        "QUARTER": "'Q'",
        "YEAR": "'Y'",
    }.get(d.grain.upper())
    if not trunc_unit:
        return qualified
    return f"TRUNC({qualified}, {trunc_unit})"


def _dim_alias(d: ResolvedDim) -> str:
    if d.column_alias:
        return d.column_alias
    base = d.field.field_name
    return f"{base}_{d.grain.lower()}" if d.grain else base


def _dim_select(d: ResolvedDim) -> str:
    return f"{_dim_expr(d)} AS {_dim_alias(d)}"


def _metric_select(m: MetricRef) -> str:
    return f"{m.expression} AS {m.metric_name}"


def _filter_predicate(f: ResolvedFilter, plan: LogicalPlan) -> str:
    """Render one predicate. For HAVING, lhs is a metric name — substitute
    its composed expression so the SQL references the aggregate directly.

    ``WHERE_RAW`` filters carry the whole predicate verbatim in ``lhs``
    (RLS fragments from SECURITY_POLICY — already operator-trusted SQL).
    """
    if f.kind == "WHERE_RAW":
        return f.lhs
    if f.kind == "HAVING":
        metric = next((m for m in plan.metrics if m.metric_name == f.lhs), None)
        if metric is None:
            # Should have been caught by the resolver; guard anyway.
            return f"{f.lhs} {f.op} {f.rhs}"
        return f"({metric.expression}) {f.op} {f.rhs}"
    # WHERE: IN/LIKE handled the same — caller-supplied rhs is verbatim
    return f"{f.lhs} {f.op} {f.rhs}"


# ---- main -------------------------------------------------------------

def render(plan: LogicalPlan, *, dialect: str = "teradata",
           pretty: bool = True, locking: bool = True) -> str:
    """Render ``plan`` as a SQL string in the given dialect.

    When ``locking`` is True (Teradata default) prepends
    ``LOCKING ROW FOR ACCESS`` so read queries don't block writers.
    """
    dim_selects = [_dim_select(d) for d in plan.dimensions]
    met_selects = [_metric_select(m) for m in plan.metrics]
    select_cols = dim_selects + met_selects or ["1"]

    q = sqlglot.select(*select_cols, dialect=dialect).from_(_anchor_from(plan), dialect=dialect)

    # Dim-only → DISTINCT
    if plan.dimensions and not plan.metrics:
        q = q.distinct()

    for step in plan.join_steps:
        if step.step_ordinal == 0:
            continue
        join_node = sqlglot.parse_one(step.join_sql, dialect=dialect, into=exp.Join)
        q = q.join(join_node, dialect=dialect)

    where_preds = [_filter_predicate(f, plan) for f in plan.filters
                   if f.kind in ("WHERE", "WHERE_RAW")]
    for pred in where_preds:
        q = q.where(pred, dialect=dialect)

    if plan.metrics and plan.dimensions:
        group_exprs = [_dim_expr(d) for d in plan.dimensions]
        q = q.group_by(*group_exprs, dialect=dialect)

    having_preds = [_filter_predicate(f, plan) for f in plan.filters if f.kind == "HAVING"]
    for pred in having_preds:
        q = q.having(pred, dialect=dialect)

    if plan.sort:
        order_exprs = [f"{s.field} {s.direction.upper()}" for s in plan.sort]
        q = q.order_by(*order_exprs, dialect=dialect)

    if plan.limit and plan.limit > 0:
        q = q.limit(plan.limit, dialect=dialect)

    sql = q.sql(dialect=dialect, pretty=pretty)
    if locking and dialect == "teradata":
        sql = "LOCKING ROW FOR ACCESS\n" + sql
    return sql
