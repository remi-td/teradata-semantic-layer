"""Value encoding for filter right-hand sides.

Centralised here so that both the Python compiler and any legacy
SP-driven path can share the same quoting rules. The encoded strings
are spliced directly into SQL, so the only safe input types are:

    STRING -> 'value' with single-quote doubling
    NUMBER -> str(value)
    DATE   -> DATE 'YYYY-MM-DD'
    RAW    -> str(value)   (caller is responsible for safety)
    IN     -> (v1, v2, ...)  each value encoded per default rules

Never format user-supplied values with f-strings at the call site.
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, List, Optional


def quote_string(s: Any) -> str:
    return "'" + str(s).replace("'", "''") + "'"


def encode_value(value: Any, type_hint: Optional[str] = None) -> str:
    if type_hint:
        th = type_hint.upper()
        if th == "DATE":
            return "DATE " + quote_string(str(value))
        if th == "NUMBER":
            return str(value)
        if th == "RAW":
            return str(value)
        return quote_string(str(value))
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float, Decimal)):
        return str(value)
    return quote_string(str(value))


def encode_in(values: List[Any]) -> str:
    return "(" + ",".join(encode_value(v) for v in values) + ")"
