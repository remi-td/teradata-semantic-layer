# Teradata Semantic Catalog

A semantic layer that lives **inside** Teradata Vantage, ships with a
lightweight web GUI, and speaks the interchange formats business tools
already know (OSI, MetricFlow).

- **Catalog is a schema, not a service.** Metadata lives in ordinary Teradata
  tables, queryable with SQL.
- **Cubes are datasets.** Start with one cube on day one; decompose into
  entities, keys, and relationships when you're ready — never a rewrite.
- **Fields are atomic.** Dimensions, measures, keys, and join columns are
  all fields in different roles. One field, many roles.
- **The catalog is the engine.** Query compilation, EXPLAIN validation, and
  import/export all run as SQL macros and procedures. No external
  middleware needed.
- **GUI is optional and removable.** A small FastAPI process renders a
  Cytoscape graph over the catalog — delete it and everything still works
  for agents speaking directly to the SQL API.

---

## Quickstart

```bash
# 1. Install
git clone <this repo>
cd semantic-layer
pip install -e ".[dev]"

# 2. Point at a Teradata
export DATABASE_URI="teradata://user:password@host:1025/demo_user"

# 3. Deploy catalog + sample data (one-time)
semantic-catalog deploy --mode split --include 00_drop_all 01_ddl_enums 02_ddl_core 03_ddl_relationships \
                                     04_ddl_metrics 05_ddl_views 06_ddl_metadata 07_comments \
                                     08_collect_stats 09_seed_enums 10_scenario_tpch_osi \
                                     11_scenario_tpch_orders 12_scenario_exec_dashboard \
                                     19_gtt_yaml_tmp 20_export_osi \
                                     32_request_staging 40_sample_tpch_ddl 41_sample_tpch_data \
                                     51_schema_ext 52_chasm_scenario_metrics
# Procedures & macros are submitted one file at a time:
semantic-catalog deploy --mode whole --include 30_sp_semantic_search 31_sp_semantic_describe \
                                                33_sp_semantic_request 60_sp_semantic_import

# 4. Launch the GUI
semantic-catalog serve
# → http://127.0.0.1:8080
```

Open the browser — the first model is loaded automatically. Switch models
from the header dropdown. The workspace has four tabs:

- **Graph** — interactive force-directed view: datasets, metrics (orange
  circles) attached to their primary dataset, joins with cardinality
  labels, semantic views as dashed lavender boxes.
- **Query builder** — pick metrics and dimensions with a type-ahead
  picker, add filters, hit **Compile** to generate Teradata SQL or
  **Compile + Run** to execute and see rows. **EXPLAIN** expands the plan.
- **Import** — paste YAML/JSON in the left pane, click **Validate** for a
  dry run or **Validate + Apply** to commit. Per-entity results appear on
  the right with green / red row accents.
- **Export** — one-click OSI YAML for the whole model.

Click anywhere — a node, a tree item, a search hit — and the right drawer
fills with Overview / Fields / Metrics / SQL / AI context tabs.

---

## Configuration

The process reads a single required env var:

```
DATABASE_URI=teradata://<user>:<password>@<host>[:<port>]/<database>[?<opts>]
```

Query-string options are forwarded to `teradatasql.connect()`:

```
DATABASE_URI=teradatasql://ldapuser:...@host/demo_user?logmech=LDAP&tmode=TERA
```

Legacy fall-back for environments that predate `DATABASE_URI`:

```
TERADATA_HOST=host
TERADATA_USER=user
TERADATA_PASSWORD=pw
TERADATA_DATABASE=demo_user
```

GUI-side knobs (all optional):

| Env var             | Default       | Purpose                               |
|---------------------|---------------|---------------------------------------|
| `SC_BIND_HOST`      | `127.0.0.1`   | Listening address                     |
| `SC_BIND_PORT`      | `8080`        | Listening port                        |
| `SC_CORS_ORIGINS`   | `*`           | Comma-separated CORS allow-list       |
| `SC_LOG_LEVEL`      | `info`        | uvicorn log level                     |

