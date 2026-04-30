# Teradata Semantic Catalog

A **Teradata-native semantic layer** that lets AI agents and BI tools
ask business questions against a governed metric + dimension model —
without asking a human to write SQL.

- **Speaks MCP out of the box.** A real Model Context Protocol server
  (Streamable HTTP / JSON-RPC) runs inside the same process as the REST
  API and the GUI. Point Claude Code, Cursor, or any MCP-aware client
  at `/mcp/` (or bridge Claude Desktop via `mcp-remote`) and five
  agent-ready tools surface: `semantic.search`, `semantic.describe`,
  `semantic.compile`, `semantic.execute`, `semantic.export_osi`.
- **Catalog is a schema, not a service.** Metadata lives in ordinary
  Teradata tables and is fully queryable with SQL.
- **Cubes are datasets.** Start with one cube on day one; decompose
  into entities, keys, and relationships as the model matures — never a
  rewrite.
- **The compiler is pure Python.** Resolution, join-graph walk,
  filtered-metric composition, chasm-trap detection, and SQL rendering
  (via `sqlglot`) all happen in-process. No middleware.
- **One-command install.** `semantic-catalog install` deploys every
  catalog object in one shot; the GUI and MCP ship with the package.

---

## Why this, versus alternatives

The semantic layer runs **inside Teradata**, not in front of it. That
means:

- Every metric definition is a row in `SEMANTIC_MODEL` / `METRIC` /
  `METRIC_FILTER`. Version-controlled by DBAs the same way tables are.
- The compiler returns native Teradata SQL with PI-aware joins, not
  pushdown from a generic planner.
- Progressive maturity — a "cube" (flat query with labelled dimensions
  and measures) is a legal first-class dataset. No need for full
  model decomposition up front.

Read [`docs/developer/semantic-catalog-design.md`](docs/developer/semantic-catalog-design.md) for the ontology and
[`docs/developer/sql-compilation-engine-design.md`](docs/developer/sql-compilation-engine-design.md) for the compiler internals.

---

## Quickstart (three commands)

```bash
# 1. Install + point at a Teradata
pip install git+https://github.com/remi-td/teradata-semantic-layer.git
export DATABASE_URI="teradata://user:password@host:1025/demo_user"

# 2. Deploy the catalog + a pre-seeded demo model in one shot
semantic-catalog install --with-sample            # defaults to school_gradebook

# 3. Launch the GUI + REST + MCP server
semantic-catalog serve
# → http://127.0.0.1:8080      (GUI, Swagger at /docs)
# → http://127.0.0.1:8080/mcp/ (MCP Streamable-HTTP endpoint)
```

Open the GUI — the seeded model is visible immediately. The workspace
has four tabs: **Graph**, **Query builder**, **Import**, and **Export**.

Need to verify DB reachability first? `semantic-catalog ping`.

> Prefer a local clone? `git clone https://github.com/remi-td/teradata-semantic-layer.git && cd teradata-semantic-layer && pip install .`. The package is not on PyPI yet — install from git in either case.

### Other example scenarios

```bash
semantic-catalog install-example tpch_physical   # sample data for tpch_orders
semantic-catalog install-example tpch_orders     # Honeydew-style model
semantic-catalog install-example tpch_osi        # OSI-style TPC-H variant
semantic-catalog install-example exec_dashboard  # single pre-canned cube
semantic-catalog install-example school_gradebook # filtered-metrics tour (the --with-sample default)
```

Teardown: `semantic-catalog uninstall-example <name>` or
`semantic-catalog uninstall` to drop every catalog table.

---

## Lite deployment (Teradata-only, no server)

For shops that don't want a Python service running next to their
database: lite mode exposes the catalog through the open-source
[Teradata MCP Server Community
Edition](https://github.com/Teradata/teradata-mcp-server). The catalog
tables and the search/describe macros all live inside Teradata; the CE
server hosts a small custom-tools manifest
(`agentic/lite/semantic_catalog_objects.yml`) that points at them.

```bash
semantic-catalog install                                       # same DDL as full
semantic-catalog import path/to/my_model.yaml                  # one-shot, no daemon
cp agentic/lite/semantic_catalog_objects.yml /path/to/mcp-config-dir/
# edit the manifest: replace 'demo_user' with your catalog database
teradata-mcp-server --config_dir /path/to/mcp-config-dir       # CE picks up *_objects.yml
```

Two tools register: `semantic.search` and `semantic.describe`. An
agent has enough hints to write SQL by hand (metric expressions,
relationships, AI context all surface through `describe`), but **does
not** get compile-time SQL generation, EXPLAIN validation, or
row-level security — those require the full deployment. OSI export is
an offline CLI (`semantic-catalog export <model>`), the same Python
exporter the full deployment exposes via `/api/export/osi`. See
[`agentic/lite/README.md`](agentic/lite/README.md) for the full
trade-off matrix.

Both modes share the same database objects; lite is a packaging choice,
not a fork of the schema.

---

## Agentic skill — plug an AI agent in

A self-contained Claude skill ships under
`agentic/skills/semantic-catalog/SKILL.md`, with a matching
`agentic/.claude-plugin/plugin.json` so the directory is directly
installable as a Claude Code plugin. It teaches an agent how to:

- install the catalog on a fresh Teradata;
- author a semantic model via `/api/import`;
- answer business questions via the five `semantic.*` MCP tools;
- interpret the compiler's structured errors (`AMBIGUOUS_PATH`,
  `CHASM_TRAP`, …).

