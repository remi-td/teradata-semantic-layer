#!/usr/bin/env python3
"""
run_tests.py — YAML-driven test runner for the Teradata Semantic Catalog.

Usage:
    python3 tests/run_tests.py                  # run every case in tests/cases/*.yaml
    python3 tests/run_tests.py filters          # only cases whose id starts with "filters"
    python3 tests/run_tests.py --only T04       # exact id match
    python3 tests/run_tests.py --report PATH    # write the report somewhere specific

Each YAML file under tests/cases/ is a **category** and contains a list of
cases. Case schema:

    id: short stable identifier (e.g. F4-01)
    title: one-line description
    category: free-form category tag (also used for grouping in the report)
    request:
      model: semantic-model name
      metrics: "metric_a,metric_b"       # or empty string
      dimensions: "alias_or_ds.field[:GRAIN],..."
      where: "alias_or_ds.field|op|value;..."     # optional
      having: "metric|op|value;..."                # optional
      sort: "metric DESC"                          # optional
      limit: integer                                # optional
      execute: 0|1                                  # optional (default 0)
    expected_sql: |
      SELECT ... (reference SQL the data architect considers correct)
    expected: PASS | SEMANTIC_WRONG | RUNTIME_ERROR | COMPILE_REJECTED | NOT_SUPPORTED
    notes: free-form explanation

The runner classifies each case as:

- PASS             — compiled, ran, and rows match reference.
- SEMANTIC_WRONG   — compiled and ran, but rows differ from reference
                     (or the compiler returned is_valid=0 on a semantic warning).
- RUNTIME_ERROR    — compiled SQL failed at execute time.
- COMPILE_REJECTED — sp_semantic_request set is_valid=0 with a clear error.
- NOT_SUPPORTED    — no SQL produced.

Rows are compared **column-order-independent** and cells are normalised
(Decimal/float rounded to 2dp, trailing CHAR(n) space stripped).
"""
import os
import sys
import io
import argparse
import textwrap
import traceback
import glob
from decimal import Decimal
from pathlib import Path

import yaml
import teradatasql

# Ensure src/ is importable so we can exercise the Python compiler.
_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "src"))

from semantic_catalog.compiler.request import (  # noqa: E402
    CompileFilter as QueryFilter,
    CompileRequest as QueryRequest,
    CompileSort as QuerySort,
)
from semantic_catalog.compiler import DbCatalog, compile as py_compile, render  # noqa: E402
from semantic_catalog.compiler.errors import CompileError  # noqa: E402

HOST = os.environ.get("TERADATA_HOST", "mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com")
USER = os.environ.get("TERADATA_USER", "demo_user")
PASS = os.environ.get("TERADATA_PASSWORD", "demo_user")
CATALOG_DB = os.environ.get("CATALOG_DB", "demo_user")
CASES_DIR = Path(__file__).resolve().parent / "cases"
DEFAULT_REPORT = Path(__file__).resolve().parent.parent / "test-reports" / "test-results.md"


# ---------------------------------------------------------------- output

class Tee(io.TextIOBase):
    def __init__(self, *streams):
        self.streams = list(streams)
    def write(self, s):
        for st in self.streams:
            try: st.write(s)
            except Exception: pass
        return len(s)
    def flush(self):
        for st in self.streams:
            try: st.flush()
            except Exception: pass


def md_table(rows, headers, max_rows=15, cell_width=60):
    if not rows:
        print("_(no rows)_\n"); return
    def cell(x):
        if x is None: return ""
        if isinstance(x, Decimal): return f"{float(x):.4f}".rstrip("0").rstrip(".")
        if isinstance(x, float):   return f"{x:.4f}".rstrip("0").rstrip(".")
        s = str(x)
        if len(s) > cell_width: s = s[:cell_width-3] + "..."
        return s.replace("|", "\\|").replace("\n", " ")
    print("| " + " | ".join(headers) + " |")
    print("| " + " | ".join(["---"] * len(headers)) + " |")
    for r in rows[:max_rows]:
        print("| " + " | ".join(cell(c) for c in r) + " |")
    if len(rows) > max_rows:
        print(f"| … and {len(rows)-max_rows} more rows |" + "" * (len(headers) - 1))
    print()


