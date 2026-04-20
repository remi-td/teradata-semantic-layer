# Test Results — Teradata Semantic Catalog

- Run against `demo_user@mcp-vikzqtnd0db0nglk.env.clearscape.teradata.com`
- Cases loaded: **27**  
- Source: `/Users/remi.turpaud/Code/semantic-layer/tests/cases/*.yaml`

## Case results


### B01 — Revenue by customer market segment (2-hop)

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Canonical fact → dim traversal with two intermediate hops.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- |
| FURNITURE | 4-NOT SPECIFIED | 23866.92 |
| HOUSEHOLD | 1-URGENT | 17220.8 |
| BUILDING | 5-LOW | 148689.66 |
| MACHINERY | 2-HIGH | 52393.6 |
| MACHINERY | 1-URGENT | 67833.95 |
| AUTOMOBILE | 2-HIGH | 99155.38 |
| AUTOMOBILE | 4-NOT SPECIFIED | 30738.12 |
| FURNITURE | 3-MEDIUM | 82119.25 |
| HOUSEHOLD | 5-LOW | 10471.68 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| AUTOMOBILE | 3-MEDIUM | 12471.48 |
| AUTOMOBILE | 1-URGENT | 116907.74 |
| BUILDING | 2-HIGH | 44464.2 |
| BUILDING | 4-NOT SPECIFIED | 66232.34 |
| AUTOMOBILE | 5-LOW | 101344.8282 |

**Reference SQL:**
```sql
SELECT orders.o_orderpriority, customer.c_mktsegment,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 GROUP BY orders.o_orderpriority, customer.c_mktsegment
```

**Reference results:**
| o_orderpriority | c_mktsegment | revenue |
| --- | --- | --- |
| 2-HIGH | BUILDING | 44464.2 |
| 2-HIGH | AUTOMOBILE | 99155.38 |
| 1-URGENT | HOUSEHOLD | 17220.8 |
| 2-HIGH | MACHINERY | 52393.6 |
| 5-LOW | HOUSEHOLD | 10471.68 |
| 1-URGENT | AUTOMOBILE | 116907.74 |
| 3-MEDIUM | HOUSEHOLD | 17252 |
| 3-MEDIUM | AUTOMOBILE | 12471.48 |
| 3-MEDIUM | FURNITURE | 82119.25 |
| 1-URGENT | MACHINERY | 67833.95 |
| 4-NOT SPECIFIED | BUILDING | 66232.34 |
| 4-NOT SPECIFIED | AUTOMOBILE | 30738.12 |
| 5-LOW | BUILDING | 148689.66 |
| 5-LOW | AUTOMOBILE | 101344.8282 |
| 4-NOT SPECIFIED | FURNITURE | 23866.92 |

**Outcome:** PASS — rows match reference.


### B02 — Single-table AVG (avg_qty by return flag)

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
  FROM demo_user.lineitem AS lineitem GROUP BY lineitem.l_returnflag, lineitem.l_linestatus
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
  FROM demo_user.lineitem AS lineitem
 GROUP BY lineitem.l_returnflag, lineitem.l_linestatus
```

**Reference results:**
| l_returnflag | l_linestatus | avg_qty |
| --- | --- | --- |
| A  | F  | 32 |
| N  | O  | 27.3684 |
| R  | F  | 32.3077 |

**Outcome:** PASS — rows match reference.


### B03 — 5-hop traversal with all intermediates named (revenue by region)

**Category:** Baseline  
**Source:** `01_baseline.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, nation, region`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, nation.n_name AS n_name, orders.o_orderpriority AS o_orderpriority, region.r_name AS r_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.nation AS nation ON customer.c_nationkey = nation.n_nationkey 
    INNER JOIN demo_user.region AS region ON nation.n_regionkey = region.r_regionkey GROUP BY customer.c_mktsegment, nation.n_name, orders.o_orderpriority, region.r_name
```

**Compiled-SQL results:**
| c_mktsegment | n_name | o_orderpriority | r_name | revenue |
| --- | --- | --- | --- | --- |
| BUILDING | IRAQ | 4-NOT SPECIFIED | MIDDLE EAST | 51262.1 |
| HOUSEHOLD | BRAZIL | 5-LOW | AMERICA | 10471.68 |
| AUTOMOBILE | ARGENTINA | 5-LOW | AMERICA | 101344.8282 |
| BUILDING | UNITED STATES | 2-HIGH | AMERICA | 44464.2 |
| AUTOMOBILE | FRANCE | 4-NOT SPECIFIED | EUROPE | 30738.12 |
| FURNITURE | GERMANY | 3-MEDIUM | EUROPE | 82119.25 |
| BUILDING | INDIA | 5-LOW | ASIA | 13017.6 |
| MACHINERY | EGYPT | 1-URGENT | MIDDLE EAST | 67833.95 |
| FURNITURE | GERMANY | 4-NOT SPECIFIED | EUROPE | 23866.92 |
| HOUSEHOLD | CANADA | 3-MEDIUM | AMERICA | 17252 |
| BUILDING | IRAQ | 5-LOW | MIDDLE EAST | 27063 |
| MACHINERY | EGYPT | 2-HIGH | MIDDLE EAST | 52393.6 |
| HOUSEHOLD | JAPAN | 1-URGENT | ASIA | 17220.8 |
| BUILDING | INDIA | 4-NOT SPECIFIED | ASIA | 14970.24 |
| AUTOMOBILE | ARGENTINA | 1-URGENT | AMERICA | 34314.14 |
| … and 4 more rows |

**Reference SQL:**
```sql
SELECT orders.o_orderpriority, customer.c_mktsegment, nation.n_name, region.r_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN demo_user.region   AS region   ON nation.n_regionkey = region.r_regionkey
 GROUP BY orders.o_orderpriority, customer.c_mktsegment, nation.n_name, region.r_name
```