Install as a Claude Code plugin by pointing at the `agentic/` root, or
copy `agentic/skills/semantic-catalog/` into any other agent's skill
directory.

---

## Configuration

| Env var                  | Required | Purpose                                                                 |
|--------------------------|:--------:|-------------------------------------------------------------------------|
| `DATABASE_URI`           | ✅        | `teradata://user:pw@host[:port]/database[?opts]`                        |
| `SEMANTIC_API_TOKEN`     | ❌ (dev)  | Bearer token required on `/api/*` and `/mcp/*` when set                 |
| `SEMANTIC_MCP_TOKEN`     | ❌        | Legacy alias for `SEMANTIC_API_TOKEN` — kept for deployed configurations |
| `SC_BIND_HOST`           | ❌        | Listening address (default `127.0.0.1`)                                 |
| `SC_BIND_PORT`           | ❌        | Listening port (default `8080`)                                         |
| `SC_CORS_ORIGINS`        | ❌        | Comma-separated CORS allow-list (default `*`)                           |
| `SC_LOG_LEVEL`           | ❌        | uvicorn log level (default `info`)                                      |

`DATABASE_URI` query-string options are forwarded to
`teradatasql.connect()`:

```
DATABASE_URI=teradatasql://ldapuser:pw@host/demo_user?logmech=LDAP&tmode=TERA
```

Legacy `TERADATA_HOST` / `TERADATA_USER` / `TERADATA_PASSWORD`
triad is still honoured if `DATABASE_URI` is absent.

**Security note.** In production always set `SEMANTIC_API_TOKEN` — every
`/api/*` and `/mcp/*` call then requires `Authorization: Bearer <token>`.
When the variable is unset the server is trust-by-localhost (dev
default).

---

## CLI

```
semantic-catalog serve                           # start the web GUI + MCP + REST
semantic-catalog ping                            # verify DB connectivity
semantic-catalog install [--fresh]               # deploy every catalog DDL and macro
semantic-catalog uninstall                       # drop every catalog object
semantic-catalog install-example <name>          # load a bundled scenario
semantic-catalog uninstall-example <name>        # tear it back down
semantic-catalog import <file> [--model NAME]    # one-shot YAML/JSON load (no server)
semantic-catalog export <model> [-o FILE]        # render model as OSI YAML (no server)
semantic-catalog deploy --include <file>...      # low-level escape hatch
```

`install` is idempotent; add `--fresh` to drop everything first.
`deploy` is kept as an escape hatch for ad-hoc SQL files — reach for
`install` / `install-example` first.

---

## REST API

Everything under `/api` is JSON; `/mcp` implements the MCP tool
contract.

| Route                                   | Verb | Purpose                                  |
|-----------------------------------------|------|------------------------------------------|
| `/api/models`                           | GET  | List semantic models                     |
| `/api/models/{name}/tree`               | GET  | Hierarchical catalog                     |
| `/api/models/{name}/graph`              | GET  | Cytoscape nodes+edges                    |
| `/api/search?q=&model=`                 | GET  | Ranked keyword search                    |
| `/api/describe?entity_type=&entity_name=&model=` | GET | Full attribute pack         |
| `/api/query/compile`                    | POST | Generate Teradata SQL for a metric request |
| `/api/query/execute`                    | POST | Compile + execute, return rows           |
| `/api/query/explain`                    | POST | Run EXPLAIN on the compiled SQL (read-only, single statement) |
| `/api/import`                           | POST | Load a semantic model (YAML/JSON)        |
| `/api/import/template`                  | GET  | Minimal example payload                  |
| `/api/export/osi/{model}`               | GET  | Export model as OSI 0.1.x YAML           |
| `/api/health` · `/api/ping`             | GET  | Process liveness · DB connectivity       |
| `/mcp/`                                 | POST | MCP Streamable-HTTP / JSON-RPC transport. Tools: `semantic.search`, `semantic.describe`, `semantic.compile`, `semantic.execute`, `semantic.export_osi`. Hand-curl is awkward — point an MCP client at it. |