---

## CLI

```
semantic-catalog serve        # start the web GUI
semantic-catalog ping         # verify DB connectivity
semantic-catalog deploy       # deploy bundled .sql files
```

`deploy` ships two modes. `split` breaks a file on `;`+blank-line
boundaries (for plain DDL/DML). `whole` submits the entire file to the
driver (for stored procedure and macro bodies that contain `;` inside
their body).

---

## REST API

The GUI is a thin shell over a REST surface that agents, CI and curl can
all use directly. All routes are under `/api`:

| Route                                        | Verb | Purpose                                         |
|----------------------------------------------|------|-------------------------------------------------|
| `/api/models`                                | GET  | List semantic models                            |
| `/api/models/{name}/tree`                    | GET  | Hierarchical catalog (datasets/metrics/views)   |
| `/api/models/{name}/graph`                   | GET  | Cytoscape-shaped nodes+edges payload            |
| `/api/search?q=&model=`                      | GET  | Ranked keyword search via `m_semantic_search`   |
| `/api/describe?entity_type=&entity_name=&model=` | GET | Full attribute pack via `m_semantic_describe`  |
| `/api/query/compile`                         | POST | Generate Teradata SQL for a metric request      |
| `/api/query/execute`                         | POST | Compile + execute, return rows                  |
| `/api/query/explain`                         | POST | Run `EXPLAIN` on arbitrary SQL                  |
| `/api/import`                                | POST | Parse YAML/JSON and dispatch to `sp_semantic_import` |
| `/api/import/template`                       | GET  | Minimal example payload                         |
| `/api/export/osi/{model}`                    | GET  | Export model as OSI 0.1.x YAML                  |
| `/api/health` · `/api/ping`                  | GET  | Process liveness · DB connectivity              |

