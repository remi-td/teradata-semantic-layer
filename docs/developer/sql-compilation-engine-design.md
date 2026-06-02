# SQL Compilation Engine — Design

*Teradata Semantic Catalog — engine reference*
*Author: semantic-layer-team, 2026-04*

---

## Purpose

The catalog in `semantic-catalog-design.md` defines **what** a semantic
model looks like. This document defines **how** the catalog turns an
agent's intent into a concrete, validated Teradata SQL query.

The engine is the Python package `semantic_catalog.compiler`, embedded
in the same FastAPI process as the REST and MCP servers. It reads the
catalog via `SELECT` queries (no writes, no staging tables) and returns
a `LogicalPlan` that the renderer turns into a SQL string. The only
Teradata writes are the final `EXPLAIN` validation call and, when the
caller requests execution, the compiled query itself.

---

## 1. Architecture overview

The compiler is a pure-Python, stateless pipeline. All intermediate state
lives in Python objects; the database is never written to during
compilation.

```
CompileRequest (Python dataclass)
        │
        ▼
┌──────────────────────┐   DB reads (SELECT only)
│   resolver.py        │◀─ SEMANTIC_MODEL, METRIC, METRIC_EXPRESSION,
│   Resolver.resolve() │   METRIC_FIELD_REF, METRIC_FILTER,
│                      │   FIELD, DATASET, RELATIONSHIP
│   · resolve model    │
│   · resolve metrics  │   → MetricRef list (composed SQL expressions)
│   · resolve dims     │   → ResolvedDim list (field + alias + constraints)
│   · resolve filters  │   → ResolvedFilter list (WHERE / HAVING)
│   · pick anchor      │   → DatasetRef (fact table heuristic)
│   · build required   │   → _RequiredIndex (datasets to join)
└──────────┬───────────┘
           │  LogicalPlan (in-memory; join_steps not yet populated)
           ▼
┌──────────────────────┐   DB reads (SELECT only)
│   joins.py           │◀─ RELATIONSHIP, REL_COLUMN_MAP
│   JoinResolver       │
│   .resolve(plan)     │   BFS expansion + bridging
│                      │   → plan.join_steps (pre-rendered SQL fragments)
│                      │   → plan.unresolved  (datasets with no path)
└──────────┬───────────┘
           │  LogicalPlan (complete)
           ▼
┌──────────────────────┐
│   render.py          │   pure Python + sqlglot (no DB I/O)
│   render(plan)       │
│                      │   → SQL string
│                      │     LOCKING ROW FOR ACCESS
│                      │     SELECT TOP N ... FROM ... JOIN ...
│                      │     WHERE ... GROUP BY ... HAVING ... ORDER BY
└──────────┬───────────┘
           │
    ┌──────┴──────────────────────────────────────┐
    ▼                                             ▼
/api/query/compile                     /api/query/execute
return SQL + metadata                  run EXPLAIN → run query → return rows
(no DB writes)                         (one EXPLAIN SELECT, one data SELECT)
```

**DB I/O summary per compile call:**

| Phase | Query count | What |
|---|---|---|
| Resolve model | 1 | `SELECT` on `SEMANTIC_MODEL` |
| Resolve metrics | 1–3 per metric | `METRIC`, `METRIC_EXPRESSION`, `METRIC_FILTER` |
| Resolve dims | 1–3 per dim | `FIELD`, `RELATIONSHIP` (role lookup), transitive walk |
| Join planning | 1 | `RELATIONSHIP` + `REL_COLUMN_MAP` (one bulk load) |
| Render | 0 | pure Python |
| EXPLAIN (compile) | 1 | `EXPLAIN <sql>` via driver |
| Execute (optional) | 1 | the compiled query |

No staging tables. No session state. The process is safe to run in
parallel across as many replicas as needed.

---

## 2. Join graph resolution

The join graph lives in `RELATIONSHIP` (directed edges, many→one) and
`REL_COLUMN_MAP` (per-edge column pairs). Nodes are `DATASET` rows.
The Python BFS in `compiler/joins.py` (`JoinResolver`) populates
`LogicalPlan.join_steps` in place after the resolver has populated
`required_datasets`.

### 2.1 Algorithm: BFS with bridging

