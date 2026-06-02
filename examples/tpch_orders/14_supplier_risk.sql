-- =========================================================================
-- Supplier Risk — two-version progressive maturity story.
-- Requires 11_scenario_tpch_orders.sql to have been loaded first.
--
-- MODEL FAMILY: supplier_risk
--
-- v1 (supplier_risk_v1): CUBE PATTERN — Level-0 maturity.
--    A single denormalized dataset (supplier_risk_cube) pre-joins everything
--    needed for supplier-risk analytics. No relationships, no decomposition.
--    Use this when you just want something working immediately.
--
-- v2 (supplier_risk_v2): NORMALIZED MODEL — Level-2 maturity.
--    Reuses the existing tpch_orders datasets (partsupp, supplier, nation,
--    region, part, lineitem) via MODEL_DATASET links. No duplicate data.
--    Metrics point to the same field_ids already registered by tpch_orders.
--    Demonstrates how dataset sharing across model versions works.
--
-- The is_latest / is_deprecated flags tell the compiler which version to
-- use when a caller requests 'supplier_risk' without a version suffix:
--   v1: is_latest=0 (deprecated in favour of v2)
--   v2: is_latest=1 (current)
-- =========================================================================

------------------------------------------------------------------------------
-- supplier_risk_v1 (cube-based, Level-0)
------------------------------------------------------------------------------

INSERT INTO demo_user.SEMANTIC_MODEL (
    model_name, description, owner_user, owner_group,
    model_family, model_version, is_latest, is_deprecated
)
VALUES (
    'supplier_risk_v1',
    'Supplier risk analytics — cube pattern (v1). Single denormalized dataset. Use v2 for the normalized model.',
    'DEMO_USER',
    'supply-chain-team',
    'supplier_risk', 1, 0, 0
);

-- Cube dataset: fully denormalized, pre-joined source query
INSERT INTO demo_user.DATASET (
    dataset_name, description, granularity_desc,
    DataBaseName, TableName, source_query
)
VALUES (
    'supplier_risk_cube',
    'Denormalized supplier-risk cube. Covers part supply cost, availability, and lineitem revenue exposure. Joins are baked in.',
    'One row per (ps_suppkey, ps_partkey, l_orderkey) combination.',
    NULL, NULL,
    'SELECT
    s.s_suppkey,
    s.s_name                                          AS supplier_name,
    s.s_acctbal                                       AS supplier_acct_bal,
    n.n_name                                          AS supplier_nation,
    r.r_name                                          AS supplier_region,
    p.p_brand                                         AS part_brand,
    p.p_type                                          AS part_type,
    p.p_size                                          AS part_size,
    ps.ps_supplycost                                  AS supply_cost,
    ps.ps_availqty                                    AS avail_qty,
    l.l_orderkey,
    l.l_extendedprice,
    l.l_discount,
    l.l_quantity,
    l.l_shipdate,
    CASE WHEN ps.ps_availqty < 100 THEN 1 ELSE 0 END AS is_low_stock
FROM tpch.PARTSUPP ps
JOIN tpch.SUPPLIER s  ON s.s_suppkey  = ps.ps_suppkey
JOIN tpch.PART     p  ON p.p_partkey  = ps.ps_partkey
JOIN tpch.NATION   n  ON n.n_nationkey = s.s_nationkey
JOIN tpch.REGION   r  ON r.r_regionkey = n.n_regionkey
LEFT JOIN tpch.LINEITEM l ON l.l_suppkey = s.s_suppkey
                          AND l.l_partkey = ps.ps_partkey
WHERE s.s_acctbal > 0'
);

-- Link supplier_risk_cube to supplier_risk_v1
INSERT INTO demo_user.MODEL_DATASET (model_id, dataset_id, is_primary)
SELECT m.model_id, d.dataset_id, 1
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v1' AND d.dataset_name='supplier_risk_cube';