**Reference results:**
| o_orderpriority | c_mktsegment | n_name | r_name | revenue |
| --- | --- | --- | --- | --- |
| 2-HIGH | MACHINERY | EGYPT | MIDDLE EAST | 52393.6 |
| 3-MEDIUM | HOUSEHOLD | CANADA | AMERICA | 17252 |
| 1-URGENT | MACHINERY | EGYPT | MIDDLE EAST | 67833.95 |
| 5-LOW | AUTOMOBILE | ARGENTINA | AMERICA | 101344.8282 |
| 5-LOW | BUILDING | UNITED STATES | AMERICA | 108609.06 |
| 3-MEDIUM | AUTOMOBILE | UNITED STATES | AMERICA | 12471.48 |
| 3-MEDIUM | FURNITURE | GERMANY | EUROPE | 82119.25 |
| 5-LOW | BUILDING | IRAQ | MIDDLE EAST | 27063 |
| 2-HIGH | BUILDING | UNITED STATES | AMERICA | 44464.2 |
| 5-LOW | HOUSEHOLD | BRAZIL | AMERICA | 10471.68 |
| 4-NOT SPECIFIED | AUTOMOBILE | FRANCE | EUROPE | 30738.12 |
| 4-NOT SPECIFIED | FURNITURE | GERMANY | EUROPE | 23866.92 |
| 5-LOW | BUILDING | INDIA | ASIA | 13017.6 |
| 4-NOT SPECIFIED | BUILDING | IRAQ | MIDDLE EAST | 51262.1 |
| 1-URGENT | AUTOMOBILE | FRANCE | EUROPE | 82593.6 |
| … and 4 more rows |

**Outcome:** PASS — rows match reference.


### F01 — Date filter with DATE literal

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"lineitem.l_shipdate|>=|DATE '1995-01-01'"`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey WHERE lineitem.l_shipdate >= DATE '1995-01-01' GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- |
| AUTOMOBILE | 2-HIGH | 99155.38 |
| BUILDING | 5-LOW | 113269.02 |
| MACHINERY | 2-HIGH | 52393.6 |
| AUTOMOBILE | 1-URGENT | 116907.74 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| FURNITURE | 3-MEDIUM | 82119.25 |
| BUILDING | 4-NOT SPECIFIED | 66232.34 |
| AUTOMOBILE | 3-MEDIUM | 12471.48 |

**Reference SQL:**
```sql
SELECT orders.o_orderpriority, customer.c_mktsegment,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 WHERE lineitem.l_shipdate >= DATE '1995-01-01'
 GROUP BY orders.o_orderpriority, customer.c_mktsegment
```

**Reference results:**
| o_orderpriority | c_mktsegment | revenue |
| --- | --- | --- |
| 3-MEDIUM | FURNITURE | 82119.25 |
| 2-HIGH | AUTOMOBILE | 99155.38 |
| 3-MEDIUM | HOUSEHOLD | 17252 |
| 2-HIGH | MACHINERY | 52393.6 |
| 5-LOW | BUILDING | 113269.02 |
| 1-URGENT | AUTOMOBILE | 116907.74 |
| 4-NOT SPECIFIED | BUILDING | 66232.34 |
| 3-MEDIUM | AUTOMOBILE | 12471.48 |

**Outcome:** PASS — rows match reference.


### F02 — LIKE filter (priority starts with 1-)

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment'`
- `where` = `"orders.o_orderpriority|LIKE|'1-%'"`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey WHERE orders.o_orderpriority LIKE '1-%' GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- |
| MACHINERY | 1-URGENT | 67833.95 |
| HOUSEHOLD | 1-URGENT | 17220.8 |
| AUTOMOBILE | 1-URGENT | 116907.74 |

**Reference SQL:**
```sql
SELECT orders.o_orderpriority, customer.c_mktsegment,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 WHERE orders.o_orderpriority LIKE '1-%'
 GROUP BY orders.o_orderpriority, customer.c_mktsegment
```

**Reference results:**
| o_orderpriority | c_mktsegment | revenue |
| --- | --- | --- |
| 1-URGENT | AUTOMOBILE | 116907.74 |
| 1-URGENT | HOUSEHOLD | 17220.8 |
| 1-URGENT | MACHINERY | 67833.95 |

**Outcome:** PASS — rows match reference.


### F03 — IN list (post-F1 — caller supplies parens, compiler does not wrap)

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F1 compiler bug — now fixed.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderstatus'`
- `where` = `"orders.o_orderstatus|IN|('O','F')"`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderstatus AS o_orderstatus, COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM demo_user.orders AS orders 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey WHERE orders.o_orderstatus IN ('O','F') GROUP BY customer.c_mktsegment, orders.o_orderstatus
```

**Compiled-SQL results:**
| c_mktsegment | o_orderstatus | count_orders |
| --- | --- | --- |
| MACHINERY | F  | 1 |
| AUTOMOBILE | O  | 3 |
| BUILDING | O  | 5 |
| BUILDING | F  | 2 |
| FURNITURE | F  | 1 |
| MACHINERY | O  | 1 |
| HOUSEHOLD | F  | 2 |
| AUTOMOBILE | F  | 3 |
| FURNITURE | O  | 1 |
| HOUSEHOLD | O  | 1 |

**Reference SQL:**
```sql
SELECT customer.c_mktsegment, orders.o_orderstatus,
       COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM demo_user.orders AS orders
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 WHERE orders.o_orderstatus IN ('O','F')
 GROUP BY customer.c_mktsegment, orders.o_orderstatus
```

**Reference results:**
| c_mktsegment | o_orderstatus | count_orders |
| --- | --- | --- |
| MACHINERY | F  | 1 |
| AUTOMOBILE | O  | 3 |
| BUILDING | O  | 5 |
| BUILDING | F  | 2 |
| FURNITURE | F  | 1 |
| MACHINERY | O  | 1 |
| HOUSEHOLD | F  | 2 |
| AUTOMOBILE | F  | 3 |
| FURNITURE | O  | 1 |
| HOUSEHOLD | O  | 1 |

**Outcome:** PASS — rows match reference.


### F04 — Filter on region.r_name with region not in dims (F2 auto-include)

**Category:** Filters  
**Source:** `02_filters.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F2 compiler bug — region dataset is now auto-included from the WHERE.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`
- `where` = `"region.r_name|=|'AMERICA'"`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, nation, region`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.nation AS nation ON customer.c_nationkey = nation.n_nationkey 
    INNER JOIN demo_user.region AS region ON nation.n_regionkey = region.r_regionkey WHERE region.r_name = 'AMERICA' GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- |
