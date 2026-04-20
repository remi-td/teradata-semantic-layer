-- =========================================================================
-- Scenario A — TPC-H OSI-style (entity-first, fully decomposed).
-- Model name: tpch_osi
-- Physical tables are referenced via DataBaseName='tpch' / TableName=... .
-- Those tables do not need to exist on the sandbox — the catalog is
-- metadata-only, and the references are validated lazily at compile time.
-- =========================================================================

------------------------------------------------------------------------------
-- 1. Semantic model
------------------------------------------------------------------------------
INSERT INTO demo_user.SEMANTIC_MODEL (model_name, description, owner_user, owner_group)
VALUES (
    'tpch_osi',
    'TPC-H retail / order analytics semantic model, OSI-style entity-first decomposition. Covers customers, orders, lineitems, parts, and nation/region geography.',
    'DEMO_USER',
    'semantic-layer-team'
);

------------------------------------------------------------------------------
-- 2. Datasets
------------------------------------------------------------------------------
INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'customer', 'Customer master. One row per customer.', 'One row per customer.', 'tpch', 'customer'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'orders', 'Order header. One row per customer order.', 'One row per order.', 'tpch', 'orders'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'lineitem', 'Order line items. Fact grain: one row per (order, line number).', 'One row per (l_orderkey, l_linenumber).', 'tpch', 'lineitem'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'part', 'Part catalog. One row per part.', 'One row per part.', 'tpch', 'part'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'nation', 'Nations. One row per nation.', 'One row per nation.', 'tpch', 'nation'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

INSERT INTO demo_user.DATASET (model_id, dataset_name, description, granularity_desc, DataBaseName, TableName)
SELECT m.model_id, 'region', 'Regions. One row per region.', 'One row per region.', 'tpch', 'region'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name = 'tpch_osi';

------------------------------------------------------------------------------
-- 3. Fields
-- Helper macro-less pattern: each INSERT joins back to the owning dataset
-- by natural key.
------------------------------------------------------------------------------

-- customer
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'c_custkey', 'K', 'c_custkey', 'Customer surrogate key.', 'Customer Key', 0, 0, 'INTEGER', 'c_custkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'c_name', 'A', 'c_name', 'Customer display name.', 'Customer Name', 1, 0, 'VARCHAR(25)', 'c_name', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'c_nationkey', 'K', 'c_nationkey', 'FK to nation.', 'Customer Nation Key', 0, 0, 'INTEGER', 'c_nationkey', 3
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'c_mktsegment', 'A', 'c_mktsegment', 'Market segment the customer belongs to.', 'Market Segment', 1, 0, 'VARCHAR(10)', 'c_mktsegment', 4
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'c_acctbal', 'A', 'c_acctbal', 'Customer account balance (USD).', 'Account Balance', 0, 0, 'DECIMAL(15,2)', 'c_acctbal', 5
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

-- orders
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_orderkey', 'K', 'o_orderkey', 'Order surrogate key.', 'Order Key', 0, 0, 'INTEGER', 'o_orderkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_custkey', 'K', 'o_custkey', 'FK to customer.', 'Order Customer Key', 0, 0, 'INTEGER', 'o_custkey', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_orderdate', 'A', 'o_orderdate', 'Date the order was placed.', 'Order Date', 1, 1, 'DATE', 'o_orderdate', 3
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_orderyear', 'A', 'EXTRACT(YEAR FROM o_orderdate)', 'Calendar year of the order date (computed).', 'Order Year', 1, 1, 'INTEGER', NULL, 4
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_totalprice', 'A', 'o_totalprice', 'Total order price (USD).', 'Order Total', 0, 0, 'DECIMAL(15,2)', 'o_totalprice', 5
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_orderstatus', 'A', 'o_orderstatus', 'Order status: O=open, F=fulfilled, P=partial.', 'Order Status', 1, 0, 'CHAR(1)', 'o_orderstatus', 6
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'o_orderpriority', 'A', 'o_orderpriority', 'Priority bucket for order fulfillment.', 'Order Priority', 1, 0, 'VARCHAR(15)', 'o_orderpriority', 7
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

