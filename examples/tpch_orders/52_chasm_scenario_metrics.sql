-- =========================================================================
-- 52_chasm_scenario_metrics.sql — adds partsupp-grain metrics to tpch_orders
-- so the chasm-trap test suite has a grain-distinct measure to pair with
-- lineitem-grain ones.
--
-- Idempotent: DELETEs any prior rows before INSERT.
-- =========================================================================

DELETE FROM demo_user.METRIC_FIELD_REF
 WHERE metric_id IN (SELECT metric_id FROM demo_user.METRIC
                      WHERE metric_name IN ('total_availqty','total_supplycost'));
DELETE FROM demo_user.METRIC_EXPRESSION
 WHERE metric_id IN (SELECT metric_id FROM demo_user.METRIC
                      WHERE metric_name IN ('total_availqty','total_supplycost'));
DELETE FROM demo_user.METRIC
 WHERE metric_name IN ('total_availqty','total_supplycost')
   AND model_id = (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders');

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team, default_time_grain)
SELECT sm.model_id,
       'total_availqty',
       'SUM of available inventory quantity across all part-supplier pairs. Grain: partsupp.',
       d.dataset_id,
       'SIMPLE', 1, 1, 'supply_chain', NULL
  FROM demo_user.SEMANTIC_MODEL sm
  JOIN demo_user.DATASET d ON d.model_id = sm.model_id AND d.dataset_name='partsupp'
 WHERE sm.model_name='tpch_orders';

INSERT INTO demo_user.METRIC (model_id, metric_name, description, primary_dataset_id, metric_type, is_additive, is_certified, owner_team, default_time_grain)
SELECT sm.model_id,
       'total_supplycost',
       'SUM of per-unit supply cost across all part-supplier pairs. Grain: partsupp.',
       d.dataset_id,
       'SIMPLE', 1, 1, 'supply_chain', NULL
  FROM demo_user.SEMANTIC_MODEL sm
  JOIN demo_user.DATASET d ON d.model_id = sm.model_id AND d.dataset_name='partsupp'
 WHERE sm.model_name='tpch_orders';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT m.metric_id, 'TERADATA', 'SUM(partsupp.ps_availqty)'
  FROM demo_user.METRIC m JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_availqty';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT m.metric_id, 'ANSI_SQL', 'SUM(partsupp.ps_availqty)'
  FROM demo_user.METRIC m JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_availqty';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT m.metric_id, 'TERADATA', 'SUM(partsupp.ps_supplycost)'
  FROM demo_user.METRIC m JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_supplycost';

INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
SELECT m.metric_id, 'ANSI_SQL', 'SUM(partsupp.ps_supplycost)'
  FROM demo_user.METRIC m JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_supplycost';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT m.metric_id, f.field_id, 'MEASURE'
  FROM demo_user.METRIC m
  JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
  JOIN demo_user.DATASET d ON d.model_id=sm.model_id AND d.dataset_name='partsupp'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_availqty'
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_availqty';

INSERT INTO demo_user.METRIC_FIELD_REF (metric_id, field_id, dep_role)
SELECT m.metric_id, f.field_id, 'MEASURE'
  FROM demo_user.METRIC m
  JOIN demo_user.SEMANTIC_MODEL sm ON sm.model_id=m.model_id
  JOIN demo_user.DATASET d ON d.model_id=sm.model_id AND d.dataset_name='partsupp'
  JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id AND f.field_name='ps_supplycost'
 WHERE sm.model_name='tpch_orders' AND m.metric_name='total_supplycost';