1. **Required set.** Collect every dataset referenced by the requested
   metrics and dimensions. Store as `LogicalPlan.required_datasets`.
2. **Anchor.** `primary_dataset_id` of the first metric (usually the fact
   table) or the dataset with the most outbound MANY_TO_ONE relationships.
   The anchor is marked `in_plan = True` and emitted as the FROM clause.
3. **Expansion loop.** On each iteration, `_pick_candidate` finds the
   best edge connecting an in-plan node to an out-of-plan required node:
   - Prefer MANY_TO_ONE forward edges (fact → dim) over reverse edges.
   - Deterministic tiebreaker on `(dataset_id, relationship_id)` for
     reproducible output.
   - Emit `INNER JOIN ... ON <REL_COLUMN_MAP pairs>` and mark in-plan.
   - Repeat until no adjacent required node remains.
4. **Bridging.** When expansion stalls but required datasets remain, add
   one intermediate dataset that is frontier-adjacent and adjacent to at
   least one out-of-plan required node. This handles multi-hop chains
   (e.g. reaching `customer` via an `orders` bridge without `orders`
   being explicitly requested). Capped at `MAX_BRIDGE_ITERATIONS = 10`.
5. **Unresolved.** Any dataset still out-of-plan after all iterations
   surfaces in `plan.unresolved` without crashing. The renderer signals
   the incomplete plan to the caller.

### 2.2 Role-playing: single-hop

When two relationships share the same `(from_dataset, to_dataset)` pair
with different `role_name` values, a plain `dataset.field` dim token is
ambiguous. The resolver rejects it with `AmbiguousPathError` and lists
the available roles.

To resolve, the caller prefixes the dim with the role name:

```
customer_nation.n_name   →  reach nation via customer_to_nation
supplier_nation.n_name   →  reach nation via supplier_to_nation
```

During join planning, each role-played node is stored with a
`role_edge_id` (the relationship_id it must be entered via). This is
propagated from `DatasetRef.role_edge_id` into `_PlanNode.role_edge_id`
in `_build_nodes`.

### 2.3 Role-playing: transitive resolution

A role prefix extends transitively to datasets downstream of the
role-played target. If `r_name` is not on `nation` (the direct role
target) but is on `region` (reachable via `nation_to_region`), the token
`customer_nation.r_name` still resolves:

1. **Resolver walk** (`_walk_transitive_role`): BFS from `nation` over
   outgoing relationships. Finds `r_name` on `region`. Returns:
   - the field ref
   - the final dataset (`region`)
   - the intermediate chain: `[(nation, "customer_nation")]`
   - the last relationship used (`nation_to_region`)
   - the alias of the node immediately before `region` (`"customer_nation"`)

2. **Required set additions:**
   - `nation` added with `alias="customer_nation"` (intermediate)
   - `region` added with `alias="customer_nation_region"`, plus two
     constraints stored on `DatasetRef`:
     - `role_edge_id = nation_to_region.relationship_id` — must enter
       region via this specific relationship
     - `entry_from_alias = "customer_nation"` — must be entered from that
       specific alias, not from any other in-plan node

3. **ResolvedDim:** `dataset_alias = "customer_nation_region"`,
   `column_alias = "customer_nation_r_name"`.

The transitive alias convention is always `{role_prefix}_{dataset_name}`.
This makes the origin role visible in both the SQL and the output column.

### 2.4 Edge-allowed constraints

`_edge_allowed(r, in_node, out_node, *, reverse)` is the gating function
called by `_pick_candidate` before accepting any edge. Three checks:

| Check | Condition | Purpose |
|---|---|---|
| **out_node role** | `out_node.role_edge_id is not None and r.relationship_id != it` | A role-pinned node may only be entered via its designated relationship. Blocks the wrong role path from claiming the node. |
| **out_node source** | `out_node.entry_from_alias is not None and in_node.alias != it` | A transitively-derived node may only be entered from its designated intermediate alias. Prevents `supplier_nation` from connecting to `customer_nation_region`. |
| **in_node reverse guard** | `reverse and in_node.role_edge_id is not None and r.relationship_id != it` | A role-pinned node may expand *forward* freely (enabling transitive walks), but cannot be traversed *backwards* via a different edge. Prevents `supplier_nation` from reaching `customer` via reversed `customer_to_nation`. |

