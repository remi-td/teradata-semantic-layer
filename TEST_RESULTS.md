# Test Results — Teradata Semantic Catalog

- Run against `demo_user@mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com`
- Cases loaded: **32** × 2 engine(s)  
- Engines: sql, python
- Source: `/Users/remi.turpaud/Code/semantic-layer/tests/cases/*.yaml`

## Case results


### B01 — Revenue by customer market segment (2-hop) _(engine=sql)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Canonical fact → dim traversal with two intermediate hops.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### B02 — Single-table AVG (avg_qty by return flag) _(engine=sql)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'avg_qty'`
- `dimensions` = `'lineitem.l_returnflag,lineitem.l_linestatus'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT lineitem.l_returnflag AS l_returnflag, lineitem.l_linestatus AS l_linestatus, AVG(lineitem.l_quantity) AS avg_qty
  FROM sem_engine.lineitem AS lineitem GROUP BY lineitem.l_returnflag, lineitem.l_linestatus
```

**Compiled-SQL results:**
| l_returnflag | l_linestatus | avg_qty |
| --- | --- | --- |
| A  | F  | 32 |
| N  | O  | 27.3684 |
| R  | F  | 32.3077 |

**Reference SQL:**
```sql
SELECT lineitem.l_returnflag, lineitem.l_linestatus,
       AVG(lineitem.l_quantity) AS avg_qty
  FROM sem_engine.lineitem AS lineitem
 GROUP BY lineitem.l_returnflag, lineitem.l_linestatus
```

**Reference results:**
| l_returnflag | l_linestatus | avg_qty |
| --- | --- | --- |
| A  | F  | 32 |
| N  | O  | 27.3684 |
| R  | F  | 32.3077 |

**Outcome:** PASS — rows match reference.


### B03 — 5-hop traversal with all intermediates named (revenue by region) _(engine=sql)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F01 — Date filter with DATE literal _(engine=sql)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"lineitem.l_shipdate|>=|DATE '1995-01-01'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F02 — LIKE filter (priority starts with 1-) _(engine=sql)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"orders.o_orderpriority|LIKE|'1-%'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F03 — IN list (post-F1 — caller supplies parens, compiler does not wrap) _(engine=sql)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F1 compiler bug — now fixed.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderstatus'`
- `where` = `"orders.o_orderstatus|IN|('O','F')"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F04 — Filter on region.r_name with region not in dims (F2 auto-include) _(engine=sql)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F2 compiler bug — region dataset is now auto-included from the WHERE.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`
- `where` = `"region.r_name|=|'AMERICA'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F05 — Unquoted string value (caller error — must still fail cleanly) _(engine=sql)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `RUNTIME_ERROR`  
**Notes:** This is a caller error — `O` is interpreted by Teradata as a column reference. Protocol requires string pre-quoting. We keep the test to document the failure mode.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'orders.o_orderstatus'`
- `where` = `'orders.o_orderstatus|=|O'`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT orders.o_orderstatus AS o_orderstatus, COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM sem_engine.orders AS orders WHERE orders.o_orderstatus = O GROUP BY orders.o_orderstatus
```

**Runtime error on compiled SQL:** `[Version 20.0.0.56] [Session 5211] [Teradata Database] [Error 5628] Column O not found in sem_engine.orders.`

**Outcome:** RUNTIME_ERROR


### R01 — promo_share by region (5-hop + part) _(engine=sql)_

**Category:** Ratio  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### R02 — HAVING promo_share > 0.1 _(engine=sql)_

**Category:** HAVING  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,nation.n_name'`
- `having` = `'promo_share|>|0.1'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### P01 — Auto-intermediates — revenue by region with NO intermediates named _(engine=sql)_

**Category:** BFS  
**Source:** `04_path_resolution.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Before F4 this returned "Could not resolve join path for datasets: region".

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'region.r_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, nation, region`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT region.r_name AS r_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem 
    INNER JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN sem_engine.nation AS nation ON customer.c_nationkey = nation.n_nationkey 
    INNER JOIN sem_engine.region AS region ON nation.n_regionkey = region.r_regionkey GROUP BY region.r_name
```

**Compiled-SQL results:**
| r_name | revenue |
| --- | --- |
| MIDDLE EAST | 198552.65 |
| EUROPE | 219317.89 |
| AMERICA | 428082.7682 |
| ASIA | 45208.64 |

**Reference SQL:**
```sql
SELECT region.r_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN sem_engine.region   AS region   ON nation.n_regionkey = region.r_regionkey
 GROUP BY region.r_name
```

**Reference results:**
| r_name | revenue |
| --- | --- |
| MIDDLE EAST | 198552.65 |
| EUROPE | 219317.89 |
| AMERICA | 428082.7682 |
| ASIA | 45208.64 |

**Outcome:** PASS — rows match reference.


### P02 — Ambiguous path — revenue by supplier direct, NOT via partsupp _(engine=sql)_

**Category:** Ambiguous path  
**Source:** `04_path_resolution.yaml`  
**Expected outcome:** `PASS`  
**Notes:** lineitem has TWO paths to supplier — direct (l_suppkey) and via partsupp (l_partkey + l_suppkey → partsupp → supplier). The compiler should pick the direct MANY_TO_ONE edge. Taking the partsupp path would inflate revenue by the partsupp fan-out.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'supplier.s_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "supplier.s_name" has 2 paths to supplier (roles: lineitem_to_supplier,  partsupp_to_supplier). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### RP01 — Role pin — customer_nation.n_name _(engine=sql)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, nation AS customer_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer_nation.n_name AS customer_nation_n_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem 
    INNER JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN sem_engine.nation AS customer_nation ON customer.c_nationkey = customer_nation.n_nationkey GROUP BY customer_nation.n_name
```

**Compiled-SQL results:**
| customer_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 264700.12 |
| IRAQ | 78325.1 |
| JAPAN | 17220.8 |
| GERMANY | 105986.17 |
| INDIA | 27987.84 |
| FRANCE | 113331.72 |
| BRAZIL | 10471.68 |
| CANADA | 17252 |
| ARGENTINA | 135658.9682 |
| EGYPT | 120227.55 |

**Reference SQL:**
```sql
SELECT nation.n_name AS customer_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
 GROUP BY nation.n_name
```

**Reference results:**
| customer_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 264700.12 |
| IRAQ | 78325.1 |
| JAPAN | 17220.8 |
| GERMANY | 105986.17 |
| INDIA | 27987.84 |
| FRANCE | 113331.72 |
| BRAZIL | 10471.68 |
| CANADA | 17252 |
| ARGENTINA | 135658.9682 |
| EGYPT | 120227.55 |

**Outcome:** PASS — rows match reference.


### RP02 — Role pin — supplier_nation.n_name _(engine=sql)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, supplier, nation AS supplier_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT supplier_nation.n_name AS supplier_nation_n_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem 
    INNER JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey 
    INNER JOIN sem_engine.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey GROUP BY supplier_nation.n_name
```

**Compiled-SQL results:**
| supplier_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 210414.8644 |
| IRAQ | 76042.88 |
| JAPAN | 66707.55 |
| GERMANY | 80919.2082 |
| INDIA | 167322.568 |
| FRANCE | 84161.9256 |
| BRAZIL | 35308 |
| ARGENTINA | 104061.86 |
| EGYPT | 66223.092 |

**Reference SQL:**
```sql
SELECT nation.n_name AS supplier_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN sem_engine.nation   AS nation   ON supplier.s_nationkey = nation.n_nationkey
 GROUP BY nation.n_name
```

**Reference results:**
| supplier_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 210414.8644 |
| IRAQ | 76042.88 |
| JAPAN | 66707.55 |
| GERMANY | 80919.2082 |
| INDIA | 167322.568 |
| FRANCE | 84161.9256 |
| BRAZIL | 35308 |
| ARGENTINA | 104061.86 |
| EGYPT | 66223.092 |

**Outcome:** PASS — rows match reference.


### RP03 — BOTH roles in one query — nation joined twice with different aliases _(engine=sql)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Canonical Kimball role-playing — both roles in one SQL, self-joined nation.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer_nation.n_name,supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, supplier, nation AS supplier_nation, nation AS customer_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT supplier_nation.n_name AS supplier_nation_n_name, customer_nation.n_name AS customer_nation_n_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem 
    INNER JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey 
    INNER JOIN sem_engine.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey 
    INNER JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN sem_engine.nation AS customer_nation ON customer.c_nationkey = customer_nation.n_nationkey GROUP BY supplier_nation.n_name, customer_nation.n_name
```

**Compiled-SQL results:**
| supplier_nation_n_name | customer_nation_n_name | revenue |
| --- | --- | --- |
| UNITED STATES | IRAQ | 47215 |
| FRANCE | UNITED STATES | 60295.0056 |
| GERMANY | BRAZIL | 10471.68 |
| GERMANY | ARGENTINA | 23070.4482 |
| UNITED STATES | EGYPT | 53520 |
| EGYPT | ARGENTINA | 38235.252 |
| IRAQ | UNITED STATES | 19355.38 |
| BRAZIL | UNITED STATES | 35308 |
| INDIA | ARGENTINA | 40039.128 |
| INDIA | FRANCE | 43584 |
| FRANCE | GERMANY | 23866.92 |
| GERMANY | UNITED STATES | 12471.48 |
| INDIA | CANADA | 17252 |
| IRAQ | GERMANY | 25577.4 |
| EGYPT | INDIA | 27987.84 |
| … and 9 more rows |