-- Fields on supplier_risk_cube
INSERT INTO demo_user.FIELD (
    dataset_id, field_name, field_type_code, expression,
    description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order
)
SELECT d.dataset_id, x.fn, x.fc, x.expr, x.descr, x.lbl, x.isd, 0, x.dt, x.col, x.ord
FROM demo_user.DATASET d,
(
    SELECT CAST('supplier_name'   AS VARCHAR(200)) fn, CAST('K'  AS CHAR(1)) fc, CAST('supplier_name'   AS VARCHAR(10000)) expr, CAST('Supplier business name.'              AS VARCHAR(10000)) descr, CAST('Supplier'       AS VARCHAR(500)) lbl, CAST(1 AS BYTEINT) isd, CAST('VARCHAR(25)'  AS VARCHAR(200)) dt, CAST('supplier_name'   AS VARCHAR(128)) col, CAST(1  AS SMALLINT) ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'supplier_nation',  'A', 'supplier_nation',  'Nation where supplier is headquartered.',   'Supplier Nation', 1, 'VARCHAR(25)',   'supplier_nation',  2  FROM (SELECT 1 x) a
    UNION ALL SELECT 'supplier_region',  'A', 'supplier_region',  'World region of the supplier nation.',      'Supplier Region', 1, 'VARCHAR(25)',   'supplier_region',  3  FROM (SELECT 1 x) a
    UNION ALL SELECT 'part_brand',       'A', 'part_brand',       'Brand of the part.',                        'Part Brand',      1, 'VARCHAR(10)',   'part_brand',       4  FROM (SELECT 1 x) a
    UNION ALL SELECT 'part_type',        'A', 'part_type',        'Part type text.',                           'Part Type',       1, 'VARCHAR(25)',   'part_type',        5  FROM (SELECT 1 x) a
    UNION ALL SELECT 'supply_cost',      'A', 'supply_cost',      'Unit supply cost from this supplier.',      'Supply Cost',     0, 'DECIMAL(15,2)', 'supply_cost',      6  FROM (SELECT 1 x) a
    UNION ALL SELECT 'avail_qty',        'A', 'avail_qty',        'Available quantity at supplier.',           'Avail Qty',       0, 'INTEGER',       'avail_qty',        7  FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_extendedprice',  'A', 'l_extendedprice',  'Extended price on lineitem.',               'Extended Price',  0, 'DECIMAL(15,2)', 'l_extendedprice',  8  FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_discount',       'A', 'l_discount',       'Line discount.',                            'Discount',        0, 'DECIMAL(15,4)', 'l_discount',       9  FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_quantity',       'A', 'l_quantity',       'Ordered quantity.',                         'Quantity',        0, 'DECIMAL(15,2)', 'l_quantity',       10 FROM (SELECT 1 x) a
    UNION ALL SELECT 'is_low_stock',     'A', 'is_low_stock',     '1 = available quantity < 100 units.',       'Low Stock Flag',  1, 'BYTEINT',       'is_low_stock',     11 FROM (SELECT 1 x) a
) x
WHERE d.dataset_name='supplier_risk_cube';

-- Metrics on supplier_risk_v1

