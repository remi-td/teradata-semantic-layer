"""YAML/JSON → ordered (kind, payload) stream.

Extracted from ``api/importer.py`` so it can be tested in isolation.
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple


def _norm_bool(v: Any) -> int:
    if v is None:
        return 0
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        return 1 if int(v) else 0
    s = str(v).strip().lower()
    return 1 if s in ("1", "true", "yes", "y", "t") else 0


def _payload_for(kind: str, raw: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(raw)
    for b in ("is_dimension", "is_time_dimension",
              "is_additive", "is_certified", "is_public"):
        if b in out:
            out[b] = _norm_bool(out[b])
    return out


def ordered_items(doc: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    """Flatten a YAML document into a topologically ordered stream."""
    if doc is None:
        return []
    if not isinstance(doc, dict):
        raise ValueError("Import payload must be a mapping at the top level")

    ordered: List[Tuple[str, Dict[str, Any]]] = []

    for m in (doc.get("models") or []):
        ordered.append(("MODEL", _payload_for("MODEL", m)))

    for d in (doc.get("datasets") or []):
        ordered.append(("DATASET", _payload_for("DATASET", d)))
        for f in (d.get("fields") or []):
            f2 = dict(f)
            f2.setdefault("dataset", d.get("name"))
            ordered.append(("FIELD", _payload_for("FIELD", f2)))

    for f in (doc.get("fields") or []):
        ordered.append(("FIELD", _payload_for("FIELD", f)))

    for m in (doc.get("metrics") or []):
        ordered.append(("METRIC", _payload_for("METRIC", m)))
        exprs = m.get("expressions") or {}
        if isinstance(exprs, dict):
            for dialect, expr in exprs.items():
                ordered.append(("METRIC_EXPR", {
                    "metric": m.get("name"),
                    "dialect": str(dialect).upper(),
                    "expression": expr,
                }))
        elif isinstance(exprs, list):
            for e in exprs:
                ordered.append(("METRIC_EXPR", {
                    "metric": m.get("name"),
                    "dialect": str(e.get("dialect", "TERADATA")).upper(),
                    "expression": e.get("expression"),
                }))
        for flt in (m.get("filters") or []):
            f2 = dict(flt)
            f2.setdefault("metric", m.get("name"))
            ordered.append(("METRIC_FILTER", f2))

    for e in (doc.get("metric_expressions") or []):
        ordered.append(("METRIC_EXPR", _payload_for("METRIC_EXPR", e)))

    for flt in (doc.get("metric_filters") or []):
        ordered.append(("METRIC_FILTER", _payload_for("METRIC_FILTER", flt)))

    for r in (doc.get("relationships") or []):
        ordered.append(("RELATIONSHIP", _payload_for("RELATIONSHIP", r)))
        for col in (r.get("columns") or []):
            c2 = dict(col)
            c2.setdefault("relationship", r.get("name"))
            c2.setdefault("from_dataset", r.get("from"))
            c2.setdefault("to_dataset", r.get("to"))
            ordered.append(("REL_COL", _payload_for("REL_COL", c2)))

    for v in (doc.get("views") or []):
        ordered.append(("VIEW", _payload_for("VIEW", v)))
        for mem in (v.get("members") or []):
            m2 = dict(mem)
            m2.setdefault("view", v.get("name"))
            ordered.append(("VIEW_MEMBER", _payload_for("VIEW_MEMBER", m2)))

    for m in (doc.get("view_members") or []):
        ordered.append(("VIEW_MEMBER", _payload_for("VIEW_MEMBER", m)))

    for h in (doc.get("hierarchies") or []):
        ordered.append(("HIERARCHY", _payload_for("HIERARCHY", h)))
        for lvl in (h.get("levels") or []):
            l2 = dict(lvl)
            l2.setdefault("hierarchy", h.get("name"))
            ordered.append(("HIERARCHY_LEVEL", l2))

    for ac in (doc.get("ai_context") or []):
        ordered.append(("AI_CONTEXT", _payload_for("AI_CONTEXT", ac)))

    return ordered