| AUTOMOBILE | 2-HIGH | 99155.38 |
| BUILDING | 5-LOW | 108609.06 |
| AUTOMOBILE | 3-MEDIUM | 12471.48 |
| HOUSEHOLD | 5-LOW | 10471.68 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| AUTOMOBILE | 1-URGENT | 34314.14 |
| BUILDING | 2-HIGH | 44464.2 |
| AUTOMOBILE | 5-LOW | 101344.8282 |

**Reference SQL:**
```sql
SELECT customer.c_mktsegment, orders.o_orderpriority,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN demo_user.region   AS region   ON nation.n_regionkey = region.r_regionkey
 WHERE region.r_name = 'AMERICA'
 GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Reference results:**
| c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- |
| AUTOMOBILE | 2-HIGH | 99155.38 |
| BUILDING | 5-LOW | 108609.06 |
| AUTOMOBILE | 3-MEDIUM | 12471.48 |
| HOUSEHOLD | 5-LOW | 10471.68 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| AUTOMOBILE | 1-URGENT | 34314.14 |
| BUILDING | 2-HIGH | 44464.2 |
| AUTOMOBILE | 5-LOW | 101344.8282 |

**Outcome:** PASS — rows match reference.


### F05 — Unquoted string value (caller error — must still fail cleanly)

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
  FROM demo_user.orders AS orders WHERE orders.o_orderstatus = O GROUP BY orders.o_orderstatus
```

**Runtime error on compiled SQL:** `[Version 20.0.0.15] [Session 4200] [Teradata Database] [Error 5628] Column O not found in demo_user.orders.`

**Outcome:** RUNTIME_ERROR


### R01 — promo_share by region (5-hop + part)

**Category:** Ratio  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'orders.o_orderpriority,customer.c_mktsegment,nation.n_name,region.r_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, part, nation, region`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, nation.n_name AS n_name, orders.o_orderpriority AS o_orderpriority, region.r_name AS r_name, CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS DECIMAL(18,6)) / NULLIFZERO(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))) AS promo_share
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.part AS part ON lineitem.l_partkey = part.p_partkey 
    INNER JOIN demo_user.nation AS nation ON customer.c_nationkey = nation.n_nationkey 
    INNER JOIN demo_user.region AS region ON nation.n_regionkey = region.r_regionkey GROUP BY customer.c_mktsegment, nation.n_name, orders.o_orderpriority, region.r_name
```

**Compiled-SQL results:**
| c_mktsegment | n_name | o_orderpriority | r_name | promo_share |
| --- | --- | --- | --- | --- |
| BUILDING | IRAQ | 4-NOT SPECIFIED | MIDDLE EAST | 0.3931 |
| HOUSEHOLD | BRAZIL | 5-LOW | AMERICA | 0 |
| AUTOMOBILE | ARGENTINA | 5-LOW | AMERICA | 0.3951 |
| BUILDING | UNITED STATES | 2-HIGH | AMERICA | 0.4279 |
| AUTOMOBILE | FRANCE | 4-NOT SPECIFIED | EUROPE | 0 |
| FURNITURE | GERMANY | 3-MEDIUM | EUROPE | 0 |
| BUILDING | INDIA | 5-LOW | ASIA | 0 |
| MACHINERY | EGYPT | 1-URGENT | MIDDLE EAST | 0.4051 |
| FURNITURE | GERMANY | 4-NOT SPECIFIED | EUROPE | 0 |
| HOUSEHOLD | CANADA | 3-MEDIUM | AMERICA | 1 |
| BUILDING | IRAQ | 5-LOW | MIDDLE EAST | 1 |
| MACHINERY | EGYPT | 2-HIGH | MIDDLE EAST | 0.497 |
| HOUSEHOLD | JAPAN | 1-URGENT | ASIA | 1 |
| BUILDING | INDIA | 4-NOT SPECIFIED | ASIA | 0 |
| AUTOMOBILE | ARGENTINA | 1-URGENT | AMERICA | 0 |
| … and 4 more rows |

**Reference SQL:**
```sql
SELECT orders.o_orderpriority, customer.c_mktsegment,
       nation.n_name, region.r_name,
       CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%'
                     THEN lineitem.l_extendedprice*(1 - lineitem.l_discount)
                     ELSE 0 END) AS DECIMAL(18,6))
       / NULLIFZERO(SUM(lineitem.l_extendedprice*(1 - lineitem.l_discount))) AS promo_share
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey   = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN demo_user.region   AS region   ON nation.n_regionkey   = region.r_regionkey
  JOIN demo_user.part     AS part     ON lineitem.l_partkey   = part.p_partkey
 GROUP BY orders.o_orderpriority, customer.c_mktsegment, nation.n_name, region.r_name
