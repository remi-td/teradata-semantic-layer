# SQL Compilation Engine — Design

*Teradata Semantic Catalog — engine reference*
*Author: semantic-layer-team, 2026-04*

---

## Purpose

The catalog in `semantic_catalog_design_v2.md` defines **what** a semantic
model looks like. This document defines **how** the catalog turns an
agent's intent into a concrete, validated Teradata SQL query.

The engine is implemented as a Teradata stored procedure,
`demo_user.sp_semantic_request`, that reads the catalog's own tables.
There is no external runtime: *the catalog is the engine.*

---

## 1. Architecture overview

`sp_semantic_request` is a single-pass compiler structured as a linear
pipeline. Each stage reads from catalog tables (or staging tables populated
by earlier stages) and writes to the next stage's input.

```
┌──────────────────────┐
│ 0. Reset staging     │  DELETE FROM request_*  (single-user sandbox;
│                      │   add SESSION_ID column for multi-tenant)
└──────────┬───────────┘
           ▼
┌──────────────────────┐   catalog input
│ 1. Resolve model     │◀──── SEMANTIC_MODEL
└──────────┬───────────┘
           ▼
┌──────────────────────┐   catalog input
│ 2. Resolve metrics   │◀──── METRIC, METRIC_EXPRESSION,
│    → request_metric  │      METRIC_FIELD_REF
└──────────┬───────────┘
           ▼
┌──────────────────────┐   catalog input
│ 3. Resolve dims      │◀──── FIELD, DATASET
│    → request_dim     │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 4. Pick anchor       │   heuristic: primary_dataset of first metric,
│                      │   else dataset with most outbound rels
└──────────┬───────────┘
           ▼
┌──────────────────────┐   catalog input
│ 5. BFS join search   │◀──── RELATIONSHIP, REL_COLUMN_MAP
│    → request_join_step
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 6. Unreachable check │   mark request invalid if any required
│                      │   dataset is not in plan
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 7. Emit SELECT list  │   dims + metric expressions
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 8. Emit FROM + JOINs │   concatenate request_join_step rows
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 9. Emit WHERE        │   pre-aggregation filters (field-based)
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 10. Emit GROUP BY    │   all dim expressions
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 11. Emit HAVING      │   metric-valued filters (substitute alias
│                      │   with metric expression)
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 12. Emit ORDER BY    │
│     + TOP N          │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 13. Assemble v_sql   │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 14. Validate EXPLAIN │   CALL DBC.SysExecSQL('EXPLAIN ' || v_sql)
│                      │   capture failure without aborting the proc
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ 15. Persist result   │   INSERT INTO request_result
└──────────────────────┘
```

Every stage runs in a single RDBMS session. Intermediate state lives in
`demo_user.request_*` staging tables so the compiler can inspect and
retry without rebuilding from scratch.

---

## 2. Join graph resolution

The join graph lives in `RELATIONSHIP` (edges, directed from many→one) and
`REL_COLUMN_MAP` (per-edge column pairs). Nodes are `DATASET` rows.

### Algorithm: directed BFS

1. Collect **required** datasets — everything referenced by the requested
   metrics and dimensions. Store in `request_required_ds`.
2. Pick an **anchor**:
   - `primary_dataset_id` of the first metric (when present), which
     usually corresponds to the fact table.
   - Fallback: the required dataset with the most outbound
     many-to-one relationships (structural hint that it is a fact).
3. Mark the anchor as `in_plan = 1` and emit it as the `FROM` clause.
4. **BFS loop** (capped at 10 iterations):
   - Among required datasets not yet `in_plan`, find one that has a
     direct `RELATIONSHIP` (in either direction) to a dataset already in
     plan. Prefer `MANY_TO_ONE` edges over `ONE_TO_MANY` (dimension
     lookup semantics), and outbound edges over inbound edges.
   - Emit an `INNER JOIN` using the column pairs from `REL_COLUMN_MAP`
     (composite joins produced by `column_position`-ordered
     concatenation).
   - Mark in plan and repeat.
5. When no progress can be made, leave the loop. Any still-out datasets
   are reported as unreachable in `validation_message`, and
   `is_valid = 0`.

### Selective pruning

The engine only joins datasets that are required. The full relationship
graph is not traversed. This keeps compiled SQL minimal — an agent that
requests `total_revenue` by `orders.o_orderyear` gets exactly two
datasets (`lineitem`, `orders`), never the full `nation/region/part`
fan-out.

### How MetricFlow and Databricks MV compare

- **MetricFlow** builds a full [`DataflowPlan`] DAG and classifies nodes
  by entity type (`primary`, `foreign`, `natural`). Its join resolver
  walks entity graphs the same way ours walks relationships, but it is
  expressed in Python and emits dialect-specific SQL via a templating
  layer.
