"""Python importer — replaces sp_semantic_import with in-Python FK
resolution and INSERT/UPDATE logic.

Why Python rather than a stored procedure:
  - Shares the CatalogDAO with the compiler (single source of truth for
    catalog reads, even in the write path).
  - Unit-testable without a DB via a FakeCursor fixture.
  - Error handling uses normal Python exceptions instead of
    SQLEXCEPTION/GET DIAGNOSTICS gymnastics.
  - Easy to extend: adding METRIC_FILTER / FIELD_HIERARCHY here is 20 LOC,
    versus 80+ LOC of Teradata SPL.

Contract mirrors the SP for drop-in replacement from the GUI importer
endpoint:
    import_entity(cur, db, model_name, kind, payload) ->
        (status, message, entity_id)

Where status is "OK" | "ERROR" | "SKIP".
"""
from __future__ import annotations

from .parser import ordered_items
from .writer import import_entity, KINDS, ImportError_, synthesize_filtered_expressions

__all__ = [
    "ordered_items",
    "import_entity",
    "synthesize_filtered_expressions",
    "KINDS",
    "ImportError_",
]
