"""In-memory CatalogDAO — the testing fake.

Lets unit tests construct a synthetic catalog without touching a database.
Mirrors the real DAO's method surface 1:1; no performance considerations.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from .catalog import (
    CatalogDAO,
    MetricFilterRow,
    MetricRow,
    RelColumnRow,
    RelationshipRow,
)
from .logical import DatasetRef, FieldRef


@dataclass
class InMemoryCatalog:
    """Minimal catalog fake. Callers mutate the lists directly in tests."""

    # (model_id, model_name) rows
    models: Dict[str, int] = field(default_factory=dict)
    # datasets keyed by dataset_id
    datasets: Dict[int, DatasetRef] = field(default_factory=dict)
    # datasets_by_model[model_id] -> list of dataset_ids
    datasets_by_model: Dict[int, List[int]] = field(default_factory=dict)
    # fields keyed by (dataset_id, field_name)
    fields: Dict[Tuple[int, str], FieldRef] = field(default_factory=dict)
    # metric rows keyed by (model_id, metric_name)
    metrics: Dict[Tuple[int, str], MetricRow] = field(default_factory=dict)
    # metric_id -> list of MetricFilterRow
    metric_filters: Dict[int, List[MetricFilterRow]] = field(default_factory=dict)
    # metric_id -> list of field_ids
    metric_field_refs: Dict[int, List[int]] = field(default_factory=dict)
    # relationships[model_id] -> list of RelationshipRow
    relationships_by_model: Dict[int, List[RelationshipRow]] = field(default_factory=dict)
    # rel_columns[relationship_id] -> list of RelColumnRow
    rel_columns: Dict[int, List[RelColumnRow]] = field(default_factory=dict)
    # row_filters_by_model[model_id] -> list of (expression, group_name|None)
    row_filters_by_model: Dict[int, List[Tuple[str, Optional[str]]]] = field(default_factory=dict)

    # ----- DAO methods (CatalogDAO Protocol) ------------------------

    def resolve_model_id(self, model_name: str) -> Optional[int]:
        return self.models.get(model_name)

    def load_datasets(self, model_id: int) -> List[DatasetRef]:
        return [self.datasets[did] for did in self.datasets_by_model.get(model_id, [])]

    def load_dataset(self, dataset_id: int) -> Optional[DatasetRef]:
        return self.datasets.get(dataset_id)

    def find_field(self, model_id: int, dataset_name: Optional[str],
                   field_name: str) -> Optional[FieldRef]:
        dids = self.datasets_by_model.get(model_id, [])
        for did in dids:
            ds = self.datasets[did]
            if dataset_name is not None and ds.dataset_name != dataset_name:
                continue
            f = self.fields.get((did, field_name))
            if f is not None:
                return f
        return None

    def find_field_on_dataset(self, dataset_id: int,
                              field_name: str) -> Optional[FieldRef]:
        return self.fields.get((dataset_id, field_name))

    def load_metric_field_refs(self, metric_id: int) -> List[int]:
        return list(self.metric_field_refs.get(metric_id, []))

    def find_metric(self, model_id: int, metric_name: str) -> Optional[MetricRow]:
        return self.metrics.get((model_id, metric_name))

    def load_metric_filters(self, metric_id: int) -> List[MetricFilterRow]:
        return list(self.metric_filters.get(metric_id, []))

    def load_relationships(self, model_id: int) -> List[RelationshipRow]:
        return list(self.relationships_by_model.get(model_id, []))

    def find_relationship_by_role(self, model_id: int,
                                  role_name: str) -> Optional[RelationshipRow]:
        for r in self.relationships_by_model.get(model_id, []):
            if r.role_name == role_name:
                return r
        return None

    def load_rel_columns(self, relationship_id: int) -> List[RelColumnRow]:
        return list(self.rel_columns.get(relationship_id, []))

    def load_row_filters(self, model_id: int, groups: List[str]) -> List[str]:
        """InMem stub: returns fragments registered via ``add_row_filter``.

        Tests use ``add_row_filter(model_id, fragment, group_name=None)``
        to pre-register policies on the fake catalog.
        """
        out: List[str] = []
        for frag, gname in self.row_filters_by_model.get(model_id, []):
            if gname is None or gname in groups:
                out.append(frag)
        return out

    # ----- Builder conveniences (test-only) -------------------------

    def add_model(self, name: str, *, model_id: Optional[int] = None) -> int:
        mid = model_id if model_id is not None else (max(self.models.values(), default=0) + 1)
        self.models[name] = mid
        self.datasets_by_model.setdefault(mid, [])
        return mid

    def add_dataset(self, model_id: int, name: str, *, dataset_id: Optional[int] = None,
                    database: Optional[str] = None, table: Optional[str] = None,
                    source_query: Optional[str] = None) -> DatasetRef:
        did = dataset_id if dataset_id is not None else (max(self.datasets.keys(), default=0) + 1)
        ds = DatasetRef(
            dataset_id=did, dataset_name=name,
            database_name=database, table_name=table or name,
            source_query=source_query, alias=name,
        )
        self.datasets[did] = ds
        self.datasets_by_model.setdefault(model_id, []).append(did)
        return ds

    def add_field(self, dataset: DatasetRef, name: str, *, expression: Optional[str] = None,
                  is_time: bool = False, field_id: Optional[int] = None) -> FieldRef:
        fid = field_id if field_id is not None else (max((f.field_id for f in self.fields.values()), default=0) + 1)
        f = FieldRef(
            field_id=fid, dataset_id=dataset.dataset_id,
            field_name=name, expression=(expression if expression is not None else name),
            is_time_dimension=is_time,
        )
        self.fields[(dataset.dataset_id, name)] = f
        return f

    def add_metric(self, model_id: int, name: str, *, expression: str,
                   primary_dataset_id: Optional[int] = None,
                   metric_type: str = "SIMPLE",
                   field_refs: Optional[List[int]] = None,
                   metric_id: Optional[int] = None) -> MetricRow:
        mid = metric_id if metric_id is not None else (max((m.metric_id for m in self.metrics.values()), default=0) + 1)
        row = MetricRow(
            metric_id=mid, metric_name=name, description=None, metric_type=metric_type,
            primary_dataset_id=primary_dataset_id, base_metric_id=None,
            aggregate_fn=None, aggregate_arg=None,
            expression_teradata=expression,
        )
        self.metrics[(model_id, name)] = row
        if field_refs:
            self.metric_field_refs[mid] = list(field_refs)
        return row

    def add_base_metric(self, model_id: int, name: str, *, aggregate_fn: str,
                        aggregate_arg: str, primary_dataset_id: int,
                        field_refs: Optional[List[int]] = None,
                        metric_id: Optional[int] = None) -> MetricRow:
        mid = metric_id if metric_id is not None else (max((m.metric_id for m in self.metrics.values()), default=0) + 1)
        row = MetricRow(
            metric_id=mid, metric_name=name, description=None, metric_type="SIMPLE",
            primary_dataset_id=primary_dataset_id, base_metric_id=None,
            aggregate_fn=aggregate_fn, aggregate_arg=aggregate_arg,
            expression_teradata=f"{aggregate_fn}({aggregate_arg})",
        )
        self.metrics[(model_id, name)] = row
        if field_refs:
            self.metric_field_refs[mid] = list(field_refs)
        return row

    def add_filtered_metric(self, model_id: int, name: str, *, base: MetricRow,
                            filters: List[Tuple[DatasetRef, FieldRef, str, str]],
                            metric_id: Optional[int] = None) -> MetricRow:
        """filters: list of (dataset, field, op, rhs_already_encoded)."""
        mid = metric_id if metric_id is not None else (max((m.metric_id for m in self.metrics.values()), default=0) + 1)
        row = MetricRow(
            metric_id=mid, metric_name=name, description=None, metric_type="SIMPLE",
            primary_dataset_id=base.primary_dataset_id, base_metric_id=base.metric_id,
            aggregate_fn=None, aggregate_arg=None, expression_teradata=None,
        )
        self.metrics[(model_id, name)] = row
        self.metric_filters[mid] = [
            MetricFilterRow(
                filter_ord=i + 1, field_id=fld.field_id, dataset_id=ds.dataset_id,
                dataset_name=ds.dataset_name, field_name=fld.field_name,
                op=op, filter_value=rhs,
            )
            for i, (ds, fld, op, rhs) in enumerate(filters)
        ]
        return row

    def add_relationship(self, model_id: int, *, name: Optional[str],
                         from_ds: DatasetRef, to_ds: DatasetRef,
                         cardinality: str = "MANY_TO_ONE",
                         role_name: Optional[str] = None,
                         columns: Optional[List[Tuple[FieldRef, FieldRef]]] = None,
                         relationship_id: Optional[int] = None) -> RelationshipRow:
        rid = relationship_id if relationship_id is not None else (
            max((r.relationship_id for rs in self.relationships_by_model.values() for r in rs), default=0) + 1
        )
        r = RelationshipRow(
            relationship_id=rid, relationship_name=name,
            from_dataset_id=from_ds.dataset_id, to_dataset_id=to_ds.dataset_id,
            cardinality=cardinality, role_name=role_name,
        )
        self.relationships_by_model.setdefault(model_id, []).append(r)
        if columns:
            self.rel_columns[rid] = [
                RelColumnRow(
                    relationship_id=rid, from_field_id=ff.field_id, from_field_name=ff.field_name,
                    to_field_id=tf.field_id, to_field_name=tf.field_name,
                    column_position=i + 1,
                )
                for i, (ff, tf) in enumerate(columns)
            ]
        return r

    def add_row_filter(self, model_id: int, expression: str,
                       *, group_name: Optional[str] = None) -> None:
        """Register a ROW_FILTER policy on the model for testing RLS."""
        self.row_filters_by_model.setdefault(model_id, []).append(
            (expression, group_name)
        )


# Register at import so Protocol structural check is eager during type checks.
_: CatalogDAO = InMemoryCatalog()  # type: ignore[assignment]