- **Databricks Metric Views** define per-view joins at creation time
  (the `WITH JOINS` clause). The engine does not choose joins at query
  time — the author baked them in. Ours chooses per request because the
  catalog owns both the facts and the possible joins.

### Known limitation (v1)

The BFS only adds datasets that are *already in the required set*.
Multi-hop traversal through non-required intermediaries is not
automatic. For example, `total_revenue` by `region.r_name` would require
the caller to include `customer` and `nation` as extra dimensions so
that BFS can chain through them. A future version can add a 2nd phase
that greedily pulls bridge datasets into the required set when the
first BFS stalls.

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

## 7. Simplification strategy

Why in-database, as a stored procedure, instead of a middleware?

| Aspect                    | In-proc (chosen)                             | Middleware (e.g. MetricFlow / Cube / Honeydew) |
| ------------------------- | -------------------------------------------- | ---------------------------------------------- |
| Runtime dependencies      | Zero — runs inside Teradata                  | Python/JVM service, deployment pipeline       |
| Catalog transactionality  | Native — catalog changes are immediately live | Cache invalidation problem                    |
| Governance                | Catalog is inside Teradata — RBAC applies    | External service authorizes separately        |
| SQL execution             | Already on the platform                      | Round-trip: compile remote, send SQL in       |
| Language                  | Teradata SPL + SQL — constrained             | Python / Rust / Go — full freedom             |
| Testability               | Procedural, call-and-inspect                 | Unit-testable objects                         |
| Cross-platform reach      | Teradata only                                | Any supported dialect                         |

The in-proc approach wins when:

- The semantic catalog and the execution target are the same platform
  (our case — Teradata).
- Governance is important (policies on the catalog cascade to compiled
  SQL automatically).
- The user base already has Teradata authentication and doesn't want to
  manage a second auth story.

It loses when:

- You need to target multiple query engines from the same catalog.
  MetricFlow / Cube make sense there because they emit dialect-
  specific SQL from a neutral representation.
- You want the catalog authored and versioned outside the database
  (git as the source of truth).

The OSI YAML export (`sp_export_osi_yaml`) is our escape hatch for the
multi-platform case: any OSI-compatible engine can consume it.

---

## 8. Future evolution

### Near term

1. **JSON request parsing.** Accept the full JSON payload from CLAUDE.md
   directly. Use `NEW JSON(...)` + `JSON_TABLE` to extract arrays, then
   run the same compiler on the normalized form.
2. **Multi-hop bridge expansion.** Add a phase between steps 5 and 6
   that, if any required dataset is unreachable, greedily pulls bridge
   datasets into the required set. Bound it by `max_bridge_hops` to
   avoid combinatorial explosion.
3. **Chasm-trap detection.** See §5 option 1 — emit an error when
   two distinct `MANY_TO_ONE` joins converge at a shared dimension.
4. **Security policy enforcement.** Honor `SECURITY_POLICY.ROW_FILTER`
   by injecting the policy expression into `WHERE` for the session
   user's group.
5. **Result streaming.** `p_execute = 1` opens a cursor on the compiled
   SQL and returns rows as a dynamic result set (Python driver consumes
   it; interactive clients pull from `request_result.result_json`).
6. **Cost hints.** Read the EXPLAIN output, extract estimated row
   counts, and drop them into `request_result` so an agent can decide
   whether to auto-approve execution.

### Medium term

1. **Incremental refresh of metric caches.** For certified SIMPLE
   metrics with a known time grain, the engine can maintain a
   rollup table and re-route `total_revenue by month` to it. Add a new
   entity `METRIC_ROLLUP` that maps `(metric_id, grain) → physical_table`.
2. **Derived metric resolution.** Expand `DERIVED` metrics at compile
   time by recursively substituting constituent metric expressions. The
   `DERIVED` type is declared today but not yet used by the compiler.
3. **Automated OSI round-trip.** Keep an OSI YAML document as a
   notional source of truth; an import procedure loads it into the
   catalog (reverse of `sp_export_osi_yaml`). This lets teams commit
   model changes to git while keeping the live engine in Teradata.

### Long term

1. **Native Teradata `MEASURE()`.** Julian Hyde's work in Apache
   Calcite (SQL 2023 MEASURE semantics) is the clearest direction. When
   Teradata exposes a native measure type, the compilation target
   becomes `SELECT MEASURE(total_revenue) BY o_orderyear FROM ...` and
   the optimizer handles chasm-avoidance automatically. Our catalog
   already carries every piece of metadata a native MEASURE would need;
   the engine becomes a thin translator.
