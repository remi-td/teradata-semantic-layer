"""Pydantic models for request / response payloads."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


# Disable pydantic's ``model_*`` protected-namespace warning — the semantic
# catalog naturally uses ``model_name`` / ``model_id`` fields everywhere.
_CFG = ConfigDict(protected_namespaces=())


# ----------------------------------------------------------------- catalog

class ModelSummary(BaseModel):
    model_config = _CFG
    model_id: int
    model_name: str
    description: Optional[str] = None
    dataset_count: int = 0
    metric_count: int = 0
    view_count: int = 0


class SearchHit(BaseModel):
    entity_type: str
    entity_name: str
    parent_name: Optional[str] = None
    description: Optional[str] = None
    synonyms: Optional[str] = None
    relevance: int


class GraphNode(BaseModel):
    id: str
    label: str
    kind: str            # DATASET | METRIC | VIEW | MODEL
    sub_kind: Optional[str] = None   # CUBE | TABLE | RATIO | SIMPLE ...
    description: Optional[str] = None
    meta: Dict[str, Any] = Field(default_factory=dict)


class GraphEdge(BaseModel):
    id: str
    source: str
    target: str
    kind: str            # RELATIONSHIP | METRIC_OF | VIEW_OF
    label: Optional[str] = None
    cardinality: Optional[str] = None
    role_name: Optional[str] = None


class GraphPayload(BaseModel):
    model_config = _CFG
    model_name: str
    nodes: List[GraphNode]
    edges: List[GraphEdge]


class DescribeAttribute(BaseModel):
    attr_ordinal: int
    attr_key: str
    attr_value: str


class RelationshipHint(BaseModel):
    """One edge incident to a DATASET, surfaced for compile disambiguation.

    ``prefix`` is the exact token to prepend in a dimension/filter (i.e.
    ``prefix.field``) to force the path through this edge.
    """
    prefix: str
    direction: str             # 'incoming' | 'outgoing'
    other_dataset: str
    cardinality: Optional[str] = None
    role_name: Optional[str] = None
    relationship_name: Optional[str] = None
    relationship_id: int


class DescribeResponse(BaseModel):
    model_config = _CFG
    entity_type: str
    entity_name: str
    model_name: Optional[str] = None
    attributes: List[DescribeAttribute]
    relationships: Optional[List[RelationshipHint]] = None


# ------------------------------------------------------------ query builder

class QueryFilter(BaseModel):
    field: Optional[str] = Field(
        default=None,
        description=(
            "Pre-aggregation filter target (WHERE). Use 'dataset.field' or "
            "'role.field' to disambiguate. Mutually exclusive with `metric`."
        ),
    )
    metric: Optional[str] = Field(
        default=None,
        description=(
            "Post-aggregation filter target (HAVING). The metric name as "
            "defined in the model. Mutually exclusive with `field`."
        ),
    )
    op: str = Field(
        description=(
            "SQL comparison operator: =, <>, !=, >, >=, <, <=, IN, NOT IN, "
            "BETWEEN, NOT BETWEEN, LIKE, NOT LIKE, IS NULL, IS NOT NULL."
        ),
    )
    value: Optional[Any] = Field(
        default=None,
        description="Single literal for =, <>, >, >=, <, <=, LIKE.",
    )
    values: Optional[List[Any]] = Field(
        default=None,
        description="Multi-valued literal for IN, NOT IN, BETWEEN.",
    )
    type: Optional[str] = Field(
        default=None,
        description=(
            "Value-encoding hint: STRING (default), NUMBER, DATE, or RAW "
            "(verbatim SQL — operator-trusted, never user input)."
        ),
    )


class QuerySort(BaseModel):
    field: str = Field(
        description=(
            "Either a metric name or a dimension token ('dataset.field' / "
            "'role.field'). Must be present in `metrics` or `dimensions`."
        ),
    )
    direction: str = Field(default="ASC", description="ASC or DESC.")


class QueryRequest(BaseModel):
    """Structured request for the semantic compile/execute pipeline.

    Tokens use string form throughout:

    - **Metric**: a metric name as defined in the model (e.g. `revenue`).
    - **Dimension**: a field token. Bare (`p_brand`) when unambiguous, or
      qualified as `dataset.field` (e.g. `supplier.s_name`) or `role.field`
      (e.g. `lineitem_to_part.p_brand`) when more than one path reaches
      the target dataset. The `role` portion accepts either the
      relationship's `role_name` or its `relationship_name`.
    - **Grain** (optional): append `:GRAIN` to a date/timestamp dimension —
      e.g. `o_orderdate:MONTH`. Allowed: DAY, WEEK, MONTH, QUARTER, YEAR.

    On AMBIGUOUS_PATH, the error's `details.suggestions` lists the exact
    tokens to retry with. Use `semantic_describe(entity_type='DATASET',
    entity_name=...)` to enumerate the relationship prefixes a target
    dataset accepts.
    """
    model_config = _CFG
    model: str = Field(
        description="Semantic-model name (e.g. 'tpch_orders').",
    )
    metrics: List[str] = Field(
        default_factory=list,
        description="Metric names to aggregate.",
    )
    dimensions: List[str] = Field(
        default_factory=list,
        description=(
            "Dimension tokens: 'field', 'dataset.field', or 'role.field'. "
            "Append ':GRAIN' on date dims to bucket (DAY|WEEK|MONTH|QUARTER|YEAR)."
        ),
    )
    where: List[QueryFilter] = Field(
        default_factory=list,
        description="Pre-aggregation filters on fields.",
    )
    having: List[QueryFilter] = Field(
        default_factory=list,
        description="Post-aggregation filters on metrics.",
    )
    sort: List[QuerySort] = Field(
        default_factory=list,
        description="ORDER BY clauses; entries reference metrics or dimensions.",
    )
    limit: int = Field(
        default=0,
        description="Row cap. 0 = unlimited (compile); execute caps at 500.",
    )
    execute: bool = Field(
        default=False,
        description="Reserved — execution is controlled by the endpoint, not the body.",
    )


class QueryExecution(BaseModel):
    columns: List[str]
    rows: List[List[Any]]
    row_count: int
    truncated: bool = False


class QueryResponse(BaseModel):
    compiled_sql: Optional[str]
    is_valid: Optional[int]
    validation_message: Optional[str]
    anchor_dataset: Optional[str]
    joined_datasets: Optional[str]
    execution: Optional[QueryExecution] = None


# ----------------------------------------------------------------- import

class ImportItem(BaseModel):
    kind: str
    payload: Dict[str, Any]


class ImportResultRow(BaseModel):
    ord: int
    kind: str
    name: Optional[str] = None
    status: str                    # OK | ERROR | SKIP
    message: str
    entity_id: Optional[int] = None


class ImportRequest(BaseModel):
    model_config = _CFG
    model: str
    text: Optional[str] = None     # YAML or JSON payload
    items: Optional[List[ImportItem]] = None
    dry_run: bool = True


class ImportResponse(BaseModel):
    model_config = _CFG
    model: str
    dry_run: bool
    total: int
    ok_count: int
    error_count: int
    results: List[ImportResultRow]
    applied: bool                  # True when committed to catalog


# -------------------------------------------------------------- explain

class ExplainRequest(BaseModel):
    sql: str


class ExplainResponse(BaseModel):
    plan: str
    ok: bool
    message: Optional[str] = None