**Reference SQL:**
```sql
SELECT cn.n_name AS customer_nation_n_name,
       sn.n_name AS supplier_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS cn       ON customer.c_nationkey = cn.n_nationkey
  JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN sem_engine.nation   AS sn       ON supplier.s_nationkey = sn.n_nationkey
 GROUP BY cn.n_name, sn.n_name
```

**Reference results:**
| customer_nation_n_name | supplier_nation_n_name | revenue |
| --- | --- | --- |
| UNITED STATES | IRAQ | 19355.38 |
| INDIA | EGYPT | 27987.84 |
| IRAQ | UNITED STATES | 47215 |
| GERMANY | FRANCE | 23866.92 |
| UNITED STATES | INDIA | 66447.44 |
| BRAZIL | GERMANY | 10471.68 |
| JAPAN | UNITED STATES | 17220.8 |
| ARGENTINA | GERMANY | 23070.4482 |
| UNITED STATES | BRAZIL | 35308 |
| GERMANY | GERMANY | 34905.6 |
| ARGENTINA | EGYPT | 38235.252 |
| FRANCE | INDIA | 43584 |
| GERMANY | UNITED STATES | 21636.25 |
| UNITED STATES | UNITED STATES | 70822.8144 |
| UNITED STATES | FRANCE | 60295.0056 |
| … and 9 more rows |

**Outcome:** PASS — rows match reference.


### C01 — revenue + total_availqty by part — compiler flags CHASM_WARNING _(engine=sql)_

**Category:** Chasm trap  
**Source:** `06_chasm_trap.yaml`  
**Expected outcome:** `COMPILE_REJECTED`  
**Notes:** is_valid=0 with validation_message beginning 'CHASM_WARNING'. The short-term contract is: refuse the request; caller splits into two separate per-grain requests (partsupp.p_name + lineitem.p_name) and joins the results client-side. A proper symmetric-aggregate sub-SELECT plan is deferred.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue,total_availqty'`
- `dimensions` = `'part.p_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "part.p_name" has 2 paths to part (roles: lineitem_to_part,  partsupp_to_part). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### FO01 — count_orders grouped at lineitem grain (DISTINCT survives fan-out) _(engine=sql)_

**Category:** Fan-out  
**Source:** `07_fanout.yaml`  
**Expected outcome:** `PASS`  
**Notes:** count_orders = COUNT(DISTINCT orders.o_orderkey) — order count is preserved.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,lineitem.l_returnflag'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG01 — No grain (day-level, default) _(engine=sql)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG02 — Monthly rollup (:MONTH) _(engine=sql)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate:MONTH,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG03 — Yearly rollup (:YEAR) _(engine=sql)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate:YEAR'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT TRUNC(orders.o_orderdate, 'Y') AS o_orderdate_year, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem 
    INNER JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey GROUP BY TRUNC(orders.o_orderdate, 'Y')
```

**Compiled-SQL results:**
| o_orderdate_year | revenue |
| --- | --- |
| 1995-01-01 | 122674.2 |
| 1994-01-01 | 113726.27 |
| 1992-01-01 | 54605.04 |
| 1997-01-01 | 133381.35 |
| 1996-01-01 | 221628.18 |
| 1998-01-01 | 82117.08 |
| 1993-01-01 | 163029.8282 |

**Reference SQL:**
```sql
SELECT TRUNC(orders.o_orderdate, 'Y') AS o_orderdate_year,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey
 GROUP BY TRUNC(orders.o_orderdate, 'Y')
```

**Reference results:**
| o_orderdate_year | revenue |
| --- | --- |
| 1995-01-01 | 122674.2 |
| 1994-01-01 | 113726.27 |
| 1992-01-01 | 54605.04 |
| 1997-01-01 | 133381.35 |
| 1996-01-01 | 221628.18 |
| 1998-01-01 | 82117.08 |
| 1993-01-01 | 163029.8282 |

**Outcome:** PASS — rows match reference.


### TG04 — Quarter rollup (:QUARTER) _(engine=sql)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'orders.o_orderdate:QUARTER'`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT TRUNC(orders.o_orderdate, 'Q') AS o_orderdate_quarter, COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM sem_engine.orders AS orders GROUP BY TRUNC(orders.o_orderdate, 'Q')
```

**Compiled-SQL results:**
| o_orderdate_quarter | count_orders |
| --- | --- |
| 1994-07-01 | 2 |
| 1994-01-01 | 1 |
| 1992-01-01 | 1 |
| 1996-10-01 | 1 |
| 1995-07-01 | 1 |
| 1998-04-01 | 1 |
| 1998-10-01 | 1 |
| 1993-04-01 | 1 |
| 1997-04-01 | 1 |
| 1998-01-01 | 1 |
| 1993-10-01 | 2 |
| 1995-10-01 | 2 |
| 1997-01-01 | 1 |
| 1992-10-01 | 1 |
| 1996-01-01 | 3 |

**Reference SQL:**
```sql
SELECT TRUNC(orders.o_orderdate, 'Q') AS o_orderdate_quarter,
       COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM sem_engine.orders AS orders
 GROUP BY TRUNC(orders.o_orderdate, 'Q')
```

**Reference results:**
| o_orderdate_quarter | count_orders |
| --- | --- |
| 1994-07-01 | 2 |
| 1994-01-01 | 1 |
| 1992-01-01 | 1 |
| 1996-10-01 | 1 |
| 1995-07-01 | 1 |
| 1998-04-01 | 1 |
| 1998-10-01 | 1 |
| 1993-04-01 | 1 |
| 1997-04-01 | 1 |
| 1998-01-01 | 1 |
| 1993-10-01 | 2 |
| 1995-10-01 | 2 |
| 1997-01-01 | 1 |
| 1992-10-01 | 1 |
| 1996-01-01 | 3 |

**Outcome:** PASS — rows match reference.


### E01 — Metric-only (scalar revenue) _(engine=sql)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
```

**Compiled-SQL results:**
| revenue |
| --- |
| 891161.9482 |

**Reference SQL:**
```sql
SELECT SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
```

**Reference results:**
| revenue |
| --- |
| 891161.9482 |

**Outcome:** PASS — rows match reference.


### E02 — Dimension-only (distinct values of one dim, F3) _(engine=sql)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F3 — dim-only requests now emit SELECT DISTINCT.

**Request:**
- `model` = `'tpch_orders'`
- `dimensions` = `'customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### E03 — Dimension-only with role alias (still DISTINCT) _(engine=sql)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Lists nations that actually have suppliers — useful for building dim filter UIs. Anchor becomes supplier (most-connected required dataset) because there is no metric to give us one.


**Request:**
- `model` = `'tpch_orders'`
- `dimensions` = `'supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `supplier` | **joined:** `supplier, nation AS supplier_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT DISTINCT supplier_nation.n_name AS supplier_nation_n_name
  FROM sem_engine.supplier AS supplier 
    INNER JOIN sem_engine.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey
```

**Compiled-SQL results:**
| supplier_nation_n_name |
| --- |
| UNITED STATES |
| IRAQ |
| JAPAN |
| GERMANY |
| INDIA |
| FRANCE |
| BRAZIL |
| ARGENTINA |
| EGYPT |

**Reference SQL:**
```sql
SELECT DISTINCT nation.n_name AS supplier_nation_n_name
  FROM sem_engine.supplier AS supplier
  JOIN sem_engine.nation   AS nation ON supplier.s_nationkey = nation.n_nationkey
```

**Reference results:**
| supplier_nation_n_name |
| --- |
| UNITED STATES |
| IRAQ |
| JAPAN |
| GERMANY |
| INDIA |
| FRANCE |
| BRAZIL |
| ARGENTINA |
| EGYPT |

**Outcome:** PASS — rows match reference.


### SL01 — Top-5 customers by revenue (ORDER BY alias + TOP) _(engine=sql)_

**Category:** Sort / limit  
**Source:** `10_sort_limit.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_name,customer.c_mktsegment,orders.o_orderpriority'`
- `sort` = `'revenue DESC'`
- `limit` = `5`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_name" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### MD01 — promo_revenue alone (needs part via METRIC_FIELD_REF) _(engine=sql)_

