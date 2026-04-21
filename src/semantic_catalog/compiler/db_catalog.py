"""DbCatalog — concrete CatalogDAO backed by the teradatasql driver.

Each method is one parametrised SELECT. Callers usually borrow a cursor
from the pool, instantiate a DbCatalog around it, and pass the catalog
into ``compile()``. Nothing is cached across requests; the Teradata
optimizer has the indexes to make these lookups cheap on their own.

Note on schema names:
  Tests and production both use ``{db}.TABLE`` qualification. The
  catalog db comes from settings.catalog_db; we accept it at construction
  time rather than looking it up per call.
"""
from __future__ import annotations

from typing import Any, List, Optional

from .catalog import (
    CatalogDAO,
    MetricFilterRow,
    MetricRow,
    RelColumnRow,
    RelationshipRow,
)
from .logical import DatasetRef, FieldRef


class DbCatalog:
    """Catalog DAO over a DB-API cursor. One instance per compile."""

    def __init__(self, cursor: Any, catalog_db: str):
        self.cur = cursor
        self.db = catalog_db

    # --- helpers ---

    def _fetchone(self, sql: str, *params: Any):
        self.cur.execute(sql, params if params else None)
        return self.cur.fetchone()

    def _fetchall(self, sql: str, *params: Any):
        self.cur.execute(sql, params if params else None)
        return self.cur.fetchall() or []

    # --- model ---

    def resolve_model_id(self, model_name: str) -> Optional[int]:
        r = self._fetchone(
            f"SELECT model_id FROM {self.db}.SEMANTIC_MODEL WHERE model_name = ?",
            model_name,
        )
        return int(r[0]) if r else None

    # --- datasets ---

    def load_datasets(self, model_id: int) -> List[DatasetRef]:
        rows = self._fetchall(
            f"""SELECT dataset_id, dataset_name, DataBaseName, TableName,
                       CAST(source_query AS VARCHAR(8000))
                  FROM {self.db}.DATASET WHERE model_id = ?
                  ORDER BY dataset_id""",
            model_id,
        )
        out: List[DatasetRef] = []
        for r in rows:
            out.append(DatasetRef(
                dataset_id=int(r[0]),
                dataset_name=str(r[1]).strip(),
                database_name=(str(r[2]).strip() if r[2] is not None else None),
                table_name=(str(r[3]).strip() if r[3] is not None else None),
                source_query=(str(r[4]) if r[4] is not None else None),
            ))
        return out

    def load_dataset(self, dataset_id: int) -> Optional[DatasetRef]:
        r = self._fetchone(
            f"""SELECT dataset_id, dataset_name, DataBaseName, TableName,
                       CAST(source_query AS VARCHAR(8000))
                  FROM {self.db}.DATASET WHERE dataset_id = ?""",
            dataset_id,
        )
        if not r:
            return None
        return DatasetRef(
            dataset_id=int(r[0]),
            dataset_name=str(r[1]).strip(),
            database_name=(str(r[2]).strip() if r[2] is not None else None),
            table_name=(str(r[3]).strip() if r[3] is not None else None),
            source_query=(str(r[4]) if r[4] is not None else None),
        )

    # --- fields ---

    def find_field(self, model_id: int, dataset_name: Optional[str],
                   field_name: str) -> Optional[FieldRef]:
        if dataset_name is not None:
            r = self._fetchone(
                f"""SELECT f.field_id, f.dataset_id, f.field_name,
                           CAST(f.expression AS VARCHAR(2000)), f.is_time_dimension
                      FROM {self.db}.FIELD f
                      JOIN {self.db}.DATASET d ON d.dataset_id = f.dataset_id
                     WHERE d.model_id = ? AND d.dataset_name = ? AND f.field_name = ?""",
                model_id, dataset_name, field_name,
            )
        else:
            r = self._fetchone(
                f"""SELECT f.field_id, f.dataset_id, f.field_name,
                           CAST(f.expression AS VARCHAR(2000)), f.is_time_dimension
                      FROM {self.db}.FIELD f
                      JOIN {self.db}.DATASET d ON d.dataset_id = f.dataset_id
                     WHERE d.model_id = ? AND f.field_name = ?""",
                model_id, field_name,
            )
        if not r:
            return None
        expr = str(r[3]) if r[3] is not None else field_name
        return FieldRef(
            field_id=int(r[0]), dataset_id=int(r[1]),
            field_name=str(r[2]).strip(),
            expression=(expr or str(r[2]).strip()),
            is_time_dimension=bool(r[4]),
        )

    def find_field_on_dataset(self, dataset_id: int,
                              field_name: str) -> Optional[FieldRef]:
        r = self._fetchone(
            f"""SELECT field_id, dataset_id, field_name,
                       CAST(expression AS VARCHAR(2000)), is_time_dimension
                  FROM {self.db}.FIELD
                 WHERE dataset_id = ? AND field_name = ?""",
            dataset_id, field_name,
        )
        if not r:
            return None
        expr = str(r[3]) if r[3] is not None else field_name
        return FieldRef(
            field_id=int(r[0]), dataset_id=int(r[1]),
            field_name=str(r[2]).strip(),
            expression=(expr or str(r[2]).strip()),
            is_time_dimension=bool(r[4]),
        )

    def load_metric_field_refs(self, metric_id: int) -> List[int]:
        rows = self._fetchall(
            f"SELECT field_id FROM {self.db}.METRIC_FIELD_REF WHERE metric_id = ?",
            metric_id,
        )
        return [int(r[0]) for r in rows]

    # --- metrics ---

    def find_metric(self, model_id: int, metric_name: str) -> Optional[MetricRow]:
        r = self._fetchone(
            f"""SELECT mt.metric_id, mt.metric_name, mt.description, mt.metric_type,
                       mt.primary_dataset_id, mt.base_metric_id,
                       mt.aggregate_fn, CAST(mt.aggregate_arg AS VARCHAR(4000)),
                       CAST(me.expression AS VARCHAR(8000))
                  FROM {self.db}.METRIC mt
                  LEFT JOIN {self.db}.METRIC_EXPRESSION me
                       ON me.metric_id = mt.metric_id AND me.dialect = 'TERADATA'
                 WHERE mt.model_id = ? AND mt.metric_name = ?""",
            model_id, metric_name,
        )
        if not r:
            return None
        return MetricRow(
            metric_id=int(r[0]), metric_name=str(r[1]).strip(),
            description=(str(r[2]) if r[2] is not None else None),
            metric_type=(str(r[3]).strip() if r[3] is not None else None),
            primary_dataset_id=(int(r[4]) if r[4] is not None else None),
            base_metric_id=(int(r[5]) if r[5] is not None else None),
            aggregate_fn=(str(r[6]).strip() if r[6] is not None else None),
            aggregate_arg=(str(r[7]) if r[7] is not None else None),
            expression_teradata=(str(r[8]) if r[8] is not None else None),
        )

    def load_metric_by_id(self, metric_id: int) -> Optional[MetricRow]:
        """Helper used by the filtered-metric path. Not part of the
        Protocol but the resolver duck-checks for it."""
        r = self._fetchone(
            f"""SELECT mt.metric_id, mt.metric_name, mt.description, mt.metric_type,
                       mt.primary_dataset_id, mt.base_metric_id,
                       mt.aggregate_fn, CAST(mt.aggregate_arg AS VARCHAR(4000)),
                       CAST(me.expression AS VARCHAR(8000))
                  FROM {self.db}.METRIC mt
                  LEFT JOIN {self.db}.METRIC_EXPRESSION me
                       ON me.metric_id = mt.metric_id AND me.dialect = 'TERADATA'
                 WHERE mt.metric_id = ?""",
            metric_id,
        )
        if not r:
            return None
        return MetricRow(
            metric_id=int(r[0]), metric_name=str(r[1]).strip(),
            description=(str(r[2]) if r[2] is not None else None),
            metric_type=(str(r[3]).strip() if r[3] is not None else None),
            primary_dataset_id=(int(r[4]) if r[4] is not None else None),
            base_metric_id=(int(r[5]) if r[5] is not None else None),
            aggregate_fn=(str(r[6]).strip() if r[6] is not None else None),
            aggregate_arg=(str(r[7]) if r[7] is not None else None),
            expression_teradata=(str(r[8]) if r[8] is not None else None),
        )

    def load_metric_filters(self, metric_id: int) -> List[MetricFilterRow]:
        rows = self._fetchall(
            f"""SELECT mf.filter_ord, mf.field_id, f.dataset_id, d.dataset_name,
                       f.field_name, mf.op, CAST(mf.filter_value AS VARCHAR(500))
                  FROM {self.db}.METRIC_FILTER mf
                  JOIN {self.db}.FIELD f ON f.field_id = mf.field_id
                  JOIN {self.db}.DATASET d ON d.dataset_id = f.dataset_id
                 WHERE mf.metric_id = ?
                 ORDER BY mf.filter_ord""",
            metric_id,
        )
        return [
            MetricFilterRow(
                filter_ord=int(r[0]), field_id=int(r[1]),
                dataset_id=int(r[2]), dataset_name=str(r[3]).strip(),
                field_name=str(r[4]).strip(),
                op=str(r[5]).strip(), filter_value=str(r[6]),
            )
            for r in rows
        ]

    # --- relationships ---

    def load_relationships(self, model_id: int) -> List[RelationshipRow]:
        rows = self._fetchall(
            f"""SELECT r.relationship_id, r.relationship_name,
                       r.from_dataset_id, r.to_dataset_id,
                       r.cardinality, r.role_name
                  FROM {self.db}.RELATIONSHIP r
                  JOIN {self.db}.DATASET df ON df.dataset_id = r.from_dataset_id
                 WHERE df.model_id = ?""",
            model_id,
        )
        return [
            RelationshipRow(
                relationship_id=int(r[0]),
                relationship_name=(str(r[1]).strip() if r[1] is not None else None),
                from_dataset_id=int(r[2]), to_dataset_id=int(r[3]),
                cardinality=(str(r[4]).strip() if r[4] is not None else None),
                role_name=(str(r[5]).strip() if r[5] is not None else None),
            )
            for r in rows
        ]

    def find_relationship_by_role(self, model_id: int,
                                  role_name: str) -> Optional[RelationshipRow]:
        r = self._fetchone(
            f"""SELECT r.relationship_id, r.relationship_name,
                       r.from_dataset_id, r.to_dataset_id,
                       r.cardinality, r.role_name
                  FROM {self.db}.RELATIONSHIP r
                  JOIN {self.db}.DATASET df ON df.dataset_id = r.from_dataset_id
                 WHERE df.model_id = ? AND r.role_name = ?""",
            model_id, role_name,
        )
        if not r:
            return None
        return RelationshipRow(
            relationship_id=int(r[0]),
            relationship_name=(str(r[1]).strip() if r[1] is not None else None),
            from_dataset_id=int(r[2]), to_dataset_id=int(r[3]),
            cardinality=(str(r[4]).strip() if r[4] is not None else None),
            role_name=(str(r[5]).strip() if r[5] is not None else None),
        )

    def load_rel_columns(self, relationship_id: int) -> List[RelColumnRow]:
        rows = self._fetchall(
            f"""SELECT rcm.relationship_id,
                       rcm.from_field_id, ff.field_name,
                       rcm.to_field_id,   tf.field_name,
                       rcm.column_position
                  FROM {self.db}.REL_COLUMN_MAP rcm
                  JOIN {self.db}.FIELD ff ON ff.field_id = rcm.from_field_id
                  JOIN {self.db}.FIELD tf ON tf.field_id = rcm.to_field_id
                 WHERE rcm.relationship_id = ?
                 ORDER BY rcm.column_position""",
            relationship_id,
        )
        return [
            RelColumnRow(
                relationship_id=int(r[0]),
                from_field_id=int(r[1]), from_field_name=str(r[2]).strip(),
                to_field_id=int(r[3]),   to_field_name=str(r[4]).strip(),
                column_position=int(r[5]),
            )
            for r in rows
        ]
