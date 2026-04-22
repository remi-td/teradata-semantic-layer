"""Value encoding for filter right-hand sides.

Pre-v0.4 this file exercised the packed-string wire format used by the
stored-procedure compiler (``sp_semantic_request``). That path has been
removed; the Python compiler now calls ``compiler.encoding.encode_value``
and ``resolver._encode_filter_rhs`` directly.

The tests below cover:

    - ``encode_value`` quoting rules across STRING / NUMBER / DATE / RAW
    - ``encode_in`` tuple shape
    - The ``_encode_filter_rhs`` RAW gate — conservative regex allow-list
"""
from __future__ import annotations

import pytest

from semantic_catalog.compiler.encoding import encode_in, encode_value
from semantic_catalog.compiler.errors import CompileError
from semantic_catalog.compiler.request import CompileFilter
from semantic_catalog.compiler.resolver import _encode_filter_rhs


# ----------- encode_value ------------

def test_numeric_value_unquoted():
    assert encode_value(10) == "10"


def test_string_value_quoted_and_escaped():
    assert encode_value("O'Brien") == "'O''Brien'"


def test_date_hint_wraps_with_DATE_literal():
    assert encode_value("1995-01-01", "DATE") == "DATE '1995-01-01'"


def test_number_hint_does_not_quote():
    assert encode_value("1000", "NUMBER") == "1000"


def test_raw_hint_returns_verbatim():
    assert encode_value("CURRENT_DATE", "RAW") == "CURRENT_DATE"


def test_boolean_encoded_as_0_or_1():
    assert encode_value(True) == "1"
    assert encode_value(False) == "0"


# ----------- encode_in ---------------

def test_in_with_values_produces_tuple():
    assert encode_in(["O", "F"]) == "('O','F')"


def test_in_with_numbers():
    assert encode_in([1, 2, 3]) == "(1,2,3)"


# ----------- _encode_filter_rhs : op allow-list -----

def test_unknown_op_rejected():
    with pytest.raises(CompileError):
        _encode_filter_rhs(CompileFilter(field="d.f", op=";DROP TABLE x--", value=1))


def test_in_without_values_rejected():
    with pytest.raises(CompileError):
        _encode_filter_rhs(CompileFilter(field="o.status", op="IN"))


# ----------- _encode_filter_rhs : RAW gate ----------

def test_raw_rejects_semicolon():
    with pytest.raises(CompileError):
        _encode_filter_rhs(CompileFilter(
            field="d.dt", op="=", type="RAW",
            value="DATE '2026-01-01'; DROP TABLE x",
        ))


def test_raw_rejects_sql_comment():
    with pytest.raises(CompileError):
        _encode_filter_rhs(CompileFilter(
            field="d.dt", op="=", type="RAW",
            value="'x' -- comment",
        ))


def test_raw_accepts_date_literal():
    out = _encode_filter_rhs(CompileFilter(
        field="d.dt", op="=", type="RAW", value="DATE '2026-03-31'",
    ))
    assert out == "DATE '2026-03-31'"


def test_raw_accepts_between_date_range():
    out = _encode_filter_rhs(CompileFilter(
        field="d.dt", op="BETWEEN", type="RAW",
        value="DATE '2026-01-01' AND DATE '2026-03-31'",
    ))
    assert out == "DATE '2026-01-01' AND DATE '2026-03-31'"


def test_raw_in_tuple_accepted():
    out = _encode_filter_rhs(CompileFilter(
        field="x.code", op="IN", type="RAW",
        value="('A','B','C')",
    ))
    assert out == "('A','B','C')"