**Category:** Metric-driven join  
**Source:** `11_metric_driven_join.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: dim "customer.c_mktsegment" has 2 paths to customer (roles: placed_by,  billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### CB01 — exec_dashboard cube — total_net_revenue (scalar) _(engine=sql)_

**Category:** Cube  
**Source:** `12_cube_source_query.yaml`  
**Expected outcome:** `RUNTIME_ERROR`  
**Notes:** F8 wraps source_query as a derived table, but exec_dashboard's underlying physical tables (sales_orders, products, etc.) don't exist on this sandbox. Expected to surface a 3807 at runtime — the important point is the compiled SQL now HAS the source_query in its FROM (not a bare `FROM sales_cube AS sales_cube`).


**Request:**
- `model` = `'exec_dashboard'`
- `metrics` = `'total_net_revenue'`

**is_valid:** `1` | **anchor:** `sales_cube` | **joined:** `sales_cube`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT SUM(sales_cube.net_revenue) AS total_net_revenue
  FROM (-- Pre-canned executive sales cube (source_query for sales_cube).

SELECT
    o.order_id,
    ol.product_id,
    o.order_date,
    TRUNC(o.order_date, 'IW')           AS order_week,
    EXTRACT(YEAR FROM o.order_date)       AS order_year,
    r.region_name                         AS region,
    r.country_name                        AS country,
    o.sales_channel,
    CASE
        WHEN c.lifetime_spend >= 100000 THEN 'Enterprise'
        WHEN c.lifetime_spend >= 10000  THEN 'SMB'
        ELSE 'Consumer'
    END                                    AS customer_segment,
    p.category_name                       AS product_category,
    p.brand_name                          AS product_brand,
    CASE WHEN c.acquisition_date >= ADD_MONTHS(CURRENT_DATE, -12) THEN 1 ELSE 0 END
                                          AS is_new_customer,
    ol.extended_price                     AS gross_revenue,
    ol.extended_price * (1 - ol.discount_pct) AS net_revenue,
    ol.quantity                           AS units_sold,
    CASE WHEN ol.return_ts IS NOT NULL THEN 1 ELSE 0 END AS is_returned
FROM sales.orders o
JOIN sales.order_lines ol
    ON ol.order_id = o.order_id
   AND ol.deleted_flag = 0
JOIN sales.customers c
    ON c.customer_id = o.customer_id
   AND c.deleted_flag = 0
JOIN sales.products p
    ON p.product_id = ol.product_id
   AND p.active_flag = 1
LEFT JOIN geo.regions r
    ON r.region_code = c.region_code
WHERE o.order_status IN ('SHIPPED','DELIVERED')
  AND o.deleted_flag = 0
  AND o.order_date >= ADD_MONTHS(CURRENT_DATE, -36)) AS sales_cube
```

**Runtime error on compiled SQL:** `[Version 20.0.0.56] [Session 5211] [Teradata Database] [Error 3802] Database 'sales' does not exist.`

**Outcome:** RUNTIME_ERROR


### FM01 — Base metric alongside a single-filter variant (exams only) _(engine=sql)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Tests that the compiler preserves the plain aggregate for score_avg
and wraps a CASE-WHEN only around the filtered variant. The
assessment_type dim is auto-included because the filter references
its category_lvl1 column.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'score_avg,exam_score_avg'`
- `dimensions` = `'student.major'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, student, assessment_type`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT student.major AS major, AVG(assessment.score) AS score_avg, AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg
  FROM sem_engine.gb_assessment AS assessment 
    INNER JOIN sem_engine.gb_student AS student ON assessment.student_id = student.student_id 
    INNER JOIN sem_engine.gb_assessment_type AS assessment_type ON assessment.type_code = assessment_type.type_code GROUP BY student.major
```

**Compiled-SQL results:**
| major | score_avg | exam_score_avg |
| --- | --- | --- |
| PHYSICS | 77 | 70.5 |
| MATH | 69.3846 | 85.8333 |
| COMP_SCI | 67.4118 | 73 |

**Reference SQL:**
```sql
SELECT student.major,
       AVG(assessment.score)                                                  AS score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END)                                   AS exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY student.major
```

**Reference results:**
| major | score_avg | exam_score_avg |
| --- | --- | --- |
| PHYSICS | 77 | 70.5 |
| MATH | 69.3846 | 85.8333 |
| COMP_SCI | 67.4118 | 73 |

**Outcome:** PASS — rows match reference.


### FM02 — Multiple single-filter variants over the same base _(engine=sql)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** All three metrics filter on the same dim (assessment_type) so the
compiler should join it exactly once.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_score_avg,homework_score_avg,final_exam_score_avg'`
- `dimensions` = `'student.major'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, student, assessment_type`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT student.major AS major, AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg, AVG(CASE WHEN assessment_type.category_lvl1 = 'HW' THEN assessment.score END) AS homework_score_avg, AVG(CASE WHEN assessment_type.category_lvl2 = 'EX_FINAL' THEN assessment.score END) AS final_exam_score_avg
  FROM sem_engine.gb_assessment AS assessment 
    INNER JOIN sem_engine.gb_student AS student ON assessment.student_id = student.student_id 
    INNER JOIN sem_engine.gb_assessment_type AS assessment_type ON assessment.type_code = assessment_type.type_code GROUP BY student.major
```

**Compiled-SQL results:**
| major | exam_score_avg | homework_score_avg | final_exam_score_avg |
| --- | --- | --- | --- |
| PHYSICS | 70.5 | 80 | 73 |
| MATH | 85.8333 | 42.8 | 88.3333 |
| COMP_SCI | 73 | 56.1667 | 77 |

**Reference SQL:**
```sql
SELECT student.major,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END) AS exam_score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'HW'
                 THEN assessment.score END) AS homework_score_avg,
       AVG(CASE WHEN assessment_type.category_lvl2 = 'EX_FINAL'
                 THEN assessment.score END) AS final_exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY student.major
```

**Reference results:**
| major | exam_score_avg | homework_score_avg | final_exam_score_avg |
| --- | --- | --- | --- |
| PHYSICS | 70.5 | 80 | 73 |
| MATH | 85.8333 | 42.8 | 88.3333 |
| COMP_SCI | 73 | 56.1667 | 77 |

**Outcome:** PASS — rows match reference.


### FM03 — Composite filter spanning two datasets (AND across dims) _(engine=sql)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Filter predicates reference fields on two different dims
(assessment_type.category_lvl1 AND student.class_year). Compiler
must auto-join both filter datasets.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'senior_exam_score_avg'`
- `dimensions` = `'course.subject'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, student, course, assessment_type`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT course.subject AS subject, AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' AND student.class_year = 4 THEN assessment.score END) AS senior_exam_score_avg
  FROM sem_engine.gb_assessment AS assessment 
    INNER JOIN sem_engine.gb_student AS student ON assessment.student_id = student.student_id 
    INNER JOIN sem_engine.gb_course AS course ON assessment.course_id = course.course_id 
    INNER JOIN sem_engine.gb_assessment_type AS assessment_type ON assessment.type_code = assessment_type.type_code GROUP BY course.subject
```

**Compiled-SQL results:**
| subject | senior_exam_score_avg |
| --- | --- |
| PHYSICS | 70.5 |
| MATH |  |
| COMP_SCI |  |

**Reference SQL:**
```sql
SELECT course.subject,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 AND student.class_year = 4
                 THEN assessment.score END) AS senior_exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_course          AS course
    ON assessment.course_id = course.course_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
 GROUP BY course.subject
```

**Reference results:**
| subject | senior_exam_score_avg |
| --- | --- |
| PHYSICS | 70.5 |
| MATH |  |
| COMP_SCI |  |

**Outcome:** PASS — rows match reference.


### FM04 — COUNT-base filtered variant (exam_count) _(engine=sql)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** COUNT uses ELSE NULL (implicit) rather than ELSE 0 so the filtered
rows drop out of the count naturally. Tests that aggregate_fn=COUNT
is handled correctly by the compiler.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_count,assessment_count'`
- `dimensions` = `'course.subject'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, course, assessment_type`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT course.subject AS subject, COUNT(assessment.assessment_id) AS assessment_count, COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.assessment_id END) AS exam_count
  FROM sem_engine.gb_assessment AS assessment 
    INNER JOIN sem_engine.gb_course AS course ON assessment.course_id = course.course_id 
    INNER JOIN sem_engine.gb_assessment_type AS assessment_type ON assessment.type_code = assessment_type.type_code GROUP BY course.subject
```

**Compiled-SQL results:**
| subject | assessment_count | exam_count |
| --- | --- | --- |
| PHYSICS | 5 | 2 |
| MATH | 10 | 4 |
| COMP_SCI | 20 | 10 |

**Reference SQL:**
```sql
SELECT course.subject,
       COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX'
                   THEN assessment.assessment_id END)     AS exam_count,
       COUNT(assessment.assessment_id)                    AS assessment_count
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_course          AS course
    ON assessment.course_id = course.course_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY course.subject
```

**Reference results:**
| subject | exam_count | assessment_count |
| --- | --- | --- |
| PHYSICS | 2 | 5 |
| MATH | 4 | 10 |
| COMP_SCI | 10 | 20 |

**Outcome:** PASS — rows match reference.


### FM05 — Filter dim is also an explicit dimension _(engine=sql)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** When the filter dim is also explicitly requested as a GROUP BY, the
compiler must not double-join. Result will include one row per
category with non-null score only on the 'EX' row.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_score_avg'`
- `dimensions` = `'assessment_type.category_lvl1'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, assessment_type`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT assessment_type.category_lvl1 AS category_lvl1, AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg
  FROM sem_engine.gb_assessment AS assessment 
    INNER JOIN sem_engine.gb_assessment_type AS assessment_type ON assessment.type_code = assessment_type.type_code GROUP BY assessment_type.category_lvl1