-- at_risk_revenue
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'at_risk_revenue',
       'Revenue exposure from suppliers that are low on stock (avail_qty < 100).',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN is_low_stock = 1 THEN l_extendedprice * (1 - l_discount) ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v1' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN supplier_risk_cube.l_extendedprice * (1 - supplier_risk_cube.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='at_risk_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN supplier_risk_cube.l_extendedprice * (1 - supplier_risk_cube.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='at_risk_revenue';

-- supplier_count
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'supplier_count',
       'Count of distinct suppliers.',
       d.dataset_id, 'SIMPLE', 0,
       'COUNT DISTINCT', 'supplier_name'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v1' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(DISTINCT supplier_risk_cube.supplier_name)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='supplier_count';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(DISTINCT supplier_risk_cube.supplier_name)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='supplier_count';

-- avg_supply_cost
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'avg_supply_cost',
       'Average unit supply cost across all (part, supplier) combinations.',
       d.dataset_id, 'SIMPLE', 0,
       'AVG', 'supply_cost'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v1' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'AVG(supplier_risk_cube.supply_cost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='avg_supply_cost';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'AVG(supplier_risk_cube.supply_cost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='avg_supply_cost';

-- low_stock_parts
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'low_stock_parts',
       'Count of (part, supplier) combinations with available quantity < 100.',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN is_low_stock = 1 THEN 1 ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v1' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='low_stock_parts';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v1' AND mt.metric_name='low_stock_parts';

-- AI context for v1
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'MODEL', m.model_id,
       'Supplier risk analytics — cube version. All dimensions and measures live in supplier_risk_cube. No joins needed. Use v2 (supplier_risk_v2) if you need to compose queries across the full tpch_orders supply chain.',
       NEW JSON('["supplier risk","supply risk","at risk suppliers","low stock"]'),
       'Supplier Risk v1 (Cube)'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='supplier_risk_v1';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'DATASET', d.dataset_id,
       'Flat denormalized cube. One row per (supplier, part, lineitem) triple where acctbal > 0. The is_low_stock flag (avail_qty < 100) is pre-computed. Use at_risk_revenue for revenue exposure and low_stock_parts for count of at-risk lines.',
       NEW JSON('["supplier cube","risk cube"]'),
       'Supplier Risk Cube'
FROM demo_user.DATASET d WHERE d.dataset_name='supplier_risk_cube';

------------------------------------------------------------------------------
-- supplier_risk_v2 (normalized, Level-2 — reuses tpch_orders datasets)
------------------------------------------------------------------------------

INSERT INTO demo_user.SEMANTIC_MODEL (
    model_name, description, owner_user, owner_group,
    model_family, model_version, is_latest, is_deprecated
)
VALUES (
    'supplier_risk_v2',
    'Supplier risk analytics — normalized model (v2). Shares datasets with tpch_orders. Latest version.',
    'DEMO_USER',
    'supply-chain-team',
    'supplier_risk', 2, 1, 0
);

-- Reuse existing datasets from tpch_orders via MODEL_DATASET links.
-- The datasets (partsupp, supplier, nation, region, part, lineitem) already
-- exist in DATASET from the tpch_orders scenario; we just add MODEL_DATASET
-- rows to link them to supplier_risk_v2.
INSERT INTO demo_user.MODEL_DATASET (model_id, dataset_id, is_primary)
SELECT m.model_id, d.dataset_id,
       CASE WHEN d.dataset_name='partsupp' THEN 1 ELSE 0 END
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v2'
  AND d.dataset_name IN ('partsupp','supplier','nation','region','part','lineitem');

-- Metrics on supplier_risk_v2 — point to the actual field_ids on normalized datasets

-- at_risk_revenue (v2)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'at_risk_revenue',
       'Revenue exposure from suppliers where partsupp.ps_availqty < 100.',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN ps_availqty < 100 THEN l_extendedprice * (1 - l_discount) ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v2' AND d.dataset_name='partsupp';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN partsupp.ps_availqty < 100 THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='at_risk_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN partsupp.ps_availqty < 100 THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='at_risk_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, CASE WHEN f.field_name IN ('l_extendedprice','l_discount') THEN 'MEASURE' ELSE 'FILTER' END
FROM demo_user.METRIC mt
JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
JOIN demo_user.DATASET d ON d.dataset_name IN ('partsupp','lineitem')
JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
     AND ((d.dataset_name='partsupp'  AND f.field_name='ps_availqty')
       OR (d.dataset_name='lineitem'  AND f.field_name IN ('l_extendedprice','l_discount')))
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='at_risk_revenue';

-- supplier_count (v2)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'supplier_count',
       'Count of distinct suppliers.',
       d.dataset_id, 'SIMPLE', 0,
       'COUNT DISTINCT', 's_suppkey'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v2' AND d.dataset_name='supplier';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(DISTINCT supplier.s_suppkey)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='supplier_count';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(DISTINCT supplier.s_suppkey)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='supplier_count';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt
JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
JOIN demo_user.DATASET d ON d.dataset_name='supplier'
JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='s_suppkey'
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='supplier_count';

-- avg_supply_cost (v2)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'avg_supply_cost',
       'Average unit supply cost across all (part, supplier) combinations.',
       d.dataset_id, 'SIMPLE', 0,
       'AVG', 'ps_supplycost'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v2' AND d.dataset_name='partsupp';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'AVG(partsupp.ps_supplycost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='avg_supply_cost';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'AVG(partsupp.ps_supplycost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='avg_supply_cost';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt
JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
JOIN demo_user.DATASET d ON d.dataset_name='partsupp'
JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_supplycost'
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='avg_supply_cost';

-- low_stock_parts (v2)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'low_stock_parts',
       'Count of (part, supplier) combinations with available quantity < 100.',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN ps_availqty < 100 THEN 1 ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='supplier_risk_v2' AND d.dataset_name='partsupp';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN partsupp.ps_availqty < 100 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='low_stock_parts';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN partsupp.ps_availqty < 100 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='low_stock_parts';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'FILTER'
FROM demo_user.METRIC mt
JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
JOIN demo_user.DATASET d ON d.dataset_name='partsupp'
JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_availqty'
WHERE m.model_name='supplier_risk_v2' AND mt.metric_name='low_stock_parts';

-- AI context for v2
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'MODEL', m.model_id,
       'Supplier risk analytics — normalized version. Shares the partsupp, supplier, part, nation, region, lineitem datasets from tpch_orders. Use relationship lineitem_to_partsupp for (part,supplier) composite joins. Prefer this over v1 for any query that also needs tpch_orders dimensions.',
       NEW JSON('["supplier risk","supply risk","at risk suppliers","low stock","normalized"]'),
       'Supplier Risk v2 (Normalized)'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='supplier_risk_v2';
