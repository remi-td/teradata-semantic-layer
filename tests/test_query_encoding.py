"""Value encoding for the query builder — mirrors tests/client.py expectations."""
from __future__ import annotations

import pytest

from semantic_catalog.api.models import QueryFilter, QuerySort
from semantic_catalog.api.query import _pack_where, _pack_having, _pack_sort


def test_numeric_value_unquoted():
    w = [QueryFilter(field="d.f", op=">", value=10)]
    assert _pack_where(w) == "d.f|>|10"


def test_string_value_quoted_and_escaped():
    w = [QueryFilter(field="d.f", op="=", value="O'Brien")]
    assert _pack_where(w) == "d.f|=|'O''Brien'"


def test_date_hint_wraps_with_DATE_literal():
    w = [QueryFilter(field="d.dt", op=">=", value="1995-01-01", type="DATE")]
    assert _pack_where(w) == "d.dt|>=|DATE '1995-01-01'"


def test_in_with_values_produces_tuple():
    w = [QueryFilter(field="o.status", op="IN", values=["O","F"])]
    assert _pack_where(w) == "o.status|IN|('O','F')"


def test_in_requires_values():
    from fastapi import HTTPException
    with pytest.raises(HTTPException):
        _pack_where([QueryFilter(field="o.status", op="IN")])


def test_having_uses_metric_name():
    h = [QueryFilter(metric="revenue", op=">", value=1000, type="NUMBER")]
    assert _pack_having(h) == "revenue|>|1000"


def test_sort_joins_fields_and_direction():
    s = [QuerySort(field="revenue", direction="desc"),
         QuerySort(field="year")]
    assert _pack_sort(s) == "revenue DESC,year ASC"


def test_field_missing_rejected():
    from fastapi import HTTPException
    with pytest.raises(HTTPException):
        _pack_where([QueryFilter(op="=", value="x")])