```

**Compiled-SQL results:**
| category_lvl1 | exam_score_avg |
| --- | --- |
| HW |  |
| PR |  |
| EX | 77.5 |
| QZ |  |

**Reference SQL:**
```sql
SELECT assessment_type.category_lvl1,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END) AS exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY assessment_type.category_lvl1
```

**Reference results:**
| category_lvl1 | exam_score_avg |
| --- | --- |
| HW |  |
| PR |  |
| EX | 77.5 |
| QZ |  |

**Outcome:** PASS — rows match reference.


### B01 — Revenue by customer market segment (2-hop) _(engine=python)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Canonical fact → dim traversal with two intermediate hops.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### B02 — Single-table AVG (avg_qty by return flag) _(engine=python)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'avg_qty'`
- `dimensions` = `'lineitem.l_returnflag,lineitem.l_linestatus'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  lineitem.l_returnflag AS l_returnflag,
  lineitem.l_linestatus AS l_linestatus,
  AVG(lineitem.l_quantity) AS avg_qty
FROM sem_engine.lineitem AS lineitem
GROUP BY
  lineitem.l_returnflag,
  lineitem.l_linestatus
```

**Compiled-SQL results:**
| l_returnflag | l_linestatus | avg_qty |
| --- | --- | --- |
| A  | F  | 32 |
| N  | O  | 27.3684 |
| R  | F  | 32.3077 |

**Reference SQL:**
```sql
SELECT lineitem.l_returnflag, lineitem.l_linestatus,
       AVG(lineitem.l_quantity) AS avg_qty
  FROM sem_engine.lineitem AS lineitem
 GROUP BY lineitem.l_returnflag, lineitem.l_linestatus
```

**Reference results:**
| l_returnflag | l_linestatus | avg_qty |
| --- | --- | --- |
| A  | F  | 32 |
| N  | O  | 27.3684 |
| R  | F  | 32.3077 |

**Outcome:** PASS — rows match reference.


### B03 — 5-hop traversal with all intermediates named (revenue by region) _(engine=python)_

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F01 — Date filter with DATE literal _(engine=python)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"lineitem.l_shipdate|>=|DATE '1995-01-01'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F02 — LIKE filter (priority starts with 1-) _(engine=python)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"orders.o_orderpriority|LIKE|'1-%'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F03 — IN list (post-F1 — caller supplies parens, compiler does not wrap) _(engine=python)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F1 compiler bug — now fixed.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderstatus'`
- `where` = `"orders.o_orderstatus|IN|('O','F')"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F04 — Filter on region.r_name with region not in dims (F2 auto-include) _(engine=python)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F2 compiler bug — region dataset is now auto-included from the WHERE.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`
- `where` = `"region.r_name|=|'AMERICA'"`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### F05 — Unquoted string value (caller error — must still fail cleanly) _(engine=python)_

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `RUNTIME_ERROR`  
**Notes:** This is a caller error — `O` is interpreted by Teradata as a column reference. Protocol requires string pre-quoting. We keep the test to document the failure mode.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'orders.o_orderstatus'`
- `where` = `'orders.o_orderstatus|=|O'`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  orders.o_orderstatus AS o_orderstatus,
  COUNT(DISTINCT orders.o_orderkey) AS count_orders
FROM sem_engine.orders AS orders
WHERE
  orders.o_orderstatus = O
GROUP BY
  orders.o_orderstatus
```

**Runtime error on compiled SQL:** `[Version 20.0.0.56] [Session 5211] [Teradata Database] [Error 5628] Column O not found in sem_engine.orders.`

**Outcome:** RUNTIME_ERROR


### R01 — promo_share by region (5-hop + part) _(engine=python)_

**Category:** Ratio  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### R02 — HAVING promo_share > 0.1 _(engine=python)_

**Category:** HAVING  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,nation.n_name'`
- `having` = `'promo_share|>|0.1'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### P01 — Auto-intermediates — revenue by region with NO intermediates named _(engine=python)_

**Category:** BFS  
**Source:** `04_path_resolution.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Before F4 this returned "Could not resolve join path for datasets: region".

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'region.r_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, region, orders, customer, nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  region.r_name AS r_name,
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
INNER JOIN sem_engine.orders AS orders
  ON lineitem.l_orderkey = orders.o_orderkey
INNER JOIN sem_engine.customer AS customer
  ON orders.o_custkey = customer.c_custkey
INNER JOIN sem_engine.nation AS nation
  ON customer.c_nationkey = nation.n_nationkey
INNER JOIN sem_engine.region AS region
  ON nation.n_regionkey = region.r_regionkey
GROUP BY
  region.r_name
```

**Compiled-SQL results:**
| r_name | revenue |
| --- | --- |
| MIDDLE EAST | 198552.65 |
| EUROPE | 219317.89 |
| AMERICA | 428082.7682 |
| ASIA | 45208.64 |

**Reference SQL:**
```sql
SELECT region.r_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN sem_engine.region   AS region   ON nation.n_regionkey = region.r_regionkey
 GROUP BY region.r_name
```

**Reference results:**
| r_name | revenue |
| --- | --- |
| MIDDLE EAST | 198552.65 |
| EUROPE | 219317.89 |
| AMERICA | 428082.7682 |
| ASIA | 45208.64 |

**Outcome:** PASS — rows match reference.


### P02 — Ambiguous path — revenue by supplier direct, NOT via partsupp _(engine=python)_

**Category:** Ambiguous path  
**Source:** `04_path_resolution.yaml`  
**Expected outcome:** `PASS`  
**Notes:** lineitem has TWO paths to supplier — direct (l_suppkey) and via partsupp (l_partkey + l_suppkey → partsupp → supplier). The compiler should pick the direct MANY_TO_ONE edge. Taking the partsupp path would inflate revenue by the partsupp fan-out.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'supplier.s_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'supplier.s_name' has 2 paths to supplier (roles: lineitem_to_supplier, partsupp_to_supplier). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### RP01 — Role pin — customer_nation.n_name _(engine=python)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, customer, nation AS customer_nation, orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  customer_nation.n_name AS customer_nation_n_name,
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
INNER JOIN sem_engine.orders AS orders
  ON lineitem.l_orderkey = orders.o_orderkey
INNER JOIN sem_engine.customer AS customer
  ON orders.o_custkey = customer.c_custkey
INNER JOIN sem_engine.nation AS customer_nation
  ON customer.c_nationkey = customer_nation.n_nationkey
GROUP BY
  customer_nation.n_name
```

**Compiled-SQL results:**
| customer_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 264700.12 |
| IRAQ | 78325.1 |
| JAPAN | 17220.8 |
| GERMANY | 105986.17 |
| INDIA | 27987.84 |
| FRANCE | 113331.72 |
| BRAZIL | 10471.68 |
| CANADA | 17252 |
| ARGENTINA | 135658.9682 |
| EGYPT | 120227.55 |

**Reference SQL:**
```sql
SELECT nation.n_name AS customer_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
 GROUP BY nation.n_name
```

**Reference results:**
| customer_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 264700.12 |
| IRAQ | 78325.1 |
| JAPAN | 17220.8 |
| GERMANY | 105986.17 |
| INDIA | 27987.84 |
| FRANCE | 113331.72 |
| BRAZIL | 10471.68 |
| CANADA | 17252 |
| ARGENTINA | 135658.9682 |
| EGYPT | 120227.55 |

**Outcome:** PASS — rows match reference.


### RP02 — Role pin — supplier_nation.n_name _(engine=python)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, supplier, nation AS supplier_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  supplier_nation.n_name AS supplier_nation_n_name,
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
INNER JOIN sem_engine.supplier AS supplier
  ON lineitem.l_suppkey = supplier.s_suppkey
INNER JOIN sem_engine.nation AS supplier_nation
  ON supplier.s_nationkey = supplier_nation.n_nationkey
GROUP BY
  supplier_nation.n_name
```

**Compiled-SQL results:**
| supplier_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 210414.8644 |
| IRAQ | 76042.88 |
| JAPAN | 66707.55 |
| GERMANY | 80919.2082 |
| INDIA | 167322.568 |
| FRANCE | 84161.9256 |
| BRAZIL | 35308 |
| ARGENTINA | 104061.86 |
| EGYPT | 66223.092 |

**Reference SQL:**
```sql
SELECT nation.n_name AS supplier_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN sem_engine.nation   AS nation   ON supplier.s_nationkey = nation.n_nationkey
 GROUP BY nation.n_name
```

**Reference results:**
| supplier_nation_n_name | revenue |
| --- | --- |
| UNITED STATES | 210414.8644 |
| IRAQ | 76042.88 |
| JAPAN | 66707.55 |
| GERMANY | 80919.2082 |
| INDIA | 167322.568 |
| FRANCE | 84161.9256 |
| BRAZIL | 35308 |
| ARGENTINA | 104061.86 |
| EGYPT | 66223.092 |

**Outcome:** PASS — rows match reference.


### RP03 — BOTH roles in one query — nation joined twice with different aliases _(engine=python)_

**Category:** Role-playing dimension  
**Source:** `05_role_playing.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Canonical Kimball role-playing — both roles in one SQL, self-joined nation.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer_nation.n_name,supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, customer, nation AS customer_nation, supplier, nation AS supplier_nation, orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  customer_nation.n_name AS customer_nation_n_name,
  supplier_nation.n_name AS supplier_nation_n_name,
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
INNER JOIN sem_engine.supplier AS supplier
  ON lineitem.l_suppkey = supplier.s_suppkey
