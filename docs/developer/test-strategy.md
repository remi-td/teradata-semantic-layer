# Test Strategy — Teradata Semantic Catalog

A plain-English guide to how we test the semantic layer. Written for data
engineers, analysts, and anyone who wants to reason about whether a given
question is one the catalog can answer *correctly*.

---

## TL;DR

- The thing we test is `sp_semantic_request` — the stored procedure that
  turns **request** (metrics + dimensions + filters) into **Teradata SQL**.
- We run adversarial cases drawn from the classic dimensional-modelling
  "traps": fan-out, chasm trap, role-playing, multi-hop graphs, ratio
  metrics with HAVING, time-grain rollups, cube scenarios.
- Every test carries a **hand-written reference SQL** that an experienced
  data architect considers correct. We compare the catalog's compiled SQL
  result-set against the reference, column-order independent.
- Tests live in `tests/cases/*.yaml` and are easy to add: drop a new case
  into any YAML and run `python3 tests/run_tests.py`.
- Outcomes are classified (PASS, SEMANTIC_WRONG, RUNTIME_ERROR, …) and the
  report explicitly distinguishes **"this matched expectation"** from
  **"this is correct."** A known-wrong behaviour can be MATCH with
  expected=SEMANTIC_WRONG, flagging a shortcoming we've documented.

---

## Why test a semantic layer at all?

A semantic layer is a **translator**. The user writes

> revenue, by region

and expects SQL like

```sql
SELECT region.r_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem
  JOIN demo_user.orders   ON …
  JOIN demo_user.customer ON …
  JOIN demo_user.nation   ON …
  JOIN demo_user.region   ON …
 GROUP BY region.r_name;
```

When the translation works, the analyst is happy. When it silently picks the
wrong JOIN path, the number is *wrong*, the dashboard shows it with
confidence, and the business makes decisions based on a lie. Semantic layers
fail **quietly**. That's what this suite is designed to prevent.

---

## The twelve shapes we test

We organise the suite into twelve folders under `tests/cases/`. Each file is a
category — the table below maps each one to the class of bug it protects
against.

| # | Folder (YAML)                       | What it tests                                       | Why it matters                                                       |
|---|-------------------------------------|-----------------------------------------------------|----------------------------------------------------------------------|
| 1 | `01_baseline.yaml`                  | Canonical star traversal (2-hop & 5-hop)            | Sanity — if these break, everything breaks.                         |
| 2 | `02_filters.yaml`                   | WHERE filters: DATE, LIKE, IN, unquoted, cross-set   | Most visible class of user-facing bugs; also guards F1 & F2 fixes. |
| 3 | `03_ratio_and_having.yaml`         | Ratio-style metrics with NULLIFZERO; HAVING on ratio | Division-safe metrics; HAVING expression substitution.              |
| 4 | `04_path_resolution.yaml`           | Auto-include intermediates; ambiguous two-path      | The compiler should walk lineitem→…→region with no prompting.       |
| 5 | `05_role_playing.yaml`              | customer_nation vs supplier_nation; both in one SQL  | Kimball role-playing dim — the archetypal intermediate-level bug. |
| 6 | `06_chasm_trap.yaml`                | Two metric grains through a shared dim              | Canonical "same dashboard, two wrong numbers" trap.                 |
| 7 | `07_fanout.yaml`                    | COUNT DISTINCT across 1:N fan-out                    | Shows that `count_orders` is safe under fan-out.                    |
| 8 | `08_time_grain.yaml`                | `:MONTH`, `:QUARTER`, `:YEAR` rollups               | Grain is the #1 ergonomic ask from BI users.                        |
| 9 | `09_edge_shapes.yaml`               | Metric-only scalar; dim-only DISTINCT               | Often used by agents to populate filter UIs or dashboards.          |
| 10 | `10_sort_limit.yaml`               | TOP N + ORDER BY on a metric alias                   | Any "top customers" query.                                          |
| 11 | `11_metric_driven_join.yaml`       | Metric pulls in a dataset not in dims                | promo_revenue needs `part`; the compiler must auto-include it.      |
| 12 | `12_cube_source_query.yaml`        | `DATASET.source_query` (cube scenario)              | Level-0 maturity — "pre-canned cube" start point.                   |

---

## A tour of the classic traps — with examples

These are the semantic bugs we specifically look for. Each one has a short
sketch here and at least one test case.

### Fan-out join

Joining from a fact at grain A to a dim at grain B produces one row per
(A,B) pair. If you now sum a field whose grain was A, you double-count.

> Example: `orders` has 20 rows. `lineitem` has 34 rows linked to orders.
> Join lineitem → orders and do `SUM(orders.o_totalprice)`. You sum one
> order's price once for every lineitem it has. Wrong.

