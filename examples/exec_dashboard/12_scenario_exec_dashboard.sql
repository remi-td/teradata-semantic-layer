-- =========================================================================
-- Scenario C — Executive Sales Dashboard cube.
-- Model name: exec_dashboard
-- Demonstrates Level-0 maturity: a single dataset (sales_cube) whose
-- source is a full pre-canned SQL query. No relationships exist — the
-- cube is self-contained. Metrics aggregate over the cube's own fields.
-- =========================================================================

------------------------------------------------------------------------------
-- 1. Model
------------------------------------------------------------------------------
INSERT INTO demo_user.SEMANTIC_MODEL (model_name, description, owner_user, owner_group)
VALUES (
    'exec_dashboard',
    'Executive weekly sales dashboard. Single pre-canned cube — no decomposed relational model. Designed to work immediately: point BI / agent at sales_cube and everything aggregates correctly without any join configuration.',
    'DEMO_USER',
    'exec-analytics'
);

------------------------------------------------------------------------------
-- 2. Single dataset defined by a source query
-- The source_query holds a realistic pre-canned SQL: multi-join fact query
-- with soft-delete exclusions, CASE-derived buckets, and a date filter.
------------------------------------------------------------------------------
INSERT INTO demo_user.DATASET (
    dataset_name, description, granularity_desc,
    DataBaseName, TableName, source_query
)
SELECT
    'sales_cube',
    'Pre-canned executive sales cube. Flat result-set with order-level grain, enriched with customer, region, and product dimensions and revenue / units measures. Inline source_query is the single source of truth for this model.',
    'One row per (order_id, product_id).',
    NULL, NULL,
    '-- Pre-canned executive sales cube (source_query for sales_cube).
-- This runs inside Teradata; any agent / BI consumer sees a flat
-- dimensional result-set: (order_id, product_id, order_date,
-- order_week, order_year, region, country, sales_channel,
-- customer_segment, product_category, product_brand, is_new_customer,
-- gross_revenue, net_revenue, units_sold, is_returned).

SELECT
    o.order_id,
    ol.product_id,
    o.order_date,
    TRUNC(o.order_date, ''IW'')           AS order_week,
    EXTRACT(YEAR FROM o.order_date)       AS order_year,
    r.region_name                         AS region,
    r.country_name                        AS country,
    o.sales_channel,
    CASE
        WHEN c.lifetime_spend >= 100000 THEN ''Enterprise''
        WHEN c.lifetime_spend >= 10000  THEN ''SMB''
        ELSE ''Consumer''
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
WHERE o.order_status IN (''SHIPPED'',''DELIVERED'')
  AND o.deleted_flag = 0
  AND o.order_date >= ADD_MONTHS(CURRENT_DATE, -36)'
FROM demo_user.SEMANTIC_MODEL m
WHERE m.model_name='exec_dashboard';

-- Link sales_cube to the exec_dashboard model
INSERT INTO demo_user.MODEL_DATASET (model_id, dataset_id, is_primary)
SELECT m.model_id, d.dataset_id, 1
FROM demo_user.SEMANTIC_MODEL m, demo_user.DATASET d
WHERE m.model_name='exec_dashboard' AND d.dataset_name='sales_cube';

------------------------------------------------------------------------------
-- 3. Fields — dimensions and raw measures on the cube
------------------------------------------------------------------------------