INNER JOIN sem_engine.nation AS supplier_nation
  ON supplier.s_nationkey = supplier_nation.n_nationkey
INNER JOIN sem_engine.orders AS orders
  ON lineitem.l_orderkey = orders.o_orderkey
INNER JOIN sem_engine.customer AS customer
  ON orders.o_custkey = customer.c_custkey
INNER JOIN sem_engine.nation AS customer_nation
  ON customer.c_nationkey = customer_nation.n_nationkey
GROUP BY
  customer_nation.n_name,
  supplier_nation.n_name
```

**Compiled-SQL results:**
| customer_nation_n_name | supplier_nation_n_name | revenue |
| --- | --- | --- |
| UNITED STATES | IRAQ | 19355.38 |
| INDIA | EGYPT | 27987.84 |
| IRAQ | UNITED STATES | 47215 |
| GERMANY | FRANCE | 23866.92 |
| UNITED STATES | INDIA | 66447.44 |
| BRAZIL | GERMANY | 10471.68 |
| JAPAN | UNITED STATES | 17220.8 |
| ARGENTINA | GERMANY | 23070.4482 |
| UNITED STATES | BRAZIL | 35308 |
| GERMANY | GERMANY | 34905.6 |
| ARGENTINA | EGYPT | 38235.252 |
| FRANCE | INDIA | 43584 |
| GERMANY | UNITED STATES | 21636.25 |
| UNITED STATES | UNITED STATES | 70822.8144 |
| UNITED STATES | FRANCE | 60295.0056 |
| … and 9 more rows |

**Reference SQL:**
```sql
SELECT cn.n_name AS customer_nation_n_name,
       sn.n_name AS supplier_nation_n_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN sem_engine.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN sem_engine.nation   AS cn       ON customer.c_nationkey = cn.n_nationkey
  JOIN sem_engine.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN sem_engine.nation   AS sn       ON supplier.s_nationkey = sn.n_nationkey
 GROUP BY cn.n_name, sn.n_name
```

**Reference results:**
| customer_nation_n_name | supplier_nation_n_name | revenue |
| --- | --- | --- |
| UNITED STATES | IRAQ | 19355.38 |
| INDIA | EGYPT | 27987.84 |
| IRAQ | UNITED STATES | 47215 |
| GERMANY | FRANCE | 23866.92 |
| UNITED STATES | INDIA | 66447.44 |
| BRAZIL | GERMANY | 10471.68 |
| JAPAN | UNITED STATES | 17220.8 |
| ARGENTINA | GERMANY | 23070.4482 |
| UNITED STATES | BRAZIL | 35308 |
| GERMANY | GERMANY | 34905.6 |
| ARGENTINA | EGYPT | 38235.252 |
| FRANCE | INDIA | 43584 |
| GERMANY | UNITED STATES | 21636.25 |
| UNITED STATES | UNITED STATES | 70822.8144 |
| UNITED STATES | FRANCE | 60295.0056 |
| … and 9 more rows |

**Outcome:** PASS — rows match reference.


### C01 — revenue + total_availqty by part — compiler flags CHASM_WARNING _(engine=python)_

**Category:** Chasm trap  
**Source:** `06_chasm_trap.yaml`  
**Expected outcome:** `COMPILE_REJECTED`  
**Notes:** is_valid=0 with validation_message beginning 'CHASM_WARNING'. The short-term contract is: refuse the request; caller splits into two separate per-grain requests (partsupp.p_name + lineitem.p_name) and joins the results client-side. A proper symmetric-aggregate sub-SELECT plan is deferred.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue,total_availqty'`
- `dimensions` = `'part.p_name'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'part.p_name' has 2 paths to part (roles: lineitem_to_part, partsupp_to_part). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### FO01 — count_orders grouped at lineitem grain (DISTINCT survives fan-out) _(engine=python)_

**Category:** Fan-out  
**Source:** `07_fanout.yaml`  
**Expected outcome:** `PASS`  
**Notes:** count_orders = COUNT(DISTINCT orders.o_orderkey) — order count is preserved.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,lineitem.l_returnflag'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG01 — No grain (day-level, default) _(engine=python)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG02 — Monthly rollup (:MONTH) _(engine=python)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate:MONTH,customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### TG03 — Yearly rollup (:YEAR) _(engine=python)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate:YEAR'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  TRUNC(orders.o_orderdate, 'Y') AS o_orderdate_year,
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
INNER JOIN sem_engine.orders AS orders
  ON lineitem.l_orderkey = orders.o_orderkey
GROUP BY
  TRUNC(orders.o_orderdate, 'Y')
```

**Compiled-SQL results:**
| o_orderdate_year | revenue |
| --- | --- |
| 1995-01-01 | 122674.2 |
| 1994-01-01 | 113726.27 |
| 1992-01-01 | 54605.04 |
| 1997-01-01 | 133381.35 |
| 1996-01-01 | 221628.18 |
| 1998-01-01 | 82117.08 |
| 1993-01-01 | 163029.8282 |

**Reference SQL:**
```sql
SELECT TRUNC(orders.o_orderdate, 'Y') AS o_orderdate_year,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
  JOIN sem_engine.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey
 GROUP BY TRUNC(orders.o_orderdate, 'Y')
```

**Reference results:**
| o_orderdate_year | revenue |
| --- | --- |
| 1995-01-01 | 122674.2 |
| 1994-01-01 | 113726.27 |
| 1992-01-01 | 54605.04 |
| 1997-01-01 | 133381.35 |
| 1996-01-01 | 221628.18 |
| 1998-01-01 | 82117.08 |
| 1993-01-01 | 163029.8282 |

**Outcome:** PASS — rows match reference.


### TG04 — Quarter rollup (:QUARTER) _(engine=python)_

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'orders.o_orderdate:QUARTER'`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  TRUNC(orders.o_orderdate, 'Q') AS o_orderdate_quarter,
  COUNT(DISTINCT orders.o_orderkey) AS count_orders
FROM sem_engine.orders AS orders
GROUP BY
  TRUNC(orders.o_orderdate, 'Q')
```

**Compiled-SQL results:**
| o_orderdate_quarter | count_orders |
| --- | --- |
| 1994-07-01 | 2 |
| 1994-01-01 | 1 |
| 1992-01-01 | 1 |
| 1996-10-01 | 1 |
| 1995-07-01 | 1 |
| 1998-04-01 | 1 |
| 1998-10-01 | 1 |
| 1993-04-01 | 1 |
| 1997-04-01 | 1 |
| 1998-01-01 | 1 |
| 1993-10-01 | 2 |
| 1995-10-01 | 2 |
| 1997-01-01 | 1 |
| 1992-10-01 | 1 |
| 1996-01-01 | 3 |

**Reference SQL:**
```sql
SELECT TRUNC(orders.o_orderdate, 'Q') AS o_orderdate_quarter,
       COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM sem_engine.orders AS orders
 GROUP BY TRUNC(orders.o_orderdate, 'Q')
```

**Reference results:**
| o_orderdate_quarter | count_orders |
| --- | --- |
| 1994-07-01 | 2 |
| 1994-01-01 | 1 |
| 1992-01-01 | 1 |
| 1996-10-01 | 1 |
| 1995-07-01 | 1 |
| 1998-04-01 | 1 |
| 1998-10-01 | 1 |
| 1993-04-01 | 1 |
| 1997-04-01 | 1 |
| 1998-01-01 | 1 |
| 1993-10-01 | 2 |
| 1995-10-01 | 2 |
| 1997-01-01 | 1 |
| 1992-10-01 | 1 |
| 1996-01-01 | 3 |

**Outcome:** PASS — rows match reference.


### E01 — Metric-only (scalar revenue) _(engine=python)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  SUM(lineitem.l_extendedprice * (
    1 - lineitem.l_discount
  )) AS revenue
FROM sem_engine.lineitem AS lineitem
```

**Compiled-SQL results:**
| revenue |
| --- |
| 891161.9482 |

**Reference SQL:**
```sql
SELECT SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM sem_engine.lineitem AS lineitem
```

**Reference results:**
| revenue |
| --- |
| 891161.9482 |

**Outcome:** PASS — rows match reference.


### E02 — Dimension-only (distinct values of one dim, F3) _(engine=python)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F3 — dim-only requests now emit SELECT DISTINCT.

**Request:**
- `model` = `'tpch_orders'`
- `dimensions` = `'customer.c_mktsegment'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### E03 — Dimension-only with role alias (still DISTINCT) _(engine=python)_

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Lists nations that actually have suppliers — useful for building dim filter UIs. Anchor becomes supplier (most-connected required dataset) because there is no metric to give us one.