Auto-generated OpenAPI at [/docs](http://127.0.0.1:8080/docs).

---

## Architecture

```
┌──────────────────────── Browser ────────────────────────┐
│  index.html · app.js · style.css                        │
│  Cytoscape.js (fcose)  │  plain ES (no build step)      │
└──────────────────────────────┬──────────────────────────┘
                               │  fetch /api/…
┌──────────────────────── FastAPI process ────────────────┐
│  auth.py     — shared bearer-token gate                 │
│  api/        — models/tree/graph/search/describe/       │
│                query/import/export                      │
│  mcp/        — MCP JSON-RPC server (Streamable HTTP)    │
│  compiler/   — pure-Python: resolver, joins, render      │
│  importer/   — pure-Python: YAML → catalog writes        │
│  exporter/   — pure-Python: catalog → OSI YAML           │
│  db.py       — bounded ConnectionPool over teradatasql   │
└──────────────────────────────┬──────────────────────────┘
                               │  teradatasql
┌──────────────────── Teradata Vantage ───────────────────┐
│  SEMANTIC_MODEL / DATASET / FIELD / METRIC / ...         │
│  sp_semantic_search · sp_semantic_describe (macros)      │
└─────────────────────────────────────────────────────────┘
```

- **No ORM, no background worker.** Synchronous teradatasql driver, a
  tiny pool, sqlglot for dialect rendering.
- **No build step.** Frontend is three files — HTML, CSS, ES5+ JS.
- **Transactional import.** Every `POST /api/import` call wraps its
  batch in a single Teradata transaction; any failure rolls back the
  whole load.

See [`docs/developer/sql-compilation-engine-design.md`](docs/developer/sql-compilation-engine-design.md)
for the query-compilation internals and
[`docs/developer/semantic-catalog-design.md`](docs/developer/semantic-catalog-design.md) for
the conceptual ontology.

---

## Import format

YAML or JSON. Any subset of these top-level keys:

```yaml
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
    # Phase-1: filtered rollups of a base metric.
    # base_metric: revenue
    # filters:
    #   - {field: part.p_type, op: LIKE, filter_value: "'PROMO%'"}
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
    members:
      - {ordinal: 1, name: total_revenue, member_type: METRIC, metric: revenue}
      - {ordinal: 2, name: order_date,    member_type: DIMENSION,
         parent_dataset: orders, field: o_orderdate}
ai_context:
  - entity_type: METRIC
    entity_name: revenue
    instructions: "Always additive across time."
    synonyms: [net sales, sales, GMV]
    display_name: Revenue
```

The backend decomposes the document into a topologically ordered stream
of per-entity writes inside a single Teradata transaction. Any error
rolls back the whole batch; `dry_run: true` rolls back unconditionally
and returns a per-item report.

---

## Testing

```bash
# Unit tests (no DB required):
pip install ".[dev]"
pytest

# Plus live smoke tests against a real Teradata:
export DATABASE_URI="teradata://demo_user:demo_user@host/demo_user"
pytest -m ""                # run everything, including `live` marker
```

| File                            | What it covers                                          |
|---------------------------------|---------------------------------------------------------|
| `test_config.py`                | `DATABASE_URI` parsing, legacy fallback                 |
| `test_importer_parsing.py`      | YAML → topological call sequence                        |
| `test_query_encoding.py`        | Filter/sort value encoding                              |
| `test_api_fake.py`              | FastAPI routers against an in-memory fake pool          |
| `test_import_api.py`            | Commit / rollback semantics for the import batch        |
| `test_live_smoke.py`            | End-to-end against a real Teradata (DB-dependent)       |
| `tests/run_tests.py` + `cases/` | YAML-driven regression suite for the compiler           |

`test_live_smoke.py` auto-skips when the DB is unreachable, so
`pytest` on a laptop with no Teradata still passes cleanly.

---

## Branding

UI follows the Teradata visual identity:

- Primary Orange `#FF5F02`, Navy `#00233C`, white space as structure.
- Inter typeface (loaded from Google Fonts); JetBrains Mono for code.
- Logo is the officially provided PNG — never recreated.

---

## License

Apache 2.0. See `LICENSE` (or the declaration in `pyproject.toml` until
the file lands on disk).