INSERT INTO demo_user.FIELD (dataset_id, field_name, field_type_code, expression, description, label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
SELECT d.dataset_id, x.field_name, x.fc, x.expr, x.descr, x.lbl, x.isd, x.ist, x.dt, x.col, x.ord
FROM demo_user.DATASET d INNER JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id INNER JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id,
  (
    SELECT CAST('order_id' AS VARCHAR(200)) AS field_name, CAST('K' AS CHAR(1)) AS fc, CAST('order_id' AS VARCHAR(10000)) AS expr, CAST('Order identifier (component of composite grain key).' AS VARCHAR(10000)) AS descr, CAST('Order' AS VARCHAR(500)) AS lbl, CAST(0 AS BYTEINT) AS isd, CAST(0 AS BYTEINT) AS ist, CAST('INTEGER' AS VARCHAR(200)) AS dt, CAST('order_id' AS VARCHAR(128)) AS col, CAST(1 AS SMALLINT) AS ord FROM (SELECT 1 x) a
    UNION ALL SELECT 'product_id','K','product_id','Product identifier (component of composite grain key).','Product',0,0,'INTEGER','product_id',2 FROM (SELECT 1 x) a
    UNION ALL SELECT 'order_date','A','order_date','Order date.','Order Date',1,1,'DATE','order_date',3 FROM (SELECT 1 x) a
    UNION ALL SELECT 'order_week','A','order_week','ISO week starting date.','Order Week',1,1,'DATE','order_week',4 FROM (SELECT 1 x) a
    UNION ALL SELECT 'order_year','A','order_year','Calendar year.','Year',1,1,'INTEGER','order_year',5 FROM (SELECT 1 x) a
    UNION ALL SELECT 'region','A','region','Customer region rollup.','Region',1,0,'VARCHAR(50)','region',6 FROM (SELECT 1 x) a
    UNION ALL SELECT 'country','A','country','Customer country.','Country',1,0,'VARCHAR(50)','country',7 FROM (SELECT 1 x) a
    UNION ALL SELECT 'sales_channel','A','sales_channel','Channel through which the order was placed.','Sales Channel',1,0,'VARCHAR(20)','sales_channel',8 FROM (SELECT 1 x) a
    UNION ALL SELECT 'customer_segment','A','customer_segment','Enterprise/SMB/Consumer bucket (derived).','Customer Segment',1,0,'VARCHAR(20)','customer_segment',9 FROM (SELECT 1 x) a
    UNION ALL SELECT 'product_category','A','product_category','Product category name.','Category',1,0,'VARCHAR(50)','product_category',10 FROM (SELECT 1 x) a
    UNION ALL SELECT 'product_brand','A','product_brand','Brand name.','Brand',1,0,'VARCHAR(50)','product_brand',11 FROM (SELECT 1 x) a
    UNION ALL SELECT 'is_new_customer','A','is_new_customer','1 = acquired in the last 12 months.','New Customer Flag',1,0,'BYTEINT','is_new_customer',12 FROM (SELECT 1 x) a
    UNION ALL SELECT 'gross_revenue','A','gross_revenue','Extended price (before discount).','Gross Revenue',0,0,'DECIMAL(18,2)','gross_revenue',13 FROM (SELECT 1 x) a
    UNION ALL SELECT 'net_revenue','A','net_revenue','Extended price after discount.','Net Revenue',0,0,'DECIMAL(18,2)','net_revenue',14 FROM (SELECT 1 x) a
    UNION ALL SELECT 'units_sold','A','units_sold','Units on the line.','Units',0,0,'INTEGER','units_sold',15 FROM (SELECT 1 x) a
    UNION ALL SELECT 'is_returned','A','is_returned','1 if the line was returned.','Returned Flag',1,0,'BYTEINT','is_returned',16 FROM (SELECT 1 x) a
  ) x
WHERE m.model_name='exec_dashboard' AND d.dataset_name='sales_cube';

-- Composite grain key
INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 1, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id INNER JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='order_id'
WHERE m.model_name='exec_dashboard' AND d.dataset_name='sales_cube';

INSERT INTO demo_user.DATASET_KEY (dataset_id, key_type, key_ordinal, column_position, field_id)
SELECT d.dataset_id, 'PK', 0, 2, f.field_id
FROM demo_user.DATASET d INNER JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id INNER JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='product_id'
WHERE m.model_name='exec_dashboard' AND d.dataset_name='sales_cube';

------------------------------------------------------------------------------
-- 4. Metrics (over the cube's raw measure fields)
------------------------------------------------------------------------------

-- total_net_revenue
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team, default_time_grain)
SELECT m.model_id, 'total_net_revenue','Net revenue (post-discount) across all selected slices.',
       d.dataset_id,'SIMPLE',1,1,'exec-analytics','WEEK'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','SUM(sales_cube.net_revenue)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_net_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','SUM(sales_cube.net_revenue)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_net_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='net_revenue'
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_net_revenue';

-- total_units
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'total_units','Total units sold.',d.dataset_id,'SIMPLE',1,1,'exec-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','SUM(sales_cube.units_sold)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_units';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','SUM(sales_cube.units_sold)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_units';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='units_sold'
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_units';

-- unique_orders (non-additive)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'unique_orders','Distinct count of orders in the slice.',d.dataset_id,'SIMPLE',0,1,'exec-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','COUNT(DISTINCT sales_cube.order_id)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='unique_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','COUNT(DISTINCT sales_cube.order_id)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='unique_orders';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='order_id'
WHERE m.model_name='exec_dashboard' AND mt.metric_name='unique_orders';

-- return_rate (RATIO)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'return_rate','Share of lines that were returned (RATIO).',d.dataset_id,'RATIO',0,1,'exec-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA','CAST(SUM(sales_cube.is_returned) AS DECIMAL(18,6)) / NULLIFZERO(COUNT(*))'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='return_rate';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL','CAST(SUM(sales_cube.is_returned) AS DECIMAL(18,6)) / NULLIF(COUNT(*), 0)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='return_rate';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, 'MEASURE'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='is_returned'
WHERE m.model_name='exec_dashboard' AND mt.metric_name='return_rate';

-- new_customer_revenue (filter-based)
INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team)
SELECT m.model_id, 'new_customer_revenue','Net revenue from customers acquired in the last 12 months.',
       d.dataset_id,'SIMPLE',1,0,'exec-analytics'
