-- =========================================================================
-- Scenario B — TPC-H Honeydew-style order analytics.
-- Model name: tpch_orders
-- Uses the full TPC-H schema (lineitem, orders, customer, supplier, part,
-- partsupp, nation, region) to exercise multi-hop relationships and
-- composite joins.
-- =========================================================================

------------------------------------------------------------------------------
-- 1. Model
------------------------------------------------------------------------------
INSERT INTO demo_user.SEMANTIC_MODEL (model_name, description, owner_user, owner_group)
VALUES (
    'tpch_orders',
    'Honeydew-style TPC-H order analytics model: full supply-chain topology with lineitem as the fact, multi-hop dimensions to customer/nation/region on one side and supplier/part/partsupp on the other.',
    'DEMO_USER',
    'semantic-layer-team'
);

------------------------------------------------------------------------------
-- 2. Datasets
------------------------------------------------------------------------------
INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'lineitem', 'Shipped order lines (fact).', 'One row per (l_orderkey, l_linenumber).', 'tpch', 'lineitem'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'orders', 'Order headers.', 'One row per order.', 'tpch', 'orders'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'customer', 'Customers.', 'One row per customer.', 'tpch', 'customer'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'supplier', 'Suppliers.', 'One row per supplier.', 'tpch', 'supplier'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'part', 'Parts.', 'One row per part.', 'tpch', 'part'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'partsupp', 'Part-supplier catalog (bridge).', 'One row per (ps_partkey, ps_suppkey).', 'tpch', 'partsupp'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'nation', 'Nations.', 'One row per nation.', 'tpch', 'nation'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'region', 'Regions.', 'One row per region.', 'tpch', 'region'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

------------------------------------------------------------------------------
-- 3. Fields
-- Compact pattern: one multi-VALUES INSERT per dataset using a derived
-- table of (name, type_code, expression, description, label, is_dim,
-- is_time, data_type, column_name, order).
------------------------------------------------------------------------------