All three checks are additive AND logic — any failure blocks the edge.

### 2.5 Selective pruning

Only datasets in `required_datasets` (plus bridges) are joined. The full
relationship graph is never traversed. A request for `revenue` by
`orders.o_orderyear` emits exactly two datasets (`lineitem`, `orders`);
the `nation/region/part` fan-out is never touched.

### 2.6 Comparison with prior art

- **MetricFlow** builds a `DataflowPlan` DAG and classifies fields by
  entity type (`primary`, `foreign`, `natural`). Its join resolver walks
  entity graphs the same way ours walks relationships, but expressed as
  Python objects emitting dialect-specific SQL via a templating layer.
- **Databricks Metric Views** bake joins into the view definition at
  creation time (`WITH JOINS`). The engine does not choose joins per
  request. Ours chooses per request because the catalog owns both the
  facts and the possible joins.
- **Cube** uses a declarative join graph that it traverses at query time
  with similar pruning semantics, but in a JS/Rust middleware layer
  rather than in-database.

---

## 3. Expression substitution

Metric and field expressions in the catalog reference `dataset.field`
using the **semantic dataset name**, not the physical table.
The engine keeps them verbatim in the compiled SQL:

```sql
-- FIELD.expression for lineitem.l_extendedprice: 'l_extendedprice'
-- METRIC_EXPRESSION (TERADATA) for total_revenue:
--     'SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'

-- Compiled FROM clause aliases the physical table to the
-- dataset_name, which makes the expression references resolve:
FROM tpch.lineitem AS lineitem
```

Every dataset is aliased to its `dataset_name`, so any expression that
uses `dataset.field` notation resolves correctly without rewriting.

Field expressions that are raw column references (`expression =
field_name`) get re-emitted as `dataset.field AS field`. Computed field
expressions (e.g. `EXTRACT(YEAR FROM o_orderdate)`) are wrapped with
parentheses and aliased to the field name.

---

## 4. Filter classification

Filters come in two flavors in the request:

| Param                | Placement | Intent                                                    |
| -------------------- | --------- | --------------------------------------------------------- |
| `p_where_filters`    | `WHERE`   | Pre-aggregation — applied to field values                 |
| `p_having_filters`   | `HAVING`  | Post-aggregation — applied to metric alias after GROUP BY |

The classification is **declarative**: callers tell the engine which
bucket a filter belongs to. This is simpler than inferring from the
referenced name because a "field" can be a grouped column, a joined
dimension, or (in some models) both a dim and a metric ingredient.

### HAVING expression substitution

A `p_having_filters` entry like `total_revenue|>|1000000` is rewritten
by **substituting the metric's Teradata expression** back in, not the
alias:

```sql
HAVING (SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))) > 1000000
```

This lets the engine emit the `HAVING` clause in a single pass without
relying on the optimizer to accept alias references post-GROUP BY
(which Teradata does not allow in all positions).

### Pre-aggregation vs post-aggregation: the Honeydew rule

Honeydew's convention (and ours) is: *if the filter references a field,
it is pre-aggregation; if it references a metric name, it is
post-aggregation.* We enforce that split by having two parameters
instead of one and by trusting the caller.

---

## 5. Fan-out and chasm traps

A classic trap:

```
customer -< orders      (one-to-many)
customer -< returns     (one-to-many)
```

If a query joins `orders` and `returns` through `customer` and then
`SUM(orders.amount)`, each order row is multiplied by the number of
returns for that customer. This is **fan-out**.

### What the engine does today (v1)

The BFS traversal is **mostly single-spine**: every join is driven from
a dataset already in plan to an *out-of-plan* neighbor. If both fact
tables (`orders` and `returns`) are requested at once, the engine will
emit both joins, producing the chasm-trap SQL.

### What it should do (v2)

Three paths, in order of implementation cost:

1. **Detect at compile time.** When two distinct `MANY_TO_ONE` edges
   converge on the same one-side dataset, flag as a potential chasm
   and reject the request with a clear message.
2. **Rewrite to subqueries.** Isolate each fact's aggregation in its
   own CTE, then join the CTEs on the shared dimension. This is what
   MetricFlow does via its `measure_group` nodes.