def code_sql(sql, label="sql"):
    print(f"```{label}")
    print(sql.rstrip())
    print("```\n")


# ---------------------------------------------------------------- row compare

def _norm(v):
    if v is None: return None
    if isinstance(v, Decimal): return round(v, 2)
    if isinstance(v, float):   return round(v, 2)
    if isinstance(v, str):     return v.rstrip()
    return v

def _row_as_fset(cols, row):
    seen, keys = {}, []
    for c in cols:
        if c in seen:
            seen[c] += 1
            keys.append(f"{c}#{seen[c]}")
        else:
            seen[c] = 0
            keys.append(c)
    return frozenset((k, _norm(v)) for k, v in zip(keys, row))

def rows_equal(cols_a, a, cols_b, b):
    from collections import Counter
    return Counter(_row_as_fset(cols_a, r) for r in a) == \
           Counter(_row_as_fset(cols_b, r) for r in b)


# ---------------------------------------------------------------- DB ops

# The legacy ``call_compile`` (SP path) was removed in v0.4 together
# with ``sp_semantic_request``. The Python compiler is the only engine
# the runner knows about now.


# ------- Python compiler path ----------------------------------------

def _parse_where_str(s: str) -> list:
    out = []
    for part in (s or "").split(";"):
        part = part.strip()
        if not part:
            continue
        bits = part.split("|")
        if len(bits) != 3:
            continue
        field, op, rhs = bits[0].strip(), bits[1].strip(), bits[2].strip()
        out.append(QueryFilter(field=field, op=op, value=rhs, type="RAW"))
    return out


def _parse_having_str(s: str) -> list:
    out = []
    for part in (s or "").split(";"):
        part = part.strip()
        if not part:
            continue
        bits = part.split("|")
        if len(bits) != 3:
            continue
        metric, op, rhs = bits[0].strip(), bits[1].strip(), bits[2].strip()
        out.append(QueryFilter(metric=metric, op=op, value=rhs, type="RAW"))
    return out


def _parse_sort_str(s: str) -> list:
    out = []
    for part in (s or "").split(","):
        part = part.strip()
        if not part:
            continue
        bits = part.split(None, 1)
        if len(bits) == 1:
            out.append(QuerySort(field=bits[0], direction="ASC"))
        else:
            out.append(QuerySort(field=bits[0], direction=bits[1].upper()))
    return out


def _request_from_yaml(req: dict) -> QueryRequest:
    """Convert the YAML SP-packed request into a Pydantic QueryRequest."""
    return QueryRequest(
        model=req.get("model", ""),
        metrics=[m.strip() for m in str(req.get("metrics", "") or "").split(",") if m.strip()],
        dimensions=[d.strip() for d in str(req.get("dimensions", "") or "").split(",") if d.strip()],
        where=_parse_where_str(str(req.get("where", "") or "")),
        having=_parse_having_str(str(req.get("having", "") or "")),
        sort=_parse_sort_str(str(req.get("sort", "") or "")),
        limit=int(req.get("limit", 0) or 0),
    )


def call_compile_python(cur, req):
    """Python compiler path — mirrors the SP's return shape for the runner."""
    catalog = DbCatalog(cur, catalog_db=CATALOG_DB)
    try:
        qr = _request_from_yaml(req)
    except Exception as e:
        return dict(sql=None, is_valid=0, message=f"bad request: {e}",
                    anchor=None, joined=None)
    try:
        plan = py_compile(qr, catalog)
    except CompileError as e:
        return dict(sql=None, is_valid=0, message=f"{e.code}: {e.message}",
                    anchor=None, joined=None)
    except Exception as e:
        return dict(sql=None, is_valid=0, message=f"python compile crashed: {e}",
                    anchor=None, joined=None)

    sql = render(plan)
    is_valid = 1
    message = plan.chasm_warning or ""
    if plan.unresolved:
        is_valid = 0
        message = (f"Could not resolve join path for datasets: "
                   f"{', '.join(plan.unresolved)}")
    elif plan.chasm_warning:
        is_valid = 0
    return dict(
        sql=sql, is_valid=is_valid, message=message,
        anchor=plan.anchor.dataset_name if plan.anchor else None,
        joined=(", ".join(plan.joined_datasets) if plan.joined_datasets else None),
    )


