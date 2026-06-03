-- Teardown for tpch_orders and tpch_supply_risk examples.
-- Deletes are leaf-to-root. Tolerant: missing tables / rows are silently ignored.
-- Run via: semantic-catalog uninstall-example tpch_orders

-- ── tpch_supply_risk (cube model, no relationships) ──────────────────────────

DELETE FROM demo_user.METRIC_FIELD_REF
 WHERE metric_id IN (SELECT mt.metric_id FROM demo_user.METRIC mt
                     JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name = 'tpch_supply_risk');

DELETE FROM demo_user.METRIC_EXPRESSION
 WHERE metric_id IN (SELECT mt.metric_id FROM demo_user.METRIC mt
                     JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name = 'tpch_supply_risk');

DELETE FROM demo_user.AI_CONTEXT
 WHERE (entity_type='DATASET' AND entity_id IN (
            SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
            JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
            WHERE m.model_name='tpch_supply_risk'))
    OR (entity_type='METRIC' AND entity_id IN (
            SELECT mt.metric_id FROM demo_user.METRIC mt
            JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
            WHERE m.model_name='tpch_supply_risk'))
    OR (entity_type='MODEL' AND entity_id IN (
            SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_supply_risk'));

DELETE FROM demo_user.METRIC
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_supply_risk');

DELETE FROM demo_user.FIELD
 WHERE dataset_id IN (
    SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
    JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
    WHERE m.model_name='tpch_supply_risk');

DELETE FROM demo_user.MODEL_DATASET
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_supply_risk');

DELETE FROM demo_user.DATASET WHERE dataset_name='supplier_risk_cube';

DELETE FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_supply_risk';

-- ── tpch_orders (normalized model) ───────────────────────────────────────────

DELETE FROM demo_user.METRIC_FIELD_REF
 WHERE metric_id IN (SELECT mt.metric_id FROM demo_user.METRIC mt
                     JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.METRIC_EXPRESSION
 WHERE metric_id IN (SELECT mt.metric_id FROM demo_user.METRIC mt
                     JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.FORMAT_SPEC
 WHERE (entity_type='METRIC' AND entity_id IN (
            SELECT mt.metric_id FROM demo_user.METRIC mt
            JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
            WHERE m.model_name='tpch_orders'))
    OR (entity_type='MODEL' AND entity_id IN (
            SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders'));

DELETE FROM demo_user.REL_COLUMN_MAP
 WHERE relationship_id IN (
    SELECT r.relationship_id FROM demo_user.RELATIONSHIP r
    JOIN demo_user.MODEL_DATASET md ON md.dataset_id=r.from_dataset_id
    JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
    WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.RELATIONSHIP
 WHERE from_dataset_id IN (
    SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
    JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
    WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.DATASET_KEY
 WHERE dataset_id IN (
    SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
    JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
    WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.FIELD
 WHERE dataset_id IN (
    SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
    JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
    WHERE m.model_name='tpch_orders');

DELETE FROM demo_user.AI_CONTEXT
 WHERE (entity_type='DATASET' AND entity_id IN (
            SELECT md.dataset_id FROM demo_user.MODEL_DATASET md
            JOIN demo_user.SEMANTIC_MODEL m ON md.model_id=m.model_id
            WHERE m.model_name='tpch_orders'))
    OR (entity_type='METRIC' AND entity_id IN (
            SELECT mt.metric_id FROM demo_user.METRIC mt
            JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
            WHERE m.model_name='tpch_orders'))
    OR (entity_type='MODEL' AND entity_id IN (
            SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders'));

DELETE FROM demo_user.SECURITY_POLICY
 WHERE entity_type='MODEL' AND entity_id IN (
    SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders');

DELETE FROM demo_user.METRIC
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders');

DELETE FROM demo_user.MODEL_DATASET
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders');

DELETE FROM demo_user.DATASET
 WHERE dataset_name IN ('lineitem','partsupp','orders','customer','supplier','part','nation','region');

DELETE FROM demo_user.SEMANTIC_MODEL WHERE model_name='tpch_orders';

-- ── Physical sample tables (tolerant — may not exist on first install) ────────
DROP TABLE lineitem;
DROP TABLE partsupp;
DROP TABLE orders;
DROP TABLE customer;
DROP TABLE supplier;
DROP TABLE part;
DROP TABLE nation;
DROP TABLE region;
