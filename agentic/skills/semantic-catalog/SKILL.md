---
name: semantic-catalog
description: Install, administer, and query the Teradata Semantic Catalog — a Teradata-native semantic layer with an embedded MCP server. Load when the user asks to "talk to Teradata", build or inspect a semantic model, author metrics/dimensions, import YAML into the catalog, compile governed SQL, or wire an AI agent to Teradata via MCP.
---

# Teradata Semantic Catalog — agent skill

This skill is self-contained: it covers install, administration, and
every agent-facing workflow for the Teradata Semantic Catalog
(`https://github.com/remi-td/teradata-semantic-layer`). Load it whenever the
user wants governed SQL answers over Teradata or needs to build/inspect
a semantic model.

---

## 1 · What this product is

- A **semantic layer** that lives inside Teradata Vantage. Metadata
  (models, datasets, fields, metrics, relationships, views, AI context)
  is stored in ordinary Teradata tables.
- Ships with three surfaces in one process:
  - **GUI** — `/` renders a Cytoscape graph of the catalog + a query
    builder.
  - **REST API** — `/api/*` for compile / execute / import / export.
  - **Embedded MCP server** — Streamable HTTP / JSON-RPC at `/mcp/`,
    exposing five tools agents call directly: `semantic.search`,
    `semantic.describe`, `semantic.compile`, `semantic.execute`,
    `semantic.export_osi`.
- **Pure-Python compiler.** No `bteq`, no external Teradata MCP server,
  no stored-procedure compiler. One `pip install`.

Key concepts (memorise these — every call below takes one of them as
input):

| Term              | What it is                                                                 |
|-------------------|-----------------------------------------------------------------------------|
| **Model**         | A named container (`tpch_orders`, `p360`, …).                              |
| **Dataset**       | A table / view / cube that contributes to the model.                       |
| **Field**         | A column (attribute `A` or key `K`) on a dataset.                          |
| **Metric**        | An aggregate definition — `SIMPLE` (a `SUM`/`COUNT`/`AVG`), `RATIO`, `CUMULATIVE`, or `DERIVED`. |
| **Filtered metric** | A `SIMPLE` metric + `METRIC_FILTER` rows. The compiler emits `AGG(CASE WHEN <predicates> THEN <arg> ELSE 0 END)` automatically. |
| **Relationship**  | A many-to-one (or rarer) join between two datasets, defined by `REL_COLUMN_MAP`. |
| **Semantic view** | A curated projection — which dimensions + metrics are "certified" for consumption. |
| **AI context**    | Free-form instructions + synonyms attached to any entity.                  |

---

## 2 · Install (fresh Teradata)

```bash
git clone https://github.com/remi-td/teradata-semantic-layer.git
cd semantic-catalog
pip install .

export DATABASE_URI="teradata://<user>:<pw>@<host>:1025/<database>"
semantic-catalog ping                        # verify connectivity
semantic-catalog install                     # deploy every catalog DDL + macros (one command)
semantic-catalog install-example tpch_orders # optional: seed a ready-made model
```

Production: also set `SEMANTIC_API_TOKEN`, then every `/api/*` and
`/mcp/*` request must carry `Authorization: Bearer <token>`.

Launch the server (GUI + REST + MCP all at once):

```bash
SEMANTIC_API_TOKEN=<secret> semantic-catalog serve --host 0.0.0.0 --port 8080
```

Common mistakes:
- `pip install -e ".[dev]"` is for contributors; end-users want plain
  `pip install .`.
- `DATABASE_URI` must start with `teradata://` or `teradatasql://`; any
  other scheme errors out.
- Re-installing is safe (`install --fresh` drops the catalog first if
  you need a clean slate).

---

## 3 · When to use which MCP tool

All five tools surface through the standard MCP **Streamable HTTP**
endpoint at `/mcp/` — wire your client (see §6) and the protocol does
the rest. From an agent's POV: call them by name with their argument
object. From the wire: it's JSON-RPC `tools/call`. Example payload:

```json
{ "name": "semantic.search", "arguments": { "term": "revenue", "model": "tpch_orders" } }
```

For shell pipelines / curl, prefer the equivalent REST endpoints under
`/api/*` (see §5).