```

**Reference results:**
| o_orderpriority | c_mktsegment | n_name | r_name | promo_share |
| --- | --- | --- | --- | --- |
| 2-HIGH | MACHINERY | EGYPT | MIDDLE EAST | 0.497 |
| 3-MEDIUM | HOUSEHOLD | CANADA | AMERICA | 1 |
| 1-URGENT | MACHINERY | EGYPT | MIDDLE EAST | 0.4051 |
| 5-LOW | AUTOMOBILE | ARGENTINA | AMERICA | 0.3951 |
| 5-LOW | BUILDING | UNITED STATES | AMERICA | 0.679 |
| 3-MEDIUM | AUTOMOBILE | UNITED STATES | AMERICA | 0 |
| 3-MEDIUM | FURNITURE | GERMANY | EUROPE | 0 |
| 5-LOW | BUILDING | IRAQ | MIDDLE EAST | 1 |
| 2-HIGH | BUILDING | UNITED STATES | AMERICA | 0.4279 |
| 5-LOW | HOUSEHOLD | BRAZIL | AMERICA | 0 |
| 4-NOT SPECIFIED | AUTOMOBILE | FRANCE | EUROPE | 0 |
| 4-NOT SPECIFIED | FURNITURE | GERMANY | EUROPE | 0 |
| 5-LOW | BUILDING | INDIA | ASIA | 0 |
| 4-NOT SPECIFIED | BUILDING | IRAQ | MIDDLE EAST | 0.3931 |
| 1-URGENT | AUTOMOBILE | FRANCE | EUROPE | 0.5277 |
| … and 4 more rows |

**Outcome:** PASS — rows match reference.


### R02 — HAVING promo_share > 0.1

**Category:** HAVING  
**Source:** `03_ratio_and_having.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_share'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,nation.n_name'`
- `having` = `'promo_share|>|0.1'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, part, nation`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, nation.n_name AS n_name, orders.o_orderpriority AS o_orderpriority, CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS DECIMAL(18,6)) / NULLIFZERO(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))) AS promo_share
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.part AS part ON lineitem.l_partkey = part.p_partkey 
    INNER JOIN demo_user.nation AS nation ON customer.c_nationkey = nation.n_nationkey GROUP BY customer.c_mktsegment, nation.n_name, orders.o_orderpriority HAVING (CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS DECIMAL(18,6)) / NULLIFZERO(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)))) > 0.1
```

**Compiled-SQL results:**
| c_mktsegment | n_name | o_orderpriority | promo_share |
| --- | --- | --- | --- |
| HOUSEHOLD | CANADA | 3-MEDIUM | 1 |
| BUILDING | IRAQ | 5-LOW | 1 |
| BUILDING | IRAQ | 4-NOT SPECIFIED | 0.3931 |
| BUILDING | UNITED STATES | 5-LOW | 0.679 |
| HOUSEHOLD | JAPAN | 1-URGENT | 1 |
| AUTOMOBILE | FRANCE | 1-URGENT | 0.5277 |
| MACHINERY | EGYPT | 2-HIGH | 0.497 |
| AUTOMOBILE | ARGENTINA | 5-LOW | 0.3951 |
| AUTOMOBILE | UNITED STATES | 2-HIGH | 0.4487 |
| BUILDING | UNITED STATES | 2-HIGH | 0.4279 |
| MACHINERY | EGYPT | 1-URGENT | 0.4051 |

**Reference SQL:**
```sql
SELECT customer.c_mktsegment, orders.o_orderpriority, nation.n_name,
       CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%'
                     THEN lineitem.l_extendedprice*(1 - lineitem.l_discount)
                     ELSE 0 END) AS DECIMAL(18,6))
       / NULLIFZERO(SUM(lineitem.l_extendedprice*(1 - lineitem.l_discount))) AS promo_share
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey   = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN demo_user.part     AS part     ON lineitem.l_partkey   = part.p_partkey
 GROUP BY customer.c_mktsegment, orders.o_orderpriority, nation.n_name
HAVING (CAST(SUM(CASE WHEN part.p_type LIKE 'PROMO%'
                      THEN lineitem.l_extendedprice*(1 - lineitem.l_discount)
                      ELSE 0 END) AS DECIMAL(18,6))
        / NULLIFZERO(SUM(lineitem.l_extendedprice*(1 - lineitem.l_discount)))) > 0.1
```

**Reference results:**
| c_mktsegment | o_orderpriority | n_name | promo_share |
| --- | --- | --- | --- |
| HOUSEHOLD | 3-MEDIUM | CANADA | 1 |
| BUILDING | 4-NOT SPECIFIED | IRAQ | 0.3931 |
| MACHINERY | 2-HIGH | EGYPT | 0.497 |
| MACHINERY | 1-URGENT | EGYPT | 0.4051 |
| HOUSEHOLD | 1-URGENT | JAPAN | 1 |
| AUTOMOBILE | 2-HIGH | UNITED STATES | 0.4487 |
| BUILDING | 5-LOW | IRAQ | 1 |
| BUILDING | 5-LOW | UNITED STATES | 0.679 |
| AUTOMOBILE | 5-LOW | ARGENTINA | 0.3951 |
| AUTOMOBILE | 1-URGENT | FRANCE | 0.5277 |
| BUILDING | 2-HIGH | UNITED STATES | 0.4279 |

**Outcome:** PASS — rows match reference.


### P01 — Auto-intermediates — revenue by region with NO intermediates named

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
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.nation AS nation ON customer.c_nationkey = nation.n_nationkey 
    INNER JOIN demo_user.region AS region ON nation.n_regionkey = region.r_regionkey GROUP BY region.r_name
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
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
  JOIN demo_user.region   AS region   ON nation.n_regionkey = region.r_regionkey
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


### P02 — Ambiguous path — revenue by supplier direct, NOT via partsupp

**Category:** Ambiguous path  
**Source:** `04_path_resolution.yaml`  
**Expected outcome:** `PASS`  
**Notes:** lineitem has TWO paths to supplier — direct (l_suppkey) and via partsupp (l_partkey + l_suppkey → partsupp → supplier). The compiler should pick the direct MANY_TO_ONE edge. Taking the partsupp path would inflate revenue by the partsupp fan-out.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'supplier.s_name'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, supplier`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT supplier.s_name AS s_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey GROUP BY supplier.s_name
```

**Compiled-SQL results:**
| s_name | revenue |
| --- | --- |
| Supplier#000000006 | 84892.032 |
| Supplier#000000003 | 104061.86 |
| Supplier#000000001 | 125522.8324 |
| Supplier#000000010 | 35308 |
| Supplier#000000002 | 84161.9256 |
| Supplier#000000007 | 76042.88 |
| Supplier#000000005 | 66707.55 |
| Supplier#000000009 | 80919.2082 |
| Supplier#000000004 | 66223.092 |
| Supplier#000000008 | 167322.568 |

**Reference SQL:**
```sql
SELECT supplier.s_name,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
 GROUP BY supplier.s_name
```

