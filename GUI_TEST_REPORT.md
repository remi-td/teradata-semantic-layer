# GUI implementation — test report

Verification of the GUI delivered under `GUI-requirements.md`. Every row
below was executed live against the ClearScape sandbox
(`DATABASE_URI=teradata://demo_user:demo_user@mcp-vikzqtnd0db0nglk...`).

## 1. Package installs

```
$ pip install -e ".[dev]"
Successfully installed semantic-catalog-0.1.0
$ semantic-catalog --help
usage: semantic-catalog [-h] [--log-level LOG_LEVEL] {serve,ping,deploy} ...
```

## 2. CLI reaches the database

```
$ DATABASE_URI=… semantic-catalog ping
opening teradatasql connection to mcp-vikzqtnd0db0nglk…
connected … as DEMO_USER @ 2026-04-17 21:04:06
```

## 3. Import SP deploys

```
$ python3 sql/run_sp.py sql/60_sp_semantic_import.sql
=> compiling sql/60_sp_semantic_import.sql (30131 chars)
   OK
```

## 4. Server boots and serves static frontend

```
$ DATABASE_URI=… SC_BIND_PORT=8766 semantic-catalog serve
Uvicorn running on http://127.0.0.1:8766
```

## 5. Full REST surface — HTTP 200 on every route

| Path                                                          | Status | Body size |
|---------------------------------------------------------------|--------|-----------|
| `/`                                                           | 200    | 9 213 B   |
| `/static/app.js`                                              | 200    | 37 996 B  |
| `/static/style.css`                                           | 200    | 20 596 B  |
| `/static/assets/teradata_logo_rgb_pos.png`                    | 200    | 50 870 B  |
| `/api/health`                                                 | 200    | 114 B     |
| `/api/ping`                                                   | 200    | 69 B      |
| `/api/models`                                                 | 200    | 903 B     |
| `/api/models/tpch_orders/tree`                                | 200    | 8 374 B   |
| `/api/models/tpch_orders/graph` (16 nodes, 18 edges)          | 200    | 5 890 B   |
| `/api/search?q=customer`                                      | 200    | 4 036 B   |
| `/api/describe?entity_type=DATASET&entity_name=lineitem&model=tpch_orders` | 200 | 2 352 B |
| `/api/import/template`                                        | 200    | 495 B     |
| `/api/export/osi/tpch_orders`                                 | 200    | 16 132 B  |

## 6. User story smoke — executed end-to-end

### Story 1 — Business user navigates and drills

- `/api/models` returned 3 seeded models (tpch_osi, tpch_orders,
  exec_dashboard).
- `/api/search?q=revenue` ranked hits (exact metric "revenue" at
  relevance 100, plus promo_revenue, new_customer_revenue, …).
- `/api/describe?entity_type=METRIC&entity_name=revenue` returned
  full attribute pack including expr_teradata, ai_instructions,
  ai_synonyms.

### Story 2 — Data architect inspects the full graph

- Graph endpoint returns nodes by kind: 8 DATASET, 7 METRIC, 1 VIEW for
  tpch_orders. Edges broken down: 10 RELATIONSHIP, 7 METRIC_OF, 1
  VIEW_OF. Cytoscape-ready JSON with sub-kind (CUBE vs TABLE) for
  colour coding.

### Story 3 — Engineer compiles, runs, EXPLAINs

Request:
```json
{"model":"tpch_orders","metrics":["revenue"],
 "dimensions":["orders.o_orderpriority"],
 "sort":[{"field":"revenue","direction":"DESC"}],"limit":5}
```

Response (executed):
```
LOCKING ROW FOR ACCESS
SELECT TOP 5 orders.o_orderpriority AS o_orderpriority,
  SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
FROM demo_user.lineitem AS lineitem
 INNER JOIN demo_user.orders AS orders
   ON lineitem.l_orderkey = orders.o_orderkey
GROUP BY orders.o_orderpriority
ORDER BY revenue DESC;

o_orderpriority | revenue
----------------+-----------
5-LOW           | 260506.17
1-URGENT        | 201962.49
2-HIGH          | 196013.18
4-NOT SPECIFIED | 120837.38
3-MEDIUM        | 111842.73
```

EXPLAIN endpoint returned full plan text (200 OK).

### Story 4 — Engineer imports new definitions from YAML

Dry run of a new metric + its expressions + AI context:
```json
{"total":4, "ok_count":4, "error_count":0, "applied":false, ...}
```

Verified rollback:
```sql
SELECT COUNT(*) FROM METRIC WHERE metric_name='__gui_test_ephemeral__';
-- 0
```

Error path (unknown dataset):
```json
{"ord":1,"kind":"METRIC","status":"ERROR",
 "message":"Unknown primary_dataset \"no_such_dataset\""}
```
`applied=false`, transaction rolled back.

Real apply then clean-up:
```
POST /api/import  → applied: true, error_count: 0
SELECT * FROM METRIC WHERE metric_name='__gui_live_test__'
→ 1 row
-- cleaned up manually in the report script
```

## 7. Export

OSI YAML (`/api/export/osi/tpch_orders`) returns a 16 KB
`version: 0.1.1` document with all 8 datasets, 10 relationships, 7
metrics — AI context inlined.

## 8. Test suite

```
$ DATABASE_URI=… pytest tests/ -q
43 passed, 0 failed in 9.9s
```

Without a DB:
```
$ pytest tests/ -q
37 passed, 6 skipped (live-only)
```

Breakdown:

| File                            | Tests | Notes                                        |
|---------------------------------|------:|----------------------------------------------|
| `test_config.py`                | 7     | DATABASE_URI parsing + legacy env            |
| `test_importer_parsing.py`      | 8     | YAML → topological call order                |
| `test_query_encoding.py`        | 8     | Value / filter encoding                      |
| `test_api_fake.py`              | 9     | FastAPI routers + FakePool                   |
| `test_import_api.py`            | 5     | Commit / rollback semantics                  |
| `test_live_smoke.py`            | 6     | End-to-end, `live` marker, auto-skip         |

## 9. Brand compliance

- Primary Orange `#FF5F02`, Navy `#00233C`, Inter typeface.
- Logo is the officially provided PNG
  (`src/semantic_catalog/static/assets/teradata_logo_rgb_pos.png`).
  Never recreated via SVG or text.
- Sentence case on headlines; active voice throughout UI copy.
- Legend in the graph toolbar distinguishes cube (deep orange) vs table
  datasets, metrics (orange circle), views (dashed lavender), and edge
  colours for join (blue) vs primary (orange dashed) vs view-of (purple
  dotted).

## 10. Known follow-ups (sprint 2 candidates)

- No unit tests for `/api/export/*`; tested ad-hoc only.
- No CSRF / auth — intentional for an on-laptop dev tool.
- The query builder's IN filter UX is text-based; could be upgraded to
  chip-style multi-select.
- `EXPLAIN` runs arbitrary SQL via the driver — could be hardened by
  requiring the SQL to originate from `sp_semantic_request` output.
