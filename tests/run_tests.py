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

HOST = os.environ.get("TERADATA_HOST", "mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com")
USER = os.environ.get("TERADATA_USER", "demo_user")
PASS = os.environ.get("TERADATA_PASSWORD", "demo_user")
CASES_DIR = Path(__file__).resolve().parent / "cases"
DEFAULT_REPORT = Path(__file__).resolve().parent.parent / "TEST_RESULTS.md"


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

def call_compile(cur, req):
    cur.execute(
        "CALL demo_user.sp_semantic_request(?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            req.get("model", ""),
            req.get("metrics", ""),
            req.get("dimensions", ""),
            req.get("where", ""),
            req.get("having", ""),
            req.get("sort", ""),
            int(req.get("limit", 0) or 0),
            None, None, None, None, None,
        )
    )
    r = cur.fetchone()
    if not r:
        return dict(sql=None, is_valid=None, message="no result row",
                    anchor=None, joined=None)
    return dict(sql=r[0], is_valid=int(r[1]) if r[1] is not None else None,
                message=r[2], anchor=r[3], joined=r[4])


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

def run_one(cur, c, label_idx):
    cid = c.get("id", f"T{label_idx:02d}")
    title = c.get("title", "")
    print(f"\n### {cid} — {title}\n")
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
        r = call_compile(cur, c.get("request") or {})
    except Exception as e:
        print(f"**sp_semantic_request raised:** `{str(e).splitlines()[0][:200]}`\n")
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
    args = ap.parse_args()

    cases = load_cases(CASES_DIR, args.filter, args.only)
    if not cases:
        print(f"No cases matched in {CASES_DIR}", file=sys.stderr)
        sys.exit(1)

    report_fh = open(args.report, "w")
    sys.stdout = Tee(sys.__stdout__, report_fh)

    print(f"# Test Results — Teradata Semantic Catalog\n")
    print(f"- Run against `{USER}@{HOST}`")
    print(f"- Cases loaded: **{len(cases)}**  ")
    print(f"- Source: `{CASES_DIR}/*.yaml`\n")

    conn = teradatasql.connect(host=HOST, user=USER, password=PASS)
    cur = conn.cursor()

    print("## Case results\n")
    results = []
    for i, c in enumerate(cases, 1):
        try:
            outcome = run_one(cur, c, i)
        except Exception as e:
            traceback.print_exc(file=sys.__stdout__)
            outcome = "HARNESS_ERROR"
        expected = c.get("expected", "PASS")
        agree = "MATCH" if outcome == expected else "MISMATCH"
        results.append((c.get("id", f"T{i:02d}"), c.get("category", ""),
                        c.get("title", "")[:70], expected, outcome, agree,
                        c["__file"]))

    # Summary
    print("\n## Summary\n")
    md_table(
        [(r[0], r[1], r[2], r[3], r[4], r[5], r[6]) for r in results],
        ["id", "category", "title", "expected", "actual", "agreement", "file"],
        max_rows=500, cell_width=80
    )

    from collections import Counter
    print("\n### Outcome distribution\n")
    md_table([[k, v] for k, v in sorted(Counter(r[4] for r in results).items())],
             ["outcome", "count"], max_rows=50)
    print("\n### Expectation agreement\n")
    md_table([[k, v] for k, v in sorted(Counter(r[5] for r in results).items())],
             ["agreement", "count"], max_rows=50)

    mismatches = [r for r in results if r[5] == "MISMATCH"]
    if mismatches:
        print("\n### Mismatches\n")
        md_table([(r[0], r[3], r[4], r[2]) for r in mismatches],
                 ["id", "expected", "actual", "title"], max_rows=100, cell_width=80)

    conn.close()
    print(f"\nReport written to: {args.report}", file=sys.__stdout__)
    report_fh.close()


if __name__ == "__main__":
    main()