**Reference results:**
| s_name | revenue |
| --- | --- |
| Supplier#000000006 | 84892.032 |
| Supplier#000000003 | 104061.86 |
| Supplier#000000001 | 125522.8324 |
| Supplier#000000010 | 35308 |
| Supplier#000000002 | 84161.9256 |
| Supplier#000000007 | 76042.88 |
| Supplier#000000005 | 66707.55 |
| Supplier#000000009 | 80919.2082 |
| Supplier#000000004 | 66223.092 |
| Supplier#000000008 | 167322.568 |

**Outcome:** PASS — rows match reference.


### RP01 — Role pin — customer_nation.n_name

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
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.nation AS customer_nation ON customer.c_nationkey = customer_nation.n_nationkey GROUP BY customer_nation.n_name
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
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.nation   AS nation   ON customer.c_nationkey = nation.n_nationkey
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


### RP02 — Role pin — supplier_nation.n_name

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
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey 
    INNER JOIN demo_user.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey GROUP BY supplier_nation.n_name
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
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN demo_user.nation   AS nation   ON supplier.s_nationkey = nation.n_nationkey
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


### RP03 — BOTH roles in one query — nation joined twice with different aliases

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
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey 
    INNER JOIN demo_user.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.nation AS customer_nation ON customer.c_nationkey = customer_nation.n_nationkey GROUP BY supplier_nation.n_name, customer_nation.n_name
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
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.nation   AS cn       ON customer.c_nationkey = cn.n_nationkey
  JOIN demo_user.supplier AS supplier ON lineitem.l_suppkey = supplier.s_suppkey
  JOIN demo_user.nation   AS sn       ON supplier.s_nationkey = sn.n_nationkey
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


### C01 — revenue + total_availqty by part — compiler flags CHASM_WARNING

**Category:** Chasm trap  
**Source:** `06_chasm_trap.yaml`  
**Expected outcome:** `COMPILE_REJECTED`  
**Notes:** is_valid=0 with validation_message beginning 'CHASM_WARNING'. The short-term contract is: refuse the request; caller splits into two separate per-grain requests (partsupp.p_name + lineitem.p_name) and joins the results client-side. A proper symmetric-aggregate sub-SELECT plan is deferred.


**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue,total_availqty'`
- `dimensions` = `'part.p_name'`

**is_valid:** `0` | **anchor:** `lineitem` | **joined:** `lineitem, part, partsupp`
**validation_message:** `CHASM_WARNING: metrics span two grains (lineitem, partsupp,) - numbers are likely double-counted. Split the request by grain.`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT part.p_name AS p_name, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue, SUM(partsupp.ps_availqty) AS total_availqty
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.part AS part ON lineitem.l_partkey = part.p_partkey 
    INNER JOIN demo_user.partsupp AS partsupp ON lineitem.l_partkey = partsupp.ps_partkey AND  lineitem.l_suppkey = partsupp.ps_suppkey GROUP BY part.p_name
```

**Outcome:** COMPILE_REJECTED — `CHASM_WARNING: metrics span two grains (lineitem, partsupp,) - numbers are likely double-counted. Split the request by grain.`


### FO01 — count_orders grouped at lineitem grain (DISTINCT survives fan-out)

**Category:** Fan-out  
**Source:** `07_fanout.yaml`  
**Expected outcome:** `PASS`  
**Notes:** count_orders = COUNT(DISTINCT orders.o_orderkey) — order count is preserved.

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'count_orders'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority,lineitem.l_returnflag'`

**is_valid:** `1` | **anchor:** `orders` | **joined:** `orders, lineitem, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, lineitem.l_returnflag AS l_returnflag, COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM demo_user.orders AS orders 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.lineitem AS lineitem ON lineitem.l_orderkey = orders.o_orderkey GROUP BY customer.c_mktsegment, orders.o_orderpriority, lineitem.l_returnflag
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | l_returnflag | count_orders |
| --- | --- | --- | --- |
| FURNITURE | 4-NOT SPECIFIED | R  | 1 |
| HOUSEHOLD | 5-LOW | R  | 1 |
| MACHINERY | 1-URGENT | R  | 1 |
| AUTOMOBILE | 2-HIGH | N  | 1 |
| MACHINERY | 2-HIGH | N  | 1 |
| AUTOMOBILE | 1-URGENT | N  | 1 |
| HOUSEHOLD | 1-URGENT | R  | 1 |
| BUILDING | 4-NOT SPECIFIED | N  | 2 |
| BUILDING | 5-LOW | N  | 3 |
| HOUSEHOLD | 3-MEDIUM | N  | 1 |
| BUILDING | 2-HIGH | R  | 1 |
| AUTOMOBILE | 4-NOT SPECIFIED | A  | 1 |
| AUTOMOBILE | 5-LOW | A  | 1 |
| AUTOMOBILE | 1-URGENT | R  | 1 |
| FURNITURE | 3-MEDIUM | N  | 1 |
| … and 3 more rows |

**Reference SQL:**
```sql
SELECT customer.c_mktsegment, orders.o_orderpriority, lineitem.l_returnflag,
       COUNT(DISTINCT orders.o_orderkey) AS count_orders
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 GROUP BY customer.c_mktsegment, orders.o_orderpriority, lineitem.l_returnflag
```

**Reference results:**
| c_mktsegment | o_orderpriority | l_returnflag | count_orders |
| --- | --- | --- | --- |
| FURNITURE | 4-NOT SPECIFIED | R  | 1 |
| HOUSEHOLD | 5-LOW | R  | 1 |
| MACHINERY | 1-URGENT | R  | 1 |
| AUTOMOBILE | 2-HIGH | N  | 1 |
| MACHINERY | 2-HIGH | N  | 1 |
| AUTOMOBILE | 1-URGENT | N  | 1 |
| HOUSEHOLD | 1-URGENT | R  | 1 |
| BUILDING | 4-NOT SPECIFIED | N  | 2 |
| BUILDING | 5-LOW | N  | 3 |
| HOUSEHOLD | 3-MEDIUM | N  | 1 |
| BUILDING | 2-HIGH | R  | 1 |
| AUTOMOBILE | 4-NOT SPECIFIED | A  | 1 |
| AUTOMOBILE | 5-LOW | A  | 1 |
| AUTOMOBILE | 1-URGENT | R  | 1 |
| FURNITURE | 3-MEDIUM | N  | 1 |
| … and 3 more rows |

**Outcome:** PASS — rows match reference.


### TG01 — No grain (day-level, default)

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate,customer.c_mktsegment'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderdate AS o_orderdate, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey GROUP BY customer.c_mktsegment, orders.o_orderdate
```