FROM demo_user.SEMANTIC_MODEL m INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'TERADATA',
       'SUM(CASE WHEN sales_cube.is_new_customer = 1 THEN sales_cube.net_revenue ELSE 0 END)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='new_customer_revenue';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT mt.metric_id, 'ANSI_SQL',
       'SUM(CASE WHEN sales_cube.is_new_customer = 1 THEN sales_cube.net_revenue ELSE 0 END)'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='new_customer_revenue';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT mt.metric_id, f.field_id, CASE WHEN f.field_name='is_new_customer' THEN 'FILTER' ELSE 'MEASURE' END
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
INNER JOIN demo_user.MODEL_DATASET md2 ON md2.model_id=m.model_id INNER JOIN demo_user.DATASET d ON d.dataset_id=md2.dataset_id AND d.dataset_name='sales_cube'
INNER JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name IN ('is_new_customer','net_revenue')
WHERE m.model_name='exec_dashboard' AND mt.metric_name='new_customer_revenue';


------------------------------------------------------------------------------
-- 6. AI context and format specs (heavy business guidance — cubes rely on
-- human context because they lack rich relational structure).
------------------------------------------------------------------------------
INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, examples, display_name)
SELECT 'MODEL', m.model_id,
       'Pre-canned executive cube. ALWAYS query sales_cube directly — do not attempt to decompose into customers/orders tables; the cube already applies soft-delete, status filters, and segment bucketing. All revenue numbers are already net of the standard three-year lookback. When the user asks for YTD, filter order_date >= first-of-year; do not attempt to re-derive from underlying tables.',
       NEW JSON('["exec dashboard","weekly sales scorecard","board pack"]'),
       NEW JSON('["Net revenue by region and segment last 4 weeks","Return rate by category","New-customer revenue trend"]'),
       'Executive Sales Dashboard'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'DATASET', d.dataset_id,
       'Flat fact cube. One row per (order_id, product_id). Already excludes cancelled, deleted, and non-shipped orders. Has a 36-month rolling window built in.',
       NEW JSON('["sales cube","weekly cube","exec cube"]'),
       'Sales Cube'
FROM demo_user.DATASET d INNER JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id INNER JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND d.dataset_name='sales_cube';

INSERT INTO demo_user.AI_CONTEXT (entity_type, entity_id, instructions, synonyms, display_name)
SELECT 'METRIC', mt.metric_id,
       'Net revenue after discount. Additive across any cube dimension. Cube applies status/soft-delete filters so this equals the board-pack figure.',
       NEW JSON('["net revenue","sales","revenue"]'),
       'Net Revenue'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='total_net_revenue';

-- Format specs
INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, currency_code, decimal_places, abbreviation)
SELECT 'METRIC', mt.metric_id, 'CURRENCY', 'USD', 2, 'COMPACT'
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name IN ('total_net_revenue','new_customer_revenue');

INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, decimal_places)
SELECT 'METRIC', mt.metric_id, 'PERCENTAGE', 2
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name='return_rate';

INSERT INTO demo_user.FORMAT_SPEC (entity_type, entity_id, format_type, decimal_places)
SELECT 'METRIC', mt.metric_id, 'NUMBER', 0
FROM demo_user.METRIC mt INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
WHERE m.model_name='exec_dashboard' AND mt.metric_name IN ('total_units','unique_orders');

-- Row-level security example: exec-only view
INSERT INTO demo_user.SECURITY_POLICY (entity_type, entity_id, policy_ordinal, policy_type, group_name, policy_expression)
SELECT 'MODEL', m.model_id, 1, 'ROW_FILTER', 'EXEC_LEADERSHIP',
       '1=1 -- exec leadership sees all slices'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='exec_dashboard';

INSERT INTO demo_user.SECURITY_POLICY (entity_type, entity_id, policy_ordinal, policy_type, group_name, policy_expression)
SELECT 'MODEL', m.model_id, 2, 'ROW_FILTER', 'REGIONAL_SALES_MANAGERS',
       'region = (SELECT assigned_region FROM hr.role_assignments WHERE user_name = USER)'
FROM demo_user.SEMANTIC_MODEL m WHERE m.model_name='exec_dashboard';