Auto-generated Swagger UI at [/docs](http://127.0.0.1:8080/docs).

---

## User stories covered

| # | Story                                                                                     | Where it lives                                    |
|---|-------------------------------------------------------------------------------------------|---------------------------------------------------|
| 1 | As a business user, navigate the catalog, search, drill from concepts to related concepts | Graph tab + left tree + search + right drawer     |
| 2 | As a data architect, visualise the full model graph to find gaps                          | Graph tab (force-directed, colour-coded by kind)  |
| 3 | As an analyst, build a query, EXPLAIN it, run it                                          | Query builder tab                                 |
| 4 | As a data engineer, import new dimensions/metrics from a YAML/JSON text box               | Import tab → `sp_semantic_import`                 |

---

## Architecture

```
┌──────────────────────── Browser ────────────────────────┐
│  index.html · app.js · style.css                        │
│    Cytoscape.js (fcose)  │  plain ES (no build step)    │
└──────────────────────────────┬──────────────────────────┘
                               │  fetch /api/…
┌──────────────────────── FastAPI ────────────────────────┐
│  catalog.py   — models / tree / graph / search / describe
│  query.py     — compile / execute / explain              │
│  importer.py  — YAML → ordered calls → sp_semantic_import│
│  export.py    — OSI YAML projection                      │
│  db.py        — bounded ConnectionPool over teradatasql  │
└──────────────────────────────┬──────────────────────────┘
                               │  teradatasql
┌──────────────────── Teradata Vantage ───────────────────┐
│  SEMANTIC_MODEL / DATASET / FIELD / METRIC / …           │
│  m_semantic_search · m_semantic_describe (macros)        │
│  sp_semantic_request · sp_semantic_import (procs)        │
└─────────────────────────────────────────────────────────┘
```

- **No ORM, no background worker.** Synchronous teradatasql driver, tiny
  pool, all real work happens in SQL.
- **No build step.** Frontend is three files — HTML, CSS, ES5+ JS — loaded
  via CDN for Cytoscape. Runs in any modern browser.
- **Transactional import.** The server wraps the import batch in one
  transaction and commits only if every entity validates; dry-run
  rolls back unconditionally.

See [`sql_compilation_engine_design.md`](./sql_compilation_engine_design.md)
for the query-compilation internals and
[`semantic_catalog_design_v2.md`](./semantic_catalog_design_v2.md) for the
conceptual ontology.

---

## Import format

YAML or JSON, any subset of these top-level keys:

```yaml
model: tpch_orders                      # target model (used for all items below)
models:
  - {name, description, owner_user, owner_group}
datasets:
  - name: customer
    description: ...
    source_table: demo_user.customer    # OR source_query: "SELECT ..."
    granularity: "one row per customer"
    fields:
      - {name, type: A|K, expression, description, label,
         is_dimension, is_time_dimension, data_type, column_name}
fields:                                 # stand-alone fields: must carry `dataset`
  - {dataset, name, ...}
metrics:
  - name: revenue
    primary_dataset: lineitem
    metric_type: SIMPLE | RATIO | CUMULATIVE | DERIVED
    description: ...
    expressions:
      TERADATA: "SUM(l_extendedprice * (1 - l_discount))"
      ANSI_SQL: "SUM(l_extendedprice * (1 - l_discount))"
relationships:
  - name: order_to_customer
    from: orders
    to:   customer
    cardinality: MANY_TO_ONE
    columns:
      - {from_field: o_custkey, to_field: c_custkey, position: 1}
views:
  - name: order_dashboard
    primary_dataset: orders
    timeseries_field: o_orderdate
    members:
      - {ordinal: 1, name: total_revenue, member_type: MEASURE, metric: revenue}
      - {ordinal: 2, name: order_date,    member_type: TIME_DIMENSION,
         parent_dataset: orders, field: o_orderdate}
ai_context:
  - entity_type: METRIC
    entity_name: revenue
    instructions: "Always additive across time."
    synonyms: [net sales, sales, GMV]
    display_name: Revenue
```

The backend decomposes the document into one
`sp_semantic_import(model, kind, payload)` call per entity, in topological
order, inside a single Teradata transaction. Any error rolls back the
whole batch; dry-run rolls back unconditionally and returns a per-item
report.

---

## Export format

- **OSI 0.1.x YAML** — full model projection (datasets, fields,
  relationships, metrics, AI context). See `GET /api/export/osi/{model}`.

---

## Testing

```bash
# Unit tests (no DB required):
pytest

# Plus live smoke tests against a real Teradata:
export DATABASE_URI="teradata://demo_user:demo_user@host/demo_user"
pytest -m ""                # run everything, including `live` marker
```

The test layout:

| File                            | What it covers                                           |
|---------------------------------|----------------------------------------------------------|
| `test_config.py`                | `DATABASE_URI` parsing, legacy fallback                  |
| `test_importer_parsing.py`      | YAML → topological call sequence                         |
| `test_query_encoding.py`        | Filter/sort value encoding for `sp_semantic_request`     |
| `test_api_fake.py`              | FastAPI routers against an in-memory fake pool           |
| `test_import_api.py`            | Commit / rollback semantics for the import batch         |
| `test_live_smoke.py`            | End-to-end against a real Teradata (DB-dependent)        |
| `tests/run_tests.py` + `cases/` | YAML-driven regression suite for `sp_semantic_request`   |

`test_live_smoke.py` auto-skips when the DB is unreachable, so a `pytest`
invocation on a laptop with no Teradata still passes cleanly.

---

## Branding

UI follows the Teradata visual identity:

- Primary Orange `#FF5F02`, Navy `#00233C`, white space as structure.
- Inter typeface (loaded from Google Fonts); JetBrains Mono for code.
- Logo is the officially provided PNG — never recreated.

See `.claude/skills/teradata-brand/SKILL.md` for the full guidelines the
UI follows.

---

## License

Apache 2.0. See `LICENSE`.