**Compiled-SQL results:**
| c_mktsegment | o_orderdate | revenue |
| --- | --- | --- |
| HOUSEHOLD | 1994-02-28 | 10471.68 |
| HOUSEHOLD | 1998-05-16 | 17252 |
| BUILDING | 1994-07-30 | 35420.64 |
| BUILDING | 1996-01-02 | 73188.42 |
| AUTOMOBILE | 1993-10-14 | 101344.8282 |
| AUTOMOBILE | 1995-07-01 | 82593.6 |
| MACHINERY | 1994-09-28 | 67833.95 |
| AUTOMOBILE | 1996-12-01 | 34314.14 |
| FURNITURE | 1992-11-22 | 23866.92 |
| MACHINERY | 1998-03-20 | 52393.6 |
| BUILDING | 1993-12-20 | 44464.2 |
| AUTOMOBILE | 1992-02-21 | 30738.12 |
| BUILDING | 1996-03-10 | 14970.24 |
| AUTOMOBILE | 1998-10-14 | 12471.48 |
| FURNITURE | 1997-05-04 | 82119.25 |
| … and 5 more rows |

**Reference SQL:**
```sql
SELECT orders.o_orderdate, customer.c_mktsegment,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 GROUP BY orders.o_orderdate, customer.c_mktsegment
```

**Reference results:**
| o_orderdate | c_mktsegment | revenue |
| --- | --- | --- |
| 1998-05-16 | HOUSEHOLD | 17252 |
| 1993-12-20 | BUILDING | 44464.2 |
| 1994-02-28 | HOUSEHOLD | 10471.68 |
| 1995-10-11 | BUILDING | 27063 |
| 1992-02-21 | AUTOMOBILE | 30738.12 |
| 1998-03-20 | MACHINERY | 52393.6 |
| 1995-07-01 | AUTOMOBILE | 82593.6 |
| 1995-10-21 | BUILDING | 13017.6 |
| 1996-01-02 | BUILDING | 73188.42 |
| 1997-01-11 | BUILDING | 51262.1 |
| 1992-11-22 | FURNITURE | 23866.92 |
| 1997-05-04 | FURNITURE | 82119.25 |
| 1993-04-14 | HOUSEHOLD | 17220.8 |
| 1996-01-10 | AUTOMOBILE | 99155.38 |
| 1998-10-14 | AUTOMOBILE | 12471.48 |
| … and 5 more rows |

**Outcome:** PASS — rows match reference.


### TG02 — Monthly rollup (:MONTH)

**Category:** Time grain  
**Source:** `08_time_grain.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'orders.o_orderdate:MONTH,customer.c_mktsegment'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, TRUNC(orders.o_orderdate, 'MM') AS o_orderdate_month, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey GROUP BY customer.c_mktsegment, TRUNC(orders.o_orderdate, 'MM')
```

**Compiled-SQL results:**
| c_mktsegment | o_orderdate_month | revenue |
| --- | --- | --- |
| FURNITURE | 1992-11-01 | 23866.92 |
| MACHINERY | 1998-03-01 | 52393.6 |
| BUILDING | 1997-01-01 | 51262.1 |
| AUTOMOBILE | 1993-10-01 | 101344.8282 |
| BUILDING | 1993-12-01 | 44464.2 |
| BUILDING | 1994-07-01 | 35420.64 |
| HOUSEHOLD | 1994-02-01 | 10471.68 |
| BUILDING | 1996-01-01 | 73188.42 |
| HOUSEHOLD | 1993-04-01 | 17220.8 |
| AUTOMOBILE | 1995-07-01 | 82593.6 |
| AUTOMOBILE | 1992-02-01 | 30738.12 |
| AUTOMOBILE | 1996-12-01 | 34314.14 |
| HOUSEHOLD | 1998-05-01 | 17252 |
| AUTOMOBILE | 1996-01-01 | 99155.38 |
| MACHINERY | 1994-09-01 | 67833.95 |
| … and 4 more rows |

**Reference SQL:**
```sql
SELECT TRUNC(orders.o_orderdate, 'MM') AS o_orderdate_month,
       customer.c_mktsegment,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 GROUP BY TRUNC(orders.o_orderdate, 'MM'), customer.c_mktsegment
```

**Reference results:**
| o_orderdate_month | c_mktsegment | revenue |
| --- | --- | --- |
| 1996-01-01 | AUTOMOBILE | 99155.38 |
| 1998-05-01 | HOUSEHOLD | 17252 |
| 1993-04-01 | HOUSEHOLD | 17220.8 |
| 1993-10-01 | AUTOMOBILE | 101344.8282 |
| 1997-01-01 | BUILDING | 51262.1 |
| 1996-01-01 | BUILDING | 73188.42 |
| 1995-07-01 | AUTOMOBILE | 82593.6 |
| 1998-03-01 | MACHINERY | 52393.6 |
| 1992-11-01 | FURNITURE | 23866.92 |
| 1998-10-01 | AUTOMOBILE | 12471.48 |
| 1993-12-01 | BUILDING | 44464.2 |
| 1996-12-01 | AUTOMOBILE | 34314.14 |
| 1996-03-01 | BUILDING | 14970.24 |
| 1995-10-01 | BUILDING | 40080.6 |
| 1994-09-01 | MACHINERY | 67833.95 |
| … and 4 more rows |

**Outcome:** PASS — rows match reference.


### TG03 — Yearly rollup (:YEAR)

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
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey GROUP BY TRUNC(orders.o_orderdate, 'Y')
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
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey
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


### TG04 — Quarter rollup (:QUARTER)

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
  FROM demo_user.orders AS orders GROUP BY TRUNC(orders.o_orderdate, 'Q')
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
  FROM demo_user.orders AS orders
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


### E01 — Metric-only (scalar revenue)

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
  FROM demo_user.lineitem AS lineitem
