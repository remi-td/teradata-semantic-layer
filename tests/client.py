"""
client.py — typed-JSON wrapper over sp_semantic_request.

Agents are expected to issue semantic requests as JSON. This helper handles
value encoding (string quoting, DATE literals, IN-list wrapping) and calls
the positional stored procedure.

Payload shape (all sections optional unless noted):
    {
      "model":      "tpch_orders",           # required
      "metrics":    ["revenue", "promo_share"],
      "dimensions": ["orders.o_orderpriority",
                     "orders.o_orderdate:MONTH",
                     "customer_nation.n_name"],
      "where": [
        {"field": "lineitem.l_shipdate", "op": ">=", "value": "1995-01-01",
         "type": "date"},
        {"field": "orders.o_orderstatus", "op": "IN", "values": ["O","F"]},
        {"field": "orders.o_orderpriority", "op": "LIKE", "value": "1-%"}
      ],
      "having": [{"metric": "promo_share", "op": ">", "value": 0.1}],
      "sort":   [{"field": "revenue", "direction": "DESC"}],
      "limit":   10,
      "execute": 0
    }

value type inference (when `type` is omitted):
- numbers → raw numeric literal
- strings → 'quoted with single-quote doubling'

Returns the request_result row (dict) after the SP call.
"""

from __future__ import annotations
import json as _json
from typing import Any, Dict, List, Union

def _quote_string(s: str) -> str:
    return "'" + str(s).replace("'", "''") + "'"

def _encode_value(value: Any, type_hint: str | None = None) -> str:
    if type_hint:
        th = type_hint.upper()
        if th == "DATE":
            return "DATE " + _quote_string(str(value))
        if th == "NUMBER":
            return str(value)
        if th == "RAW":
            return str(value)
        # default = STRING
        return _quote_string(str(value))
    # inference
    if isinstance(value, (int, float)):
        return str(value)
    return _quote_string(str(value))

def _encode_in_values(values: List[Any]) -> str:
    return "(" + ",".join(_encode_value(v) for v in values) + ")"

def _build_where(where_items: List[Dict[str, Any]]) -> str:
    parts = []
    for item in where_items or []:
        field = item["field"]
        op    = item["op"]
        if op.upper() == "IN":
            rhs = _encode_in_values(item["values"])
        else:
            rhs = _encode_value(item.get("value"), item.get("type"))
        parts.append(f"{field}|{op}|{rhs}")
    return ";".join(parts)

def _build_having(having_items: List[Dict[str, Any]]) -> str:
    parts = []
    for item in having_items or []:
        metric = item["metric"]
        op     = item["op"]
        value  = item.get("value")
        rhs    = str(value) if isinstance(value, (int, float)) \
                 else _encode_value(value, item.get("type"))
        parts.append(f"{metric}|{op}|{rhs}")
    return ";".join(parts)

def _build_sort(sort_items: List[Dict[str, Any]]) -> str:
    return ",".join(
        f'{s["field"]} {s.get("direction","ASC").upper()}'
        for s in sort_items or []
    )

def translate(payload: Union[str, Dict[str, Any]]) -> Dict[str, Any]:
    """Return the positional args dict {model, metrics, dimensions, ...}."""
    if isinstance(payload, str):
        payload = _json.loads(payload)
    return dict(
        model=payload.get("model", ""),
        metrics=",".join(payload.get("metrics") or []),
        dimensions=",".join(payload.get("dimensions") or []),
        where=_build_where(payload.get("where") or []),
        having=_build_having(payload.get("having") or []),
        sort=_build_sort(payload.get("sort") or []),
        limit=int(payload.get("limit") or 0),
        execute=int(payload.get("execute") or 0),
    )

def compile_from_json(cur, payload: Union[str, Dict[str, Any]]) -> Dict[str, Any]:
    """Translate JSON, call sp_semantic_request, return the OUT-param row."""
    args = translate(payload)
    cur.execute(
        "CALL demo_user.sp_semantic_request(?,?,?,?,?,?,?,?,?,?,?,?)",
        (args["model"], args["metrics"], args["dimensions"],
         args["where"], args["having"], args["sort"], args["limit"],
         None, None, None, None, None),
    )
    r = cur.fetchone()
    if not r:
        return dict(sql=None, is_valid=None, message="no result row",
                    anchor=None, joined=None)
    return dict(sql=r[0],
                is_valid=int(r[1]) if r[1] is not None else None,
                message=r[2], anchor=r[3], joined=r[4],
                translated=args)


if __name__ == "__main__":
    # Self-test via `python3 tests/client.py`
    import os, teradatasql
    payload = {
        "model": "tpch_orders",
        "metrics": ["revenue"],
        "dimensions": ["orders.o_orderdate:MONTH", "customer_nation.n_name"],
        "where": [
            {"field": "lineitem.l_shipdate", "op": ">=", "value": "1995-01-01", "type": "date"},
            {"field": "orders.o_orderstatus", "op": "IN", "values": ["O","F"]}
        ],
        "sort":  [{"field": "revenue", "direction": "DESC"}],
        "limit": 10
    }
    print("translated args:")
    for k, v in translate(payload).items():
        print(f"  {k!r:12} = {v!r}")

    conn = teradatasql.connect(
        host=os.environ.get("TERADATA_HOST",
             "mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com"),
        user=os.environ.get("TERADATA_USER", "demo_user"),
        password=os.environ.get("TERADATA_PASSWORD", "demo_user"))
    cur = conn.cursor()
    result = compile_from_json(cur, payload)
    print("\nResult:")
    print("  is_valid:", result["is_valid"])
    print("  anchor:  ", result["anchor"])
    print("  joined:  ", result["joined"])
    print("  message: ", result["message"])
    print("\nCompiled SQL:\n" + (result["sql"] or "<none>"))
