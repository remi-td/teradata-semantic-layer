-- =========================================================================
-- tpch_supply_risk — Level-0 cube model for supplier risk analytics.
--
-- Standalone model. Does NOT require tpch_orders to be loaded first.
-- Demonstrates the "start with a cube" pattern: a single denormalized
-- dataset pre-joins everything needed for supplier-risk analytics.
--
-- The progressive maturity story:
--   Monday   → load tpch_supply_risk (this file). Works immediately.
--   Friday   → switch consumers to tpch_orders, which already contains
--              all the underlying normalized datasets. The cube stays
--              queryable until explicitly deprecated.
-- =========================================================================

INSERT INTO demo_user.SEMANTIC_MODEL (
    model_name, description, owner_user, owner_group,
    model_family, model_version, is_latest, is_deprecated
)
VALUES (
    'tpch_supply_risk',
    'Supplier risk analytics — cube pattern. Single denormalized dataset covering part supply cost, availability, and revenue exposure. Graduate to tpch_orders for the full normalized model.',
    'DEMO_USER',
    'supply-chain-team',
    'tpch_supply_risk', 1, 1, 0
);

-- Cube dataset: fully denormalized, all joins baked into source_query
INSERT INTO demo_user.DATASET (
    dataset_name, description, granularity_desc,
    DataBaseName, TableName, source_query
)
VALUES (
    'supplier_risk_cube',
    'Denormalized supplier-risk cube. Covers part supply cost, availability, and lineitem revenue exposure per (supplier, part, lineitem) triple where acctbal > 0.',
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

-- Link supplier_risk_cube to tpch_supply_risk
INSERT INTO demo_user.MODEL_DATASET (model_id, dataset_id, is_primary)
SELECT m.model_id, d.dataset_id, 1
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='tpch_supply_risk' AND d.dataset_name='supplier_risk_cube';

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

-- Metrics

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'at_risk_revenue',
       'Revenue exposure from suppliers that are low on stock (avail_qty < 100).',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN is_low_stock = 1 THEN l_extendedprice * (1 - l_discount) ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='tpch_supply_risk' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN supplier_risk_cube.l_extendedprice * (1 - supplier_risk_cube.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='at_risk_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN supplier_risk_cube.l_extendedprice * (1 - supplier_risk_cube.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='at_risk_revenue';

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'supplier_count',
       'Count of distinct suppliers.',
       d.dataset_id, 'SIMPLE', 0,
       'COUNT DISTINCT', 'supplier_name'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='tpch_supply_risk' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(DISTINCT supplier_risk_cube.supplier_name)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='supplier_count';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(DISTINCT supplier_risk_cube.supplier_name)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='supplier_count';

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'avg_supply_cost',
       'Average unit supply cost across all (part, supplier) combinations.',
       d.dataset_id, 'SIMPLE', 0,
       'AVG', 'supply_cost'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='tpch_supply_risk' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'AVG(supplier_risk_cube.supply_cost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='avg_supply_cost';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'AVG(supplier_risk_cube.supply_cost)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='avg_supply_cost';

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, aggregate_fn, aggregate_arg)
SELECT m.model_id, 'low_stock_parts',
       'Count of (part, supplier) combinations with available quantity < 100.',
       d.dataset_id, 'SIMPLE', 1,
       'SUM', 'CASE WHEN is_low_stock = 1 THEN 1 ELSE 0 END'
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='tpch_supply_risk' AND d.dataset_name='supplier_risk_cube';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='low_stock_parts';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN supplier_risk_cube.is_low_stock = 1 THEN 1 ELSE 0 END)'
FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_supply_risk' AND mt.metric_name='low_stock_parts';

-- AI context
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'MODEL', m.model_id,
       'Supplier risk analytics — cube pattern. All dimensions and measures live in a single supplier_risk_cube dataset, no joins needed. For broader supply-chain analysis or to combine with order metrics, switch to the tpch_orders model which contains all the underlying normalized datasets.',
       NEW JSON('["supplier risk","supply risk","at risk suppliers","low stock","supplier analytics"]'),
       'TPC-H Supplier Risk (Cube)'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_supply_risk';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'DATASET', d.dataset_id,
       'Flat denormalized cube. One row per (supplier, part, lineitem) triple where acctbal > 0. The is_low_stock flag (avail_qty < 100) is pre-computed. Use at_risk_revenue for revenue exposure and low_stock_parts for count of at-risk lines.',
       NEW JSON('["supplier cube","risk cube","supply chain cube"]'),
       'Supplier Risk Cube'
FROM demo_user.DATASET d WHERE d.dataset_name='supplier_risk_cube';