```

**Compiled-SQL results:**
| revenue |
| --- |
| 891161.9482 |

**Reference SQL:**
```sql
SELECT SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
```

**Reference results:**
| revenue |
| --- |
| 891161.9482 |

**Outcome:** PASS — rows match reference.


### E02 — Dimension-only (distinct values of one dim, F3)

**Category:** Edge shapes  
**Source:** `09_edge_shapes.yaml`  
**Expected outcome:** `PASS`  
**Notes:** Was F3 — dim-only requests now emit SELECT DISTINCT.

**Request:**
- `model` = `'tpch_orders'`
- `dimensions` = `'customer.c_mktsegment'`

**is_valid:** `1` | **anchor:** `customer` | **joined:** `customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT DISTINCT customer.c_mktsegment AS c_mktsegment
  FROM demo_user.customer AS customer
```

**Compiled-SQL results:**
| c_mktsegment |
| --- |
| FURNITURE |
| MACHINERY |
| AUTOMOBILE |
| HOUSEHOLD |
| BUILDING |

**Reference SQL:**
```sql
SELECT DISTINCT customer.c_mktsegment
  FROM demo_user.customer AS customer
```

**Reference results:**
| c_mktsegment |
| --- |
| FURNITURE |
| MACHINERY |
| AUTOMOBILE |
| HOUSEHOLD |
| BUILDING |

**Outcome:** PASS — rows match reference.


### E03 — Dimension-only with role alias (still DISTINCT)

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
  FROM demo_user.supplier AS supplier 
    INNER JOIN demo_user.nation AS supplier_nation ON supplier.s_nationkey = supplier_nation.n_nationkey
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
  FROM demo_user.supplier AS supplier
  JOIN demo_user.nation   AS nation ON supplier.s_nationkey = nation.n_nationkey
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


### SL01 — Top-5 customers by revenue (ORDER BY alias + TOP)

**Category:** Sort / limit  
**Source:** `10_sort_limit.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'revenue'`
- `dimensions` = `'customer.c_name,customer.c_mktsegment,orders.o_orderpriority'`
- `sort` = `'revenue DESC'`
- `limit` = `5`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT TOP 5 customer.c_name AS c_name, customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey GROUP BY customer.c_name, customer.c_mktsegment, orders.o_orderpriority ORDER BY revenue DESC
```

**Compiled-SQL results:**
| c_name | c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- | --- |
| Customer#000000001 | BUILDING | 5-LOW | 108609.06 |
| Customer#000000003 | AUTOMOBILE | 5-LOW | 101344.8282 |
| Customer#000000006 | AUTOMOBILE | 2-HIGH | 99155.38 |
| Customer#000000002 | AUTOMOBILE | 1-URGENT | 82593.6 |
| Customer#000000009 | FURNITURE | 3-MEDIUM | 82119.25 |

**Reference SQL:**
```sql
SELECT TOP 5 customer.c_name, customer.c_mktsegment, orders.o_orderpriority,
       SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
 GROUP BY customer.c_name, customer.c_mktsegment, orders.o_orderpriority
 ORDER BY revenue DESC
```

**Reference results:**
| c_name | c_mktsegment | o_orderpriority | revenue |
| --- | --- | --- | --- |
| Customer#000000001 | BUILDING | 5-LOW | 108609.06 |
| Customer#000000003 | AUTOMOBILE | 5-LOW | 101344.8282 |
| Customer#000000006 | AUTOMOBILE | 2-HIGH | 99155.38 |
| Customer#000000002 | AUTOMOBILE | 1-URGENT | 82593.6 |
| Customer#000000009 | FURNITURE | 3-MEDIUM | 82119.25 |

**Outcome:** PASS — rows match reference.


### MD01 — promo_revenue alone (needs part via METRIC_FIELD_REF)

**Category:** Metric-driven join  
**Source:** `11_metric_driven_join.yaml`  
**Expected outcome:** `PASS`  

**Request:**
- `model` = `'tpch_orders'`
- `metrics` = `'promo_revenue'`
- `dimensions` = `'customer.c_mktsegment,orders.o_orderpriority'`

**is_valid:** `1` | **anchor:** `lineitem` | **joined:** `lineitem, orders, customer, part`

**Compiled SQL:**
```sql
LOCKING ROW FOR ACCESS 
SELECT customer.c_mktsegment AS c_mktsegment, orders.o_orderpriority AS o_orderpriority, SUM(CASE WHEN part.p_type LIKE 'PROMO%' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS promo_revenue
  FROM demo_user.lineitem AS lineitem 
    INNER JOIN demo_user.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey 
    INNER JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey 
    INNER JOIN demo_user.part AS part ON lineitem.l_partkey = part.p_partkey GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Compiled-SQL results:**
| c_mktsegment | o_orderpriority | promo_revenue |
| --- | --- | --- |
| FURNITURE | 4-NOT SPECIFIED | 0 |
| HOUSEHOLD | 1-URGENT | 17220.8 |
| BUILDING | 5-LOW | 100813.4544 |
| MACHINERY | 2-HIGH | 26040 |
| MACHINERY | 1-URGENT | 27480 |
| AUTOMOBILE | 2-HIGH | 44492 |
| AUTOMOBILE | 4-NOT SPECIFIED | 0 |
| FURNITURE | 3-MEDIUM | 0 |
| HOUSEHOLD | 5-LOW | 0 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| AUTOMOBILE | 3-MEDIUM | 0 |
| AUTOMOBILE | 1-URGENT | 43584 |
| BUILDING | 2-HIGH | 19027.8 |
| BUILDING | 4-NOT SPECIFIED | 20152 |
| AUTOMOBILE | 5-LOW | 40039.128 |

**Reference SQL:**
```sql
SELECT customer.c_mktsegment, orders.o_orderpriority,
       SUM(CASE WHEN part.p_type LIKE 'PROMO%'
                THEN lineitem.l_extendedprice*(1 - lineitem.l_discount)
                ELSE 0 END) AS promo_revenue
  FROM demo_user.lineitem AS lineitem
  JOIN demo_user.orders   AS orders   ON lineitem.l_orderkey = orders.o_orderkey
  JOIN demo_user.customer AS customer ON orders.o_custkey = customer.c_custkey
  JOIN demo_user.part     AS part     ON lineitem.l_partkey = part.p_partkey
 GROUP BY customer.c_mktsegment, orders.o_orderpriority
