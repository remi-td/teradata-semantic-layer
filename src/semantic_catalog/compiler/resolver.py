"""Resolver v1 — tokens + catalog → (partial) LogicalPlan.

Responsibilities in this version:

  * Model resolution
  * Metric resolution including filtered-metric composition
    (base_metric_id + METRIC_FILTER rows)
  * Dimension parsing: ``prefix.field[:GRAIN]`` with role-playing
  * Filter parsing: WHERE + HAVING, with role-playing
  * Required-dataset inventory with role alias tracking
  * Grain counting + chasm warning flag
  * Single-grain anchor selection (most-connected dataset otherwise)

Out of scope for this version:
  * Join-path BFS (task #23)
  * Metric-in-metric references (task #24)

The resolver runs entirely in Python against a CatalogDAO. It does not
emit SQL; rendering is in render.py.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Set, Tuple

from ..api.models import QueryFilter, QueryRequest, QuerySort
from .catalog import CatalogDAO, MetricFilterRow, MetricRow
from .encoding import encode_in, encode_value
from .errors import (
    AmbiguousPathError,
    CompileError,
    CycleError,
    UnknownEntityError,
    UnknownModelError,
)
from .logical import (
    DatasetRef,
    FieldRef,
    JoinStep,
    LogicalPlan,
    MetricRef,
    ResolvedDim,
    ResolvedFilter,
    SortKey,
)


_GRAIN_UNITS = {"DAY", "WEEK", "MONTH", "QUARTER", "YEAR"}

# Phase 2 — metric-in-metric references. Chosen syntax: ${name}.
# Unambiguous (no column collisions), trivial to parse pre-sqlglot.
_METRIC_REF_RE = re.compile(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
_MAX_METRIC_REF_DEPTH = 8


# --------------------------------------------------------- token parsing

def _split_grain(token: str) -> Tuple[str, Optional[str]]:
    """Split ``'prefix.field:GRAIN'`` into ``('prefix.field', 'GRAIN')``."""
    if ":" in token:
        lhs, grain = token.split(":", 1)
        return lhs.strip(), grain.strip().upper()
    return token.strip(), None


def _split_prefix(token: str) -> Tuple[Optional[str], str]:
    """Split ``'prefix.field'`` into ``('prefix', 'field')``.

    Returns ``(None, token)`` when there is no dot (an unqualified token).
    Splits on the *first* dot only: ``foo.bar.baz`` becomes
    ``('foo', 'bar.baz')`` — the resolver will treat that as an error
    downstream since such field names are not supported.
    """
    if "." in token:
        pfx, fld = token.split(".", 1)
        return pfx.strip() or None, fld.strip()
    return None, token.strip()


# ---------------------------------------------------------- value encode

def _encode_filter_rhs(f: QueryFilter) -> str:
    op = f.op.upper()
    if op == "IN":
        if not f.values:
            raise CompileError(f"IN filter missing 'values' (lhs={f.field or f.metric})")
        return encode_in(f.values)
    return encode_value(f.value, f.type)


# -------------------------------------------------------- filtered metric

_SUM_ELSE_ZERO = {"SUM"}  # SUM treats NULL as 0 anyway, but ELSE 0 is clearer


def _compose_filtered_expression(base: MetricRow,
                                 filters: List[MetricFilterRow]) -> str:
    """Build the ``AGG(CASE WHEN ... THEN <arg> ELSE <default> END)`` SQL
    for a filtered rollup. Mirrors sp_semantic_request::F-phase-1.
    """
    if base.aggregate_fn is None or base.aggregate_arg is None:
        raise CompileError(
            f"Filtered metric base '{base.metric_name}' is missing "
            f"aggregate_fn / aggregate_arg."
        )
    if not filters:
        raise CompileError(
            f"Filtered metric based on '{base.metric_name}' has no METRIC_FILTER rows."
        )
    predicates = [
        f"{row.dataset_name}.{row.field_name} {row.op} {row.filter_value}"
        for row in filters
    ]
    predicate_sql = " AND ".join(predicates)
    agg = base.aggregate_fn.upper()
    arg = base.aggregate_arg
    if agg == "SUM":
        return f"SUM(CASE WHEN {predicate_sql} THEN {arg} ELSE 0 END)"
    if agg == "COUNT_DISTINCT":
        return f"COUNT(DISTINCT CASE WHEN {predicate_sql} THEN {arg} END)"
    # AVG / MIN / MAX / COUNT: implicit ELSE NULL is skipped by these aggs.
    return f"{agg}(CASE WHEN {predicate_sql} THEN {arg} END)"


# -------------------------------------------------- required-dataset book

class _RequiredIndex:
    """Tracks required datasets keyed by (dataset_id, alias).

    Role-playing means the same dataset may appear under multiple aliases
    in one query (e.g. ``sold_date`` and ``ship_date`` both point at
    ``date_dim``). The BFS walker will distinguish them by alias.
    """

    def __init__(self) -> None:
        self._items: Dict[Tuple[int, str], DatasetRef] = {}
        self._order: List[Tuple[int, str]] = []

    def add(self, ds: DatasetRef, *, alias: Optional[str] = None) -> DatasetRef:
        use_alias = alias or ds.alias or ds.dataset_name
        key = (ds.dataset_id, use_alias)
        if key in self._items:
            return self._items[key]
        copy = DatasetRef(
            dataset_id=ds.dataset_id, dataset_name=ds.dataset_name,
            database_name=ds.database_name, table_name=ds.table_name,
            source_query=ds.source_query, alias=use_alias,
        )
        self._items[key] = copy
        self._order.append(key)
        return copy

    def as_list(self) -> List[DatasetRef]:
        return [self._items[k] for k in self._order]


# ---------------------------------------------------------- resolver

class Resolver:
    """Compile a QueryRequest against a CatalogDAO into a LogicalPlan.

    The resolver is stateless across calls; one instance can serve many.
    """

    def __init__(self, catalog: CatalogDAO):
        self.catalog = catalog

    def resolve(self, req: QueryRequest) -> LogicalPlan:
        model_id = self.catalog.resolve_model_id(req.model)
        if model_id is None:
            raise UnknownModelError(f"Unknown model: {req.model}")

        required = _RequiredIndex()

        metrics = self._resolve_metrics(model_id, req.metrics, required)
        dimensions = self._resolve_dimensions(model_id, req.dimensions, required)
        where_filters, having_filters = self._resolve_filters(
            model_id, req.where, req.having, metrics, required,
        )

        anchor = self._pick_anchor(model_id, metrics, required)
        grain_count = len({
            m.primary_dataset_id for m in metrics if m.primary_dataset_id is not None
        })

        chasm_warning = None
        if grain_count >= 2:
            grains = sorted({
                self.catalog.load_dataset(m.primary_dataset_id).dataset_name
                for m in metrics if m.primary_dataset_id is not None
            })
            chasm_warning = (
                f"CHASM_WARNING: metrics span {grain_count} grains "
                f"({', '.join(grains)}) — numbers are likely double-counted. "
                f"Split the request by grain."
            )

        return LogicalPlan(
            model_id=model_id,
            model_name=req.model,
            anchor=anchor,
            required_datasets=required.as_list(),
            metrics=metrics,
            dimensions=dimensions,
            filters=where_filters + having_filters,
            join_steps=[],    # populated by join resolver (task #23)
            sort=[SortKey(field=s.field, direction=s.direction.upper()) for s in req.sort],
            limit=int(req.limit or 0),
            grain_count=grain_count,
            chasm_warning=chasm_warning,
        )

    # -------- metrics ----------

    def _resolve_metrics(self, model_id: int, names: List[str],
                         required: _RequiredIndex) -> List[MetricRef]:
        resolved: List[MetricRef] = []
        for raw in names:
            name = (raw or "").strip()
            if not name:
                continue
            expr, primary_ds_id, metric_id = self._compose_metric(
                model_id, name, required, visited=set(), depth=0,
            )
            resolved.append(MetricRef(
                metric_id=metric_id,
                metric_name=name,
                expression=expr,
                primary_dataset_id=primary_ds_id,
            ))
        return resolved

    def _compose_metric(self, model_id: int, name: str,
                        required: _RequiredIndex,
                        *, visited: Set[str], depth: int) -> Tuple[str, Optional[int], int]:
        """Resolve ``name`` to (final SQL expression, primary_dataset_id, metric_id).

        Handles three metric shapes in one recursive pass:
          1. Simple metric with METRIC_EXPRESSION.expression (may contain
             ``${other_metric}`` references).
          2. Filtered rollup: (base_metric_id, METRIC_FILTER rows) composed
             into AGG(CASE WHEN ... END).
          3. Composed: expression contains ``${other}`` placeholders —
             recursively resolve each and splice with paren-wrap.

        Cycle detection: ``visited`` is the chain of ancestor metric names;
        re-entering any name in it raises CycleError.

        Depth limit: guards against deep legal chains that would bloat the
        emitted SQL.
        """
        if name in visited:
            raise CycleError(
                f"Metric reference cycle detected: {' -> '.join([*visited, name])}",
                chain=[*visited, name],
            )
        if depth > _MAX_METRIC_REF_DEPTH:
            raise CompileError(
                f"Metric '{name}' reference chain exceeds max depth "
                f"({_MAX_METRIC_REF_DEPTH}). Refactor the composition."
            )
        visited = visited | {name}

        row = self.catalog.find_metric(model_id, name)
        if row is None:
            raise UnknownEntityError(f"Unknown metric: {name}")

        if row.base_metric_id is not None:
            # Filtered rollup — aggregate_arg is raw SQL, not allowed to
            # contain ${...} references (a metric reference inside an
            # aggregate call is ill-formed).
            base = self._load_base_metric(row.base_metric_id, for_metric=name)
            filters = self.catalog.load_metric_filters(row.metric_id)
            if base.aggregate_arg and _METRIC_REF_RE.search(base.aggregate_arg):
                raise CompileError(
                    f"Filtered metric '{name}': base '{base.metric_name}' "
                    f"aggregate_arg contains a ${{...}} reference which is "
                    f"not supported inside an aggregate."
                )
            expression = _compose_filtered_expression(base, filters)
            primary_ds_id = row.primary_dataset_id or base.primary_dataset_id
            self._mark_metric_datasets(required, row.metric_id)
            self._mark_metric_datasets(required, base.metric_id)
            for frow in filters:
                ds = self.catalog.load_dataset(frow.dataset_id)
                if ds is not None:
                    required.add(ds)
            if primary_ds_id is not None:
                pds = self.catalog.load_dataset(primary_ds_id)
                if pds is not None:
                    required.add(pds)
            return expression, primary_ds_id, row.metric_id

        if not row.expression_teradata:
            raise CompileError(
                f"Metric '{name}' has no TERADATA dialect expression."
            )

        raw_expr = row.expression_teradata
        refs = _METRIC_REF_RE.findall(raw_expr)

        if not refs:
            # Plain metric — no composition needed.
            primary_ds_id = row.primary_dataset_id
            self._mark_metric_datasets(required, row.metric_id)
            if primary_ds_id is not None:
                pds = self.catalog.load_dataset(primary_ds_id)
                if pds is not None:
                    required.add(pds)
            return raw_expr, primary_ds_id, row.metric_id

        # Composed metric — recursively resolve each placeholder, splice.
        sub_primary_ids: Set[int] = set()
        expression = raw_expr
        for ref in refs:
            sub_expr, sub_pds, _ = self._compose_metric(
                model_id, ref, required, visited=visited, depth=depth + 1,
            )
            # Wrap in parens for safe precedence.
            expression = expression.replace("${" + ref + "}", f"({sub_expr})")
            if sub_pds is not None:
                sub_primary_ids.add(sub_pds)

        # Primary dataset: prefer the composed metric's declared primary,
        # otherwise unify from the sub-refs. Multiple distinct primaries
        # among sub-refs means the composition itself spans grains — that
        # is a chasm trap and we reject it up-front rather than emitting
        # silently-wrong SQL.
        declared = row.primary_dataset_id
        if declared is not None:
            primary_ds_id: Optional[int] = declared
            if sub_primary_ids and declared not in sub_primary_ids and \
               not sub_primary_ids.issubset({declared}):
                # sub-refs span grains outside the declared primary
                if len(sub_primary_ids) > 1:
                    raise CompileError(
                        f"Metric '{name}' composes sub-metrics on "
                        f"{len(sub_primary_ids)} different grains — "
                        f"cross-grain composition is a chasm trap."
                    )
        else:
            if len(sub_primary_ids) > 1:
                raise CompileError(
                    f"Metric '{name}' composes sub-metrics on "
                    f"{len(sub_primary_ids)} different grains — "
                    f"cross-grain composition is a chasm trap."
                )
            primary_ds_id = next(iter(sub_primary_ids), None)

        # Required datasets: this metric's own field_refs + primary.
        self._mark_metric_datasets(required, row.metric_id)
        if primary_ds_id is not None:
            pds = self.catalog.load_dataset(primary_ds_id)
            if pds is not None:
                required.add(pds)
        return expression, primary_ds_id, row.metric_id

    def _load_base_metric(self, base_id: int, *, for_metric: str) -> MetricRow:
        # Catalog DAO doesn't expose load-by-id directly; find via datasets
        # list is wasteful. Iterate the in-memory cache by dataset or rely
        # on a future DAO method. For now scan: tests & production both
        # have few metrics.
        # NOTE(rh): the DbCatalog will override _load_base_metric with a
        # direct SELECT.  The Protocol doesn't mandate it, so we add a
        # defensive duck-typed call.
        loader = getattr(self.catalog, "load_metric_by_id", None)
        if callable(loader):
            found = loader(base_id)
            if found is not None:
                return found
        # Slow path: scan the in-memory catalog.
        scan = getattr(self.catalog, "metrics", {})
        for row in scan.values():
            if row.metric_id == base_id:
                return row
        raise CompileError(
            f"Filtered metric '{for_metric}' references unknown base_metric_id={base_id}"
        )

    def _mark_metric_datasets(self, required: _RequiredIndex, metric_id: int) -> None:
        for fid in self.catalog.load_metric_field_refs(metric_id):
            # Resolve each field's dataset. Catalog DAO doesn't expose a
            # field-by-id helper; look through the in-memory `fields` dict
            # if present, otherwise skip (real DbCatalog will expose it).
            fields_map = getattr(self.catalog, "fields", None)
            if fields_map is None:
                continue
            for (ds_id, _fname), f in fields_map.items():  # type: ignore[attr-defined]
                if f.field_id == fid:
                    ds = self.catalog.load_dataset(ds_id)
                    if ds is not None:
                        required.add(ds)
                    break

    # -------- dimensions -------

    def _resolve_dimensions(self, model_id: int, tokens: List[str],
                            required: _RequiredIndex) -> List[ResolvedDim]:
        resolved: List[ResolvedDim] = []
        for raw in tokens:
            token = (raw or "").strip()
            if not token:
                continue
            field_part, grain = _split_grain(token)
            if grain and grain not in _GRAIN_UNITS:
                raise CompileError(
                    f"Unknown grain '{grain}' on dim '{token}' "
                    f"(allowed: {sorted(_GRAIN_UNITS)})"
                )
            prefix, field_name = _split_prefix(field_part)

            role_rel = None
            if prefix is not None:
                role_rel = self.catalog.find_relationship_by_role(model_id, prefix)

            if role_rel is not None:
                target_ds = self.catalog.load_dataset(role_rel.to_dataset_id)
                if target_ds is None:
                    raise CompileError(
                        f"Dim '{token}': role '{prefix}' points to missing dataset"
                    )
                field = self.catalog.find_field_on_dataset(target_ds.dataset_id, field_name)
                if field is None:
                    raise UnknownEntityError(
                        f"Dim '{token}': no field '{field_name}' on role '{prefix}'"
                    )
                alias = prefix
                ds_for_required = target_ds
                role_edge_id = role_rel.relationship_id
                # Also pin the role's FROM side so BFS is forced through
                # this edge (handled later in the joins task; we still
                # need the dataset available as a required-plan node).
                from_ds = self.catalog.load_dataset(role_rel.from_dataset_id)
                if from_ds is not None:
                    required.add(from_ds)
                column_alias = f"{alias}_{field_name}"
            else:
                field = self.catalog.find_field(model_id, prefix, field_name)
                if field is None:
                    raise UnknownEntityError(
                        f"Dim '{token}': no field '{field_name}'"
                        + (f" on dataset '{prefix}'" if prefix else "")
                    )
                ds_for_required = self.catalog.load_dataset(field.dataset_id)
                alias = prefix or (ds_for_required.dataset_name if ds_for_required else field_name)
                role_edge_id = None
                column_alias = field_name

            if ds_for_required is not None:
                required.add(ds_for_required, alias=alias)

            # Ambiguity check for un-roled dim: reject when the target
            # dataset has >1 incoming edges in this model.
            if role_rel is None and ds_for_required is not None:
                self._check_unambiguous(model_id, ds_for_required, token)

            full_alias = (f"{column_alias}_{grain.lower()}"
                          if grain else column_alias)
            resolved.append(ResolvedDim(
                field=field,
                dataset_alias=alias,
                grain=grain,
                role_edge_id=role_edge_id,
                column_alias=full_alias,
            ))
        return resolved

    def _check_unambiguous(self, model_id: int, ds: DatasetRef, token: str) -> None:
        incoming = [
            r for r in self.catalog.load_relationships(model_id)
            if r.to_dataset_id == ds.dataset_id
        ]
        if len(incoming) > 1:
            roles = [r.role_name or r.relationship_name or str(r.relationship_id)
                     for r in incoming]
            raise AmbiguousPathError(
                f"AMBIGUOUS_PATH: dim '{token}' has {len(incoming)} paths "
                f"to {ds.dataset_name} (roles: {', '.join(roles)}). "
                f"Prefix the dim with a role, e.g. role_name.field_name.",
                roles=roles,
            )

    # -------- filters ----------

    def _resolve_filters(self, model_id: int,
                         where: List[QueryFilter],
                         having: List[QueryFilter],
                         metrics: List[MetricRef],
                         required: _RequiredIndex,
                         ) -> Tuple[List[ResolvedFilter], List[ResolvedFilter]]:
        where_out: List[ResolvedFilter] = []
        for f in where:
            if not f.field:
                raise CompileError("WHERE filter missing 'field'")
            prefix, field_name = _split_prefix(f.field)

            role_rel = None
            if prefix is not None:
                role_rel = self.catalog.find_relationship_by_role(model_id, prefix)

            if role_rel is not None:
                target_ds = self.catalog.load_dataset(role_rel.to_dataset_id)
                alias = prefix
                ds_for_required = target_ds
                role_edge_id = role_rel.relationship_id
                from_ds = self.catalog.load_dataset(role_rel.from_dataset_id)
                if from_ds is not None:
                    required.add(from_ds)
            else:
                if prefix is None:
                    raise CompileError(
                        f"WHERE filter '{f.field}' must be prefixed with "
                        f"dataset or role."
                    )
                ds_for_required = None
                for ds in self.catalog.load_datasets(model_id):
                    if ds.dataset_name == prefix:
                        ds_for_required = ds
                        break
                if ds_for_required is None:
                    raise UnknownEntityError(
                        f"WHERE filter references unknown dataset/role: {prefix}"
                    )
                alias = prefix
                role_edge_id = None

            if ds_for_required is not None:
                required.add(ds_for_required, alias=alias)

            where_out.append(ResolvedFilter(
                kind="WHERE",
                lhs=f"{alias}.{field_name}",
                op=f.op,
                rhs=_encode_filter_rhs(f),
                dataset_id=ds_for_required.dataset_id if ds_for_required else None,
                role_edge_id=role_edge_id,
            ))

        having_out: List[ResolvedFilter] = []
        known_metrics = {m.metric_name for m in metrics}
        for f in having:
            if not f.metric:
                raise CompileError("HAVING filter missing 'metric'")
            if f.metric not in known_metrics:
                raise UnknownEntityError(
                    f"HAVING filter references metric '{f.metric}' "
                    f"which is not in the request"
                )
            having_out.append(ResolvedFilter(
                kind="HAVING",
                lhs=f.metric,
                op=f.op,
                rhs=_encode_filter_rhs(f),
                dataset_id=None,
                role_edge_id=None,
            ))
        return where_out, having_out

    # -------- anchor -----------

    def _pick_anchor(self, model_id: int, metrics: List[MetricRef],
                     required: _RequiredIndex) -> DatasetRef:
        # Single-grain: the metric's primary dataset is the anchor.
        primary_ids = {m.primary_dataset_id for m in metrics
                       if m.primary_dataset_id is not None}
        if len(primary_ids) == 1:
            (pid,) = primary_ids
            ds = self.catalog.load_dataset(pid)
            if ds is not None:
                return required.add(ds)

        # Fallback: most-connected required dataset.
        items = required.as_list()
        if not items:
            raise CompileError(
                "Request is empty: no anchor dataset could be identified."
            )
        rels = self.catalog.load_relationships(model_id)
        counts = {ds.dataset_id: 0 for ds in items}
        for r in rels:
            if r.from_dataset_id in counts:
                counts[r.from_dataset_id] += 1
            if r.to_dataset_id in counts:
                counts[r.to_dataset_id] += 1
        best = max(items, key=lambda d: (counts.get(d.dataset_id, 0), -d.dataset_id))
        return best
