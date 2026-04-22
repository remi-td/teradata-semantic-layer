"""Catalog DAO.

This is the only module in the compiler that touches the database. Each
method is a single round-trip that the resolver composes. Tests fabricate
an in-memory fake implementing the same Protocol.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Protocol

from .logical import DatasetRef, FieldRef


# -- Record types returned by the DAO. These are distinct from the plan
# -- dataclasses because they carry catalog-level state (e.g. aggregate_fn
# -- for filtered-metric composition) that is not part of the final plan.

@dataclass
class MetricRow:
    metric_id: int
    metric_name: str
    description: Optional[str]
    metric_type: Optional[str]
    primary_dataset_id: Optional[int]
    base_metric_id: Optional[int]
    aggregate_fn: Optional[str]
    aggregate_arg: Optional[str]
    expression_teradata: Optional[str]    # from METRIC_EXPRESSION dialect='TERADATA'


@dataclass
class MetricFilterRow:
    filter_ord: int
    field_id: int
    dataset_id: int
    dataset_name: str
    field_name: str
    op: str
    filter_value: str


@dataclass
class RelationshipRow:
    relationship_id: int
    relationship_name: Optional[str]
    from_dataset_id: int
    to_dataset_id: int
    cardinality: Optional[str]
    role_name: Optional[str]


@dataclass
class RelColumnRow:
    relationship_id: int
    from_field_id: int
    from_field_name: str
    to_field_id: int
    to_field_name: str
    column_position: int


class CatalogDAO(Protocol):
    """Catalog read surface used by the resolver."""

    # -------- model ----------
    def resolve_model_id(self, model_name: str) -> Optional[int]: ...

    # -------- datasets -------
    def load_datasets(self, model_id: int) -> List[DatasetRef]: ...
    def load_dataset(self, dataset_id: int) -> Optional[DatasetRef]: ...

    # -------- fields ---------
    def find_field(self, model_id: int, dataset_name: Optional[str],
                   field_name: str) -> Optional[FieldRef]: ...
    def find_field_on_dataset(self, dataset_id: int,
                              field_name: str) -> Optional[FieldRef]: ...
    def load_metric_field_refs(self, metric_id: int) -> List[int]: ...

    # -------- metrics --------
    def find_metric(self, model_id: int, metric_name: str) -> Optional[MetricRow]: ...
    def load_metric_filters(self, metric_id: int) -> List[MetricFilterRow]: ...

    # -------- relationships --
    def load_relationships(self, model_id: int) -> List[RelationshipRow]: ...
    def find_relationship_by_role(self, model_id: int,
                                  role_name: str) -> Optional[RelationshipRow]: ...
    def load_rel_columns(self, relationship_id: int) -> List[RelColumnRow]: ...

    # -------- security -------
    def load_row_filters(self, model_id: int,
                         groups: List[str]) -> List[str]:
        """Return ROW_FILTER policy expressions for the model that apply
        to any of the supplied groups (or whose ``group_name`` is NULL,
        meaning 'applies to everyone'). Called by the API layer for
        per-request RLS — see ``CompileRequest.policy_fragments``. May
        return an empty list; implementations that don't support RLS
        return an empty list."""
        ...