-- lineitem
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_orderkey', 'K', 'l_orderkey', 'FK to orders.', 'Order Key', 0, 0, 'INTEGER', 'l_orderkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_linenumber', 'K', 'l_linenumber', 'Line sequence within an order.', 'Line Number', 0, 0, 'INTEGER', 'l_linenumber', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_partkey', 'K', 'l_partkey', 'FK to part.', 'Part Key', 0, 0, 'INTEGER', 'l_partkey', 3
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_quantity', 'A', 'l_quantity', 'Quantity ordered for this line.', 'Quantity', 0, 0, 'DECIMAL(15,2)', 'l_quantity', 4
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_extendedprice', 'A', 'l_extendedprice', 'Extended price for the line (before discount/tax).', 'Extended Price', 0, 0, 'DECIMAL(15,2)', 'l_extendedprice', 5
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_discount', 'A', 'l_discount', 'Line discount fraction (0.0 - 0.10).', 'Discount', 0, 0, 'DECIMAL(15,4)', 'l_discount', 6
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_tax', 'A', 'l_tax', 'Line tax rate.', 'Tax', 0, 0, 'DECIMAL(15,4)', 'l_tax', 7
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_returnflag', 'A', 'l_returnflag', 'Return status: R=returned, A=accepted, N=none.', 'Return Flag', 1, 0, 'CHAR(1)', 'l_returnflag', 8
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'l_shipdate', 'A', 'l_shipdate', 'Date this line shipped.', 'Ship Date', 1, 1, 'DATE', 'l_shipdate', 9
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

-- part
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_partkey', 'K', 'p_partkey', 'Part surrogate key.', 'Part Key', 0, 0, 'INTEGER', 'p_partkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_name', 'A', 'p_name', 'Part display name.', 'Part Name', 1, 0, 'VARCHAR(55)', 'p_name', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_mfgr', 'A', 'p_mfgr', 'Manufacturer.', 'Manufacturer', 1, 0, 'VARCHAR(25)', 'p_mfgr', 3
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_brand', 'A', 'p_brand', 'Brand label.', 'Brand', 1, 0, 'VARCHAR(10)', 'p_brand', 4
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_type', 'A', 'p_type', 'Part type text.', 'Part Type', 1, 0, 'VARCHAR(25)', 'p_type', 5
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'p_retailprice', 'A', 'p_retailprice', 'Retail price of the part.', 'Retail Price', 0, 0, 'DECIMAL(15,2)', 'p_retailprice', 6
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

-- nation
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'n_nationkey', 'K', 'n_nationkey', 'Nation surrogate key.', 'Nation Key', 0, 0, 'INTEGER', 'n_nationkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='nation';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'n_name', 'A', 'n_name', 'Nation display name.', 'Nation', 1, 0, 'VARCHAR(25)', 'n_name', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='nation';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'n_regionkey', 'K', 'n_regionkey', 'FK to region.', 'Region Key', 0, 0, 'INTEGER', 'n_regionkey', 3
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='nation';

-- region
INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'r_regionkey', 'K', 'r_regionkey', 'Region surrogate key.', 'Region Key', 0, 0, 'INTEGER', 'r_regionkey', 1
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='region';

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, 'r_name', 'A', 'r_name', 'Region display name (AMERICA, EUROPE, ...).', 'Region', 1, 0, 'VARCHAR(25)', 'r_name', 2
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='region';

------------------------------------------------------------------------------
-- 4. Dataset keys (primary)
------------------------------------------------------------------------------
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='c_custkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='orders';

-- lineitem PK is composite (l_orderkey, l_linenumber)
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_orderkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 2, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_linenumber'
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='p_partkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='part';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='n_nationkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='nation';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='r_regionkey'
WHERE m.model_name='tpch_osi' AND d.dataset_name='region';

------------------------------------------------------------------------------
-- 5. Relationships + column maps
------------------------------------------------------------------------------

-- orders → customer
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'orders_to_customer',
       'Every order belongs to exactly one customer.', 'MANY_TO_ONE', 'INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND df.dataset_name='orders' AND dt.dataset_name='customer';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='o_custkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='c_custkey'
WHERE m.model_name='tpch_osi' AND r.relationship_name='orders_to_customer';

-- lineitem → orders
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_orders',
       'Every lineitem belongs to exactly one order.', 'MANY_TO_ONE', 'INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND df.dataset_name='lineitem' AND dt.dataset_name='orders';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_orderkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='o_orderkey'
WHERE m.model_name='tpch_osi' AND r.relationship_name='lineitem_to_orders';

-- lineitem → part
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'lineitem_to_part',
       'Each lineitem references one part.', 'MANY_TO_ONE', 'INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND df.dataset_name='lineitem' AND dt.dataset_name='part';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='l_partkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='p_partkey'
WHERE m.model_name='tpch_osi' AND r.relationship_name='lineitem_to_part';

-- customer → nation
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'customer_to_nation',
       'Each customer belongs to one nation.', 'MANY_TO_ONE', 'INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND df.dataset_name='customer' AND dt.dataset_name='nation';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='c_nationkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='n_nationkey'