| Tool                    | Use when                                                                 |
|-------------------------|--------------------------------------------------------------------------|
| `semantic.search`       | User asks vague questions ("do we have revenue?", "find deposit metrics"). Ranked hits across every entity + synonym. |
| `semantic.describe`     | You know the entity name and want full metadata (datasets, filters, AI context, expressions). |
| `semantic.compile`      | Build governed SQL from a structured request. Use for "show me the SQL" queries. |
| `semantic.execute`      | Same request, but actually run it and return rows (≤ 500).               |
| `semantic.export_osi`   | User needs an OSI YAML dump of a model.                                  |

### Shape of a compile/execute request

```json
{
  "request": {
    "model": "tpch_orders",
    "metrics": ["revenue", "promo_share"],
    "dimensions": ["customer.c_mktsegment", "nation.n_name"],
    "where":  [{"field": "orders.o_orderdate", "op": ">=", "value": "2023-01-01", "type": "DATE"}],
    "having": [{"metric": "revenue", "op": ">", "value": 100000, "type": "NUMBER"}],
    "sort":   [{"field": "revenue", "direction": "DESC"}],
    "limit":  100,
    "execute": false
  }
}
```

Things to know:
- `metrics`, `dimensions` are lists of strings. Dimensions may be
  `dataset.field` or `role_alias.field[:GRAIN]` (e.g.
  `customer.c_nationkey → role.n_name`).
- `where` targets row-level columns → pre-aggregation `WHERE`.
- `having` targets metric names → post-aggregation `HAVING`.
- `type` hints accepted on values: `STRING` (default), `NUMBER`, `DATE`,
  `RAW`. Prefer `STRING` / `NUMBER` / `DATE`; use `RAW` only for
  BETWEEN date ranges (`"DATE 'X' AND DATE 'Y'"`). The compiler now
  regex-validates every RAW value, so arbitrary SQL will be rejected.
- `limit: 0` means unlimited on compile; `semantic.execute` truncates
  at 500 rows regardless.

### Interpreting compile errors

The compiler returns structured `code` fields on failure:

| Code             | What it means                                                                 | Typical fix                                                                 |
|------------------|-------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| `UNKNOWN_MODEL`  | No model with that name in the catalog.                                       | `semantic.search` to find the right name, or `install-example` to seed one. |
| `UNKNOWN_METRIC` | Metric name not found in the model.                                           | Confirm via `semantic.describe(entity_type="MODEL", entity_name=…)`.        |
| `UNKNOWN_FIELD`  | Dimension or filter field not on the named dataset.                           | Either add the field to the model via `/api/import` or pick an alternative. |
| `AMBIGUOUS_PATH` | More than one join path between two datasets; resolver refuses to guess.      | Add a `role_name` to one of the relationships, or request the joined datasets explicitly. |
| `CHASM_TRAP`     | Two independent fact tables grouped by a dimension each could double-count.   | Constrain to one fact or rewrite as separate queries.                       |
| `CYCLE`          | Metric-in-metric cycle (`${a}` ↔ `${b}`).                                    | Break the cycle in the definitions.                                         |
| `COMPILE_ERROR`  | Catch-all — detail in `message`.                                              | Read the message; the layer is conservative about raising before SQL runs.  |

---

## 4 · Author a semantic model (minimal recipe)

Every model is one YAML document. Load it via
`POST /api/import` with `{ "model": "<name>", "text": "<yaml>",
"dry_run": false }`.

### Minimal viable YAML

```yaml
models:
  - name: my_model
    description: Short sentence the agent can paraphrase.

datasets:
  - name: sales
    source_table: ops.fact_sales
    description: One row per transaction.
    fields:
      - {name: sale_id,     type: K, data_type: INTEGER}
      - {name: customer_id, type: K, data_type: INTEGER, is_dimension: 1}
      - {name: sale_ts,     type: A, data_type: TIMESTAMP(6), is_dimension: 1, is_time_dimension: 1}
      - {name: amount,      type: A, data_type: DECIMAL(18,2)}

  - name: customer
    source_table: ops.dim_customer
    fields:
      - {name: customer_id, type: K, data_type: INTEGER}
      - {name: region,      type: A, data_type: VARCHAR(64), is_dimension: 1}

relationships:
  - name: sales_to_customer
    from: sales
    to:   customer
    cardinality: MANY_TO_ONE
    columns:
      - {from_field: customer_id, to_field: customer_id}

metrics:
  - name: revenue
    primary_dataset: sales
    aggregate_fn: SUM
    aggregate_arg: sales.amount
    is_certified: 1
    expressions:
      TERADATA: SUM(sales.amount)

ai_context:
  - entity_type: METRIC
    entity_name: revenue
    instructions: "Sum of sale amounts. Additive across all dimensions."
    synonyms: [net sales, GMV]
```

