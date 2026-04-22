# Server Guide

Operational guide for the `semantic-catalog serve` FastAPI process. Covers configuration, deployment, MCP integration, engine selection, and troubleshooting.

---

## Architecture at a glance

```
   ┌──────────────┐     ┌─────────────────────────────────────────┐
   │  Browser     │     │  FastAPI process (semantic-catalog      │
   │  (GUI)       │─────┼─  serve)                                │
   │  / MCP agent │     │                                         │
   └──────────────┘     │  /static/*    single-page GUI           │
                        │  /api/*       REST endpoints            │
                        │  /mcp/*       MCP tools                 │
                        │                                         │
                        │  compiler/    Python SQL compiler       │
                        │               (sqlglot, Teradata dialect)│
                        │  importer/    in-proc catalog writes    │
                        │  exporter/    OSI YAML generation       │
                        │               │                         │
                        └───────────────┼─────────────────────────┘
                                        │
                                        ▼
                        ┌──────────────────────────┐
                        │   Teradata Vantage       │
                        │                          │
                        │   demo_user (or          │
                        │   sem_engine) schema     │
                        │   — catalog tables       │
                        │   — sp_semantic_search   │
                        │   — sp_semantic_describe │
                        └──────────────────────────┘
```

Core properties:

- **Stateless**. The FastAPI process caches nothing across requests. All state lives in Teradata tables. You can run as many replicas as your firewall allows.
- **One database round-trip per conceptual lookup** in the compiler — Teradata's indexes do the heavy lifting.
- **No cold start cost**. The first request opens a DB connection; subsequent requests reuse the pooled connection.

---

## Configuration

All config comes from environment variables. The CLI reads them on startup.

| Variable                | Default                     | Purpose                                                |
|-------------------------|-----------------------------|--------------------------------------------------------|
| `DATABASE_URI`          | *(required)*                | `teradata://user:pass@host:1025/catalog_db`            |
| `TERADATA_HOST`         |                             | Alternative to `DATABASE_URI` (split form)             |
| `TERADATA_USER`         |                             |                                                        |
| `TERADATA_PASSWORD`     |                             |                                                        |
| `TERADATA_LOGMECH`      | `TD2`                       | `TD2` \| `LDAP` \| `KRB5` \| `TDNEGO`                  |
| `CATALOG_DB`            | parsed from `DATABASE_URI`  | Override the catalog schema                            |
| `BIND_HOST`             | `127.0.0.1`                 | ASGI bind address. Use `0.0.0.0` behind a reverse proxy |
| `BIND_PORT`             | `8080`                      |                                                        |
| `CORS_ALLOW_ORIGINS`    | `*`                         | Comma-separated list                                   |
| `SEMANTIC_API_TOKEN`    | *(unset = no auth)*         | Bearer token required on every `/api/*` and `/mcp/*` request. `SEMANTIC_MCP_TOKEN` is still accepted as a legacy alias. |
| `TQ_LOGMECH`            | `TD2`                       | Forwarded to the `tq` client for ad-hoc queries        |

### Example `.env` (dev)

```bash
DATABASE_URI=teradata://demo_user:demo_user@localhost:1025/sem_engine
BIND_HOST=127.0.0.1
BIND_PORT=8080
```

### Example systemd unit (prod)

```ini
[Unit]
Description=Teradata Semantic Catalog
After=network.target

[Service]
Type=simple
User=semantic
WorkingDirectory=/srv/semantic-catalog
EnvironmentFile=/srv/semantic-catalog/env
ExecStart=/srv/semantic-catalog/.venv/bin/semantic-catalog serve --host 0.0.0.0
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

---

## Deploying the catalog itself

The catalog schema (tables, macros, stored procedures) is deployed with a separate command, distinct from starting the server:

```bash
# Full install, drops any existing catalog objects first
semantic-catalog install --fresh

# Regular install — idempotent, keeps existing data
semantic-catalog install