3. **Use Teradata MEASURE() semantics** (future, requires platform
   support) — the planner takes care of the rewrite natively, à la
   Databricks' metric views.

MetricFlow's approach relies on labeling fields as `entity` vs
`measure` vs `dimension`. We already have that vocabulary
(`FIELD.field_type_code`, `is_dimension`, `METRIC`, `METRIC_FIELD_REF`)
— we just don't currently use it for chasm detection.

---

## 6. Teradata-specific optimizations

### Locking

The emitted SQL starts with `LOCKING ROW FOR ACCESS`. For metadata and
analytical reads this avoids read locks on the base tables, which is the
right default for dashboard queries.

### Statistics

All catalog tables are covered by `COLLECT STATISTICS` on their PI and
common filter columns (see `sql/08_collect_stats.sql`). The base data
tables used in compiled SQL must be stats-collected by the data team;
the engine does not inject `COLLECT STATS` calls (it would be too
invasive to run automatically).

### Primary-index awareness

The engine emits `INNER JOIN ... ON dataset.pk = dataset.fk` using the
column pairs from `REL_COLUMN_MAP`. When those columns align with the
PI of each side, Teradata's optimizer can plan a row-hash join and avoid
redistribution. The catalog carries primary-key metadata
(`DATASET_KEY`) that a future version could use to hint or re-order joins
for PI alignment.

### Partition elimination

A future version can read `CUSTOM_EXTENSION.extension_data` for
partitioning hints (we already store such a hint on `tpch_orders.lineitem`
— the partitioning scheme is there as JSON) and inject partition
predicates in `WHERE`.

### Row-hash vs product join traps

The EXPLAIN validation step catches product joins early — if Teradata
reports one, the compiler marks the request invalid and returns the
SQL for inspection without running it. (On our sandbox the base tables
don't exist so we catch a different error, but the plumbing is the
same.)

---

## 7. Design rationale

Why Python in the same process as the API, rather than a stored procedure
or a standalone middleware?

| Aspect | Python in-process (chosen) | Pure SP (original design) | Standalone middleware |
| --- | --- | --- | --- |
| Testability | 146 unit tests, no DB required | Call-and-inspect only | Unit-testable but deploy overhead |
| Catalog currency | One `SELECT` per compile — always live | Same | Cache invalidation risk |
| Error handling | Full Python exceptions, structured errors | SPL SQLEXCEPTION blocks | Full language freedom |
| SQL generation | sqlglot handles quoting, dialect nuance | String concatenation | Full freedom |
| Governance | Teradata auth flows through to compiled SQL | Native RBAC | Separate auth layer |
| Dependency | teradatasql driver only | Zero (inside TD) | JVM / Python service + deploy |
| Cross-platform | Teradata only (sqlglot can retarget) | Teradata only | Any dialect |
| MCP/REST co-location | Same process, zero latency | Separate call boundary | Network hop |

The Python-in-process approach wins here because:

- The catalog is Teradata-hosted, so the compiler always has a live
  connection. No caching layer is needed.
- Unit tests run without a database — the `InMemoryCatalog` test double
  covers the full compiler surface.
- The same process hosts the REST API, MCP server, and GUI static files.
  A compile call from an MCP tool has no extra network hops.
- sqlglot handles Teradata quoting, `TOP N` vs `LIMIT`, and `LOCKING`
  syntax without fragile string concatenation.

The escape hatch for multi-platform reach is the OSI YAML exporter
(`semantic-catalog export` / `/api/export/osi`): any OSI-compatible
engine can consume the exported model.

---

## 8. Future evolution

### Near term

1. **Chasm-trap detection.** See §5 option 1 — when two distinct
   `MANY_TO_ONE` joins converge at a shared one-side dataset, emit a
   compile-time error rather than producing inflated SQL.
2. **Security policy enforcement.** Honor `SECURITY_POLICY.ROW_FILTER`
   by injecting the policy expression into `WHERE` for the requesting
   user's group. The table exists; the compiler doesn't read it yet.
3. **Cost hints from EXPLAIN.** Parse the EXPLAIN output for estimated
   row counts and surface them in the compile response so an agent can
   decide whether to auto-approve execution.