def compile_for_engine(engine: str, cur, req):
    if engine != "python":
        raise ValueError(
            f"engine={engine!r} is no longer supported; the SPL compiler was "
            f"retired in v0.4. Pass --engine python (default)."
        )
    return call_compile_python(cur, req)


def run_sql(cur, sql):
    cur.execute(sql)
    try:
        cols = [d[0] for d in cur.description]
    except Exception:
        return [], []
    return cols, cur.fetchmany(500)


# ---------------------------------------------------------------- loader

def load_cases(cases_dir, name_filter=None, only=None):
    cases = []
    for p in sorted(cases_dir.glob("*.yaml")):
        with open(p) as f:
            doc = yaml.safe_load(f)
        if not doc: continue
        for c in doc.get("cases", []):
            c["__file"] = p.name
            if only and c.get("id") != only: continue
            if name_filter and name_filter not in (
                c.get("id", ""), c.get("category", ""), p.stem
            ):
                if name_filter not in c.get("id", "") \
                   and name_filter not in c.get("category", "") \
                   and name_filter not in p.stem:
                    continue
            cases.append(c)
    return cases


# ---------------------------------------------------------------- runner

def run_one(cur, c, label_idx, engine="python"):
    cid = c.get("id", f"T{label_idx:02d}")
    title = c.get("title", "")
    print(f"\n### {cid} — {title} _(engine={engine})_\n")
    print(f"**Category:** {c.get('category','')}  ")
    print(f"**Source:** `{c['__file']}`  ")
    print(f"**Expected outcome:** `{c.get('expected','PASS')}`  ")
    if c.get("notes"):
        print(f"**Notes:** {c['notes']}")
    print()

    print("**Request:**")
    for k, v in (c.get("request") or {}).items():
        print(f"- `{k}` = `{v!r}`")
    print()

    # Compile
    try:
        r = compile_for_engine(engine, cur, c.get("request") or {})
    except Exception as e:
        print(f"**compile ({engine}) raised:** `{str(e).splitlines()[0][:200]}`\n")
        return "COMPILE_ERROR"

    print(f"**is_valid:** `{r['is_valid']}` | **anchor:** `{r['anchor']}` | **joined:** `{r['joined']}`")
    if r["message"]:
        print(f"**validation_message:** `{r['message']}`")
    print()

    if not r["sql"]:
        print("_(no SQL produced)_\n")
        return "NOT_SUPPORTED"

    print("**Compiled SQL:**")
    code_sql(r["sql"])

    if r["is_valid"] == 0:
        print(f"**Outcome:** COMPILE_REJECTED — `{r['message']}`\n")
        return "COMPILE_REJECTED"

    # Execute compiled
    try:
        cc, cr = run_sql(cur, r["sql"])
    except Exception as e:
        err_line = str(e).splitlines()[0][:180]
        print(f"**Runtime error on compiled SQL:** `{err_line}`\n")
        print("**Outcome:** RUNTIME_ERROR\n")
        return "RUNTIME_ERROR"

    print("**Compiled-SQL results:**")
    md_table(cr, cc)

    ref_sql = c.get("expected_sql")
    if ref_sql:
        # Reference SQL is authored with the placeholder schema 'demo_user';
        # substitute the active CATALOG_DB so it runs against whichever deploy
        # we are testing (same convention as the CLI's _render_sql).
        import re as _re
        ref_sql = _re.sub(r"\bdemo_user\b", CATALOG_DB, ref_sql)
        print("**Reference SQL:**")
        code_sql(textwrap.dedent(ref_sql).strip())
        try:
            rc, rr = run_sql(cur, textwrap.dedent(ref_sql))
        except Exception as e:
            print(f"**Reference SQL failed:** `{str(e).splitlines()[0][:200]}`\n")
            return "REFERENCE_ERROR"
        print("**Reference results:**")
        md_table(rr, rc)

        if rows_equal(cc, cr, rc, rr):
            print("**Outcome:** PASS — rows match reference.\n")
            return "PASS"
        print(f"**Outcome:** SEMANTIC_WRONG — rows differ "
              f"(compiled {len(cr)}, reference {len(rr)}).\n")
        from collections import Counter
        ca = Counter(_row_as_fset(cc, x) for x in cr)
        cb = Counter(_row_as_fset(rc, x) for x in rr)
        only_c = [x for x, n in (ca - cb).items()][:3]
        only_r = [x for x, n in (cb - ca).items()][:3]
        if only_c:
            print("_Rows in compiled but not reference (up to 3):_")
            for x in only_c: print(f"- `{dict(x)}`")
        if only_r:
            print("_Rows in reference but not compiled (up to 3):_")
            for x in only_r: print(f"- `{dict(x)}`")
        print()
        return "SEMANTIC_WRONG"

    print("_(no reference SQL — outcome judged structurally)_\n")
    return "STRUCTURAL_PASS"


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("filter", nargs="?", default=None,
                    help="substring filter on id/category/file")
    ap.add_argument("--only", default=None, help="exact id match")
    ap.add_argument("--report", default=str(DEFAULT_REPORT), help="report path")
    ap.add_argument("--engine", default="python", choices=("python",),
                    help="compile engine; 'python' is the only option since v0.4")
    args = ap.parse_args()

    cases = load_cases(CASES_DIR, args.filter, args.only)
    if not cases:
        print(f"No cases matched in {CASES_DIR}", file=sys.stderr)
        sys.exit(1)

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_fh = open(report_path, "w")
    sys.stdout = Tee(sys.__stdout__, report_fh)

    engines = [args.engine]

    print(f"# Test Results — Teradata Semantic Catalog\n")
    print(f"- Run against `{USER}@{HOST}`")
    print(f"- Cases loaded: **{len(cases)}** × {len(engines)} engine(s)  ")
    print(f"- Engines: {', '.join(engines)}")
    print(f"- Source: `{CASES_DIR}/*.yaml`\n")

    conn = teradatasql.connect(host=HOST, user=USER, password=PASS)
    cur = conn.cursor()

    print("## Case results\n")
    results = []
    for eng in engines:
        for i, c in enumerate(cases, 1):
            try:
                outcome = run_one(cur, c, i, engine=eng)
            except Exception:
                traceback.print_exc(file=sys.__stdout__)
                outcome = "HARNESS_ERROR"
            expected = c.get("expected", "PASS")
            agree = "MATCH" if outcome == expected else "MISMATCH"
            results.append((c.get("id", f"T{i:02d}"), eng, c.get("category", ""),
                            c.get("title", "")[:70], expected, outcome, agree,
                            c["__file"]))

    # Summary
    print("\n## Summary\n")
    md_table(
        results,
        ["id", "engine", "category", "title", "expected", "actual",
         "agreement", "file"],
        max_rows=500, cell_width=80,
    )

    from collections import Counter
    print("\n### Outcome distribution (by engine)\n")
    distribution = Counter((r[1], r[5]) for r in results)
    md_table([[k[0], k[1], v] for k, v in sorted(distribution.items())],
             ["engine", "outcome", "count"], max_rows=50)
    print("\n### Expectation agreement (by engine)\n")
    agree_dist = Counter((r[1], r[6]) for r in results)
    md_table([[k[0], k[1], v] for k, v in sorted(agree_dist.items())],
             ["engine", "agreement", "count"], max_rows=50)

    # Parity view: compare SP vs Python outcomes for the same case id
    if len(engines) == 2:
        print("\n### Engine parity (SP vs Python)\n")
        by_id = {}
        for r in results:
            by_id.setdefault(r[0], {})[r[1]] = r[5]
        rows = []
        for cid, per_eng in sorted(by_id.items()):
            sp = per_eng.get("sql", "-")
            py = per_eng.get("python", "-")
            flag = "=" if sp == py else "≠"
            rows.append([cid, sp, py, flag])
        md_table(rows, ["id", "sql", "python", "match"],
                 max_rows=500, cell_width=40)

    mismatches = [r for r in results if r[6] == "MISMATCH"]
    if mismatches:
        print("\n### Mismatches\n")
        md_table([(r[0], r[1], r[4], r[5], r[3]) for r in mismatches],
                 ["id", "engine", "expected", "actual", "title"],
                 max_rows=200, cell_width=80)

    conn.close()
    print(f"\nReport written to: {args.report}", file=sys.__stdout__)
    report_fh.close()


if __name__ == "__main__":
    main()