2. **MCP server integration.** Wrap `sp_semantic_search`,
   `sp_semantic_describe`, and `sp_semantic_request` behind an MCP
   server so Claude (and other agents) can call them without knowing
   any SQL. The procedures already return well-typed result sets that
   map cleanly to MCP tool schemas.
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
|                |            | in-proc BFS is conceptually similar, just expressed in    |
|                |            | SPL + catalog tables.                                     |
| Apache Calcite | Apache 2.0 | Long-term target for native MEASURE() semantics;          |
|                |            | Julian Hyde's papers on SQL 2023 MEASURE.                 |

---

## Appendix B — Request-time pseudocode

```
INPUT: p_model_name, p_metrics, p_dimensions,
       p_where_filters, p_having_filters, p_sort, p_row_limit, p_execute

clear_staging()

model_id ← resolve(p_model_name)
for metric_name in split(p_metrics, ','):
    (metric_id, expr, primary_ds) ← resolve_metric(metric_name, model_id)
    request_metric.insert((metric_id, metric_name, expr, primary_ds))
    required_ds.add(datasets_referenced_by(metric_id))

for dim_spec in split(p_dimensions, ','):
    (dataset, field) ← parse_ds_field(dim_spec)
    field_id ← resolve_field(dataset, field, model_id)
    request_dim.insert((field_id, dataset, field, ...))
    required_ds.add(dataset_of(field_id))

anchor ← primary_ds_of_first_metric() OR most_central_required()
mark_in_plan(anchor)
emit "FROM <anchor_physical> AS <anchor_dataset>"

while has_unplanned_required():
    cand ← pick_best_neighbor_of_planned()
    if cand is None: break
    join_sql ← build_join(cand, relationship_id, rel_column_map)
    emit join_sql
    mark_in_plan(cand)

if has_unplanned_required():
    is_valid ← 0
    validation_message ← "unreachable: <list>"

select_list ← emit_dims() ++ emit_metrics()
where ← emit_where_filters(p_where_filters)
group_by ← emit_group_by(request_dim) if request_metric else ''
having ← emit_having_filters(p_having_filters)
order_by ← emit_order_by(p_sort)
top ← emit_top(p_row_limit)

v_sql ← "LOCKING ROW FOR ACCESS\nSELECT " + top + select_list + "\n" +
        "  " + from_clause + where + group_by + having + order_by

try:
    CALL DBC.SysExecSQL('EXPLAIN ' || v_sql)
except:
    is_valid ← 0
    validation_message ← "EXPLAIN failed"

persist(v_sql, is_valid, validation_message, anchor_name, joined_list)
```

---

## Appendix C — File layout

```
semantic-layer/
├── CLAUDE.md                              — task spec
├── semantic_catalog_design_v2.md          — conceptual / logical design
├── sql_compilation_engine_design.md       — this document
└── sql/
    ├── 00_drop_all.sql                    — idempotent drop for re-runs
    ├── 01_ddl_enums.sql                   — reference tables
    ├── 02_ddl_core.sql                    — SEMANTIC_MODEL / DATASET / FIELD / DATASET_KEY
    ├── 03_ddl_relationships.sql           — RELATIONSHIP / REL_COLUMN_MAP
    ├── 04_ddl_metrics.sql                 — METRIC / METRIC_EXPRESSION / METRIC_FIELD_REF
    ├── 05_ddl_views.sql                   — SEMANTIC_VIEW / VIEW_MEMBER
    ├── 06_ddl_metadata.sql                — AI_CONTEXT / FORMAT_SPEC / SECURITY_POLICY / CUSTOM_EXTENSION
    ├── 07_comments.sql                    — all table / column comments
    ├── 08_collect_stats.sql               — statistics seeding
    ├── 09_seed_enums.sql                  — enum seed data
    ├── 10_scenario_tpch_osi.sql           — Scenario A
    ├── 11_scenario_tpch_orders.sql        — Scenario B (Honeydew-style)
    ├── 12_scenario_exec_dashboard.sql     — Scenario C (cube)
    ├── 19_gtt_yaml_tmp.sql                — yaml_tmp buffer table (superseded)
    ├── 20_export_osi.sql                  — sp_export_osi_yaml
    ├── 30_sp_semantic_search.sql          — m_semantic_search (macro)
    ├── 31_sp_semantic_describe.sql        — m_semantic_describe (macro)
    ├── 32_request_staging.sql             — staging tables for compiler
    ├── 33_sp_semantic_request.sql         — sp_semantic_request (the compiler)
    └── run_sp.py                          — helper to compile stored objects
                                            (tq splits on ';' inside SP bodies)
```