4. **Streaming execution results.** `/api/query/execute` currently
   buffers the full result set. Large results should stream as
   newline-delimited JSON.

### Medium term

1. **Incremental refresh of metric caches.** For certified SIMPLE
   metrics with a known time grain, the engine can maintain a
   rollup table and re-route `total_revenue by month` to it. Add a new
   entity `METRIC_ROLLUP` that maps `(metric_id, grain) → physical_table`.
2. **Derived metric resolution.** Expand `DERIVED` metrics at compile
   time by recursively substituting constituent metric expressions. The
   `DERIVED` type is declared today but not yet used by the compiler.
3. **Automated OSI round-trip.** Keep an OSI YAML document as a
   notional source of truth; the importer loads it into the catalog
   (reverse of `/api/export/osi`). This lets teams commit model
   changes to git while keeping the live engine in Teradata.

### Long term

1. **Native Teradata `MEASURE()`.** Julian Hyde's work in Apache
   Calcite (SQL 2023 MEASURE semantics) is the clearest direction. When
   Teradata exposes a native measure type, the compilation target
   becomes `SELECT MEASURE(total_revenue) BY o_orderyear FROM ...` and
   the optimizer handles chasm-avoidance automatically. Our catalog
   already carries every piece of metadata a native MEASURE would need;
   the engine becomes a thin translator.
2. **Richer MCP tool surface.** The MCP server (`/mcp/`) is already
   shipped. Future tools could expose per-entity describe calls,
   streaming execution, and EXPLAIN previews so agents can make
   cost-aware decisions before running queries.
3. **OSI compatibility layer.** Complete the round-trip: OSI-compliant
   models in, OSI YAML out, and — when paired with the import procedure
   — a full interchange story across OSI adopters.

---

## Appendix A — Referenced open-source work

| Project        | License    | What we learned from it                                   |
| -------------- | ---------- | --------------------------------------------------------- |
| MetricFlow     | Apache 2.0 | DataflowPlan DAG, entity-type classification for chasm    |
|                |            | detection, dialect-specific SQL emission. See             |
|                |            | `metricflow/plan_conversion/` and `metricflow/sql/`.      |
| Cube           | Apache 2.0 | Join-path resolution against a declarative graph;         |
|                |            | pre-aggregation matching. Architectural inspiration.      |
| dotML          | Apache 2.0 | Minimal YAML → SQL compiler (~500 LOC Python). Our        |
|                |            | resolver + BFS is architecturally similar but             |
|                |            | catalog-driven rather than YAML-file-driven.              |
| Apache Calcite | Apache 2.0 | Long-term target for native MEASURE() semantics;          |
|                |            | Julian Hyde's papers on SQL 2023 MEASURE.                 |

---

## Appendix B — Request-time pseudocode

This reflects the actual Python compiler. All DB I/O is `SELECT`; no
staging tables, no writes during compilation.

