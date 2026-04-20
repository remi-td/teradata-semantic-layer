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


class DescribeResponse(BaseModel):
    model_config = _CFG
    entity_type: str
    entity_name: str
    model_name: Optional[str] = None
    attributes: List[DescribeAttribute]


# ------------------------------------------------------------ query builder

class QueryFilter(BaseModel):
    field: Optional[str] = None
    metric: Optional[str] = None
    op: str
    value: Optional[Any] = None
    values: Optional[List[Any]] = None
    type: Optional[str] = None   # STRING | NUMBER | DATE | RAW


class QuerySort(BaseModel):
    field: str
    direction: str = "ASC"


class QueryRequest(BaseModel):
    model_config = _CFG
    model: str
    metrics: List[str] = Field(default_factory=list)
    dimensions: List[str] = Field(default_factory=list)
    where: List[QueryFilter] = Field(default_factory=list)
    having: List[QueryFilter] = Field(default_factory=list)
    sort: List[QuerySort] = Field(default_factory=list)
    limit: int = 0
    execute: bool = False


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