WHERE m.model_name='tpch_osi' AND r.relationship_name='customer_to_nation';

-- nation → region
INSERT INTO demo_user.RELATIONSHIP (from_dataset_id, to_dataset_id, relationship_name, description, cardinality, join_type_hint)
SELECT df.dataset_id, dt.dataset_id, 'nation_to_region',
       'Each nation belongs to one region.', 'MANY_TO_ONE', 'INNER'
FROM demo_user.DATASET df INNER JOIN demo_user.DATASET dt ON df.model_id=dt.model_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND df.dataset_name='nation' AND dt.dataset_name='region';

INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
SELECT r.relationship_id, 1, ff.field_id, tf.field_id
FROM demo_user.RELATIONSHIP r
INNER JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
INNER JOIN demo_user.DATASET dt ON r.to_dataset_id=dt.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON df.model_id=m.model_id
INNER JOIN demo_user.FIELD ff ON ff.dataset_id=df.dataset_id AND ff.field_name='n_regionkey'
INNER JOIN demo_user.FIELD tf ON tf.dataset_id=dt.dataset_id AND tf.field_name='r_regionkey'
WHERE m.model_name='tpch_osi' AND r.relationship_name='nation_to_region';

------------------------------------------------------------------------------
-- 6. Metrics
------------------------------------------------------------------------------

-- total_revenue — classic TPC-H Q1: SUM(l_extendedprice * (1 - l_discount))
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team, default_time_grain)
SELECT m.model_id, 'total_revenue',
       'Net revenue from shipped line items. Defined as SUM(l_extendedprice * (1 - l_discount)).',
       d.dataset_id, 'SIMPLE', 1, 1, 'finance-analytics', 'MONTH'
FROM demo_user.SEMANTIC_MODEL m
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='total_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='total_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_extendedprice'
WHERE m.model_name='tpch_osi' AND mt.metric_name='total_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_discount'
WHERE m.model_name='tpch_osi' AND mt.metric_name='total_revenue';

-- order_count
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'order_count',
       'Distinct count of orders.', d.dataset_id, 'SIMPLE', 0, 1, 'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(DISTINCT orders.o_orderkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='order_count';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(DISTINCT orders.o_orderkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='order_count';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderkey'
WHERE m.model_name='tpch_osi' AND mt.metric_name='order_count';

-- customer_count
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'customer_count',
       'Distinct count of customers.', d.dataset_id, 'SIMPLE', 0, 1, 'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='customer'
WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA', 'COUNT(DISTINCT customer.c_custkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_count';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL', 'COUNT(DISTINCT customer.c_custkey)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_count';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='customer'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='c_custkey'
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_count';

-- avg_order_value (RATIO, cross-dataset) — revenue / order_count
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'avg_order_value',
       'Average revenue per order. Cross-dataset ratio of total_revenue over order_count.',
       NULL, 'RATIO', 0, 0, 'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m
WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'CAST(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS DECIMAL(18,4)) / NULLIFZERO(COUNT(DISTINCT orders.o_orderkey))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'CAST(SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS DECIMAL(18,4)) / NULLIF(COUNT(DISTINCT orders.o_orderkey), 0)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_extendedprice'
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_discount'
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderkey'
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

-- customer_lifetime_value (cross-dataset) — SUM over lineitem grouped conceptually by customer
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'customer_lifetime_value',
       'Lifetime net revenue generated per customer (cross-dataset: lineitem -> orders -> customer).',
       NULL, 'SIMPLE', 1, 0, 'finance-analytics'
FROM demo_user.SEMANTIC_MODEL m
WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_lifetime_value';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_lifetime_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_extendedprice'
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_lifetime_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='l_discount'
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_lifetime_value';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'GROUP_BY'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='customer'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='c_custkey'
WHERE m.model_name='tpch_osi' AND mt.metric_name='customer_lifetime_value';

------------------------------------------------------------------------------
-- 7. Semantic view + members
------------------------------------------------------------------------------
INSERT INTO demo_user.SEMANTIC_VIEW (model_id, view_name, description, primary_dataset_id, timeseries_field, is_certified, is_public, owner_user)
SELECT m.model_id, 'tpch_order_analytics',
       'Curated view for order and revenue analytics — exposes the headline dimensions and certified metrics.',
       d.dataset_id, 'o_orderdate', 1, 1, 'DEMO_USER'
FROM demo_user.SEMANTIC_MODEL m
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='lineitem'
WHERE m.model_name='tpch_osi';

-- Dimension members
INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 1, 'order_date', 'TIME_DIMENSION', f.field_id, 'Order Date', 1, 1
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderdate'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 2, 'order_year', 'TIME_DIMENSION', f.field_id, 'Order Year', 1, 2
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderyear'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 3, 'market_segment', 'DIMENSION', f.field_id, 'Market Segment', 1, 3
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='customer'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='c_mktsegment'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 4, 'nation', 'DIMENSION', f.field_id, 'Nation', 1, 4
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='nation'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='n_name'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 5, 'region', 'DIMENSION', f.field_id, 'Region', 1, 5
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='region'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='r_name'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 6, 'order_status', 'DIMENSION', f.field_id, 'Order Status', 1, 6
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='orders'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='o_orderstatus'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, field_id, display_name, is_public, member_order)
SELECT v.view_id, 7, 'part_brand', 'DIMENSION', f.field_id, 'Brand', 1, 7
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.DATASET d ON d.model_id=m.model_id AND d.dataset_name='part'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='p_brand'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