```python
# compiler/orchestrator.py  compile(req, catalog) → LogicalPlan

# ── resolver.py ─────────────────────────────────────────────────────────────
model_id = catalog.resolve_model_id(req.model)          # DB SELECT
required  = _RequiredIndex()

metrics = []
for name in req.metrics:
    metric = catalog.find_metric(model_id, name)        # DB SELECT
    expr   = _compose_expression(metric, catalog)       # DB SELECT × depth
    required.add(catalog.load_dataset(metric.primary_dataset_id))
    metrics.append(MetricRef(metric_name=name, expression=expr, ...))

dims = []
for token in req.dimensions:
    field_part, grain = _split_grain(token)
    prefix, field_name = _split_prefix(field_part)

    if prefix and (role_rel := catalog.find_relationship_by_role(model_id, prefix)):
        # role-prefixed: reach target via pinned relationship
        target_ds = catalog.load_dataset(role_rel.to_dataset_id)  # DB SELECT
        field = catalog.find_field_on_dataset(target_ds.id, field_name)
        if field is None:
            # transitive: BFS over outgoing rels from target_ds
            field, final_ds, intermediates, last_rel_id, entry_from = \
                _walk_transitive_role(model_id, ...)     # DB SELECT × hops
            required.add(target_ds, alias=prefix)
            required.add(final_ds,  alias=f"{prefix}_{final_ds.name}",
                         role_edge_id=last_rel_id, entry_from_alias=entry_from)
        else:
            required.add(target_ds, alias=prefix)
        dims.append(ResolvedDim(field=field, dataset_alias=..., role_edge_id=...))
    else:
        # unambiguous or plain dataset.field
        field = catalog.find_field(model_id, prefix, field_name)  # DB SELECT
        _check_unambiguous(model_id, field.dataset_id, token)      # DB SELECT
        required.add(catalog.load_dataset(field.dataset_id))
        dims.append(ResolvedDim(field=field, dataset_alias=prefix or ds.name))

anchor = _pick_anchor(required, metrics)
plan   = LogicalPlan(model_id=model_id, anchor=anchor,
                     required_datasets=required.as_list(),
                     metrics=metrics, dimensions=dims, ...)

# ── joins.py ─────────────────────────────────────────────────────────────────
rels = catalog.load_relationships(model_id)              # DB SELECT (one query)
JoinResolver(catalog, model_id).resolve(plan)
# → plan.join_steps filled; plan.unresolved lists unreachable datasets

# ── render.py ─────────────────────────────────────────────────────────────────
sql = render(plan)   # pure Python + sqlglot, zero DB I/O
# → "LOCKING ROW FOR ACCESS\nSELECT TOP N ...\nFROM ...\nINNER JOIN ...\n..."

# ── caller (api/query.py) ────────────────────────────────────────────────────
explain_result = conn.execute(f"EXPLAIN {sql}")          # DB EXPLAIN SELECT
if execute:
    rows = conn.execute(sql)                             # DB data SELECT
return CompileResponse(compiled_sql=sql, is_valid=..., ...)
```

---

## Appendix C — File layout

```
semantic-layer/
├── docs/developer/
│   ├── semantic-catalog-design.md         — conceptual / logical design
│   └── sql-compilation-engine-design.md   — this document
├── src/semantic_catalog/
│   ├── __main__.py                        — CLI: serve | install | install-example | ping | deploy
│   ├── compiler/
│   │   ├── catalog.py                     — CatalogDAO abstract interface (SELECTs only)
│   │   ├── db_catalog.py                  — DbCatalog: live Teradata reads via teradatasql
│   │   ├── inmem_catalog.py               — InMemoryCatalog: test double (no DB required)
│   │   ├── logical.py                     — DatasetRef, FieldRef, MetricRef, ResolvedDim,
│   │   │                                    LogicalPlan, JoinStep, …
│   │   ├── request.py                     — CompileRequest, CompileFilter, CompileSort
│   │   ├── errors.py                      — CompileError, AmbiguousPathError,
│   │   │                                    UnknownEntityError, UnresolvedJoinError, …
│   │   ├── resolver.py                    — CompileRequest → LogicalPlan
│   │   │                                    (metric / dim / filter resolution,
│   │   │                                    role-playing, transitive walks, anchor)
│   │   ├── joins.py                       — JoinResolver: BFS join planning
│   │   │                                    (_edge_allowed, _add_bridge)
│   │   ├── render.py                      — LogicalPlan → Teradata SQL (sqlglot)
│   │   └── orchestrator.py               — compile(req, catalog) entry point
│   ├── api/
│   │   ├── catalog.py                     — /api/models, /tree, /graph, /search, /describe
│   │   └── query.py                       — /api/query/compile, /execute, /explain
│   ├── mcp/
│   │   ├── server.py                      — MCP Streamable HTTP at /mcp/
│   │   └── tools.py                       — semantic.compile, semantic.execute, …
│   └── sql_bundle/                        — DDL + m_semantic_search / m_semantic_describe macros
│                                            (deployed to Teradata by `semantic-catalog install`)
├── examples/
│   ├── tpch_orders/                       — TPC-H sample data + semantic model SQL
│   └── school_gradebook/                  — gradebook sample (filtered metrics, roles)
└── tests/
    ├── test_compiler_resolver.py          — resolver unit tests (InMemoryCatalog)
    ├── test_compiler_joins.py             — BFS + render end-to-end tests
    ├── test_api_fake.py                   — FastAPI routes against FakePool
    └── test_live_smoke.py                 — end-to-end against real Teradata (marker: live)
```