```

**Reference results:**
| c_mktsegment | o_orderpriority | promo_revenue |
| --- | --- | --- |
| FURNITURE | 4-NOT SPECIFIED | 0 |
| HOUSEHOLD | 1-URGENT | 17220.8 |
| BUILDING | 5-LOW | 100813.4544 |
| MACHINERY | 2-HIGH | 26040 |
| MACHINERY | 1-URGENT | 27480 |
| AUTOMOBILE | 2-HIGH | 44492 |
| AUTOMOBILE | 4-NOT SPECIFIED | 0 |
| FURNITURE | 3-MEDIUM | 0 |
| HOUSEHOLD | 5-LOW | 0 |
| HOUSEHOLD | 3-MEDIUM | 17252 |
| AUTOMOBILE | 3-MEDIUM | 0 |
| AUTOMOBILE | 1-URGENT | 43584 |
| BUILDING | 2-HIGH | 19027.8 |
| BUILDING | 4-NOT SPECIFIED | 20152 |
| AUTOMOBILE | 5-LOW | 40039.128 |

**Outcome:** PASS — rows match reference.


### CB01 — exec_dashboard cube — total_net_revenue (scalar)

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
-- This runs inside Teradata; any agent / BI consumer sees a flat
-- dimensional result-set: (order_id, product_id, order_date,
-- order_week, order_year, region, country, sales_channel,
-- customer_segment, product_category, product_brand, is_new_customer,
-- gross_revenue, net_revenue, units_sold, is_returned).

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

**Runtime error on compiled SQL:** `[Version 20.0.0.15] [Session 4200] [Teradata Database] [Error 3802] Database 'sales' does not exist.`

**Outcome:** RUNTIME_ERROR


## Summary

| id | category | title | expected | actual | agreement | file |
| --- | --- | --- | --- | --- | --- | --- |
| B01 | Baseline | Revenue by customer market segment (2-hop) | PASS | PASS | MATCH | 01_baseline.yaml |
| B02 | Baseline | Single-table AVG (avg_qty by return flag) | PASS | PASS | MATCH | 01_baseline.yaml |
| B03 | Baseline | 5-hop traversal with all intermediates named (revenue by region) | PASS | PASS | MATCH | 01_baseline.yaml |
| F01 | Filters | Date filter with DATE literal | PASS | PASS | MATCH | 02_filters.yaml |
| F02 | Filters | LIKE filter (priority starts with 1-) | PASS | PASS | MATCH | 02_filters.yaml |
| F03 | Filters | IN list (post-F1 — caller supplies parens, compiler does not wrap) | PASS | PASS | MATCH | 02_filters.yaml |
| F04 | Filters | Filter on region.r_name with region not in dims (F2 auto-include) | PASS | PASS | MATCH | 02_filters.yaml |
| F05 | Filters | Unquoted string value (caller error — must still fail cleanly) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 02_filters.yaml |
| R01 | Ratio | promo_share by region (5-hop + part) | PASS | PASS | MATCH | 03_ratio_and_having.yaml |
| R02 | HAVING | HAVING promo_share > 0.1 | PASS | PASS | MATCH | 03_ratio_and_having.yaml |
| P01 | BFS | Auto-intermediates — revenue by region with NO intermediates named | PASS | PASS | MATCH | 04_path_resolution.yaml |
| P02 | Ambiguous path | Ambiguous path — revenue by supplier direct, NOT via partsupp | PASS | PASS | MATCH | 04_path_resolution.yaml |
| RP01 | Role-playing dimension | Role pin — customer_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP02 | Role-playing dimension | Role pin — supplier_nation.n_name | PASS | PASS | MATCH | 05_role_playing.yaml |
| RP03 | Role-playing dimension | BOTH roles in one query — nation joined twice with different aliases | PASS | PASS | MATCH | 05_role_playing.yaml |
| C01 | Chasm trap | revenue + total_availqty by part — compiler flags CHASM_WARNING | COMPILE_REJECTED | COMPILE_REJECTED | MATCH | 06_chasm_trap.yaml |
| FO01 | Fan-out | count_orders grouped at lineitem grain (DISTINCT survives fan-out) | PASS | PASS | MATCH | 07_fanout.yaml |
| TG01 | Time grain | No grain (day-level, default) | PASS | PASS | MATCH | 08_time_grain.yaml |
| TG02 | Time grain | Monthly rollup (:MONTH) | PASS | PASS | MATCH | 08_time_grain.yaml |
| TG03 | Time grain | Yearly rollup (:YEAR) | PASS | PASS | MATCH | 08_time_grain.yaml |
| TG04 | Time grain | Quarter rollup (:QUARTER) | PASS | PASS | MATCH | 08_time_grain.yaml |
| E01 | Edge shapes | Metric-only (scalar revenue) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| E02 | Edge shapes | Dimension-only (distinct values of one dim, F3) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| E03 | Edge shapes | Dimension-only with role alias (still DISTINCT) | PASS | PASS | MATCH | 09_edge_shapes.yaml |
| SL01 | Sort / limit | Top-5 customers by revenue (ORDER BY alias + TOP) | PASS | PASS | MATCH | 10_sort_limit.yaml |
| MD01 | Metric-driven join | promo_revenue alone (needs part via METRIC_FIELD_REF) | PASS | PASS | MATCH | 11_metric_driven_join.yaml |
| CB01 | Cube | exec_dashboard cube — total_net_revenue (scalar) | RUNTIME_ERROR | RUNTIME_ERROR | MATCH | 12_cube_source_query.yaml |


### Outcome distribution

| outcome | count |
| --- | --- |
| COMPILE_REJECTED | 1 |
| PASS | 24 |
| RUNTIME_ERROR | 2 |


### Expectation agreement

| agreement | count |
| --- | --- |
| MATCH | 27 |