### Pattern: filtered-rollup metric

Define a **base** metric once, declare variants as filtered
specialisations. The compiler emits one `CASE WHEN` per variant:

```yaml
metrics:
  - name: score_avg             # base
    primary_dataset: assessment
    aggregate_fn: AVG
    aggregate_arg: assessment.score

  - name: exam_score_avg        # filtered variant
    base_metric: score_avg
    filters:
      - {field: assessment_type.category_lvl1, op: '=', filter_value: "'EX'"}
```

Compiled SQL:
`AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg`
— plus the `assessment ↔ assessment_type` join, added automatically.

### Pattern: ratio metric

Use `metric_type: RATIO` and put the full expression (including
`NULLIFZERO`) in the TERADATA dialect. Reference other datasets by name
so the resolver joins them for you:

```yaml
metrics:
  - name: promo_share
    primary_dataset: lineitem
    metric_type: RATIO
    is_additive: 0
    expressions:
      TERADATA: |-
        CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%'
                      THEN lineitem.l_extendedprice*(1 - lineitem.l_discount) END)
             / NULLIFZERO(SUM(lineitem.l_extendedprice*(1 - lineitem.l_discount)))
             AS DECIMAL(18,6))
```

### Common import pitfalls

- **`synonyms` must be a YAML list** — `[a, b, c]`. A comma-separated
  string fails the JSON validator inside Teradata.
- **`ai_context` keys are `entity_type` / `entity_name`** (not
  `object_type/_name`; the writer silently falls through otherwise).
- **Any failure rolls back the whole batch.** The error list in the
  response tells you which ord failed first; everything after is
  `unknown model …` cascade noise.

---

## 5 · Querying worked examples (pastable)

### List models

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/models | jq
```

> Below is the **REST** entry point (handy for shell pipelines / curl).
> AI agents should use the **MCP** tools instead — see §6 for client
> wiring; the tool names mirror the REST endpoints.

### Natural-language search

```bash
curl -s -G --data-urlencode "q=revenue" --data-urlencode "model=tpch_orders" \
     -H "Authorization: Bearer $TOKEN" \
     http://localhost:8080/api/search | jq '.[0:5]'
```

### Compile SQL only

```bash
curl -s -X POST http://localhost:8080/api/query/compile \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
            "model":"tpch_orders",
            "metrics":["revenue"],
            "dimensions":["nation.n_name"],
            "sort":[{"field":"revenue","direction":"DESC"}],
            "limit":10}' | jq '.sql'
```

### Compile + execute

```bash
curl -s -X POST http://localhost:8080/api/query/execute \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
            "model":"tpch_orders",
            "metrics":["revenue","promo_share"],
            "dimensions":["customer.c_mktsegment","nation.n_name","region.r_name"],
            "having":[{"metric":"promo_share","op":">","value":0.1,"type":"NUMBER"}]}' \
     | jq '.row_count, .rows[0]'
```

### Export OSI YAML

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
     http://localhost:8080/api/export/osi/tpch_orders > model.osi.yaml
```

---

## 6 · MCP client wiring

The server speaks the standard MCP **Streamable HTTP** transport at
`/mcp`. Two client shapes cover every common case.

### Claude Code, Cursor, Continue (native HTTP MCP)

```jsonc
{
  "mcpServers": {
    "semantic-catalog": {
      "url": "http://localhost:8080/mcp/",
      "headers": { "Authorization": "Bearer ${SEMANTIC_API_TOKEN}" }
    }
  }
}
```

### Claude Desktop (stdio-only — bridge via `mcp-remote`)

`claude_desktop_config.json` only accepts stdio servers, so use
`mcp-remote` (npm) to proxy stdio ↔ HTTP:

```jsonc
{
  "mcpServers": {
    "semantic-catalog": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "http://localhost:8080/mcp/",
        "--header", "Authorization: Bearer ${SEMANTIC_API_TOKEN}"
      ],
      "env": { "SEMANTIC_API_TOKEN": "<paste-token-here>" }
    }
  }
}
```

The `env` block is required — Claude Desktop spawns `npx` without
inheriting your interactive shell, so `${SEMANTIC_API_TOKEN}` references
the value defined in `env`, not your shell.