**Request:**
- `model` = `'tpch_orders'`
- `dimensions` = `'supplier_nation.n_name'`

**is_valid:** `1` | **anchor:** `supplier` | **joined:** `supplier, nation AS supplier_nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT DISTINCT
  supplier_nation.n_name AS supplier_nation_n_name
FROM sem_engine.supplier AS supplier
INNER JOIN sem_engine.nation AS supplier_nation
  ON supplier.s_nationkey = supplier_nation.n_nationkey
```

**Compiled-SQL results:**
| supplier_nation_n_name |
| --- |
| UNITED STATES |
| IRAQ |
| JAPAN |
| GERMANY |
| INDIA |
| FRANCE |
| BRAZIL |
| ARGENTINA |
| EGYPT |

**Reference SQL:**
```sql
SELECT DISTINCT nation.n_name AS supplier_nation_n_name
  FROM sem_engine.supplier AS supplier
  JOIN sem_engine.nation   AS nation ON supplier.s_nationkey = nation.n_nationkey
```

**Reference results:**
| supplier_nation_n_name |
| --- |
| UNITED STATES |
| IRAQ |
| JAPAN |
| GERMANY |
| INDIA |
| FRANCE |
| BRAZIL |
| ARGENTINA |
| EGYPT |

**Outcome:** PASS — rows match reference.


### SL01 — Top-5 customers by revenue (ORDER BY alias + TOP) _(engine=python)_

**Category:** Sort / limit  
**Source:** `10_sort_limit.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_name,customer.c_mktsegment,orders.o_orderpriority'`
- `sort` = `'revenue DESC'`
- `limit` = `5`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_name' has 2 paths to customer (roles: placed_by, billed_to). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### MD01 — promo_revenue alone (needs part via METRIC_FIELD_REF) _(engine=python)_

**Category:** Metric-driven join  
**Source:** `11_metric_driven_join.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`

**is_valid:** `0` | **anchor:** `None` | **joined:** `None`
**validation_message:** `AMBIGUOUS_PATH: AMBIGUOUS_PATH: dim 'customer.c_mktsegment' has 2 paths to customer (roles: billed_to, placed_by). Prefix the dim with a role, e.g. role_name.field_name.`

_(no SQL produced)_


### CB01 — exec_dashboard cube — total_net_revenue (scalar) _(engine=python)_

**Category:** Cube  
**Source:** `12_cube_source_query.yaml`  
**Expected outcome:** `RUNTIME_ERROR`  
**Notes:** F8 wraps source_query as a derived table, but exec_dashboard's underlying physical tables (sales_orders, products, etc.) don't exist on this sandbox. Expected to surface a 3807 at runtime — the important point is the compiled SQL now HAS the source_query in its FROM (not a bare `FROM sales_cube AS sales_cube`).


**Request:**
- `model` = `'exec_dashboard'`
- `metrics` = `'total_net_revenue'`

**is_valid:** `1` | **anchor:** `sales_cube` | **joined:** `sales_cube`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  SUM(sales_cube.net_revenue) AS total_net_revenue
FROM (
  /* Pre-canned executive sales cube (source_query for sales_cube). */
  SELECT
    o.order_id,
    ol.product_id,
    o.order_date,
    TRUNC(o.order_date, 'IW') AS order_week,
    EXTRACT(YEAR FROM o.order_date) AS order_year,
    r.region_name AS region,
    r.country_name AS country,
    o.sales_channel,
    CASE
      WHEN c.lifetime_spend >= 100000
      THEN 'Enterprise'
      WHEN c.lifetime_spend >= 10000
      THEN 'SMB'
      ELSE 'Consumer'
    END AS customer_segment,
    p.category_name AS product_category,
    p.brand_name AS product_brand,
    CASE WHEN c.acquisition_date >= ADD_MONTHS(CURRENT_DATE, -12) THEN 1 ELSE 0 END AS is_new_customer,
    ol.extended_price AS gross_revenue,
    ol.extended_price * (
      1 - ol.discount_pct
    ) AS net_revenue,
    ol.quantity AS units_sold,
    CASE WHEN NOT ol.return_ts IS NULL THEN 1 ELSE 0 END AS is_returned
  FROM sales.orders AS o
  JOIN sales.order_lines AS ol
    ON ol.order_id = o.order_id AND ol.deleted_flag = 0
  JOIN sales.customers AS c
    ON c.customer_id = o.customer_id AND c.deleted_flag = 0
  JOIN sales.products AS p
    ON p.product_id = ol.product_id AND p.active_flag = 1
  LEFT JOIN geo.regions AS r
    ON r.region_code = c.region_code
  WHERE
    o.order_status IN ('SHIPPED', 'DELIVERED')
    AND o.deleted_flag = 0
    AND o.order_date >= ADD_MONTHS(CURRENT_DATE, -36)
) AS sales_cube
```

**Runtime error on compiled SQL:** `[Version 20.0.0.56] [Session 5211] [Teradata Database] [Error 3802] Database 'sales' does not exist.`

**Outcome:** RUNTIME_ERROR


### FM01 — Base metric alongside a single-filter variant (exams only) _(engine=python)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Tests that the compiler preserves the plain aggregate for score_avg
and wraps a CASE-WHEN only around the filtered variant. The
assessment_type dim is auto-included because the filter references
its category_lvl1 column.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'score_avg,exam_score_avg'`
- `dimensions` = `'student.major'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment, assessment_type, student`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  student.major AS major,
  AVG(assessment.score) AS score_avg,
  AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg
FROM sem_engine.gb_assessment AS assessment
INNER JOIN sem_engine.gb_student AS student
  ON assessment.student_id = student.student_id
INNER JOIN sem_engine.gb_assessment_type AS assessment_type
  ON assessment.type_code = assessment_type.type_code
GROUP BY
  student.major
```

**Compiled-SQL results:**
| major | score_avg | exam_score_avg |
| --- | --- | --- |
| PHYSICS | 77 | 70.5 |
| MATH | 69.3846 | 85.8333 |
| COMP_SCI | 67.4118 | 73 |

**Reference SQL:**
```sql
SELECT student.major,
       AVG(assessment.score)                                                  AS score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END)                                   AS exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY student.major
```

**Reference results:**
| major | score_avg | exam_score_avg |
| --- | --- | --- |
| PHYSICS | 77 | 70.5 |
| MATH | 69.3846 | 85.8333 |
| COMP_SCI | 67.4118 | 73 |

**Outcome:** PASS — rows match reference.


### FM02 — Multiple single-filter variants over the same base _(engine=python)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** All three metrics filter on the same dim (assessment_type) so the
compiler should join it exactly once.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_score_avg,homework_score_avg,final_exam_score_avg'`
- `dimensions` = `'student.major'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment_type, assessment, student`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  student.major AS major,
  AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg,
  AVG(CASE WHEN assessment_type.category_lvl1 = 'HW' THEN assessment.score END) AS homework_score_avg,
  AVG(CASE WHEN assessment_type.category_lvl2 = 'EX_FINAL' THEN assessment.score END) AS final_exam_score_avg
FROM sem_engine.gb_assessment AS assessment
INNER JOIN sem_engine.gb_student AS student
  ON assessment.student_id = student.student_id
INNER JOIN sem_engine.gb_assessment_type AS assessment_type
  ON assessment.type_code = assessment_type.type_code
GROUP BY
  student.major
```

**Compiled-SQL results:**
| major | exam_score_avg | homework_score_avg | final_exam_score_avg |
| --- | --- | --- | --- |
| PHYSICS | 70.5 | 80 | 73 |
| MATH | 85.8333 | 42.8 | 88.3333 |
| COMP_SCI | 73 | 56.1667 | 77 |

**Reference SQL:**
```sql
SELECT student.major,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END) AS exam_score_avg,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'HW'
                 THEN assessment.score END) AS homework_score_avg,
       AVG(CASE WHEN assessment_type.category_lvl2 = 'EX_FINAL'
                 THEN assessment.score END) AS final_exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY student.major
```

**Reference results:**
| major | exam_score_avg | homework_score_avg | final_exam_score_avg |
| --- | --- | --- | --- |
| PHYSICS | 70.5 | 80 | 73 |
| MATH | 85.8333 | 42.8 | 88.3333 |
| COMP_SCI | 73 | 56.1667 | 77 |

**Outcome:** PASS — rows match reference.


### FM03 — Composite filter spanning two datasets (AND across dims) _(engine=python)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Filter predicates reference fields on two different dims
(assessment_type.category_lvl1 AND student.class_year). Compiler
must auto-join both filter datasets.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'senior_exam_score_avg'`
- `dimensions` = `'course.subject'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment_type, student, assessment, course`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  course.subject AS subject,
  AVG(
    CASE
      WHEN assessment_type.category_lvl1 = 'EX' AND student.class_year = 4
      THEN assessment.score
    END
  ) AS senior_exam_score_avg
FROM sem_engine.gb_assessment AS assessment
INNER JOIN sem_engine.gb_student AS student
  ON assessment.student_id = student.student_id
INNER JOIN sem_engine.gb_course AS course
  ON assessment.course_id = course.course_id
