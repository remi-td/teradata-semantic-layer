# Semantic Catalog — Design Guidelines

This document describes the common modelling patterns supported by the
catalog and when to use each. Treat it as a decision manual; the examples
under `examples/` are working references for every pattern here.

---

## Table of contents

1. [Core entities recap](#core-entities-recap)
2. [Pattern A — Simple metric on one fact table](#pattern-a--simple-metric-on-one-fact-table)
3. [Pattern B — Filtered-rollup metrics (one base, many variants)](#pattern-b--filtered-rollup-metrics-one-base-many-variants)
4. [Pattern C — Role-played dimensions](#pattern-c--role-played-dimensions)
5. [Pattern D — Cube-first / Level-0 model](#pattern-d--cube-first--level-0-model)
6. [Pattern E — Chasm trap (two separate fact grains)](#pattern-e--chasm-trap-two-separate-fact-grains)
7. [Pattern F — Dimension hierarchy metadata](#pattern-f--dimension-hierarchy-metadata)
8. [Anti-patterns — what not to do](#anti-patterns--what-not-to-do)
9. [Decision checklist](#decision-checklist)
10. [Not yet supported](#not-yet-supported)

---

## Core entities recap

The catalog stores four things per model:

| Entity | What it represents |
|---|---|
| `DATASET` | A table, a view, or an inline SELECT exposed as a queryable object |
| `FIELD` | A column on a dataset (key, dimension, or measure source) |
| `METRIC` | An aggregate expression + its metadata (additivity, certification, AI context) |
| `RELATIONSHIP` | A join between two datasets (with optional `role_name` for disambiguation) |

On top of those, `SEMANTIC_VIEW` + `VIEW_MEMBER` curate a consumer-facing
projection; `AI_CONTEXT`, `FORMAT_SPEC`, etc. attach soft metadata.

`sp_semantic_request` is the compiler. Given a request shape
`{model, metrics[], dimensions[], where[], having[], sort, limit}` it
returns fully-formed Teradata SQL.

---

## Pattern A — Simple metric on one fact table

**Use when:** a metric is a straightforward aggregate of one column on
one fact, possibly sliced by dimensions from its own table.

**Example (TPC-H, `tpch_orders`):**

```
METRIC revenue
  expression: SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))
  primary_dataset: lineitem
  field_refs: [lineitem.l_extendedprice, lineitem.l_discount]
```

**Query:**
```json
{
  "model": "tpch_orders",
  "metrics": ["revenue"],
  "dimensions": ["lineitem.l_returnflag"]
}
```

**Compiles to:**
```sql
SELECT lineitem.l_returnflag,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM ... lineitem
 GROUP BY lineitem.l_returnflag
```

**Rule of thumb:** this is the default shape. Don't reach for anything
more elaborate unless you need to. Populate `METRIC_EXPRESSION` with the
full SQL and `METRIC_FIELD_REF` with every column it consumes (this
drives join resolution).

---

## Pattern B — Filtered-rollup metrics (one base, many variants)

**Use when:** you need several curated KPIs that all share the same
aggregate function over the same column, differing only in a dimension
predicate. The canonical case: one measure (`amount`, `score`, `count`)
and a hierarchy dim whose members you want to expose as distinct named
metrics (e.g. `exam_score_avg`, `homework_score_avg`,
`final_exam_score_avg`, all derived from `score_avg`).

**Definition shape:**

```sql
-- Base metric: aggregate_fn and aggregate_arg populated
INSERT INTO METRIC (..., aggregate_fn, aggregate_arg)
VALUES ('score_avg', ..., 'AVG', 'assessment.score');

-- Filtered variant: base_metric_id FK + METRIC_FILTER rows
INSERT INTO METRIC (..., base_metric_id)
VALUES ('exam_score_avg', ..., <score_avg's id>);

INSERT INTO METRIC_FILTER (metric_id, filter_ord, field_id, op, filter_value)
VALUES (<exam_score_avg id>, 1, <assessment_type.category_lvl1 field_id>,
        '=', '''EX''');
```

**Query:**
```json
{
  "model": "school_gradebook",
  "metrics": ["score_avg", "exam_score_avg", "homework_score_avg"],
  "dimensions": ["student.major"]
}
```

**Compiles to:**
```sql
SELECT student.major,
       AVG(assessment.score)                                              AS score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END)                               AS exam_score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'HW'
                 THEN assessment.score END)                               AS homework_score_avg
  FROM demo_user.gb_assessment      AS assessment
  JOIN demo_user.gb_student         AS student
    ON assessment.student_id = student.student_id
  JOIN demo_user.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY student.major
```

Note how the compiler:
- preserves the plain aggregate for the base metric,
- wraps filtered variants in `CASE WHEN <filters> THEN arg ELSE <default> END`,
  where the default is `0` for `SUM` and `NULL` for `AVG` / `MIN` / `MAX` /
  `COUNT` / `COUNT_DISTINCT`,
- auto-joins the dataset(s) referenced by the filters (once, even when
  many variants use the same dim).

**Multi-predicate filters** — stack ordinals:

```sql
-- senior_exam_score_avg = score_avg WHERE category_lvl1='EX' AND class_year=4
INSERT INTO METRIC_FILTER VALUES (<mid>, 1, <cat_lvl1 field>, '=', '''EX''');
INSERT INTO METRIC_FILTER VALUES (<mid>, 2, <class_year field>, '=', '4');
```

The compiler ANDs them and auto-joins both filter datasets. See
`tests/cases/13_filtered_metrics.yaml` (FM03) for a worked example.

**When NOT to use this pattern:**
- If you'd be defining more than a dozen filtered variants on the **same
  hierarchy**, you probably want a dimension-driven rollup instead —
  register the hierarchy column as a FIELD and let the caller
  `GROUP BY` it. See the anti-pattern section.
- If the variants differ by an arithmetic expression (not just a filter
  predicate), use a plain `METRIC_EXPRESSION`.

---

## Pattern C — Role-played dimensions

**Use when:** two relationships exist between the same pair of datasets
with different semantic meaning — e.g. `orders.o_custkey → customer`
(the buyer) and `orders.o_billing_custkey → customer` (the billed
party). Without a role, an agent asking for `customer.c_mktsegment`
cannot know which edge to take.

**Definition:** set `role_name` on `RELATIONSHIP`. A unique index
enforces one role per (from, to, role).

```sql
INSERT INTO RELATIONSHIP (..., relationship_name, role_name, ...)
VALUES (..., 'orders_placed_by_customer', 'placed_by', ...);

INSERT INTO RELATIONSHIP (..., relationship_name, role_name, ...)
VALUES (..., 'orders_billed_to_customer', 'billed_to', ...);
```

**Query syntax:** caller prefixes the dim with the role name instead
of the dataset name: `placed_by.c_mktsegment` vs `billed_to.c_mktsegment`.

**Ambiguity detection:** if a caller names a dim on a dataset that has
multiple incoming relationships (none pinned by role), the compiler
fails with an explicit `AMBIGUOUS_PATH` error listing the available
roles. No silent "pick the first edge" behavior.

See `examples/tpch_orders/11_scenario_tpch_orders.sql` for a full
working example, and `tests/cases/05_role_playing.yaml` for regression
cases.

---

## Pattern D — Cube-first / Level-0 model

**Use when:** you have an existing BI report or data-science output
and want to expose it as a semantic entity immediately, without
spending days modelling the underlying entity graph.

**Definition:** register a single DATASET whose `source_query` is the
full multi-join SQL, and attach FIELDs + METRICs to that single cube.
No RELATIONSHIPS.

```sql
INSERT INTO DATASET (..., source_query)
VALUES ('sales_cube', ..., 'SELECT ... FROM sales.orders o JOIN ...');
```

The compiler wraps `source_query` as `(<query>) AS dataset_name` in the
FROM clause. No join resolution happens because there's only one
dataset.

**Trade-off:** you get analytics immediately but can't compose the cube
with other datasets. Upgrade path: once you decompose the cube into
real fact + dim datasets, swap `source_query` for `DataBaseName` +
`TableName` and add RELATIONSHIPs. Existing queries keep working.

See `examples/exec_dashboard/` for a concrete example.

---

## Pattern E — Chasm trap (two separate fact grains)

**Use when:** a single request asks for metrics from two different
fact tables (different grains) that share some dimensions.

**Typical shape:** retail analytics asking for `revenue` (from
`orders`) AND `inventory_balance` (from `inventory_snapshot`) by the
same `product.category` dim. A naive INNER JOIN multiplies rows and
corrupts both metrics.

**Compiler behavior:** when `request_metric` rows show two different
`primary_dataset_id` values, the compiler emits one sub-SELECT per
grain and `FULL OUTER JOIN`s them on the common dimensions. The
`is_valid` flag is set to 1 with a `CHASM_WARNING` validation
message so the caller knows the shape was non-trivial.

See `examples/tpch_orders/52_chasm_scenario_metrics.sql` and
`tests/cases/06_chasm_trap.yaml`.

---

## Pattern F — Dimension hierarchy metadata

**Use when:** a model has columns that form a drill-up/drill-down
chain (e.g. `product_category` → `product_subcategory` → `product`)
and you want the GUI or an agent to know they're related.

**Definition:** register a `FIELD_HIERARCHY` + one
`FIELD_HIERARCHY_LEVEL` row per level, in top-down order.

```sql
INSERT INTO FIELD_HIERARCHY (model_id, hierarchy_name, description)
VALUES (..., 'assessment_category', '...');

INSERT INTO FIELD_HIERARCHY_LEVEL (hierarchy_id, level_ord, field_id, level_name)
VALUES (<hid>, 1, <category_lvl1 field_id>, 'Category');
INSERT INTO FIELD_HIERARCHY_LEVEL
VALUES (<hid>, 2, <category_lvl2 field_id>, 'Sub-category');
```

**What the compiler does with it:** nothing. This is **metadata only**.
Compiled SQL is identical whether or not a hierarchy is registered.
The data is surfaced through:

- the tree / graph API endpoints, so a GUI can render drill-down links
- the AI-context / search interface, so an agent knows "Subcategory
  rolls up to Category" without having to infer it from naming

**Rule of thumb:** register hierarchies for your curated dimensions
(where drill-down is business-meaningful). Skip for keys and opaque
codes.

---

## Anti-patterns — what not to do

### Anti-pattern 1 — Enumerate every dim-member as a separate METRIC

**Bad:**

```sql
METRIC exam_score_avg_freshmen   filter: category='EX', year=1
METRIC exam_score_avg_sophomores filter: category='EX', year=2
METRIC exam_score_avg_juniors    filter: category='EX', year=3
METRIC exam_score_avg_seniors    filter: category='EX', year=4
METRIC hw_score_avg_freshmen     filter: category='HW', year=1
...
(16 metrics)
```

**Good:**

```sql
METRIC exam_score_avg filter: category='EX'
METRIC hw_score_avg   filter: category='HW'
```

Callers pass `dimensions: [student.class_year]` and get one row per
year with the filtered metrics as columns. The cross-product
materialises at query time, not at metadata time.

**Rule:** if the only difference between two candidate metrics is a
filter value on a dim the caller will naturally group by, skip the
metric — use a dim. **Reserve named metrics for concepts the business
calls by name** (NII, Exam Avg, Total Revenue) — not every cell of a
cross-tab.

### Anti-pattern 2 — Copy-paste CASE-WHEN filters across metrics

**Bad:**

```sql
METRIC exam_score_avg
  expression: AVG(CASE WHEN assessment_type.category_lvl1='EX'
                        THEN assessment.score END)
METRIC senior_exam_score_avg
  expression: AVG(CASE WHEN assessment_type.category_lvl1='EX'
                         AND student.class_year=4
                        THEN assessment.score END)
```

If you later change the filter (say, category also admits 'EX_ALT'),
you have to touch every metric.

**Good:** use Pattern B (`base_metric_id` + `METRIC_FILTER`). The
filter lives in one place per variant, the base aggregate lives in one
place overall.

### Anti-pattern 3 — Role-played dim without `role_name`

**Bad:**

```sql
RELATIONSHIP (..., relationship_name='orders_placed',   role_name=NULL)
RELATIONSHIP (..., relationship_name='orders_billed',   role_name=NULL)
-- same (from, to) pair, no roles
```

A caller requesting `customer.c_mktsegment` can't know which edge
to take. Today's compiler will refuse with `AMBIGUOUS_PATH`; a less
strict design would silently pick one, giving wrong numbers.

**Good:** populate `role_name` on both (e.g. `placed_by`, `billed_to`).
See Pattern C.

### Anti-pattern 4 — Metric-in-metric references via SQL copy-paste

**Bad:**

```sql
METRIC spread_bps
  expression: "SUM(CASE WHEN vt='NII' THEN amount END)
             / NULLIFZERO(SUM(CASE WHEN vt='NBR' THEN amount END))
             * 10000"
```

If the definition of the NII filter changes (add a `commercial='Y'`
clause, say), SPREAD silently goes stale.

**Status in the catalog today:** no first-class metric-in-metric
reference mechanism exists. Workarounds:
- Write the full expression inline and rely on a reviewer to catch drift.
- Use a CTE-like pattern by referring to a physical view that implements
  the base metric.

See [Not yet supported](#not-yet-supported).

---

## Decision checklist

Before adding a new METRIC, ask:

1. **Is there an existing base metric whose only difference from mine is
   a filter predicate on a dimension?** → Use Pattern B
   (`base_metric_id` + `METRIC_FILTER`).

2. **Would my metric's only purpose be to expose a single dim-member
   value that the caller could request with `GROUP BY`?** → Don't add
   the metric; use a dim. (Anti-pattern 1.)

3. **Does my metric depend on another named metric arithmetically
   (ratio, delta, contribution)?** → Write the full SQL in
   `METRIC_EXPRESSION` and flag for review. No metric-in-metric
   references yet. (Anti-pattern 4.)

4. **Does the metric cross two different fact grains?** → Keep the two
   metrics separate. The compiler detects the chasm and emits a safe
   FULL OUTER JOIN. (Pattern E.)

5. **Are there multiple paths from the request's dims to my metric's
   primary dataset?** → Decide whether those paths are semantically
   identical or role-played. If the latter, populate `role_name`
   (Pattern C); if the former, add a `CUSTOM_EXTENSION` note so
   reviewers know the path is deterministic.

---

## Not yet supported

Documented here so they don't surprise a future reader:

- **Runtime metric-in-metric substitution** (`${NII} / ${NBR}`).
  Considered but deferred: the recursive expander is a poor fit for
  stored-procedure compilation logic. Revisit when the compiler moves
  to Python. Import-time expansion remains possible as a lighter
  alternative.

- **Cypher-style multi-hop role prefixes** (`orders.placed_by.customer.
  nation.name`). Current syntax handles single-role dot prefixes;
  deep paths require the caller to break the request into intermediate
  dims.

- **Metric-level security / row-level filters** not tied to the
  `WHERE` filter in the request shape. The `SECURITY_POLICY` table
  exists but the compiler does not yet consume it.

- **`sp_semantic_import` support for `base_metric_id`, `aggregate_fn`,
  `aggregate_arg`, `METRIC_FILTER`, `FIELD_HIERARCHY`.** The DB-side
  DDL and compiler are Phase 1/3-ready, but the JSON import SP still
  expects the pre-Phase-1 metric shape. Direct SQL inserts work today
  (see `examples/school_gradebook/`); GUI import will be extended
  after user feedback on the core compiler path.

- **Time grain on filtered metrics.** The dim-side `:GRAIN` suffix
  (DAY/WEEK/MONTH/...) is supported in requests. Applying time-grain
  to the filter predicate of a filtered metric — e.g. "count exams
  in the last 30 days" — requires the caller to pass the time window
  as a `where` filter, not as a property of the metric itself. This
  matches the separation-of-concerns principle (metric = what,
  filter = scope).