The five tools surface under both client shapes as
`semantic.search`, `semantic.describe`, `semantic.compile`,
`semantic.execute`, `semantic.export_osi`.

---

## 7 · Known limitations (be upfront with the user)

Flag these before offering to do something the layer can't:

- **No time-shifted metrics.** Period-over-period (`CY − PY`), `MoM`,
  `12M rolling` as a metric kind aren't first-class yet. Achieve them
  with two requests and client-side diff, or fall through to raw SQL.
  Roadmap: v0.5 `period_compare` metric kind.
- **No window functions.** `RANK()`, `ROW_NUMBER()`, `SUM() OVER ()`
  aren't emitted by the compiler. Topping / ranking is simulated via
  `sort + limit`. Roadmap: v0.5+.
- **No grouping sets / rollup.** One GROUP BY per query. Roadmap: v0.5.
- **Raw filters are conservatively gated.** `type: RAW` accepts only
  dates, numbers, single-quoted strings, and BETWEEN-date ranges. For
  anything else, use the structured `value` / `values` fields.
- **`FORMAT_SPEC` round-trips via OSI export but not yet via
  `/api/import`.** To register format info on a metric or field today,
  INSERT directly into `FORMAT_SPEC` (entity_type + entity_id). The
  exporter and `semantic.describe` already surface it.

If the user asks for any of these, say so explicitly and offer a
workaround.

---

## 7b · Row-level security (operator-trusted WHERE injection)

Since v0.4 the compiler will inject operator-defined WHERE fragments
for every `/api/query/{compile,execute}` call that carries an
`X-Semantic-Groups` header. The fragments live in the `SECURITY_POLICY`
catalog table (`policy_type = 'ROW_FILTER'`) and can be group-scoped or
global (`group_name IS NULL`). The user's request body cannot set
RLS predicates — by design.

Wire RLS up:

```sql
-- one-time, per model (via tq or Vantage Studio):
INSERT INTO sem_engine.SECURITY_POLICY
  (entity_type, entity_id, policy_ordinal, policy_type, group_name, policy_expression)
VALUES
  ('MODEL', 42, 1, 'ROW_FILTER', 'branch_100', 'events.CO_LE IN (''100'')'),
  ('MODEL', 42, 2, 'ROW_FILTER', NULL,         'events.is_deleted = 0');
```

Then every call:

```bash
curl -s -X POST http://localhost:8080/api/query/compile \
     -H "Authorization: Bearer $TOKEN" \
     -H "X-Semantic-Groups: branch_100" \
     -H "Content-Type: application/json" \
     -d '{"model":"p360","metrics":["amount_sum"]}' | jq '.compiled_sql'
```

The compiler AND-joins the global policy, every group-matched policy,
and the user's own filters. It does not parse, template, or validate
the fragments — the `policy_expression` column is operator-trusted raw
SQL (use `CURRENT_USER` for identity binding when needed).

Scope (v0.4): `entity_type = MODEL` only. DATASET- and VIEW-scoped
policies are declared in the DDL but not yet consumed.

---

## 8 · Diagnostic recipes

- **"Compile returned `UNKNOWN_FIELD` on `foo.bar`"** →
  `semantic.describe(entity_type="DATASET", entity_name="foo")` — check
  if the field exists; if the field is on a different dataset, use
  `role_alias.field` or rename.
- **"Import returned many `unknown model` errors"** → look at the
  *first* ERROR row. Everything after is cascade (the transaction
  aborted; the model insert rolled back).
- **"Execute succeeded with zero rows"** → run `semantic.compile`,
  copy the SQL, run `/api/query/explain` (read-only) to confirm the
  plan. Then spot-check the filters in the GUI's Query Builder.
- **"`/api/*` returns 401"** → `SEMANTIC_API_TOKEN` is set in the
  server's environment; include `Authorization: Bearer <token>`.

---

## 9 · Handing off

When you finish a task against this skill, tell the user:
1. Which model(s) you touched (`/api/import` applied? how many entities
   loaded?).
2. The compiled SQL of the key query (truncated to ~20 lines).
3. Any `AMBIGUOUS_PATH` / `CHASM_TRAP` warnings that surfaced — these
   are design issues in the model, not just transient errors.

Do **not** run `semantic-catalog uninstall*` without an explicit ask.
Do **not** modify `pyproject.toml` or version numbers as a side effect
of test runs.