INNER JOIN sem_engine.gb_assessment_type AS assessment_type
  ON assessment.type_code = assessment_type.type_code
GROUP BY
  course.subject
```

**Compiled-SQL results:**
| subject | senior_exam_score_avg |
| --- | --- |
| PHYSICS | 70.5 |
| MATH |  |
| COMP_SCI |  |

**Reference SQL:**
```sql
SELECT course.subject,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 AND student.class_year = 4
                 THEN assessment.score END) AS senior_exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_course          AS course
    ON assessment.course_id = course.course_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
  JOIN sem_engine.gb_student         AS student
    ON assessment.student_id = student.student_id
 GROUP BY course.subject
```

**Reference results:**
| subject | senior_exam_score_avg |
| --- | --- |
| PHYSICS | 70.5 |
| MATH |  |
| COMP_SCI |  |

**Outcome:** PASS — rows match reference.


### FM04 — COUNT-base filtered variant (exam_count) _(engine=python)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** COUNT uses ELSE NULL (implicit) rather than ELSE 0 so the filtered
rows drop out of the count naturally. Tests that aggregate_fn=COUNT
is handled correctly by the compiler.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_count,assessment_count'`
- `dimensions` = `'course.subject'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment_type, assessment, course`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  course.subject AS subject,
  COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.assessment_id END) AS exam_count,
  COUNT(assessment.assessment_id) AS assessment_count
FROM sem_engine.gb_assessment AS assessment
INNER JOIN sem_engine.gb_course AS course
  ON assessment.course_id = course.course_id
INNER JOIN sem_engine.gb_assessment_type AS assessment_type
  ON assessment.type_code = assessment_type.type_code
GROUP BY
  course.subject
```

**Compiled-SQL results:**
| subject | exam_count | assessment_count |
| --- | --- | --- |
| PHYSICS | 2 | 5 |
| MATH | 4 | 10 |
| COMP_SCI | 10 | 20 |

**Reference SQL:**
```sql
SELECT course.subject,
       COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX'
                   THEN assessment.assessment_id END)     AS exam_count,
       COUNT(assessment.assessment_id)                    AS assessment_count
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_course          AS course
    ON assessment.course_id = course.course_id
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY course.subject
```

**Reference results:**
| subject | exam_count | assessment_count |
| --- | --- | --- |
| PHYSICS | 2 | 5 |
| MATH | 4 | 10 |
| COMP_SCI | 10 | 20 |

**Outcome:** PASS — rows match reference.


### FM05 — Filter dim is also an explicit dimension _(engine=python)_

**Category:** Filtered Metrics  
**Source:** `13_filtered_metrics.yaml`  
**Expected outcome:** `PASS`  
**Notes:** When the filter dim is also explicitly requested as a GROUP BY, the
compiler must not double-join. Result will include one row per
category with non-null score only on the 'EX' row.


**Request:**
- `model` = `'school_gradebook'`
- `metrics` = `'exam_score_avg'`
- `dimensions` = `'assessment_type.category_lvl1'`

**is_valid:** `1` | **anchor:** `assessment` | **joined:** `assessment_type, assessment`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS
SELECT
  assessment_type.category_lvl1 AS category_lvl1,
  AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' THEN assessment.score END) AS exam_score_avg
FROM sem_engine.gb_assessment AS assessment
INNER JOIN sem_engine.gb_assessment_type AS assessment_type
  ON assessment.type_code = assessment_type.type_code
GROUP BY
  assessment_type.category_lvl1
```

**Compiled-SQL results:**
| category_lvl1 | exam_score_avg |
| --- | --- |
| HW |  |
| PR |  |
| EX | 77.5 |
| QZ |  |

**Reference SQL:**
```sql
SELECT assessment_type.category_lvl1,
       AVG(CASE WHEN assessment_type.category_lvl1 = 'EX'
                 THEN assessment.score END) AS exam_score_avg
  FROM sem_engine.gb_assessment      AS assessment
  JOIN sem_engine.gb_assessment_type AS assessment_type
    ON assessment.type_code = assessment_type.type_code
 GROUP BY assessment_type.category_lvl1
```

**Reference results:**
| category_lvl1 | exam_score_avg |
| --- | --- |
| HW |  |
| PR |  |
| EX | 77.5 |
| QZ |  |

**Outcome:** PASS — rows match reference.


## Summary

| id | engine | category | title | expected | actual | agreement | file |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B01 | sql | Baseline | Revenue by customer market segment (2-hop) | PASS | NOT_SUPPORTED | MISMATCH | 01_baseline.yaml |
| B02 | sql | Baseline | Single-table AVG (avg_qty by return flag) | PASS | PASS | MATCH | 01_baseline.yaml |
| B03 | sql | Baseline | 5-hop traversal with all intermediates named (revenue by region) | PASS | NOT_SUPPORTED | MISMATCH | 01_baseline.yaml |
| F01 | sql | Filters | Date filter with DATE literal | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F02 | sql | Filters | LIKE filter (priority starts with 1-) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F03 | sql | Filters | IN list (post-F1 — caller supplies parens, compiler does not wrap) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F04 | sql | Filters | Filter on region.r_name with region not in dims (F2 auto-include) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F05 | sql | Filters | Unquoted string value (caller error — must still fail cleanly) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 02_filters.yaml |
| R01 | sql | Ratio | promo_share by region (5-hop + part) | PASS | NOT_SUPPORTED | MISMATCH | 03_ratio_and_having.yaml |
| R02 | sql | HAVING | HAVING promo_share > 0.1 | PASS | NOT_SUPPORTED | MISMATCH | 03_ratio_and_having.yaml |
| P01 | sql | BFS | Auto-intermediates — revenue by region with NO intermediates named | PASS | PASS | MATCH | 04_path_resolution.yaml |
| P02 | sql | Ambiguous path | Ambiguous path — revenue by supplier direct, NOT via partsupp | PASS | NOT_SUPPORTED | MISMATCH | 04_path_resolution.yaml |
| RP01 | sql | Role-playing dimension | Role pin — customer_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP02 | sql | Role-playing dimension | Role pin — supplier_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP03 | sql | Role-playing dimension | BOTH roles in one query — nation joined twice with different aliases | PASS | PASS | MATCH | 05_role_playing.yaml |
| C01 | sql | Chasm trap | revenue + total_availqty by part — compiler flags CHASM_WARNING | COMPILE_REJECTED | NOT_SUPPORTED | MISMATCH | 06_chasm_trap.yaml |
| FO01 | sql | Fan-out | count_orders grouped at lineitem grain (DISTINCT survives fan-out) | PASS | NOT_SUPPORTED | MISMATCH | 07_fanout.yaml |
| TG01 | sql | Time grain | No grain (day-level, default) | PASS | NOT_SUPPORTED | MISMATCH | 08_time_grain.yaml |
| TG02 | sql | Time grain | Monthly rollup (:MONTH) | PASS | NOT_SUPPORTED | MISMATCH | 08_time_grain.yaml |
| TG03 | sql | Time grain | Yearly rollup (:YEAR) | PASS | PASS | MATCH | 08_time_grain.yaml |
| TG04 | sql | Time grain | Quarter rollup (:QUARTER) | PASS | PASS | MATCH | 08_time_grain.yaml |
| E01 | sql | Edge shapes | Metric-only (scalar revenue) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| E02 | sql | Edge shapes | Dimension-only (distinct values of one dim, F3) | PASS | NOT_SUPPORTED | MISMATCH | 09_edge_shapes.yaml |
| E03 | sql | Edge shapes | Dimension-only with role alias (still DISTINCT) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| SL01 | sql | Sort / limit | Top-5 customers by revenue (ORDER BY alias + TOP) | PASS | NOT_SUPPORTED | MISMATCH | 10_sort_limit.yaml |
| MD01 | sql | Metric-driven join | promo_revenue alone (needs part via METRIC_FIELD_REF) | PASS | NOT_SUPPORTED | MISMATCH | 11_metric_driven_join.yaml |
| CB01 | sql | Cube | exec_dashboard cube — total_net_revenue (scalar) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 12_cube_source_query.yaml |
| FM01 | sql | Filtered Metrics | Base metric alongside a single-filter variant (exams only) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM02 | sql | Filtered Metrics | Multiple single-filter variants over the same base | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM03 | sql | Filtered Metrics | Composite filter spanning two datasets (AND across dims) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM04 | sql | Filtered Metrics | COUNT-base filtered variant (exam_count) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM05 | sql | Filtered Metrics | Filter dim is also an explicit dimension | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| B01 | python | Baseline | Revenue by customer market segment (2-hop) | PASS | NOT_SUPPORTED | MISMATCH | 01_baseline.yaml |
| B02 | python | Baseline | Single-table AVG (avg_qty by return flag) | PASS | PASS | MATCH | 01_baseline.yaml |
| B03 | python | Baseline | 5-hop traversal with all intermediates named (revenue by region) | PASS | NOT_SUPPORTED | MISMATCH | 01_baseline.yaml |
| F01 | python | Filters | Date filter with DATE literal | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F02 | python | Filters | LIKE filter (priority starts with 1-) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F03 | python | Filters | IN list (post-F1 — caller supplies parens, compiler does not wrap) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F04 | python | Filters | Filter on region.r_name with region not in dims (F2 auto-include) | PASS | NOT_SUPPORTED | MISMATCH | 02_filters.yaml |
| F05 | python | Filters | Unquoted string value (caller error — must still fail cleanly) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 02_filters.yaml |
| R01 | python | Ratio | promo_share by region (5-hop + part) | PASS | NOT_SUPPORTED | MISMATCH | 03_ratio_and_having.yaml |
| R02 | python | HAVING | HAVING promo_share > 0.1 | PASS | NOT_SUPPORTED | MISMATCH | 03_ratio_and_having.yaml |
| P01 | python | BFS | Auto-intermediates — revenue by region with NO intermediates named | PASS | PASS | MATCH | 04_path_resolution.yaml |
| P02 | python | Ambiguous path | Ambiguous path — revenue by supplier direct, NOT via partsupp | PASS | NOT_SUPPORTED | MISMATCH | 04_path_resolution.yaml |
| RP01 | python | Role-playing dimension | Role pin — customer_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP02 | python | Role-playing dimension | Role pin — supplier_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP03 | python | Role-playing dimension | BOTH roles in one query — nation joined twice with different aliases | PASS | PASS | MATCH | 05_role_playing.yaml |
| C01 | python | Chasm trap | revenue + total_availqty by part — compiler flags CHASM_WARNING | COMPILE_REJECTED | NOT_SUPPORTED | MISMATCH | 06_chasm_trap.yaml |
| FO01 | python | Fan-out | count_orders grouped at lineitem grain (DISTINCT survives fan-out) | PASS | NOT_SUPPORTED | MISMATCH | 07_fanout.yaml |
| TG01 | python | Time grain | No grain (day-level, default) | PASS | NOT_SUPPORTED | MISMATCH | 08_time_grain.yaml |
| TG02 | python | Time grain | Monthly rollup (:MONTH) | PASS | NOT_SUPPORTED | MISMATCH | 08_time_grain.yaml |
| TG03 | python | Time grain | Yearly rollup (:YEAR) | PASS | PASS | MATCH | 08_time_grain.yaml |
| TG04 | python | Time grain | Quarter rollup (:QUARTER) | PASS | PASS | MATCH | 08_time_grain.yaml |
| E01 | python | Edge shapes | Metric-only (scalar revenue) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| E02 | python | Edge shapes | Dimension-only (distinct values of one dim, F3) | PASS | NOT_SUPPORTED | MISMATCH | 09_edge_shapes.yaml |
| E03 | python | Edge shapes | Dimension-only with role alias (still DISTINCT) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| SL01 | python | Sort / limit | Top-5 customers by revenue (ORDER BY alias + TOP) | PASS | NOT_SUPPORTED | MISMATCH | 10_sort_limit.yaml |
| MD01 | python | Metric-driven join | promo_revenue alone (needs part via METRIC_FIELD_REF) | PASS | NOT_SUPPORTED | MISMATCH | 11_metric_driven_join.yaml |
| CB01 | python | Cube | exec_dashboard cube — total_net_revenue (scalar) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 12_cube_source_query.yaml |
| FM01 | python | Filtered Metrics | Base metric alongside a single-filter variant (exams only) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM02 | python | Filtered Metrics | Multiple single-filter variants over the same base | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM03 | python | Filtered Metrics | Composite filter spanning two datasets (AND across dims) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM04 | python | Filtered Metrics | COUNT-base filtered variant (exam_count) | PASS | PASS | MATCH | 13_filtered_metrics.yaml |
| FM05 | python | Filtered Metrics | Filter dim is also an explicit dimension | PASS | PASS | MATCH | 13_filtered_metrics.yaml |