-- Measure members
INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 10, 'total_revenue', 'MEASURE', mt.metric_id, 'Total Revenue', 1, 10
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='total_revenue'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 11, 'order_count', 'MEASURE', mt.metric_id, 'Orders', 1, 11
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='order_count'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 12, 'customer_count', 'MEASURE', mt.metric_id, 'Customers', 1, 12
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='customer_count'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

INSERT INTO demo_user.VIEW_MEMBER (view_id, member_ordinal, member_name, member_type, metric_id, display_name, is_public, member_order)
SELECT v.view_id, 13, 'avg_order_value', 'MEASURE', mt.metric_id, 'Avg Order Value', 1, 13
FROM demo_user.SEMANTIC_VIEW v INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
INNER JOIN demo_user.METRIC mt ON mt.model_id=m.model_id AND mt.metric_name='avg_order_value'
WHERE m.model_name='tpch_osi' AND v.view_name='tpch_order_analytics';

------------------------------------------------------------------------------
-- 8. AI context on model / key datasets / key metrics
------------------------------------------------------------------------------
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, examples, display_name)
SELECT 'MODEL', m.model_id,
       'TPC-H retail and order analytics. Anchor fact is lineitem; decomposed to orders, customer, nation, region, and part. Revenue metric follows TPC-H canonical definition.',
       NEW JSON('["order analytics","retail","tpch"]'),
       NEW JSON('["What was total revenue by nation last year?","Top 10 brands by revenue","Average order value by market segment"]'),
       'TPC-H Order Analytics'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='tpch_osi';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'DATASET', d.dataset_id,
       'Fact table grain: one row per line in an order. All revenue and quantity facts live here.',
       NEW JSON('["line items","shipments","order lines"]'),
       'Line Items'
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='lineitem';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'DATASET', d.dataset_id,
       'Customer master. Join to orders on o_custkey = c_custkey. Join to nation on c_nationkey.',
       NEW JSON('["account","buyer","client"]'),
       'Customer'
FROM demo_user.DATASET d INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND d.dataset_name='customer';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, examples, display_name)
SELECT 'METRIC', mt.metric_id,
       'Use this for all headline revenue reporting — it discounts extended price by line discount. Additive: can be summed across any dimension slice.',
       NEW JSON('["revenue","net sales","sales","GMV"]'),
       NEW JSON('["Total revenue by region","Monthly revenue trend"]'),
       'Total Revenue'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='total_revenue';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'METRIC', mt.metric_id,
       'Average net revenue per distinct order. Non-additive (do not sum).',
       NEW JSON('["AOV","average basket size","ticket size"]'),
       'Average Order Value'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name='avg_order_value';

------------------------------------------------------------------------------
-- 9. Format specs on currency metrics
------------------------------------------------------------------------------
INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, currency_code, decimal_places, abbreviation)
SELECT 'METRIC', mt.metric_id, 'CURRENCY', 'USD', 2, 'COMPACT'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='tpch_osi' AND mt.metric_name IN ('total_revenue','avg_order_value','customer_lifetime_value');

INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, currency_code, decimal_places)
SELECT 'FIELD', f.field_id, 'CURRENCY', 'USD', 2
FROM demo_user.FIELD f INNER JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
WHERE m.model_name='tpch_osi'
  AND ((d.dataset_name='lineitem' AND f.field_name='l_extendedprice')
       OR (d.dataset_name='orders'   AND f.field_name='o_totalprice')
       OR (d.dataset_name='customer' AND f.field_name='c_acctbal')
       OR (d.dataset_name='part'     AND f.field_name='p_retailprice'));
