# Getting Started

This guide walks from a fresh clone to your first compiled query in about 10 minutes. It assumes a reachable Teradata Vantage instance (ClearScape, on-prem, or your own sandbox).

> Reading pace: if you just want to copy-paste and skip explanation, follow the fenced blocks. The narrative is sized for first-time readers.

---

## 1. Prerequisites

- Python 3.9 or newer
- A Teradata Vantage you can log into with a user that can `CREATE` tables
- (Optional) `git` and ~50 MB of disk

---

## 2. Install

```bash
git clone <this repo>
cd semantic-layer
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

`pip install -e .` registers the package in editable mode and installs the `semantic-catalog` CLI on your PATH.

---

## 3. Point at your Teradata

The server reads a single environment variable:

```bash
export DATABASE_URI="teradata://<user>:<pass>@<host>:1025/<database>"
```

`<database>` is the **catalog schema** — where the semantic catalog lives. For a clean install, pick a fresh database such as `sem_engine`.

Verify connectivity:

```bash
semantic-catalog ping
```

Prints `OK` on success, an error on failure.

---

## 4. Deploy the catalog

One command brings up every catalog table, the Teradata-side search / describe macros, and a handful of sample scenarios:

```bash
semantic-catalog install
```

The install prints each SQL file as it executes and reports a final row count per table. Expect ~30 seconds against a warm Teradata.

Want a clean slate? Add `--fresh` to drop every catalog object first.

---

## 5. Load example data (optional but recommended)

```bash
semantic-catalog install-example school_gradebook
semantic-catalog install-example tpch_orders
```

Each example ships a tiny physical schema plus the semantic model registration. The gradebook is 5 students × 35 assessments — small enough to eyeball individual rows, large enough to exercise filters, joins, and role-playing.

---

## 6. Launch the server

```bash
semantic-catalog serve
# → http://127.0.0.1:8080
```

The GUI opens on `/`. The API is at `/api/*`, MCP tools at `/mcp/*`, OpenAPI spec at `/docs`.

---

## 7. Your first compiled query

The compile endpoint takes a structured request and returns the SQL that would run. Try a simple metric + dimension:

```bash
curl -s http://127.0.0.1:8080/api/query/compile \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "school_gradebook",
    "metrics": ["score_avg"],
    "dimensions": ["student.major"]
  }' | jq .
```

Expect a response like:

```json
{
  "compiled_sql": "LOCKING ROW FOR ACCESS\nSELECT\n  student.major AS major,\n  AVG(assessment.score) AS score_avg\nFROM sem_engine.gb_assessment AS assessment\nINNER JOIN sem_engine.gb_student AS student ON assessment.student_id = student.student_id\nGROUP BY student.major",
  "is_valid": 1,
  "validation_message": null,
  "anchor_dataset": "assessment",
  "joined_datasets": "assessment, student AS student",
  "execution": null
}
```

To run it end-to-end and get rows back, use `/api/query/execute` instead.

The default engine is the **Python compiler** (v0.3+). To compare against the legacy stored procedure, append `?engine=sql`:

```bash
curl -s 'http://127.0.0.1:8080/api/query/compile?engine=sql' -d '{...}'
```

The legacy path emits a `[DEPRECATED engine=sql; use engine=python]` marker in the `validation_message` and is scheduled for removal in v0.4.

---

## 8. A filtered metric

Filtered metrics are base metrics rolled up with extra predicates. The gradebook model ships `exam_score_avg` as a filtered variant of `score_avg`:

```bash
curl -s http://127.0.0.1:8080/api/query/compile \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "school_gradebook",
    "metrics": ["score_avg", "exam_score_avg"],
    "dimensions": ["student.major"]
  }' | jq -r '.compiled_sql'
```

The compiler emits a single `SELECT` with `AVG(...)` for `score_avg` and `AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END)` for the filtered variant — no joins duplicated, no rows inflated.

---

## 9. A composed metric (Phase 2)

Metric expressions may reference other metrics via the `${name}` placeholder:

```yaml
metrics:
  - name: margin
    metric_type: RATIO
    primary_dataset: lineitem
    expressions:
      TERADATA: "${revenue} / ${cost}"
```

The compiler substitutes `${revenue}` with the revenue metric's composed SQL, `${cost}` with cost's, wraps each in parens for precedence, and unifies the grain. Cycles and cross-grain compositions are rejected at compile time.

Import the YAML via the GUI's **Import** tab, or POST it:

```bash
curl -s http://127.0.0.1:8080/api/import \
  -H 'Content-Type: application/json' \
  -d '{"model": "tpch_orders", "text": "<your yaml>", "dry_run": false}' | jq .
```

---

## 10. MCP tools

Agents speak to the catalog through five MCP tools, served over the
standard MCP **Streamable HTTP** (JSON-RPC) transport at `/mcp/`. Wire
an MCP client (Claude Code / Cursor / Continue / Claude Desktop via
`mcp-remote`) and the five `semantic.*` tools surface automatically —
see the project README for client-specific config.

For shell pipelines, the same operations exist as plain REST under
`/api/*`:

```bash
# Search (REST)
curl -s -G --data-urlencode 'q=revenue' http://127.0.0.1:8080/api/search | jq .

# Compile (REST)
curl -s -X POST http://127.0.0.1:8080/api/query/compile \
  -H 'Content-Type: application/json' \
  -d '{"model": "tpch_orders", "metrics": ["revenue"]}'
```

Protect the MCP endpoints in production with a bearer token:

```bash
export SEMANTIC_API_TOKEN="s0m3-very-long-random-string"
semantic-catalog serve
```

Clients must then send `Authorization: Bearer <token>` on every
`/mcp/*` and `/api/*` request.

---

## Where next

- **[Server Guide](server-guide.md)** — deployment, configuration, scaling, MCP integration, troubleshooting.
- **[Design Guidelines](design-guidelines.md)** — the catalog's patterns, anti-patterns, and not-yet-supported features.
- **Design document** — [`developer/semantic-catalog-design.md`](developer/semantic-catalog-design.md).
- **Test suite** — `tests/run_tests.py --engine both` writes its report to `test-reports/test-results.md` (gitignored). Pass `--report PATH` to override.