-- lineitem
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('l_orderkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('l_orderkey' AS VARCHAR(10000)) AS expr, CAST('FK to orders.' AS VARCHAR(10000)) AS descr, CAST('Order Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('l_orderkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_linenumber','K','l_linenumber','Line sequence inside the order.','Line Number',0,0,'INTEGER','l_linenumber',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_partkey','K','l_partkey','FK to part.','Part Key',0,0,'INTEGER','l_partkey',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_suppkey','K','l_suppkey','FK to supplier.','Supplier Key',0,0,'INTEGER','l_suppkey',4 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_quantity','A','l_quantity','Units on this line.','Quantity',0,0,'DECIMAL(15,2)','l_quantity',5 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_extendedprice','A','l_extendedprice','Extended price before discount.','Extended Price',0,0,'DECIMAL(15,2)','l_extendedprice',6 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_discount','A','l_discount','Line discount (0-0.1).','Discount',0,0,'DECIMAL(15,4)','l_discount',7 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_tax','A','l_tax','Tax rate applied to line.','Tax',0,0,'DECIMAL(15,4)','l_tax',8 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_returnflag','A','l_returnflag','Return status.','Return Flag',1,0,'CHAR(1)','l_returnflag',9 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_linestatus','A','l_linestatus','Line status.','Line Status',1,0,'CHAR(1)','l_linestatus',10 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_shipdate','A','l_shipdate','Ship date.','Ship Date',1,1,'DATE','l_shipdate',11 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_commitdate','A','l_commitdate','Commit date.','Commit Date',1,1,'DATE','l_commitdate',12 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_receiptdate','A','l_receiptdate','Receipt date.','Receipt Date',1,1,'DATE','l_receiptdate',13 FROM (SELECT 1 x) a
    UNION ALL SELECT 'l_shipmode','A','l_shipmode','Shipping mode.','Ship Mode',1,0,'VARCHAR(10)','l_shipmode',14 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='lineitem';

-- orders
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('o_orderkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('o_orderkey' AS VARCHAR(10000)) AS expr, CAST('Order surrogate key.' AS VARCHAR(10000)) AS descr, CAST('Order Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('o_orderkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_custkey','K','o_custkey','FK to customer (placed-by).','Placed-by Customer Key',0,0,'INTEGER','o_custkey',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_billing_custkey','K','o_billing_custkey','FK to customer (billed-to).','Billed-to Customer Key',0,0,'INTEGER','o_billing_custkey',9 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_orderstatus','A','o_orderstatus','Status flag.','Order Status',1,0,'CHAR(1)','o_orderstatus',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_totalprice','A','o_totalprice','Total price at order level.','Order Total',0,0,'DECIMAL(15,2)','o_totalprice',4 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_orderdate','A','o_orderdate','Order date.','Order Date',1,1,'DATE','o_orderdate',5 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_orderpriority','A','o_orderpriority','Priority band.','Order Priority',1,0,'VARCHAR(15)','o_orderpriority',6 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_clerk','A','o_clerk','Clerk that entered the order.','Clerk',1,0,'VARCHAR(15)','o_clerk',7 FROM (SELECT 1 x) a
    UNION ALL SELECT 'o_shippriority','A','o_shippriority','Shipping priority.','Ship Priority',1,0,'INTEGER','o_shippriority',8 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='orders';

-- customer
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('c_custkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('c_custkey' AS VARCHAR(10000)) AS expr, CAST('Customer key.' AS VARCHAR(10000)) AS descr, CAST('Customer Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('c_custkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'c_name','A','c_name','Customer name.','Customer',1,0,'VARCHAR(25)','c_name',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'c_nationkey','K','c_nationkey','FK to nation.','Nation Key',0,0,'INTEGER','c_nationkey',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'c_mktsegment','A','c_mktsegment','Segment bucket.','Market Segment',1,0,'VARCHAR(10)','c_mktsegment',4 FROM (SELECT 1 x) a
    UNION ALL SELECT 'c_acctbal','A','c_acctbal','Account balance.','Account Balance',0,0,'DECIMAL(15,2)','c_acctbal',5 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='customer';

-- supplier
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('s_suppkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('s_suppkey' AS VARCHAR(10000)) AS expr, CAST('Supplier key.' AS VARCHAR(10000)) AS descr, CAST('Supplier Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('s_suppkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 's_name','A','s_name','Supplier name.','Supplier',1,0,'VARCHAR(25)','s_name',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 's_nationkey','K','s_nationkey','FK to nation.','Nation Key',0,0,'INTEGER','s_nationkey',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 's_acctbal','A','s_acctbal','Supplier account balance.','Supplier Balance',0,0,'DECIMAL(15,2)','s_acctbal',4 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='supplier';

-- part
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('p_partkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('p_partkey' AS VARCHAR(10000)) AS expr, CAST('Part key.' AS VARCHAR(10000)) AS descr, CAST('Part Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('p_partkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'p_name','A','p_name','Part name.','Part',1,0,'VARCHAR(55)','p_name',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'p_mfgr','A','p_mfgr','Manufacturer.','Manufacturer',1,0,'VARCHAR(25)','p_mfgr',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'p_brand','A','p_brand','Brand.','Brand',1,0,'VARCHAR(10)','p_brand',4 FROM (SELECT 1 x) a
    UNION ALL SELECT 'p_type','A','p_type','Part type text (starts with PROMO for promotions).','Part Type',1,0,'VARCHAR(25)','p_type',5 FROM (SELECT 1 x) a
    UNION ALL SELECT 'p_retailprice','A','p_retailprice','Retail price.','Retail Price',0,0,'DECIMAL(15,2)','p_retailprice',6 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='part';

-- partsupp
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('ps_partkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('ps_partkey' AS VARCHAR(10000)) AS expr, CAST('FK to part (component of composite PK).' AS VARCHAR(10000)) AS descr, CAST('Part Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('ps_partkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'ps_suppkey','K','ps_suppkey','FK to supplier (component of composite PK).','Supplier Key',0,0,'INTEGER','ps_suppkey',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'ps_availqty','A','ps_availqty','Available quantity at supplier.','Available Qty',0,0,'INTEGER','ps_availqty',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'ps_supplycost','A','ps_supplycost','Unit supply cost.','Supply Cost',0,0,'DECIMAL(15,2)','ps_supplycost',4 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='partsupp';

-- nation
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('n_nationkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('n_nationkey' AS VARCHAR(10000)) AS expr, CAST('Nation key.' AS VARCHAR(10000)) AS descr, CAST('Nation Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('n_nationkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'n_name','A','n_name','Nation display name.','Nation',1,0,'VARCHAR(25)','n_name',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'n_regionkey','K','n_regionkey','FK to region.','Region Key',0,0,'INTEGER','n_regionkey',3 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='nation';

-- region
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id,
  (
    SELECT CAST('r_regionkey' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('r_regionkey' AS VARCHAR(10000)) AS expr, CAST('Region key.' AS VARCHAR(10000)) AS descr, CAST('Region Key' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('r_regionkey' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'r_name','A','r_name','Region display name.','Region',1,0,'VARCHAR(25)','r_name',2 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='tpch_orders' AND d.dataset_name='region';

------------------------------------------------------------------------------
-- 4. Dataset keys
------------------------------------------------------------------------------
-- Single-column PKs
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
WHERE m.model_name='tpch_orders' AND (
    (d.dataset_name='orders'   AND f.field_name='o_orderkey') OR
    (d.dataset_name='customer' AND f.field_name='c_custkey')  OR
    (d.dataset_name='supplier' AND f.field_name='s_suppkey')  OR
    (d.dataset_name='part'     AND f.field_name='p_partkey')  OR
    (d.dataset_name='nation'   AND f.field_name='n_nationkey')OR
    (d.dataset_name='region'   AND f.field_name='r_regionkey')
);

-- lineitem composite PK (l_orderkey, l_linenumber)
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_orderkey'
WHERE m.model_name='tpch_orders' AND d.dataset_name='lineitem';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 2, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_linenumber'
WHERE m.model_name='tpch_orders' AND d.dataset_name='lineitem';

-- partsupp composite PK (ps_partkey, ps_suppkey)
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_partkey'
WHERE m.model_name='tpch_orders' AND d.dataset_name='partsupp';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 2, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_suppkey'
WHERE m.model_name='tpch_orders' AND d.dataset_name='partsupp';

------------------------------------------------------------------------------
-- 5. Relationships (single-column)
-- lineitem -> orders, lineitem -> part, lineitem -> supplier
-- orders -> customer, customer -> nation, supplier -> nation, nation -> region
-- partsupp -> part, partsupp -> supplier
-- lineitem -> partsupp (composite)
------------------------------------------------------------------------------

-- Helper style: one INSERT, one column map INSERT per simple relationship
-- (code-gen could compact this; explicit is fine for a catalog build).

-- lineitem -> orders
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_orders','Lineitem belongs to order.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='lineitem' AND dt.dataset_name='orders';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_orderkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='o_orderkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='lineitem_to_orders';

-- lineitem -> part
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_part','Lineitem references a part.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='lineitem' AND dt.dataset_name='part';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_partkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='p_partkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='lineitem_to_part';

-- lineitem -> supplier
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_supplier','Lineitem references a supplier.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='lineitem' AND dt.dataset_name='supplier';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_suppkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='s_suppkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='lineitem_to_supplier';

-- orders -> customer (role-played: placed_by + billed_to)
-- Same two datasets, same key type; the ONLY disambiguator is the role.
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint, role_name)
SELECT df.dataset_id, dt.dataset_id, 'orders_placed_by_customer','Customer who placed the order.','MANY_TO_ONE','INNER','placed_by'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='orders' AND dt.dataset_name='customer';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='o_custkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='c_custkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='orders_placed_by_customer';

INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint, role_name)
SELECT df.dataset_id, dt.dataset_id, 'orders_billed_to_customer','Customer who is billed for the order.','MANY_TO_ONE','INNER','billed_to'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='orders' AND dt.dataset_name='customer';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='o_billing_custkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='c_custkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='orders_billed_to_customer';

-- customer -> nation (role-played: customer_nation vs supplier_nation)
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint, role_name)
SELECT df.dataset_id, dt.dataset_id, 'customer_to_nation','Customer belongs to nation.','MANY_TO_ONE','INNER','customer_nation'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='customer' AND dt.dataset_name='nation';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='c_nationkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='n_nationkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='customer_to_nation';

-- supplier -> nation (role-played: supplier_nation)
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint, role_name)
SELECT df.dataset_id, dt.dataset_id, 'supplier_to_nation','Supplier belongs to nation.','MANY_TO_ONE','INNER','supplier_nation'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='supplier' AND dt.dataset_name='nation';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='s_nationkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='n_nationkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='supplier_to_nation';

-- nation -> region
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'nation_to_region','Nation belongs to region.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='nation' AND dt.dataset_name='region';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='n_regionkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='r_regionkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='nation_to_region';

-- partsupp -> part
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'partsupp_to_part','Partsupp references a part.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='partsupp' AND dt.dataset_name='part';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='ps_partkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='p_partkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='partsupp_to_part';

-- partsupp -> supplier
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'partsupp_to_supplier','Partsupp references a supplier.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='partsupp' AND dt.dataset_name='supplier';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='ps_suppkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='s_suppkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='partsupp_to_supplier';

-- lineitem -> partsupp (composite: l_partkey,l_suppkey -> ps_partkey,ps_suppkey)
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_partsupp',
       'Lineitem references a (part,supplier) row in partsupp — composite join.','MANY_TO_ONE','INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND df.dataset_name='lineitem' AND dt.dataset_name='partsupp';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_partkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='ps_partkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='lineitem_to_partsupp';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 2, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_suppkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='ps_suppkey'
WHERE m.model_name='tpch_orders' AND r.relationship_name='lineitem_to_partsupp';

------------------------------------------------------------------------------
-- 6. Metrics
------------------------------------------------------------------------------

-- revenue (canonical TPC-H)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team, default_time_grain)
SELECT m.model_id, 'revenue','Canonical TPC-H revenue: SUM(l_extendedprice * (1 - l_discount)).',
       d.dataset_id,'SIMPLE',1,1,'finance-analytics','MONTH'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name IN ('l_extendedprice','l_discount')
WHERE m.model_name='tpch_orders' AND mt.metric_name='revenue';

-- promo_revenue (requires part.p_type — multi-hop through lineitem_to_part)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'promo_revenue',
       'Revenue from promotional parts (p_type starts with PROMO). Requires lineitem -> part join.',
       d.dataset_id,'SIMPLE',1,1,'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN part.p_type LIKE ''PROMO%'' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN part.p_type LIKE ''PROMO%'' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, CASE WHEN f.field_name='p_type' THEN 'FILTER' ELSE 'MEASURE' END
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_revenue'
  AND ((d.dataset_name='lineitem' AND f.field_name IN ('l_extendedprice','l_discount'))
       OR (d.dataset_name='part' AND f.field_name='p_type'));

-- count_orders
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'count_orders','Distinct count of orders.',d.dataset_id,'SIMPLE',0,1,'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','COUNT(DISTINCT orders.o_orderkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='count_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','COUNT(DISTINCT orders.o_orderkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='count_orders';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderkey'
WHERE m.model_name='tpch_orders' AND mt.metric_name='count_orders';

-- avg_qty
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'avg_qty','Average quantity per lineitem.',d.dataset_id,'SIMPLE',0,1,'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','AVG(lineitem.l_quantity)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='avg_qty';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','AVG(lineitem.l_quantity)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='avg_qty';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_quantity'
WHERE m.model_name='tpch_orders' AND mt.metric_name='avg_qty';

-- promo_share (RATIO derived) — promo_revenue / revenue
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'promo_share',
       'Share of revenue attributed to promotional parts. RATIO of promo_revenue / revenue.',
       d.dataset_id,'RATIO',0,0,'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'CAST(SUM(CASE WHEN part.p_type LIKE ''PROMO%'' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS DECIMAL(18,6)) / NULLIFZERO(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_share';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'CAST(SUM(CASE WHEN part.p_type LIKE ''PROMO%'' THEN lineitem.l_extendedprice * (1 - lineitem.l_discount) ELSE 0 END) AS DECIMAL(18,6)) / NULLIF(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)), 0)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_share';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, CASE WHEN f.field_name='p_type' THEN 'FILTER' ELSE 'MEASURE' END
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_share'
  AND ((d.dataset_name='lineitem' AND f.field_name IN ('l_extendedprice','l_discount'))
       OR (d.dataset_name='part' AND f.field_name='p_type'));

------------------------------------------------------------------------------
-- 7. Semantic view + members
------------------------------------------------------------------------------
INSERT INTO demo_user.SEMANTIC_VIEW (model_id, view_name, description, primary_dataset_id, timeseries_field, is_certified, is_public, owner_user)
SELECT m.model_id, 'order_supply_analytics',
       'Full-supply-chain order analytics: dimensions from customer/nation/region, supplier/nation/region, part/brand/type; measures for revenue family.',
       d.dataset_id, 'o_orderdate', 1, 1, 'DEMO_USER'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_orders';

-- dimensions
INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 1, 'order_date', 'TIME_DIMENSION', f.field_id, 'Order Date', 1, 1
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderdate'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 2, 'ship_date', 'TIME_DIMENSION', f.field_id, 'Ship Date', 1, 2
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_shipdate'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 3, 'customer_nation', 'DIMENSION', f.field_id, 'Customer Nation', 1, 3
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='nation'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='n_name'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 4, 'region', 'DIMENSION', f.field_id, 'Region', 1, 4
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='region'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='r_name'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 5, 'market_segment', 'DIMENSION', f.field_id, 'Market Segment', 1, 5
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='customer'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='c_mktsegment'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 6, 'brand', 'DIMENSION', f.field_id, 'Brand', 1, 6
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='part'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='p_brand'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 7, 'ship_mode', 'DIMENSION', f.field_id, 'Ship Mode', 1, 7
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_shipmode'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

-- measures
INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 10, 'revenue', 'MEASURE', mt.metric_id, 'Revenue', 1, 10
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='revenue'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 11, 'promo_revenue', 'MEASURE', mt.metric_id, 'Promo Revenue', 1, 11
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='promo_revenue'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 12, 'promo_share', 'MEASURE', mt.metric_id, 'Promo Share', 1, 12
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='promo_share'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 13, 'count_orders', 'MEASURE', mt.metric_id, 'Orders', 1, 13
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='count_orders'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 14, 'avg_qty', 'MEASURE', mt.metric_id, 'Avg Qty', 1, 14
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='avg_qty'
WHERE m.model_name='tpch_orders' AND v.view_name='order_supply_analytics';

------------------------------------------------------------------------------
-- 8. AI context and format specs
------------------------------------------------------------------------------
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, examples, display_name)
SELECT 'MODEL', m.model_id,
       'Supply-chain order analytics. Central fact: lineitem. Dimension branches: orders->customer->nation->region and supplier->nation->region and part. Use lineitem_to_partsupp for (part,supplier) composite joins.',
       NEW JSON('["order analytics","supply chain","tpch orders","honeydew"]'),
       NEW JSON('["Revenue by supplier nation","Promo share of revenue by brand","Average shipping time by ship mode"]'),
       'TPC-H Order Supply Analytics'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_orders';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'METRIC', mt.metric_id,
       'Use for any net-revenue question. Additive. Prefer this over o_totalprice aggregates because revenue respects discounts.',
       NEW JSON('["net sales","revenue","GMV","sales"]'),
       'Revenue'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='revenue';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'METRIC', mt.metric_id,
       'Revenue restricted to parts whose p_type starts with PROMO. Requires a join from lineitem to part.',
       NEW JSON('["promotional revenue","promo sales"]'),
       'Promo Revenue'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_revenue';

INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, currency_code, decimal_places, abbreviation)
SELECT 'METRIC', mt.metric_id, 'CURRENCY', 'USD', 2, 'COMPACT'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name IN ('revenue','promo_revenue');

INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, decimal_places)
SELECT 'METRIC', mt.metric_id, 'PERCENTAGE', 2
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND mt.metric_name='promo_share';

-- Custom extension: retain physical-index hint for optimizer-aware compilation
INSERT INTO demo_user.CUSTOM_EXTENSION (entity_type, entity_id, vendor_name, extension_data)
SELECT 'DATASET', d.dataset_id, 'TERADATA',
       NEW JSON('{"primary_index":["l_orderkey"],"partitioning":"RANGE_N(l_shipdate BETWEEN DATE ''1992-01-01'' AND DATE ''1998-12-31'' EACH INTERVAL ''1'' MONTH)"}')
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_orders' AND d.dataset_name='lineitem';
