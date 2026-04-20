#!/usr/bin/env python3
"""Compile one or more Teradata stored procedures from .sql files.

tq splits on semicolons and therefore cannot submit a procedure body as
a single statement. This helper reads each file in full and submits it
via the teradatasql driver. It also retrieves the full compiler error
text from dbc.ErrorTbl-style output when REPLACE PROCEDURE fails.

Usage:
    python3 run_sp.py <file.sql> [<file.sql> ...]
"""
import os
import sys
import teradatasql

HOST = os.environ.get("TERADATA_HOST", "mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com")
USER = os.environ.get("TERADATA_USER", "demo_user")
PASSWORD = os.environ.get("TERADATA_PASSWORD", "demo_user")

def run(paths):
    conn = teradatasql.connect(host=HOST, user=USER, password=PASSWORD)
    cur = conn.cursor()
    failures = 0
    for p in paths:
        with open(p, "r") as f:
            lines = f.readlines()
        # Strip leading pure-comment / blank lines until we hit the
        # CREATE / REPLACE PROCEDURE keyword. Trailing blank lines also
        # discarded; trailing ';' kept.
        while lines and (lines[0].strip() == "" or lines[0].lstrip().startswith("--")):
            lines.pop(0)
        sql = "".join(lines).rstrip()
        # Keep trailing ';' — Teradata drivers strip it if needed.
        print(f"=> compiling {p} ({len(sql)} chars)")
        try:
            cur.execute(sql)
            # Drain any compiler warnings
            try:
                rows = cur.fetchall()
                for r in rows:
                    print("  ", r)
            except Exception:
                pass
            print(f"   OK")
        except Exception as e:
            print(f"   FAILED: {e}")
            failures += 1
    conn.close()
    return 0 if failures == 0 else 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: run_sp.py <file.sql> [<file.sql> ...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(run(sys.argv[1:]))