Defense: metric definitions for `count_orders` use `COUNT(DISTINCT
orders.o_orderkey)`. `FO01` verifies that even adding lineitem dims doesn't
throw it off.

### Chasm trap

Two fact tables share a dimension. Join both to the dim at once, and **both
sums fan out through each other**.

```
            part
            /   \
    lineitem     partsupp
```

> Asking for `revenue` (lineitem) AND `total_availqty` (partsupp) by
> `part.p_name` in one SQL gives both numbers wrong. No GROUP BY fixes it.

Defense: the catalog refuses the request with a `CHASM_WARNING` message
(is_valid = 0). The caller is expected to split into two per-grain queries
and merge client-side. `C01` verifies this refusal. A proper symmetric-aggregate
sub-SELECT pattern is future work (documented in `workflow-review.md`).

### Role-playing dimension

One physical table (`nation`) used in two roles: customer's nation and
supplier's nation. The user needs to say **which**.

> `SELECT supplier_nation.n_name, customer_nation.n_name FROM lineitem`
> needs the `nation` table in the FROM clause **twice** with different
> aliases.

Defense: `RELATIONSHIP.role_name` pins an edge to a role. Request syntax
`supplier_nation.n_name` tells the compiler to use that edge. Two roles in
one request produces a SQL with two self-joins of `nation`. Tested by
`RP01`, `RP02`, `RP03`.

### Multi-hop graphs (BFS)

A request that names only the final dim (e.g. `region.r_name`) requires the
compiler to auto-walk intermediate datasets (`orders`, `customer`, `nation`)
on the way from the anchor (`lineitem`) to the target.

Defense: F4 auto-include adds any dataset adjacent to the current plan that
is on the shortest path to an unreached required dataset. `P01` verifies a
5-hop auto-walk.

### Ambiguous two-path

A dataset can be reached by **two** edges: direct (lineitem → supplier via
`l_suppkey`) or indirect (lineitem → partsupp → supplier). The indirect
path fans out by the number of part-supplier pairs.

Defense: the BFS prefers MANY_TO_ONE direct edges. `P02` asserts the direct
edge is taken and the numbers match a hand-written direct-join SQL.

### Ratio metrics with HAVING

`promo_share = promo_revenue / total_revenue`. Filtering on a ratio in
HAVING needs the ratio expression to be substituted into HAVING, not
referenced by alias (Teradata disallows that).

Defense: `R01`, `R02` check that `HAVING (expr_A) / NULLIFZERO(expr_B) > 0.1`
is emitted verbatim and returns expected rows.

### Time-grain rollups

`orders.o_orderdate:MONTH` wraps the column with `TRUNC(col, 'MM')` in both
SELECT and GROUP BY. Also applies to `:QUARTER` and `:YEAR`.

Defense: `TG01`–`TG04`.

### Cube datasets (source_query)

Some datasets aren't tables — they're SQL queries (e.g. a curated cube
behind a BI dashboard). The FROM clause must wrap `(source_query) AS alias`.

Defense: `CB01`. The test asserts the *shape* (derived-table FROM); rows
can't be verified on the sandbox because the cube's physical tables don't
exist there.

---

## How a test case is structured

Each case is a YAML block. Here's a minimal example:

```yaml
- id: B01
  title: Revenue by customer market segment (2-hop)
  category: Baseline
  request:
    model: tpch_orders
    metrics: revenue
    dimensions: orders.o_orderpriority,customer.c_mktsegment
  expected_sql: |
    SELECT orders.o_orderpriority, customer.c_mktsegment,
           SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
      FROM demo_user.lineitem AS lineitem
      JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
      JOIN demo_user.customer AS customer ON orders.o_custkey   = customer.c_custkey
     GROUP BY orders.o_orderpriority, customer.c_mktsegment
  expected: PASS
  notes: Canonical fact → dim traversal with two intermediate hops.
```

- `id` — short stable tag (used to skip-filter from the command line).
- `request` — positional args to `sp_semantic_request`.
- `expected_sql` — the hand-written reference. **This is the contract.**
  The compiler's output doesn't have to be textually identical; it just
  has to return the same rows.
- `expected` — one of `PASS | SEMANTIC_WRONG | RUNTIME_ERROR |
  COMPILE_REJECTED | NOT_SUPPORTED`. Choose what you **believe today's
  compiler does**; the harness tells you if reality agrees.
- `notes` — free-form rationale.

---

## Adding a new case — worked example

Say you want to verify "revenue by nation name, for any customer whose
market segment is BUILDING". Drop this into
`tests/cases/02_filters.yaml`:

