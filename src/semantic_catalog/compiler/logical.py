"""LogicalPlan and its constituent dataclasses.

Dialect-neutral. The plan is the contract between the resolver (which
walks the catalog) and the renderer (which emits SQL). Tests fabricate
plans directly without touching a database.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple


@dataclass
class DatasetRef:
    dataset_id: int
    dataset_name: str
    # Physical mapping. When ``source_query`` is set and ``database_name``
    # is NULL, the dataset is a cube: the source_query is wrapped as a
    # derived table in FROM.
    database_name: Optional[str] = None
    table_name: Optional[str] = None
    source_query: Optional[str] = None
    # Alias used in FROM / JOIN. Equal to ``dataset_name`` in the common
    # case; differs when a role-played relationship pins an alias.
    alias: str = ""
    # When set, the BFS may only enter this node via this relationship.
    role_edge_id: Optional[int] = None
    # When set, the BFS may only enter this node from the in-plan node
    # whose alias matches this string.  Used for transitively-reached
    # datasets (e.g. ``supplier_nation_region`` may only be joined from
    # ``supplier_nation``, not from ``customer_nation``).
    entry_from_alias: Optional[str] = None

    def __post_init__(self) -> None:
        if not self.alias:
            self.alias = self.dataset_name


@dataclass
class FieldRef:
    field_id: int
    dataset_id: int
    field_name: str
    # Raw expression from the catalog. When it equals ``field_name`` the
    # renderer prepends the alias dot; otherwise it is emitted verbatim.
    expression: str
    is_time_dimension: bool = False


@dataclass
class MetricRef:
    metric_id: int
    metric_name: str
    # Final composed SQL (post filtered-metric rollup, post metric-in-metric
    # substitution). The resolver is responsible for producing this.
    expression: str
    primary_dataset_id: Optional[int] = None


@dataclass
class ResolvedDim:
    field: FieldRef
    # Dataset alias in the emitted FROM — may equal ``field.dataset`` name
    # or a role name when role-playing is active.
    dataset_alias: str
    grain: Optional[str] = None          # DAY | WEEK | MONTH | QUARTER | YEAR
    role_edge_id: Optional[int] = None
    # Output column alias — defaults to ``field_name`` but gets a role
    # prefix when role-played, plus a grain suffix when a grain is set.
    column_alias: Optional[str] = None


@dataclass
class ResolvedFilter:
    kind: str           # "WHERE" | "HAVING"
    lhs: str            # resolved left-hand side: "customer.c_name" or a metric name
    op: str             # =, <>, <, <=, >, >=, LIKE, IN
    rhs: str            # already encoded (quoted / wrapped in parens)
    dataset_id: Optional[int] = None
    role_edge_id: Optional[int] = None


@dataclass
class JoinStep:
    step_ordinal: int
    relationship_id: Optional[int]       # None for step 0 (anchor FROM)
    from_dataset_id: Optional[int]
    to_dataset_id: int
    # Pre-rendered SQL fragment. For step 0: "FROM ...". For steps >0:
    # "INNER JOIN ... ON ...". We keep it as a string because the ON clause
    # is easier to compose from catalog rows than via AST manipulation.
    join_sql: str


@dataclass
class SortKey:
    field: str          # metric or dim output column name
    direction: str = "ASC"


@dataclass
class LogicalPlan:
    model_id: int
    model_name: str
    anchor: DatasetRef
    required_datasets: List[DatasetRef] = field(default_factory=list)
    metrics: List[MetricRef] = field(default_factory=list)
    dimensions: List[ResolvedDim] = field(default_factory=list)
    filters: List[ResolvedFilter] = field(default_factory=list)
    join_steps: List[JoinStep] = field(default_factory=list)
    sort: List[SortKey] = field(default_factory=list)
    limit: int = 0
    grain_count: int = 0
    chasm_warning: Optional[str] = None
    unresolved: List[str] = field(default_factory=list)

    @property
    def joined_datasets(self) -> List[str]:
        seen = []
        for d in self.required_datasets:
            label = d.dataset_name if d.alias == d.dataset_name else f"{d.dataset_name} AS {d.alias}"
            if label not in seen:
                seen.append(label)
        return seen