### Outcome distribution (by engine)

| engine | outcome | count |
| --- | --- | --- |
| python | NOT_SUPPORTED | 16 |
| python | PASS | 14 |
| python | RUNTIME_ERROR | 2 |
| sql | NOT_SUPPORTED | 16 |
| sql | PASS | 14 |
| sql | RUNTIME_ERROR | 2 |


### Expectation agreement (by engine)

| engine | agreement | count |
| --- | --- | --- |
| python | MATCH | 16 |
| python | MISMATCH | 16 |
| sql | MATCH | 16 |
| sql | MISMATCH | 16 |


### Engine parity (SP vs Python)

| id | sql | python | match |
| --- | --- | --- | --- |
| B01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| B02 | PASS | PASS | = |
| B03 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| C01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| CB01 | RUNTIME_ERROR | RUNTIME_ERROR | = |
| E01 | PASS | PASS | = |
| E02 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| E03 | PASS | PASS | = |
| F01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| F02 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| F03 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| F04 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| F05 | RUNTIME_ERROR | RUNTIME_ERROR | = |
| FM01 | PASS | PASS | = |
| FM02 | PASS | PASS | = |
| FM03 | PASS | PASS | = |
| FM04 | PASS | PASS | = |
| FM05 | PASS | PASS | = |
| FO01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| MD01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| P01 | PASS | PASS | = |
| P02 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| R01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| R02 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| RP01 | PASS | PASS | = |
| RP02 | PASS | PASS | = |
| RP03 | PASS | PASS | = |
| SL01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| TG01 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| TG02 | NOT_SUPPORTED | NOT_SUPPORTED | = |
| TG03 | PASS | PASS | = |
| TG04 | PASS | PASS | = |


### Mismatches

| id | engine | expected | actual | title |
| --- | --- | --- | --- | --- |
| B01 | sql | PASS | NOT_SUPPORTED | Revenue by customer market segment (2-hop) |
| B03 | sql | PASS | NOT_SUPPORTED | 5-hop traversal with all intermediates named (revenue by region) |
| F01 | sql | PASS | NOT_SUPPORTED | Date filter with DATE literal |
| F02 | sql | PASS | NOT_SUPPORTED | LIKE filter (priority starts with 1-) |
| F03 | sql | PASS | NOT_SUPPORTED | IN list (post-F1 — caller supplies parens, compiler does not wrap) |
| F04 | sql | PASS | NOT_SUPPORTED | Filter on region.r_name with region not in dims (F2 auto-include) |
| R01 | sql | PASS | NOT_SUPPORTED | promo_share by region (5-hop + part) |
| R02 | sql | PASS | NOT_SUPPORTED | HAVING promo_share > 0.1 |
| P02 | sql | PASS | NOT_SUPPORTED | Ambiguous path — revenue by supplier direct, NOT via partsupp |
| C01 | sql | COMPILE_REJECTED | NOT_SUPPORTED | revenue + total_availqty by part — compiler flags CHASM_WARNING |
| FO01 | sql | PASS | NOT_SUPPORTED | count_orders grouped at lineitem grain (DISTINCT survives fan-out) |
| TG01 | sql | PASS | NOT_SUPPORTED | No grain (day-level, default) |
| TG02 | sql | PASS | NOT_SUPPORTED | Monthly rollup (:MONTH) |
| E02 | sql | PASS | NOT_SUPPORTED | Dimension-only (distinct values of one dim, F3) |
| SL01 | sql | PASS | NOT_SUPPORTED | Top-5 customers by revenue (ORDER BY alias + TOP) |
| MD01 | sql | PASS | NOT_SUPPORTED | promo_revenue alone (needs part via METRIC_FIELD_REF) |
| B01 | python | PASS | NOT_SUPPORTED | Revenue by customer market segment (2-hop) |
| B03 | python | PASS | NOT_SUPPORTED | 5-hop traversal with all intermediates named (revenue by region) |
| F01 | python | PASS | NOT_SUPPORTED | Date filter with DATE literal |
| F02 | python | PASS | NOT_SUPPORTED | LIKE filter (priority starts with 1-) |
| F03 | python | PASS | NOT_SUPPORTED | IN list (post-F1 — caller supplies parens, compiler does not wrap) |
| F04 | python | PASS | NOT_SUPPORTED | Filter on region.r_name with region not in dims (F2 auto-include) |
| R01 | python | PASS | NOT_SUPPORTED | promo_share by region (5-hop + part) |
| R02 | python | PASS | NOT_SUPPORTED | HAVING promo_share > 0.1 |
| P02 | python | PASS | NOT_SUPPORTED | Ambiguous path — revenue by supplier direct, NOT via partsupp |
| C01 | python | COMPILE_REJECTED | NOT_SUPPORTED | revenue + total_availqty by part — compiler flags CHASM_WARNING |
| FO01 | python | PASS | NOT_SUPPORTED | count_orders grouped at lineitem grain (DISTINCT survives fan-out) |
| TG01 | python | PASS | NOT_SUPPORTED | No grain (day-level, default) |
| TG02 | python | PASS | NOT_SUPPORTED | Monthly rollup (:MONTH) |
| E02 | python | PASS | NOT_SUPPORTED | Dimension-only (distinct values of one dim, F3) |
| SL01 | python | PASS | NOT_SUPPORTED | Top-5 customers by revenue (ORDER BY alias + TOP) |
| MD01 | python | PASS | NOT_SUPPORTED | promo_revenue alone (needs part via METRIC_FIELD_REF) |