```yaml
- id: F06
  title: Revenue by nation, filtered to BUILDING mkt segment
  category: Filters
  request:
    model: tpch_orders
    metrics: revenue
    dimensions: nation.n_name
    where: "customer.c_mktsegment|=|'BUILDING'"
  expected_sql: |
    SELECT nation.n_name,
           SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
      FROM demo_user.lineitem AS lineitem
      JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
      JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
      JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
     WHERE customer.c_mktsegment = 'BUILDING'
     GROUP BY nation.n_name
  expected: PASS
```

Run it:

```bash
python3 tests/run_tests.py F06
```

If the harness classifies it `PASS`, your reference and the compiler agree.
If it comes back `SEMANTIC_WRONG`, you've found a real divergence — the
harness prints up to three sample rows that are in one but not the other,
which usually points straight at the bug.

---

## How to run

```bash
# everything
python3 tests/run_tests.py

# one category (substring match on id / category / filename stem)
python3 tests/run_tests.py role

# single case by id
python3 tests/run_tests.py --only TG02

# write the report to a custom path
python3 tests/run_tests.py --report /tmp/today.md
```

The runner writes a markdown report (default `test-reports/test-results.md`,
gitignored). Each case section contains:

1. the input request
2. the compiled SQL (what sp_semantic_request produced)
3. the compiled SQL's results
4. the reference SQL
5. the reference SQL's results
6. verdict + up to 3 sample diverging rows if any

At the end: a summary table, outcome distribution, expectation agreement,
and a mismatch list.

---

## JSON client (for agents and notebooks)

Semantic layers are usually called from agents, notebooks, and apps —
which prefer JSON to pipe-delimited strings. `tests/client.py` is a
self-contained Python helper that:

- accepts a structured JSON payload (model, metrics, dimensions, typed
  filters with `type: date|number|string|raw`, IN lists, sort, limit),
- encodes each value correctly (single-quoted strings, DATE literals,
  parenthesised IN lists),
- calls `sp_semantic_request` with positional args,
- returns `{sql, is_valid, message, anchor, joined, translated}`.

Agent code looks like this:

```python
from tests.client import compile_from_json
import teradatasql

conn = teradatasql.connect(host="…", user="…", password="…")
cur  = conn.cursor()

result = compile_from_json(cur, {
    "model": "tpch_orders",
    "metrics": ["revenue"],
    "dimensions": ["region.r_name", "orders.o_orderdate:MONTH"],
    "where": [{"field": "lineitem.l_shipdate", "op": ">=",
               "value": "1995-01-01", "type": "date"}],
    "sort":   [{"field": "revenue", "direction": "DESC"}],
    "limit":  10
})
print(result["sql"])
```

Running `python3 tests/client.py` executes a self-test end-to-end.

---

## Outcome classes — what they mean

| Outcome            | Compiled? | SQL runs? | Rows match ref? | Interpretation                                        |
|--------------------|-----------|-----------|-----------------|-------------------------------------------------------|
| `PASS`             | ✓         | ✓         | ✓               | The catalog gave the right answer.                   |
| `SEMANTIC_WRONG`   | ✓         | ✓         | ✗               | Dangerous — caller gets a plausible-but-wrong result. |
| `RUNTIME_ERROR`    | ✓         | ✗         | —               | Compile succeeded but DB rejected at execute time.   |
| `COMPILE_REJECTED` | partial   | —         | —               | `is_valid=0` — engine refused with a clear message. |
| `NOT_SUPPORTED`    | ✗         | —         | —               | Engine produced no SQL at all.                      |

**A `COMPILE_REJECTED` is often the best outcome** for a known-hard case —
far better than a silent `SEMANTIC_WRONG`. The chasm-trap test C01 is
deliberately tagged `expected: COMPILE_REJECTED`.

---

## Extending: adding a new category

1. Create `tests/cases/13_your_category.yaml`:
   ```yaml
   category: Your category
   description: >
     One paragraph — what class of problem this probes.

   cases:
     - id: YC01
       title: "…"
       category: …
       request:   { … }
       expected_sql: | …
       expected: PASS
   ```
2. `python3 tests/run_tests.py your_category` to see it run.
3. If the compiler fails in a **new** way, file a finding by adding a
   note on the case (`notes:`), set `expected` to the actual outcome,
   and open a ticket/PR with the root cause.

---

## What this suite deliberately does *not* do

- **Performance.** No SLA checks, no execution-plan assertions.
- **Concurrency / session isolation.** Single-session sanity only.
- **Schema migrations.** Catalog schema is assumed stable between test
  runs. A schema change that breaks request parsing would surface as many
  test failures simultaneously — design-intentional.
- **Agent behaviour.** We don't test LLM prompting or tool choice; only
  what the compiler does with a well-formed request.

These are appropriate for future, separate test suites.