# Uninstall (requires confirmation)
semantic-catalog uninstall
```

The installer runs SQL files from `src/semantic_catalog/sql_bundle/` in dependency order. Each file is rendered against the configured `CATALOG_DB` (the placeholder `demo_user` is substituted on the way).

For a surgical re-deploy of specific files:

```bash
semantic-catalog deploy --mode split --include 04_ddl_metrics 05a_ddl_hierarchies
semantic-catalog deploy --mode whole --include 30_sp_semantic_search
```

`--mode split` is for DDL files (one statement per semicolon); `--mode whole` is for stored procedures and macros (submitted as a single statement).

---

## The compiler

Compilation, filtered-metric composition, join resolution, and SQL
rendering all run in-process in `semantic_catalog.compiler` (pure
Python with `sqlglot` for dialect emission). The older
`sp_semantic_request` SPL compiler was retired in v0.4 and has been
removed from the SQL bundle entirely.

```bash
POST /api/query/compile   # compile to SQL
POST /api/query/execute   # compile + execute, returns rows
POST /api/query/explain   # read-only EXPLAIN on the compiled SQL
```

---

## MCP integration

The server exposes five MCP-compatible tools at `/mcp/tools`:

| Tool                    | Delegates to                                |
|-------------------------|---------------------------------------------|
| `semantic.search`       | `sp_semantic_search`                        |
| `semantic.describe`     | `sp_semantic_describe`                      |
| `semantic.compile`      | Python compiler                             |
| `semantic.execute`      | Python compiler + execute                   |
| `semantic.export_osi`   | `exporter.osi.export_osi_yaml`              |

### Protocol

```
GET  /mcp/tools                           List tool schemas (OpenAI-style)
POST /mcp/tools/<tool_name>               Invoke; JSON body = args
```

Responses are plain JSON. An MCP protocol bridge (stdio, SSE) can wrap these endpoints, and many agent SDKs can speak to HTTP+JSON tools directly.

### Auth

Bearer-token auth is opt-in via `SEMANTIC_MCP_TOKEN`:

```bash
export SEMANTIC_MCP_TOKEN="$(openssl rand -hex 32)"
semantic-catalog serve
```

When set, every `/api/*` and `/mcp/*` request must include `Authorization: Bearer <token>`. When unset, no auth is applied (dev default — safe because the default bind is localhost). Use `SEMANTIC_API_TOKEN`; `SEMANTIC_MCP_TOKEN` is still honoured for backwards compatibility.

---

## Scaling

### Vertical

- The `teradatasql` driver is synchronous. Each request holds a cursor until it returns. For dev workloads this is irrelevant.
- The connection pool defaults to 4. Override via `DATABASE_POOL_SIZE`. Rule of thumb: match your Uvicorn worker count.

### Horizontal

- **The process is stateless.** Run N replicas behind a load balancer; add/remove capacity without drain.
- **The Python compiler holds no catalog cache.** Every request rereads what it needs from Teradata — bounded by 5–15 single-row lookups per compile (model, dataset, metric, relationship).

### Rate limiting

Not built in. Front with an API gateway (Envoy, nginx, a cloud load balancer) or use FastAPI middleware like `slowapi`.

---

## Observability

- `GET /api/health`   → version + DB host (no connection made)
- `GET /api/ping`     → `SELECT 1` round-trip; returns 503 on failure
- Logs go to stdout. Configure via standard `logging` environment: `LOG_LEVEL=DEBUG`.
- Response times are not instrumented by default — add `opentelemetry-instrumentation-fastapi` if you need traces.

---

## Troubleshooting

### `No DATABASE_URI found and TERADATA_HOST/USER/PASSWORD are not all set`

The process couldn't read a connection string. Set `DATABASE_URI` or all three split vars.

### `Column 'demo_user.mt.base_metric_id' does not exist`

The deployed catalog is on a pre-Phase-1 schema. Re-run `semantic-catalog install --fresh` to pick up the Phase 1 DDL (adds `base_metric_id`, `aggregate_fn`, `aggregate_arg` to `METRIC`, creates `METRIC_FILTER`).

### `AMBIGUOUS_PATH: dim 'X.Y' has N paths to X`

A role-played dataset was referenced without a role prefix. Prefix the dim with the role name:

```diff
- "dimensions": ["customer.c_mktsegment"]
+ "dimensions": ["placed_by.c_mktsegment"]
```

### `CHASM_WARNING: metrics span N grains`

You asked for metrics defined on different primary datasets in the same request. Split the request by grain — see [design-guidelines.md](design-guidelines.md#chasm-trap).

### `CYCLE` on metric compile

A composed metric's `${...}` references form a cycle. The error payload lists the full chain: `chain: ["margin", "profit", "margin"]`.

### MCP `401 missing bearer token`

`SEMANTIC_MCP_TOKEN` is set but the request didn't carry `Authorization: Bearer <token>`. Add the header, or unset the env var in dev.

### `EXECUTE_ERROR: ... Object does not exist`

The compiled SQL references a physical table that isn't deployed. Either the example data wasn't loaded (`semantic-catalog install-example <name>`) or the catalog's `DataBaseName`/`TableName` metadata points at the wrong schema. Check via `SELECT DataBaseName, TableName FROM <catalog>.DATASET WHERE dataset_name = '...'`.

---

## Upgrading

The semver rule: breaking changes to the REST contract, MCP tool signatures, or YAML import schema bump the **minor** version. DDL changes bump the **patch** version with a migration note in the release commit.

- Check `git log --oneline` for the last `Task #30: Tag v0.X` commit to find the current release.
- Before upgrading the catalog schema, dump the catalog YAML: `curl /api/export/osi/<model> > backup.yaml`.
- After upgrading the DDL, re-import the YAML: the Python importer is upsert-safe, so the round trip is idempotent.

---

## Where the code lives

```
src/semantic_catalog/
├── __main__.py        CLI entry point
├── config.py          DATABASE_URI parsing
├── db.py              teradatasql connection pool
├── server.py          FastAPI app factory
├── api/               REST endpoints (thin wrappers)
├── compiler/          Python SQL compiler (the main act)
│   ├── logical.py     LogicalPlan dataclasses
│   ├── catalog.py     CatalogDAO Protocol
│   ├── db_catalog.py  Concrete DAO over teradatasql
│   ├── inmem_catalog.py  In-memory fake for tests
│   ├── resolver.py    Tokens → ResolvedMetric/Dim/Filter
│   ├── joins.py       BFS + chasm detection
│   ├── render.py      LogicalPlan → sqlglot AST → SQL
│   └── orchestrator.py  compile(req, catalog) → plan
├── importer/          YAML → catalog INSERTs (pure Python)
├── exporter/          Catalog → OSI YAML
├── mcp/               Embedded MCP tools
├── static/            Single-page GUI
└── sql_bundle/        SQL files shipped with the package
```

Tests mirror this layout under `tests/`. The YAML regression suite lives in `tests/cases/`.
